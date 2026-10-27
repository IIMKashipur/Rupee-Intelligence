# =============================================================================
# 01_fetch_data.R  -  download every series from its official source
# Output: data/raw/*  (untouched files)  +  data/processed/provenance.csv
# =============================================================================
source("R/00_config.R")

UA <- httr::user_agent("Mozilla/5.0 (IIM Kashipur EMBA BI&BA academic project)")
# FRED's CDN sometimes resets HTTP/2 streams; force HTTP/1.1 and retry.
http11 <- httr::config(http_version = 2L)  # 2L = HTTP/1.1 in libcurl
get_retry <- function(url, ..., times = 4) {
  last <- NULL
  for (i in seq_len(times)) {
    last <- tryCatch(
      httr::GET(url, UA, http11, httr::timeout(60), ...),
      error = function(e) e)
    if (!inherits(last, "error") && !httr::http_error(last)) return(last)
    Sys.sleep(min(2^i, 8))
  }
  if (inherits(last, "error")) stop(last)
  httr::stop_for_status(last)
}
provenance <- list()

log_source <- function(column, source, series_id, url, n, first, last, note = "") {
  provenance[[length(provenance) + 1]] <<- tibble::tibble(
    column, source, series_id, url = gsub("api_key=[^&]+", "api_key=***", url),
    rows = n, first_obs = as.character(first), last_obs = as.character(last),
    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), note
  )
}

# ---- 1. FRED -----------------------------------------------------------------
# Prefer the official FRED API when FRED_API_KEY is set. Otherwise download the
# public fredgraph.csv. R/httr often hangs on FRED's CDN, so CSV downloads go
# through a short Python helper (same official URL, same bytes).
fetch_fred_csv_python <- function(id, start, dest) {
  py <- sprintf(paste(
    "import ssl, urllib.request",
    "try:\n import certifi\n ctx=ssl.create_default_context(cafile=certifi.where())",
    "except Exception:\n ctx=ssl._create_unverified_context()",
    "url=%s",
    "req=urllib.request.Request(url, headers={'User-Agent':'IIMKashipur-BIBA'})",
    "data=urllib.request.urlopen(req, timeout=90, context=ctx).read()",
    "open(%s,'wb').write(data)",
    "print(len(data))",
    sep = "\n"),
    shQuote(sprintf("https://fred.stlouisfed.org/graph/fredgraph.csv?id=%s&cosd=%s", id, start), type = "cmd"),
    shQuote(normalizePath(dest, mustWork = FALSE), type = "cmd"))
  status <- system2("python3", c("-c", py), stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(status, "status")) && attr(status, "status") != 0)
    stop("Python FRED download failed for ", id, ": ", paste(status, collapse = " "))
  invisible
}

