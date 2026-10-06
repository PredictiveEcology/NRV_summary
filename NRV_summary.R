defineModule(sim, list(
  name = "NRV_summary",
  description = paste("NRV simulation post-processing and summary creation.",
                      "Produces summaries for multiple patch metrics and other indicators."),
  keywords = c("NRV"),
  authors = c(
    person(c("Alex", "M."), "Chubaty", email = "achubaty@for-cast.ca", role = c("aut"))
  ),
  childModules = character(0),
  version = list(NRV_summary = "2.0.0.9025"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  loadOrder = list(after = c("Biomass_core")),
  documentation = list("README.md", "NRV_summary.Rmd"), ## .md produced from .Rmd
  reqdPkgs = list(
    "crayon", "data.table", "dplyr", "fs", "future", "future.apply", "future.callr",
    "ggforce", "ggplot2", "gifski", "googledrive", "landscapemetrics", "qs2",
    "RColorBrewer", "reproducible", "sf", "terra", "tidyterra",
    "PredictiveEcology/LandR@development (>= 1.2.0.9024)",
    "PredictiveEcology/LandWebUtils@development (>= 1.0.3.9016)",
    ## 0.2.10 floor, not 0.2.7: the LandWeb#118 tenure x sub-region crossings mint refCodes of the
    ## form <kind>_<slug> whose subregion names themselves contain "_", and nrvtools < 0.2.10 aborts
    ## calculatePatchMetrics()/calculatePatchMetricsSeral()/nrv_metrics_landscape() on those with
    ## "polyName contains too many underscores". 0.2.10 also gives summarize_nrv() rptPoly
    ## auto-detection, so metrics summarised over SEVERAL reporting layers aggregate without
    ## collapsing across them -- exactly the crossed-layer case -- and fixes nrv_metrics_landscape()
    ## stamping rep/time/poly from full-length vectors onto the already row-bound table, which
    ## shifted every later row's identifiers by one subregion whenever a subregion came back empty.
    ## 0.2.11, not 0.2.10: calculateLandWebMetrics() (the `lw` path) still split result names on
    ## "_" and purrr::transpose()d them, so a reporting layer mixing 1- and 2-token polygon
    ## names (the tenure layer holds both "ANC" and "DawsonCreek_TSA") recombined into the
    ## cartesian product of tokens -- 45 fabricated tenures in place of 11, 6 dropped. Wrong
    ## but non-blank labels, and the run completes, so nothing catches it downstream.
    "FOR-CAST/nrvtools@development (>= 0.2.11)",
    "PredictiveEcology/pemisc@development (>= 0.0.4.9016)",
    "PredictiveEcology/SpaDES.core@development (>= 3.2.1.9001)" ## dirnamesFromSet(), resolveSimYears(), padYears()
  ),
  parameters = bindrows(
    defineParameter("ageClasses", "character", LandWebUtils:::.ageClasses, NA, NA,
                    "descriptions/labels for age classes (seral stages)"),
    defineParameter("ageClassCutOffs", "integer", LandWebUtils:::.ageClassCutOffs, NA, NA,
                    "defines the age boundaries between age classes"),
    defineParameter("ageClassMaxAge", "integer", 400L, NA, NA,
                    "maximum possible age"),
    defineParameter("patchDirections", "integer", 4L, 4L, 8L,
                    paste("patch connectivity for the 'lw' (LandWeb summary) large-patch analysis,",
                          "passed to `nrvtools::largePatchCounts()` (via `landscapemetrics::get_patches`):",
                          "`4` = rook / 4-connected (matches v2's GDAL `polygonize`; the default),",
                          "`8` = queen / 8-connected. NOTE: v2 was fixed at 4-connectivity;",
                          "exposing 8 (queen) is a departure from v2.")),
    defineParameter("mixedType", "integer", 2L,
                    desc = paste("How to define mixed stands: `0L` for none; `1L` for any species admixture;",
                                 "`2L` for deciduous > conifer. See `LandR::vegTypeMapGenerator`.")),
    defineParameter("mode", "character", "single", NA, NA,
                    paste("use 'single' to run part of a simulation;",
                          "use 'multi' to run as part of postprocessing multiple runs.")),
    defineParameter("reuseAggregates", "logical", FALSE, NA, NA,
                    paste("(mode = 'multi') if TRUE, reuse a complete per-replicate `_aggregates`",
                          "parquet dataset instead of recomputing it, re-summarizing the surviving",
                          "parquets to regenerate the envelopes/CSVs/figures. Use to iterate on the",
                          "plots/CSVs without re-running the (~hours) landscape-metric aggregation;",
                          "leave FALSE for a fresh run.")),
    defineParameter("plotWorkers", "integer", 8L, 1L, NA,
                    paste("(mode = 'multi') hard cap on the number of local worker processes used to",
                          "render the postprocess figures in parallel (each figure is an independent",
                          "`ggsave`). The actual count is RAM-aware (`pemisc::optimalClusterNum`) but",
                          "never exceeds this cap, so a shared compute node is not swamped; 1 renders",
                          "sequentially. Uses `future` multisession (not fork; the crew worker is a",
                          "mirai daemon).")),
    defineParameter("postprocessEvents", "character", c("lm", "pm"), NA, NA,
                    paste("Specify which subset of postprocessing events to run.",
                          "At least one of:",
                          "'am' for the stand-age time-series animation (GIF);",
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
    defineParameter("stabilityAlpha", "numeric", 0.05, 0, 1,
                    paste("(mode = 'multi') significance level of the Mann-Kendall trend test in the",
                          "stability check.")),
    defineParameter("stabilityMinChange", "numeric", 0.10, 0, 1,
                    paste("(mode = 'multi') a series is flagged 'still changing' only if its fitted change",
                          "across the stability window exceeds this fraction of the series' range",
                          "(its largest minus smallest value over all reps within the window), as well as",
                          "being a significant trend.")),
    defineParameter("stabilityWindow", "numeric", 0.5, 0, 1,
                    paste("(mode = 'multi') the last fraction of `summaryPeriod` over which the stability",
                          "check looks for a directional trend (0.5 = the last half). A run whose",
                          "metrics are still trending there needs to be longer. It does not define the NRV",
                          "(see `nrvWindow`).")),
    defineParameter("nrvWindow", "numeric", 0.3, 0, 1,
                    paste("the NRV is the last fraction of `summaryPeriod` (0.3 = the last 30%; in a 1000-year",
                          "run, years 700-1000). Must be above 0 and at most 1. The NRV range and the current",
                          "condition overview use only the summary times in it; the time-series figures still",
                          "show all of `summaryPeriod`, with the NRV years shaded.")),
    defineParameter("summaryInterval", "integer", 100L, NA, NA,
                    "simulation time interval at which to take 'snapshots' used for summary analyses."),
    defineParameter("summaryPeriod", "integer", c(start(sim), end(sim)), NA, NA,
                    paste("lower and upper end of the range of simulation times summarised and shown in the",
                          "time-series figures; default is the whole run. The NRV is the last `nrvWindow`",
                          "fraction of it.")),
    defineParameter("timeSeriesTimes", "numeric", NA_real_, NA, NA,
                    paste("simulation times for which to build time series animations; default (NA) is",
                          "start + 601:650 when the run is that long, otherwise the last 50 years of the run.")),
    defineParameter("vegLeadingProportion", "numeric", LandR::leadingSpeciesProp(),
                    0.0, 1.0,
                    desc = paste("a number that defines whether a species is leading for a given pixel.",
                                 "Default: `LandR::leadingSpeciesProp()`, i.e. option `LandR.leadingSpeciesProp`,",
                                 "which takes `LandR.mixedwoodProp` (0.75) unless set. Setting it in one place",
                                 "moves every module and LandR function together.")),
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
    expectsInput("LandTypeCC_reporting", "SpatRaster",
                 desc = paste("Current-conditions land cover (Canada LCC 2020) with urban RETAINED.",
                              "Used to correct the year-0 current-condition snapshot: the simulation",
                              "imputes urban to its nearest forest type (pre-industrial state), so the",
                              "year-0 rasters would otherwise report imputed forest as real current",
                              "forest. Only urban differs between the sim and reporting layers --",
                              "water/barren/snow are already NA on both sides.")),
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
      ## No tree species in this study area (sppEquiv has no rows, established by fireSense_ELFs):
      ## there is no vegetation to summarise, so schedule nothing.
      if (is.data.frame(sim$sppEquiv) && nrow(sim$sppEquiv) == 0L) {
        message("NRV_summary: no tree species in this study area; no vegetation summaries")
        return(invisible(sim))
      }

      if (min(P(sim)$summaryPeriod) < start(sim) || max(P(sim)$summaryPeriod) > end(sim)) {
        stop("summaryPeriod values are outside the range of simulation times")
      }
      if (!(P(sim)$nrvWindow > 0 && P(sim)$nrvWindow <= 1)) {
        stop("nrvWindow must be above 0 and at most 1")
      }
      if (all(is.na(P(sim)$timeSeriesTimes))) {
        P(sim)$timeSeriesTimes <- if (end(sim) >= start(sim) + 650) {
          start(sim) + 601:650
        } else {
          seq(max(start(sim), end(sim) - 49), end(sim))
        }
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

        ## also generate + save the stand-age / veg-type maps at each timeSeriesTimes
        ## year, so the animation has its frames (read back in mode = "multi"). These
        ## typically fall outside summaryPeriod, so they are not covered by the
        ## summaryInterval reschedule; schedule map_generators before save_single so
        ## the maps exist when saved.
        for (tst in P(sim)$timeSeriesTimes) {
          sim <- scheduleEvent(sim, tst, "NRV_summary", "map_generators", .last())
          sim <- scheduleEvent(sim, tst, "NRV_summary", "save_single", .last())
        }
      } else if (P(sim)$mode == "multi") {
        stopifnot(!is.null(sim$reportingPolygons))

        ## reuse complete _aggregates parquet datasets (skip the ~2h landscape-metric recompute) so
        ## the postprocess events can iterate on plots/CSVs; read by .buildRepDataset() (process-local).
        options(NRV_summary.reuseAggregates = isTRUE(P(sim)$reuseAggregates))

        sim <- InitMulti(sim)

        if ("am" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "animation", .last())
        }

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

        ## after the metric events above, whose parquet datasets and the burn blocks it reads
        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_stability", .last() + 1)

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
      ## TODO: not yet implemented
      message("NRV_summary: the `fd` postprocess event is not yet implemented.")
    },
    postprocess_lw = {
      sim <- landWebMetrics(sim)
    },
    postprocess_stability = {
      sim <- stabilityCheck(sim)
    },
    postprocess_bc = {
      sim <- makeSeralStageMapsBC(sim)
      sim <- patchMetricsSeralBC(sim)
    },
    postprocess_on = {
      ## TODO finalize implementation
      message("Ontario NRV metrics are not yet fully implemented.")
    },
    animation = {
      sim <- makeAnimation(sim)
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
      ## stand-age + veg-type maps are saved at the summary times AND at each
      ## timeSeriesTimes year (the animation frames, read back in mode = "multi").
      ## cohortData + pixelGroupMap are only needed at the summary analysis times,
      ## so they are NOT written at the (many) timeSeriesTimes years.
      times_during <- c(start(sim), end(sim), mod$analysesOutputsTimes) |> unique() |> sort()
      times_maps <- c(times_during, P(sim)$timeSeriesTimes) |> unique() |> sort()

      if (time(sim) %in% times_maps) {
        f_standAgeMap <- file.path(outputPath(sim), paste0("standAgeMap_year", padYear, ".tif"))
        terra::writeRaster(mod$standAgeMap, f_standAgeMap, datatype = "INT2U", overwrite = TRUE)
        sim <- registerOutputs(f_standAgeMap, sim)

        f_vegTypeMap <- file.path(outputPath(sim), paste0("vegTypeMap_year", padYear, ".tif"))
        terra::writeRaster(mod$vegTypeMap, f_vegTypeMap, datatype = "INT2U", overwrite = TRUE)
        sim <- registerOutputs(f_vegTypeMap, sim)
      }

      if (time(sim) %in% times_during) {
        f_cohortData <- file.path(outputPath(sim), paste0("cohortData_year", padYear, ".qs2"))
        qs2::qs_save(sim$cohortData, f_cohortData)
        sim <- registerOutputs(f_cohortData, sim)

        f_pixelGroupMap <- file.path(outputPath(sim), paste0("pixelGroupMap_year", padYear, ".tif"))
        terra::writeRaster(sim$pixelGroupMap, f_pixelGroupMap, datatype = "INT4U", overwrite = TRUE)
        sim <- registerOutputs(f_pixelGroupMap, sim)

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
  mod$useOutputs <- NROW(sim$outputsDF) > 0
  ## a file saved more than once (e.g. the last year, by the sim's own save and again at the end of
  ## the run) is registered more than once in outputsDF; it is still one file per rep and year, and
  ## repeating it would repeat that rep's row at that time in the envelopes (n_reps > number of reps).
  ## Sorted, so each rep's veg-type and stand-age maps are listed in the same year order: the patch
  ## metrics pair them by position (outputsDF is in the order the files were saved, which is not
  ## the same for the two kinds).
  outFiles <- sort(unique(sim$outputsDF$file))
  mod$allReps <- dirnamesFromSet(outFiles, P(sim)$reps)

  ## assigned back: P(sim)$simTimes is read downstream, not just for padding
  P(sim)$simTimes <- resolveSimYears(P(sim)$simTimes, sim)
  pad <- padYears(P(sim)$simTimes)

  ## where rep 1's outputs are: with outputsDF, wherever they were saved (in multi mode `outputPath(sim)`
  ## is the summary directory, not a replicate's); otherwise `outputPath(sim)/<rep>`.
  rep1Dir <- if (mod$useOutputs) {
    dirnamesFromSet(outFiles, P(sim)$reps, leafOnly = FALSE)[1]
  } else {
    file.path(outputPath(sim), mod$allReps[1])
  }

  ## all reps have same flammable map
  mod$flm <- file.path(rep1Dir, paste0("flammableMap_year", pad$end, ".tif"))

  ## current-conditions reference = the sim's saved year-0 state (the deterministic
  ## initial condition, identical across reps -- read from rep 1). Read directly so
  ## the CC snapshot needs no regeneration from speciesLayers / no "CC SAM" input,
  ## and no write-before-read ordering between the landscape + patch metric events.
  mod$fvtm0 <- file.path(rep1Dir, paste0("vegTypeMap_year", pad$start, ".tif"))
  mod$fsam0 <- file.path(rep1Dir, paste0("standAgeMap_year", pad$start, ".tif"))
  ## current-conditions time-since-fire (burnSummaries output); age basis for the LandWeb summaries.
  mod$ftsf0 <- file.path(rep1Dir, paste0("rstTimeSinceFire_year", pad$start, ".tif"))

  ## The year-0 rasters are the SIMULATION's initial state, in which urban has been imputed to its
  ## nearest forest type so the run approximates a pre-industrial landscape. Reporting current
  ## condition from them unchanged would count that imputed forest as real forest today. Re-remove
  ## urban here, using the reporting copy of the current-conditions land cover.
  ## Urban is the ONLY class that differs between the sim and reporting layers: water/barren/
  ## snow-ice are sent to NA by `remapDT` on both sides, so nothing else needs correcting.
  ## The NRV envelope (built from the replicates) is deliberately NOT masked -- the envelope is the
  ## pre-industrial landscape, the marker is today's, and that difference IS the land-conversion
  ## component of the departure.
  ccrep <- sim$LandTypeCC_reporting
  if (is.null(ccrep)) {
    ## do not fail silently: a missing layer here would look identical to "no urban present".
    warning("NRV_summary: `LandTypeCC_reporting` is absent; current-condition metrics will ",
            "report simulation year-0 state, counting urban imputed to forest as current forest.",
            call. = FALSE)
  } else {
    urbanMask <- terra::ifel(ccrep == 17L, NA, 1L) ## 17 = urban (LCC 2020)
    ccDir <- checkPath(file.path(outputPath(sim), "_cc"), create = TRUE)
    mod$fvtm0 <- .maskCC(mod$fvtm0, urbanMask, file.path(ccDir, "cc_vegTypeMap.tif"))
    mod$fsam0 <- .maskCC(mod$fsam0, urbanMask, file.path(ccDir, "cc_standAgeMap.tif"))
    mod$ftsf0 <- .maskCC(mod$ftsf0, urbanMask, file.path(ccDir, "cc_rstTimeSinceFire.tif"))
  }

  ## the files of one kind in the reps: from outputsDF, or by searching `outputPath(sim)`
  filesOf <- function(regexp) {
    files <- if (mod$useOutputs) {
      grep(regexp, outFiles, value = TRUE)
    } else {
      as.character(fs::dir_ls(outputPath(sim), regexp = regexp, recurse = 1, type = "file"))
    }
    grep(paste0("(", paste0(mod$allReps, collapse = "|"), ")"), x = files, value = TRUE)
  }
  yearsPattern <- paste(mod$analysesOutputsTimes, collapse = "|")
  cdpgm <- grep(yearsPattern, x = filesOf("cohortData|pixelGroupMap"), value = TRUE)
  mod$allouts <- grep("gri|png|txt|xml", x = filesOf("vegType|standAge"), value = TRUE, invert = TRUE)

  if (mod$useOutputs) {
    mod$allouts2 <- mod$allouts
  } else {
    mod$allouts2 <- paste(
      paste0(
        "year",
        paddedFloatToChar(
          setdiff(c(0, P(sim)$timeSeriesTimes), mod$analysesOutputsTimes),
          padL = pad$padL
        )
      ),
      collapse = "|"
    ) |>
      grep(pattern = _, x = mod$allouts, value = TRUE, invert = TRUE)

    filesUserHas <- c(cdpgm, mod$allouts2)

    dirsExpected <- file.path(outputPath(sim), mod$allReps)
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
  }

  mod$sam <- gsub(".*vegTypeMap.*", NA, mod$allouts2) |>
    grep(paste(mod$analysesOutputsTimes, collapse = "|"), x = _, value = TRUE)
  mod$vtm <- gsub(".*standAgeMap.*", NA, mod$allouts2) |>
    grep(paste(mod$analysesOutputsTimes, collapse = "|"), x = _, value = TRUE)

  ## time-since-fire per year (burnSummaries output), aligned with mod$vtm by rep/year path (see
  ## landWebMetrics(): the LandWeb summaries bin time-since-fire into age classes, matching v2).
  mod$tsf <- gsub("vegTypeMap", "rstTimeSinceFire", mod$vtm)

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

## ---- arrow-native NRV summary helpers (nrvtools >= 0.1.0) --------------------------------------
## Replicated metrics are summarised through nrvtools' Arrow-native path (see the "Memory-bounded NRV
## summaries" vignette): each replicate's raw metric table is written to its own parquet partition
## under `<outputPath>/_aggregates/<refCode>/replicate=<rep>/`, then `summarize_nrv()` reduces across
## replicates by pushing the aggregation down to Arrow compute, so the per-replicate rows are never
## all held in memory at once. This replaces the former in-memory `calculateLandscapeMetrics()` /
## `summarizePatchMetrics()` reduction (both removed from nrvtools >= 0.1.0); the raw producers
## (`nrv_metrics_landscape()`, `calculatePatchMetrics()`, `calculatePatchMetricsSeral()`) now return
## the raw per-replicate long table (schema: level/class/metric/value/rep/time/poly) which
## `tidy_nrv_metrics()` binds and `summarize_nrv()` reduces to the mean/sd/min/max/... envelope.

## Post-processing outputs (parquet aggregates, figures, csv) live under
## `outputs/<studyArea>/postprocess/` -- a sibling of the mainSim rep dirs, which are still READ from
## `outputPath(sim)` (= outputs/<studyArea>/mainSim). `figures/` and `csv/` mirror the same
## `<kind>/<layer>/` sub-structure (kind = lm/pm/boxplots/histograms/...; layer = the full
## reporting-polygon-layer name), so a human can find a figure and its data side by side.
## Mask a year-0 current-condition raster by `urbanMask` (NA where urban) and write it to
## `outFile`, returning that path. Returns the ORIGINAL path unchanged if the source is missing or
## the geometries do not line up, so a grid mismatch degrades to "uncorrected" loudly rather than
## producing a silently wrong current-condition value.
.maskCC <- function(f, urbanMask, outFile) {
  if (!file.exists(f)) return(f)
  r <- terra::rast(f)
  if (!isTRUE(terra::compareGeom(r, urbanMask, stopOnError = FALSE))) {
    warning("NRV_summary: current-condition layer does not match ", basename(f),
            "; leaving it uncorrected (urban will count as forest).", call. = FALSE)
    return(f)
  }
  terra::mask(r, urbanMask, filename = outFile, overwrite = TRUE,
              wopt = list(datatype = terra::datatype(r)))
  outFile
}

## Clip reporting polygons to the study area.
##
## terra::crop(), NOT sf::st_crop(): st_crop() clips to the study area's BOUNDING BOX, so for a
## non-rectangular study area it keeps polygon area lying outside it. Clipping ANSR by the
## WF_Hinton FMA gives 15,428 km2 / 23 features by bbox versus 9,594 km2 / 22 by geometry -- a 61%
## overstatement that every per-reporting-polygon metric would inherit. terra::crop() intersects
## GEOMETRY, and as a side benefit does not emit sf's "attribute variables are assumed to be
## spatially constant" warning (138 per summaries run); the attributes here are labels (Name), so
## there was never anything to re-apportion.
##
## Returns sf: callers index the result as a data frame (`rptPoly[[col]]`, `rptPoly[cond, ]`), and
## `[[` on a SpatVector returns a one-column data.frame rather than a vector.
.cropToStudyArea <- function(x, y) {
  ## vect() errors on SpatVector input, so only convert what is not already one.
  xv <- if (inherits(x, "SpatVector")) x else terra::vect(x)
  yv <- if (inherits(y, "SpatVector")) y else terra::vect(y)
  ## a CRS mismatch makes terra::crop() return an empty SpatVector rather than erroring, which
  ## downstream reads as "this layer has no polygons in the study area" -- reproject instead.
  if (!terra::same.crs(xv, yv)) {
    yv <- terra::project(yv, terra::crs(xv))
  }
  sf::st_as_sf(terra::crop(xv, yv))
}

## Set the future plan to the current strategy with `nWorkers` workers; returns the previous plan.
## `sequential` has no `workers` argument, so tweaking it only warns ("unknown future arguments").
.planWithWorkers <- function(nWorkers) {
  strategy <- future::plan()
  if (!inherits(strategy, "sequential")) {
    strategy <- future::tweak(strategy, workers = nWorkers)
  }
  future::plan(strategy)
}

.ppRoot <- function(sim) {
  file.path(dirname(outputPath(sim)), "postprocess")
}

## `<postprocess>/_aggregates/<refCode>` -- the parquet dataset root for one refCode.
.nrvAggRoot <- function(sim, refCode) {
  file.path(.ppRoot(sim), "_aggregates", refCode)
}

## figure / csv output dir for one analysis `kind` and reporting `layer` (created on demand).
.ppFigDir <- function(sim, kind, layer, ...) {
  reproducible::checkPath(file.path(.ppRoot(sim), "figures", kind, layer, ...), create = TRUE)
}
.ppCsvDir <- function(sim, kind, layer, ...) {
  reproducible::checkPath(file.path(.ppRoot(sim), "csv", kind, layer, ...), create = TRUE)
}

## split a per-replicate map-file vector (`.../rep<NN>/<map>_year<YYYY>.tif`) into a named list by rep.
.filesByRep <- function(files) {
  split(files, basename(dirname(files)))
}

## The files of `files` (named `..._year<YYYY>.<ext>`) whose year is within `period`. Used for the pooled
## (over time) NRV distributions, which cover the NRV years only.
.filesInPeriod <- function(files, period) {
  yr <- as.integer(sub("^.*_year([0-9]+)\\.[^.]*$", "\\1", basename(files)))
  files[!is.na(yr) & yr >= min(period) & yr <= max(period)]
}

## TRUE iff `root` already holds a `replicate=<id>/*.parquet` partition for EVERY requested repID,
## i.e. the parquet dataset is complete and can be reused instead of recomputed.
.aggComplete <- function(root, repIDs) {
  dir.exists(root) &&
    all(vapply(repIDs, function(r) {
      length(list.files(file.path(root, paste0("replicate=", r)), pattern = "\\.parquet$")) > 0L
    }, logical(1L)))
}

## Build the parquet dataset for one refCode and return the across-replicate envelope.
## `compute_fn(repID)` returns the raw metric list for one replicate (from a raw nrvtools producer).
## `reuse = TRUE` skips the (expensive) recompute + rewrite when the dataset is already complete for
## `repIDs` (see `.aggComplete()`), re-summarizing the surviving parquets -- useful for iterating on
## the plots/CSVs without re-running the landscape-metric aggregation.
.buildRepDataset <- function(root, repIDs, compute_fn, studyArea = NULL, scenario = NULL,
                             id_cols = NULL, reuse = getOption("NRV_summary.reuseAggregates", FALSE)) {
  if (!(reuse && .aggComplete(root, repIDs))) {
    unlink(root, recursive = TRUE)
    for (repID in repIDs) {
      tidied <- tidy_nrv_metrics(compute_fn(repID), studyArea = studyArea, scenario = scenario)
      write_nrv_parquet(tidied, root, replicate = repID)
    }
  }
  ## id_cols = NULL -> summarize_nrv() default (per-time envelopes); the LandWeb summaries pass an
  ## explicit set excluding `time` so the NRV distribution pools across replicates AND summary years.
  summarize_nrv(root, id_cols = id_cols)
}

## Write the range-of-variation envelope for one refCode + reporting `layer` under csv/<kind>/<layer>/:
## a combined `<base>.csv` plus one `<base>_<metric>.csv` per metric. `kind` (lm/pm/sspm/lw) and the
## `_CC` suffix are recovered from `refCode`; the enclosing <kind>/<layer>/ dir supplies the context
## the flat filenames used to carry, and it mirrors the figure dir structure. The `lw` (LandWeb
## summary) envelope is split by analysis -- leadingProp -> csv/boxplots/<layer>/ (the leading
## boxplot data), the large-patch metrics -> csv/histograms/<layer>/.
.writeNrvSummaryCSVs <- function(sim, env, refCode, layer) {
  if (is.null(env) || !nrow(env)) {
    return(invisible(character(0)))
  }
  kind <- sub("_.*$", "", refCode)
  cc <- if (grepl("_CC$", refCode)) "_CC" else ""
  writeSet <- function(e, k, base) {
    if (is.null(e) || !nrow(e)) {
      return(invisible())
    }
    d <- .ppCsvDir(sim, k, layer)
    write.csv(e, file.path(d, paste0(base, cc, ".csv")), row.names = FALSE)
    for (m in unique(e$metric)) {
      write.csv(e[e$metric == m, ], file.path(d, paste0(base, cc, "_", m, ".csv")), row.names = FALSE)
    }
  }
  if (kind == "lw") {
    isLead <- env$metric == "leadingProp"
    writeSet(env[isLead, , drop = FALSE], "boxplots", "leading")
    writeSet(env[!isLead, , drop = FALSE], "histograms", "largePatches")
  } else {
    writeSet(env, kind, kind)
  }
  invisible()
}

## build landscape metric envelopes from vegetation type maps (VTMs)
landscapeMetrics <- function(sim) {
  fvtm0 <- mod$fvtm0 ## current-conditions VTM = the saved year-0 state (see InitMulti)
  fvtm <- mod$vtm
  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)

  funList <- default_landscape_metrics() ## TODO: pass this further up via parameter funList_lm

  oldPlan <- .planWithWorkers(pemisc::optimalClusterNum(5000, length(fvtm)))
  on.exit(future::plan(oldPlan), add = TRUE)

  vtmByRep <- .filesByRep(fvtm)

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
      rptPoly <- .cropToStudyArea(rptPoly, studyArea) ## geometry, not bbox

      rptPolyCol <- "Name" ## label column set by LandWebUtils::buildReportingPolygons()
      refCode <- LandWebUtils::refCodeFor("lm", p) ## key output on the layer name (cf. bc event)
      refCodeCC <- paste0(refCode, "_CC")
      ## drop features with no grouping label: an NA polyName makes patch/landscape stats
      ## select an empty subpoly (`summaryPolys[[col]] == NA`) -> crop() NULL -> values(NULL).
      rptPoly <- rptPoly[!is.na(rptPoly[[rptPolyCol]]), ]
      if (nrow(rptPoly) == 0) {
        return(invisible(NULL)) ## no named features in this layer within the study area
      }

      ## raw per-replicate landscape metrics, Cached on the map file(s) it reads.
      lmRaw <- function(vtm) {
        Cache(
          nrv_metrics_landscape,
          summaryPolys = rptPoly,
          polyCol = rptPolyCol,
          vtm = vtm,
          funList = funList,
          .cacheExtra = file.info(vtm)[, c("size", "mtime")]
        )
      }

      ## current conditions: a single snapshot, summarised as one replicate.
      mod[[refCodeCC]] <- suppressWarnings(
        .buildRepDataset(
          .nrvAggRoot(sim, refCodeCC),
          repIDs = "CC",
          compute_fn = function(repID) lmRaw(fvtm0)
        )
      )

      ## simulation: one parquet partition per replicate, then reduce across reps.
      mod[[refCode]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCode),
        repIDs = names(vtmByRep),
        compute_fn = function(repID) lmRaw(vtmByRep[[repID]])
      )

      .writeNrvSummaryCSVs(sim, mod[[refCode]], refCode, p)
      .writeNrvSummaryCSVs(sim, mod[[refCodeCC]], refCodeCC, p)

      return(invisible(NULL))
    },
    studyArea = studyAreaReporting,
    reportingPolygons = sim$reportingPolygons
  )

  return(invisible(sim))
}

patchMetrics <- function(sim) {
  fflm <- mod$flm
  ## current-conditions reference = the sim's saved year-0 state (see InitMulti):
  ## read directly, no regeneration from speciesLayers / no "CC SAM" input needed.
  fsam0 <- mod$fsam0
  fsam <- mod$sam
  fvtm0 <- mod$fvtm0
  fvtm <- mod$vtm

  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)
  funList <- default_patch_metrics() ## TODO: pass this further up via parameter funList_pm

  oldPlan <- .planWithWorkers(pemisc::optimalClusterNum(5000, length(fvtm)))
  on.exit(future::plan(oldPlan), add = TRUE)

  ## one parquet partition per replicate (the vtm/sam file vectors align by index).
  vtmByRep <- .filesByRep(fvtm)
  samByRep <- .filesByRep(fsam)

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
      rptPoly <- .cropToStudyArea(rptPoly, studyArea) ## geometry, not bbox
      rptPolyCol <- "Name" ## label column set by LandWebUtils::buildReportingPolygons()
      refCode <- LandWebUtils::refCodeFor("pm", p) ## key output on the layer name (cf. bc event)
      refCodeCC <- paste0(refCode, "_CC")
      ## drop features with no grouping label: an NA polyName makes patch/landscape stats
      ## select an empty subpoly (`summaryPolys[[col]] == NA`) -> crop() NULL -> values(NULL).
      rptPoly <- rptPoly[!is.na(rptPoly[[rptPolyCol]]), ]
      if (nrow(rptPoly) == 0) {
        return(invisible(NULL)) ## no named features in this layer within the study area
      }

      ## raw per-replicate patch metrics, Cached on the map files they read.
      pmRaw <- function(vtm, sam) {
        Cache(
          calculatePatchMetrics,
          sam = sam,
          vtm = vtm,
          flm = fflm,
          summaryPolys = rptPoly,
          polyCol = rptPolyCol,
          funList = funList,
          .cacheExtra = file.info(c(vtm, sam))[, c("size", "mtime")]
        )
      }

      ## current conditions
      mod[[refCodeCC]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCodeCC),
        repIDs = "CC",
        compute_fn = function(repID) pmRaw(fvtm0, fsam0)
      )

      ## simulation results
      mod[[refCode]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCode),
        repIDs = names(vtmByRep),
        compute_fn = function(repID) pmRaw(vtmByRep[[repID]], samByRep[[repID]])
      )

      ## relabel integer vegType class codes -> species names in the envelope (class-level lsm_c_*
      ## metrics report raw codes), so CSVs + plots show species. Applied here too (not only at the
      ## nrvtools source) so a reused/older parquet with integer-coded classes is fixed without
      ## re-aggregating; idempotent once the parquet already stores labels.
      vtmRAT <- terra::rast(fvtm0)
      mod[[refCode]] <- nrvtools::label_vegtype_classes(mod[[refCode]], vtmRAT)
      mod[[refCodeCC]] <- nrvtools::label_vegtype_classes(mod[[refCodeCC]], vtmRAT)

      .writeNrvSummaryCSVs(sim, mod[[refCode]], refCode, p)
      .writeNrvSummaryCSVs(sim, mod[[refCodeCC]], refCodeCC, p)

      return(invisible(NULL))
    },
    studyArea = studyAreaReporting,
    reportingPolygons = sim$reportingPolygons
  )

  return(invisible(sim))
}

