defineModule(sim, list(
  name = "NRV_summary",
  description = paste("NRV simulation post-processing and summary creation.",
                      "Produces summaries for multiple patch metrics and other indicators."),
  keywords = c("NRV"),
  authors = c(
    person(c("Alex", "M."), "Chubaty", email = "achubaty@for-cast.ca", role = c("aut"))
  ),
  childModules = character(0),
  version = list(NRV_summary = "1.1.3"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  loadOrder = list(after = c("Biomass_core")),
  documentation = list("README.md", "NRV_summary.Rmd"), ## .md produced from .Rmd
  reqdPkgs = list(
    "data.table", "dplyr", "fs", "future.apply", "future.callr",
    "ggforce", "ggplot2", "googledrive", "landscapemetrics", "qs2", "sf", "terra",
    "PredictiveEcology/LandR@development (>= 1.1.1)",
    "PredictiveEcology/LandWebUtils@development (>= 0.1.5)",
    "FOR-CAST/nrvtools (>= 0.0.21)",
    "PredictiveEcology/pemisc@development (>= 0.0.4.9016)",
    "PredictiveEcology/SpaDES.core@development (>= 3.0.3.9000)"
  ),
  parameters = bindrows(
    defineParameter("ageClasses", "character", LandWebUtils:::.ageClasses, NA, NA,
                    "descriptions/labels for age classes (seral stages)"),
    defineParameter("ageClassCutOffs", "integer", LandWebUtils:::.ageClassCutOffs, NA, NA,
                    "defines the age boundaries between age classes"),
    defineParameter("ageClassMaxAge", "integer", 400L, NA, NA,
                    "maximum possible age"),
    defineParameter("mixedType", "integer", 2L,
                    desc = paste("How to define mixed stands: `0L` for none; `1L` for any species admixture;",
                                 "`2L` for deciduous > conifer. See `LandR::vegTypeMapGenerator`.")),
    defineParameter("mode", "character", "single", NA, NA,
                    paste("use 'single' to run part of a simulation;",
                          "use 'multi' to run as part of postprocessing multiple runs.")),
    defineParameter("postprocessEvents", "character", c("lm", "pm"), NA, NA,
                    paste("Specify which subset of postprocessing events to run.",
                          "At least one of:",
                          "'bc' for BC seral stage patch metrics;",
                          "'fd' for forest degradation indicators;",
                          "'lm' for default landscape metrics;",
                          "'lw' for default LandWeb summaries",
                          "'pm' for default patch metrics;",
                          "'on' for ON patch metrics.")),
    defineParameter("reps", "integer", 1L:10L, 1L, NA_integer_,
                    paste("number of replicates/runs per study area.")),
    defineParameter("sieveThresh", "integer", 1L, NA_integer_, NA_integer_,
                    paste("threshold patch size (number of pixels) to use with `terra::sieve`",
                          "when creating seral stage maps")),
    defineParameter("simTimes", "numeric", c(NA, NA), NA, NA,
                    "Simulation start and end times when running in 'multi' mode."),
    defineParameter("sppEquivCol", "character", "LandR", NA, NA,
                    "The column in `sim$sppEquiv` data.table to use as a naming convention"),
    defineParameter("summaryInterval", "integer", 100L, NA, NA,
                    "simulation time interval at which to take 'snapshots' used for summary analyses."),
    defineParameter("summaryPeriod", "integer", start(sim) + c(700L, 1000L), NA, NA,
                    "lower and upper end of the range of simulation times used for summary analyses."),
    defineParameter("timeSeriesTimes", "numeric", start(sim) + 601:650, NA, NA,
                    "simulation times for which to build time steries animations."),
    defineParameter("vegLeadingProportion", "numeric", 0.8, 0.0, 1.0,
                    "a number that defines whether a species is leading for a given pixel"),
    defineParameter(".plots", "character", "screen", NA, NA,
                    "Used by `SpaDES.core::Plots`, which can be optionally used here."),
    defineParameter(".plotInitialTime", "numeric", start(sim), NA, NA,
                    "Describes the simulation time at which the first plot event should occur."),
    defineParameter(".plotInterval", "numeric", NA, NA, NA,
                    "Describes the simulation time interval between plot events."),
    defineParameter(".studyAreaName", "character", NA, NA, NA,
                    paste("Human-readable name for the study area used, or a hash of the study",
                          "area obtained using `reproducible::studyAreaName()`.")),
    defineParameter(".seed", "list", list(), NA, NA,
                    "Named list of seeds to use for each event (names)."),
    defineParameter(".useCache", "logical", FALSE, NA, NA,
                    "Should caching of events or module be used?")
  ),
  inputObjects = bindrows(
    expectsInput("cohortData", "data.table",
                 desc = "Required in single mode."),
    expectsInput("flammableMap", "SpatRaster",
                 desc = "binary flammability map (required with `type = 'single'`)"),
    expectsInput("pixelGroupMap", "SpatRaster",
                 desc = "Required in single mode."),
    expectsInput("reportingPolygons", "list",
                 desc = "reporting polygons for post-processing (required with `type = 'multi'`)"),
    expectsInput("speciesLayers", "SpatRaster",
                 desc = "initial percent cover raster layers used for simulation."),
    expectsInput("sppColorVect", "character",
                 desc = paste("A named vector of colors to use for plotting.",
                              "The names must be in `sim$sppEquiv[[P(sim)$sppEquivCol]]`,",
                              "and should also contain a color for 'Mixed'")),
    expectsInput("sppEquiv", "data.table", NA, NA, NA,
                 desc = "table of species equivalencies. See `LandR::sppEquivalencies_CA`."),
    expectsInput("studyAreaReporting", "SpatVector",
                 desc = "Required in single mode.")
  ),
  outputObjects = SpaDES.core:::._outputObjectsDF()
))

## event types
#   - type `init` is required for initialization

doEvent.NRV_summary = function(sim, eventTime, eventType) {
  switch(
    eventType,
    init = {
      if (min(P(sim)$summaryPeriod) < start(sim) || max(P(sim)$summaryPeriod) > end(sim)) {
        stop("summaryPeriod values are outside the range of simulation times")
      }
      if (min(P(sim)$timeSeriesTimes) < start(sim) || max(P(sim)$timeSeriesTimes) > end(sim)) {
        stop("timeSeriesTimes values are outside the range of simulation times")
      }

      mod$analysesOutputsTimes <- analysesOutputsTimes(P(sim)$summaryPeriod, P(sim)$summaryInterval)

      if (P(sim)$mode == "single") {
        stopifnot(
          !is.null(sim$cohortData),
          !is.null(sim$pixelGroupMap),
          !is.null(sim$speciesLayers),
          !is.null(sim$sppColorVect),
          !is.null(sim$sppEquiv),
          !is.null(sim$studyAreaReporting)
        )

        sim <- scheduleEvent(sim, start(sim), "NRV_summary", "map_generators", .last())
        ## fmt: skip
        sim <- scheduleEvent(sim, P(sim)$summaryPeriod[1], "NRV_summary", "map_generators", .last())
        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "map_generators", .last())

        sim <- scheduleEvent(sim, start(sim), "NRV_summary", "save_single", .last())
        sim <- scheduleEvent(sim, P(sim)$summaryPeriod[1], "NRV_summary", "save_single", .last())
        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "save_single", .last())
      } else if (P(sim)$mode == "multi") {
        stopifnot(!is.null(sim$reportingPolygons))

        sim <- InitMulti(sim)

        if ("lm" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_lm", .last())
        }

        if ("pm" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_pm", .last())
        }

        if ("fd" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_fd", .last())
        }

        if ("lw" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_lw", .last())
        }

        if ("bc" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_bc", .last())
        }

        if ("on" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_on", .last())
        }

        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess", .last())
        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "plot", .last())
      }
    },
    map_generators = {
      mod$vegTypeMap <- LandR::vegTypeMapGenerator(
        sim$cohortData,
        sim$pixelGroupMap,
        P(sim)$vegLeadingProportion,
        mixedType = P(sim)$mixedType,
        sppEquiv = sim$sppEquiv,
        sppEquivCol = P(sim)$sppEquivCol,
        colors = sim$sppColorVect,
        doAssertion = getOption("LandR.assertions", TRUE)
      )

      mod$standAgeMap <- LandR::standAgeMapGenerator(
        sim$cohortData,
        sim$pixelGroupMap,
        weight = "biomass",
        doAssertion = getOption("LandR.assertions", TRUE)
      ) |>
        terra::mask(sim$studyAreaReporting)

      if (time(sim) >= P(sim)$summaryPeriod[1] && time(sim) < P(sim)$summaryPeriod[2]) {
        ## fmt: skip
        sim <- scheduleEvent(sim, time(sim) + P(sim)$summaryInterval, "NRV_summary", "map_generators", .last())
      }
    },
    plot = {
      plotFun(sim)
    },
    postprocess_lm = {
      sim <- landscapeMetrics(sim) ## TODO: warning: Number of classes must be >= 3, IJI = NA.
    },
    postprocess_pm = {
      sim <- patchMetrics(sim)
    },
    postprocess_fd = {
      browser() ## TODO
    },
    postprocess_lw = {
      browser() ## TODO
    },
    postprocess_bc = {
      sim <- makeSeralStageMapsBC(sim)
      sim <- patchMetricsSeralBC(sim)
    },
    postprocess_on = {
      ## TODO finalize implementation
      message("Ontario NRV metrics are not yet fully implemented.")
    },
    save_single = {
      padYear <- paddedFloatToChar(time(sim), padL = ceiling(log10(end(sim) + 1)))

      ## objects to save at start of simulation ---------------------------------------------------
      if (time(sim) == start(sim)) {
        f_sppColorVect <- file.path(outputPath(sim), paste0("sppColorVect_year", padYear, ".qs2"))
        qs2::qs_save(sim$sppColorVect, f_sppColorVect)
        sim <- registerOutputs(f_sppColorVect, sim)

        f_sppEquiv <- file.path(outputPath(sim), paste0("sppEquiv_year", padYear, ".qs2"))
        qs2::qs_save(sim$sppEquiv, f_sppEquiv)
        sim <- registerOutputs(f_sppEquiv, sim)

        f_speciesLayers <- file.path(outputPath(sim), paste0("speciesLayers_year", padYear, ".tif"))
        terra::writeRaster(sim$speciesLayers, f_speciesLayers, datatype = "INT2U", overwrite = TRUE)
        sim <- registerOutputs(f_speciesLayers, sim)
      }

      ## objects to save during simulation --------------------------------------------------------
      times_during <- c(start(sim), end(sim), mod$analysesOutputsTimes) |> unique() |> sort()
      if (time(sim) %in% times_during) {
        f_cohortData <- file.path(outputPath(sim), paste0("cohortData_year", padYear, ".qs2"))
        qs2::qs_save(sim$cohortData, f_cohortData)
        sim <- registerOutputs(f_cohortData, sim)

        f_pixelGroupMap <- file.path(outputPath(sim), paste0("pixelGroupMap_year", padYear, ".tif"))
        terra::writeRaster(sim$pixelGroupMap, f_pixelGroupMap, datatype = "INT4U", overwrite = TRUE)
        sim <- registerOutputs(f_pixelGroupMap, sim)

        f_standAgeMap <- file.path(outputPath(sim), paste0("standAgeMap_year", padYear, ".tif"))
        terra::writeRaster(mod$standAgeMap, f_standAgeMap, datatype = "INT2U", overwrite = TRUE)
        sim <- registerOutputs(f_standAgeMap, sim)

        f_vegTypeMap <- file.path(outputPath(sim), paste0("vegTypeMap_year", padYear, ".tif"))
        terra::writeRaster(mod$vegTypeMap, f_vegTypeMap, datatype = "INT2U", overwrite = TRUE)
        sim <- registerOutputs(f_vegTypeMap, sim)

        if (time(sim) >= P(sim)$summaryPeriod[1] && time(sim) < P(sim)$summaryPeriod[2]) {
          ## fmt: skip
          sim <- scheduleEvent(sim, time(sim) + P(sim)$summaryInterval, "NRV_summary", "save_single", .last())
        }
      }

      ## objects to save at end of simulation -----------------------------------------------------
      if (time(sim) == end(sim)) {
        f_flammableMap <- file.path(outputPath(sim), paste0("flammableMap_year", padYear, ".tif"))
        terra::writeRaster(sim$flammableMap, f_flammableMap, datatype = "INT2U", overwrite = TRUE)
        sim <- registerOutputs(f_flammableMap, sim)
      }
    },
    noEventWarning(sim)
  )

  return(invisible(sim))
}

