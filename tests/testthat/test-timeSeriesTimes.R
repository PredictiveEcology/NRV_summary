## `timeSeriesTimes` defaults to start + 601:650, which is outside any run shorter than 650 years.
## The default (NULL) is resolved in init: start + 601:650 if the run is that long, else its last 50 years.

initTimeSeriesTimes <- function(end, ...) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  period <- c(end - 100L, end)
  yrs <- analysesOutputsTimes(period, 50L)
  ## InitMulti() only checks that the files it expects are listed in outputsDF
  files <- file.path(root, "_all", "rep1", c(sprintf("cohortData_year%04d.qs2", yrs),
                                             sprintf("pixelGroupMap_year%04d.tif", yrs),
                                             sprintf("standAgeMap_year%04d.tif", yrs),
                                             sprintf("vegTypeMap_year%04d.tif", yrs)))
  sim <- SpaDES.core::simInit(
    times = list(start = 2020, end = end),
    params = list(NRV_summary = list(mode = "multi", reps = 1L, summaryPeriod = period,
                                     summaryInterval = 50L, ...)),
    modules = moduleName,
    objects = list(outputsDF = data.table::data.table(file = files, saveTime = end),
                   reportingPolygons = list(ELF = "placeholder")),
    paths = list(modulePath = modulePath, outputPath = file.path(root, "_all"),
                 cachePath = file.path(root, "cache"), inputPath = file.path(root, "in"))
  )
  suppressWarnings(
    SpaDES.core::spades(sim, events = list(NRV_summary = "init"), debug = FALSE)
  )
}

test_that("a 300-year run resolves the default timeSeriesTimes to its last 50 years", {
  sim <- initTimeSeriesTimes(end = 2320)
  expect_identical(as.numeric(SpaDES.core::P(sim, module = "NRV_summary")$timeSeriesTimes), 2320 - 49:0)
})

test_that("a 1000-year run resolves the default timeSeriesTimes to start + 601:650", {
  sim <- initTimeSeriesTimes(end = 3020)
  expect_identical(as.numeric(SpaDES.core::P(sim, module = "NRV_summary")$timeSeriesTimes), 2020 + 601:650)
})

test_that("an explicit timeSeriesTimes outside the run still stops", {
  expect_error(initTimeSeriesTimes(end = 2320, timeSeriesTimes = 2700:2710),
               "timeSeriesTimes values are outside")
})