## LandWeb summaries (ported v2 LandWeb_summary): leading-veg-by-age-class + large-patch counts.
## Age basis = time-since-fire (mod$tsf, from burnSummaries), matching v2. No flammable masking.
## The NRV distribution pools across replicates AND summary years, so summarize with `time` excluded
## from the id columns (idCols below); the plots (plotFun) are distributions, not time envelopes.
landWebMetrics <- function(sim) {
  ftsf0 <- mod$ftsf0
  ftsf <- mod$tsf
  fvtm0 <- mod$fvtm0
  fvtm <- mod$vtm

  studyAreaReporting <- sf::st_as_sf(sim$studyAreaReporting)
  funList <- default_landweb_metrics() ## TODO: pass this further up via parameter funList_lw
  idCols <- c("poly", "level", "class", "metric", "metric.1") ## pool across rep x NRV year (no time)

  oldPlan <- .planWithWorkers(pemisc::optimalClusterNum(5000, length(fvtm)))
  on.exit(future::plan(oldPlan), add = TRUE)

  ## pooled over summary years, so these are NRV distributions: only the NRV years
  nrvPeriod <- .nrvPeriod(sim)
  vtmByRep <- .filesByRep(.filesInPeriod(fvtm, nrvPeriod))
  tsfByRep <- .filesByRep(.filesInPeriod(ftsf, nrvPeriod))

  lapply(
    mod$rptPolyNames,
    function(p, reportingPolygons, studyArea) {
      message(crayon::magenta("Calculating LandWeb summaries for", p, "..."))

      rptPoly <- reportingPolygons[[p]]

      if (is(rptPoly, "Spatial")) {
        rptPoly <- sf::st_as_sf(rptPoly)
      } else if (
        is(rptPoly, "sf") && sf::st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON"
      ) {
        rptPoly <- sf::st_collection_extract(rptPoly, "POLYGON")
      }
      rptPoly <- .cropToStudyArea(rptPoly, studyArea) ## geometry, not bbox
      rptPolyCol <- "Name" ## label column set by LandWebUtils::buildReportingPolygons()
      refCode <- LandWebUtils::refCodeFor("lw", p) ## key output on the layer name (cf. bc event)
      refCodeCC <- paste0(refCode, "_CC")
      rptPoly <- rptPoly[!is.na(rptPoly[[rptPolyCol]]), ]
      if (nrow(rptPoly) == 0) {
        return(invisible(NULL)) ## no named features in this layer within the study area
      }

      ## raw per-replicate LandWeb summaries, Cached on the map files they read.
      lwRaw <- function(vtm, tsf) {
        Cache(
          calculateLandWebMetrics,
          summaryPolys = rptPoly,
          polyCol = rptPolyCol,
          vtm = vtm,
          age = tsf,
          funList = funList,
          ageClassCutOffs = P(sim)$ageClassCutOffs,
          ageClasses = P(sim)$ageClasses,
          directions = P(sim)$patchDirections, ## 4 = rook (v2), 8 = queen; -> largePatchCounts()
          .cacheExtra = file.info(c(vtm, tsf))[, c("size", "mtime")]
        )
      }

      ## current conditions: a single (year-0) snapshot, treated as one replicate.
      mod[[refCodeCC]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCodeCC),
        repIDs = "CC",
        compute_fn = function(repID) lwRaw(fvtm0, ftsf0),
        id_cols = idCols
      )

      ## simulation results: one parquet partition per replicate (vtm/tsf vectors align by index).
      mod[[refCode]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCode),
        repIDs = names(vtmByRep),
        compute_fn = function(repID) lwRaw(vtmByRep[[repID]], tsfByRep[[repID]]),
        id_cols = idCols
      )

      .writeNrvSummaryCSVs(sim, mod[[refCode]], refCode, p)
      .writeNrvSummaryCSVs(sim, mod[[refCodeCC]], refCodeCC, p)

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
  NDTBEC <- .cropToStudyArea(
    sim$reportingPolygons[["ecoregionLayer"]], studyAreaReporting  ## geometry, not bbox
  )
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

  ssmByRep <- .filesByRep(fssm)

  lapply(
    rptPolyNames,
    function(p, reportingPolygons, reportingPolygonCols, studyArea) {
      message(crayon::magenta("Calculating seral stage patch metrics for", p, "..."))

      rptPoly <- reportingPolygons[[p]]

      if (is(rptPoly, "sf") && sf::st_geometry_type(rptPoly, by_geometry = FALSE) != "POLYGON") {
        rptPoly <- sf::st_collection_extract(rptPoly, "POLYGON")
      }
      rptPoly <- .cropToStudyArea(rptPoly, studyArea) ## geometry, not bbox
      rptPolyCol <- reportingPolygonCols[[p]]
      refCode <- LandWebUtils::refCodeFor("sspm", p)
      refCodeCC <- paste0(refCode, "_CC")

      ## raw per-replicate seral patch metrics, Cached on the seral maps read.
      bcRaw <- function(ssm) {
        Cache(
          calculatePatchMetricsSeral,
          ssm = ssm,
          flm = fflm,
          summaryPolys = rptPoly,
          polyCol = rptPolyCol,
          funList = funList[[1]], ## TODO: temporarily, only patchAreasSeral
          .cacheExtra = file.info(ssm)[, c("size", "mtime")]
        )
      }

      ## current conditions
      mod[[refCodeCC]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCodeCC),
        repIDs = "CC",
        compute_fn = function(repID) bcRaw(fssm0)
      )

      ## simulation results
      mod[[refCode]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCode),
        repIDs = names(ssmByRep),
        compute_fn = function(repID) bcRaw(ssmByRep[[repID]])
      )

      .writeNrvSummaryCSVs(sim, mod[[refCode]], refCode, p)
      .writeNrvSummaryCSVs(sim, mod[[refCodeCC]], refCodeCC, p)

      ## SeralTable: range (min/mean/max over time) of each seral class's share of area, for the
      ## NDTxBEC reporting polygons. area = sum(n_reps * mean) reproduces the former sum(N * mn)
      ## (total patch area pooled across replicates); the replicate pooling cancels in the
      ## class/total proportion. `metric == "area"` is the landscapemetrics name for patchAreasSeral.
      if (refCode == "sspm_NDTBEC") {
        seral_table <- mod[[refCode]] |>
          dplyr::filter(.data$metric == "area") |>
          dplyr::select("class", "poly", "time", "n_reps", "mean") |>
          na.omit() |>
          dplyr::mutate(
            class = factor(.data$class, levels = seral_stages()),
            poly = as.factor(.data$poly)
          ) |>
          dplyr::summarize(
            area = sum(.data$n_reps * .data$mean, na.rm = TRUE),
            .by = c("class", "poly", "time")
          ) |>
          dplyr::mutate(totalArea = sum(.data$area, na.rm = TRUE), .by = c("poly", "time")) |>
          dplyr::summarize(
            minPctArea = 100 * min(.data$area / .data$totalArea, na.rm = TRUE),
            meanPctArea = 100 * mean(.data$area / .data$totalArea, na.rm = TRUE),
            maxPctArea = 100 * max(.data$area / .data$totalArea, na.rm = TRUE),
            .by = c("class", "poly")
          )

        write.csv(seral_table, file.path(outputPath(sim), "SeralTable.csv"), row.names = FALSE)
      }

      return(invisible(NULL))
    },
    studyArea = studyAreaReporting,
    reportingPolygons = rptPolygons,
    reportingPolygonCols = rptPolyCols
  )

  return(invisible(sim))
}

