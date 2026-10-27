# =============================================================================
# What Really Drives the Rupee?  |  IIM Kashipur EMBA  |  BI & BA  |  Group 4
# 00_config.R  -  settings, series catalogue, packages
# -----------------------------------------------------------------------------
# REAL-DATA POLICY: every number in this project is downloaded from an official
# publisher. Nothing is simulated, randomly generated or interpolated. If a
# source fails, the scripts stop with an error instead of inventing values.
# =============================================================================

options(stringsAsFactors = FALSE, timeout = 120, scipen = 999)

# ---- Packages ---------------------------------------------------------------
required_pkgs <- c(
  "httr", "jsonlite", "readr", "purrr", "tibble", "readxl", "dplyr", "tidyr", "lubridate",
  "rvest", "xml2", "zoo", "ggplot2", "scales", "corrplot", "car", "lmtest",
  "sandwich", "rpart", "rpart.plot", "MASS", "e1071", "caret", "pROC",
  "cluster", "factoextra", "gridExtra", "arules", "quantmod", "shiny", "bslib", "plotly",
  "DT", "tseries"
)
missing_pkgs <- setdiff(required_pkgs, rownames(installed.packages()))
if (length(missing_pkgs) > 0) {
  message("Installing: ", paste(missing_pkgs, collapse = ", "))
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(lubridate); library(readr)
  library(ggplot2)
})
select <- dplyr::select   # MASS masks select()

# ---- Folders ----------------------------------------------------------------
DIR_RAW       <- "data/raw"          # untouched downloads (never edited)
DIR_MANUAL    <- "data/manual"       # CSVs copied by hand from official pages
DIR_PROCESSED <- "data/processed"    # cleaned monthly dataset
DIR_OUTPUT    <- "output"            # charts, tables, model objects
for (d in c(DIR_RAW, DIR_MANUAL, DIR_PROCESSED, DIR_OUTPUT)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ---- Study window -----------------------------------------------------------
START_DATE       <- as.Date("2010-01-01")  # history for charts
MODEL_START      <- as.Date("2012-01-01")  # India_Rate starts Nov 2011
TRAIN_END        <- as.Date("2022-12-01")  # chronological split
TEST_START       <- as.Date("2023-01-01")

# ---- Optional API keys (set in ~/.Renviron, never hard-code) ----------------
# FRED_API_KEY  : free from https://fred.stlouisfed.org/docs/api/api_key.html
#                 Without it, the public fredgraph.csv endpoint is used.
# MOSPI_USER / MOSPI_PASS : account at https://api.mospi.gov.in (India CPI)
FRED_API_KEY <- Sys.getenv("FRED_API_KEY", unset = "")

# ---- FRED series catalogue --------------------------------------------------
# agg = how a DAILY series becomes monthly ("mean", "last"); "none" = monthly
fred_series <- tibble::tribble(
  ~column,          ~fred_id,            ~agg,   ~description,
  "USDINR",         "EXINUS",            "none", "INR per USD, monthly average (Fed G.5)",
  "USDINR_daily",   "DEXINUS",           "daily","INR per USD, daily noon buying rate (Fed H.10)",
  "Brent",          "DCOILBRENTEU",      "mean", "Brent crude spot, USD/bbl (EIA)",
  "Broad_USD",      "DTWEXBGS",          "mean", "Nominal broad US dollar index (Fed)",
  "VIX",            "VIXCLS",            "mean", "CBOE VIX, global risk sentiment",
  "US_CPI",         "CPIAUCSL",          "none", "US CPI, all urban consumers, SA (BLS)",
  "US_Rate",        "FEDFUNDS",          "none", "Effective federal funds rate, %",
  "US_10Y",         "GS10",              "none", "US 10-year Treasury yield, %",
  "India_Rate",     "INDIR3TIB01STM",    "none", "India 3-month interbank rate, % (OECD; proxy for RBI repo, not the policy rate itself)",
  "India_CPI_fred", "INDCPIALLMINMEI",   "none", "India CPI 2015=100 (OECD; ends Mar 2025)",
  "Exports",        "XTEXVA01INM667S",   "none", "India merchandise exports, USD, SA (OECD)",
  "Imports",        "XTIMVA01INM667S",   "none", "India merchandise imports, USD, SA (OECD)",
  "Forex_Reserves", "TRESEGINM052N",     "none", "India reserves excl. gold, USD mn (IMF)"
)

# ---- World Bank Pink Sheet (cross-check for oil) ----------------------------
# The document id in this URL changes each year. If it 404s, open
# https://www.worldbank.org/en/research/commodity-markets and copy the current
# "Monthly prices" xlsx link here.
WB_PINK_SHEET_URL <- paste0(
  "https://thedocs.worldbank.org/en/doc/",
  "74e8be41ceb20fa0da750cda2f6b9e4e-0050012026/related/",
  "CMO-Historical-Data-Monthly.xlsx"
)

# ---- NSDL FPI report ---------------------------------------------------------
NSDL_FPI_URL <- "https://www.fpi.nsdl.co.in/Reports/Yearwise.aspx?RptType=6"

# ---- Historical shock windows (dates are public record) ---------------------
shock_events <- tibble::tribble(
  ~event,                              ~start,        ~end,
  "Taper tantrum",                     "2013-05-01",  "2013-09-30",
  "Demonetisation",                    "2016-11-01",  "2016-12-31",
  "2018 oil spike and EM sell-off",    "2018-04-01",  "2018-10-31",
  "COVID-19 shock",                    "2020-02-01",  "2020-05-31",
  "Russia-Ukraine war and Fed hikes",  "2022-02-01",  "2022-10-31",
  "West Asia conflict, rupee past 95", "2026-02-01",  "2026-09-30"
) |> mutate(start = as.Date(start), end = as.Date(end))