# event functions -------------------------------------------------------------------

InitMulti <- function(sim) {
  ## check for necessary output files -----------------------------------------------
  ## NOTE: don't load simLists -- slow and unreliable
  allReps <- sprintf("rep%02d", P(sim)$reps)
  padL <- ceiling(log10(P(sim)$simTimes[2] + 1))
  padYearStart <- paddedFloatToChar(P(sim)$simTimes[1], padL = padL)
  padYearEnd <- paddedFloatToChar(P(sim)$simTimes[2], padL = padL)

  ## all reps have same flammable map
  mod$flm <- file.path(outputPath(sim), allReps[1], paste0("flammableMap_year", padYearEnd, ".tif"))

  cdpgm <- fs::dir_ls(
    outputPath(sim),
    regexp = "cohortData|pixelGroupMap",
    recurse = 1,
    type = "file"
  ) |>
    grep(paste0("(", paste0(allReps, collapse = "|"), ")"), x = _, value = TRUE) |>
    grep(paste(mod$analysesOutputsTimes, collapse = "|"), x = _, value = TRUE)
  mod$allouts <- fs::dir_ls(
    outputPath(sim),
    regexp = "vegType|standAge",
    recurse = 1,
    type = "file"
  ) |>
    grep(paste0("(", paste0(allReps, collapse = "|"), ")"), x = _, value = TRUE) |>
    grep("gri|png|txt|xml", x = _, value = TRUE, invert = TRUE)
  mod$allouts2 <- paste(
    paste0(
      "year",
      paddedFloatToChar(
        setdiff(c(0, P(sim)$timeSeriesTimes), mod$analysesOutputsTimes),
        padL = padL
      )
    ),
    collapse = "|"
  ) |>
    grep(pattern = _, x = mod$allouts, value = TRUE, invert = TRUE)

  filesUserHas <- c(cdpgm, mod$allouts2)

  dirsExpected <- file.path(outputPath(sim), allReps)
  filesExpected <- as.character(sapply(dirsExpected, function(d) {
    c(
      file.path(d, sprintf("cohortData_year%04d.qs2", mod$analysesOutputsTimes)),
      file.path(d, sprintf("pixelGroupMap_year%04d.tif", mod$analysesOutputsTimes)),
      file.path(d, sprintf("standAgeMap_year%04d.tif", mod$analysesOutputsTimes)),
      file.path(d, sprintf("vegTypeMap_year%04d.tif", mod$analysesOutputsTimes))
    )
  }))

  filesNeeded <- data.frame(file = filesExpected, exists = filesExpected %in% filesUserHas)

  if (!all(filesNeeded$exists)) {
    missing <- filesNeeded[filesNeeded$exists == FALSE, ]$file
    stop(
      sum(!filesNeeded$exists),
      " simulation files appear to be missing:\n",
      paste(missing, collapse = "\n")
    )
  }

  mod$layerName <- gsub(mod$allouts2, pattern = paste0(".*", outputPath(sim)), replacement = "")
  mod$layerName <- gsub(mod$layerName, pattern = "[/\\]", replacement = "_")
  mod$layerName <- gsub(mod$layerName, pattern = "^_", replacement = "")

  mod$sam <- gsub(".*vegTypeMap.*", NA, mod$allouts2) |>
    grep(paste(mod$analysesOutputsTimes, collapse = "|"), x = _, value = TRUE)
  mod$vtm <- gsub(".*standAgeMap.*", NA, mod$allouts2) |>
    grep(paste(mod$analysesOutputsTimes, collapse = "|"), x = _, value = TRUE)

  mod$samTimeSeries <- gsub(".*vegTypeMap.*", NA, mod$allouts) |>
    grep(paste(P(sim)$timeSeriesTimes, collapse = "|"), x = _, value = TRUE)
  mod$vtmTimeSeries <- gsub(".*standAgeMap.*", NA, mod$allouts) |>
    grep(paste(P(sim)$timeSeriesTimes, collapse = "|"), x = _, value = TRUE)

  ## cohortData and pixelGroupMap files
  mod$cd <- grep("cohortData", cdpgm, value = TRUE)
  mod$pgm <- grep("pixelGroupMap", cdpgm, value = TRUE)

  ## extract the reporting polygons to run the analyses on
  mod$rptPolyNames <- names(sim$reportingPolygons)

  # ! ----- STOP EDITING ----- ! #

  return(invisible(sim))
}