### stand-age time-series animation (ports the v2 LandWeb_summary `animation` event)
## Encoded with gifski (pure-Rust; no ImageMagick), so it avoids the ImageMagick
## cache-exhaustion that broke the v2 `animation::saveGIF` path -- see LandWeb#153.
## No system (policy.xml) configuration is required.
makeAnimation <- function(sim) {
  ## animate replicate 1's saved stand-age time series (the deterministic first rep,
  ## matching the CC snapshot); frames were masked to studyAreaReporting when saved.
  samFiles <- grep("rep01", mod$samTimeSeries, value = TRUE)
  if (length(samFiles) == 0L) {
    warning("NRV_summary animation: no rep01 standAgeMap time-series files found; skipping.")
    return(invisible(sim))
  }
  yrs <- as.integer(gsub(".*year0*([0-9]+)\\.tif$", "\\1", samFiles))
  ord <- order(yrs)
  samFiles <- samFiles[ord]
  yrs <- yrs[ord]

  ## age-class reclassification + colours (RdYlGn young -> old, matching v2's brewer.pal).
  ## `ageClassCutOffs` are the LOWER bound of each class (length == n); the final class
  ## runs to +Inf so old stands are never dropped.
  cutoffs <- P(sim)$ageClassCutOffs
  n <- length(cutoffs)
  ageClasses <- P(sim)$ageClasses[seq_len(n)]
  rcl <- cbind(cutoffs, c(cutoffs[-1], Inf), seq_len(n))
  pal <- grDevices::colorRampPalette(
    RColorBrewer::brewer.pal(min(9L, max(3L, n)), "RdYlGn")
  )(n)
  names(pal) <- ageClasses

  ageClassFrame <- function(f) {
    r <- terra::classify(terra::rast(f), rcl, right = FALSE, include.lowest = TRUE)
    levels(r) <- data.frame(id = seq_len(n), ageClass = ageClasses)
    r
  }

  gifFile <- file.path(figurePath(sim), "standAge_animation.gif")
  gifski::save_gif(
    expr = {
      for (i in seq_along(samFiles)) {
        gg <- ggplot2::ggplot() +
          tidyterra::geom_spatraster(data = ageClassFrame(samFiles[i])) +
          ggplot2::scale_fill_manual(
            values = pal, na.value = "transparent", drop = FALSE, name = "age class"
          ) +
          ggplot2::labs(
            title = paste0(P(sim)$.studyAreaName, " — stand age"),
            subtitle = paste("year", yrs[i])
          ) +
          ggplot2::coord_sf(expand = FALSE) +
          ggplot2::theme_minimal()
        print(gg)
      }
    },
    gif_file = gifFile,
    width = 1200,
    height = 1200,
    delay = 1,
    progress = FALSE
  )

  message("NRV_summary: wrote stand-age animation (", length(samFiles), " frames) to ", gifFile)
  return(invisible(sim))
}

