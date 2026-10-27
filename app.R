# =============================================================================
# app.R  -  Rupee Intelligence Dashboard (Shiny)
# Run from the project folder:  shiny::runApp()
# Reads only files produced by the pipeline (all real, official data).
# =============================================================================
library(shiny); library(bslib); library(plotly); library(DT)
library(dplyr); library(readr); library(lubridate)
select <- dplyr::select

P  <- function(...) file.path(...)
rd <- function(f) if (file.exists(f)) read_csv(f, show_col_types = FALSE) else NULL

df        <- rd(P("data/processed/rupee_monthly.csv"))
prov      <- rd(P("data/processed/provenance.csv"))
dq        <- rd(P("data/processed/data_quality_log.csv"))
score     <- rd(P("output/driver_scorecard.csv"))
comp      <- rd(P("output/model_comparison.csv"))
stress    <- rd(P("output/stress_probabilities.csv"))
cls_res   <- rd(P("output/classification_results.csv"))
clusters  <- rd(P("output/month_clusters.csv"))
cprof     <- rd(P("output/cluster_profiles.csv"))
rules     <- rd(P("output/association_rules.csv"))
live      <- rd(P("data/live/live_quotes.csv"))
nowcast   <- rd(P("data/live/nowcast.csv"))
reg       <- readRDS(P("output/regression_models.rds"))
if (is.null(df)) stop("Run R/run_all.R first - no processed data found.")

source(P("R/00_config.R"), local = TRUE)   # shock_events, constants
latest <- df |> filter(!is.na(USDINR)) |> slice_max(date, n = 1)
md     <- rd(P("data/processed/model_data.csv"))

kpi <- function(title, value, sub = NULL) value_box(title = title, value = value,
                                                    p(sub), theme = "primary")

ui <- page_navbar(
  title = "What Really Drives the Rupee?",
  theme = bs_theme(version = 5, bootswatch = "flatly"),

  nav_panel("Overview",
    layout_columns(
      kpi("USD/INR (monthly avg)", sprintf("%.2f", latest$USDINR), format(latest$date, "%b %Y, FRED")),
      kpi("Live USD/INR", if (!is.null(live)) sprintf("%.2f", tail(live$close[live$series == "USDINR"], 1)) else "run refresh",
          if (!is.null(live)) paste("Yahoo Finance,", max(live$date)) else ""),
      kpi("Month-to-date model estimate",
          if (!is.null(nowcast)) sprintf("%+.2f%%", nowcast$model_estimate_pct) else "run refresh",
          if (!is.null(nowcast)) sprintf("Actual so far %+.2f%%", nowcast$actual_mtd_pct) else ""),
      kpi("Forex reserves", sprintf("$%.0f bn", tail(na.omit(df$Reserves_bn), 1)), "excl. gold, IMF")
    ),
    card(card_header("USD/INR since 2010 - shaded bands are major shocks"),
         plotlyOutput("p_trend", height = 420))
  ),

  nav_panel("Shock Explorer",
    layout_sidebar(
      sidebar = sidebar(selectInput("event", "Event", shock_events$event),
                        sliderInput("win", "Months before / after", 1, 12, c(3, 6))),
      card(card_header("Indexed to 100 at the start of the event"),
           plotlyOutput("p_shock", height = 450)))
  ),

  nav_panel("Driver Scorecard",
    layout_columns(col_widths = c(7, 5),
      card(card_header("Standardised effect on monthly USD/INR change (Model C, 95% CI)"),
           plotlyOutput("p_score", height = 420)),
      card(card_header("Is oil really the villain? Model comparison"),
           DTOutput("t_comp")))
  ),

  nav_panel("What-if Simulator",
    layout_sidebar(
      sidebar = sidebar(width = 320,
        sliderInput("s_oil", "Brent change this month (%)", -40, 40, 0, 1),
        sliderInput("s_usd", "Broad dollar change (%)", -5, 5, 0, 0.1),
        sliderInput("s_fpi", "Net FPI flow (US$ bn)", -15, 15, round(median(md$FPI), 1), 0.5),
        sliderInput("s_rate", "Change in India-US rate gap (pp)", -1, 1, 0, 0.05),
        sliderInput("s_trade", "Change in trade balance (US$ bn)", -10, 10, 0, 0.5),
        sliderInput("s_infl", "India minus US inflation (pp)", -3, 8,
                    round(tail(md$Infl_diff, 1), 1), 0.1)),
      layout_columns(uiOutput("sim_box1"), uiOutput("sim_box2")),
      card(p("Hypothetical estimate from Model C fitted on real 2012-latest data.",
             "It is a statistical association under the chosen assumptions, not a forecast."),
           plotlyOutput("p_sim", height = 300)))
  ),

  nav_panel("Stress Monitor",
    card(card_header("Probability of a high-depreciation month"),
         radioButtons("which_p", NULL, inline = TRUE,
                      c("Early warning (last month's data)" = "p_high_early",
                        "Nowcast (same-month drivers)" = "p_high_now")),
         plotlyOutput("p_stress", height = 380)),
    card(card_header("Test-period performance (2023 onward)"), DTOutput("t_cls"))
  ),

  nav_panel("Regimes & Rules",
    layout_columns(col_widths = c(6, 6),
      card(card_header("Currency regimes found by k-means"), plotlyOutput("p_clu", height = 380),
           DTOutput("t_cprof")),
      card(card_header("Conditions that co-occur with a weak rupee (Apriori)"), DTOutput("t_rules")))
  ),

  nav_panel("Data & Sources",
    card(card_header("Provenance - every column, its official source and download time"),
         DTOutput("t_prov")),
    card(card_header("Data-quality log (missing months are dropped, never filled)"),
         DTOutput("t_dq")))
)