## build landscape metrics tables from vegetation type maps (VTMs)
landscapeMetrics <- function(sim) {
  fvtm0 <- file.path(outputPath(sim), paste0("vegTypeMap_year", P(sim)$simTimes[1], ".tif"))
  fvtm <- mod$vtm
  browser()
  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)

  funList <- default_landscape_metrics() ## TODO: pass this further up via parameter funList_lm

  oldPlan <- future::plan() |>
    tweak(workers = pemisc::optimalClusterNum(5000, length(fvtm))) |>
    future::plan()
  on.exit(future::plan(oldPlan), add = TRUE)

  lapply(
    mod$rptPolyNames,
    function(p, reportingPolygons, studyArea) {
      message(crayon::magenta("Calculating landscape metrics for", p, "..."))

      rptPoly <- reportingPolygons[[p]]

      if (is(rptPoly, "Spatial")) {
        rptPoly <- sf::st_as_sf(rptPoly)
      } else if (
        is(rptPoly, "sf") && sf::st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON"
      ) {
        rptPoly <- sf::st_collection_extract(rptPoly, "POLYGON")
      }
      rptPoly <- sf::st_crop(rptPoly, studyArea) ## ensure cropped to studyArea

      rptPolyCol <- "NAME"
      refCode <- paste0("lm_", rptPoly[["ID"]])
      refCodeCC <- paste0(refCode, "_CC")

      fileInfo <- file.info(fvtm0)[, c("size", "mtime")]
      mod[[refCodeCC]] <- suppressWarnings({
        Cache(
          calculateLandscapeMetrics,
          summaryPolys = rptPoly,
          polyCol = rptPolyCol,
          vtm = fvtm0,
          funList = funList,
          .cacheExtra = fileInfo
        )
      })
      lapply(names(mod[[refCodeCC]]), function(f) {
        write.csv(
          mod[[refCodeCC]][[f]],
          file.path(outputPath(sim), paste0(refCodeCC, "_", f, ".csv")),
          row.names = FALSE
        )
      })

      fileInfo <- file.info(vtm)[, c("size", "mtime")]
      mod[[refCode]] <- Cache(
        calculateLandscapeMetrics,
        summaryPolys = rptPoly,
        polyCol = rptPolyCol,
        vtm = fvtm,
        funList = funList,
        .cacheExtra = fileInfo
      )
      lapply(names(mod[[refCode]]), function(f) {
        write.csv(
          mod[[refCode]][[f]],
          file.path(outputPath(sim), paste0(refCode, "_", f, ".csv")),
          row.names = FALSE
        )
      })

      return(invisible(NULL))
    },
    studyArea = studyAreaReporting,
    reportingPolygons = sim$reportingPolygons
  )

  return(invisible(sim))
}