## LandWeb-summary figure TASKS for one reporting layer: the v2-form leading boxplots
## (figures/boxplots/<layer>/<subregion> <species>.png) and large-patch histograms
## (figures/histograms/<layer>/<size>/<subregion> <species>.png -- one file per species, four
## age-class panels), read from the raw per-replicate parquet with the current-condition overlay.
## Returns a list of self-contained render tasks (see .renderTasks()) rather than rendering inline,
## so plotFun can render them in parallel. The output dirs are created here (main worker).
.saveLandWebFigTasks <- function(sim, p) {
  refCode <- LandWebUtils::refCodeFor("lw", p)
  raw <- open_nrv_dataset(.nrvAggRoot(sim, refCode))
  if (is.null(raw)) {
    return(list())
  }
  raw <- as.data.frame(dplyr::collect(raw))
  if (!nrow(raw)) {
    return(list())
  }
  cc <- open_nrv_dataset(.nrvAggRoot(sim, paste0(refCode, "_CC")))
  cc <- if (!is.null(cc)) as.data.frame(dplyr::collect(cc)) else NULL

  ageClasses <- P(sim)$ageClasses
  saName <- P(sim)$.studyAreaName
  if (is.null(saName) || is.na(saName)) saName <- ""
  saPrefix <- if (nzchar(saName)) paste0(saName, " — ") else ""
  safe <- function(s) gsub("[/\\]", "-", s) ## filename-safe subregion / species
  ccFor <- function(poly, sp, met) {
    if (is.null(cc)) {
      NULL
    } else {
      cc[cc$poly == poly & cc$metric.1 == sp & cc$metric == met, , drop = FALSE]
    }
  }
  tasks <- list()

  ## Leading boxplots: one file per (subregion x species), with the forested-area caption
  lead <- raw[raw$metric == "leadingProp", , drop = FALSE]
  if (nrow(lead)) {
    dBox <- .ppFigDir(sim, "boxplots", p)
    ## forested area (ha) per subregion x leading species from the CC (year-0) VTM, for the boxplot
    ## captions (v2 / NW_AB form); computed once per layer. NA lookups -> no caption.
    areas <- tryCatch(
      nrvtools::subregion_forested_area(terra::rast(mod$fvtm0), sim$reportingPolygons[[p]], "Name"),
      error = function(e) {
        message("NRV_summary: forested-area calc failed for '", p, "': ", conditionMessage(e))
        NULL
      }
    )
    ## match the reporting-polygon Name to the parquet `poly` robustly: the source Names may carry a
    ## trailing abbreviation period ("Ltd.") that a (reused/older) parquet stored without, so compare
    ## on a trimmed, trailing-period-stripped key.
    normPoly <- function(x) trimws(sub("\\.\\s*$", "", as.character(x)))
    areaKey <- if (!is.null(areas)) normPoly(areas$poly) else character(0)
    areaHa <- function(poly, sp) {
      if (is.null(areas)) {
        return(NA_real_)
      }
      a <- areas$area_ha[areaKey == normPoly(poly) & areas$vegCover == sp]
      if (length(a)) a[[1L]] else NA_real_
    }
    for (poly in unique(lead$poly)) {
      for (sp in unique(lead$metric.1)) {
        d <- lead[lead$poly == poly & lead$metric.1 == sp, , drop = FALSE]
        if (!nrow(d) || all(d$value == 0, na.rm = TRUE)) next ## skip empty subregions / absent species
        a <- areaHa(poly, sp)
        cap <- if (!is.na(a)) {
          paste0("Total ", sp, "-leading area in ", poly, ": ", format(round(a), big.mark = ","), " ha")
        } else {
          NULL
        }
        tasks[[length(tasks) + 1L]] <- list(
          plotter = "leading", df = d, cc = ccFor(poly, sp, "leadingProp"),
          ageClasses = ageClasses, title = paste0(saPrefix, poly, " ", sp), caption = cap,
          file = file.path(dBox, paste0(safe(poly), " ", safe(sp), ".png")),
          width = 8, height = 6
        )
      }
    }
  }

  ## Large-patch histograms: one file per (size x subregion x species), four age-class panels
  for (met in grep("^Npatch_ge", unique(raw$metric), value = TRUE)) {
    sz <- sub("^Npatch_ge(\\d+)ha$", "\\1", met)
    dSz <- .ppFigDir(sim, "histograms", p, sz)
    lp <- raw[raw$metric == met, , drop = FALSE]
    for (poly in unique(lp$poly)) {
      for (sp in unique(lp$metric.1)) {
        d <- lp[lp$poly == poly & lp$metric.1 == sp, , drop = FALSE]
        if (!nrow(d)) next
        tasks[[length(tasks) + 1L]] <- list(
          plotter = "histogram", df = d, cc = ccFor(poly, sp, met),
          ageClasses = ageClasses,
          xlab = paste("Number of patches greater than", sz, "ha"),
          title = paste0(saPrefix, poly, " ", sp, " (>=", sz, " ha)"),
          file = file.path(dSz, paste0(safe(poly), " ", safe(sp), ".png")),
          width = 9, height = 7
        )
      }
    }
  }
  tasks
}

