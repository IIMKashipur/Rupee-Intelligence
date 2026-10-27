# =============================================================================
# 06_clustering_rules.R  -  Sessions 15-16: unsupervised learning
#  (1) k-means + hierarchical clustering -> "currency regimes"
#  (2) Association rules (Apriori) -> which conditions co-occur with a weak rupee
#      (market-basket analysis where each month is a "basket" of conditions)
# =============================================================================
source("R/00_config.R")
md  <- readr::read_csv(file.path(DIR_PROCESSED, "model_data.csv"), show_col_types = FALSE)
out <- function(f) file.path(DIR_OUTPUT, f)
sink(out("06_clustering_rules.txt"), split = TRUE)
set.seed(2026)  # fixes k-means starting centres only; no data is generated

# ---- 1. Clustering ----------------------------------------------------------
feat <- c("INR_ret", "INR_vol", "Brent_ret", "USD_ret", "FPI", "VIX_chg")
X <- scale(md[, feat])

png(out("fig_kmeans_elbow_silhouette.png"), width = 1400, height = 600, res = 130)
gridExtra_ok <- requireNamespace("gridExtra", quietly = TRUE)
p_elbow <- factoextra::fviz_nbclust(X, kmeans, method = "wss", k.max = 8)
p_sil   <- factoextra::fviz_nbclust(X, kmeans, method = "silhouette", k.max = 8)
if (gridExtra_ok) gridExtra::grid.arrange(p_elbow, p_sil, ncol = 2) else print(p_sil)
dev.off()

sil_width <- sapply(2:6, function(k) {
  km <- kmeans(X, centers = k, nstart = 50)
  mean(cluster::silhouette(km$cluster, dist(X))[, 3])
})
k_best <- (2:6)[which.max(sil_width)]
cat("Average silhouette by k (2-6):", round(sil_width, 3), "-> chosen k =", k_best, "\n")

km <- kmeans(X, centers = k_best, nstart = 50)
md$Cluster_km <- factor(km$cluster)

hc <- hclust(dist(X), method = "ward.D2")
md$Cluster_hc <- factor(cutree(hc, k = k_best))
png(out("fig_dendrogram.png"), width = 1400, height = 700, res = 130)
plot(hc, labels = format(md$date, "%b-%y"), cex = 0.4,
     main = "Hierarchical clustering of months (Ward)")
rect.hclust(hc, k = k_best, border = 2:(k_best + 1))
dev.off()
cat("\nAgreement between k-means and hierarchical clusters:\n")
print(table(kmeans = md$Cluster_km, hierarchical = md$Cluster_hc))

profile <- md |> group_by(Cluster_km) |>
  summarise(months = n(), across(all_of(feat), mean), .groups = "drop")
cat("\nCluster profiles (means, original units):\n"); print(profile, width = Inf)
readr::write_csv(profile, out("cluster_profiles.csv"))
readr::write_csv(md |> select(date, USDINR, INR_ret, Cluster_km, Cluster_hc),
                 out("month_clusters.csv"))

p <- factoextra::fviz_cluster(km, data = X, geom = "point", ellipse.type = "convex",
                              main = "Currency regimes (k-means, PCA view)")
ggsave(out("fig_kmeans_clusters.png"), p, width = 8, height = 6, dpi = 150)

# ---- 2. Association rules ---------------------------------------------------
suppressPackageStartupMessages(library(arules))  # needed for as(..., "transactions")
select <- dplyr::select
tercile <- function(x, lab) cut(x, quantile(x, c(0, 1/3, 2/3, 1)),
                                labels = paste0(lab, "=", c("Low", "Mid", "High")),
                                include.lowest = TRUE)
items <- md |> transmute(
  Rupee  = cut(INR_ret, quantile(INR_ret, c(0, 1/3, 2/3, 1)),
               labels = c("Rupee=Strong", "Rupee=Stable", "Rupee=Weak"),
               include.lowest = TRUE),
  Oil    = tercile(Brent_ret, "OilChange"),
  Dollar = tercile(USD_ret,   "DollarChange"),
  Flows  = tercile(FPI,       "FPI"),
  Risk   = tercile(VIX_chg,   "VIXChange"),
  Rates  = tercile(d_Rate_diff, "RateGapChange"),
  Trade  = tercile(d_Trade_Bal, "TradeBalChange"))
trans <- as(lapply(seq_len(nrow(items)), function(i) as.character(unlist(items[i, ]))),
            "transactions")
cat("\nFrequent itemsets (support >= 0.10):\n")
fi <- arules::apriori(trans, parameter = list(target = "frequent itemsets",
                                               support = 0.10, minlen = 2))
arules::inspect(head(sort(fi, by = "support"), 10))

rules <- arules::apriori(trans,
  parameter  = list(support = 0.05, confidence = 0.5, minlen = 2, maxlen = 4),
  appearance = list(rhs = "Rupee=Weak", default = "lhs"))
rules <- sort(rules, by = "lift")
cat("\nRules that end in Rupee=Weak (sorted by lift):\n")
arules::inspect(head(rules, 15))
readr::write_csv(as(head(rules, 30), "data.frame"), out("association_rules.csv"))
sink()
