## The stability check asks whether a series is still trending over the last part of the run.
## Series are synthetic: 5 reps x the summary times, one metric.

times <- seq(0, 1000, by = 100)
window <- c(500, 1000)
keys <- "metric"

makeSeries <- function(f, sd = 0, reps = 1:5, metric = "m", seed = 1) {
  set.seed(seed)
  g <- expand.grid(rep = reps, time = times)
  data.frame(metric = metric, rep = g$rep, time = g$time, value = f(g$time) + stats::rnorm(nrow(g), sd = sd))
}

verdict <- function(series) .trendStability(series, keys, window, alpha = 0.05, minChange = 0.10)$flag

test_that("a flat series is stable", {
  expect_identical(verdict(makeSeries(function(t) 10 + 0 * t)), "stable")
})

test_that("a linear trend is still changing, with the right size", {
  s <- makeSeries(function(t) 10 + 0.01 * t, sd = 0.2)
  r <- .trendStability(s, keys, window)
  expect_identical(r$flag, "still changing")
  expect_equal(r$slope, 0.01, tolerance = 0.1)
  ## the NRV range is the window's (5 to 10 here); the fitted change over 500 years is 5
  expect_equal(r$changePctRange, 100 * 5 / diff(range(s$value[s$time >= window[1]])), tolerance = 0.1)
})

test_that("a noisy flat series is stable", {
  for (seed in 1:5) {
    expect_identical(verdict(makeSeries(function(t) 10 + 0 * t, sd = 2, seed = seed)), "stable")
  }
})

test_that("the NRV range is the window's: a transient before the window does not hide a trend in it", {
  ## values before the window run from 60 down to 10; inside it they drift from 10 to 15
  f <- function(t) 10 + ifelse(t < 500, 50 * (500 - t) / 500, 0) + 0.01 * pmax(t - 500, 0)
  s <- makeSeries(f, sd = 0.01)
  r <- .trendStability(s, keys, window)
  ## the fitted change over the window (5) against the window's range (about 5), not the whole series' (about 55)
  expect_equal(r$changePctRange, 100, tolerance = 0.1)
  expect_identical(r$flag, "still changing")
})

test_that("an early transient that has levelled off does not count: only the window is tested", {
  f <- function(t) 10 + ifelse(t < 500, 50 * (500 - t) / 500, 0)
  expect_identical(verdict(makeSeries(f, sd = 0.2)), "stable")
})

test_that("fewer than 3 times in the window cannot be tested", {
  s <- makeSeries(function(t) 10 + 0.01 * t)
  r <- .trendStability(s, keys, c(900, 1000))
  expect_identical(r$flag, "insufficient")
  expect_true(is.na(r$p))
})

test_that("each key combination is its own series, and NA keys are kept", {
  s <- rbind(makeSeries(function(t) 10 + 0 * t, metric = "flat"),
             makeSeries(function(t) 10 + 0.02 * t, metric = "rising"))
  s$class <- c(NA, "Pine")[1 + (s$metric == "rising")]
  r <- .trendStability(s, c("metric", "class"), window)
  expect_identical(r$metric, c("flat", "rising"))
  expect_identical(r$flag, c("stable", "still changing"))
  expect_true(is.na(r$class[1]))
})

test_that("the verdict line counts the series still changing", {
  res <- data.frame(flag = c("stable", "still changing", "stable", "insufficient"))
  expect_identical(.stabilityVerdict(res),
                   "1 of 3 metrics still changing; consider a longer run (1 with too few summary times to test)")
  expect_identical(.stabilityVerdict(data.frame(flag = "stable")),
                   "0 of 1 metrics still changing; the run is long enough")
})

test_that("the burn series is burnSummaries' own block table, found through the registered outputs", {
  ## LandMine or scfm fires: burnSummaries' block table has the area burned; its fire sizes have no areaBurnedHa
  blocks <- data.frame(rep = rep(1:2, each = 3), block = rep(c(2020, 2120, 2220), 2), nFires = 4L,
                       areaBurnedHa = c(100, 0, 50, 7, 7, 7))
  f <- file.path(withr::local_tempdir(), "burnSummaries_fireBlocks.csv")
  utils::write.csv(blocks, f, row.names = FALSE)
  other <- file.path(dirname(f), "burnSummaries_fireSizes_allReps.csv")
  files <- c(other, f, "somewhere/else/burnSummaries_fireRegime.csv")
  expect_identical(.burnBlocksFile(files), f)
  expect_null(.burnBlocksFile(c(other, "a/b.csv")))
  b <- .burnSeries(f)
  expect_equal(b$value[b$rep == 1], c(100, 0, 50))
  expect_equal(b$time[b$rep == 1], c(2020, 2120, 2220))
  expect_true(all(b$value[b$rep == 2] == 7))
  ## the verdict sees a growing burn that the old areaBurnedHa column (always 0 here) hid
  grow <- data.frame(rep = rep(1:5, each = 11), block = rep(seq(0, 1000, 100), 5), nFires = 1L,
                     areaBurnedHa = rep(seq(0, 1000, 100), 5) + rep(1:5, each = 11))
  utils::write.csv(grow, f, row.names = FALSE)
  g <- .burnSeries(f)
  g$metric <- "areaBurnedHa per block"
  expect_identical(.trendStability(g, "metric", c(500, 1000))$flag, "still changing")
})

test_that("the stability series keep landscape and class rows, not one row per patch", {
  g <- expand.grid(rep = 1:2, time = c(0, 100))
  raw <- rbind(
    data.frame(level = "landscape", class = NA, metric = "lsm_l_ai", g, value = 1),
    data.frame(level = "class", class = "Pine", metric = "lsm_c_ai", g, value = 2),
    data.frame(level = "patch", class = "Pine", metric = "lsm_p_area", g[rep(seq_len(nrow(g)), each = 3), ], value = 3)
  )
  raw$poly <- "a"
  kept <- .seriesLevels(raw)
  expect_setequal(kept$level, c("landscape", "class"))
  ## exactly one value per rep x time per series
  key <- c("level", "class", "metric", "rep", "time")
  expect_false(anyDuplicated(kept[key]) > 0L)
  expect_true(anyDuplicated(raw[key]) > 0L)
})

test_that("a stability page's canvas holds the panels it has, and the bold line is the median", {
  expect_equal(.pageLayout(13, 1)[c("ncol", "nrow")], list(ncol = 4L, nrow = 3L))
  one <- .pageLayout(13, 2) ## the last page: 1 panel
  expect_equal(c(one$ncol, one$nrow, one$width, one$height), c(1, 1, 8, 5))
  expect_lt(.pageLayout(14, 2)$height, .pageLayout(14, 1)$height)
  d <- list(series = data.frame(kind = "burn", layer = "a", poly = "a", level = "landscape", class = NA, metric = "m",
                                rep = rep(1:3, each = 2), time = rep(1:2, 3), value = c(1, 1, 1, 1, 10, 10)),
            flag = "stable", id = "burn a a landscape NA m")
  g <- .stabilityPanels(d, c(1, 2), ncol = 1L, nrow = 1L)
  expect_match(g$labels$caption, "bold: median")
  b <- ggplot2::ggplot_build(g)
  expect_equal(b$data[[3]]$y, c(1, 1)) ## the median of 1, 1, 10; the mean would be 4
})
