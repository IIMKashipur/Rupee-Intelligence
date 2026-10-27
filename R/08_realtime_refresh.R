# =============================================================================
# 08_realtime_refresh.R  -  near-real-time update
#  (a) Live market quotes from Yahoo Finance (quantmod) for the dashboard ticker
#  (b) Month-to-date "nowcast" of the rupee pressure using FRED DAILY series
#      (same definitions as the model; FRED daily data lags about one week)
# Schedule it (see README): daily on weekdays, e.g. 19:00 IST.
# =============================================================================
source("R/00_config.R")
dir.create("data/live", showWarnings = FALSE)

# ---- (a) Live quotes ---------------------------------------------------------
tickers <- c(USDINR = "INR=X", Brent_futures = "BZ=F", DXY = "DX-Y.NYB", VIX = "^VIX")
live <- purrr::imap_dfr(tickers, function(tk, nm) {
  x <- tryCatch(quantmod::getSymbols(tk, src = "yahoo", from = Sys.Date() - 40,
                                      auto.assign = FALSE, warnings = FALSE),
                error = function(e) { warning(nm, ": ", e$message); NULL })
  if (is.null(x)) return(NULL)
  cl <- stats::na.omit(quantmod::Cl(x))
  tibble::tibble(series = nm, ticker = tk, date = as.Date(zoo::index(cl)),
                 close = as.numeric(cl))
})
if (nrow(live) > 0) {
  live <- live |> mutate(fetched_at = format(Sys.time(), "%Y-%m-%d %H:%M %Z"))
  readr::write_csv(live, "data/live/live_quotes.csv")
  print(live |> group_by(series) |> slice_max(date, n = 1))
}

# ---- (b) Month-to-date nowcast with FRED daily data -------------------------
source("R/01_fetch_data.R",    local = new.env())  # re-download official sources
source("R/02_build_dataset.R", local = new.env())  # rebuild monthly dataset

fred_raw <- readRDS(file.path(DIR_RAW, "fred_raw.rds"))
this_m   <- floor_date(max(fred_raw$USDINR_daily$date), "month")
mtd_avg  <- function(col, m) mean(fred_raw[[col]]$value[floor_date(fred_raw[[col]]$date, "month") == m])
prev_m   <- this_m %m-% months(1)

nowcast_input <- tibble::tibble(
  Brent_ret   = 100 * (mtd_avg("Brent", this_m)     / mtd_avg("Brent", prev_m) - 1),
  USD_ret     = 100 * (mtd_avg("Broad_USD", this_m) / mtd_avg("Broad_USD", prev_m) - 1),
  FPI         = tail(na.omit(readr::read_csv(file.path(DIR_PROCESSED, "rupee_monthly.csv"),
                                             show_col_types = FALSE)$FPI), 1),
  Infl_diff   = tail(na.omit(readr::read_csv(file.path(DIR_PROCESSED, "rupee_monthly.csv"),
                                             show_col_types = FALSE)$Infl_diff), 1),
  d_Rate_diff = 0, d_Trade_Bal = 0)
actual_mtd <- 100 * (mtd_avg("USDINR_daily", this_m) / mtd_avg("USDINR_daily", prev_m) - 1)

reg <- readRDS(file.path(DIR_OUTPUT, "regression_models.rds"))
est <- predict(reg$final, newdata = nowcast_input, interval = "prediction", level = 0.8)
nowcast <- nowcast_input |> mutate(
  month = this_m, last_daily_obs = max(fred_raw$USDINR_daily$date),
  model_estimate_pct = est[, "fit"], low80 = est[, "lwr"], high80 = est[, "upr"],
  actual_mtd_pct = actual_mtd,
  note = "FPI and inflation gap carried from latest published month")
print(nowcast, width = Inf)
readr::write_csv(nowcast, "data/live/nowcast.csv")