patchMetrics <- function(sim) {
  fflm <- mod$flm
  fsam0 <- file.path(outputPath(sim), "standAgeMap_year0000.tif")
  fsam <- mod$sam
  fvtm0 <- file.path(outputPath(sim), "vegTypeMap_year0000.tif")
  fvtm <- mod$vtm

  ## current conditions
  vtmCC <- Cache(
    vegTypeMapGenerator,
    x = sim$speciesLayers,
    vegLeadingProportion = P(sim)$vegLeadingProportion,
    mixedType = 2,
    sppEquiv = sim$sppEquiv,
    sppEquivCol = P(sim)$sppEquivCol,
    colors = sim$sppColorVect,
    doAssertion = FALSE
  )
  terra::writeRaster(vtmCC, fvtm0, datatype = "INT1U", overwrite = TRUE)

  samCC <- if (is.null(sim$reportingPolygons[["CC SAM"]])) {
    sim$reportingPolygons[["CC TSF"]]
  } else {
    sim$reportingPolygons[["CC SAM"]]
  }
  if (is(samCC, "PackedSpatRaster")) {
    samCC <- unwrap(samCC) ## TODO: why is this necessary? saveSimList wraps Spat* objects
  }
  terra::writeRaster(samCC, fsam0, datatype = "INT1U", overwrite = TRUE)

  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)
  browser()
  funList <- default_patch_metrics() ## TODO: pass this further up via parameter funList_pm

  oldPlan <- future::plan() |>
    tweak(workers = pemisc::optimalClusterNum(5000, length(fvtm))) |>
    future::plan()
  on.exit(future::plan(oldPlan), add = TRUE)

  lapply(
    mod$rptPolyNames,
    function(p, reportingPolygons, studyArea) {
      message(crayon::magenta("Calculating patch metrics for", p, "..."))

      rptPoly <- reportingPolygons[[p]]

      if (is(rptPoly, "Spatial")) {
        rptPoly <- st_as_sf(rptPoly)
      } else if (is(rptPoly, "sf") && st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON") {
        rptPoly <- st_collection_extract(rptPoly, "POLYGON")
      }
      rptPoly <- st_crop(rptPoly, studyArea) ## ensure cropped to studyArea
      rptPolyCol <- "NAME"
      refCode <- paste0("pm_", rptPoly[["ID"]])
      refCodeCC <- paste0(refCode, "_CC")

      ## CC
      fileInfo <- file.info(fvtm0, fsam0)[, c("size", "mtime")]
      dfl_cc <- Cache(
        calculatePatchMetrics,
        sam = fsam0,
        vtm = fvtm0,
        flm = fflm,
        summaryPolys = rptPoly,
        polyCol = rptPolyCol,
        funList = funList,
        .cacheExtra = fileInfo
      )
      lapply(names(dfl_cc), function(f) {
        write.csv(
          dfl_cc[[f]],
          file.path(outputPath(sim), paste0(refCodeCC, "_", f, "_raw.csv")),
          row.names = FALSE
        )
      })

      mod[[refCodeCC]] <- summarizePatchMetrics(dfl_cc)
      lapply(names(mod[[refCodeCC]]), function(f) {
        write.csv(
          mod[[refCodeCC]][[f]],
          file.path(outputPath(sim), paste0(refCode, "_", f, ".csv")),
          row.names = FALSE
        )
      })

      ## simulation results
      fileInfo <- file.info(fsam, fvtm)[, c("size", "mtime")]
      dfl <- Cache(
        calculatePatchMetrics,
        sam = fsam,
        vtm = fvtm,
        flm = fflm,
        summaryPolys = rptPoly,
        polyCol = rptPolyCol,
        funList = funList,
        .cacheExtra = fileInfo
      )
      lapply(names(dfl), function(f) {
        write.csv(
          dfl[[f]],
          file.path(outputPath(sim), paste0(refCode, "_", f, "_raw.csv")),
          row.names = FALSE
        )
      })

      mod[[refCode]] <- summarizePatchMetrics(dfl)
      lapply(names(mod[[refCode]]), function(f) {
        write.csv(
          mod[[refCode]][[f]],
          file.path(outputPath(sim), paste0(refCode, "_", f, ".csv")),
          row.names = FALSE
        )
      })

      return(invisible(NULL))
    },
    studyArea = studyAreaReporting,
    reportingPolygons = sim$reportingPolygons
  )

  return(invisible(sim))
}

