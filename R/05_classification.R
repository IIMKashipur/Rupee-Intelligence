# =============================================================================
# 05_classification.R  -  Sessions 12-14: Rupee Stress Monitor
# Target: High_Pressure = month's depreciation above the TRAIN 75th percentile
# Two set-ups, reported separately and labelled honestly:
#   Early warning : uses only LAST month's data  (a true forecast)
#   Nowcast       : uses the SAME month's drivers (explains, cannot forecast)
# Methods: logistic regression, LDA, decision tree, SVM + confusion matrices
# =============================================================================
source("R/00_config.R")
md  <- readr::read_csv(file.path(DIR_PROCESSED, "model_data.csv"), show_col_types = FALSE)
out <- function(f) file.path(DIR_OUTPUT, f)
sink(out("05_classification.txt"), split = TRUE)
set.seed(2026)  # only fixes SVM's internal cross-validation; no data is generated

md <- md |> mutate(High_Pressure = factor(High_Pressure, levels = c("Normal", "High"))) |>
  drop_na(L1_FPI, L1_INR_ret, L1_INR_vol, L1_Brent_ret, L1_USD_ret, L1_VIX_chg,
          L1_Reserves_chg, Brent_ret, USD_ret, FPI, VIX_chg, d_Rate_diff,
          d_Trade_Bal, Infl_diff)
train <- md |> filter(date <= TRAIN_END)
test  <- md |> filter(date >= TEST_START)
cat("Class balance (train):\n"); print(table(train$High_Pressure))
cutoff <- mean(train$High_Pressure == "High")   # prior share as decision cutoff

setups <- list(
  EarlyWarning = High_Pressure ~ L1_INR_ret + L1_INR_vol + L1_Brent_ret +
                                 L1_USD_ret + L1_FPI + L1_VIX_chg + L1_Reserves_chg,
  Nowcast      = High_Pressure ~ Brent_ret + USD_ret + FPI + VIX_chg +
                                 d_Rate_diff + d_Trade_Bal + Infl_diff
)

evaluate <- function(prob, truth, label) {
  # Align lengths; drop NA probs (e.g. incomplete SVM attribute)
  ok <- !is.na(prob) & !is.na(truth)
  if (sum(ok) < 5) {
    cat("\n---", label, "--- SKIPPED (too few non-NA predictions)\n")
    return(tibble::tibble(model = label, accuracy = NA_real_, sensitivity = NA_real_,
                          specificity = NA_real_, precision = NA_real_,
                          balanced_acc = NA_real_, AUC = NA_real_))
  }
  prob <- as.numeric(prob[ok]); truth <- truth[ok]
  pred <- factor(ifelse(prob > cutoff, "High", "Normal"), levels = c("Normal", "High"))
  truth <- factor(truth, levels = c("Normal", "High"))
  cm   <- caret::confusionMatrix(pred, truth, positive = "High")
  auc  <- tryCatch(as.numeric(pROC::auc(pROC::roc(truth, prob, quiet = TRUE))),
                   error = function(e) NA_real_)
  cat("\n---", label, "---\n"); print(cm$table)
  tibble::tibble(model = label, accuracy = unname(cm$overall["Accuracy"]),
                 sensitivity = unname(cm$byClass["Sensitivity"]),
                 specificity = unname(cm$byClass["Specificity"]),
                 precision   = unname(cm$byClass["Pos Pred Value"]),
                 balanced_acc = unname(cm$byClass["Balanced Accuracy"]), AUC = auc)
}

prob_high <- function(mat_or_vec) {
  if (is.null(mat_or_vec)) return(rep(NA_real_, nrow(test)))
  if (is.vector(mat_or_vec) && !is.matrix(mat_or_vec)) return(as.numeric(mat_or_vec))
  if ("High" %in% colnames(mat_or_vec)) return(as.numeric(mat_or_vec[, "High"]))
  # e1071 sometimes returns columns in factor order without reliable names
  as.numeric(mat_or_vec[, ncol(mat_or_vec)])
}

