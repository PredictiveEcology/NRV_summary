## landscapeMap = "forest" with landscapeMetricFuns = "lsm_c_ed" (2.0.0.9044): the 'lm' event reports forest
## edge density, from forest / non-forest maps built from the saved stand-age maps; its rows travel the path of every other
## landscape metric (envelope, lm_nrvComparison.csv, figures).

## a 4 x 4 map of 10 m cells: left half old stand (100 years), right half `right` years: with 10, one 40 m edge
## over 0.16 ha is 250 m/ha.
fragAge <- function(right) {
  terra::rast(matrix(rep(c(100, 100, right, right), 4), 4, 4, byrow = TRUE), crs = "EPSG:32611",
              extent = terra::ext(0, 40, 0, 40))
}
fragSquare <- function() {
  sf::st_sf(Name = "A", geometry = sf::st_sfc(
    sf::st_polygon(list(rbind(c(0, 0), c(40, 0), c(40, 40), c(0, 40), c(0, 0)))), crs = 32611))
}

## the files of one replicate under `root`, saved as a run does: the maps of 2020 (current condition) and of
## each analysis year; the stand-age maps are the ones the forest maps are made from
fragFiles <- function(root, times = c(2720, 2820)) {
  d <- file.path(root, "rep1")
  dir.create(d, recursive = TRUE)
  for (yr in c(2020, times)) {
    ## the vegetation-type map is a placeholder: only its path is used
    terra::writeRaster(fragAge(10), file.path(d, sprintf("vegTypeMap_year%04d.tif", yr)), datatype = "INT1U")
    ## stand age in years: old everywhere today, the right half young in the simulated years
    terra::writeRaster(fragAge(if (yr == 2020) 100 else 10), file.path(d, sprintf("standAgeMap_year%04d.tif", yr)))
  }
  data.table::data.table(file = list.files(d, full.names = TRUE), saveTime = max(times))
}

fragSim <- function(root, ...) {
  SpaDES.core::simInit(
    times = list(start = 2020, end = 2820),
    params = list(NRV_summary = list(mode = "multi", reps = 1L, summaryPeriod = c(2720L, 2820L),
                                     summaryInterval = 100L, timeSeriesTimes = 2721:2722,
                                     postprocessEvents = "lm", ...)),
    modules = moduleName,
    objects = list(outputsDF = fragFiles(root), reportingPolygons = list(ELF = fragSquare()),
                   studyAreaReporting = fragSquare()),
    paths = list(modulePath = modulePath, outputPath = file.path(root, "_all"),
                 cachePath = file.path(root, "cache"), inputPath = file.path(root, "in"))
  )
}
fragInit <- function(sim) suppressWarnings(SpaDES.core::spades(sim, events = list(NRV_summary = "init"), debug = FALSE))

test_that("the lm event defaults to the vegetation-type maps and the ten default metrics", {
  p <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)$parameters
  expect_identical(p$default[[which(p$paramName == "landscapeMap")]], "vegType")
  expect_identical(p$default[[which(p$paramName == "landscapeMetricFuns")]],
                   unlist(nrvtools::default_landscape_metrics()))
  expect_identical(p$default[[which(p$paramName == "fragmentationAgeThreshold")]], 20)
  testthat::local_mocked_bindings(P = function(sim, ...) sim) ## `sim` stands for the parameter list
  landscapeMap <- moduleFn(".landscapeMap", new.env())
  expect_identical(landscapeMap(list(landscapeMap = "forest")), "forest")
  expect_error(landscapeMap(list(landscapeMap = "wood")), "should be one of")
})

test_that("the forest maps keep the <rep>/<prefix>_year<YYYY>.tif path nrvtools parses", {
  root <- withr::local_tempdir()
  fragFiles(root)
  sam <- file.path(root, "rep1", sprintf("standAgeMap_year%04d.tif", c(2020, 2720)))
  build <- moduleFn(".buildForestMaps", new.env())
  out <- build(sam, file.path(root, "pp", "_forestMaps"), 20, fragSquare())
  expect_identical(basename(out), sprintf("forestMap_year%04d.tif", c(2020, 2720)))
  expect_identical(basename(dirname(out)), c("rep1", "rep1"))
  expect_identical(as.vector(terra::values(terra::rast(out[[2]]))), rep(c(1, 1, 0, 0), 4))
  ## the threshold is the parameter's: with 5 years the 10-year stands are forest too
  out5 <- build(sam[2], file.path(root, "pp", "_f5"), 5, fragSquare())
  expect_identical(unique(as.vector(terra::values(terra::rast(out5)))), 1)
  expect_error(build(file.path(root, "rep1", "vegTypeMap_year2020.tif"), file.path(root, "pp", "x"), 20, fragSquare()))
})

test_that("with landscapeMetrics = 'fragmentation' the lm event writes forest edge density", {
  withr::local_package("SpaDES.core")
  withr::local_options(reproducible.useCache = TRUE)
  root <- withr::local_tempdir()
  sim <- fragInit(fragSim(root, landscapeMap = "forest", landscapeMetricFuns = "lsm_c_ed"))
  mod <- sim@.xData$.modObjs[[moduleName]]
  expect_identical(basename(mod$fnf0), "forestMap_year2020.tif")
  expect_identical(basename(mod$fnf), sprintf("forestMap_year%04d.tif", c(2720, 2820)))
  expect_identical(basename(mod$sam), sprintf("standAgeMap_year%04d.tif", c(2720, 2820))) ## made from these
  expect_true(all(file.exists(c(mod$fnf0, mod$fnf))))
  ## the species-level maps are still what the other events read
  expect_match(basename(mod$vtm), "^vegTypeMap_year")

  fn <- moduleFn("landscapeMetrics", mod)
  env <- environment(fn)
  for (nm in c(".buildRepDataset", ".writeNrvSummaryCSVs", ".writeNrvComparisonCSV", ".recordComparison")) {
    env[[nm]] <- moduleFn(nm, mod)
  }
  environment(env$.buildRepDataset)$.summarizeRepDataset <- moduleFn(".summarizeRepDataset", mod)
  environment(env$.writeNrvComparisonCSV)$.recordComparison <- env$.recordComparison
  testthat::local_mocked_bindings(P = function(sim, ...) SpaDES.core::params(sim)$NRV_summary)
  withr::local_options(reproducible.cachePath = file.path(root, "cache"))
  fn(sim)

  cmp <- utils::read.csv(file.path(dirname(SpaDES.core::outputPath(sim)), "postprocess", "csv", "lm", "ELF",
                                   "lm_nrvComparison.csv"))
  expect_identical(cmp$metric, "forest_ed") ## the forest class of lsm_c_ed
  expect_equal(cmp$current, 0) ## today: all forest, no edge
  expect_equal(cmp$mid, 250) ## the simulated years: one 40 m edge over 0.16 ha
  expect_identical(cmp$position, "below") ## today is below the simulated range
  expect_identical(mod$nrvComparisons[["lm ELF"]]$label, "Forest edge density (m/ha)")
})
