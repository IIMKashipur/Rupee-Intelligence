# =============================================================================
# 07_scenario.R  -  Sessions 17-18: prescriptive analytics / what-if
# Uses the fitted Model C to estimate the rupee's response to hypothetical
# shocks, then turns it into a decision aid for an importer's hedging choice.
# These are MODEL ESTIMATES under assumptions, not forecasts of the future.
# =============================================================================
source("R/00_config.R")
md  <- readr::read_csv(file.path(DIR_PROCESSED, "model_data.csv"), show_col_types = FALSE)
df  <- readr::read_csv(file.path(DIR_PROCESSED, "rupee_monthly.csv"), show_col_types = FALSE)
reg <- readRDS(file.path(DIR_OUTPUT, "regression_models.rds"))
m   <- reg$final
out <- function(f) file.path(DIR_OUTPUT, f)

latest <- df |> filter(!is.na(USDINR)) |> slice_max(date, n = 1)
spot   <- latest$USDINR

# A "neutral month": no change in oil, dollar, rates or trade; typical FPI;
# inflation gap at its latest observed value.
neutral <- tibble::tibble(
  Brent_ret = 0, USD_ret = 0, d_Rate_diff = 0, d_Trade_Bal = 0,
  FPI = median(md$FPI), Infl_diff = tail(md$Infl_diff, 1))

scen <- function(name, ...) { s <- neutral; mods <- list(...)
  for (k in names(mods)) s[[k]] <- mods[[k]]; s$scenario <- name; s }
scenarios <- bind_rows(
  scen("Neutral month"),
  scen("Oil +20%",                       Brent_ret = 20),
  scen("Broad dollar +3%",               USD_ret = 3),
  scen("FPI outflow of US$5 bn",         FPI = -5),
  scen("RBI widens rate gap +50 bp",     d_Rate_diff = 0.5),
  scen("Combined stress (oil, dollar, outflow)", Brent_ret = 20, USD_ret = 3, FPI = -5)
)
pr <- predict(m, newdata = scenarios, interval = "prediction", level = 0.80)
scenarios <- scenarios |> mutate(
  est_change_pct = pr[, "fit"], low80 = pr[, "lwr"], high80 = pr[, "upr"],
  implied_USDINR = spot * (1 + est_change_pct / 100),
  implied_low    = spot * (1 + low80 / 100),
  implied_high   = spot * (1 + high80 / 100))
cat(sprintf("Starting point: USD/INR %.2f (%s, FRED EXINUS)\n", spot, latest$date))
print(scenarios |> select(scenario, est_change_pct, low80, high80, implied_USDINR))
readr::write_csv(scenarios, out("scenarios.csv"))

# ---- Decision aid: should an importer hedge a US$10 mn payable? -------------
# Compares the estimated extra rupee cost of staying unhedged with a hedge cost
# entered by the user (e.g. the forward premium quoted by their bank).
exposure_usd     <- 10e6
hedge_cost_pct   <- as.numeric(Sys.getenv("HEDGE_COST_PCT", "0.40"))  # % of notional, 1 month
decision <- scenarios |> mutate(
  extra_cost_unhedged_crore = exposure_usd * spot * pmax(est_change_pct, 0) / 100 / 1e7,
  worst_case_crore          = exposure_usd * spot * pmax(high80, 0) / 100 / 1e7,
  hedge_cost_crore          = exposure_usd * spot * hedge_cost_pct / 100 / 1e7,
  recommendation = case_when(
    worst_case_crore > hedge_cost_crore & extra_cost_unhedged_crore > hedge_cost_crore ~ "Hedge",
    worst_case_crore > hedge_cost_crore ~ "Consider partial hedge",
    TRUE ~ "Stay unhedged"))
print(decision |> select(scenario, extra_cost_unhedged_crore, worst_case_crore,
                         hedge_cost_crore, recommendation))
readr::write_csv(decision, out("hedging_decision.csv"))
