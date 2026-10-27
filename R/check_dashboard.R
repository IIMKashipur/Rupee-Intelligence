# Quick non-interactive check that every Shiny input exists and tabs are present.
files <- c(
  "data/processed/rupee_monthly.csv", "data/processed/provenance.csv",
  "data/processed/data_quality_log.csv", "data/processed/model_data.csv",
  "output/driver_scorecard.csv", "output/model_comparison.csv",
  "output/stress_probabilities.csv", "output/classification_results.csv",
  "output/month_clusters.csv", "output/cluster_profiles.csv",
  "output/association_rules.csv", "output/regression_models.rds",
  "data/live/live_quotes.csv", "data/live/nowcast.csv"
)
miss <- files[!file.exists(files)]
if (length(miss)) stop("Missing dashboard inputs:\n", paste(miss, collapse = "\n"))

txt <- paste(readLines("app.R"), collapse = "\n")
tabs <- regmatches(txt, gregexpr('nav_panel\\("[^"]+"', txt))[[1]]
tabs <- gsub('nav_panel\\("|\"', "", tabs)
message("Tabs (", length(tabs), "): ", paste(tabs, collapse = " | "))
stopifnot(length(tabs) == 7)
message("DASHBOARD_OK")