fetch_fred <- function(id, start = START_DATE) {
  if (nzchar(FRED_API_KEY)) {
    url <- sprintf(paste0("https://api.stlouisfed.org/fred/series/observations?",
                          "series_id=%s&api_key=%s&file_type=json&observation_start=%s"),
                   id, FRED_API_KEY, start)
    res <- tryCatch(get_retry(url), error = function(e) e)
    if (!inherits(res, "error") && !httr::http_error(res)) {
      txt <- httr::content(res, "text", encoding = "UTF-8")
      writeLines(txt, file.path(DIR_RAW, paste0("fred_", id, ".json")))
      obs <- jsonlite::fromJSON(txt)$observations
      df  <- tibble::tibble(date = as.Date(obs$date),
                            value = suppressWarnings(as.numeric(obs$value)))
      df <- df |> filter(!is.na(date), !is.na(value), date >= start)
      if (nrow(df) > 0) { attr(df, "url") <- url; return(df) }
    }
    message("FRED API unavailable for ", id, "; falling back to public CSV via Python")
  }
  url  <- sprintf("https://fred.stlouisfed.org/graph/fredgraph.csv?id=%s&cosd=%s", id, start)
  dest <- file.path(DIR_RAW, paste0("fred_", id, ".csv"))
  # Reuse a fresh local CSV if present (Gate-1 freeze / offline re-runs)
  if (!file.exists(dest) || file.info(dest)$size < 50) {
    fetch_fred_csv_python(id, start, dest)
  }
  df <- readr::read_csv(dest, col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  names(df)[1:2] <- c("date", "value")
  df <- df |> transmute(date = as.Date(date),
                        value = suppressWarnings(as.numeric(value)))
  df <- df |> filter(!is.na(date), !is.na(value), date >= start)
  if (nrow(df) == 0) stop("FRED returned no observations for ", id)
  attr(df, "url") <- url
  df
}

fred_raw <- list()
for (i in seq_len(nrow(fred_series))) {
  s <- fred_series[i, ]
  message("FRED  ", s$fred_id, "  ->  ", s$column)
  df <- fetch_fred(s$fred_id)
  fred_raw[[s$column]] <- df
  log_source(s$column, "FRED (St. Louis Fed)", s$fred_id, attr(df, "url"),
             nrow(df), min(df$date), max(df$date), s$description)
  Sys.sleep(0.5)                                   # be polite to the server
}
saveRDS(fred_raw, file.path(DIR_RAW, "fred_raw.rds"))

# ---- 2. World Bank Pink Sheet (Brent cross-check) ---------------------------
fetch_wb_brent <- function() {
  f   <- file.path(DIR_RAW, "wb_pink_sheet_monthly.xlsx")
  res <- httr::GET(WB_PINK_SHEET_URL, UA, httr::write_disk(f, overwrite = TRUE))
  if (httr::http_error(res)) {
    warning("World Bank Pink Sheet download failed (HTTP ", httr::status_code(res),
            "). Update WB_PINK_SHEET_URL in 00_config.R. Brent from FRED is still used.")
    return(NULL)
  }
  sheets <- readxl::excel_sheets(f)
  sheet  <- sheets[grepl("Monthly Prices", sheets, ignore.case = TRUE)][1]
  raw    <- readxl::read_excel(f, sheet = sheet, col_names = FALSE,
                               .name_repair = "minimal")
  raw    <- as.data.frame(lapply(raw, as.character))
  hit    <- which(apply(raw, 1, function(r) any(grepl("Crude oil, Brent", r, fixed = TRUE))))[1]
  col    <- which(grepl("Crude oil, Brent", unlist(raw[hit, ]), fixed = TRUE))[1]
  out <- tibble::tibble(period = raw[[1]], value = raw[[col]]) |>
    filter(grepl("^\\d{4}M\\d{2}$", period)) |>
    transmute(date  = as.Date(paste0(substr(period, 1, 4), "-", substr(period, 6, 7), "-01")),
              value = suppressWarnings(as.numeric(value))) |>
    filter(!is.na(value), date >= START_DATE)
  log_source("Brent_WB", "World Bank Pink Sheet", "Crude oil, Brent ($/bbl)",
             WB_PINK_SHEET_URL, nrow(out), min(out$date), max(out$date),
             "Cross-check for FRED/EIA Brent")
  out
}
wb_brent <- tryCatch(fetch_wb_brent(), error = function(e) { warning(e$message); NULL })
if (!is.null(wb_brent)) saveRDS(wb_brent, file.path(DIR_RAW, "wb_brent.rds"))

# ---- 3. FPI flows (NSDL) -----------------------------------------------------
# Strategy: (a) manual CSV if present, (b) scrape NSDL year by year.
# Manual CSV format  data/manual/fpi_monthly.csv
#   month,fpi_equity,fpi_debt,fpi_total,unit
#   2012-01,1234.5,-210.0,1024.5,INR_cr
# Copy figures exactly from the NSDL "Monthly FPI Net Investments" table.
fetch_nsdl_year <- function(year) {
  s    <- rvest::session(NSDL_FPI_URL, UA)
  form <- rvest::html_form(s)[[1]]
  flds <- names(form$fields)
  yr_field <- flds[grepl("year|yr|ddl", flds, ignore.case = TRUE)][1]
  if (is.na(yr_field)) stop("Could not find the year selector on the NSDL page")
  form <- do.call(rvest::html_form_set,
                  c(list(form), stats::setNames(list(as.character(year)), yr_field)))
  page <- rvest::session_submit(s, form)
  tabs <- rvest::html_elements(page, "table")
  months <- month.name
  rows <- list()
  for (tb in tabs) {
    for (tr in rvest::html_elements(tb, "tr")) {
      cells <- rvest::html_text2(rvest::html_elements(tr, "td"))
      if (length(cells) >= 3 && trimws(cells[1]) %in% months) {
        nums <- readr::parse_number(cells[-1])
        rows[[length(rows) + 1]] <- tibble::tibble(
          month = sprintf("%d-%02d", year, match(trimws(cells[1]), months)),
          fpi_equity = nums[1],
          fpi_debt   = sum(nums[2:min(4, length(nums) - 1)], na.rm = TRUE),
          fpi_total  = nums[length(nums)],
          unit = "INR_cr")
      }
    }
  }
  if (length(rows) == 0) stop("No monthly rows parsed for ", year)
  dplyr::bind_rows(rows) |> distinct(month, .keep_all = TRUE)
}

manual_fpi <- file.path(DIR_MANUAL, "fpi_monthly.csv")
if (file.exists(manual_fpi)) {
  fpi <- readr::read_csv(manual_fpi, col_types = "cdddc")
  log_source("FPI", "NSDL (manual copy)", "Monthly FPI Net Investments", NSDL_FPI_URL,
             nrow(fpi), min(fpi$month), max(fpi$month), "Copied from official table")
} else {
  yrs <- seq(year(START_DATE), year(Sys.Date()))
  fpi <- purrr::map_dfr(yrs, function(y) {
    message("NSDL FPI  ", y)
    tryCatch(fetch_nsdl_year(y), error = function(e) {
      warning("NSDL ", y, ": ", e$message); NULL })
  })
  if (nrow(fpi) == 0) {
    stop("FPI scrape failed. Copy the NSDL monthly table into ", manual_fpi,
         " (format in the comment above) and re-run. No values will be invented.")
  }
  readr::write_csv(fpi, file.path(DIR_RAW, "nsdl_fpi_scraped.csv"))
  log_source("FPI", "NSDL (scraped)", "Monthly FPI Net Investments", NSDL_FPI_URL,
             nrow(fpi), min(fpi$month), max(fpi$month), "INR crore, net")
}
saveRDS(fpi, file.path(DIR_RAW, "fpi.rds"))

# ---- 4. India CPI (headline, y/y) -------------------------------------------
# Priority: (a) manual CSV of MoSPI headline inflation, (b) MoSPI API,
# (c) FRED/OECD index (ends Mar 2025 - pipeline flags the gap, never fills it).
# Manual CSV  data/manual/india_cpi.csv :  month,india_cpi_yoy   (e.g. 2025-04,3.16)
# Values: all-India general CPI, combined, y/y % from MoSPI press releases.
fetch_mospi_cpi <- function() {
  user <- Sys.getenv("MOSPI_USER"); pass <- Sys.getenv("MOSPI_PASS")
  if (!nzchar(user) || !nzchar(pass)) return(NULL)
  base <- "https://api.mospi.gov.in"
  login <- httr::POST(paste0(base, "/api/login"), UA, encode = "json",
                      body = list(username = user, password = pass))
  httr::stop_for_status(login, "MoSPI login")
  tok <- httr::content(login)$token %||% httr::content(login)$access_token
  res <- httr::GET(paste0(base, "/api/cpi/getCPIIndex"), UA,
                   httr::add_headers(Authorization = paste("Bearer", tok)),
                   query = list(base_year = 2012, series = "Current",
                                year = paste(2011:year(Sys.Date()), collapse = ","),
                                format = "CSV"))
  httr::stop_for_status(res, "MoSPI CPI")
  txt <- httr::content(res, "text", encoding = "UTF-8")
  writeLines(txt, file.path(DIR_RAW, "mospi_cpi_raw.csv"))
  message("MoSPI CPI raw saved. Inspect column names, then filter to ",
          "State = All India, Sector = Combined, Group = General in 02_build_dataset.R")
  readr::read_csv(I(txt), show_col_types = FALSE)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

manual_cpi <- file.path(DIR_MANUAL, "india_cpi.csv")
india_cpi <- NULL
if (file.exists(manual_cpi)) {
  india_cpi <- readr::read_csv(manual_cpi, col_types = "cd")
  log_source("India_CPI_yoy", "MoSPI (manual copy)", "All-India CPI combined y/y",
             "https://www.mospi.gov.in", nrow(india_cpi),
             min(india_cpi$month), max(india_cpi$month), "Headline inflation %")
} else {
  mospi <- tryCatch(fetch_mospi_cpi(), error = function(e) { warning(e$message); NULL })
  if (!is.null(mospi)) saveRDS(mospi, file.path(DIR_RAW, "mospi_cpi.rds"))
}
saveRDS(india_cpi, file.path(DIR_RAW, "india_cpi_manual.rds"))

# ---- 5. Save provenance ------------------------------------------------------
prov <- dplyr::bind_rows(provenance)
readr::write_csv(prov, file.path(DIR_PROCESSED, "provenance.csv"))
print(prov |> select(column, series_id, rows, first_obs, last_obs))
message("Done. Raw files are in ", DIR_RAW)
