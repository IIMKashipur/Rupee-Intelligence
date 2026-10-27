# What Really Drives the Rupee?
IIM Kashipur EMBA (Analytics) · Business Intelligence & Business Analytics · Group 4

A data-driven intelligence system that explains and classifies monthly USD/INR
movements using **only real, official data downloaded by code**.

## Real-data policy
- Every value comes from FRED (Federal Reserve, EIA, BLS, OECD, IMF series), the
  World Bank Pink Sheet, NSDL (FPI) or MoSPI (CPI).
- Nothing is simulated, randomly generated, interpolated or imputed. If a source
  fails, the scripts stop with an error.
- `set.seed()` appears only to make SVM cross-validation and k-means starting
  points reproducible; it never creates data.
- `data/processed/provenance.csv` lists the source, series ID, URL and download
  time of every column.

## Folder layout
```
rupee_project/
├── app.R                         Shiny dashboard
├── R/
│   ├── 00_config.R               settings, series catalogue, packages
│   ├── 01_fetch_data.R           downloads (FRED API/CSV, World Bank, NSDL, MoSPI)
│   ├── 02_build_dataset.R        monthly alignment, merge, features, QA log
│   ├── 03_descriptive_inferential.R   stats, correlation, t-tests, ANOVA
│   ├── 04_regression.R           Models A-D + forecast model F, diagnostics, test
│   ├── 05_classification.R       logistic, LDA, tree, SVM, confusion matrices
│   ├── 06_clustering_rules.R     k-means, hierarchical, Apriori rules
│   ├── 07_scenario.R             what-if scenarios + hedging decision aid
│   ├── 08_realtime_refresh.R     live quotes + month-to-date nowcast
│   └── run_all.R                 runs 01-07 in order
├── data/raw/        untouched downloads
├── data/manual/     CSVs copied by hand from official pages (FPI, India CPI)
├── data/processed/  rupee_monthly.csv, model_data.csv, provenance, QA log
└── output/          charts (.png), tables (.csv), model objects (.rds)
```

## Setup (once)
1. Install R (4.1 or newer) and RStudio.
2. Open the `rupee_project` folder as the working directory.
3. Optional but recommended: a free FRED API key from
   https://fred.stlouisfed.org/docs/api/api_key.html. Add it to `~/.Renviron`:
   ```
   FRED_API_KEY=your_key_here
   ```
   Without a key the scripts use FRED's public CSV download, which returns the
   same data.
4. `source("R/run_all.R")` — the first run installs missing packages.

## The two semi-manual series
| Series | Why | What to do |
|---|---|---|
| FPI flows | NSDL publishes an HTML report, not an API. The script tries to scrape it year by year. | If scraping fails, copy the "Monthly FPI Net Investments" table into `data/manual/fpi_monthly.csv` with columns `month,fpi_equity,fpi_debt,fpi_total,unit` (unit `INR_cr` or `USD_mn`). |
| India CPI | FRED's OECD India CPI stops at March 2025. | Either add MoSPI API credentials (`MOSPI_USER`, `MOSPI_PASS` in `.Renviron`) or copy headline all-India CPI inflation (y/y %) from MoSPI press releases into `data/manual/india_cpi.csv` with columns `month,india_cpi_yoy`. |

Copy figures exactly as published. Do not round, estimate or fill gaps.

## Near-real-time updates
`R/08_realtime_refresh.R` pulls live quotes (Yahoo Finance via `quantmod`),
re-downloads all official sources and recomputes a month-to-date estimate.

Schedule it on weekdays:
- **macOS/Linux (cron):** `0 19 * * 1-5 cd /path/to/rupee_project && Rscript R/08_realtime_refresh.R`
- **Windows:** Task Scheduler → Create Basic Task → Daily → Action: start
  `Rscript.exe` with argument `R/08_realtime_refresh.R` and "Start in" set to the
  project folder.

## Dashboard
`shiny::runApp()` from the project folder. Tabs: Overview, Shock Explorer,
Driver Scorecard, What-if Simulator, Stress Monitor, Regimes & Rules, Data & Sources.
To share it, deploy free on shinyapps.io with `rsconnect::deployApp()`.

## How to read results
- `INR_ret` > 0 means the rupee weakened (more rupees per dollar).
- Regression results are statistical associations, not proof of causation.
- The "Nowcast" classifier uses same-month data and cannot forecast; the
  "Early warning" classifier uses only last month's data and is the honest test
  of predictability.

## Documents (submission pack)
- [`docs/DATA_DICTIONARY.md`](docs/DATA_DICTIONARY.md) — column definitions and sources  
- [`docs/FINAL_REPORT.md`](docs/FINAL_REPORT.md) — full project report  
- [`docs/PRESENTATION_SLIDES.md`](docs/PRESENTATION_SLIDES.md) — 12-slide outline for Sessions 19–20  
- [`docs/RQ1_descriptive_inferential.md`](docs/RQ1_descriptive_inferential.md) / [`docs/RQ2_RQ3_regression.md`](docs/RQ2_RQ3_regression.md) — analysis notes  
- Smoke-test dashboard inputs: `Rscript R/check_dashboard.R`

**Headline result (Gate-2 freeze):** oil is **not** a significant partial driver of monthly USD/INR returns; **FPI** and the **broad dollar** are. Model C fits in-sample (adj. R² ≈ 0.43) but does **not** beat a naive mean on 2023+ test RMSE — reported honestly.