results <- list(); fitted_models <- list()
for (s in names(setups)) {
  fo <- setups[[s]]
  cat("\n#################", s, "#################\n")

  logit <- glm(fo, data = train, family = binomial)
  print(summary(logit))
  cat("Odds ratios:\n"); print(round(exp(coef(logit)), 3))
  results[[length(results) + 1]] <- evaluate(
    predict(logit, test, type = "response"), test$High_Pressure, paste(s, "- Logistic"))

  lda_m <- MASS::lda(fo, data = train)
  results[[length(results) + 1]] <- evaluate(
    predict(lda_m, test)$posterior[, "High"], test$High_Pressure, paste(s, "- LDA"))

  tree <- rpart::rpart(fo, data = train, method = "class",
                       control = rpart::rpart.control(cp = 0.01, minbucket = 8))
  best_cp <- tree$cptable[which.min(tree$cptable[, "xerror"]), "CP"]
  tree <- rpart::prune(tree, cp = best_cp)
  png(out(paste0("fig_tree_", s, ".png")), width = 1100, height = 800, res = 130)
  rpart.plot::rpart.plot(tree, main = paste("Decision tree -", s), extra = 104)
  dev.off()
  results[[length(results) + 1]] <- evaluate(
    prob_high(predict(tree, test, type = "prob")), test$High_Pressure, paste(s, "- Tree"))

  # e1071::svm chokes on extra NA columns in newdata; pass model-frame columns only
  svm_vars <- all.vars(fo)
  train_df <- as.data.frame(train[, svm_vars, drop = FALSE])
  test_df  <- as.data.frame(test[,  svm_vars, drop = FALSE])
  rownames(test_df) <- as.character(seq_len(nrow(test_df)))
  svm_m <- e1071::svm(fo, data = train_df, kernel = "radial", probability = TRUE,
                      scale = TRUE, na.action = na.omit)
  sp <- tryCatch({
    pr <- predict(svm_m, newdata = test_df, probability = TRUE, na.action = na.fail)
    stopifnot(length(pr) == nrow(test_df))
    prob_high(attr(pr, "probabilities"))
  }, error = function(e) {
    warning("SVM probs failed: ", e$message); rep(NA_real_, nrow(test))
  })
  results[[length(results) + 1]] <- evaluate(sp, test$High_Pressure, paste(s, "- SVM"))

  fitted_models[[s]] <- list(logit = logit, lda = lda_m, tree = tree, svm = svm_m)
}

res <- bind_rows(results)
cat("\nTest-period performance (2023 onward):\n"); print(res, width = Inf)
readr::write_csv(res, out("classification_results.csv"))

# Month-by-month stress probabilities for the dashboard (nowcast logistic)
all_prob <- md |> mutate(
  p_high_early = predict(fitted_models$EarlyWarning$logit, md, type = "response"),
  p_high_now   = predict(fitted_models$Nowcast$logit,      md, type = "response"),
  set = ifelse(date <= TRAIN_END, "Train", "Test")) |>
  select(date, USDINR, INR_ret, High_Pressure, p_high_early, p_high_now, set)
readr::write_csv(all_prob, out("stress_probabilities.csv"))
saveRDS(list(models = fitted_models, results = res, cutoff = cutoff),
        out("classification_models.rds"))

# ---- Appendix: 3-class labels from the proposal (Stable / Moderate / High) --
# Main Stress Monitor stays binary (train 75th percentile). This tree is only
# so Sessions 12-14 match the proposal wording; it is not used for forecasting.
md3 <- md |> mutate(
  Pressure3 = cut(INR_ret,
                  breaks = quantile(train$INR_ret, c(0, 0.50, 0.75, 1), na.rm = TRUE),
                  labels = c("Stable", "Moderate", "High"),
                  include.lowest = TRUE)
)
train3 <- md3 |> filter(date <= TRAIN_END)
test3  <- md3 |> filter(date >= TEST_START)
cat("\n################# Appendix: 3-class pressure (proposal labels) #################\n")
cat("Train class counts:\n"); print(table(train3$Pressure3))
tree3 <- rpart::rpart(
  Pressure3 ~ Brent_ret + USD_ret + FPI + VIX_chg + d_Rate_diff + d_Trade_Bal + Infl_diff,
  data = train3, method = "class",
  control = rpart::rpart.control(cp = 0.01, minbucket = 8))
png(out("fig_tree_Pressure3.png"), width = 1100, height = 800, res = 130)
rpart.plot::rpart.plot(tree3, main = "Decision tree - 3-class pressure (appendix)", extra = 104)
dev.off()
pred3 <- predict(tree3, test3, type = "class")
cm3 <- caret::confusionMatrix(pred3, test3$Pressure3)
cat("\nTest confusion matrix (3-class nowcast tree):\n"); print(cm3$table)
cat("Accuracy:", round(cm3$overall["Accuracy"], 3), "\n")
readr::write_csv(
  tibble::tibble(date = test3$date, actual = as.character(test3$Pressure3),
                 predicted = as.character(pred3)),
  out("classification_3class_test.csv"))
sink()