makeSeralStageMapsBC <- function(sim) {
  message(crayon::magenta("Creating seral stage maps ..."))

  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)
  NDTBEC <- sim$reportingPolygons[["ecoregionLayer"]] |>
    sf::st_as_sf() |>
    sf::st_crop(studyAreaReporting)
  fNDTBEC <- file.path(outputPath(sim), "NDTBEC.shp")
  sf::st_write(NDTBEC, fNDTBEC, append = FALSE, quiet = TRUE)
  rm(studyAreaReporting, NDTBEC)

  fcd0 <- file.path(outputPath(sim), "rep01", "cohortData_year0000.qs2")
  fpgm0 <- file.path(outputPath(sim), "rep01", "pixelGroupMap_year0000.tif")

  fcd <- c(fcd0, mod$cd)
  fpgm <- c(fpgm0, mod$pgm)

  # oldPlan <- future::plan() |>
  #   tweak(workers = pemisc::optimalClusterNum(5000, length(fcd))) |>
  #   future::plan()
  oldPlan <- plan("callr", workers = pemisc::optimalClusterNum(5000, length(fcd)))
  on.exit(plan(oldPlan), add = TRUE)

  ssmFiles <- writeSeralStageMapBC(cd = fcd, pgm = fpgm, ndtbec = fNDTBEC)

  if (!is.na(P(sim)$sieveThresh)) {
    ## pass ssm through terra::sieve to merge singletons with neighbouring large patches?
    ## <https://rspatial.github.io/terra/reference/sieve.html>
    ssmFiles <- vapply(
      ssmFiles,
      function(f) {
        ## clumps < threshold merged with largest neighbour
        fs <- .suffix(f, sprintf("-sieve%d", as.integer(P(sim)$sieveThresh))) ## TODO: use round() ??
        terra::sieve(rast(f), threshold = P(sim)$sieveThresh, filename = fs, overwrite = TRUE)
        fs
      },
      character(1)
    )
  }

  mod$ssm0 <- grep("/seralStageMap_year0000.*[.]tif$", ssmFiles, value = TRUE)
  mod$ssm <- grep("/seralStageMap_year0000.*[.]tif$", ssmFiles, invert = TRUE, value = TRUE)

  return(invisible(sim))
}

