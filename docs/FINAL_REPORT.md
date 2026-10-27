# What Really Drives the Rupee?
## A Data-Driven Intelligence System for Explaining and Predicting USD/INR Movements

**IIM Kashipur · EMBA (Analytics) · Business Intelligence & Business Analytics · Group 4**

| Member | Roll |
|---|---|
| Ankit Singh | EMBAA25004 |
| Aswin G. | EMBAA25008 |
| Atul Kumar Singh | EMBAA25009 |
| Devanshu Priyam | EMBAA25014 |
| Gopalakrishnan S | EMBAA25017 |
| Murugan Perumal | EMBAA25020 |

---

## 1. Problem and motivation

In 2026 the rupee crossed ₹95 per US dollar and was Asia’s weakest major currency. Public debate often collapses the move to a single cause — “oil went up, so the rupee fell.” Importers, exporters and treasurers need a clearer ranking of forces and a way to stress-test exposure.

This project builds a **Rupee Intelligence System in R** that:

1. Explains which official macroeconomic and market series move with monthly USD/INR returns  
2. Ranks drivers holding others constant  
3. Tests whether oil alone is enough (“Is oil really the villain?”)  
4. Flags high-depreciation months and runs what-if scenarios for hedging decisions  

All numbers come from official publishers. Nothing is simulated, interpolated or typed in by hand except two series copied exactly from NSDL and MoSPI pages when APIs are incomplete.

---

## 2. Data and provenance

**Sources:** FRED (Fed G.5/H.10, EIA Brent, BLS CPI, OECD India rate/trade/CPI, IMF reserves), World Bank Pink Sheet (Brent cross-check), NSDL monthly FPI, MoSPI CPI press releases (Apr 2025 onward).

**Sample:** charts from Jan 2010; models from Jan 2012 (India interbank rate starts Nov 2011) through **Aug 2026** (175 complete months). Trade and reserves publish with a lag, so the model sample ends earlier than the latest USD/INR print.

**Target:** `INR_ret` = monthly % change in FRED `EXINUS`. Positive = rupee weaker.

**Integrity:** `data/processed/provenance.csv` records source, series ID, URL and download time for every column. Missing months are dropped and logged in `data_quality_log.csv`. See `docs/DATA_DICTIONARY.md`.

**Note on India rates:** the proposal mentioned RBI repo; the pipeline uses OECD **3-month interbank** (`INDIR3TIB01STM`) as an automatable official **proxy**, footnoted as such.

**ADF:** levels of USD/INR, Brent and the broad dollar fail to reject a unit root; returns reject it. Specifications therefore use returns and changes, not levels.

---

## 3. Methods (syllabus map)

| Sessions | Technique | Script |
|---|---|---|
| 6–7 | Descriptives, frequencies, trends | `R/03_descriptive_inferential.R` |
| 8–9 | Correlation, Welch t-tests, ANOVA / Tukey / Kruskal–Wallis | same |
| 10–11 | Nested OLS A–D + lagged forecast F; VIF, BP, DW, Newey–West; scorecard | `R/04_regression.R` |
| 12–14 | Logistic, LDA, tree, SVM; early-warning vs nowcast; 3-class appendix | `R/05_classification.R` |
| 15–16 | k-means, hierarchical clustering, Apriori rules | `R/06_clustering_rules.R` |
| 17–18 | What-if scenarios + importer hedge rule (RFM substitute) | `R/07_scenario.R` |

**Train / test:** chronological — train through Dec 2022, test from Jan 2023. Never random.

**High-pressure month:** `INR_ret` above the **training** 75th percentile (**1.26% per month**), fixed before looking at the test period.

**RFM:** not applicable to FX; replaced by scenario analysis and a hedge decision aid (confirm with Prof. Varma).

---

## 4. Findings

### 4.1 RQ1 — What moves with the rupee?

Strongest same-month correlations with `INR_ret`:

- **FPI** r = −0.49 (inflows ↔ stronger rupee)  
- **Broad dollar return** r = +0.47  
- **Reserves change** r = −0.37  
- **Brent return** r = −0.13 (**not significant**)  
- **Inflation gap** r = +0.05 (**not significant**)

ANOVA by FPI regime is highly significant; by oil regime it is not. Volatility is higher in labelled shock windows than in normal months.

### 4.2 RQ2–RQ3 — Driver scorecard and “Is oil the villain?”

Standardised Model C coefficients (Newey–West SEs), train 2012–2022:

| Driver | Std. β | Significant? | Interpretation |
|---|---|---|---|
| FPI | −0.40 | Yes | Inflows associated with stronger rupee |
| Broad dollar return | +0.32 | Yes | Stronger dollar ↔ weaker rupee |
| Rate-gap change | +0.17 | No | — |
| Inflation gap | +0.14 | No | — |
| Trade-balance change | +0.11 | No | — |
| **Brent return** | **−0.01** | **No** | **Oil not a significant driver once others are held constant** |

Nested fit (train adj. R²): Model A (oil only) 0.03 → B 0.03 → **C 0.43** → D 0.43. Adding the multi-factor set lifts in-sample fit sharply; oil alone does not.

**Out-of-sample (2023 onward), honest result:**

| Model | Test RMSE | Direction hit |
|---|---|---|
| Naive (train mean) | **0.74** | 0.63 |
| F (lagged only) | 0.78 | 0.60 |
| A (oil) | 0.86 | 0.60 |
| C (multi-factor) | 1.01 | 0.63 |

Model C **explains** in sample but **does not beat the naive mean on test RMSE**. Direction accuracy is similar to naive. We report this as a finding, not a failure: same-month associations are real; **predicting next month’s move from these drivers is hard**.

