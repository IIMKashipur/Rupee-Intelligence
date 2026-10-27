# =============================================================================
# 03_descriptive_inferential.R  -  Sessions 6-9
# Descriptive: frequencies, mode, mean, median, SD, trends
# Inferential: correlation (with p-values), t-tests, one-way ANOVA + Tukey
# =============================================================================
source("R/00_config.R")
df <- readr::read_csv(file.path(DIR_PROCESSED, "rupee_monthly.csv"), show_col_types = FALSE)
md <- readr::read_csv(file.path(DIR_PROCESSED, "model_data.csv"),   show_col_types = FALSE)
out <- function(f) file.path(DIR_OUTPUT, f)
sink(out("03_descriptive_inferential.txt"), split = TRUE)

# ---- 1. Descriptive statistics ----------------------------------------------
vars <- c("USDINR", "INR_ret", "INR_vol", "Brent", "Brent_ret", "Broad_USD",
          "USD_ret", "VIX", "FPI", "Infl_diff", "Rate_diff", "Trade_Balance",
          "Reserves_bn")
desc <- md |> select(all_of(vars)) |>
  pivot_longer(everything()) |>
  group_by(variable = name) |>
  summarise(n = n(), mean = mean(value), median = median(value),
            sd = sd(value), min = min(value), max = max(value),
            skew = mean((value - mean(value))^3) / sd(value)^3, .groups = "drop")
print(desc, n = Inf, width = Inf)
readr::write_csv(desc, out("descriptive_stats.csv"))

# Frequencies and mode: direction of the rupee each month
md <- md |> mutate(Direction = case_when(INR_ret >  0.5 ~ "Depreciated > 0.5%",
                                         INR_ret < -0.5 ~ "Appreciated > 0.5%",
                                         TRUE           ~ "Stable (within 0.5%)"))
freq <- md |> count(Direction) |> mutate(share = round(100 * n / sum(n), 1))
print(freq)
cat("Mode (most frequent month type):", freq$Direction[which.max(freq$n)], "\n")
cat("Calendar years where rupee weakened (Dec vs prior Dec):\n")
print(df |> filter(month(date) == 12, !is.na(USDINR)) |>
        mutate(pct_change = 100 * (USDINR / lag(USDINR) - 1)) |>
        select(Year, USDINR, pct_change), n = Inf)

# ---- 2. Trend charts ---------------------------------------------------------
p1 <- ggplot(df |> filter(!is.na(USDINR)), aes(date, USDINR)) +
  geom_rect(data = shock_events, inherit.aes = FALSE,
            aes(xmin = start, xmax = end, ymin = -Inf, ymax = Inf),
            fill = "grey70", alpha = 0.35) +
  geom_line(linewidth = 0.8, colour = "#1f4e79") +
  labs(title = "USD/INR monthly average, with major shock periods shaded",
       x = NULL, y = "Rupees per US dollar",
       caption = "Source: Federal Reserve G.5 via FRED (EXINUS)") +
  theme_minimal(base_size = 12)
ggsave(out("fig_usdinr_trend.png"), p1, width = 10, height = 5, dpi = 150)

p2 <- ggplot(md, aes(INR_ret)) +
  geom_histogram(bins = 30, fill = "#1f4e79", colour = "white") +
  geom_vline(xintercept = mean(md$INR_ret), linetype = 2) +
  labs(title = "Distribution of monthly USD/INR returns",
       x = "% change in USD/INR (positive = rupee weaker)", y = "Months") +
  theme_minimal(base_size = 12)
ggsave(out("fig_return_hist.png"), p2, width = 8, height = 5, dpi = 150)