server <- function(input, output, session) {

  output$p_trend <- renderPlotly({
    d <- df |> filter(!is.na(USDINR))
    shapes <- lapply(seq_len(nrow(shock_events)), function(i) list(
      type = "rect", xref = "x", yref = "paper", y0 = 0, y1 = 1, line = list(width = 0),
      x0 = shock_events$start[i], x1 = shock_events$end[i],
      fillcolor = "rgba(150,150,150,0.25)"))
    plot_ly(d, x = ~date, y = ~USDINR, type = "scatter", mode = "lines",
            line = list(color = "#1f4e79"), name = "USD/INR") |>
      layout(shapes = shapes, yaxis = list(title = "Rupees per US$"), xaxis = list(title = ""))
  })

  output$p_shock <- renderPlotly({
    ev <- shock_events |> filter(event == input$event)
    s  <- ev$start %m-% months(input$win[1]); e <- ev$start %m+% months(input$win[2])
    d  <- df |> filter(date >= s, date <= e) |>
      select(date, `USD/INR` = USDINR, Brent, `Broad dollar` = Broad_USD, `Reserves` = Reserves_bn) |>
      tidyr::pivot_longer(-date) |> group_by(name) |>
      mutate(index = 100 * value / value[date == floor_date(ev$start, "month")][1]) |> ungroup()
    plot_ly(d, x = ~date, y = ~index, color = ~name, type = "scatter", mode = "lines+markers") |>
      layout(yaxis = list(title = "Index (event start = 100)"), xaxis = list(title = ""),
             shapes = list(list(type = "line", x0 = ev$start, x1 = ev$start, yref = "paper",
                                y0 = 0, y1 = 1, line = list(dash = "dash"))))
  })

  output$p_score <- renderPlotly({
    s <- score |> arrange(abs(beta_std))
    plot_ly(s, x = ~beta_std, y = ~factor(driver, levels = driver), type = "scatter",
            mode = "markers", marker = list(size = 11, color = ifelse(s$significant, "#c0392b", "#7f8c8d")),
            error_x = list(type = "data", symmetric = FALSE,
                           array = s$ci_high - s$beta_std, arrayminus = s$beta_std - s$ci_low)) |>
      layout(xaxis = list(title = "Std. coefficient (+ = rupee weaker)", zeroline = TRUE),
             yaxis = list(title = ""))
  })
  output$t_comp <- renderDT(datatable(comp, rownames = FALSE, options = list(dom = "t")) |>
                              formatRound(3:8, 3))

  sim <- reactive({
    nd <- tibble::tibble(Brent_ret = input$s_oil, USD_ret = input$s_usd, FPI = input$s_fpi,
                         d_Rate_diff = input$s_rate, d_Trade_Bal = input$s_trade,
                         Infl_diff = input$s_infl)
    pr <- predict(reg$final, nd, interval = "prediction", level = 0.8)
    list(fit = pr[, "fit"], lo = pr[, "lwr"], hi = pr[, "upr"])
  })
  output$sim_box1 <- renderUI(kpi("Estimated monthly change in USD/INR",
    sprintf("%+.2f%%", sim()$fit), sprintf("80%% range %+.2f%% to %+.2f%%", sim()$lo, sim()$hi)))
  output$sim_box2 <- renderUI(kpi("Implied USD/INR from latest level",
    sprintf("%.2f", latest$USDINR * (1 + sim()$fit / 100)),
    sprintf("from %.2f (%s)", latest$USDINR, format(latest$date, "%b %Y"))))
  output$p_sim <- renderPlotly({
    plot_ly(x = c(sim()$fit), y = "Estimate", type = "bar", orientation = "h",
            error_x = list(type = "data", symmetric = FALSE,
                           array = sim()$hi - sim()$fit, arrayminus = sim()$fit - sim()$lo)) |>
      layout(xaxis = list(title = "% change in USD/INR", range = c(-6, 6)), yaxis = list(title = ""))
  })

  output$p_stress <- renderPlotly({
    d <- stress |> mutate(p = .data[[input$which_p]])
    plot_ly(d, x = ~date, y = ~p, type = "scatter", mode = "lines", name = "Probability",
            line = list(color = "#1f4e79")) |>
      add_markers(data = d |> filter(High_Pressure == "High"), x = ~date, y = ~p,
                  marker = list(color = "#c0392b", size = 7), name = "Actual high-pressure month") |>
      layout(yaxis = list(title = "P(high depreciation)", range = c(0, 1)),
             xaxis = list(title = ""),
             shapes = list(list(type = "line", x0 = TEST_START, x1 = TEST_START, yref = "paper",
                                y0 = 0, y1 = 1, line = list(dash = "dot"))))
  })
  output$t_cls <- renderDT(datatable(cls_res, rownames = FALSE, options = list(dom = "t", pageLength = 10)) |>
                             formatRound(2:7, 3))

  output$p_clu <- renderPlotly(plot_ly(clusters, x = ~date, y = ~INR_ret, color = ~factor(Cluster_km),
                                       type = "scatter", mode = "markers") |>
                                 layout(yaxis = list(title = "% change in USD/INR"), xaxis = list(title = "")))
  output$t_cprof <- renderDT(datatable(cprof, rownames = FALSE, options = list(dom = "t")) |>
                               formatRound(3:8, 2))
  output$t_rules <- renderDT(datatable(rules, rownames = FALSE, options = list(pageLength = 10)))
  output$t_prov  <- renderDT(datatable(prov, rownames = FALSE, options = list(pageLength = 20)))
  output$t_dq    <- renderDT(datatable(dq, rownames = FALSE, options = list(dom = "t")))
}

shinyApp(ui, server)