## Number of local worker processes for parallel plot rendering: RAM-aware (optimalClusterNum) but
## hard-capped by the `plotWorkers` parameter, so a shared node is not swamped. 1 -> render inline.
.plotWorkers <- function(sim, nTasks) {
  cap <- P(sim)$plotWorkers
  if (is.null(cap) || is.na(cap)) cap <- 1L
  cap <- max(1L, as.integer(cap))
  if (cap <= 1L || nTasks <= 1L) {
    return(1L)
  }
  n <- tryCatch(pemisc::optimalClusterNum(1500, min(cap, nTasks)), error = function(e) 1L)
  max(1L, min(as.integer(n), cap, nTasks))
}

## Render a list of self-contained plot tasks to PNGs, in parallel across .plotWorkers() local
## `future` multisession processes (each task = one ggsave to its own file, so trivially parallel).
## Tasks carry only plain data (data.frame + strings + path) -- no sim / SpatRaster -- so they
## serialize cleanly to workers. multisession (not fork) is used because the crew worker running
## this target is a mirai daemon. data.table threads are pinned to 1 per worker to avoid
## oversubscription. Returns the written file paths.
.renderTasks <- function(sim, tasks) {
  tasks <- Filter(function(tk) !is.null(tk) && !is.null(tk[["file"]]), tasks)
  if (!length(tasks)) {
    return(character(0))
  }

  render_one <- function(task) {
    data.table::setDTthreads(1L)
    gg <- switch(
      task[["plotter"]],
      envelope = .addCurrentCondition(
        .addNrvShading(
          nrvtools::plot_nrv_envelope(
            task[["df"]], type = task[["type"]], facet = task[["facet"]],
            ylab = task[["ylab"]], title = task[["title"]], page = task[["page"]]
          ),
          task[["nrvPeriod"]]
        ),
        task[["cc"]], task[["facet"]]
      ),
      leading = nrvtools::plot_leading_boxplot(
        task[["df"]], cc = task[["cc"]], ageClasses = task[["ageClasses"]],
        title = task[["title"]], caption = task[["caption"]]
      ),
      histogram = nrvtools::plot_largepatch_histogram(
        task[["df"]], cc = task[["cc"]], ageClasses = task[["ageClasses"]],
        xlab = task[["xlab"]], title = task[["title"]]
      ),
      NULL
    )
    if (is.null(gg)) {
      return(NA_character_)
    }
    ggplot2::ggsave(task[["file"]], gg, width = task[["width"]], height = task[["height"]])
    task[["file"]]
  }
  ## Detach render_one from this frame: a closure carries its enclosing environment, so left as-is
  ## `future` would serialize the entire (multi-hundred-MB) `tasks` list *with the function* to every
  ## worker. The body only calls namespaced / base functions, so a fresh env under globalenv()
  ## resolves everything; each task's data is shipped on its own as the mapped argument. (globalenv,
  ## not baseenv -- the latter trips future's "cycles in parent chains" during serialization.)
  environment(render_one) <- new.env(parent = globalenv())
  ## the one module helper render_one uses, detached the same way
  addCC <- .addCurrentCondition
  environment(addCC) <- list2env(list(.ccColour = .ccColour), parent = globalenv())
  assign(".addCurrentCondition", addCC, envir = environment(render_one))

  nWorkers <- .plotWorkers(sim, length(tasks))
  message("NRV_summary: rendering ", length(tasks), " figure(s) across ", nWorkers, " worker(s)")
  files <- if (nWorkers <= 1L) {
    lapply(tasks, render_one)
  } else {
    ## per-worker task chunks can be sizeable (raw per-rep data); the nodes have >500 GB, so lift the
    ## default 500 MiB transfer guard. future.globals = FALSE: render_one is self-contained.
    oldOpt <- options(future.globals.maxSize = 4 * 1024^3)
    on.exit(options(oldOpt), add = TRUE)
    oldPlan <- future::plan(future::multisession, workers = nWorkers)
    on.exit(future::plan(oldPlan), add = TRUE)
    future.apply::future_lapply(
      tasks, render_one,
      future.globals = FALSE,
      future.packages = c("nrvtools", "ggplot2", "data.table"),
      future.seed = TRUE
    )
  }
  files <- unlist(files, use.names = FALSE)
  files[!is.na(files) & nzchar(files)]
}