# ---- 2b. Stationarity (ADF): why the models use returns, not USD/INR levels --
# Proposal specified an ADF test. India_Rate is the OECD 3-month interbank
# series (FRED INDIR3TIB01STM), used as a proxy for the RBI repo — not the
# policy rate itself.
cat("\nAugmented Dickey-Fuller tests (H0: unit root). Negative, significant t = stationary.\n")
adf_series <- list(
  USDINR_level     = md$USDINR,
  INR_ret          = md$INR_ret,
  Brent_level      = md$Brent,
  Brent_ret        = md$Brent_ret,
  Broad_USD_level  = md$Broad_USD,
  USD_ret          = md$USD_ret,
  India_Rate_level = md$India_Rate,
  d_Rate_diff      = md$d_Rate_diff
)
adf_tbl <- purrr::imap_dfr(adf_series, function(x, nm) {
  x <- x[is.finite(x)]
  a <- tseries::adf.test(x, alternative = "stationary")
  tibble::tibble(series = nm, n = length(x), statistic = unname(a$statistic),
                 lag = a$parameter, p_value = a$p.value)
})
print(adf_tbl, n = Inf, width = Inf)
readr::write_csv(adf_tbl, out("adf_tests.csv"))
cat("Interpretation: USD/INR and Brent levels typically fail to reject a unit root;",
    "INR_ret and Brent_ret typically reject it. Models therefore use returns/changes.\n")

# ---- 3. Correlation with significance ---------------------------------------
cvars <- c("INR_ret", "Brent_ret", "USD_ret", "VIX_chg", "FPI", "Infl_diff",
           "d_Rate_diff", "d_Trade_Bal", "Reserves_chg")
cm <- cor(md[, cvars])
corr_tbl <- purrr::map_dfr(cvars[-1], function(v) {
  t <- cor.test(md$INR_ret, md[[v]])
  tibble::tibble(variable = v, r = unname(t$estimate), p_value = t$p.value,
                 ci_low = t$conf.int[1], ci_high = t$conf.int[2])
}) |> arrange(desc(abs(r)))
cat("\nCorrelation of each driver with INR_ret (same month):\n"); print(corr_tbl)
readr::write_csv(corr_tbl, out("correlation_with_inr.csv"))
png(out("fig_corrplot.png"), width = 900, height = 900, res = 130)
corrplot::corrplot(cm, method = "color", type = "upper", addCoef.col = "black",
                   number.cex = 0.7, tl.col = "black", diag = FALSE)
dev.off()

# ---- 4. t-tests --------------------------------------------------------------
cat("\nH0: mean INR_ret is equal in FPI-outflow and FPI-inflow months\n")
print(t.test(INR_ret ~ (FPI < 0), data = md))           # Welch t-test
cat("\nH0: mean INR_ret is equal when oil rose vs fell\n")
print(t.test(INR_ret ~ (Brent_ret > 0), data = md))
cat("\nH0: rupee volatility is equal in shock and normal months\n")
print(t.test(INR_vol ~ (Shock_period == "Normal"), data = md))

# ---- 5. One-way ANOVA --------------------------------------------------------
md <- md |> mutate(
  Oil_Regime  = cut(Brent_ret, quantile(Brent_ret, c(0, 1/3, 2/3, 1)),
                    labels = c("Oil falling", "Oil flat", "Oil rising"),
                    include.lowest = TRUE),
  Flow_Regime = cut(FPI, quantile(FPI, c(0, 1/3, 2/3, 1)),
                    labels = c("Heavy outflow", "Neutral", "Strong inflow"),
                    include.lowest = TRUE))
cat("\nANOVA: INR_ret by oil regime\n")
a1 <- aov(INR_ret ~ Oil_Regime, data = md);  print(summary(a1)); print(TukeyHSD(a1))
cat("\nANOVA: INR_ret by FPI flow regime\n")
a2 <- aov(INR_ret ~ Flow_Regime, data = md); print(summary(a2)); print(TukeyHSD(a2))
cat("\nANOVA assumption check (Levene):\n")
print(car::leveneTest(INR_ret ~ Flow_Regime, data = md))
cat("\nKruskal-Wallis (non-parametric check):\n")
print(kruskal.test(INR_ret ~ Flow_Regime, data = md))

p3 <- ggplot(md, aes(Flow_Regime, INR_ret, fill = Flow_Regime)) +
  geom_boxplot(show.legend = FALSE) +
  labs(title = "Rupee moves by FPI flow regime", x = NULL,
       y = "% change in USD/INR") + theme_minimal(base_size = 12)
ggsave(out("fig_anova_fpi.png"), p3, width = 8, height = 5, dpi = 150)

sink()
message("Saved outputs to ", DIR_OUTPUT)
