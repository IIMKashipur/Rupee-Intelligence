# =============================================================================
# 02_build_dataset.R  -  align to monthly, merge, engineer features, QA
# Output: data/processed/rupee_monthly.csv   (all months, all columns)
#         data/processed/model_data.csv      (complete rows used for models)
#         data/processed/data_quality_log.csv
# Rule: NO interpolation, NO imputation. Missing months are dropped & logged.
# =============================================================================
source("R/00_config.R")

fred_raw <- readRDS(file.path(DIR_RAW, "fred_raw.rds"))
fpi      <- readRDS(file.path(DIR_RAW, "fpi.rds"))
cpi_man  <- readRDS(file.path(DIR_RAW, "india_cpi_manual.rds"))
wb_path  <- file.path(DIR_RAW, "wb_brent.rds")
wb_brent <- if (file.exists(wb_path)) readRDS(wb_path) else NULL

to_month <- function(d) floor_date(d, "month")

# ---- 1. Monthly series (already monthly: just rename) -----------------------
monthly_cols <- fred_series |> filter(agg == "none") |> pull(column)
monthly <- purrr::map(monthly_cols, function(col) {
  fred_raw[[col]] |> transmute(date = to_month(date), !!col := value)
}) |> purrr::reduce(full_join, by = "date")

# ---- 2. Daily series -> monthly ---------------------------------------------
daily_mean <- function(col) {
  fred_raw[[col]] |> mutate(date = to_month(date)) |>
    group_by(date) |> summarise(!!col := mean(value), .groups = "drop")
}
inr_daily <- fred_raw[["USDINR_daily"]] |> arrange(date) |>
  mutate(ret = 100 * log(value / lag(value)), m = to_month(date)) |>
  group_by(date = m) |>
  summarise(USDINR_eom = last(value),
            INR_vol    = sd(ret, na.rm = TRUE),   # SD of daily % log returns
            trading_days = n(), .groups = "drop")

daily <- list(daily_mean("Brent"), daily_mean("Broad_USD"), daily_mean("VIX"),
              inr_daily) |> purrr::reduce(full_join, by = "date")

# ---- 3. FPI: INR crore -> USD bn (using the same month's official USDINR) ----
fpi_m <- fpi |>
  mutate(date = as.Date(paste0(month, "-01"))) |>
  left_join(monthly |> select(date, USDINR), by = "date") |>
  mutate(conv = ifelse(unit == "USD_mn", 1 / 1000, 10 / USDINR / 1000),
         FPI_Equity = fpi_equity * conv,
         FPI_Debt   = fpi_debt   * conv,
         FPI        = fpi_total  * conv) |>         # US$ billion, net inflow +
  select(date, FPI, FPI_Equity, FPI_Debt)

# ---- 4. India CPI inflation (y/y %) -----------------------------------------
cpi_fred <- monthly |> select(date, India_CPI_fred) |> arrange(date) |>
  mutate(cpi_yoy_fred = 100 * (India_CPI_fred / lag(India_CPI_fred, 12) - 1)) |>
  select(date, cpi_yoy_fred)
if (!is.null(cpi_man)) {
  cpi_m <- cpi_man |> transmute(date = as.Date(paste0(month, "-01")),
                                cpi_yoy_man = india_cpi_yoy)
  cpi <- full_join(cpi_fred, cpi_m, by = "date") |>
    mutate(India_CPI_yoy = coalesce(cpi_yoy_man, cpi_yoy_fred),
           India_CPI_src = ifelse(!is.na(cpi_yoy_man), "MoSPI", "OECD/FRED"))
} else {
  cpi <- cpi_fred |> mutate(India_CPI_yoy = cpi_yoy_fred, India_CPI_src = "OECD/FRED")
}
cpi <- cpi |> select(date, India_CPI_yoy, India_CPI_src)

# ---- 5. Merge ----------------------------------------------------------------
df <- monthly |>
  full_join(daily, by = "date") |>
  full_join(fpi_m, by = "date") |>
  full_join(cpi,   by = "date") |>
  filter(date >= START_DATE) |>
  arrange(date)

stopifnot(!any(duplicated(df$date)))   # one row per month

