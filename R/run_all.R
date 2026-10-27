# =============================================================================
# run_all.R  -  full pipeline, run from the project folder:
#   Rscript R/run_all.R          (or source("R/run_all.R") in RStudio)
# =============================================================================
steps <- c("R/01_fetch_data.R", "R/02_build_dataset.R", "R/03_descriptive_inferential.R",
           "R/04_regression.R", "R/05_classification.R", "R/06_clustering_rules.R",
           "R/07_scenario.R")
for (s in steps) {
  message("\n==================== ", s, " ====================")
  source(s, local = new.env())
}
message("\nPipeline complete. Optional live update: source('R/08_realtime_refresh.R')",
        "\nLaunch the dashboard: shiny::runApp()")
