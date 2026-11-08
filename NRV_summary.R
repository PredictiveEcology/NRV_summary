defineModule(sim, list(
  name = "NRV_summary",
  description = paste("NRV simulation post-processing and summary creation.",
                      "Produces summaries for multiple patch metrics and other indicators."),
  keywords = c("NRV"),
  authors = c(
    person(c("Alex", "M."), "Chubaty", email = "achubaty@for-cast.ca", role = c("aut"))
  ),
  childModules = character(0),
  version = list(NRV_summary = "2.0.0.9039"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  loadOrder = list(after = c("Biomass_core")),
  documentation = list("README.md", "NRV_summary.Rmd"), ## .md produced from .Rmd
  reqdPkgs = list(
    "crayon", "data.table", "dplyr", "fs", "future", "future.apply", "future.callr",
    "ggforce", "ggplot2", "gifski", "googledrive", "landscapemetrics", "qs2",
    "RColorBrewer", "reproducible", "sf", "terra", "tidyterra",
    "PredictiveEcology/LandR@development (>= 1.2.0.9054)", ## leadingSpeciesProp(), leadingByPixelGroup()
    "PredictiveEcology/LandWebUtils@development (>= 1.0.3.9045)", ## sppEquiv_groups(), recode_cohorts()
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
    ## 0.3.4.9000, not 0.2.11: the figures draw the current condition over the NRV
    ## (plot_nrv_envelope(cc =), plot_by_class(cc =)) and the per-class pages read
    ## nrv_replicate_values().
    ## 0.3.4.9001, not 0.3.4.9000: summarize_nrv() takes the per-replicate values that the patch
    ## metric envelopes are built from and returns exact quartiles; nrv_metric_info() names the
    ## axes; the plot functions take captions.
    "FOR-CAST/nrvtools@development (>= 0.3.4.9002)",
    "PredictiveEcology/pemisc@development (>= 0.0.4.9016)",
    "PredictiveEcology/SpaDES.core@development (>= 3.2.1.9057)" ## dirnamesFromSet() (bare-number replicate folders), resolveSimYears(), padYears()
  ),
  parameters = bindrows(
    defineParameter("autocorrMaxLag", "integer", 200L, 1L, NA,
                    paste("longest lag (years) of the autocorrelation of the annual landscape series, which",
                          "gives the thinning interval for the summary snapshots.")),
    defineParameter("ageClasses", "character", LandWebUtils:::.ageClasses, NA, NA,
                    "descriptions/labels for age classes (seral stages)"),
    defineParameter("ageClassCutOffs", "integer", LandWebUtils:::.ageClassCutOffs, NA, NA,
                    "defines the age boundaries between age classes"),
    defineParameter("ageClassMaxAge", "integer", 400L, NA, NA,
                    "maximum possible age"),
    defineParameter("ccStandAgeSource", "character", "standAgeMap", NA, NA,
                    paste("(mode = 'single') where the current condition's (year 0's) stand-age map",
                          "comes from: 'standAgeMap', the age layer `sim$standAgeMap` (e.g.",
                          "Biomass_borealDataPrep's) on the pixels with cohorts, rounded and then",
                          "floored to the decade, as `LandR::standAgeMapGenerator()` floors the",
                          "simulated years' ages; or 'cohortData', that generator's biomass-weighted",
                          "age of the year-0 cohorts, which keeps the binning of the cohort ages.",
                          "'standAgeMap' warns and uses the cohorts when `sim$standAgeMap` is absent or",
                          "not on a grid aligned with `pixelGroupMap`. The simulated years always come",
                          "from the cohorts.")),
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
    defineParameter("recordAnnualSeries", "logical", TRUE, NA, NA,
                    paste("(mode = 'single') record a few landscape scalars every year (proportion young and old,",
                          "mean stand age, total biomass, proportion by leading species) in",
                          "`annualSeries.csv`. In 'multi' mode they give the autocorrelation time of the",
                          "landscape, hence how far apart the summary snapshots must be to be independent.")),
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
                          "'lm' for default landscape metrics;",
                          "'lw' for default LandWeb summaries",
                          "'pm' for default patch metrics;",
                          "'st' for stand-level measures (age-class, leading-type and forested shares, total",
                          "biomass) at each summary time, from the saved snapshots;",
                          "'on' for ON patch metrics.",
                          "Any other value is an error ('fd', forest degradation indicators, is not",
                          "implemented).")),
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
    defineParameter("sppEquivColReporting", "character", NA_character_, NA, NA,
                    paste("(mode = 'multi') column of `sim$sppEquiv` that groups the simulated species",
                          "(`sppEquivCol`) for reporting. When set, the vegetation-type maps that the",
                          "'lm', 'lw' and 'pm' analyses read, for the simulated years and for current",
                          "conditions, are rebuilt from the saved `cohortData` and `pixelGroupMap` with",
                          "each species recoded to its group, so biomass is summed within a group",
                          "before the leading type is decided. `LandR::vegTypeMapGenerator()` sums only",
                          "within a code, so relabelling the species-level maps would not give this.",
                          "`NA` (the default) analyses the species-level maps the simulation saved.")),
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
    expectsInput("sppColorVectReporting", "character",
                 desc = paste("(mode = 'multi', with `sppEquivColReporting`) named colours for the",
                              "reporting groups and 'Mixed'. If absent, `LandR::sppColors()` on the",
                              "reporting column.")),
    expectsInput("sppEquiv", "data.table", NA, NA, NA,
                 desc = "table of species equivalencies. See `LandR::sppEquivalencies_CA`."),
    expectsInput("standAgeMap", "SpatRaster",
                 desc = paste("(mode = 'single') stand age of the current forest (e.g.",
                              "Biomass_borealDataPrep's), on the grid of `pixelGroupMap` or on a",
                              "larger grid aligned with it. The year-0 stand-age map, with",
                              "`ccStandAgeSource = 'standAgeMap'`.")),
    expectsInput("studyAreaReporting", "SpatVector",
                 desc = "Required in single mode.")
  ),
  outputObjects = SpaDES.core:::._outputObjectsDF()
))

## event types
#   - type `init` is required for initialization

doEvent.NRV_summary = function(sim, eventTime, eventType) {
  ## The vegetation objects come from other modules, whose init may run after this one: check them at
  ## the first event that uses them (all scheduled .last()), not in init.
  if (eventType %in% c("map_generators", "save_single", "annual_series") && !isTRUE(mod$inputsChecked)) {
    .checkSingleInputs(sim)
    mod$inputsChecked <- TRUE
  }
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
        if (!P(sim)$ccStandAgeSource %in% c("standAgeMap", "cohortData")) {
          stop("ccStandAgeSource must be 'standAgeMap' or 'cohortData'.", call. = FALSE)
        }

        ## Year 0 is the current condition that mode = "multi" reports today's values from, so it
        ## is taken before any time-0 dynamics: after every module's init (SpaDES.core schedules
        ## those at .first()), before e.g. Biomass_core's growth and mortality (priority 6) when its
        ## growthInitialTime is start(sim). At .last(), it held a simulated year of both.
        sim <- scheduleEvent(sim, start(sim), "NRV_summary", "map_generators", .first() + 1)
        sim <- scheduleEvent(sim, start(sim), "NRV_summary", "save_single", .first() + 1)

        ## The later years at the end of their year, also each timeSeriesTimes year so the
        ## animation has its frames (read back in mode = "multi"); those typically fall outside
        ## summaryPeriod, so the summaryInterval reschedule does not cover them. The start of the
        ## summary period, the end and the timeSeriesTimes can coincide: each distinct time is
        ## scheduled once, and a time equal to start(sim) is left out (a second year-0 save would
        ## overwrite the one above). map_generators before save_single, so the maps exist when saved.
        later <- unique(c(P(sim)$summaryPeriod[1], end(sim), P(sim)$timeSeriesTimes))
        later <- later[later != start(sim)]
        mod$initTimes <- c(start(sim), later)
        for (tm in later) {
          sim <- scheduleEvent(sim, tm, "NRV_summary", "map_generators", .last())
          sim <- scheduleEvent(sim, tm, "NRV_summary", "save_single", .last())
        }

        if (isTRUE(P(sim)$recordAnnualSeries)) {
          mod$annualSeries <- list()
          sim <- scheduleEvent(sim, start(sim), "NRV_summary", "annual_series", .last())
        }
      } else if (P(sim)$mode == "multi") {
        stopifnot(!is.null(sim$reportingPolygons))

        ## reuse complete _aggregates parquet datasets (skip the ~2h landscape-metric recompute) so
        ## the postprocess events can iterate on plots/CSVs; read by .buildRepDataset() (process-local).
        options(NRV_summary.reuseAggregates = isTRUE(P(sim)$reuseAggregates))

        .checkPostprocessEvents(P(sim)$postprocessEvents)
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

        if ("lw" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_lw", .last())
        }

        if ("st" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_st", .last())
        }

        if ("bc" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_bc", .last())
        }

        if ("on" %in% tolower(P(sim)$postprocessEvents)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_on", .last())
        }

        ## after the metric events above, whose parquet datasets and the burn blocks it reads
        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_stability", .last() + 1)

        ## one figure of every group's current condition against the NRV, after the group events that make them
        if (any(c("lm", "st") %in% tolower(P(sim)$postprocessEvents))) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_cc", .last() + 1)
        }

        if (isTRUE(P(sim)$recordAnnualSeries)) {
          sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess_autocorr", .last())
        }

        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "postprocess", .last())
        sim <- scheduleEvent(sim, end(sim), "NRV_summary", "plot", .last())
      }
    },
    map_generators = {
      maps <- .landscapeMaps(sim)
      mod$vegTypeMap <- maps$vegTypeMap
      mod$standAgeMap <- maps$standAgeMap

      ## the current condition: today's ages, not the cohorts' binned ages, floored to the decade
      ## as the generator floors the simulated years' (see .ccStandAgeMap())
      if (time(sim) == start(sim) && P(sim)$ccStandAgeSource == "standAgeMap") {
        mod$standAgeMap <- .ccStandAgeMap(sim$standAgeMap, mod$standAgeMap)
      }

      nextTime <- time(sim) + P(sim)$summaryInterval
      ## times scheduled by init are not scheduled a second time here
      if (time(sim) >= P(sim)$summaryPeriod[1] && time(sim) < P(sim)$summaryPeriod[2] && !nextTime %in% mod$initTimes) {
        sim <- scheduleEvent(sim, nextTime, "NRV_summary", "map_generators", .last())
      }
    },
    annual_series = {
      if (is.null(mod$reportingCells)) {
        mod$reportingCells <- .reportingCells(sim$pixelGroupMap, sim$studyAreaReporting)
      }
      nPerGroup <- tabulate(terra::values(sim$pixelGroupMap, mat = FALSE)[mod$reportingCells])
      mod$annualSeries[[length(mod$annualSeries) + 1L]] <-
        .annualSeriesRow(time(sim), sim$cohortData, nPerGroup, prod(terra::res(sim$pixelGroupMap)) / 1e4,
                         P(sim)$ageClassCutOffs, P(sim)$vegLeadingProportion, P(sim)$mixedType,
                         sim$sppEquiv, P(sim)$sppEquivCol)
      if (time(sim) < end(sim)) {
        sim <- scheduleEvent(sim, time(sim) + 1, "NRV_summary", "annual_series", .last())
      } else {
        sim <- saveAnnualSeries(sim)
      }
    },
    postprocess_autocorr = {
      sim <- autocorrSummary(sim)
    },
    postprocess = {
      sim <- .registerPostprocessOutputs(sim)
    },
    plot = {
      sim <- plotFun(sim) ## plotFun() registers the PNGs, so its sim must be kept
    },
    postprocess_lm = {
      sim <- landscapeMetrics(sim) ## TODO: warning: Number of classes must be >= 3, IJI = NA.
    },
    postprocess_pm = {
      sim <- patchMetrics(sim)
    },
    postprocess_lw = {
      sim <- landWebMetrics(sim)
    },
    postprocess_st = {
      sim <- standMetrics(sim)
    },
    postprocess_stability = {
      sim <- stabilityCheck(sim)
    },
    postprocess_cc = {
      sim <- currentConditionAll(sim)
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
      sim <- .saveSingle(sim)
    },
    noEventWarning(sim)
  )

  return(invisible(sim))
}

# event functions -------------------------------------------------------------------