# ---- 6. Feature engineering --------------------------------------------------
pct <- function(x, k = 1) 100 * (x / lag(x, k) - 1)
df <- df |>
  mutate(
    # target: + = rupee depreciation, - = appreciation
    INR_ret        = pct(USDINR),
    INR_ret_eom    = pct(USDINR_eom),
    Brent_ret      = pct(Brent),
    USD_ret        = pct(Broad_USD),
    VIX_chg        = VIX - lag(VIX),
    US_CPI_yoy     = pct(US_CPI, 12),
    Infl_diff      = India_CPI_yoy - US_CPI_yoy,
    Rate_diff      = India_Rate - US_Rate,
    d_Rate_diff    = Rate_diff - lag(Rate_diff),
    d_US_10Y       = US_10Y - lag(US_10Y),
    Trade_Balance  = (Exports - Imports) / 1e9,          # US$ bn
    d_Trade_Bal    = Trade_Balance - lag(Trade_Balance),
    Reserves_bn    = Forex_Reserves / 1000,
    Reserves_chg   = pct(Forex_Reserves),
    Year           = year(date),
    Shock_period   = purrr::map_chr(date, function(d) {
      hit <- shock_events$event[d >= shock_events$start & d <= shock_events$end]
      if (length(hit)) hit[1] else "Normal"
    })
  ) |>
  # one-month lags: what was known before the month started (for forecasting)
  mutate(across(c(Brent_ret, USD_ret, VIX_chg, FPI, d_Rate_diff, Infl_diff,
                  d_Trade_Bal, Reserves_chg, INR_ret, INR_vol),
                ~ lag(.x), .names = "L1_{.col}"))

# High-pressure month = depreciation above the 75th percentile of TRAINING
# months only (threshold fixed before looking at the test period).
thr <- quantile(df$INR_ret[df$date >= MODEL_START & df$date <= TRAIN_END],
                0.75, na.rm = TRUE)
df <- df |> mutate(High_Pressure = factor(ifelse(INR_ret > thr, "High", "Normal"),
                                          levels = c("Normal", "High")))
attr(df, "pressure_threshold") <- thr
message(sprintf("High-pressure threshold (train 75th pct): %.2f%% per month", thr))

# ---- 7. Data-quality log -----------------------------------------------------
model_vars <- c("INR_ret", "Brent_ret", "USD_ret", "VIX_chg", "FPI",
                "Infl_diff", "d_Rate_diff", "d_Trade_Bal", "Reserves_chg")
dq <- df |> filter(date >= MODEL_START) |>
  summarise(across(all_of(model_vars), ~ sum(is.na(.x)))) |>
  pivot_longer(everything(), names_to = "variable", values_to = "missing_months") |>
  left_join(
    df |> filter(date >= MODEL_START) |>
      summarise(across(all_of(model_vars), ~ as.character(max(date[!is.na(.x)])))) |>
      pivot_longer(everything(), names_to = "variable", values_to = "last_month"),
    by = "variable")
print(dq)
lag_vars <- dq |> filter(as.Date(last_month) < max(as.Date(dq$last_month)) %m-% months(3))
if (nrow(lag_vars) > 0) {
  warning("These inputs end early and will cut the model sample: ",
          paste0(lag_vars$variable, " (", lag_vars$last_month, ")", collapse = ", "),
          ". For Infl_diff, add MoSPI headline CPI to data/manual/india_cpi.csv.")
}
readr::write_csv(dq, file.path(DIR_PROCESSED, "data_quality_log.csv"))

# Oil cross-check: FRED/EIA vs World Bank
if (!is.null(wb_brent)) {
  chk <- inner_join(df |> select(date, Brent), wb_brent, by = "date")
  message(sprintf("Brent cross-check: %d months, correlation %.4f, mean abs diff $%.2f",
                  nrow(chk), cor(chk$Brent, chk$value), mean(abs(chk$Brent - chk$value))))
}

# ---- 8. Save -----------------------------------------------------------------
readr::write_csv(df, file.path(DIR_PROCESSED, "rupee_monthly.csv"))
model_data <- df |> filter(date >= MODEL_START) |> drop_na(all_of(model_vars))
readr::write_csv(model_data, file.path(DIR_PROCESSED, "model_data.csv"))
saveRDS(list(threshold = thr), file.path(DIR_PROCESSED, "meta.rds"))
message(sprintf("Model data: %d complete months, %s to %s",
                nrow(model_data), min(model_data$date), max(model_data$date)))