patchMetricsSeralBC <- function(sim) {
  fflm <- mod$flm
  fssm0 <- mod$ssm0
  fssm <- mod$ssm
  browser()
  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)

  funList <- default_patch_metrics_seral() ## TODO: pass further up via parameter funList_bc

  rptPolygons <- lapply(sim$reportingPolygons, sf::st_as_sf) ## converts to sf, keeping names
  rptPolyCols <- vapply(
    sim$reportingPolygons,
    FUN = attr,
    which = "field",
    FUN.VALUE = character(1)
  )
  rptPolyNames <- names(sim$reportingPolygons)

  oldPlan <- plan(workers = pemisc::optimalClusterNum(5000, length(fssm)))
  on.exit(future::plan(oldPlan), add = TRUE)

  lapply(
    rptPolyNames,
    function(p, reportingPolygons, reportingPolygonCols, studyArea) {
      message(crayon::magenta("Calculating seral stage patch metrics for", p, "..."))

      rptPoly <- reportingPolygons[[p]]

      if (is(rptPoly, "sf") && sf::st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON") {
        rptPoly <- sf::st_collection_extract(rptPoly, "POLYGON")
      }
      rptPoly <- sf::st_crop(rptPoly, studyArea) ## ensure cropped to studyArea
      rptPolyCol <- reportingPolygonCols[[p]]
      refCode <- paste0("sspm_", abbreviate(p, minlength = 8)) ## TODO: is this unique enough?
      refCodeCC <- paste0(refCode, "_CC")

      ## CC
      fileInfo <- file.info(fssm)[, c("size", "mtime")]
      dfl_cc <- calculatePatchMetricsSeral(
        ssm = fssm0,
        flm = fflm,
        summaryPolys = rptPoly,
        polyCol = rptPolyCol,
        funList = funList[[1]] ## TODO: temporarily, only patchAreasSeral
      ) |>
        Cache(.cacheExtra = fileInfo)

      lapply(names(dfl_cc), function(f) {
        write.csv(
          dfl_cc[[f]],
          file.path(outputPath(sim), paste0(refCodeCC, "_", f, "_raw.csv")),
          row.names = FALSE
        )
      })
      mod[[refCodeCC]] <- summarizePatchMetricsSeral(dfl_cc)
      lapply(names(mod[[refCodeCC]]), function(f) {
        write.csv(
          mod[[refCodeCC]][[f]],
          file.path(outputPath(sim), paste0(refCodeCC, "_", f, ".csv")),
          row.names = FALSE
        )
      })

      ## simulation results
      fileInfo <- file.info(mod$ssm)[, c("size", "mtime")]
      dfl <- Cache(
        calculatePatchMetricsSeral,
        ssm = fssm,
        flm = fflm,
        summaryPoly = rptPoly,
        polyCol = rptPolyCol,
        funList = funList[[1]], ## TODO: temporarily, only patchAreasSeral
        .cacheExtra = fileInfo
      )
      lapply(names(dfl), function(f) {
        write.csv(
          dfl[[f]],
          file.path(outputPath(sim), paste0(refCode, "_", f, "_raw.csv")),
          row.names = FALSE
        )
      })
      mod[[refCode]] <- summarizePatchMetricsSeral(dfl)
      lapply(names(mod[[refCode]]), function(f) {
        if (refCode == "sspm_NDTBEC" && f == "patchAreasSeral") {
          seral_table <- mod[[refCode]][[f]] |>
            na.omit() |>
            mutate(
              class = as.factor(class),
              poly = as.factor(poly),
              mm = NULL,
              q1 = NULL,
              md = NULL,
              q3 = NULL,
              mx = NULL,
              sd = NULL,
              cv = NULL,
              se = NULL,
              ci = NULL,
              n = NULL
            ) |>
            ungroup() |>
            summarize(area = sum(N * mn, na.rm = TRUE), .by = c("class", "poly", "time")) |>
            mutate(totalArea = sum(area, na.rm = TRUE), .by = c("poly", "time")) |>
            summarize(
              minPctArea = 100 * min(area / totalArea, na.rm = TRUE),
              meanPctArea = 100 * mean(area / totalArea, na.rm = TRUE),
              maxPctArea = 100 * max(area / totalArea, na.rm = TRUE),
              .by = c("class", "poly")
            )

          write.csv(seral_table, file.path(outputPath(sim), "SeralTable.csv"), row.names = FALSE)
        }
        write.csv(
          mod[[refCode]][[f]],
          file.path(outputPath(sim), paste0(refCode, "_", f, ".csv")),
          row.names = FALSE
        )
      })

      return(invisible(NULL))
    },
    studyArea = studyAreaReporting,
    reportingPolygons = rptPolygons,
    reportingPolygonCols = rptPolyCols
  )

  return(invisible(sim))
}

