## The module's metadata is its public contract: a project using this module binds to these
## object names and classes, and `reqdPkgs` states what it needs to run at all. These are
## CHARACTERIZATION tests -- they pin today's contract so a change to it has to be deliberate,
## rather than describing behaviour that did not exist before.
##
## GENERATED from the module's live metadata, then reviewed. When a change is intended, update
## this file in the same commit and bump the module version to match: removed, renamed or
## retyped is a MAJOR bump.

test_that("module metadata parses", {
  md <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)
  expect_type(md, "list")
  expect_identical(md$name, moduleName)
})

test_that("inputs are the expected names and classes", {
  md <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)
  inputs <- stats::setNames(md$inputObjects$objectClass, md$inputObjects$objectName)
  inputs <- inputs[!is.na(names(inputs))]
  expect_identical(
    inputs[order(tolower(names(inputs)))],
    c(
      "cohortData"           = "data.table",
      "flammableMap"         = "SpatRaster",
      "LandTypeCC_reporting" = "SpatRaster",
      "pixelGroupMap"        = "SpatRaster",
      "reportingPolygons"    = "list",
      "speciesLayers"        = "SpatRaster",
      "sppColorVect"         = "character",
      "sppColorVectReporting" = "character",
      "sppEquiv"             = "data.table",
      "standAgeMap"          = "SpatRaster",
      "studyAreaReporting"   = "SpatVector"
)
  )
})

test_that("the module declares no output objects", {
  ## By design, not by omission: NRV_summary is a post-processing module. Everything it
  ## produces -- the per-refCode parquet aggregates, the envelope CSVs and the figures --
  ## is written to `outputPath(sim)`, and nothing is handed back through the simList. A
  ## `createsOutput()` appearing here would be a real change in how it is consumed.
  md <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)
  expect_equal(NROW(md$outputObjects), 0L)
})

test_that("parameters are the expected names", {
  md <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)
  expect_identical(
    sort(md$parameters$paramName),
    c(
      ".plotInitialTime", ".plotInterval", ".plots", ".seed", ".studyAreaName", ".useCache",
      "ageClassCutOffs", "ageClasses", "ageClassMaxAge", "autocorrMaxLag", "bigTreedQuantile", "ccStandAgeSource",
      "mixedType", "mode", "nationalReportingLayers", "nationalReportingLayersPath", "nrvWindow", "patchDirections",
      "plotWorkers", "postprocessEvents", "recentFireYears",
      "recordAnnualSeries", "reps", "reuseAggregates", "sieveThresh", "simTimes",
      "sofIndicators", "sppEquivCol", "sppEquivColReporting", "stabilityAlpha", "stabilityMinChange",
      "stabilityWindow", "standOnlyLayers", "summaryInterval", "summaryPeriod", "timeSeriesTimes",
      "vegLeadingProportion"
)
  )
})


test_that("reqdPkgs floors the packages that a library with an older build would otherwise keep", {
  md <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)
  pkgs <- unlist(md$reqdPkgs)
  expect_true(any(grepl("^PredictiveEcology/LandWebUtils@development \\(>= 1\\.1\\.0\\)$", pkgs))) ## nationalReportingLayers()
  expect_true(any(grepl("^FOR-CAST/spatialutils@main \\(>= 0\\.0\\.2\\)$", pkgs)))
})
