## The current condition is drawn on the envelope figures and summarised in one overview figure.

envelope <- function(classes = c("Pine", "Spruce")) {
  g <- expand.grid(time = c(100, 200, 300), class = classes, stringsAsFactors = FALSE)
  base <- ifelse(g$class == "Pine", 10, 50)
  data.frame(time = g$time, poly = "ELF", class = g$class, metric = "area_mn", metric.1 = NA_character_,
             mean = base, min = base - 2, max = base + 2, q25 = base - 1, median = base, q75 = base + 1)
}
ccFor <- function(classes, values) {
  data.frame(poly = "ELF", class = classes, metric = "area_mn", metric.1 = NA_character_, mean = values)
}

test_that("the current condition is a labelled line in the panel of its class", {
  facet <- c("class", "metric.1")
  for (type in c("ribbon", "boxplot")) {
    gg <- nrvtools::plot_nrv_envelope(envelope(), type = type, facet = facet)
    gg <- .addCurrentCondition(gg, ccFor(c("Pine", "Spruce"), c(12, 47)), facet)
    b <- ggplot2::ggplot_build(gg)
    hl <- b$data[[length(b$data)]] ## the last layer is the line
    expect_equal(nrow(hl), 2L)
    ## each panel's line is the current condition of the class drawn in that panel (Pine's envelope
    ## tops out at 12, Spruce's at 52)
    top <- sapply(split(b$data[[1]]$ymax, b$data[[1]]$PANEL), max)
    expect_equal(hl$yintercept[match(names(top), hl$PANEL)], unname(ifelse(top == 12, 12, 47)))
    expect_true("current condition" %in% b$plot$scales$get_scales("colour")$get_labels())
  }
})

test_that("with a single panel the line is still drawn", {
  gg <- nrvtools::plot_nrv_envelope(envelope("Pine"), type = "ribbon", facet = c("class", "metric.1"))
  gg <- .addCurrentCondition(gg, ccFor("Pine", 11), c("class", "metric.1"))
  hl <- ggplot2::ggplot_build(gg)$data[[3]]
  expect_equal(hl$yintercept, 11)
})

test_that("no current condition leaves the figure unchanged", {
  gg <- nrvtools::plot_nrv_envelope(envelope(), type = "ribbon", facet = "class")
  expect_identical(.addCurrentCondition(gg, NULL, "class"), gg)
})

test_that("the overview puts every metric on one 0-1 axis, and shows what is outside the NRV", {
  env <- rbind(
    transform(envelope("Pine")[, c("time", "poly", "metric", "mean", "min", "max")], metric = "m_in"),
    transform(envelope("Pine")[, c("time", "poly", "metric", "mean", "min", "max")], metric = "m_out")
  )
  ## NRV range of each metric is 8 to 12; the mean is 10
  cc <- data.frame(poly = "ELF", metric = c("m_in", "m_out"), mean = c(11, 20))
  gg <- .currentConditionOverview(list(env = env, cc = cc))
  d <- gg$data
  expect_equal(d$ccPos[d$metric == "m_in"], 0.75)
  expect_equal(d$ccPos[d$metric == "m_out"], 3)  ## outside the envelope: beyond 1
  expect_equal(d$midPos, c(0.5, 0.5))
  expect_s3_class(gg, "ggplot")
  expect_no_error(ggplot2::ggplot_build(gg))
})