### plotting
plotFun <- function(sim) {
  # ! ----- EDIT BELOW ----- ! #

  pngs_lm <- pngs_pm <- pngs_bc <- pngs_on <- list()

  if ("lm" %in% tolower(P(sim)$postprocessEvents)) {
    pngs_lm <- lapply(mod$rptPolyNames, function(p) {
      rptPoly <- sim$reportingPolygons[[p]]

      if (is(rptPoly, "Spatial")) {
        rptPoly <- sf::st_as_sf(rptPoly)
      } else if (
        is(rptPoly, "sf") && sf::st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON"
      ) {
        rptPoly <- sf::st_collection_extract(rptPoly, "POLYGON")
      }

      rptPolyCol <- "NAME"
      refCode <- paste0("lm_", rptPoly[["ID"]])
      refCodeCC <- paste0(refCode, "_CC")

      lapply(names(mod[[refCode]]), function(f) {
        ## TODO: use Plots
        gg1 <- plot_over_time(mod[[refCode]][[f]], substr(f, 7, nchar(f))) +
          geom_hline(
            data = mod[[refCodeCC]][[f]],
            aes(yintercept = mn),
            col = "darkred",
            linetype = 2
          )
        nPages <- n_pages(gg1)
        lapply(seq_len(nPages), function(pg) {
          gg <- plot_over_time(mod[[refCode]][[f]], substr(f, 7, nchar(f)), page = pg) +
            geom_hline(
              data = mod[[refCodeCC]][[f]],
              aes(yintercept = mn),
              col = "darkred",
              linetype = 2
            )
          file.path(figurePath(sim), paste0(f, "_facet_by_", refCode, "_p", pg, ".png")) |>
            ggsave(gg, height = 10, width = 16)
        })
      }) |>
        unlist()
    })

    sim <- registerOutputs(pngs_lm, sim)
  }

  if ("pm" %in% tolower(P(sim)$postprocessEvents)) {
    pngs_pm <- lapply(mod$rptPolyNames, function(p) {
      rptPoly <- sim$reportingPolygons[[p]]

      if (is(rptPoly, "Spatial")) {
        rptPoly <- sf::st_as_sf(rptPoly)
      } else if (
        is(rptPoly, "sf") && sf::st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON"
      ) {
        rptPoly <- sf::st_collection_extract(rptPoly, "POLYGON")
      }
      browser()
      rptPolyCol <- "NAME"
      refCode <- paste0("pm_", rptPoly[["ID"]])
      refCodeCC <- paste0(refCode, "_CC")

      pngs_pm_a <- lapply(names(mod[[refCode]]), function(f) {
        ## TODO: use Plots
        ggbox1 <- plot_by_class(mod[[refCode]][[f]], "box") +
          geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
        nPages <- n_pages(ggbox1)
        lapply(seq_len(nPages), function(pg) {
          ggbox <- plot_by_class(mod[[refCode]][[f]], "box", page = pg) +
            geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
          file.path(
            figurePath(sim),
            paste0(f, "_facet_by_", refCode, "_box_plot", "_p", pg, ".png")
          ) |>
            ggsave(ggbox, height = 10, width = 16)
        })
      }) |>
        unlist()

      pngs_pm_b <- lapply(names(mod[[refCode]]), function(f) {
        ## TODO: use Plots
        ggvio1 <- plot_by_class(mod[[refCode]][[f]], "violin") +
          geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
        nPages <- n_pages(ggvio1)
        lapply(seq_len(nPages), function(pg) {
          ggvio <- plot_by_class(mod[[refCode]][[f]], "violin", page = pg) +
            geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
          ggsave(
            file.path(
              figurePath(sim),
              paste0(f, "_facet_by_", refCode, "_vio_plot", "_p", pg, ".png")
            ),
            ggvio,
            height = 10,
            width = 16
          )
        })
      }) |>
        unlist()

      c(pngs_pm_a, pngs_pm_b)
    })

    sim <- registerOutputs(pngs_pm, sim)
  }

  if ("bc" %in% tolower(P(sim)$postprocessEvents)) {
    pngs_bc <- lapply(mod$rptPolyNames, function(p) {
      rptPoly <- sim$reportingPolygons[[p]]

      if (is(rptPoly, "Spatial")) {
        rptPoly <- st_as_sf(rptPoly)
      } else if (is(rptPoly, "sf") && st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON") {
        rptPoly <- st_collection_extract(rptPoly, "POLYGON")
      }
      browser()
      rptPolyCol <- "NAME"
      refCode <- paste0("sspm_", rptPoly[["ID"]])
      refCodeCC <- paste0(refCode, "_CC")

      pngs_bc_a <- lapply(names(mod[[refCode]]), function(f) {
        ggbox1 <- plot_by_class(mod[[refCode]][[f]], "box") +
          geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
        nPages <- n_pages(ggbox1)
        lapply(seq_len(nPages), function(pg) {
          ggbox <- plot_by_class(mod[[refCode]][[f]], "box", page = pg) +
            geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
          ggsave(
            file.path(
              figurePath(sim),
              paste0(f, "_facet_by_", refCode, "_box_plot", "_p", pg, ".png")
            ),
            ggbox,
            height = 10,
            width = 16
          )
        })
      }) |>
        unlist()

      pngs_bc_b <- lapply(names(mod[[refCode]]), function(f) {
        ggvio1 <- plot_by_class(mod[[refCode]][[f]], "violin") +
          geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
        nPages <- n_pages(ggvio1)
        lapply(seq_len(nPages), function(pg) {
          ggvio <- plot_by_class(mod[[refCode]][[f]], "violin", page = pg) +
            geom_point(data = mod[[refCodeCC]][[f]], col = "darkred", size = 2.5)
          ggsave(
            file.path(
              figurePath(sim),
              paste0(f, "_facet_by_", refCode, "_vio_plot", "_p", pg, ".png")
            ),
            ggvio,
            height = 10,
            width = 16
          )
        })
      }) |>
        unlist()

      pngs_bc_c <- lapply(names(mod[[refCode]]), function(f) {
        gg1 <- plot_over_time_by_class(mod[[refCode]][[f]], f) +
          geom_hline(data = mod[[refCodeCC]][[f]], aes(yintercept = mn), linetype = 2)
        nPages <- n_pages(gg1)
        lapply(seq_len(nPages), function(pg) {
          gg <- plot_over_time_by_class(mod[[refCode]][[f]], f, page = pg) +
            geom_hline(data = mod[[refCodeCC]][[f]], aes(yintercept = mn), linetype = 2)
          ggsave(
            file.path(figurePath(sim), paste0(f, "_facet_by_", refCode, "_p", pg, ".png")),
            gg,
            height = 10,
            width = 16
          )
        })
      }) |>
        unlist()

      c(pngs_bc_a, pngs_bc_b, pngs_bc_c)
    })

    sim <- registerOutputs(pngs_bc, sim)
  }

  if ("on" %in% tolower(P(sim)$postprocessEvents)) {
    ## TODO
  }

  # ! ----- STOP EDITING ----- ! #
  return(invisible(sim))
}

.inputObjects <- function(sim) {
  ## nothing here

  return(invisible(sim))
}
