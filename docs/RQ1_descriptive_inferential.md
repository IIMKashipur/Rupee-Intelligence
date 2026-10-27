# RQ1 notes — Descriptive & inferential (Sessions 6–9)

**Dataset:** 175 complete model months, Jan 2012 – Aug 2026 (`model_data.csv`).

## Descriptive
- Mean monthly `INR_ret` ≈ **+0.35%** (median 0.18%, SD 1.45%) — the rupee drifted weaker on average.
- ADF tests: **USD/INR, Brent and Broad USD levels fail to reject a unit root**; **returns / changes reject** (p ≈ 0.01). Models correctly use returns, not levels.
- `India_Rate` is the OECD 3-month interbank series (FRED `INDIR3TIB01STM`) — a **proxy for RBI repo**, not the policy rate itself.

## Correlations with `INR_ret` (same month)
| Driver | r | p |
|---|---|---|
| FPI | −0.49 | ≪ 0.001 |
| Broad dollar return | +0.47 | ≪ 0.001 |
| Reserves % change | −0.37 | ≪ 0.001 |
| Rate-gap change | +0.25 | 0.001 |
| VIX change | +0.23 | 0.002 |
| Brent return | −0.13 | 0.08 (n.s.) |
| Inflation gap | +0.05 | 0.51 (n.s.) |

## Tests
- **Welch t-test:** mean `INR_ret` is higher in FPI-outflow months than inflow months (clear difference).
- Oil up vs oil down: **not significant** (p ≈ 0.35).
- Volatility higher in shock windows than normal months (p ≈ 0.015).
- **ANOVA by FPI regime:** highly significant (p ≪ 0.001); Tukey: Heavy outflow > Neutral > Strong inflow for depreciation.
- **ANOVA by oil regime:** not significant (p ≈ 0.31).

## RQ1 answer (draft for report)
The variables that move most strongly with monthly USD/INR returns are **net FPI flows** and the **broad US dollar**, not crude oil. Oil’s simple association is weak and insignificant in this sample.