### plotting
plotFun <- function(sim) {
  ## Build a flat list of self-contained render tasks across all enabled kinds, then render them in
  ## parallel via .renderTasks(). Envelope figures (lm/pm/sspm) -> figures/<kind>/<layer>/...; the
  ## LandWeb summaries (lw) are per-species boxplots / histograms -> figures/{boxplots,histograms}/...
  saName <- P(sim)$.studyAreaName
  if (is.null(saName) || is.na(saName)) saName <- ""
  saPrefix <- if (nzchar(saName)) paste0(saName, " — ") else ""
  safe <- function(s) gsub("[/\\]", "-", s) ## filename-safe metric / subregion

  ## build envelope render tasks for one kind x layer (see .renderTasks()).
  envTasks <- function(kind, p, ylab, perSubregion = FALSE) {
    env <- mod[[LandWebUtils::refCodeFor(kind, p)]]
    if (is.null(env) || !nrow(env)) {
      return(list())
    }
    d <- .ppFigDir(sim, kind, p) ## create the output dir on the main worker
    ccAll <- mod[[paste0(LandWebUtils::refCodeFor(kind, p), "_CC")]] ## the current-condition snapshot
    tasks <- list()
    nrvPeriod <- .nrvPeriod(sim)

    if (perSubregion) {
      ## One plot per (metric x reporting sub-polygon); the sub-polygon name (e.g. the individual
      ## FMA) is in the filename AND the title. Class-resolved metrics (pm) facet by species so each
      ## sub-polygon is its own figure rather than many crammed/paginated together; landscape metrics
      ## (lm) have no class, so each is a single-panel envelope for that sub-polygon. Title carries
      ## the sub-polygon + metric name (the study area is in the output path, not repeated here).
      for (met in unique(env$metric)) {
        em <- env[env$metric == met, , drop = FALSE]
        for (poly in unique(em$poly)) {
          sub <- em[em$poly == poly, , drop = FALSE]
          if (!nrow(sub)) next
          ttl <- paste0(poly, " — ", .metricLabel(met))
          cc <- if (!is.null(ccAll)) ccAll[ccAll$poly == poly & ccAll$metric == met, , drop = FALSE]
          for (type in c("ribbon", "boxplot")) {
            tasks[[length(tasks) + 1L]] <- list(
              plotter = "envelope", df = sub, type = type, cc = cc, nrvPeriod = nrvPeriod,
              facet = c("class", "metric.1"), ylab = ylab, title = ttl, page = NULL,
              file = file.path(d, paste0(safe(poly), " ", safe(met), "_", type, ".png")),
              width = 16, height = 10
            )
          }
        }
      }
      return(tasks)
    }

    ## One figure-set per metric: facet the subregion panels and paginate them across pages, so a
    ## large panel set becomes several PNGs (<metric>_<type>_p<pg>.png). Used for the compare-
    ## subregions layout (sspm). Page count is resolved once here (main worker); one task per page.
    for (met in unique(env$metric)) {
      sub <- env[env$metric == met, , drop = FALSE]
      if (!nrow(sub)) next
      ttl <- paste0(saPrefix, .metricLabel(met))
      for (type in c("ribbon", "boxplot")) {
        gg1 <- plot_nrv_envelope(
          sub, type = type, facet = c("poly", "class", "metric.1"),
          ylab = ylab, title = ttl, page = 1
        )
        if (is.null(gg1)) next
        nPages <- tryCatch(ggforce::n_pages(gg1), error = function(e) 1L)
        if (is.null(nPages) || is.na(nPages)) nPages <- 1L
        for (pg in seq_len(nPages)) {
          tasks[[length(tasks) + 1L]] <- list(
            plotter = "envelope", df = sub, type = type, nrvPeriod = nrvPeriod,
            facet = c("poly", "class", "metric.1"), ylab = ylab, title = ttl, page = pg,
            file = file.path(d, paste0(safe(met), "_", type, "_p", pg, ".png")),
            width = 16, height = 10
          )
        }
      }
    }
    tasks
  }

  events <- tolower(P(sim)$postprocessEvents)
  tasks <- list()

  if ("lm" %in% events) {
    for (p in mod$rptPolyNames) {
      tasks <- c(tasks, envTasks("lm", p, ylab = "landscape metric value", perSubregion = TRUE))

      env <- mod[[LandWebUtils::refCodeFor("lm", p)]]
      cc <- mod[[paste0(LandWebUtils::refCodeFor("lm", p), "_CC")]]
      if (!is.null(env) && nrow(env) && !is.null(cc) && nrow(cc)) {
        Plots(
          data = list(env = env, cc = cc, period = .nrvPeriod(sim)), fn = .currentConditionOverview,
          filename = "current_condition_overview", path = .ppFigDir(sim, "lm", p),
          types = P(sim)$.plots, ggsaveArgs = list(width = 10, height = 8, units = "in")
        )
      }
    }
  }
  if ("pm" %in% events) {
    for (p in mod$rptPolyNames) {
      tasks <- c(tasks, envTasks("pm", p, ylab = "patch metric value", perSubregion = TRUE))
    }
  }
  if ("lw" %in% events) {
    for (p in mod$rptPolyNames) {
      tasks <- c(tasks, .saveLandWebFigTasks(sim, p))
    }
  }
  if ("bc" %in% events) {
    for (p in mod$rptPolyNames) {
      tasks <- c(tasks, envTasks("sspm", p, ylab = "seral patch area (ha)"))
    }
  }

  pngs <- .renderTasks(sim, tasks)
  if (length(pngs)) {
    sim <- registerOutputs(pngs, sim)
  }
  return(invisible(sim))
}