InitMulti <- function(sim) {
  mod$ppFiles <- character(0) ## files the postprocess events write; see .registerPostprocessOutputs()
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

  mod$rep1Dir <- rep1Dir
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
  fvtm0src <- mod$fvtm0 ## the species-level year-0 map, before the urban mask (see below)
  urbanMask <- NULL
  ccrep <- sim$LandTypeCC_reporting
  if (is.null(ccrep)) {
    ## do not fail silently: a missing layer here would look identical to "no urban present".
    warning("NRV_summary: `LandTypeCC_reporting` is absent; current-condition metrics will ",
            "report simulation year-0 state, counting urban imputed to forest as current forest.",
            call. = FALSE)
  } else {
    urbanMask <- terra::ifel(ccrep == 17L, NA, 1L) ## 17 = urban (LCC 2020)
    ccDir <- checkPath(file.path(outputPath(sim), "_cc"), create = TRUE)
    mod$fvtm0 <- .maskCC(mod$fvtm0, urbanMask, ccDir)
    mod$fsam0 <- .maskCC(mod$fsam0, urbanMask, ccDir)
    mod$ftsf0 <- .maskCC(mod$ftsf0, urbanMask, ccDir)
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

  ## per-rep annual landscape series (written by the `annual_series` event, if it ran)
  mod$annualSeriesFiles <- grep(paste0("(", paste0(mod$allReps, collapse = "|"), ")"),
                                filesOf("annualSeries[.]csv$"), value = TRUE)

  ## cohortData and pixelGroupMap files
  mod$cd <- grep("cohortData", cdpgm, value = TRUE)
  mod$pgm <- grep("pixelGroupMap", cdpgm, value = TRUE)

  ## Reporting groups: the lm/lw/pm analyses read maps of the groups rather than of the simulated
  ## species, rebuilt from the saved cohorts (see .buildReportingVegTypeMaps()). Only the maps they
  ## read change: time since fire (mod$tsf, mod$ftsf0) and stand age (mod$sam, mod$fsam0) stay those
  ## of the replicate folders, and mod$tsf was derived from the species-level paths above.
  if (!is.na(P(sim)$sppEquivColReporting)) {
    grp <- LandWebUtils::sppEquiv_groups(sim$sppEquiv, P(sim)$sppEquivCol, P(sim)$sppEquivColReporting)
    maps <- .buildReportingVegTypeMaps(
      c(fvtm0src, mod$vtm),
      outRoot = file.path(.ppRoot(sim), "_reportingMaps"),
      grp = grp,
      colors = .reportingColors(sim$sppColorVectReporting, grp),
      vegLeadingProportion = P(sim)$vegLeadingProportion,
      mixedType = P(sim)$mixedType
    )
    mod$vtm <- maps[-1L]
    mod$fvtm0 <- maps[[1L]]
    if (!is.null(urbanMask)) {
      mod$fvtm0 <- .maskCC(maps[[1L]], urbanMask, file.path(.ppRoot(sim), "_reportingMaps", "_cc"))
    }
    mod$ppFiles <- c(mod$ppFiles, maps, mod$fvtm0)
  }

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
## Mask a year-0 current-condition raster by `urbanMask` (NA where urban) and write it under
## `ccDir`, returning the new path. Returns the ORIGINAL path unchanged if the source is missing or
## the geometries do not line up, so a grid mismatch degrades to "uncorrected" loudly rather than
## producing a silently wrong current-condition value.
##
## The copy keeps the source's `<rep>/<prefix>_year<YYYY>.tif` tail (`<ccDir>/rep01/vegTypeMap_year0000.tif`):
## nrvtools labels every per-map result from that path and errors on anything else, so the
## `_cc/cc_vegTypeMap.tif` name this used to write stopped the lm/pm summaries the first time the
## correction actually ran.
.maskCC <- function(f, urbanMask, ccDir) {
  if (!file.exists(f)) return(f)
  outFile <- file.path(ccDir, basename(dirname(f)), basename(f))
  dir.create(dirname(outFile), recursive = TRUE, showWarnings = FALSE)
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

## The current condition's (year 0's) stand-age map: the age layer `standAgeMap` (e.g.
## Biomass_borealDataPrep's, on its larger grid) cropped to the grid of `cohortAge`, the map
## LandR::standAgeMapGenerator() makes from the year-0 cohorts, on the cells where that map has a
## value. Each age is rounded half up, as LandR::asInteger() rounds the ages the cohorts are made
## from, then floored to the decade, as standAgeMapGenerator() floors the age of every pixel in the
## maps of the simulated years, from which the envelopes are built (`floor(age / 10) * 10`, inline in
## the generator: LandR exports no function for it). So year 0 has the decade resolution of the
## envelopes, but not the binning of the cohort ages: Biomass_borealDataPrep rounds those above
## `minAgeForGrouping` to the nearest `pixelGroupAgeClass` (on WesternAlbertaUpland, above 70 to the
## nearest 20), which put 30.4% of that forest at 120 years or older, against 22.1% by the age layer.
## A cell with cohorts but no value in the age layer (Biomass_borealDataPrep imputes those ages)
## keeps its cohort age. Without an age layer on an aligned grid, warns and returns `cohortAge`.
.ccStandAgeMap <- function(standAgeMap, cohortAge) {
  useCohorts <- function(why) {
    warning("NRV_summary: `standAgeMap` ", why, "; the current condition's stand ages are those ",
            "of the year-0 cohorts, which are binned. Set `ccStandAgeSource = \"cohortData\"` to ",
            "use them without this warning.", call. = FALSE)
    cohortAge
  }
  if (is.null(standAgeMap)) {
    return(useCohorts("is absent"))
  }
  if (!inherits(standAgeMap, "SpatRaster")) {
    standAgeMap <- terra::rast(standAgeMap)
  }
  sam <- tryCatch(terra::crop(standAgeMap, cohortAge), error = function(e) NULL)
  if (is.null(sam) || !isTRUE(terra::compareGeom(sam, cohortAge, stopOnError = FALSE))) {
    return(useCohorts("is not on a grid aligned with `pixelGroupMap`"))
  }
  sam <- floor(sam + 0.5) ## rounded half up, as LandR::asInteger()
  sam <- floor(sam / 10) * 10 ## floored to the decade, as LandR::standAgeMapGenerator()
  nFilled <- terra::global(is.na(sam) & !is.na(cohortAge), "sum", na.rm = TRUE)[[1L]]
  if (nFilled > 0) {
    message("NRV_summary: ", nFilled, " pixels with cohorts have no value in `standAgeMap`; ",
            "their current stand age is that of their cohorts.")
  }
  sam <- terra::mask(terra::cover(sam, cohortAge), cohortAge)
  names(sam) <- names(cohortAge)
  sam
}

## Colours for the reporting groups and "Mixed", named exactly as LandR::vegTypeMapGenerator()
## asserts: the groups in `grp$groups` plus "Mixed".
.reportingColors <- function(colors, grp) {
  want <- c(grp$groups[[grp$col]], "Mixed")
  if (is.null(colors)) {
    colors <- LandR::sppColors(grp$groups, grp$col, newVals = "Mixed", palette = "Accent")
  }
  miss <- setdiff(want, names(colors))
  if (length(miss)) {
    stop("NRV_summary: `sppColorVectReporting` has no colour for: ", paste(miss, collapse = ", "),
         ".", call. = FALSE)
  }
  colors[want]
}

## One vegetation-type map by reporting group: a copy of `cohortData` with each species recoded to
## its group (`grp` from LandWebUtils::sppEquiv_groups()), so that LandR::vegTypeMapGenerator(),
## which sums B within a species code, sums it within a group before deciding the leading type.
.reportingVegTypeMap <- function(cohortData, pixelGroupMap, grp, colors, vegLeadingProportion,
                                 mixedType) {
  LandR::vegTypeMapGenerator(
    LandWebUtils::recode_cohorts(cohortData, grp$map),
    pixelGroupMap,
    vegLeadingProportion,
    mixedType = mixedType,
    sppEquiv = grp$groups,
    sppEquivCol = grp$col,
    colors = colors,
    doAssertion = getOption("LandR.assertions", TRUE)
  )
}

## Rebuild species-level vegetation-type maps (`<dir>/<rep>/vegTypeMap_year<YYYY>.tif`) by reporting
## group, from the cohortData and pixelGroupMap saved beside each. Written to
## `<outRoot>/<rep>/vegTypeMap_year<YYYY>.tif`, keeping the `<rep>/<prefix>_year<YYYY>` tail nrvtools
## labels its results from; `outRoot` is cleared first. Returns the new paths in the order of `vtm`.
.buildReportingVegTypeMaps <- function(vtm, outRoot, grp, colors, vegLeadingProportion, mixedType) {
  stopifnot(all(grepl("^vegTypeMap_year[0-9]+\\.tif$", basename(vtm))))
  cd <- file.path(dirname(vtm), sub("^vegTypeMap(_year[0-9]+)\\.tif$", "cohortData\\1.qs2", basename(vtm)))
  pgm <- file.path(dirname(vtm), sub("^vegTypeMap", "pixelGroupMap", basename(vtm)))
  miss <- c(cd, pgm)[!file.exists(c(cd, pgm))]
  if (length(miss)) {
    stop("NRV_summary: cannot build the reporting-group maps; missing:\n", paste(miss, collapse = "\n"),
         call. = FALSE)
  }
  out <- file.path(outRoot, basename(dirname(vtm)), basename(vtm))
  unlink(outRoot, recursive = TRUE)
  for (i in seq_along(vtm)) {
    m <- .reportingVegTypeMap(qs2::qs_read(cd[i]), terra::rast(pgm[i]), grp, colors,
                              vegLeadingProportion, mixedType)
    dir.create(dirname(out[i]), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(m, out[i], datatype = "INT1U", overwrite = TRUE) ## a few classes; keeps the colour table
  }
  out
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

## Stop before any work if `postprocessEvents` asks for an event this module does not implement:
## an unknown value would otherwise be skipped without a word, and 'fd' (forest degradation) was
## scheduled as a stub that stopped in browser() after the other summaries had run.
.checkPostprocessEvents <- function(events) {
  known <- c("am", "bc", "lm", "lw", "on", "pm", "st")
  bad <- setdiff(tolower(events), known)
  if (length(bad)) {
    stop(
      "postprocessEvents not implemented: ", paste0("'", bad, "'", collapse = ", "),
      ". Use any of: ", paste0("'", known, "'", collapse = ", "), "."
    )
  }
  invisible(events)
}

.ppRoot <- function(sim) {
  file.path(dirname(outputPath(sim)), "postprocess")
}

## Register every file the postprocess events wrote (parquet aggregates, envelope CSVs, the
## stand-age animation) as module outputs, so the stage's `_files` target in a targets pipeline
## tracks them; unregistered, it tracked nothing. Figures are registered by plotFun(), which runs
## after this.
.registerPostprocessOutputs <- function(sim) {
  f <- unique(mod$ppFiles)
  f <- f[file.exists(f)]
  mod$ppFiles <- character(0)
  if (length(f)) {
    sim <- registerOutputs(f, sim)
  }
  sim
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

## Build the parquet dataset for one refCode: one partition per replicate. `compute_fn(repID)`
## returns the raw metric list for one replicate (from a raw nrvtools producer). `reuse = TRUE` skips
## the (expensive) recompute + rewrite when the dataset is already complete for `repIDs` (see
## `.aggComplete()`) -- useful for iterating on the plots/CSVs without re-running the
## landscape-metric aggregation.
.writeRepDataset <- function(root, repIDs, compute_fn, studyArea = NULL, scenario = NULL,
                             reuse = getOption("NRV_summary.reuseAggregates", FALSE)) {
  if (!(reuse && .aggComplete(root, repIDs))) {
    unlink(root, recursive = TRUE)
    for (repID in repIDs) {
      tidied <- tidy_nrv_metrics(compute_fn(repID), studyArea = studyArea, scenario = scenario)
      write_nrv_parquet(tidied, root, replicate = repID)
    }
  }
  invisible(root)
}

## The across-replicate envelope of one refCode's dataset, registering its parquet files.
## id_cols = NULL -> summarize_nrv() default (per-time envelopes); the LandWeb summaries pass an
## explicit set excluding `time` so the NRV distribution pools across replicates AND summary years.
## `perReplicate = TRUE` first reduces each replicate's patches to their mean
## (nrvtools::nrv_replicate_values()), so that a patch-level metric's envelope is, like a class- or
## landscape-level one's, the range of the replicates rather than of every patch of every
## replicate; class- and landscape-level metrics pass through unchanged. A replicate without a
## value there (an undefined metric, such as the standard deviation of a single patch) is then left
## out, so the envelope's n_reps counts the replicates that have one.
.summarizeRepDataset <- function(root, id_cols = NULL, perReplicate = FALSE) {
  mod$ppFiles <- c(mod$ppFiles, list.files(root, "\\.parquet$", recursive = TRUE, full.names = TRUE))
  if (!perReplicate) {
    return(nrvtools::summarize_nrv(root, id_cols = id_cols))
  }
  v <- nrvtools::nrv_replicate_values(root)
  if (nrow(v)) {
    v <- v[!is.na(v$value), , drop = FALSE]
  }
  nrvtools::summarize_nrv(v, id_cols = id_cols)
}

## Build the parquet dataset for one refCode and return the across-replicate envelope.
.buildRepDataset <- function(root, repIDs, compute_fn, studyArea = NULL, scenario = NULL,
                             id_cols = NULL, reuse = getOption("NRV_summary.reuseAggregates", FALSE),
                             perReplicate = FALSE) {
  .writeRepDataset(root, repIDs, compute_fn, studyArea = studyArea, scenario = scenario,
                   reuse = reuse)
  .summarizeRepDataset(root, id_cols = id_cols, perReplicate = perReplicate)
}

## Class area (`ca`) of 0 ha for each class that a subregion shows -- in its current condition or
## in any replicate-year -- but lacks in a replicate-year, the current condition included.
## landscapemetrics returns no row for a class absent from a map, so the class-area envelopes and
## boxes summarised only the replicate-years where the class occurs, and a class absent from most
## of them looked as common as one present in all. Patch size, shape and age metrics stay undefined
## for an absent class, so only `ca` is filled. `roots` are the dataset roots of one reporting
## layer (replicates and current condition). The zeros go to `replicate=<id>/<zerosFile>`, rebuilt
## from the other files on every call, so a reused dataset is filled the same way. Returns the
## files written.
.fillClassAreaZeros <- function(roots, zerosFile = "ca_zeros.parquet") {
  .fillAbsentZeros(
    roots,
    zerosFile,
    select = function(ds) dplyr::filter(ds, .data$level == "class", .data$metric == "ca"),
    classCol = "class"
  )
}

## The same for the LandWeb summaries (lw): 0 in every lw metric (leading proportion, share of the
## forest, large-patch count and area) of each vegetation type that a subregion shows but lacks in
## a replicate-year. The nrvtools producers write rows only for the types present in a map, so a
## type that leads in 7 of 105 replicate-years had its boxes drawn from those 7 alone. Each metric x
## age class the dataset holds is filled.
.fillLeadingZeros <- function(roots, zerosFile = "lw_zeros.parquet") {
  .fillAbsentZeros(roots, zerosFile, select = identity, classCol = "metric.1",
                   otherCols = c("level", "metric", "class"))
}

## Rows of 0 for each class (`classCol`) that a subregion shows -- in its current condition or in
## any replicate-year -- but lacks in a replicate-year, among the rows that `select()` (an Arrow
## query) picks from each dataset, for every combination of `otherCols` those rows hold. See
## .fillClassAreaZeros().
.fillAbsentZeros <- function(roots, zerosFile, select, classCol, otherCols = character(0)) {
  parts <- lapply(roots, function(root) {
    f <- list.files(root, "\\.parquet$", recursive = TRUE, full.names = TRUE)
    unlink(f[basename(f) == zerosFile])
    f <- f[basename(f) != zerosFile]
    if (!length(f)) {
      return(NULL)
    }
    ds <- arrow::open_dataset(f)
    yearCols <- intersect(c("studyArea", "scenario", "rptPoly", "replicate", "rep", "time"), names(ds))
    list(
      root = root,
      schema = ds$schema,
      ## every replicate-year of the dataset, whether or not a subregion has the class in it
      years = as.data.frame(dplyr::collect(dplyr::distinct(ds, !!!rlang::syms(yearCols)))),
      rows = as.data.frame(dplyr::collect(select(ds)))
    )
  })
  parts <- Filter(Negate(is.null), parts)
  seen <- unique(do.call(rbind, lapply(parts, function(p) p$rows[c("poly", classCol)])))
  if (is.null(seen) || !nrow(seen)) {
    return(invisible(character(0)))
  }
  written <- character(0)
  for (p in parts) {
    if (!nrow(p$rows)) next ## a dataset without such rows (another funList) gets none
    grid <- merge(p$years, seen, by = NULL)
    if (length(otherCols)) grid <- merge(grid, unique(p$rows[otherCols]), by = NULL)
    keyCols <- c(names(p$years), "poly", classCol, otherCols)
    key <- function(d) do.call(paste, c(lapply(d[keyCols], as.character), sep = "\r"))
    miss <- grid[!key(grid) %in% key(p$rows), , drop = FALSE]
    if (!nrow(miss)) next
    ## in a fixed order, so a rerun writes the same files: Arrow returns rows in no fixed order
    miss <- miss[do.call(order, c(unname(as.list(miss[keyCols])), method = "radix")), , drop = FALSE]
    ## zero rows shaped like the dataset's own rows
    z <- p$rows[rep(1L, nrow(miss)), , drop = FALSE]
    z[keyCols] <- miss[keyCols]
    z$value[] <- 0
    if ("id" %in% names(z)) z$id[] <- NA
    z <- z[names(p$schema)]
    for (r in unique(z$replicate)) {
      dst <- file.path(p$root, paste0("replicate=", r), zerosFile)
      tmp <- tempfile(tmpdir = dirname(dst), fileext = ".parquet.tmp")
      arrow::write_parquet(arrow::arrow_table(z[z$replicate == r, , drop = FALSE], schema = p$schema), tmp)
      if (!file.rename(tmp, dst)) {
        unlink(tmp)
        stop("NRV_summary: failed to write ", dst, call. = FALSE)
      }
      written <- c(written, dst)
    }
  }
  invisible(written)
}

## Write the range-of-variation envelope for one refCode + reporting `layer` under csv/<kind>/<layer>/:
## a combined `<base>.csv` plus one `<base>_<metric>.csv` per metric. `kind` (lm/pm/sspm/lw) and the
## `_CC` suffix are recovered from `refCode`; the enclosing <kind>/<layer>/ dir supplies the context
## the flat filenames used to carry, and it mirrors the figure dir structure. The `lw` (LandWeb
## summary) envelope is split by analysis -- leadingProp and leadingShare -> csv/boxplots/<layer>/
## (the leading boxplot data), the large-patch metrics -> csv/histograms/<layer>/.
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
    fs <- file.path(d, paste0(base, cc, ".csv"))
    write.csv(e, fs, row.names = FALSE)
    for (m in unique(e$metric)) {
      fm <- file.path(d, paste0(base, cc, "_", m, ".csv"))
      write.csv(e[e$metric == m, ], fm, row.names = FALSE)
      fs <- c(fs, fm)
    }
    mod$ppFiles <- c(mod$ppFiles, fs)
  }
  if (kind == "lw") {
    isLead <- env$metric %in% c("leadingProp", "leadingShare")
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
      ## perReplicate: the envelopes count only the replicates with a value, as for pm
      mod[[refCodeCC]] <- suppressWarnings(
        .buildRepDataset(
          .nrvAggRoot(sim, refCodeCC),
          repIDs = "CC",
          compute_fn = function(repID) lmRaw(fvtm0),
          perReplicate = TRUE
        )
      )

      ## simulation: one parquet partition per replicate, then reduce across reps.
      mod[[refCode]] <- .buildRepDataset(
        .nrvAggRoot(sim, refCode),
        repIDs = names(vtmByRep),
        compute_fn = function(repID) lmRaw(vtmByRep[[repID]]),
        perReplicate = TRUE
      )

      .writeNrvSummaryCSVs(sim, mod[[refCode]], refCode, p)
      .writeNrvSummaryCSVs(sim, mod[[refCodeCC]], refCodeCC, p)
      .writeNrvComparisonCSV(sim, mod[[refCode]], mod[[refCodeCC]], "lm", p)

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

      ## current conditions, then the simulation results; then 0 ha of each class a subregion lacks
      ccRoot <- .nrvAggRoot(sim, refCodeCC)
      simRoot <- .nrvAggRoot(sim, refCode)
      .writeRepDataset(ccRoot, repIDs = "CC", compute_fn = function(repID) pmRaw(fvtm0, fsam0))
      .writeRepDataset(
        simRoot,
        repIDs = names(vtmByRep),
        compute_fn = function(repID) pmRaw(vtmByRep[[repID]], samByRep[[repID]])
      )
      .fillClassAreaZeros(c(simRoot, ccRoot))

      ## a patch-level metric's envelope spans the replicates' means over their patches, as the
      ## per-class pages do. Pooling every patch of every replicate ran the band from a single cell
      ## to the largest patch, and the current condition's patch mean and median (the lines of the
      ## ribbon and box figures) were up to 51 times apart.
      mod[[refCodeCC]] <- .summarizeRepDataset(ccRoot, perReplicate = TRUE)
      mod[[refCode]] <- .summarizeRepDataset(simRoot, perReplicate = TRUE)

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

      ## current conditions: a single (year-0) snapshot, treated as one replicate; simulation
      ## results: one parquet partition per replicate (vtm/tsf vectors align by index). Then 0 in
      ## each replicate-year for the vegetation types a subregion shows but lacks there.
      ccRoot <- .nrvAggRoot(sim, refCodeCC)
      simRoot <- .nrvAggRoot(sim, refCode)
      .writeRepDataset(ccRoot, repIDs = "CC", compute_fn = function(repID) lwRaw(fvtm0, ftsf0))
      .writeRepDataset(
        simRoot,
        repIDs = names(vtmByRep),
        compute_fn = function(repID) lwRaw(vtmByRep[[repID]], tsfByRep[[repID]])
      )
      .fillLeadingZeros(c(simRoot, ccRoot))
      mod[[refCodeCC]] <- .summarizeRepDataset(ccRoot, id_cols = idCols)
      mod[[refCode]] <- .summarizeRepDataset(simRoot, id_cols = idCols)

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

  oldPlan <- .planWithWorkers(pemisc::optimalClusterNum(5000, length(fssm)))
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

  mod$ppFiles <- c(mod$ppFiles, gifFile)
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

    ## Shares of the forest: one file per subregion, a box per leading type in each age-class panel
    tasks <- c(tasks, .leadingShareFigTasks(
      raw, cc, ageClasses, dBox, saPrefix,
      areaHa = function(poly) areaHa(poly, "All species")
    ))
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

## The share-of-forest figure TASKS of one reporting layer, one per subregion
## (`<dir>/<subregion> share of forest.png`): a panel per age class with a box per leading
## vegetation type of its share of the subregion's forest over the replicates and summary years
## (nrvtools::plot_leading_share()), and the current condition in red. `raw` and `cc` hold the
## layer's per-replicate and current-condition lw rows (`cc` may be NULL), and `areaHa(poly)` a
## subregion's forested area for the caption (NA: none). A subregion where no type leads in any
## replicate-year gets no figure.
.leadingShareFigTasks <- function(raw, cc, ageClasses, dir, titlePrefix, areaHa) {
  share <- raw[raw$metric == "leadingShare", , drop = FALSE]
  safe <- function(s) gsub("[/\\]", "-", s) ## filename-safe subregion
  tasks <- list()
  for (poly in unique(share$poly)) {
    d <- share[share$poly == poly & share$metric.1 != "All species", , drop = FALSE]
    if (!nrow(d) || all(d$value == 0, na.rm = TRUE)) next
    ccP <- if (!is.null(cc)) cc[cc$poly == poly & cc$metric == "leadingShare", , drop = FALSE]
    if (!is.null(ccP) && !nrow(ccP)) ccP <- NULL
    nk <- paste(.countText(length(unique(d$replicate)), "replicate"), "x",
                .countText(length(unique(d$time)), "simulation year"))
    cap <- paste0(
      "Boxes: median and quartiles of ", nk, ", counting a replicate-year in which a type leads ",
      "nowhere as 0; whiskers: to the furthest value within 1.5 x IQR of the box, with values ",
      "beyond as points",
      if (!is.null(ccP)) "; red points: current condition (simulation year 0)",
      "."
    )
    cap <- paste(strwrap(cap, width = 150), collapse = "\n")
    a <- areaHa(poly)
    if (!is.na(a)) {
      cap <- paste0(cap, "\nTotal forested area in ", poly, ": ",
                    format(round(a), big.mark = ","), " ha")
    }
    sp <- unique(as.character(d$metric.1))
    tasks[[length(tasks) + 1L]] <- list(
      plotter = "leadingShare", df = d, cc = ccP, ageClasses = ageClasses,
      species_labels = stats::setNames(.vegTypeLabels(sp), sp),
      title = paste0(titlePrefix, poly), caption = cap,
      file = file.path(dir, paste0(safe(poly), " share of forest.png")),
      width = 11, height = max(4, 2 + 0.5 * length(sp))
    )
  }
  tasks
}

## Current-condition rows of one metric (and subregion) from a `<refCode>_CC` table, drawn over that
## metric's figures as the reference. NULL when there are none.
.ccFor <- function(cc, met, poly = NULL) {
  if (is.null(cc) || !nrow(cc)) {
    return(NULL)
  }
  keep <- cc$metric == met
  if (!is.null(poly)) {
    keep <- keep & cc$poly == poly
  }
  cc <- cc[which(keep), , drop = FALSE]
  if (nrow(cc)) cc else NULL
}

## Pages that nrvtools' paginated figures (4 x 3 panels per page) take for `nPanels` panels.
.nPages <- function(nPanels, perPage = 12L) {
  max(1L, as.integer(ceiling(nPanels / perPage)))
}

## The layout of page `page` of `nPanels` panels at `perPage` a page: the last page holds only what is left.
.pageLayout <- function(nPanels, page, perPage = 12L) {
  .figLayout(min(perPage, nPanels - perPage * (page - 1L)), paginate = TRUE)
}

.pageTitle <- function(title, page, nPages) {
  if (nPages > 1L) paste0(title, " (page ", page, " of ", nPages, ")") else title
}

## Panel grid and canvas (inches) of a figure of `nPanels` panels, four to a row. A page holds at
## most three rows (`paginate`), and the height follows the rows, so a page of fewer panels has no
## empty rows. A single panel gets a smaller canvas. `extra` adds height, e.g. for x axis labels
## that stand on end.
.figLayout <- function(nPanels, paginate = FALSE, extra = 0) {
  if (nPanels <= 1L) {
    return(list(ncol = 1L, nrow = 1L, width = 8, height = 5 + extra))
  }
  ncol <- min(4L, as.integer(nPanels))
  nrow <- as.integer(ceiling(nPanels / ncol))
  if (paginate) {
    nrow <- min(3L, nrow)
  }
  list(ncol = ncol, nrow = nrow, width = max(8, 4 * ncol), height = 2 + 2.75 * nrow + extra)
}

## Panels of a figure of `d` faceted by the columns `facet`: one per combination of their values.
.nPanels <- function(d, facet) {
  facet <- intersect(facet, names(d))
  if (length(facet)) nrow(unique(d[facet])) else 1L
}

## The level of the rows of one metric ("patch", "class" or "landscape"); NA if not one level.
.levelOf <- function(d) {
  lv <- unique(d$level)
  if (length(lv) == 1L) as.character(lv) else NA_character_
}

## The y title of a figure of metric `met`: its plain name and unit (nrvtools::nrv_metric_info()),
## for a patch-level metric with how a replicate's value comes from its patches.
.metricTitle <- function(met, level) {
  lab <- nrvtools::nrv_metric_info(met, level)$label
  if (identical(level, "patch")) paste0(lab, ", mean over patches") else lab
}

## Display names of vegetation types: the labels of LandWeb's reporting groups
## (LandWebUtils::landweb_report_groups(); "Bl Spruce" for Bl_Spruce), else the code with its
## underscores as spaces.
.vegTypeLabels <- function(x) {
  x <- as.character(x)
  g <- LandWebUtils::landweb_report_groups()
  lab <- g$label[match(x, g$code)]
  ifelse(is.na(lab), gsub("_", " ", x, fixed = TRUE), lab)
}

## "15 replicates", "1 replicate", or "3-15 replicates" when the counts `n` differ.
.countText <- function(n, what) {
  n <- n[!is.na(n)]
  if (length(n) && min(n) < max(n)) {
    return(paste0(min(n), "-", max(n), " ", what, "s"))
  }
  n <- max(c(n, 0))
  paste(n, if (n == 1) what else paste0(what, "s"))
}

## The caption of an NRV figure: what its marks show, with the replicate and year counts of the
## data drawn. `type` is "ribbon" (a band), "lines" (a line per replicate) or "boxplot" for an envelope (`df` from summarize_nrv(), whose
## n_reps count the replicates with a value), "box" or "violin" for a per-class page (`df` of
## per-replicate values). `cc` holds the figure's current-condition rows, if any; the caption names
## the current condition when one of them has a value to draw. Wrapped to `width` inches.
.figCaption <- function(type, df, cc = NULL, perPatch = FALSE, width = 16) {
  fewer <- " (fewer where a class is absent or the metric undefined)"
  if (type %in% c("ribbon", "lines", "boxplot")) {
    n <- .countText(df$n_reps, "replicate")
    varies <- length(unique(df$n_reps)) > 1L
    parts <- if (type == "ribbon") {
      c(paste0("Grey band: range of ", n, " at each simulation year", if (varies) fewer), "line: mean")
    } else if (type == "lines") {
      c(paste0("Thin grey lines: ", n, if (varies) fewer), "bold line: median over the replicates")
    } else {
      c(
        paste0("Boxes: median and quartiles of ", n, " at each simulation year", if (varies) fewer),
        "whiskers: minimum to maximum"
      )
    }
    ccCol <- if (type == "boxplot") "median" else "mean"
    if (!is.null(cc) && any(is.finite(cc[[ccCol]]))) {
      parts <- c(parts, "red dashed line: current condition (simulation year 0)")
    }
  } else {
    fin <- df[is.finite(df$value), , drop = FALSE]
    n <- length(unique(fin$replicate))
    k <- length(unique(fin$time))
    nk <- paste(.countText(n, "replicate"), "x", .countText(k, "simulation year"))
    perBox <- table(paste(fin$poly, fin$class))
    varies <- any(perBox < n * k)
    parts <- if (type == "box") {
      c(
        paste0("Boxes: median and quartiles of ", nk, if (varies) fewer),
        "whiskers: to the furthest value within 1.5 x IQR of the box, with values beyond as points"
      )
    } else {
      paste0("Violins: distribution of ", nk, if (varies) fewer)
    }
    drawn <- if (!is.null(cc)) cc[cc$poly %in% fin$poly & is.finite(cc$value), , drop = FALSE]
    if (!is.null(drawn) && nrow(drawn)) {
      parts <- c(parts, "red points: current condition (simulation year 0)")
      if (any(!paste(drawn$poly, drawn$class) %in% names(perBox))) {
        parts <- c(parts, "a red point without a box has no simulated value")
      }
    }
  }
  txt <- paste0(paste(parts, collapse = "; "), ".")
  if (perPatch) {
    txt <- paste(txt, "A replicate's value is the mean over its patches.")
  }
  paste(strwrap(txt, width = floor(14 * width)), collapse = "\n")
}

## Envelope figure TASKS (see .renderTasks()) for one analysis `kind` (lm/pm/sspm) x reporting
## `layer`, from the envelope in `mod`, each with the current-condition envelope (`<refCode>_CC`)
## drawn over it as a reference line:
## - layout "subregion": one figure per (metric x subregion), the subregion in the filename and the
##   title (the study area is in the output path); class-resolved metrics (pm) facet by class, and
##   landscape metrics (lm), which have no class, are a single panel.
## - layout "metric": one figure-set per metric with a panel per subregion (and class), paginated
##   across PNGs (`<metric>_<type>_p<pg>.png`, in `subdir` of the layer's figure dir when given).
##   A layer with fewer than `minSubregions` subregions gets none.
## Only units with a value get a panel, so the panels and pages counted here are those drawn. The
## y title is the metric's plain name and unit unless `ylab` is given; `classLabels` maps the class
## codes to the names shown; `captions = FALSE` omits the captions, which describe replicate
## envelopes. `repLines = TRUE` draws the ribbon figures as a thin grey line per replicate and the
## median bold (the replicates' values read from the parquet aggregates, as for the per-class pages),
## not as a band; where the aggregates hold no replicate values the band is drawn. The output dirs
## are created here (main worker).
.envelopeFigTasks <- function(sim, kind, p, ylab = NULL, layout = c("subregion", "metric"),
                              subdir = NULL, titlePrefix = "", minSubregions = 1L,
                              classLabels = NULL, captions = TRUE, nrvPeriod = NULL,
                              repLines = FALSE) {
  layout <- match.arg(layout)
  refCode <- LandWebUtils::refCodeFor(kind, p)
  env <- mod[[refCode]]
  if (is.null(env) || !nrow(env)) {
    return(list())
  }
  env <- env[is.finite(env$mean) & is.finite(env$min) & is.finite(env$max), , drop = FALSE]
  cc <- mod[[paste0(refCode, "_CC")]]
  if (!is.null(classLabels)) {
    env$class <- classLabels(env$class)
    if (!is.null(cc) && nrow(cc)) {
      cc$class <- classLabels(cc$class)
    }
  }
  reps <- if (repLines) nrvtools::nrv_replicate_values(.nrvAggRoot(sim, refCode))
  if (!is.null(reps) && nrow(reps)) {
    reps <- reps[is.finite(reps$value), , drop = FALSE]
    if (!is.null(classLabels)) {
      reps$class <- classLabels(reps$class)
    }
  }
  safe <- function(s) gsub("[/\\]", "-", s) ## filename-safe metric / subregion
  ## `nrvPeriod` (the NRV years, .nrvPeriod(sim)) is shaded on every envelope; see .addNrvShading()
  task <- function(sub, ccSub, type, facet, title, page, lay, file) {
    lev <- .levelOf(sub)
    ## the replicates' values of the metric (and subregion) drawn, for a ribbon figure
    repSub <- if (type == "ribbon" && !is.null(reps) && nrow(reps)) {
      reps[reps$metric %in% sub$metric & reps$poly %in% sub$poly, , drop = FALSE]
    }
    if (!is.null(repSub) && !nrow(repSub)) repSub <- NULL
    list(
      plotter = "envelope", df = sub, cc = ccSub, type = type, facet = facet, nrvPeriod = nrvPeriod,
      reps = repSub,
      ylab = if (is.null(ylab)) .metricTitle(unique(sub$metric), lev) else ylab,
      xlab = "Simulation year", title = title,
      caption = if (captions) {
        .figCaption(if (is.null(repSub)) type else "lines", sub, cc = ccSub, perPatch = identical(lev, "patch"), width = lay$width)
      },
      page = page, ncol = lay$ncol, nrow = if (is.null(page)) NULL else lay$nrow,
      file = file, width = lay$width, height = lay$height
    )
  }
  tasks <- list()

  if (layout == "subregion") {
    d <- .ppFigDir(sim, kind, p)
    facet <- c("class", "metric.1")
    for (met in unique(env$metric)) {
      em <- env[env$metric == met, , drop = FALSE]
      for (poly in unique(em$poly)) {
        sub <- em[em$poly == poly, , drop = FALSE]
        lay <- .figLayout(.nPanels(sub, facet))
        for (type in c("ribbon", "boxplot")) {
          tasks[[length(tasks) + 1L]] <- task(
            sub, .ccFor(cc, met, poly), type, facet,
            title = paste0(poly, " — ", met), page = NULL, lay = lay,
            file = file.path(d, paste0(safe(poly), " ", safe(met), "_", type, ".png"))
          )
        }
      }
    }
    return(tasks)
  }

  if (length(unique(env$poly)) < minSubregions) {
    return(list())
  }
  d <- if (is.null(subdir)) .ppFigDir(sim, kind, p) else .ppFigDir(sim, kind, p, subdir)
  facet <- c("poly", "class", "metric.1")
  for (met in unique(env$metric)) {
    sub <- env[env$metric == met, , drop = FALSE]
    nPanels <- .nPanels(sub, facet)
    lay <- .figLayout(nPanels, paginate = TRUE)
    nPages <- .nPages(nPanels)
    for (type in c("ribbon", "boxplot")) {
      for (pg in seq_len(nPages)) {
        tasks[[length(tasks) + 1L]] <- task(
          sub, .ccFor(cc, met), type, facet,
          title = .pageTitle(paste0(titlePrefix, met), pg, nPages), page = pg, lay = lay,
          file = file.path(d, paste0(safe(met), "_", type, "_p", pg, ".png"))
        )
      }
    }
  }
  tasks
}

## Per-class distribution figure TASKS for one analysis `kind` (pm) x reporting `layer`: for each
## metric, box and violin plots of its values for each class, one panel per subregion, paginated
## (`<metric>_<box|violin>_p<pg>.png` in `subdir`), with the current-condition values as red
## points. The values are those of each replicate and summary year, read from the raw parquet
## aggregates (nrvtools::nrv_replicate_values(), which averages a patch-level metric over each
## replicate's patches), so a box spans the variation across replicates and time. A layer this run
## did not summarise gets none: what is on disk may be another run's. Patch area has no pages of
## its own: a replicate's mean patch area is the class's mean patch area, area_mn. Only subregions
## with a value get a panel, so the pages counted here are those drawn.
.byClassFigTasks <- function(sim, kind, p, xlab = "class", subdir = "per-metric", titlePrefix = "",
                             classLabels = NULL) {
  refCode <- LandWebUtils::refCodeFor(kind, p)
  if (is.null(mod[[refCode]]) || !nrow(mod[[refCode]])) {
    return(list())
  }
  reps <- nrvtools::nrv_replicate_values(.nrvAggRoot(sim, refCode))
  if (!nrow(reps)) {
    return(list())
  }
  cc <- nrvtools::nrv_replicate_values(.nrvAggRoot(sim, paste0(refCode, "_CC")))
  ## integer class codes -> labels, as for the envelopes (a no-op once the parquet stores labels)
  if (!is.null(mod$fvtm0) && file.exists(mod$fvtm0)) {
    vtmRAT <- terra::rast(mod$fvtm0)
    reps <- nrvtools::label_vegtype_classes(reps, vtmRAT)
    cc <- nrvtools::label_vegtype_classes(cc, vtmRAT)
  }
  if (!is.null(classLabels)) {
    reps$class <- classLabels(reps$class)
    if (nrow(cc)) {
      cc$class <- classLabels(cc$class)
    }
  }
  d <- .ppFigDir(sim, kind, p, subdir)
  safe <- function(s) gsub("[/\\]", "-", s) ## filename-safe metric
  tasks <- list()
  for (met in unique(reps$metric)) {
    sub <- reps[reps$metric == met, , drop = FALSE]
    lev <- .levelOf(sub)
    if (met == "area" && identical(lev, "patch") && "area_mn" %in% reps$metric) next
    sub <- sub[sub$poly %in% sub$poly[is.finite(sub$value)], , drop = FALSE]
    if (!nrow(sub)) next
    nPanels <- length(unique(sub$poly))
    lay <- .figLayout(nPanels, paginate = TRUE, extra = 0.5)
    nPages <- .nPages(nPanels)
    ccMet <- .ccFor(cc, met)
    for (type in c("box", "violin")) {
      for (pg in seq_len(nPages)) {
        tasks[[length(tasks) + 1L]] <- list(
          plotter = "byclass", df = sub, cc = ccMet, type = type, page = pg,
          ncol = lay$ncol, nrow = lay$nrow, xlab = xlab, ylab = .metricTitle(met, lev),
          title = .pageTitle(paste0(titlePrefix, met), pg, nPages),
          caption = .figCaption(type, sub, cc = ccMet, perPatch = identical(lev, "patch"),
                                width = lay$width),
          file = file.path(d, paste0(safe(met), "_", type, "_p", pg, ".png")),
          width = lay$width, height = lay$height
        )
      }
    }
  }
  tasks
}

## Number of local worker processes for parallel plot rendering: RAM-aware (optimalClusterNum) but
## hard-capped by the `plotWorkers` parameter, so a shared node is not swamped. 1 -> render inline.
## Set the current future plan's `workers` to `nWorkers`, keeping its backend; returns the previous
## plan, for on.exit(). A backend without `workers` (sequential) is left alone: tweaking it only
## warns. future (<= 1.76.0) appends a tweak rather than replacing it, so re-tweaking `workers` on a
## plan set as `plan(<backend>, workers = n)` failed with 'formal argument "workers" matched by
## multiple actual arguments'; only the latest value of each tweak is kept.
.planWithWorkers <- function(nWorkers) {
  strategy <- future::plan()
  if (!"workers" %in% names(formals(strategy))) {
    return(strategy)
  }
  strategy <- future::tweak(strategy, workers = nWorkers)
  tweaks <- attr(strategy, "tweaks")
  if (is.list(tweaks) && anyDuplicated(names(tweaks))) {
    attr(strategy, "tweaks") <- tweaks[!duplicated(names(tweaks), fromLast = TRUE)]
  }
  future::plan(strategy)
}

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
## oversubscription. A figure that fails to render warns with its file name, and the others are
## still rendered. Returns the written file paths.
.renderTasks <- function(sim, tasks) {
  tasks <- Filter(function(tk) !is.null(tk) && !is.null(tk[["file"]]), tasks)
  if (!length(tasks)) {
    return(character(0))
  }

  render_one <- function(task) {
    data.table::setDTthreads(1L)
    tryCatch(
      {
        gg <- switch(
          task[["plotter"]],
          ## the NRV years shaded over the envelope (nrvPeriod from .nrvPeriod(sim), set per task)
          envelope = .envelopePlot(task),
          byclass = nrvtools::plot_by_class(
            task[["df"]], type = task[["type"]], page = task[["page"]], cc = task[["cc"]],
            value_col = "value", facet = "poly", ncol = task[["ncol"]], nrow = task[["nrow"]],
            scales = "free_y", xlab = task[["xlab"]], ylab = task[["ylab"]],
            title = task[["title"]], caption = task[["caption"]]
          ),
          leading = nrvtools::plot_leading_boxplot(
            task[["df"]], cc = task[["cc"]], ageClasses = task[["ageClasses"]],
            title = task[["title"]], caption = task[["caption"]]
          ),
          leadingShare = nrvtools::plot_leading_share(
            task[["df"]], cc = task[["cc"]], ageClasses = task[["ageClasses"]],
            species_labels = task[["species_labels"]], title = task[["title"]],
            caption = task[["caption"]]
          ),
          histogram = nrvtools::plot_largepatch_histogram(
            task[["df"]], cc = task[["cc"]], ageClasses = task[["ageClasses"]],
            xlab = task[["xlab"]], title = task[["title"]]
          ),
          NULL
        )
        if (!is.null(gg) && task[["plotter"]] %in% c("envelope", "byclass")) {
          ## one strip size on every envelope and per-class figure; captions read from the left
          gg <- gg +
            ggplot2::theme(
              strip.text = ggplot2::element_text(size = 11),
              strip.text.x = ggplot2::element_text(size = 11),
              plot.caption = ggplot2::element_text(hjust = 0),
              plot.caption.position = "plot"
            )
        }
        if (is.null(gg)) {
          NA_character_
        } else {
          ggplot2::ggsave(task[["file"]], gg, width = task[["width"]], height = task[["height"]])
          task[["file"]]
        }
      },
      error = function(e) {
        warning("NRV_summary: could not render ", task[["file"]], ": ", conditionMessage(e),
                call. = FALSE)
        NA_character_
      }
    )
  }
  ## Detach render_one from this frame: a closure carries its enclosing environment, so left as-is
  ## `future` would serialize the entire (multi-hundred-MB) `tasks` list *with the function* to every
  ## worker. The body only calls namespaced / base functions, so a fresh env under globalenv()
  ## resolves everything; each task's data is shipped on its own as the mapped argument. (globalenv,
  ## not baseenv -- the latter trips future's "cycles in parent chains" during serialization.)
  environment(render_one) <- new.env(parent = globalenv())
  ## the module helpers render_one uses, detached the same way, in render_one's own environment
  ## so that they find each other
  for (helper in c(".envelopePlot", ".addNrvShading", ".addReplicateLines", ".replicateLayers")) {
    fn <- get(helper)
    environment(fn) <- environment(render_one)
    assign(helper, fn, envir = environment(render_one))
  }

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
  ## parallel via .renderTasks(). Envelope figures (lm/pm/sspm) -> figures/<kind>/<layer>/..., each
  ## with the current condition drawn over it; lm and pm add pages comparing a layer's subregions
  ## metric by metric -> figures/<kind>/<layer>/per-metric/... (lm: envelopes; pm: per-class box and
  ## violin plots). The LandWeb summaries (lw) are per-species boxplots / histograms ->
  ## figures/{boxplots,histograms}/...
  saName <- P(sim)$.studyAreaName
  if (is.null(saName) || is.na(saName)) saName <- ""
  saPrefix <- if (nzchar(saName)) paste0(saName, " — ") else ""

  events <- tolower(P(sim)$postprocessEvents)
  tasks <- list()
  nrvPeriod <- .nrvPeriod(sim) ## shaded on the envelope figures

  ## y titles name each metric and its unit; vegetation types are shown by their display names
  if ("lm" %in% events) {
    for (p in mod$rptPolyNames) {
      tasks <- c(
        tasks,
        .envelopeFigTasks(sim, "lm", p, nrvPeriod = nrvPeriod, repLines = TRUE),
        .envelopeFigTasks(sim, "lm", p, layout = "metric", subdir = "per-metric",
                          titlePrefix = paste0(p, " — "), minSubregions = 2L, nrvPeriod = nrvPeriod,
                          repLines = TRUE)
      )

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
      tasks <- c(
        tasks,
        .envelopeFigTasks(sim, "pm", p, classLabels = .vegTypeLabels, nrvPeriod = nrvPeriod,
                          repLines = TRUE),
        .byClassFigTasks(sim, "pm", p, xlab = "Vegetation type",
                         titlePrefix = paste0(p, " — "), classLabels = .vegTypeLabels)
      )
    }
  }
  if ("lw" %in% events) {
    for (p in mod$rptPolyNames) {
      tasks <- c(tasks, .saveLandWebFigTasks(sim, p))
    }
  }
  if ("bc" %in% events) {
    ## the seral envelopes pool every patch of every replicate (SeralTable sums them), which the
    ## replicate captions would misdescribe
    for (p in mod$rptPolyNames) {
      tasks <- c(tasks, .envelopeFigTasks(sim, "sspm", p, ylab = "seral patch area (ha)",
                                          layout = "metric", titlePrefix = saPrefix,
                                          captions = FALSE, nrvPeriod = nrvPeriod))
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
  sam_mdn = "Median stand age", ## patchAges(): the median stand age of each patch
  ## the annual landscape series (.annualSeriesRow())
  propYoung = "Proportion of forest young", propOld = "Proportion of forest old",
  meanStandAge = "Mean stand age", totalBiomassTg = "Total biomass (Tg)"
)

## the full name of each metric code; a code without a name is returned as it is
.metricLabel <- function(metric) {
  metric <- as.character(metric)
  label <- unname(.metricNames[metric])
  ifelse(is.na(label), metric, label)
}

## ---- current condition on the figures ---------------------------------------------------------
## where the current condition falls against the NRV range (.nrvComparison()'s `position`): its colour and legend
## label, on every figure that colours the current condition
.positionColour <- c(inside = "#1b9e77", below = "#2166ac", above = "#7b3294")
.positionLabels <- c(inside = "inside the NRV range", below = "below the NRV range", above = "above the NRV range")

## Add the current-condition value to an envelope figure from `plot_nrv_envelope()` as a dashed red
## horizontal line labelled "current condition", in the panel it belongs to. `cc` has the facet
## columns of `facet` and `mean` (the current-condition value, a single snapshot). The panel a row
## belongs to is read from the plot's own `.panel` column, so the labels cannot drift from nrvtools'.

## The NRV years: the last `nrvWindow` of the summary period (a subset of it by construction)
.nrvPeriod <- function(sim) .lastFraction(P(sim)$summaryPeriod, P(sim)$nrvWindow)

## The last `fraction` of `period` (the summary period), as c(from, to)
.lastFraction <- function(period, fraction) {
  sp <- range(period)
  c(sp[2L] - fraction * diff(sp), sp[2L])
}

## The envelope figure of one task (see .envelopeFigTasks()), the NRV years shaded behind it: nrvtools'
## panels, scales and current-condition line, with its band replaced by the replicates' lines when the task
## carries their values (`reps`).
.envelopePlot <- function(task) {
  gg <- nrvtools::plot_nrv_envelope(
    task[["df"]], type = task[["type"]], facet = task[["facet"]],
    ylab = task[["ylab"]], title = task[["title"]], ncol = task[["ncol"]],
    nrow = task[["nrow"]], page = task[["page"]], cc = task[["cc"]],
    xlab = task[["xlab"]], caption = task[["caption"]]
  )
  if (!is.null(gg) && !is.null(task[["reps"]])) {
    gg <- .addReplicateLines(gg, task[["reps"]])
  }
  .addNrvShading(gg, task[["nrvPeriod"]])
}

## Replace the band and mean line of a `plot_nrv_envelope(type = "ribbon")` figure with each replicate as a thin
## grey line and the median over the replicates bold (`.replicateLayers()`), in the panels of the plot. `reps`
## has `replicate`, `time`, `value` and the panel columns (poly, class, metric, metric.1) of the plot's data,
## whose `median` column is the bold line.
.addReplicateLines <- function(gg, reps) {
  keys <- intersect(c("poly", "class", "metric", "metric.1"), intersect(names(reps), names(gg$data)))
  panels <- unique(as.data.frame(gg$data)[, c(keys, ".panel")])
  series <- merge(reps, panels, by = keys)
  med <- as.data.frame(gg$data)[, c("time", ".panel")]
  med$value <- gg$data$median
  isBand <- vapply(gg$layers, function(l) inherits(l$geom, c("GeomRibbon", "GeomLine")), logical(1))
  gg$layers <- c(
    .replicateLayers(series, med, ggplot2::aes(time, value, group = replicate),
                     repColour = "grey70", medColour = "black"),
    gg$layers[!isBand]
  )
  gg
}

## Shade the NRV years `period` on an envelope figure from `plot_nrv_envelope()`, behind the data. The
## boxplot figure has a discrete time axis (one box per time), the ribbon figure a continuous one. The shading is
## added to the figure's caption.
.addNrvShading <- function(gg, period) {
  if (is.null(gg) || is.null(period) || !"time" %in% names(gg$data)) {
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
  ## added to the figure's caption, which says what its lines and marks show
  caption <- gg$labels$caption
  gg + ggplot2::labs(caption = if (is.null(caption)) "shaded: NRV years" else
    paste0(sub("\\.$", "", caption), "; shaded: NRV years."))
}

## The legend name of the tick at `mid` on the current-condition figures
.nrvMidLabel <- "NRV median"

## The NRV range of each poly x metric: smallest min, largest max and median of the mean, over the
## times of `period` (the NRV years). `env` has poly, metric, time, mean, min and max.
.nrvRange <- function(env, period) {
  env <- env[env$time >= min(period) & env$time <= max(period), , drop = FALSE]
  byMetric <- split(env, paste(env$poly, env$metric, sep = "\r"))
  do.call(rbind, lapply(byMetric, function(e) {
    data.frame(poly = e$poly[1L], metric = e$metric[1L], lo = min(e$min), hi = max(e$max), mid = stats::median(e$mean))
  }))
}

## The current condition against the NRV, one row per poly x metric: the NRV range (lo, hi) and mean (mid)
## of `.nrvRange()`, the current condition (`current`, the mean of `cc`) and where it falls: "inside",
## "above" or "below" the range. `env` and `cc` as for `.nrvRange()` (cc: poly, metric, mean).
.nrvComparison <- function(env, cc, period) {
  nrv <- .nrvRange(env, period)
  nrv <- merge(nrv, stats::setNames(cc[c("poly", "metric", "mean")], c("poly", "metric", "current")),
               by = c("poly", "metric"))
  tol <- 1e-9 * pmax(1, abs(nrv$lo), abs(nrv$hi)) ## a value equal to an end is inside
  nrv$position <- ifelse(nrv$current < nrv$lo - tol, "below", ifelse(nrv$current > nrv$hi + tol, "above", "inside"))
  nrv$tested <- .nrvTested(nrv)
  nrv
}

## Whether each row of comparisons is a test of the current condition: a leading type that is 0 in the current condition
## and in the NRV (it leads nowhere) is not. The one definition of the rule, for the figure, nrvInside.csv and readers.
.nrvTested <- function(cmp) !(grepl("^lead_", cmp$metric) & cmp$current == 0 & cmp$hi == 0)

## Per polygon, the tests (`tested` rows of every group) of `cmp` (poly, position, tested) and how many fall inside the
## NRV range: poly, nTests, nInside, pctInside (100 * nInside / nTests).
.nrvInside <- function(cmp) {
  cmp <- cmp[cmp$tested, , drop = FALSE]
  polys <- unique(cmp$poly)
  out <- data.frame(poly = polys,
                    nTests = vapply(polys, function(p) sum(cmp$poly == p), integer(1), USE.NAMES = FALSE),
                    nInside = vapply(polys, function(p) sum(cmp$poly == p & cmp$position == "inside"), integer(1),
                                     USE.NAMES = FALSE))
  out$pctInside <- 100 * out$nInside / out$nTests
  out
}

## Write `.nrvInside()` of `cmp` to `dir`/nrvInside.csv; returns the file.
.writeNrvInside <- function(cmp, dir) {
  f <- file.path(dir, "nrvInside.csv")
  utils::write.csv(.nrvInside(cmp), f, row.names = FALSE)
  f
}

## Write `.nrvComparison()` of one analysis `kind` and reporting `layer` to csv/<kind>/<layer>/<kind>_nrvComparison.csv
.writeNrvComparisonCSV <- function(sim, env, cc, kind, layer) {
  if (is.null(env) || !nrow(env) || is.null(cc) || !nrow(cc)) {
    return(invisible())
  }
  f <- file.path(.ppCsvDir(sim, kind, layer), paste0(kind, "_nrvComparison.csv"))
  cmp <- .nrvComparison(env, cc, .nrvPeriod(sim))
  utils::write.csv(cmp, f, row.names = FALSE)
  .recordComparison(kind, cmp, layer)
  mod$ppFiles <- c(mod$ppFiles, f)
  invisible()
}

## Keep the comparison of one analysis `kind` and reporting `layer` for the figure of every group
## (`currentConditionAll()`), with its group and the metric's label (a `label` column, else `.metricLabel()`).
.recordComparison <- function(kind, cmp, layer = "") {
  cmp$group <- unname(.ccAllGroups[kind])
  cmp$order <- NULL ## the figure orders its own rows (.currentConditionAllData()); only st has the column
  if (is.null(cmp$label)) cmp$label <- .metricLabel(cmp$metric)
  mod$nrvComparisons[[paste(kind, layer)]] <- cmp
  invisible()
}

## Where the current condition falls within the NRV, one facet per metric on its real scale.
## `data` = list(env =, cc =, period =): the envelope over the summary times (min, max, mean per time), the
## current-condition snapshot (mean) and the NRV years. The grey bar is the NRV range (smallest min to
## largest max over the NRV years), the black tick the NRV median, the dot the current condition, coloured by
## its position: inside, below or above the range (`.positionColour`). `data$labels` (default `.metricLabel`)
## names the metrics.
.currentConditionOverview <- function(data) {
  nrv <- .nrvComparison(data$env, data$cc, data$period)
  labels <- if (is.null(data$labels)) .metricLabel else data$labels
  nrv$panel <- paste0(if (length(unique(nrv$poly)) > 1L) paste0(nrv$poly, ": ") else "", labels(nrv$metric))
  ggplot2::ggplot(nrv) +
    ggplot2::geom_segment(ggplot2::aes(x = lo, xend = hi, y = 0, yend = 0), colour = "grey75", linewidth = 4) +
    ggplot2::geom_point(ggplot2::aes(x = mid, y = 0, shape = .nrvMidLabel), size = 3) +
    ggplot2::geom_point(ggplot2::aes(x = current, y = 0, colour = position), size = 3) +
    ggplot2::scale_colour_manual(values = .positionColour, breaks = names(.positionColour),
                                 labels = unname(.positionLabels), drop = FALSE, name = "current condition") +
    ggplot2::scale_shape_manual(values = stats::setNames(124, .nrvMidLabel), name = NULL) +
    ggplot2::facet_wrap(~panel, scales = "free_x", labeller = ggplot2::label_wrap_gen(30)) +
    ggplot2::labs(x = "metric value (grey bar: NRV range over the NRV years)", y = NULL,
                  title = "Current condition relative to the NRV") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom", axis.text.y = ggplot2::element_blank(),
                   axis.ticks.y = ggplot2::element_blank(), panel.grid.major.y = ggplot2::element_blank(),
                   panel.grid.minor.y = ggplot2::element_blank())
}

## ---- every metric of every group on one figure ----------------------------------------------------------
## The groups that write an nrvComparison table, by analysis kind: lm (landscape metrics) and st (stand-level
## measures). pm and the other kinds have none, so they are not on the figure.
.ccAllGroups <- c(lm = "landscape", st = "stand")
.ccAllTitles <- c(landscape = "Landscape metrics", stand = "Stand-level measures")
.ccAllXlab <- "position relative to the natural range (0 = lowest, 1 = highest simulated value)"
.ccAllLimits <- c(-1, 2) ## a point further out than one range width beyond an end is drawn at the limit

## `x` on the scale where the NRV range [lo, hi] is 0 to 1. A range of one value (hi == lo) is given a width of
## 1% of the value (at least 0.01) centred on it.
.nrvScale <- function(x, lo, hi) {
  width <- hi - lo
  point <- width == 0
  width <- ifelse(point, 0.01 * pmax(abs(hi), 1), width)
  lo <- ifelse(point, lo - width / 2, lo)
  (x - lo) / width
}

## Order of the stand-level rows: biomass, the age classes young to old (`.ccAllAgeOrder`; others after, by name),
## the forested share, then the leading types. Landscape rows have one rank, so they keep their order.
.ccAllAgeOrder <- c("Young", "Immature", "Mature", "Old")
.standRank <- function(metric, group) {
  age <- match(sub("^age_", "", metric), .ccAllAgeOrder, nomatch = length(.ccAllAgeOrder) + 1L)
  ifelse(group != "stand", 0, ifelse(metric == "biomassTg", 1, ifelse(grepl("^age_", metric), 2 + age / 10,
         ifelse(metric == "forested", 3, 4))))
}

## The position of each stand-level row (`metric`, `label`) in the order above, ties by label: 1, 2, ... (the `order`
## column of st_nrvComparison.csv; the figure sorts by it).
.standOrder <- function(metric, label) order(order(.standRank(metric, rep("stand", length(metric))), label))

## The rows of the figure from the recorded comparisons (`poly`, `metric`, `group`, `label`, `lo`, `hi`, `mid`,
## `current`, `position`): a leading type that is 0 in the current condition and in the NRV is dropped; the NRV
## mid and the current condition are rescaled (xMid, xCurrent); the current condition is drawn at xPlot, clipped
## to `.ccAllLimits` (clipped = TRUE); y is the row, from the top, with a row above each group for its title.
.currentConditionAllData <- function(cmp) {
  cmp <- cmp[.nrvTested(cmp), , drop = FALSE]
  cmp$group <- factor(cmp$group, names(.ccAllTitles))
  stand <- cmp$group == "stand"
  rank <- integer(nrow(cmp)) ## landscape rows keep their order
  rank[stand] <- .standOrder(cmp$metric[stand], cmp$label[stand])
  cmp <- cmp[order(cmp$group, rank), , drop = FALSE]
  cmp$xMid <- .nrvScale(cmp$mid, cmp$lo, cmp$hi)
  cmp$xCurrent <- .nrvScale(cmp$current, cmp$lo, cmp$hi)
  cmp$xPlot <- pmin(pmax(cmp$xCurrent, .ccAllLimits[1]), .ccAllLimits[2])
  cmp$clipped <- cmp$xPlot != cmp$xCurrent
  cmp$group <- as.character(cmp$group)
  newGroup <- !duplicated(cmp$group)
  cmp$y <- -(seq_len(nrow(cmp)) + cumsum(newGroup))
  attr(cmp, "titles") <- data.frame(group = cmp$group[newGroup], y = cmp$y[newGroup] + 1,
                                    title = unname(.ccAllTitles[cmp$group[newGroup]]))
  cmp
}

## One panel, a row per metric: the grey bar is the NRV range (0 to 1), the black tick the NRV median, the dot the
## current condition, coloured by its position. A current condition clipped at the limit has an arrow and its
## value written beside it.
.currentConditionAll <- function(data) {
  titles <- attr(data, "titles")
  clip <- data[data$clipped, , drop = FALSE]
  dir <- sign(clip$xCurrent)
  ggplot2::ggplot(data) +
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = 1, y = y, yend = y), colour = "grey75", linewidth = 3) +
    ggplot2::geom_point(ggplot2::aes(x = xMid, y = y, shape = .nrvMidLabel), size = 3) +
    ggplot2::geom_point(ggplot2::aes(x = xPlot, y = y, colour = position), size = 2.5) +
    ggplot2::geom_segment(data = clip, ggplot2::aes(x = xPlot - dir * 0.12, xend = xPlot, y = y, yend = y, colour = position),
                          arrow = grid::arrow(length = grid::unit(0.08, "in")), show.legend = FALSE) +
    ggplot2::geom_text(data = clip, ggplot2::aes(x = xPlot - dir * 0.16, y = y, label = signif(current, 3), colour = position),
                       hjust = ifelse(dir > 0, 1, 0), size = 2.6, show.legend = FALSE) +
    ggplot2::geom_text(data = titles, ggplot2::aes(x = .ccAllLimits[1], y = y, label = title), hjust = 0,
                       fontface = "bold", size = 3.2) +
    ggplot2::geom_vline(xintercept = c(0, 1), linetype = "dotted", colour = "grey60") +
    ggplot2::scale_y_continuous(breaks = data$y, labels = data$label, expand = ggplot2::expansion(add = 0.8)) +
    ggplot2::scale_x_continuous(breaks = seq(.ccAllLimits[1], .ccAllLimits[2], 0.5),
                                limits = .ccAllLimits + c(-0.1, 0.1)) +
    ggplot2::scale_colour_manual(values = .positionColour, breaks = names(.positionColour),
                                 labels = unname(.positionLabels), drop = FALSE, name = "current condition") +
    ggplot2::scale_shape_manual(values = stats::setNames(124, .nrvMidLabel), name = NULL) +
    ggplot2::labs(x = .ccAllXlab, y = NULL, title = "Current condition relative to the NRV") +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(legend.position = "bottom", panel.grid.major.y = ggplot2::element_blank(),
                   panel.grid.minor = ggplot2::element_blank())
}

## figures/all/<name>.png: `current_condition_all`, with the polygon's name appended when there are several
## polygons (characters that are not letters, digits, . or - become _)
.ccAllName <- function(poly, nPoly) {
  if (nPoly > 1L) paste0("current_condition_all_", gsub("[^A-Za-z0-9.-]+", "_", poly)) else "current_condition_all"
}

## The `postprocess_cc` event: one figure per reporting polygon with every group's NRV comparison recorded by the
## lm and st events (`.recordComparison()`), written to postprocess/figures/all/ and registered as outputs.
currentConditionAll <- function(sim) {
  cmp <- do.call(rbind, mod$nrvComparisons)
  if (is.null(cmp) || !nrow(cmp)) {
    message("NRV_summary: no NRV comparisons for the combined current-condition figure")
    return(invisible(sim))
  }
  polys <- unique(cmp$poly)
  sim <- registerOutputs(.writeNrvInside(cmp, reproducible::checkPath(file.path(.ppRoot(sim), "csv", "all"), create = TRUE)), sim)
  types <- P(sim)$.plots
  dir <- reproducible::checkPath(file.path(.ppRoot(sim), "figures", "all"), create = TRUE)
  for (p in polys) {
    d <- .currentConditionAllData(cmp[cmp$poly == p, , drop = FALSE])
    name <- .ccAllName(p, length(polys))
    Plots(data = d, fn = .currentConditionAll, filename = name, path = dir, types = types,
          ggsaveArgs = list(width = 11, height = 2 + 0.25 * nrow(d), units = "in"))
    f <- file.path(dir, paste0(name, ".png"))
    if (file.exists(f)) sim <- registerOutputs(f, sim)
  }
  invisible(sim)
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

## The per-block fire table burnSummaries writes (burnSummaries_fireBlocks.csv: rep, block, nFires, areaBurnedHa;
## blocks with no fire are 0), among the registered output `files`; NULL when it did not run. It is built from
## the fire sizes every fire model writes, so the area burned is there for LandMine and scfm as well as fireSense.
.burnBlocksFile <- function(files) {
  f <- files[basename(files) == "burnSummaries_fireBlocks.csv"]
  if (length(f)) f[length(f)]
}

## The stability series of the area burned per block, from that table: rep, time (the block's first year), value.
.burnSeries <- function(file) {
  b <- data.table::fread(file)
  data.frame(rep = b$rep, time = b$block, value = b$areaBurnedHa)
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
  ## the stand-level series (the `st` event)
  st <- if ("st" %in% events && !is.null(mod$standSeries)) {
    d <- mod$standSeries
    data.frame(kind = "st", layer = P(sim)$.studyAreaName, poly = P(sim)$.studyAreaName, level = "landscape",
               class = NA_character_, metric = d$metric, rep = d$rep, time = d$time, value = d$value)
  }
  fb <- .burnBlocksFile(outputs(sim)$file)
  burn <- if (!is.null(fb)) {
    b <- .burnSeries(fb)
    data.frame(kind = "burn", layer = P(sim)$.studyAreaName, poly = P(sim)$.studyAreaName,
               level = "landscape", class = NA_character_, metric = "areaBurnedHa per block",
               rep = b$rep, time = b$time, value = b$value)
  }
  do.call(rbind, c(unlist(one, recursive = FALSE), list(st, burn)))
}

.stabilityKeys <- c("kind", "layer", "poly", "level", "class", "metric")

## the window the check looks at: the last `stabilityWindow` of the summary period
.stabilityWindow <- function(sim) .lastFraction(P(sim)$summaryPeriod, P(sim)$stabilityWindow)

## Panels of each series over time (reps as thin lines, median in bold), the window shaded, and the
## verdict in each panel title; `page` of `nPages` panels sets.
.stabilityPanels <- function(data, window, page = 1L, ncol = 4L, nrow = 3L) {
  d <- data$series
  d$panel <- paste0(ifelse(is.na(d$class), "", paste0(d$class, " ")), .metricLabel(d$metric), "\n", d$layer, "/", d$poly, ": ",
                    data$flag[match(do.call(paste, d[.stabilityKeys]), data$id)])
  ggplot2::ggplot(d, ggplot2::aes(time, value)) +
    ggplot2::annotate("rect", xmin = window[1L], xmax = window[2L], ymin = -Inf, ymax = Inf,
                      alpha = 0.15, fill = "orange") +
    ggplot2::geom_line(ggplot2::aes(group = rep), colour = "grey60", linewidth = 0.3) +
    ggplot2::stat_summary(fun = stats::median, geom = "line", linewidth = 0.8) +
    ggforce::facet_wrap_paginate(~panel, ncol = ncol, nrow = nrow, page = page, scales = "free_y") +
    ggplot2::labs(x = "time", y = NULL, caption = "shaded: stability window; thin lines: reps; bold: median") +
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
    nPages <- .nPages(nrow(rk))
    for (pg in seq_len(nPages)) {
      ## the canvas holds the panels of this page: a last page with few panels is not a full page
      lay <- .pageLayout(nrow(rk), pg)
      Plots(
        data = list(series = sk, flag = rk$flag, id = do.call(paste, rk[.stabilityKeys])),
        fn = .stabilityPanels, window = window, page = pg, ncol = lay$ncol, nrow = lay$nrow,
        filename = paste0("stability_", k, "_p", pg), path = figDir,
        types = P(sim)$.plots, ggsaveArgs = list(width = lay$width, height = lay$height, units = "in")
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

## ---- stand-level measures (the `st` event) ------------------------------------------------------------
## At each summary time of each rep, and for the current condition, over the reporting area
## (`studyAreaReporting`): the share of the forested area in each age class (`ageClasses`, `ageClassCutOffs`;
## the saved standAgeMap), the forested share of the area, the share of the forested area led by each vegetation
## type (the saved vegTypeMap) and the total tree biomass (Tg; the saved cohortData and pixelGroupMap).
## A pixel is forested when it has a stand age and a pixel group above 0. Read from the snapshots the
## lm/pm events read, so the current condition is the same year-0 state (urban removed when
## `LandTypeCC_reporting` is supplied).

## One snapshot, from the values of the reporting-area pixels: `sam` stand age, `vtmCode` vegetation type code,
## `pgm` pixel group; `cohortData` (B in g/m2) and the pixel area in ha. Returns metric, value: age_<class>
## (% of forested), forested (% of the area), biomassTg, lead_<code> (% of the forested pixels, as the annual series).
.standRow <- function(sam, vtmCode, pgm, cohortData, pixelHa, ageClassCutOffs, ageClasses) {
  forest <- !is.na(sam) & !is.na(pgm) & pgm > 0
  ac <- cut(sam[forest], c(ageClassCutOffs, Inf), right = FALSE, labels = ageClasses)
  bPG <- rowsum(as.numeric(cohortData$B), cohortData$pixelGroup)
  B <- bPG[match(pgm, as.integer(rownames(bPG)))]
  lead <- table(vtmCode[!is.na(vtmCode)])
  data.frame(
    metric = c(paste0("age_", ageClasses), "forested", "biomassTg", paste0("lead_", names(lead))),
    value = c(100 * as.numeric(table(ac)) / max(1, sum(forest)), 100 * mean(forest),
              sum(B, na.rm = TRUE) * 0.01 * pixelHa / 1e6, ## as .annualSeriesRow()
              100 * as.numeric(lead) / max(1, sum(forest)))
  )
}

## The vegetation type code of each pixel of a saved vegTypeMap (its levels: ID, code)
.vtmCodes <- function(vtm) {
  lv <- terra::levels(vtm)[[1]]
  lv[[2]][match(terra::values(vtm, mat = FALSE), lv[[1]])]
}

## The snapshot files of each rep and time, one row each: rep (the rep folder), time, sam, vtm, pgm, cd.
.snapshotTable <- function(sam, vtm, pgm, cd) {
  key <- function(f, col) {
    d <- data.frame(rep = basename(dirname(f)), time = as.numeric(sub("^.*_year([0-9.]+)\\.[^.]*$", "\\1", basename(f))), f)
    names(d)[3] <- col
    d
  }
  Reduce(function(a, b) merge(a, b, by = c("rep", "time")),
         list(key(sam, "sam"), key(vtm, "vtm"), key(pgm, "pgm"), key(cd, "cd")))
}

## A vegetation type absent from a snapshot leads 0% of it: every metric of `rows` (rep, time, metric, value)
## at every rep x time, 0 where missing; `metrics` adds metrics found elsewhere (e.g. only in the current condition).
.fillAbsentMetrics <- function(rows, metrics = character(0)) {
  grid <- expand.grid(rep = unique(rows$rep), time = unique(rows$time), metric = union(unique(rows$metric), metrics),
                      stringsAsFactors = FALSE)
  out <- merge(grid, rows, by = c("rep", "time", "metric"), all.x = TRUE)
  out$value[is.na(out$value)] <- 0
  out[order(out$rep, out$time, out$metric), ]
}

.leadingYlab <- "Share of the forested area (%)" ## the y title of the leading-type figures
.standFigSize <- list(width = 9, height = 5, units = "in") ## the size of a stand-level figure

## The class a stand-level metric is about, for a legend where the axis says what is measured: the age class,
## the leading type (by `sppEquiv`'s EN_generic_full when it has one), or the measure itself.
.standClass <- function(metric, sppEquiv = NULL, sppEquivCol = "LandR") {
  code <- sub("^lead_", "", metric)
  sp <- if (!is.null(sppEquiv) && "EN_generic_full" %in% names(sppEquiv)) {
    sppEquiv[["EN_generic_full"]][match(code, sppEquiv[[sppEquivCol]])]
  } else rep(NA_character_, length(code))
  sp <- ifelse(is.na(sp), .vegTypeLabels(code), sp)
  ifelse(metric == "biomassTg", "Total tree biomass",
  ifelse(metric == "forested", "Forested",
  ifelse(grepl("^age_", metric), sub("^age_", "", metric), sp)))
}

## Readable names of the stand-level metrics (the CSV labels): `.standClass()` with what is measured
.standLabel <- function(metric, sppEquiv = NULL, sppEquivCol = "LandR") {
  cls <- .standClass(metric, sppEquiv, sppEquivCol)
  ifelse(metric == "biomassTg", "Total tree biomass (Tg)",
  ifelse(metric == "forested", "Forested share of the area (%)",
  ifelse(grepl("^age_", metric), paste0(cls, " forest, share of forested area (%)"),
         paste0(cls, " leading, share of forested area (%)"))))
}

## The layers that draw replicates: each a thin line (`series`, `mapping` naming its group), the median over
## them bold (`med`). A colour, if given, is fixed (`repColour`, `medColour`); otherwise the plot's own mapping
## colours both.
.replicateLayers <- function(series, med, mapping, repColour = NULL, medColour = NULL) {
  list(
    do.call(ggplot2::geom_line, c(list(data = series, mapping = mapping, alpha = 0.35, linewidth = 0.3),
                                  if (!is.null(repColour)) list(colour = repColour))),
    do.call(ggplot2::geom_line, c(list(data = med, mapping = ggplot2::aes(time, value), linewidth = 1),
                                  if (!is.null(medColour)) list(colour = medColour)))
  )
}

## One stand-level figure: each rep a thin line, the median over reps bold, the current condition a circle, the
## NRV years shaded. `data` = list(series = (rep, time, class, value), cc = (time, class, value[, position]),
## period =, title =, ylab =). Classes are coloured and named in a legend on the right (the class only, in as many
## columns as it takes to fit); when `cc` has a `position` the figure is of one class, drawn in black, and the
## circle is filled by its position against the NRV range (`.positionColour`).
.standSeriesPanels <- function(data) {
  d <- data$series
  cc <- data$cc
  nClass <- length(unique(d$class))
  byPosition <- "position" %in% names(cc)
  med <- stats::aggregate(value ~ class + time, d, stats::median)
  gg <- ggplot2::ggplot(d, ggplot2::aes(time, value, colour = class)) +
    ggplot2::annotate("rect", xmin = min(data$period), xmax = max(data$period), ymin = -Inf, ymax = Inf,
                      alpha = 0.15, fill = "orange") +
    .replicateLayers(d, med, ggplot2::aes(group = interaction(class, rep)))
  gg <- if (byPosition) {
    gg +
      ggplot2::scale_colour_manual(values = stats::setNames(rep("black", nClass), unique(d$class)), guide = "none") +
      ggplot2::geom_point(data = cc, ggplot2::aes(time, value, fill = position), inherit.aes = FALSE,
                          shape = 21, colour = "black", size = 3.5, stroke = 1) +
      ggplot2::scale_fill_manual(values = .positionColour, labels = function(b) unname(.positionLabels[b]),
                                 name = "current condition")
  } else {
    gg + ggplot2::geom_point(data = cc, shape = 1, size = 2.5, stroke = 1) +
      ggplot2::guides(colour = ggplot2::guide_legend(ncol = ceiling(nClass / 12)))
  }
  gg +
    ggplot2::labs(x = "Simulation year", y = data$ylab, colour = NULL, title = data$title,
                  caption = "thin lines: replicates; bold: median; circle: current condition; shaded: NRV years") +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(legend.position = if (nClass > 1L || byPosition) "right" else "none")
}

## The data of one figure per leading type (`lead_*` metrics that lead somewhere), for `.standSeriesPanels()`: the
## replicates' series, the current condition with its `position` from `cmp` (.nrvComparison() rows), named by metric.
.speciesFigData <- function(series, ccRows, cmp, period, sa, sppEquiv = NULL, sppEquivCol = "LandR") {
  leadMax <- tapply(series$value, series$metric, max)
  m <- names(leadMax)[grepl("^lead_", names(leadMax)) & leadMax > 0]
  ccRows$position <- cmp$position[match(ccRows$metric, cmp$metric)]
  stats::setNames(lapply(m, function(x) {
    list(series = series[series$metric == x, , drop = FALSE], cc = ccRows[ccRows$metric == x, , drop = FALSE],
         period = period, ylab = .leadingYlab,
         title = paste(sa, "-", .standClass(x, sppEquiv, sppEquivCol), "leading"))
  }), m)
}

standMetrics <- function(sim) {
  sa <- P(sim)$.studyAreaName
  pad <- padYears(P(sim)$simTimes)
  snaps <- .snapshotTable(mod$sam, mod$vtm, mod$pgm, mod$cd)
  cc <- data.frame(rep = "CC", time = P(sim)$simTimes[1], sam = mod$fsam0, vtm = mod$fvtm0,
                   pgm = file.path(mod$rep1Dir, paste0("pixelGroupMap_year", pad$start, ".tif")),
                   cd = file.path(mod$rep1Dir, paste0("cohortData_year", pad$start, ".qs2")))
  cells <- NULL
  one <- function(f) {
    pgm <- terra::rast(f$pgm)
    if (is.null(cells)) cells <<- which(.reportingCells(pgm, sim$studyAreaReporting))
    row <- .standRow(terra::values(terra::rast(f$sam), mat = FALSE)[cells], .vtmCodes(terra::rast(f$vtm))[cells],
                     terra::values(pgm, mat = FALSE)[cells], qs2::qs_read(f$cd), prod(terra::res(pgm)) / 1e4,
                     P(sim)$ageClassCutOffs, P(sim)$ageClasses)
    data.frame(rep = f$rep, time = f$time, row)
  }
  series <- do.call(rbind, lapply(split(snaps, seq_len(nrow(snaps))), one))
  ccRows <- one(cc)
  series <- .fillAbsentMetrics(series, ccRows$metric)
  series$rep <- as.integer(sub("^\\D*", "", series$rep))
  ccRows <- .fillAbsentMetrics(ccRows, series$metric)
  series$label <- .standLabel(series$metric, sim$sppEquiv, P(sim)$sppEquivCol)
  ccRows$label <- .standLabel(ccRows$metric, sim$sppEquiv, P(sim)$sppEquivCol)
  series$class <- .standClass(series$metric, sim$sppEquiv, P(sim)$sppEquivCol)
  ccRows$class <- .standClass(ccRows$metric, sim$sppEquiv, P(sim)$sppEquivCol)
  mod$standSeries <- series

  env <- stats::aggregate(value ~ metric + time, series, function(v) c(mean = mean(v), min = min(v), max = max(v)))
  env <- data.frame(poly = sa, metric = env$metric, time = env$time, env$value)
  cmp <- .nrvComparison(env, data.frame(poly = sa, metric = ccRows$metric, mean = ccRows$value), .nrvPeriod(sim))
  cmp$label <- .standLabel(cmp$metric, sim$sppEquiv, P(sim)$sppEquivCol)
  cmp$order <- .standOrder(cmp$metric, cmp$label)
  .recordComparison("st", cmp, sa)

  d <- .ppCsvDir(sim, "st", sa)
  fs <- file.path(d, c("st.csv", "st_CC.csv", "st_nrvComparison.csv"))
  utils::write.csv(series[names(series) != "class"], fs[1], row.names = FALSE)
  utils::write.csv(ccRows[, c("metric", "label", "value")], fs[2], row.names = FALSE)
  utils::write.csv(cmp, fs[3], row.names = FALSE)
  mod$ppFiles <- c(mod$ppFiles, fs)

  ## figures: age classes, leading types (those leading at least 0.5% of the forested area in some snapshot), biomass
  leadMax <- tapply(series$value, series$metric, max)
  groups <- list(
    age = list(m = paste0("age_", P(sim)$ageClasses), ylab = "Share of forested area (%)", what = "forest age classes"),
    leading = list(m = names(leadMax)[grepl("^lead_", names(leadMax)) & leadMax >= 0.5],
                   ylab = .leadingYlab, what = "leading tree type"),
    biomass = list(m = "biomassTg", ylab = "Total tree biomass (Tg)", what = "tree biomass")
  )
  for (g in names(groups)) {
    m <- groups[[g]]$m
    Plots(
      data = list(series = series[series$metric %in% m, ], cc = ccRows[ccRows$metric %in% m, ],
                  period = .nrvPeriod(sim), title = paste(sa, "-", groups[[g]]$what), ylab = groups[[g]]$ylab),
      fn = .standSeriesPanels, filename = paste0("stand_", g), path = .ppFigDir(sim, "st", sa),
      types = P(sim)$.plots, ggsaveArgs = .standFigSize
    )
  }

  ## one figure per leading type (the mixed class too): figures/st/<studyArea>/species/lead_<code>.png
  spp <- .speciesFigData(series, ccRows, cmp, .nrvPeriod(sim), sa, sim$sppEquiv, P(sim)$sppEquivCol)
  for (m in names(spp)) {
    Plots(data = spp[[m]], fn = .standSeriesPanels, filename = m, path = .ppFigDir(sim, "st", sa, "species"),
          types = P(sim)$.plots, ggsaveArgs = .standFigSize)
  }

  ## where the current condition falls against the NRV, one panel per stand-level metric
  Plots(
    data = list(env = env, cc = data.frame(poly = sa, metric = ccRows$metric, mean = ccRows$value),
                period = .nrvPeriod(sim), labels = function(m) .standLabel(m, sim$sppEquiv, P(sim)$sppEquivCol)),
    fn = .currentConditionOverview, filename = "current_condition_overview", path = .ppFigDir(sim, "st", sa),
    types = P(sim)$.plots, ggsaveArgs = list(width = 12, height = 10, units = "in")
  )
  invisible(sim)
}

## ---- annual landscape series and their autocorrelation ----------------------------------------------
## The summary snapshots are `summaryInterval` years apart so they are nearly independent samples, as
## thinning does for MCMC. The interval that achieves that is the autocorrelation time of the landscape,
## which maps saved every year would measure at the cost of far too much data. A few landscape scalars
## recorded every year measure it instead.

## The vegetation-type and stand-age maps, as `map_generators` makes them (leading species by
## `vegLeadingProportion` and `mixedType`; stand age weighted by biomass, masked to the reporting area).
.checkSingleInputs <- function(sim) {
  needed <- c("cohortData", "pixelGroupMap", "speciesLayers", "sppColorVect", "sppEquiv", "studyAreaReporting")
  missing <- needed[vapply(needed, function(nm) is.null(sim[[nm]]), logical(1))]
  if (length(missing)) {
    stop("NRV_summary (mode = 'single') needs ", paste(missing, collapse = ", "),
         " in the simList by the first summary event, but not found; they come from the vegetation modules (e.g. Biomass_core).")
  }
  invisible(TRUE)
}

.landscapeMaps <- function(sim) {
  list(
    vegTypeMap = LandR::vegTypeMapGenerator(
      sim$cohortData, sim$pixelGroupMap, P(sim)$vegLeadingProportion,
      mixedType = P(sim)$mixedType, sppEquiv = sim$sppEquiv, sppEquivCol = P(sim)$sppEquivCol,
      colors = sim$sppColorVect, doAssertion = getOption("LandR.assertions", TRUE)
    ),
    standAgeMap = LandR::standAgeMapGenerator(
      sim$cohortData, sim$pixelGroupMap, weight = "biomass",
      doAssertion = getOption("LandR.assertions", TRUE)
    ) |> terra::mask(sim$studyAreaReporting)
  )
}

## The pixels of the reporting area, once: the annual row counts pixel groups within them every year.
.reportingCells <- function(pixelGroupMap, studyAreaReporting) {
  !is.na(terra::values(terra::mask(terra::rast(pixelGroupMap, vals = 1), studyAreaReporting), mat = FALSE))
}

## One row of landscape scalars from `cohortData` and `nPerGroup`, the number of reporting-area pixels in each
## pixel group (`tabulate()` of the pixelGroupMap values; no rasters are made). The forested pixels are those of
## the pixel groups in `cohortData`. Same definitions as the maps of `.landscapeMaps()`: leading species from
## `LandR::leadingByPixelGroup()` (what `vegTypeMapGenerator()` uses), stand age biomass-weighted
## and floored to 10 years as `standAgeMapGenerator()` does. propYoung and propOld: stand age below the first
## positive and at or above the last of the `ageClassCutOffs` (the module's first and last age classes);
## totalBiomassTg: B (g/m2) times pixels times `pixelHa`; lead_<species>: proportion of the forested pixels
## led by each species ("Mixed" included).
.annualSeriesRow <- function(time, cohortData, nPerGroup, pixelHa, ageClassCutOffs,
                             vegLeadingProportion, mixedType, sppEquiv, sppEquivCol) {
  weightN <- function(pg) {
    n <- nPerGroup[pg]
    n[is.na(n)] <- 0
    n
  }
  w <- rowsum(cbind(ageB = cohortData$age * cohortData$B, B = cohortData$B), cohortData$pixelGroup)
  age <- data.frame(pixelGroup = as.integer(rownames(w)), age = floor(w[, "ageB"] / w[, "B"] / 10) * 10)
  lead <- LandR::leadingByPixelGroup(cohortData, vegLeadingProportion, mixedType = mixedType, sppEquiv = sppEquiv,
                                     sppEquivCol = sppEquivCol)
  nAge <- weightN(age$pixelGroup)
  nLead <- weightN(lead$pixelGroup)
  nForest <- sum(nAge)
  byLead <- tapply(nLead, as.character(lead$leading), sum) / sum(nLead)
  cuts <- ageClassCutOffs[ageClassCutOffs > min(ageClassCutOffs)]
  data.frame(
    time = time, propYoung = sum(nAge[age$age < min(cuts)]) / nForest, propOld = sum(nAge[age$age >= max(cuts)]) / nForest,
    meanStandAge = sum(age$age * nAge) / nForest,
    totalBiomassTg = sum(as.numeric(cohortData$B) * weightN(cohortData$pixelGroup)) * 0.01 * pixelHa / 1e6,
    as.list(stats::setNames(as.numeric(byLead), paste0("lead_", names(byLead))))
  )
}

## all years' rows in one table: a species leading in only some years is 0 in the others
.bindAnnualRows <- function(rows) {
  d <- data.table::rbindlist(rows, fill = TRUE)
  for (l in grep("^lead_", names(d), value = TRUE)) data.table::set(d, which(is.na(d[[l]])), l, 0)
  as.data.frame(d)
}

## The files a single-mode run saves at this time (see the save_single event), each registered with
## the name of the object it holds so a replay can load it back as that input.
.saveSingle <- function(sim) {
  padYear <- paddedFloatToChar(time(sim), padL = ceiling(log10(end(sim) + 1)))

  ## objects to save at start of simulation ---------------------------------------------------
  if (time(sim) == start(sim)) {
    f_sppColorVect <- file.path(outputPath(sim), paste0("sppColorVect_year", padYear, ".qs2"))
    qs2::qs_save(sim$sppColorVect, f_sppColorVect)
    sim <- registerOutputs(f_sppColorVect, sim, objectName = "sppColorVect", fun = "qs2::qs_save")

    f_sppEquiv <- file.path(outputPath(sim), paste0("sppEquiv_year", padYear, ".qs2"))
    qs2::qs_save(sim$sppEquiv, f_sppEquiv)
    sim <- registerOutputs(f_sppEquiv, sim, objectName = "sppEquiv", fun = "qs2::qs_save")

    f_speciesLayers <- file.path(outputPath(sim), paste0("speciesLayers_year", padYear, ".tif"))
    terra::writeRaster(sim$speciesLayers, f_speciesLayers, datatype = "INT2U", overwrite = TRUE)
    sim <- registerOutputs(f_speciesLayers, sim, objectName = "speciesLayers", fun = "terra::writeRaster")
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
    sim <- registerOutputs(f_standAgeMap, sim, objectName = "standAgeMap", fun = "terra::writeRaster")

    f_vegTypeMap <- file.path(outputPath(sim), paste0("vegTypeMap_year", padYear, ".tif"))
    terra::writeRaster(mod$vegTypeMap, f_vegTypeMap, datatype = "INT2U", overwrite = TRUE)
    sim <- registerOutputs(f_vegTypeMap, sim, objectName = "vegTypeMap", fun = "terra::writeRaster")
  }

  if (time(sim) %in% times_during) {
    f_cohortData <- file.path(outputPath(sim), paste0("cohortData_year", padYear, ".qs2"))
    qs2::qs_save(sim$cohortData, f_cohortData)
    sim <- registerOutputs(f_cohortData, sim, objectName = "cohortData", fun = "qs2::qs_save")

    f_pixelGroupMap <- file.path(outputPath(sim), paste0("pixelGroupMap_year", padYear, ".tif"))
    terra::writeRaster(sim$pixelGroupMap, f_pixelGroupMap, datatype = "INT4U", overwrite = TRUE)
    sim <- registerOutputs(f_pixelGroupMap, sim, objectName = "pixelGroupMap", fun = "terra::writeRaster")

    nextTime <- time(sim) + P(sim)$summaryInterval
    ## times scheduled by init are not scheduled a second time here
    if (time(sim) >= P(sim)$summaryPeriod[1] && time(sim) < P(sim)$summaryPeriod[2] && !nextTime %in% mod$initTimes) {
      sim <- scheduleEvent(sim, nextTime, "NRV_summary", "save_single", .last())
    }
  }

  ## objects to save at end of simulation -----------------------------------------------------
  if (time(sim) == end(sim)) {
    f_flammableMap <- file.path(outputPath(sim), paste0("flammableMap_year", padYear, ".tif"))
    terra::writeRaster(sim$flammableMap, f_flammableMap, datatype = "INT2U", overwrite = TRUE)
    sim <- registerOutputs(f_flammableMap, sim, objectName = "flammableMap", fun = "terra::writeRaster")
  }
  sim
}

saveAnnualSeries <- function(sim) {
  f <- file.path(outputPath(sim), "annualSeries.csv")
  utils::write.csv(.bindAnnualRows(mod$annualSeries), f, row.names = FALSE)
  registerOutputs(f, sim)
}

## The autocorrelation function of `x` (an annual series) at lags 0 to `maxLag` (NA beyond the series' length); all NA for a constant series.
.acf <- function(x, maxLag) {
  x <- x[is.finite(x)]
  if (length(x) < 3L || stats::sd(x) == 0) return(rep(NA_real_, maxLag + 1L))
  rho <- as.numeric(stats::acf(x, lag.max = min(maxLag, length(x) - 1L), plot = FALSE)$acf)
  c(rho, rep(NA_real_, maxLag + 1L - length(rho)))
}

## The integrated autocorrelation time of an ACF `rho` (lag 0 first): tau = -1 + 2 * the sum of the pair sums
## rho[2k] + rho[2k + 1] (Geyer's initial positive sequence: the sum stops before the first non-positive pair
## sum, and the pair sums are made non-increasing). White noise gives 1, an AR(1) series with coefficient
## phi gives (1 + phi) / (1 - phi).
.autocorrTime <- function(rho) {
  if (anyNA(rho)) return(NA_real_)
  if (length(rho) %% 2L) rho <- c(rho, 0)
  pairs <- cummin(rho[c(TRUE, FALSE)] + rho[c(FALSE, TRUE)])
  n <- which(pairs <= 0)[1L] - 1L
  if (is.na(n)) n <- length(pairs)
  max(1, -1 + 2 * sum(pairs[seq_len(n)]))
}

## The first lag at which the ACF is below `level`; NA if it never is.
.firstLagBelow <- function(rho, level = 0.1) {
  k <- which(rho < level)[1L]
  if (anyNA(rho) || is.na(k)) NA_integer_ else k - 1L
}

## Effective number of independent samples among `n` samples with lag correlation `r` (AR(1)): n (1 - r) / (1 + r),
## r clipped to [0, 1).
.essAR1 <- function(n, r) {
  r <- min(max(r, 0), 0.999)
  n * (1 - r) / (1 + r)
}

## `tables`: per-rep data.frames of the annual series (a `time` column, one column per series); `period`: the NRV
## years c(from, to); `interval`: `summaryInterval`. Per series:
## - `phi`: the lag-1 autocorrelation over the NRV years, the mean of the per-rep lag-1 ACFs (clipped to [0, 0.999]),
##   and the autocorrelation time of the AR(1) decay it fits, `tau` = (1 + phi) / (1 - phi);
## - `ar1Misfit`: the largest absolute difference between the pooled empirical ACF at lags 1 to 50 and phi^lag
##   (near 0 when the decay is exponential, large for e.g. oscillating series);
## - `r`, `rMin`, `rMax`: the ACF at lag `interval`, pooled (mean over reps) and the lowest and highest rep;
## - `effectiveSnapshots`: the snapshots `interval` apart over all reps, times (1 - r) / (1 + r);
## - `tauGeyer`: Geyer's initial positive sequence estimate, for comparison only (noisy for short series);
## - `lagBelow0.1`: first lag of the pooled ACF below 0.1.
## `thin` is ceiling(max tau); `limiting` the series with that tau. `acf` holds the empirical ACF per series, rep and
## "pooled", for lags 0 to the larger of `maxLag`, `interval` and 50, and `fitted` the phi^lag curves.
.autocorrSummary <- function(tables, period, maxLag, interval) {
  series <- setdiff(Reduce(intersect, lapply(tables, names)), "time")
  lagMax <- max(maxLag, interval, 50L)
  acfs <- do.call(rbind, lapply(seq_along(tables), function(i) {
    d <- tables[[i]][tables[[i]]$time >= period[1L] & tables[[i]]$time <= period[2L], , drop = FALSE]
    do.call(rbind, lapply(series, function(s) {
      rho <- .acf(d[[s]], lagMax)
      data.frame(series = s, rep = as.character(i), lag = seq_along(rho) - 1L, acf = rho)
    }))
  }))
  pooled <- stats::aggregate(acf ~ series + lag, acfs, mean, na.action = stats::na.pass)
  pooledAcf <- data.frame(series = pooled$series, rep = "pooled", lag = pooled$lag, acf = pooled$acf)
  acfAt <- function(d, lag) d$acf[d$lag == lag]
  nSnapshots <- floor(diff(range(period)) / interval) + 1
  fit <- do.call(rbind, lapply(series, function(s) {
    reps <- acfs[acfs$series == s, , drop = FALSE]
    pool <- pooledAcf[pooledAcf$series == s, , drop = FALSE]
    phi <- min(max(mean(vapply(split(reps, reps$rep), acfAt, numeric(1), lag = 1L)), 0), 0.999)
    rInt <- vapply(split(reps, reps$rep), acfAt, numeric(1), lag = interval)
    r <- acfAt(pool, interval)
    data.frame(series = s, phi = phi, tau = (1 + phi) / (1 - phi),
               ar1Misfit = max(abs(pool$acf[pool$lag %in% 1:50] - phi^(1:50))),
               r = r, rMin = min(rInt), rMax = max(rInt),
               effectiveSnapshots = .essAR1(nSnapshots * length(tables), r),
               tauGeyer = .autocorrTime(pool$acf), lagBelow0.1 = .firstLagBelow(pool$acf, 0.1))
  }))
  fitted <- merge(fit[c("series", "phi")], data.frame(lag = 0:lagMax))
  fitted$acf <- fitted$phi^fitted$lag
  limiting <- fit$series[which.max(fit$tau)]
  list(acf = rbind(acfs, pooledAcf), fitted = fitted, fit = fit, thin = ceiling(max(fit$tau, na.rm = TRUE)),
       limiting = limiting, interval = interval, nSnapshots = nSnapshots * length(tables))
}

## Full names of the annual series: `.metricLabel()`, and a species' full name for lead_<code>
.annualSeriesLabel <- function(series, sppEquiv = NULL, sppEquivCol = "LandR") {
  code <- sub("^lead_", "", series)
  full <- rep(NA_character_, length(code))
  if (!is.null(sppEquiv)) full <- sppEquiv[["EN_generic_full"]][match(code, sppEquiv[[sppEquivCol]])]
  ifelse(grepl("^lead_", series), paste("Leading:", ifelse(is.na(full), code, full)), .metricLabel(series))
}

## Empirical ACF by lag for each series (reps faint, pooled bold), the fitted phi^lag curve dashed and a vertical
## line at the summary interval
.autocorrPanels <- function(data, sppEquiv = NULL, sppEquivCol = "LandR") {
  a <- data$acf
  a$label <- .annualSeriesLabel(a$series, sppEquiv, sppEquivCol)
  f <- data$fitted
  f$label <- .annualSeriesLabel(f$series, sppEquiv, sppEquivCol)
  ggplot2::ggplot(a[a$rep != "pooled", ], ggplot2::aes(lag, acf)) +
    ggplot2::geom_line(ggplot2::aes(group = rep), colour = "grey70", linewidth = 0.3) +
    ggplot2::geom_line(data = a[a$rep == "pooled", ], linewidth = 0.8) +
    ggplot2::geom_line(data = f, colour = "firebrick", linetype = "dashed") +
    ggplot2::geom_vline(xintercept = data$interval, colour = "steelblue") +
    ggplot2::facet_wrap(~label) +
    ggplot2::labs(x = "lag (years)", y = "autocorrelation",
                  caption = "faint: reps; bold: mean; dashed: fitted decay; blue: summaryInterval") +
    ggplot2::theme_bw(base_size = 9)
}

autocorrSummary <- function(sim) {
  files <- mod$annualSeriesFiles
  if (!length(files)) {
    message("NRV_summary autocorrelation: no annualSeries.csv found; run with recordAnnualSeries = TRUE")
    return(invisible(sim))
  }
  res <- .autocorrSummary(lapply(files, utils::read.csv), .nrvPeriod(sim), P(sim)$autocorrMaxLag,
                          P(sim)$summaryInterval)
  fit <- res$fit
  fit$label <- .annualSeriesLabel(fit$series, sim$sppEquiv, P(sim)$sppEquivCol)
  fit$recommendedThin <- res$thin
  fit$summaryInterval <- res$interval
  fit$nSnapshots <- res$nSnapshots
  d <- reproducible::checkPath(file.path(.ppRoot(sim), "csv", "autocorrelation"), create = TRUE)
  f_csv <- file.path(d, "autocorrelation.csv")
  utils::write.csv(fit, f_csv, row.names = FALSE)
  sim <- registerOutputs(f_csv, sim)

  lim <- fit[fit$series == res$limiting, ]
  message("NRV_summary autocorrelation: snapshots ", res$interval, " years apart: correlation r = ", signif(lim$r, 2),
          " (reps ", signif(lim$rMin, 2), "-", signif(lim$rMax, 2), "); about ", signif(lim$effectiveSnapshots, 2),
          " effectively independent snapshots in the NRV; fitted autocorrelation time tau = ", signif(lim$tau, 3),
          " years (series: ", lim$label, "); recommended thinning ", res$thin, " years")

  Plots(
    data = res, fn = .autocorrPanels, sppEquiv = sim$sppEquiv, sppEquivCol = P(sim)$sppEquivCol,
    filename = "autocorrelation", path = .ppFigDir(sim, "autocorrelation", "all"),
    types = P(sim)$.plots, ggsaveArgs = list(width = 12, height = 8, units = "in")
  )
  invisible(sim)
}

.inputObjects <- function(sim) {
  ## nothing here

  return(invisible(sim))
}
