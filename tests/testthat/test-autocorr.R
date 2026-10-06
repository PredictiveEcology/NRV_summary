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
