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

## two metrics on very different scales, with a transient at time 100 before the later times
overviewEnv <- function() {
  g <- expand.grid(time = c(100, 200, 300), metric = c("ai", "area_mn"), stringsAsFactors = FALSE)
  base <- ifelse(g$metric == "ai", 10, 5000) * ifelse(g$time == 100, 5, 1)
  data.frame(time = g$time, poly = "ELF", metric = g$metric, mean = base, min = base - 2, max = base + 2)
}

test_that("the NRV range spans every summary time, not only the last of them", {
  r <- .nrvRange(overviewEnv(), period = c(100, 300))
  r <- r[r$metric == "ai", ]
  expect_equal(c(r$lo, r$hi), c(8, 52)) ## the time-100 envelope is part of the NRV
  expect_equal(r$mid, mean(c(50, 10, 10)))
  ## times outside the summary period are not
  r2 <- .nrvRange(overviewEnv(), period = c(200, 300))
  expect_equal(c(r2$lo[r2$metric == "ai"], r2$hi[r2$metric == "ai"]), c(8, 12))
})

test_that("the overview is on each metric's real scale, one facet per metric", {
  cc <- data.frame(poly = "ELF", metric = c("ai", "area_mn"), mean = c(11, 20000))
  gg <- .currentConditionOverview(list(env = overviewEnv(), cc = cc, period = c(100, 300)))
  b <- ggplot2::ggplot_build(gg)
  expect_s3_class(gg$facet, "FacetWrap")
  expect_true(gg$facet$params$free$x)
  expect_equal(length(unique(b$layout$layout$PANEL)), 2L)
  x <- unlist(lapply(b$data, function(l) c(l$x, l$xmin, l$xend)))
  expect_true(all(c(8, 52, 11, 20000) %in% x)) ## raw min, max and current condition; not 0-1
  expect_gt(max(x), 1000)
  expect_true("current condition" %in% b$plot$scales$get_scales("colour")$get_labels())
})

test_that("the overview facets carry the full metric names", {
  cc <- data.frame(poly = "ELF", metric = c("ai", "area_mn"), mean = c(11, 20000))
  b <- ggplot2::ggplot_build(.currentConditionOverview(list(env = overviewEnv(), cc = cc, period = c(100, 300))))
  expect_setequal(as.character(b$layout$layout$panel), c("Aggregation index", "Mean patch area"))
})
