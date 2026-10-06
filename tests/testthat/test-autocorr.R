## The autocorrelation time of the landscape gives the interval at which summary snapshots are independent.

ar1 <- function(phi, n = 20000, seed = 1) {
  set.seed(seed)
  as.numeric(stats::arima.sim(list(ar = phi), n = n))
}

test_that("tau of an AR(1) series with phi = 0.9 is (1 + phi) / (1 - phi) = 19", {
  tau <- .autocorrTime(.acf(ar1(0.9, n = 2e5), 200))
  expect_equal(tau, 19, tolerance = 0.1)
})

test_that("white noise has tau of about 1", {
  set.seed(2)
  expect_equal(.autocorrTime(.acf(stats::rnorm(2e5), 200)), 1, tolerance = 0.1)
})

test_that("the first lag with ACF below 0.1 is where it is, NA when it never is", {
  expect_identical(.firstLagBelow(c(1, 0.5, 0.2, 0.05, 0)), 3L)
  expect_identical(.firstLagBelow(c(1, 0.5, 0.4)), NA_integer_)
})

test_that("the recommended thin is the largest tau over series, with the effective sample count", {
  n <- 2000
  tables <- lapply(1:3, function(r) data.frame(time = seq_len(n), slow = ar1(0.9, n, r), fast = ar1(0.3, n, 10 + r),
                                               constant = 1))
  res <- .autocorrSummary(tables, c(1, n), maxLag = 100, interval = 100)
  pooled <- res$tau[res$tau$rep == "pooled", ]
  expect_identical(res$thin, ceiling(max(pooled$tau, na.rm = TRUE)))
  expect_identical(pooled$series[which.max(pooled$tau)], "slow")
  expect_true(is.na(pooled$tau[pooled$series == "constant"]))
  expect_equal(res$effectiveSamples, n / res$thin)
  expect_equal(res$nSnapshots, floor((n - 1) / 100) + 1)
  expect_setequal(unique(res$tau$rep), c("1", "2", "3", "pooled"))
})

test_that("a summary interval shorter than thin gives fewer independent snapshots than snapshots", {
  tables <- list(data.frame(time = 1:1000, slow = ar1(0.95, 1000)))
  res <- .autocorrSummary(tables, c(1, 1000), maxLag = 100, interval = 5)
  expect_lt(res$effectiveSnapshots, res$nSnapshots)
})

test_that("the annual recorder returns one row with the expected columns", {
  ## 4 x 4 pixels, 3 pixel groups; pixel group 3 is outside the reporting area (no stand age)
  pgm <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 400, ymin = 0, ymax = 400, vals = rep(c(1, 2, 3, 1), 4))
  cd <- data.table::data.table(pixelGroup = c(1L, 1L, 2L, 3L), speciesCode = c("Pice_mar", "Betu_pap", "Betu_pap", "Pice_mar"),
                               age = c(30L, 60L, 150L, 10L), B = c(1000L, 500L, 2000L, 100L))
  sam <- terra::rast(pgm); terra::values(sam) <- rep(c(30, 150, NA, 30), 4)
  vtm <- terra::rast(pgm); terra::values(vtm) <- rep(c(1, 2, 1, 1), 4)
  levels(vtm) <- data.frame(ID = 1:2, species = c("Pice_mar", "Betu_pap"))
  rows <- lapply(c(5, 6), function(t) .annualSeriesRow(t, list(vegTypeMap = vtm, standAgeMap = sam), cd, pgm,
                                                        c(0L, 40L, 80L, 120L)))
  one <- rows[[1]]
  expect_identical(nrow(one), 1L)
  expect_identical(names(one), c("time", "propYoung", "propOld", "meanStandAge", "totalBiomassTg",
                                 "lead_Pice_mar", "lead_Betu_pap"))
  ## 12 forested pixels: 8 aged 30 (young, < 40) and 4 aged 150 (old, >= 120); led by Pice_mar on 8, Betu_pap on 4;
  ## pixel group 1 covers 8 of them (1500 g/m2) and group 2 covers 4 (2000 g/m2), 1 ha each
  expect_equal(unlist(one[1, -1]), c(propYoung = 2/3, propOld = 1/3, meanStandAge = 70, totalBiomassTg = 2e-4,
                                      lead_Pice_mar = 2/3, lead_Betu_pap = 1/3))
  expect_identical(nrow(.bindAnnualRows(rows)), 2L)
})

test_that("series have full names, a species by its full name, one label per series", {
  sppEquiv <- data.frame(LandR = c("Pice_mar", "Betu_pap"), EN_generic_full = c("Black spruce", "Paper birch"))
  series <- c("propYoung", "lead_Pice_mar", "lead_Betu_pap", "lead_Mixed", "meanStandAge")
  expect_identical(.annualSeriesLabel(series, sppEquiv),
                   c("Proportion of forest young", "Leading: Black spruce", "Leading: Paper birch",
                     "Leading: Mixed", "Mean stand age"))
  expect_identical(.annualSeriesLabel(series[1:2]), c("Proportion of forest young", "Leading: Pice_mar"))
})
