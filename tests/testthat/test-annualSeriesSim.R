## The annual recorder and the autocorrelation summary, run as events of a real sim on a stub landscape.

stubObjects <- function() {
  pgm <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1000, ymin = 0, ymax = 1000,
                     vals = rep(c(1, 2, 3, 1, 2), 20))
  names(pgm) <- "pixelGroup"
  cd <- data.table::data.table(pixelGroup = c(1L, 1L, 2L, 2L, 3L),
                               speciesCode = c("Pice_mar", "Betu_pap", "Betu_pap", "Pice_mar", "Pice_mar"),
                               age = c(30L, 60L, 150L, 160L, 90L), B = c(1000L, 500L, 2000L, 100L, 800L))
  sa <- terra::as.polygons(terra::ext(pgm)); terra::crs(sa) <- terra::crs(pgm)
  list(
    cohortData = cd, pixelGroupMap = pgm, studyAreaReporting = sa,
    speciesLayers = terra::rast(pgm, vals = 1), flammableMap = terra::rast(pgm, vals = 1),
    sppColorVect = c(Pice_mar = "black", Betu_pap = "white", Mixed = "grey"),
    sppEquiv = data.table::data.table(LandR = c("Pice_mar", "Betu_pap"), Type = c("Conifer", "Deciduous"),
                                      EN_generic_full = c("Black spruce", "Paper birch"))
  )
}

simPaths <- function(root) {
  list(modulePath = modulePath, outputPath = file.path(root, "out"), cachePath = file.path(root, "cache"),
       inputPath = file.path(root, "in"))
}

test_that("single mode writes one annualSeries.csv row per year and registers it", {
  root <- withr::local_tempdir()
  sim <- SpaDES.core::simInit(
    times = list(start = 0, end = 4),
    params = list(NRV_summary = list(mode = "single", summaryInterval = 2L, .plots = NA)),
    modules = moduleName, objects = stubObjects(), paths = simPaths(root)
  )
  sim <- suppressWarnings(SpaDES.core::spades(sim, debug = FALSE))
  f <- file.path(root, "out", "annualSeries.csv")
  expect_true(file.exists(f))
  d <- utils::read.csv(f)
  expect_identical(d$time, 0:4)
  expect_true(all(c("propYoung", "propOld", "meanStandAge", "totalBiomassTg", "lead_Pice_mar") %in% names(d)))
  expect_true(any(basename(SpaDES.core::outputs(sim)$file) == "annualSeries.csv"))
  ## switched off, it is not written
  root2 <- withr::local_tempdir()
  sim2 <- SpaDES.core::simInit(
    times = list(start = 0, end = 2),
    params = list(NRV_summary = list(mode = "single", summaryInterval = 2L, recordAnnualSeries = FALSE, .plots = NA)),
    modules = moduleName, objects = stubObjects(), paths = simPaths(root2)
  )
  suppressWarnings(SpaDES.core::spades(sim2, debug = FALSE))
  expect_false(file.exists(file.path(root2, "out", "annualSeries.csv")))
})

test_that("multi mode reads the reps' annual series and writes the autocorrelation csv and figure", {
  root <- withr::local_tempdir()
  end <- 600L
  period <- c(0L, end)
  yrs <- analysesOutputsTimes(period, 300L)
  files <- unlist(lapply(1:3, function(r) {
    d <- file.path(root, "out", paste0("rep", r))
    dir.create(d, recursive = TRUE)
    set.seed(r)
    ts <- data.frame(time = 0:end, propYoung = as.numeric(stats::arima.sim(list(ar = 0.9), end + 1)),
                     lead_Pice_mar = as.numeric(stats::arima.sim(list(ar = 0.3), end + 1)))
    utils::write.csv(ts, file.path(d, "annualSeries.csv"), row.names = FALSE)
    file.path(d, c("annualSeries.csv", sprintf("cohortData_year%04d.qs2", yrs), sprintf("pixelGroupMap_year%04d.tif", yrs),
                   sprintf("standAgeMap_year%04d.tif", yrs), sprintf("vegTypeMap_year%04d.tif", yrs)))
  }))
  sim <- SpaDES.core::simInit(
    times = list(start = 0, end = end),
    params = list(NRV_summary = list(mode = "multi", reps = 1:3, summaryPeriod = period, summaryInterval = 300L,
                                     nrvWindow = 1, postprocessEvents = "none", .plots = "png",
                                     .studyAreaName = "stub")),
    modules = moduleName,
    objects = list(outputsDF = data.table::data.table(file = files, saveTime = end), reportingPolygons = list(ELF = "x"),
                   sppEquiv = stubObjects()$sppEquiv),
    paths = simPaths(root)
  )
  msgs <- testthat::capture_messages(
    suppressWarnings(SpaDES.core::spades(sim, events = list(NRV_summary = c("init", "postprocess_autocorr")), debug = FALSE))
  )
  expect_match(paste(msgs, collapse = ""), "recommended thinning [0-9]+ years")
  csv <- list.files(root, "autocorrelation.csv", recursive = TRUE, full.names = TRUE)
  expect_length(csv, 1L)
  d <- utils::read.csv(csv)
  expect_true(all(c("series", "rep", "tau", "lagBelow0.1", "label", "recommendedThin") %in% names(d)))
  expect_true("Proportion of forest young" %in% d$label)
  expect_gt(d$recommendedThin[1], 5)
  expect_length(list.files(root, "autocorrelation.png", recursive = TRUE), 1L)
})
