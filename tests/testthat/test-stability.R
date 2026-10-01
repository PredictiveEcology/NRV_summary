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

test_that("area burned per block counts blocks with no fire as zero", {
  fs <- data.frame(rep = c(1, 1, 2), year = c(2025, 2230, 2030), areaBurnedHa = c(100, 50, 7))
  b <- .burnBlockSeries(fs, c(2020, 2320), 100L)
  expect_equal(nrow(b), 2 * 3) ## 2 reps x 3 blocks
  expect_equal(b$value[b$rep == 1], c(100, 0, 50))
  expect_equal(b$value[b$rep == 2], c(7, 0, 0))
  expect_equal(unique(b$time), c(2020, 2120, 2220))
})
