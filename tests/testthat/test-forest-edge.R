## landscapeMetrics = "fragmentation" (2.0.0.9044): the 'lm' event reports one metric, forest edge density,
## from forest / non-forest maps built from the saved cohorts; its rows travel the path of every other
## landscape metric (envelope, lm_nrvComparison.csv, figures).

## a 4 x 4 map of 10 m cells: left half old stand (pixel group 1), right half young (2): one 40 m edge over
## 0.16 ha is 250 m/ha. In the current condition (2020) the right half is old too, so no edge there.
fragCohorts <- function() {
  data.table::data.table(pixelGroup = 1:2, speciesCode = "Pice_mar", age = c(100L, 10L), B = 500L)
}
fragPGM <- function(right) {
  terra::rast(matrix(rep(c(1L, 1L, right, right), 4), 4, 4, byrow = TRUE), crs = "EPSG:32611",
              extent = terra::ext(0, 40, 0, 40))
}
fragSquare <- function() {
  sf::st_sf(Name = "A", geometry = sf::st_sfc(
    sf::st_polygon(list(rbind(c(0, 0), c(40, 0), c(40, 40), c(0, 40), c(0, 0)))), crs = 32611))
}

## the files of one replicate under `root`, saved as a run does: the maps of 2020 (current condition) and of
## each analysis year, with cohortData and pixelGroupMap beside the vegetation-type map
fragFiles <- function(root, times = c(2720, 2820)) {
  d <- file.path(root, "rep1")
  dir.create(d, recursive = TRUE)
  for (yr in c(2020, times)) {
    ## the placeholders: only the path of the vegetation-type and stand-age maps is used
    for (nm in c("vegTypeMap", "standAgeMap")) {
      terra::writeRaster(fragPGM(2L), file.path(d, sprintf("%s_year%04d.tif", nm, yr)), datatype = "INT1U")
    }
    qs2::qs_save(fragCohorts(), file.path(d, sprintf("cohortData_year%04d.qs2", yr)))
    terra::writeRaster(fragPGM(if (yr == 2020) 1L else 2L), file.path(d, sprintf("pixelGroupMap_year%04d.tif", yr)),
                       datatype = "INT4U")
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

test_that("landscapeMetrics defaults to the ten metrics, and only the two sets are accepted", {
  p <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)$parameters
  expect_identical(p$default[[which(p$paramName == "landscapeMetrics")]], "default")
  expect_identical(p$default[[which(p$paramName == "fragmentationAgeThreshold")]], 20)
  check <- moduleFn(".checkLandscapeMetrics", new.env())
  expect_identical(check("fragmentation"), "fragmentation")
  expect_error(check("fragmetation"), "landscapeMetrics must be 'default' or 'fragmentation'")
})

test_that("the forest maps keep the <rep>/<prefix>_year<YYYY>.tif path nrvtools parses, and need the saved cohorts", {
  root <- withr::local_tempdir()
  fragFiles(root)
  vtm <- file.path(root, "rep1", sprintf("vegTypeMap_year%04d.tif", c(2020, 2720)))
  out <- moduleFn(".buildForestMaps", new.env())(vtm, file.path(root, "pp", "_forestMaps"), 20, fragSquare())
  expect_identical(basename(out), sprintf("forestMap_year%04d.tif", c(2020, 2720)))
  expect_identical(basename(dirname(out)), c("rep1", "rep1"))
  expect_identical(as.vector(terra::values(terra::rast(out[[2]]))), rep(c(1, 1, 0, 0), 4))
  ## the threshold is the parameter's: with 5 years the 10-year stands are forest too
  out5 <- moduleFn(".buildForestMaps", new.env())(vtm[2], file.path(root, "pp", "_f5"), 5, fragSquare())
  expect_identical(unique(as.vector(terra::values(terra::rast(out5)))), 1)
  file.remove(file.path(root, "rep1", "cohortData_year2720.qs2"))
  expect_error(moduleFn(".buildForestMaps", new.env())(vtm, file.path(root, "pp", "x"), 20, fragSquare()),
               "cannot build the forest maps; missing:.*cohortData_year2720.qs2")
})

test_that("with landscapeMetrics = 'fragmentation' the lm event writes forest edge density", {
  withr::local_package("SpaDES.core")
  withr::local_options(reproducible.useCache = TRUE)
  root <- withr::local_tempdir()
  sim <- fragInit(fragSim(root, landscapeMetrics = "fragmentation"))
  mod <- sim@.xData$.modObjs[[moduleName]]
  expect_identical(basename(mod$fnf0), "forestMap_year2020.tif")
  expect_identical(basename(mod$fnf), sprintf("forestMap_year%04d.tif", c(2720, 2820)))
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
  expect_identical(cmp$metric, "forest_ed")
  expect_equal(cmp$current, 0) ## today: all forest, no edge
  expect_equal(cmp$mid, 250) ## the simulated years: one 40 m edge over 0.16 ha
  expect_identical(cmp$position, "below") ## today is below the simulated range
  expect_identical(mod$nrvComparisons[["lm ELF"]]$label, "Forest edge density (m/ha)")
})
