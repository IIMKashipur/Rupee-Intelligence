# Presentation deck — What Really Drives the Rupee?  
**Group 4 · IIM Kashipur EMBAA · BI & BA · Sessions 19–20**  
*(12 slides — paste into PowerPoint / Google Slides)*

---

### Slide 1 — Title
**What Really Drives the Rupee?**  
A data-driven intelligence system for USD/INR  
Group 4 · Ankit, Aswin, Atul, Devanshu, Gopalakrishnan, Murugan

### Slide 2 — Why this matters
- Rupee past ₹95 in 2026; Asia’s weakest major currency  
- Businesses hear “oil did it” — we test that claim with official data  
- Deliverable: ranked drivers + stress monitor + what-if simulator

### Slide 3 — Research questions
1. Which factors move with monthly USD/INR returns?  
2. Is oil the villain, or dollar + flows?  
3. Can we flag high-pressure months early?  
4. What does the model imply under stress scenarios?

### Slide 4 — Data integrity
- FRED, World Bank Pink Sheet, NSDL FPI, MoSPI CPI  
- No synthetic / interpolated values; provenance file for every column  
- 175 model months (2012–Aug 2026); train→2022, test 2023+

### Slide 5 — RQ1 snapshot
- FPI r = −0.49; broad dollar r = +0.47  
- Brent and inflation gap **not** significant alone  
- ANOVA: FPI regimes matter; oil regimes do not

### Slide 6 — “Is oil the villain?”
- Model A (oil only): adj. R² ≈ 0.03  
- Model C (oil + inflation + rates + dollar + FPI + trade): adj. R² ≈ 0.43  
- Standardised β: **FPI −0.40**, **dollar +0.32**, **oil ≈ 0**  
- Answer: **No — oil is not the villain in this monthly sample**

### Slide 7 — Honest forecast test
- Out-of-sample RMSE: Naive 0.74 &lt; Model F 0.78 &lt; Model C 1.01  
- Associations are real; month-ahead prediction is hard  
- We report the miss vs naive as a finding

### Slide 8 — Stress monitor
- High-pressure = above train 75th pct (1.26%/month)  
- Early-warning (lagged): modest skill (LDA bal. acc. ≈ 0.72)  
- Nowcast (same month): high AUC ≈ 0.87 — **explanation only**

### Slide 9 — Regimes & rules
- Two k-means regimes: calm/inflow vs pressure/outflow  
- Apriori: low FPI + rising rate gap co-occur with weak rupee (lift ≈ 3)

### Slide 10 — What-if & hedge
- From ₹95.51: oil +20% → little move; dollar +3% or $5 bn outflow → ~₹96.5–96.8  
- Combined stress → ~₹97.4 → **Hedge** a US$10 mn payable  
- Ranges under assumptions, not forecasts

### Slide 11 — Managerial takeaways
1. Watch **FPI and the broad dollar**, not oil headlines alone  
2. Use the simulator for treasury stress tests  
3. Keep language as **association**, not causation

### Slide 12 — Demo & Q&A
Live: Shock Explorer (2026) → Driver Scorecard → What-if → Data & Sources  
Code: `Rscript R/run_all.R` then `shiny::runApp()`
