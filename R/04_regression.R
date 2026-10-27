# =============================================================================
# 04_regression.R  -  Sessions 10-11: simple & multiple linear regression
# Experiment "Is oil really the villain?"
#   Model A  oil only
#   Model B  oil + inflation differential
#   Model C  oil + inflation + rate differential + broad dollar + FPI + trade
#   Model D  C + global risk (VIX) + previous-month FPI   (Sabnavis-style lag)
#   Model F  forecasting model: ONLY last month's information
# Train 2012-2022, test 2023-latest (chronological, never random)
# =============================================================================
source("R/00_config.R")
md  <- readr::read_csv(file.path(DIR_PROCESSED, "model_data.csv"), show_col_types = FALSE)
out <- function(f) file.path(DIR_OUTPUT, f)
sink(out("04_regression.txt"), split = TRUE)

md    <- md |> drop_na(L1_FPI, L1_INR_ret, L1_Brent_ret, L1_USD_ret)
train <- md |> filter(date <= TRAIN_END)
test  <- md |> filter(date >= TEST_START)
cat(sprintf("Train: %d months (%s to %s) | Test: %d months (%s to %s)\n",
            nrow(train), min(train$date), max(train$date),
            nrow(test),  min(test$date),  max(test$date)))

f <- list(
  A = INR_ret ~ Brent_ret,
  B = INR_ret ~ Brent_ret + Infl_diff,
  C = INR_ret ~ Brent_ret + Infl_diff + d_Rate_diff + USD_ret + FPI + d_Trade_Bal,
  D = INR_ret ~ Brent_ret + Infl_diff + d_Rate_diff + USD_ret + FPI + d_Trade_Bal +
                VIX_chg + L1_FPI,
  F = INR_ret ~ L1_INR_ret + L1_Brent_ret + L1_USD_ret + L1_FPI + L1_VIX_chg +
                L1_d_Rate_diff + L1_Reserves_chg
)
models <- purrr::map(f, ~ lm(.x, data = train))

# ---- 1. Coefficients with autocorrelation-robust (Newey-West) SEs ----------
for (m in names(models)) {
  cat("\n================ Model", m, "================\n")
  print(summary(models[[m]]))
  cat("Newey-West robust standard errors:\n")
  print(lmtest::coeftest(models[[m]], vcov = sandwich::NeweyWest(models[[m]])))
}

# ---- 2. Diagnostics on the main model C -------------------------------------
mC <- models$C
cat("\nVIF (multicollinearity, >5 is a concern):\n"); print(car::vif(mC))
cat("\nBreusch-Pagan (heteroskedasticity):\n");      print(lmtest::bptest(mC))
cat("\nDurbin-Watson (autocorrelation):\n");          print(lmtest::dwtest(mC))
cat("\nShapiro-Wilk on residuals:\n");                print(shapiro.test(resid(mC)))
png(out("fig_modelC_diagnostics.png"), width = 1200, height = 1000, res = 130)
par(mfrow = c(2, 2)); plot(mC); dev.off()

# ---- 3. Model comparison: in-sample fit and out-of-sample accuracy ----------
rmse <- function(a, p) sqrt(mean((a - p)^2, na.rm = TRUE))
mae  <- function(a, p) mean(abs(a - p), na.rm = TRUE)
comparison <- purrr::imap_dfr(models, function(m, nm) {
  p <- predict(m, newdata = test)
  tibble::tibble(
    model = nm, k = length(coef(m)) - 1,
    adj_R2_train = summary(m)$adj.r.squared,
    AIC = AIC(m),
    RMSE_test = rmse(test$INR_ret, p),
    MAE_test  = mae(test$INR_ret, p),
    R2_test   = 1 - sum((test$INR_ret - p)^2, na.rm = TRUE) /
                    sum((test$INR_ret - mean(train$INR_ret))^2),
    Direction_hit = mean(sign(p) == sign(test$INR_ret), na.rm = TRUE))
})
naive <- tibble::tibble(model = "Naive (train mean)", k = 0,
  adj_R2_train = NA, AIC = NA,
  RMSE_test = rmse(test$INR_ret, mean(train$INR_ret)),
  MAE_test  = mae(test$INR_ret, mean(train$INR_ret)),
  R2_test = 0, Direction_hit = mean(sign(mean(train$INR_ret)) == sign(test$INR_ret)))
comparison <- bind_rows(comparison, naive)
cat("\nModel comparison (test = 2023 onward):\n"); print(comparison, width = Inf)
readr::write_csv(comparison, out("model_comparison.csv"))

# ---- 4. Driver scorecard: standardised coefficients of model C --------------
zvars <- all.vars(f$C)[-1]
train_z <- train |> mutate(across(all_of(c("INR_ret", zvars)), ~ as.numeric(scale(.x))))
mZ <- lm(f$C, data = train_z)
nw <- lmtest::coeftest(mZ, vcov = sandwich::NeweyWest(mZ))
scorecard <- tibble::tibble(
  driver = rownames(nw)[-1], beta_std = nw[-1, 1], se = nw[-1, 2],
  p_value = nw[-1, 4]) |>
  mutate(ci_low = beta_std - 1.96 * se, ci_high = beta_std + 1.96 * se,
         effect = ifelse(beta_std > 0, "Weakens rupee", "Strengthens rupee"),
         significant = p_value < 0.05) |>
  arrange(desc(abs(beta_std)))
cat("\nDriver scorecard (standardised betas, Newey-West SEs):\n"); print(scorecard)
readr::write_csv(scorecard, out("driver_scorecard.csv"))

p <- ggplot(scorecard, aes(reorder(driver, abs(beta_std)), beta_std,
                           colour = significant)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_pointrange(aes(ymin = ci_low, ymax = ci_high)) + coord_flip() +
  labs(title = "Rupee driver scorecard (Model C, standardised)",
       subtitle = "Positive = associated with rupee depreciation; bars = 95% CI",
       x = NULL, y = "Standardised coefficient") + theme_minimal(base_size = 12)
ggsave(out("fig_driver_scorecard.png"), p, width = 9, height = 5, dpi = 150)

# ---- 5. Actual vs fitted on the test period ----------------------------------
test$pred_C <- predict(mC, newdata = test)
p2 <- ggplot(test, aes(date)) +
  geom_col(aes(y = INR_ret), fill = "grey70") +
  geom_line(aes(y = pred_C), colour = "#c0392b", linewidth = 1) +
  labs(title = "Out-of-sample: actual (bars) vs Model C estimate (line)",
       x = NULL, y = "% change in USD/INR") + theme_minimal(base_size = 12)
ggsave(out("fig_test_actual_vs_pred.png"), p2, width = 10, height = 5, dpi = 150)

# Refit the chosen model on ALL data for the dashboard simulator
final_model <- lm(f$C, data = md)
saveRDS(list(models = models, final = final_model, comparison = comparison,
             scorecard = scorecard), out("regression_models.rds"))
sink()