## ---- metric names on the figures ----
## Full names of the metric codes (landscapemetrics' codes and the module's own), for figure titles, facets
## and axes only; CSVs and file names keep the codes. landscapemetrics::lsm_abbreviations_names is not used:
## its names do not tell _mn, _sd and _cv apart ("patch area" for all three).
.metricNames <- c(
  ai = "Aggregation index", area = "Patch area", area_cv = "Patch area CV", area_mn = "Mean patch area",
  area_sd = "Patch area SD", ca = "Class area", cohesion = "Patch cohesion index",
  condent = "Conditional entropy", core_cv = "Core area CV", core_mn = "Mean core area",
  core_sd = "Core area SD", ed = "Edge density", enn = "Euclidean nearest-neighbour distance",
  enn_cv = "Nearest-neighbour distance CV", enn_mn = "Mean nearest-neighbour distance",
  enn_sd = "Nearest-neighbour distance SD", iji = "Interspersion-juxtaposition index",
  sam_mdn = "Median stand age" ## patchAges(): the median stand age of each patch
)

## the full name of each metric code; a code without a name is returned as it is
.metricLabel <- function(metric) {
  metric <- as.character(metric)
  label <- unname(.metricNames[metric])
  ifelse(is.na(label), metric, label)
}

## ---- current condition on the figures ---------------------------------------------------------
## the legend label and colour of the current condition, on every figure that shows it
.ccColour <- c("current condition" = "firebrick")

## Add the current-condition value to an envelope figure from `plot_nrv_envelope()` as a dashed red
## horizontal line labelled "current condition", in the panel it belongs to. `cc` has the facet
## columns of `facet` and `mean` (the current-condition value, a single snapshot). The panel a row
## belongs to is read from the plot's own `.panel` column, so the labels cannot drift from nrvtools'.
.addCurrentCondition <- function(gg, cc, facet) {
  if (is.null(cc) || !nrow(cc)) {
    return(gg)
  }
  d <- gg$data
  facet <- facet[facet %in% names(d) & facet %in% names(cc)]
  facet <- facet[vapply(facet, function(f) length(unique(d[[f]])) > 1L, logical(1L))]
  line <- if (length(facet)) {
    merge(unique(d[c(".panel", facet)]), cc[c(facet, "mean")], by = facet)
  } else {
    data.frame(.panel = unique(d$.panel), mean = cc$mean[1L])
  }
  line$line <- names(.ccColour)
  gg +
    ggplot2::geom_hline(data = line, ggplot2::aes(yintercept = mean, colour = line),
                        linetype = "dashed", linewidth = 0.7, inherit.aes = FALSE) +
    ggplot2::scale_colour_manual(values = .ccColour, name = NULL) +
    ggplot2::theme(legend.position = "bottom")
}

## The NRV years: the last `nrvWindow` of the summary period (a subset of it by construction)
.nrvPeriod <- function(sim) .lastFraction(P(sim)$summaryPeriod, P(sim)$nrvWindow)

## The last `fraction` of `period` (the summary period), as c(from, to)
.lastFraction <- function(period, fraction) {
  sp <- range(period)
  c(sp[2L] - fraction * diff(sp), sp[2L])
}

## Shade the NRV years `period` on an envelope figure from `plot_nrv_envelope()`, behind the data. The
## boxplot figure has a discrete time axis (one box per time), the ribbon figure a continuous one.
.addNrvShading <- function(gg, period) {
  if (is.null(gg) || !"time" %in% names(gg$data)) {
    return(gg)
  }
  times <- sort(unique(gg$data$time))
  inNrv <- times >= min(period) & times <= max(period)
  if (!any(inNrv)) {
    return(gg)
  }
  box <- any(vapply(gg$layers, function(l) inherits(l$geom, "GeomBoxplot"), logical(1L)))
  x <- if (box) range(which(inNrv)) + c(-0.5, 0.5) else range(times[inNrv])
  gg$layers <- c(
    ggplot2::annotate("rect", xmin = x[1L], xmax = x[2L], ymin = -Inf, ymax = Inf,
                      alpha = 0.15, fill = "orange"),
    gg$layers
  )
  gg + ggplot2::labs(caption = "shaded: NRV years")
}

## The NRV range of each poly x metric: smallest min, largest max and mean of the mean, over the
## times of `period` (the NRV years). `env` has poly, metric, time, mean, min and max.
.nrvRange <- function(env, period) {
  env <- env[env$time >= min(period) & env$time <= max(period), , drop = FALSE]
  byMetric <- split(env, paste(env$poly, env$metric, sep = "\r"))
  do.call(rbind, lapply(byMetric, function(e) {
    data.frame(poly = e$poly[1L], metric = e$metric[1L], lo = min(e$min), hi = max(e$max), mid = mean(e$mean))
  }))
}

## Where the current condition falls within the NRV, one facet per metric on its real scale.
## `data` = list(env =, cc =, period =): the envelope over the summary times (min, max, mean per time), the
## current-condition snapshot (mean) and the NRV years. The grey bar is the NRV range (smallest min to
## largest max over the NRV years), the black tick the NRV mean, the red dot the current condition.
## A dot beyond the bar is outside the NRV.
.currentConditionOverview <- function(data) {
  nrv <- .nrvRange(data$env, data$period)
  nrv <- merge(nrv, stats::setNames(data$cc[c("poly", "metric", "mean")], c("poly", "metric", "current")),
               by = c("poly", "metric"))
  nrv$panel <- paste0(if (length(unique(nrv$poly)) > 1L) paste0(nrv$poly, ": ") else "", .metricLabel(nrv$metric))
  ggplot2::ggplot(nrv) +
    ggplot2::geom_segment(ggplot2::aes(x = lo, xend = hi, y = 0, yend = 0), colour = "grey75", linewidth = 4) +
    ggplot2::geom_point(ggplot2::aes(x = mid, y = 0, shape = "NRV mean"), size = 3) +
    ggplot2::geom_point(ggplot2::aes(x = current, y = 0, colour = names(.ccColour)), size = 3) +
    ggplot2::scale_colour_manual(values = .ccColour, name = NULL) +
    ggplot2::scale_shape_manual(values = c("NRV mean" = 124), name = NULL) +
    ggplot2::facet_wrap(~panel, scales = "free_x") +
    ggplot2::labs(x = "metric value (grey bar: NRV range over the NRV years)", y = NULL,
                  title = "Current condition relative to the NRV") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom", axis.text.y = ggplot2::element_blank(),
                   axis.ticks.y = ggplot2::element_blank(), panel.grid.major.y = ggplot2::element_blank(),
                   panel.grid.minor.y = ggplot2::element_blank())
}

## ---- is the run long enough? Directional change over the last part of the summary period -----------
## The summaries describe a landscape that is meant to be in equilibrium. A metric still trending at
## the end of the run means the envelope mixes the transient with the equilibrium, and the run needs
## to be longer. Each series (a landscape metric, a patch metric by class, the area burned per block)
## is tested over the last `stabilityWindow` of `summaryPeriod`, on the values of all reps pooled.
## Test: Mann-Kendall (Kendall's tau of value against time) for the p-value and the Theil-Sen slope
## (median of the pairwise slopes) for the size of the trend. Both use ranks and medians, so one odd
## rep or a skewed metric does not decide the verdict, as it can with an OLS slope; and pooling the reps
## keeps the spread among reps in the test, so a noisy series needs a larger trend to be significant.
## A series is "still changing" when the trend is significant AND the fitted change over the window is
## more than `minChange` of the series' range (largest minus smallest value over all reps in the
## window, not the approach to it); a significant but tiny trend is not worth a longer run. Fewer than 3
## distinct times in the window cannot be tested ("insufficient"). The window is not the NRV: the NRV is
## all of `summaryPeriod`.

