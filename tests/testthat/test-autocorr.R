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

## reps x years of AR(1) (or other) series, as the summary reads them
repTables <- function(f, reps = 5, years = 300, seed = 1) {
  lapply(seq_len(reps), function(r) {
    set.seed(seed * 100 + r)
    data.frame(time = seq_len(years), x = f(years))
  })
}
nrv <- c(1, 300)

test_that("5 reps x 300 years of AR(1) with phi 0.95 give a fitted tau within 30% of 39 in most seeds", {
  tau <- vapply(1:6, function(seed) {
    .autocorrSummary(repTables(function(n) as.numeric(stats::arima.sim(list(ar = 0.95), n)), seed = seed),
                     nrv, 200, 100)$fit$tau
  }, numeric(1))
  expect_gte(sum(abs(tau / 39 - 1) < 0.3), 5)
})

test_that("r at the summary interval is close to phi^interval and its reps bracket it", {
  tables <- repTables(function(n) as.numeric(stats::arima.sim(list(ar = 0.95), n)), reps = 20, years = 2000)
  at100 <- .autocorrSummary(tables, c(1, 2000), 200, 100)$fit
  expect_lt(abs(at100$r - 0.95^100), 0.05)
  at20 <- .autocorrSummary(tables, c(1, 2000), 200, 20)$fit
  expect_equal(at20$r, 0.95^20, tolerance = 0.1)
  expect_lte(at20$rMin, at20$r)
  expect_gte(at20$rMax, at20$r)
})

test_that("the effective snapshots follow n (1 - r) / (1 + r), with r clipped to [0, 1)", {
  expect_equal(.essAR1(10, 0.5), 10 / 3)
  expect_equal(.essAR1(10, -0.3), 10)
  expect_lt(.essAR1(10, 1.2), 0.1 * 10)
})

test_that("the misfit is near 0 for AR(1) and large for an oscillating AR(2) series", {
  ar1Fit <- .autocorrSummary(repTables(function(n) as.numeric(stats::arima.sim(list(ar = 0.9), n)), years = 2000),
                             c(1, 2000), 100, 100)$fit
  osc <- .autocorrSummary(repTables(function(n) as.numeric(stats::arima.sim(list(ar = c(1.4, -0.8)), n)), years = 2000),
                          c(1, 2000), 100, 100)$fit
  expect_lt(ar1Fit$ar1Misfit, 0.1)
  expect_gt(osc$ar1Misfit, 0.3)
})

test_that("the recommended thin is the ceiling of the largest tau; the Geyer tau is kept; a constant series is NA", {
  n <- 600
  tables <- lapply(1:3, function(r) {
    set.seed(r)
    data.frame(time = seq_len(n), slow = ar1(0.9, n, r), fast = ar1(0.3, n, 10 + r), constant = 1)
  })
  res <- .autocorrSummary(tables, c(1, n), maxLag = 100, interval = 100)
  fit <- res$fit
  expect_identical(res$thin, ceiling(max(fit$tau, na.rm = TRUE)))
  expect_identical(res$limiting, "slow")
  expect_true(is.na(fit$tau[fit$series == "constant"]))
  expect_true(all(c("phi", "tau", "ar1Misfit", "r", "rMin", "rMax", "effectiveSnapshots", "tauGeyer") %in% names(fit)))
  expect_equal(res$nSnapshots, 3 * (floor((n - 1) / 100) + 1))
  expect_setequal(unique(res$acf$rep), c("1", "2", "3", "pooled"))
})

test_that("the annual recorder returns one row per call, equal to the same scalars from the maps", {
  ## 4 x 4 pixels of 100 m; pixel group 3 has no cohorts (not forest)
  pgm <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 400, ymin = 0, ymax = 400, vals = rep(c(1, 2, 3, 1), 4))
  names(pgm) <- "pixelGroup"
  cd <- data.table::data.table(pixelGroup = c(1L, 1L, 2L, 2L), speciesCode = c("Pice_mar", "Betu_pap", "Betu_pap", "Pice_mar"),
                               age = c(30L, 60L, 150L, 160L), B = c(1000L, 500L, 2000L, 100L))
  sppEquiv <- data.table::data.table(LandR = c("Pice_mar", "Betu_pap"), Type = c("Conifer", "Deciduous"),
                                     EN_generic_full = c("Black spruce", "Paper birch"))
  cuts <- c(0L, 40L, 80L, 120L)
  row <- function(t) .annualSeriesRow(t, cd, tabulate(terra::values(pgm, mat = FALSE)), 1, cuts, 0.8, 2L, sppEquiv, "LandR")
  rows <- lapply(c(5, 6), row)
  expect_identical(nrow(rows[[1]]), 1L)
  expect_identical(rows[[1]]$time, 5)
  expect_identical(nrow(.bindAnnualRows(rows)), 2L)

  ## the same scalars from the maps map_generators makes
  sam <- LandR::standAgeMapGenerator(cd, pgm, weight = "biomass", doAssertion = FALSE)
  vtm <- LandR::vegTypeMapGenerator(cd, pgm, 0.8, mixedType = 2L, sppEquiv = sppEquiv, sppEquivCol = "LandR",
                                    colors = c(Pice_mar = "black", Betu_pap = "white", Mixed = "grey"), doAssertion = FALSE)
  age <- terra::values(sam, mat = FALSE)
  forest <- !is.na(age)
  lv <- terra::levels(vtm)[[1L]]
  lead <- tabulate(match(terra::values(vtm, mat = FALSE)[forest], lv[[1L]]), nbins = nrow(lv)) / sum(forest)
  expected <- c(propYoung = mean(age[forest] < 40), propOld = mean(age[forest] >= 120), meanStandAge = mean(age[forest]),
                setNames(lead, paste0("lead_", lv[[2L]])))
  got <- unlist(rows[[1]][setdiff(names(expected), "totalBiomassTg")])
  expect_equal(got[order(names(got))], expected[order(names(expected))])
  ## biomass: 8 pixels of group 1 (1500 g/m2) and 4 of group 2 (2100 g/m2), 1 ha each
  expect_equal(rows[[1]]$totalBiomassTg, (8 * 1500 + 4 * 2100) * 0.01 / 1e6)
})

test_that("series have full names, a species by its full name, one label per series", {
  sppEquiv <- data.frame(LandR = c("Pice_mar", "Betu_pap"), EN_generic_full = c("Black spruce", "Paper birch"))
  series <- c("propYoung", "lead_Pice_mar", "lead_Betu_pap", "lead_Mixed", "meanStandAge")
  expect_identical(.annualSeriesLabel(series, sppEquiv),
                   c("Proportion of forest young", "Leading: Black spruce", "Leading: Paper birch",
                     "Leading: Mixed", "Mean stand age"))
  expect_identical(.annualSeriesLabel(series[1:2]), c("Proportion of forest young", "Leading: Pice_mar"))
})
