# RQ2–RQ3 — Regression notes (Sessions 10–11)

## Models
- **A:** oil only  
- **B:** oil + inflation gap  
- **C:** oil + inflation + rate-gap change + broad dollar + FPI + trade  
- **D:** C + VIX + lagged FPI  
- **F:** lagged inputs only (honest forecast)

## In-sample
Model C adj. R² ≈ **0.43** vs Model A ≈ **0.03**. Multi-factor nest answers RQ3: oil alone is insufficient.

## Scorecard (Model C, standardised, Newey–West)
Significant: **FPI (−)** and **USD_ret (+)**. Brent insignificant.

## Out-of-sample honesty
Naive mean beats Models A–D–F on test RMSE. Direction hit for C ties naive (~63%). Report as: explanatory power ≠ forecast skill at monthly horizon.

## Diagnostics (Model C)
VIF &lt; 2; BP p ≈ 0.19; DW p ≈ 0.06; Shapiro p ≈ 0.44.