## one series: Mann-Kendall p-value and Theil-Sen slope of `value` against `time`
.senKendall <- function(time, value) {
  if (length(unique(value)) < 2L) {
    return(c(slope = 0, p = 1)) ## constant: no trend
  }
  pairs <- utils::combn(length(time), 2L)
  dt <- time[pairs[2L, ]] - time[pairs[1L, ]]
  dv <- value[pairs[2L, ]] - value[pairs[1L, ]]
  p <- suppressWarnings(stats::cor.test(time, value, method = "kendall", exact = FALSE)$p.value)
  c(slope = stats::median(dv[dt != 0] / dt[dt != 0]), p = p)
}

## `series`: one row per rep x time x series, with the `keys` columns identifying the series, plus
## `rep`, `time` and `value`. `window` = c(from, to) in simulation time. Returns one row per series:
## the keys, nTimes (distinct times in the window), slope (per time unit), p, changePctRange (the fitted
## change over the window as % of the window's range), flag ("still changing", "stable" or "insufficient").
.trendStability <- function(series, keys, window, alpha = 0.05, minChange = 0.10) {
  id <- do.call(paste, c(lapply(series[keys], as.character), sep = "\r"))
  rows <- lapply(split(seq_len(nrow(series)), factor(id, levels = unique(id))), function(i) {
    s <- series[i, , drop = FALSE]
    s <- s[is.finite(s$value), , drop = FALSE]
    w <- s[s$time >= window[1L] & s$time <= window[2L], , drop = FALSE]
    out <- cbind(series[i[1L], keys, drop = FALSE], nTimes = length(unique(w$time)), slope = NA_real_,
                 p = NA_real_, changePctRange = NA_real_, flag = "insufficient")
    if (out$nTimes >= 3L) {
      tr <- .senKendall(w$time, w$value)
      windowRange <- diff(range(w$value)) ## the window's values, not the transient before it
      out$slope <- tr[["slope"]]
      out$p <- tr[["p"]]
      out$changePctRange <- if (windowRange > 0) 100 * out$slope * diff(range(w$time)) / windowRange else 0
      out$flag <- if (out$p < alpha && abs(out$changePctRange) > 100 * minChange) "still changing" else "stable"
    }
    out
  })
  res <- do.call(rbind, rows)
  rownames(res) <- NULL
  res
}

## Area burned (ha) per block of `blockYears` years per rep, from the fire-size table of
## burnSummaries (columns rep, year, areaBurnedHa). Blocks with no fire are 0, not missing: a
## missing block would hide exactly the trend a shrinking fire regime shows. `time` = block start.
.burnBlockSeries <- function(fireSizes, years, blockYears = 100L) {
  starts <- seq(years[1L], years[2L] - 1L, by = blockYears)
  reps <- sort(unique(fireSizes$rep))
  blocks <- expand.grid(rep = reps, time = starts)
  blocks$value <- mapply(function(r, t) {
    sum(fireSizes$areaBurnedHa[fireSizes$rep == r & fireSizes$year >= t & fireSizes$year < t + blockYears])
  }, blocks$rep, blocks$time)
  blocks
}

## One value per rep x time per series: patch-level rows (one per patch) are not a series, only the
## landscape and class levels are.
.seriesLevels <- function(raw) {
  raw[raw$level %in% c("landscape", "class"), , drop = FALSE]
}

## The series the stability check looks at: landscape and patch metrics per rep (from the _aggregates
## parquet), and the area burned per block when burnSummaries wrote it. Columns:
## kind, layer, poly, level, class, metric, rep, time, value.
.stabilitySeries <- function(sim) {
  events <- tolower(P(sim)$postprocessEvents)
  vtmRAT <- terra::rast(mod$fvtm0)
  one <- lapply(intersect(c("lm", "pm"), events), function(kind) {
    lapply(mod$rptPolyNames, function(p) {
      raw <- open_nrv_dataset(.nrvAggRoot(sim, LandWebUtils::refCodeFor(kind, p)))
      if (is.null(raw)) {
        return(NULL)
      }
      raw <- .seriesLevels(as.data.frame(dplyr::collect(raw)))
      if (kind == "pm") raw <- nrvtools::label_vegtype_classes(raw, vtmRAT)
      raw$class <- as.character(raw$class)
      data.frame(kind = kind, layer = p, raw[, c("poly", "level", "class", "metric", "rep", "time", "value")])
    })
  })
  fs <- file.path(outputPath(sim), "burnSummaries_fireSizes_allReps.csv")
  burn <- if (file.exists(fs)) {
    b <- .burnBlockSeries(data.table::fread(fs), P(sim)$simTimes, P(sim)$summaryInterval)
    data.frame(kind = "burn", layer = P(sim)$.studyAreaName, poly = P(sim)$.studyAreaName,
               level = "landscape", class = NA_character_, metric = "areaBurnedHa per block",
               rep = b$rep, time = b$time, value = b$value)
  }
  do.call(rbind, c(unlist(one, recursive = FALSE), list(burn)))
}

.stabilityKeys <- c("kind", "layer", "poly", "level", "class", "metric")

## the window the check looks at: the last `stabilityWindow` of the summary period
.stabilityWindow <- function(sim) .lastFraction(P(sim)$summaryPeriod, P(sim)$stabilityWindow)

## Panels of each series over time (reps as thin lines, mean in bold), the window shaded, and the
## verdict in each panel title; `page` of `nPages` panels sets.
.stabilityPanels <- function(data, window, page = 1L, ncol = 4L, nrow = 3L) {
  d <- data$series
  d$panel <- paste0(ifelse(is.na(d$class), "", paste0(d$class, " ")), .metricLabel(d$metric), "\n", d$layer, "/", d$poly, ": ",
                    data$flag[match(do.call(paste, d[.stabilityKeys]), data$id)])
  ggplot2::ggplot(d, ggplot2::aes(time, value)) +
    ggplot2::annotate("rect", xmin = window[1L], xmax = window[2L], ymin = -Inf, ymax = Inf,
                      alpha = 0.15, fill = "orange") +
    ggplot2::geom_line(ggplot2::aes(group = rep), colour = "grey60", linewidth = 0.3) +
    ggplot2::stat_summary(fun = mean, geom = "line", linewidth = 0.8) +
    ggforce::facet_wrap_paginate(~panel, ncol = ncol, nrow = nrow, page = page, scales = "free_y") +
    ggplot2::labs(x = "time", y = NULL, caption = "shaded: stability window; thin lines: reps; bold: mean") +
    ggplot2::theme_bw(base_size = 9)
}

## One summary of the verdicts: fitted change over the window as % of the window's range, one point per
## series, by metric, coloured by verdict, with the `minChange` thresholds.
.stabilitySummary <- function(res, minChange) {
  res$label <- paste(res$kind, .metricLabel(res$metric))
  ggplot2::ggplot(res, ggplot2::aes(changePctRange, label, colour = flag)) +
    ggplot2::geom_vline(xintercept = c(-1, 1) * 100 * minChange, linetype = "dashed") +
    ggplot2::geom_point(alpha = 0.7) +
    ggplot2::scale_colour_manual(values = c(stable = "steelblue", `still changing` = "firebrick",
                                            insufficient = "grey60"), drop = FALSE) +
    ggplot2::labs(x = "fitted change over the window (% of the window's range)", y = NULL, colour = NULL) +
    ggplot2::theme_bw(base_size = 9)
}

## "N of M metrics still changing; consider a longer run"
.stabilityVerdict <- function(res) {
  tested <- res$flag != "insufficient"
  n <- sum(res$flag == "still changing")
  paste0(n, " of ", sum(tested), " metrics still changing",
         if (n > 0L) "; consider a longer run" else "; the run is long enough",
         if (any(!tested)) paste0(" (", sum(!tested), " with too few summary times to test)"))
}

stabilityCheck <- function(sim) {
  series <- .stabilitySeries(sim)
  if (is.null(series) || !nrow(series)) {
    message("NRV_summary stability: no series to test")
    return(invisible(sim))
  }
  window <- .stabilityWindow(sim)
  res <- .trendStability(series, .stabilityKeys, window, P(sim)$stabilityAlpha, P(sim)$stabilityMinChange)

  d <- reproducible::checkPath(file.path(.ppRoot(sim), "csv", "stability"), create = TRUE)
  f_csv <- file.path(d, "stability.csv")
  utils::write.csv(res, f_csv, row.names = FALSE)
  sim <- registerOutputs(f_csv, sim)

  message("NRV_summary stability (", window[1L], "-", window[2L], "): ", .stabilityVerdict(res))

  figDir <- .ppFigDir(sim, "stability", "all")
  id <- do.call(paste, res[.stabilityKeys])
  for (k in unique(series$kind)) {
    sk <- series[series$kind == k, , drop = FALSE]
    rk <- res[res$kind == k, , drop = FALSE]
    nPages <- ceiling(nrow(rk) / 12L)
    for (pg in seq_len(nPages)) {
      Plots(
        data = list(series = sk, flag = rk$flag, id = do.call(paste, rk[.stabilityKeys])),
        fn = .stabilityPanels, window = window, page = pg,
        filename = paste0("stability_", k, "_p", pg), path = figDir,
        types = P(sim)$.plots, ggsaveArgs = list(width = 16, height = 10, units = "in")
      )
    }
  }
  Plots(
    data = res, fn = .stabilitySummary, minChange = P(sim)$stabilityMinChange,
    filename = "stability_summary", path = figDir,
    types = P(sim)$.plots, ggsaveArgs = list(width = 10, height = max(4, 0.25 * length(unique(res$metric))), units = "in")
  )
  invisible(sim)
}

.inputObjects <- function(sim) {
  ## nothing here

  return(invisible(sim))
}
