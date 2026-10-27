# Data dictionary — What Really Drives the Rupee?

IIM Kashipur EMBA (Analytics) · BI & BA · Group 4  
Sample for models: January 2012 to the latest month where all model inputs exist. Charts use history from January 2010.

**Integrity:** every value is from an official publisher. Missing months are dropped (never interpolated). Provenance of each download is in `data/processed/provenance.csv`.

| Column | Definition | Unit | Source / series ID | Expected sign on USD/INR (`INR_ret` > 0 = weaker rupee) |
|---|---|---|---|---|
| `date` | Month start (YYYY-MM-01) | date | constructed | — |
| `USDINR` | INR per USD, monthly average | ₹/$ | FRED `EXINUS` (Fed G.5) | target level |
| `USDINR_eom` | Month-end INR per USD | ₹/$ | FRED `DEXINUS` (Fed H.10) | — |
| `INR_ret` | Monthly % change in `USDINR` | % | derived | **target** |
| `INR_vol` | SD of daily log % returns in the month | % | derived from `DEXINUS` | — |
| `Brent` | Brent crude spot | $/bbl | FRED `DCOILBRENTEU` (EIA); cross-check World Bank Pink Sheet | + |
| `Brent_ret` | Monthly % change in Brent | % | derived | + |
| `Broad_USD` | Nominal broad US dollar index | index | FRED `DTWEXBGS` (Fed) | + |
| `USD_ret` | Monthly % change in broad dollar | % | derived | + |
| `VIX` | CBOE VIX | index | FRED `VIXCLS` | + (risk-off) |
| `VIX_chg` | Month change in VIX | points | derived | + |
| `US_CPI` | US CPI, all urban, SA | index | FRED `CPIAUCSL` (BLS) | — |
| `US_CPI_yoy` | US CPI year-on-year | % | derived | — |
| `India_CPI_yoy` | All-India CPI combined y/y | % | FRED `INDCPIALLMINMEI` (OECD) to Mar 2025; MoSPI press releases after (`data/manual/india_cpi.csv`) | + (via gap) |
| `Infl_diff` | India CPI y/y − US CPI y/y | pp | derived | + |
| `US_Rate` | Effective federal funds rate | % | FRED `FEDFUNDS` | + (via gap) |
| `US_10Y` | US 10-year Treasury yield | % | FRED `GS10` | — |
| `India_Rate` | India 3-month interbank rate | % | FRED `INDIR3TIB01STM` (OECD) | **proxy for RBI repo**, not the policy rate itself |
| `Rate_diff` | India_Rate − US_Rate | pp | derived | − (wider India premium) |
| `d_Rate_diff` | Change in rate differential | pp | derived | − |
| `Exports` / `Imports` | India merchandise trade, SA | USD | FRED `XTEXVA01INM667S` / `XTIMVA01INM667S` (OECD) | — |
| `Trade_Balance` | Exports − Imports | US$ bn | derived | − when surplus |
| `d_Trade_Bal` | Change in trade balance | US$ bn | derived | − |
| `Forex_Reserves` | Reserves excl. gold | US$ mn | FRED `TRESEGINM052N` (IMF) | — |
| `Reserves_bn` / `Reserves_chg` | Level / % change | US$ bn / % | derived | − (buffer) |
| `FPI` | Net FPI (equity + debt + other) | US$ bn | NSDL Monthly FPI Net Investments (`data/manual/fpi_monthly.csv`) | − (inflow) |
| `High_Pressure` | `INR_ret` above **train** 75th percentile | factor | derived (threshold fixed on 2012–2022) | — |
| `L1_*` | One-month lag of a driver | same | derived | used only in forecast / early-warning models |

### Manual series (copied exactly from publisher pages)

- **FPI:** NSDL [Yearwise Monthly FPI Net Investments](https://www.fpi.nsdl.co.in/web/Reports/Yearwise.aspx?RptType=6), columns `month,fpi_equity,fpi_debt,fpi_total,unit` with `unit=INR_cr`. Converted to US$ bn with the same month’s `USDINR`.
- **India CPI (Apr 2025 onward):** MoSPI / NSO all-India combined general CPI y/y from press releases; see `data/manual/india_cpi_SOURCES.txt`.

### Train / test split

- Train: `date <= 2022-12-01`
- Test: `date >= 2023-01-01`  
Chronological only — never random.