Diagnostics on Model C: VIF all &lt; 2; Breusch–Pagan p ≈ 0.19; Durbin–Watson p ≈ 0.06; Shapiro–Wilk on residuals p ≈ 0.44.

### 4.3 RQ4 — Stress monitor

- **Early-warning** (last month’s data only): LDA balanced accuracy ≈ 0.72, AUC ≈ 0.69 — modest forecast skill.  
- **Nowcast** (same-month drivers): LDA / logistic AUC ≈ 0.86–0.87 — **explains** pressure, must not be sold as a forecast.  
- 3-class appendix tree (Stable / Moderate / High): test accuracy ≈ 0.63.

### 4.4 Regimes and rules

k-means finds **two** regimes (silhouette):

1. **Calm / inflow:** mean `INR_ret` −0.45%, FPI +2.8 bn, dollar soft, VIX down  
2. **Pressure / outflow:** mean `INR_ret` +1.41%, FPI −1.7 bn, dollar firm, VIX up  

Top Apriori rule (rhs = Rupee=Weak): `{FPI=Low, RateGapChange=High, TradeBalChange=Mid}` — support 5%, confidence 100%, lift ≈ 3.0.

### 4.5 Scenarios and hedging (from ₹95.51, Sep 2026 FRED)

| Scenario | Est. monthly Δ | Implied USD/INR | Hedge advice (US$10 mn payable, 0.40% cost) |
|---|---|---|---|
| Neutral | +0.26% | 95.8 | Consider partial hedge |
| Oil +20% | +0.10% | 95.6 | Consider partial hedge |
| Broad dollar +3% | +1.36% | 96.8 | **Hedge** |
| FPI outflow $5 bn | +1.06% | 96.5 | **Hedge** |
| Combined stress | +1.99% | 97.4 | **Hedge** |

These are **model-implied ranges under assumptions**, not forecasts.

---

## 5. Dashboard

Seven-tab Shiny app (`app.R`): Overview, Shock Explorer, Driver Scorecard, What-if Simulator, Stress Monitor, Regimes & Rules, Data & Sources.

Run: from `rupee_project/`, `shiny::runApp()`. Optional public deploy: `rsconnect::deployApp()` (credentials required; not executed in this workspace).

Near-real-time: `R/08_realtime_refresh.R` refreshes Yahoo live quotes and a month-to-date Model C estimate.

---

## 6. Managerial implications

1. **Do not hedge “because oil rose.”** In this monthly sample, oil is not a significant partial associate of rupee returns; the broad dollar and FPI flows are.  
2. **Watch portfolio flows and the dollar index** for stress. Combined outflow + dollar strength is the scenario that most clearly tips the hedge rule to “Hedge.”  
3. **Treat same-month “nowcasts” as explanation**, and use the early-warning classifier only with modest expectations — it does not dominate a naive benchmark.  
4. **Reserve changes** proxy RBI intervention imperfectly; unexplained variation remains, especially around 2026.

---

## 7. Limitations

- Association ≠ causation; FPI and the rupee are endogenous.  
- Structural breaks possible across taper, COVID and 2022–26 regimes.  
- Trade/reserves lag trim the model sample to Aug 2026.  
- India interbank rate proxies repo.  
- Monthly averages smooth daily shocks.  
- RBI intervention is not observed directly.

---

## 8. How to reproduce

```bash
cd doucments/rupee_project
# optional: FRED_API_KEY in ~/.Renviron
Rscript R/run_all.R          # 01–07
Rscript R/08_realtime_refresh.R   # optional live
# then in R: shiny::runApp()
```

Manual inputs (already populated for this freeze):

- `data/manual/fpi_monthly.csv` — NSDL monthly totals  
- `data/manual/india_cpi.csv` — MoSPI y/y from Apr 2025  

---

## 9. References (APA style)

Federal Reserve Bank of St. Louis. (n.d.). *Federal Reserve Economic Data (FRED)*. https://fred.stlouisfed.org/

Board of Governors of the Federal Reserve System. (n.d.). *G.5 / H.10 Foreign exchange rates*. https://www.federalreserve.gov/releases/h10/

U.S. Energy Information Administration. (n.d.). *Brent spot price*. (via FRED `DCOILBRENTEU`).

World Bank. (2026). *Commodity markets: Pink Sheet historical data (monthly)*. https://www.worldbank.org/en/research/commodity-markets

National Securities Depository Limited. (n.d.). *Monthly FPI net investments (calendar year)*. https://www.fpi.nsdl.co.in/web/Reports/Yearwise.aspx?RptType=6

Ministry of Statistics and Programme Implementation. (2025–2026). *Consumer Price Index press releases* (all-India combined general). https://www.mospi.gov.in/

Organisation for Economic Co-operation and Development. (n.d.). India short-term interest rate and merchandise trade series (via FRED).

International Monetary Fund. (n.d.). India total reserves excluding gold (via FRED `TRESEGINM052N`).

Polymerupdate / CareEdge. (2026). *Rupee@97: Decoding the drivers of the slide* (Sabnavis regression summary cited as benchmark).

Group-provided Economic Times article on rupee drivers (cite full APA details from the PDF held by the group).

---

## 10. Demo script (Sessions 19–20)

1. **Overview** — latest FRED USD/INR, live Yahoo quote, MTD nowcast.  
2. **Shock Explorer** — select “West Asia conflict, rupee past 95”; show indexed drivers.  
3. **Driver Scorecard** — FPI and dollar dominate; oil near zero.  
4. **What-if** — oil +20% vs dollar +3% + FPI −5; compare hedge advice.  
5. **Data & Sources** — open provenance to show integrity.
