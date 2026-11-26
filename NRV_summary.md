---
title: "NRV_summary Manual"
subtitle: "v.2.0.0.9046"
date: "Last updated: 2026-11-26"
output:
  bookdown::html_document2:
    toc: true
    toc_float: true
    theme: sandstone
    number_sections: false
    df_print: paged
    keep_md: yes
editor_options:
  chunk_output_type: console
  bibliography: citations/references_NRV_summary.bib
citation-style: citations/ecology-letters.csl
link-citations: true
always_allow_html: true
---

# NRV_summary Module

<!-- the following are text references used in captions for LaTeX compatibility -->
(ref:NRV-summary) *NRV_summary*



[![made-with-Markdown](figures/markdownBadge.png)](http://commonmark.org)

<!-- if knitting to pdf remember to add the pandoc_args: ["--extract-media", "."] option to yml in order to get the badge images -->

#### Authors:

Alex M. Chubaty <achubaty@for-cast.ca> [aut]
<!-- ideally separate authors with new lines, '\n' not working -->

## Module Overview

### Module summary

NRV simulation post-processing and summary creation.
Produces 'X over time' and other summaries for multiple landscape and patch metrics.

### Module inputs and parameters

Table \@ref(tab:moduleInputs-NRV-summary) shows the full list of module inputs.

<table class="table" style="margin-left: auto; margin-right: auto;">
<caption>(\#tab:moduleInputs-NRV-summary)(\#tab:moduleInputs-NRV-summary)List of (ref:NRV-summary) input objects and their description.</caption>
 <thead>
  <tr>
   <th style="text-align:left;"> objectName </th>
   <th style="text-align:left;"> objectClass </th>
   <th style="text-align:left;"> desc </th>
   <th style="text-align:left;"> sourceURL </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> cohortData </td>
   <td style="text-align:left;"> data.table </td>
   <td style="text-align:left;"> Required in single mode. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> LandTypeCC_reporting </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Current-conditions land cover (Canada LCC 2020) with urban RETAINED. Used to correct the year-0 current-condition snapshot: the simulation imputes urban to its nearest forest type (pre-industrial state), so the year-0 rasters would otherwise report imputed forest as real current forest. Only urban differs between the sim and reporting layers -- water/barren/snow are already NA on both sides. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> flammableMap </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> binary flammability map (required with `type = 'single'`) </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> pixelGroupMap </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Required in single mode. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> reportingPolygons </td>
   <td style="text-align:left;"> list </td>
   <td style="text-align:left;"> reporting polygons for post-processing (required with `type = 'multi'`) </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> speciesLayers </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> initial percent cover raster layers used for simulation. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sppColorVect </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> A named vector of colors to use for plotting. The names must be in `sim$sppEquiv[[P(sim)$sppEquivCol]]`, and should also contain a color for 'Mixed' </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sppColorVectReporting </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> (mode = 'multi', with `sppEquivColReporting`) named colours for the reporting groups and 'Mixed'. If absent, `LandR::sppColors()` on the reporting column. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sppEquiv </td>
   <td style="text-align:left;"> data.table </td>
   <td style="text-align:left;"> table of species equivalencies. See `LandR::sppEquivalencies_CA`.NANA </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> standAgeMap </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> (mode = 'single') stand age of the current forest (e.g. Biomass_borealDataPrep's), on the grid of `pixelGroupMap` or on a larger grid aligned with it. The year-0 stand-age map, with `ccStandAgeSource = 'standAgeMap'`. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> studyAreaReporting </td>
   <td style="text-align:left;"> SpatVector </td>
   <td style="text-align:left;"> Required in single mode. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
</tbody>
</table>

Summary of user-visible parameters (Table \@ref(tab:moduleParams-NRV-summary)).


<table class="table" style="margin-left: auto; margin-right: auto;">
<caption>(\#tab:moduleParams-NRV-summary)(\#tab:moduleParams-NRV-summary)List of (ref:NRV-summary) parameters and their description.</caption>
 <thead>
  <tr>
   <th style="text-align:left;"> paramName </th>
   <th style="text-align:left;"> paramClass </th>
   <th style="text-align:left;"> default </th>
   <th style="text-align:left;"> min </th>
   <th style="text-align:left;"> max </th>
   <th style="text-align:left;"> paramDesc </th>
   <th style="text-align:left;"> cacheKey </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> autocorrMaxLag </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 200 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> longest lag (years) of the autocorrelation of the annual landscape series, which gives the thinning interval for the summary snapshots. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ageClasses </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> Young, I.... </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> descriptions/labels for age classes (seral stages) </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ageClassCutOffs </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 0, 40, 8.... </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> defines the age boundaries between age classes </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ageClassMaxAge </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 400 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> maximum possible age </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> bigTreedQuantile </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0.75 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> stand-level event: a stand is big-treed old forest (`bigOld`) when it is in the oldest age class and its biomass is at least this quantile of the biomass of the oldest age class at the current condition over the reporting area. A stand-in for site productivity, until that is available. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ccStandAgeSource </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> standAgeMap </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'single') where the current condition's (year 0's) stand-age map comes from: 'standAgeMap', the age layer `sim$standAgeMap` (e.g. Biomass_borealDataPrep's) on the pixels with cohorts, rounded and then floored to the decade, as `LandR::standAgeMapGenerator()` floors the simulated years' ages; or 'cohortData', that generator's biomass-weighted age of the year-0 cohorts, which keeps the binning of the cohort ages. 'standAgeMap' warns and uses the cohorts when `sim$standAgeMap` is absent or not on a grid aligned with `pixelGroupMap`. The simulated years always come from the cohorts. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> patchDirections </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 4 </td>
   <td style="text-align:left;"> 4 </td>
   <td style="text-align:left;"> 8 </td>
   <td style="text-align:left;"> patch connectivity for the 'lw' (LandWeb summary) large-patch analysis, passed to `nrvtools::largePatchCounts()` (via `landscapemetrics::get_patches`): `4` = rook / 4-connected (matches v2's GDAL `polygonize`; the default), `8` = queen / 8-connected. NOTE: v2 was fixed at 4-connectivity; exposing 8 (queen) is a departure from v2. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> mixedType </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 2 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> How to define mixed stands: `0L` for none; `1L` for any species admixture; `2L` for deciduous &gt; conifer. See `LandR::vegTypeMapGenerator`. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> mode </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> single </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> use 'single' to run part of a simulation; use 'multi' to run as part of postprocessing multiple runs. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> recordAnnualSeries </td>
   <td style="text-align:left;"> logical </td>
   <td style="text-align:left;"> TRUE </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'single') record a few landscape scalars every year (proportion young and old, mean stand age, total biomass, proportion by leading species) in `annualSeries.csv`. In 'multi' mode they give the autocorrelation time of the landscape, hence how far apart the summary snapshots must be to be independent. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> reuseAggregates </td>
   <td style="text-align:left;"> logical </td>
   <td style="text-align:left;"> FALSE </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') if TRUE, reuse a complete per-replicate `_aggregates` parquet dataset instead of recomputing it, re-summarizing the surviving parquets to regenerate the envelopes/CSVs/figures. Use to iterate on the plots/CSVs without re-running the (~hours) landscape-metric aggregation; leave FALSE for a fresh run. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> plotWorkers </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 8 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') hard cap on the number of local worker processes used to render the postprocess figures in parallel (each figure is an independent `ggsave`). The actual count is RAM-aware (`pemisc::optimalClusterNum`) but never exceeds this cap, so a shared compute node is not swamped; 1 renders sequentially. Uses `future` multisession (not fork; the crew worker is a mirai daemon). </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> postprocessEvents </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> lm, pm </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Specify which subset of postprocessing events to run. At least one of: 'am' for the stand-age time-series animation (GIF); 'bc' for BC seral stage patch metrics; 'lm' for default landscape metrics; 'lw' for default LandWeb summaries 'pm' for default patch metrics; 'st' for stand-level measures (age-class, leading-type and forested shares, total biomass) at each summary time, from the saved snapshots; 'on' for ON patch metrics. Any other value is an error ('fd', forest degradation indicators, is not implemented). </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> recentFireYears </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 1985, 2024 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> stand-level event: the observed fire years (NBAC) whose burned area is the current condition of `burnedRecent`; their number (40 by default, as ECCC's boreal caribou disturbance measure) is also the window of the simulated time since fire (`burnedRecent`) and of stand age (`youngRecent`). </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> reps </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 1, 2, 3,.... </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> number of replicates/runs per study area. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sieveThresh </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> threshold patch size (number of pixels) to use with `terra::sieve` when creating seral stage maps </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> simTimes </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> NA, NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Simulation start and end times when running in 'multi' mode. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sppEquivCol </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> LandR </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> The column in `sim$sppEquiv` data.table to use as a naming convention </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> standOnlyLayers </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> Protected </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> reporting layers summarised by the stand-level event (`st`) only, not by the landscape and patch metrics: layers of units too small or scattered for patch structure to mean much, such as the protected areas. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sofIndicators </td>
   <td style="text-align:left;"> logical </td>
   <td style="text-align:left;"> FALSE </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> the State of the Forest indicator outputs: the stand-level measures `bigOld`, `youngRecent` and `burnedRecent` (the last fetches NBAC fires for its current condition), the `sofIndicator` column of the `lm_` and `st_nrvComparison.csv` tables, and the stand_disturbance figure. FALSE (the default) writes none of them. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> stabilityAlpha </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0.05 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> (mode = 'multi') significance level of the Mann-Kendall trend test in the stability check. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> stabilityMinChange </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0.1 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> (mode = 'multi') a series is flagged 'still changing' only if its fitted change across the stability window exceeds this fraction of the series' range (its largest minus smallest value over all reps within the window), as well as being a significant trend. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> stabilityWindow </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0.5 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> (mode = 'multi') the last fraction of `summaryPeriod` over which the stability check looks for a directional trend (0.5 = the last half). A run whose metrics are still trending there needs to be longer. It does not define the NRV (see `nrvWindow`). </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> nationalReportingLayers </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;">  </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') layers of `LandWebUtils::nationalReportingLayers()` to add to `reportingPolygons`, by `NAME_SHORT`: any of 'Province', 'Ecozone', 'Protected', 'BorealCaribou', 'Intact' and 'Intact2000' (intact forest in 2025 and 2000, the stand-in for primary forest; with `sofIndicators`, csv/sof/Intact/intact_extent.csv gives its loss). Each is clipped to `studyAreaReporting`, so a run reports its own pieces of a province or an ecozone. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> nationalReportingLayersPath </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> where the national layers are downloaded (once, and shared by every run that points here); `NA` is `inputPath(sim)`. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> fragmentationAgeThreshold </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') with `landscapeMap = "forest"`: stands whose stand age (years, the stand-age maps of the stand outputs) is below this are non-forest, with the pixels that have no cohorts. Forest is every other pixel of the reporting area. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> landscapeMap </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> vegType </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') the map the 'lm' event's metrics are computed on: 'vegType' (the vegetation-type maps) or 'forest' (forest / non-forest maps made from the saved stand-age maps, non-forest being a stand age below `fragmentationAgeThreshold` or no cohorts; the current condition's urban pixels are left out as for 'vegType'). On 'forest' only the forest class (class 1) is reported, as a landscape metric named `forest_&lt;metric&gt;`: with `landscapeMetricFuns = "lsm_c_ed"`, `forest_ed`, 'Forest edge density (m/ha)'. Its rows are those of any other landscape metric in `lm_nrvComparison.csv`, the inside counts and the figures. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> landscapeMetricFuns </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> lsm_l_ar.... </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') the metrics of the 'lm' event: the `landscapemetrics` function names passed as `funList` to `nrvtools::nrv_metrics_landscape()`. The default is `nrvtools::default_landscape_metrics()`. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> nrvWindow </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0.3 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> the NRV is the last fraction of `summaryPeriod` (0.3 = the last 30%; in a 1000-year run, years 700-1000). Must be above 0 and at most 1. The NRV range and the current condition overview use only the summary times in it; the time-series figures still show all of `summaryPeriod`, with the NRV years shaded. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> sppEquivColReporting </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (mode = 'multi') column of `sim$sppEquiv` that groups the simulated species (`sppEquivCol`) for reporting. When set, the vegetation-type maps that the 'lm', 'lw' and 'pm' analyses read, for the simulated years and for current conditions, are rebuilt from the saved `cohortData` and `pixelGroupMap` with each species recoded to its group, so biomass is summed within a group before the leading type is decided. `LandR::vegTypeMapGenerator()` sums only within a code, so relabelling the species-level maps would not give this. `NA` (the default) analyses the species-level maps the simulation saved. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> standGroupsCol </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> Type </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (stand-level `st` measures) column of `sim$sppEquiv` that groups the simulated species (`sppEquivCol`) into the forest cover types reported: the default `"Type"` gives `Conifer` and `Deciduous`, and `Mixed` is the mixedwood class of the vegetation-type map (`mixedType`, `vegLeadingProportion`). The cover measures `lead_&lt;group&gt;` are the share of the forested area each cover type leads: a pixel's leading species, from the vegetation-type map, mapped to its group. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> standTopSpecies </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 3 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> (stand-level `st` measures) the species measures `biomass_&lt;species&gt;` are each species' share of the total tree biomass of the forested area. Only the `standTopSpecies` species with the largest share in the current condition are kept (default 3); `NA` keeps every species. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> summaryInterval </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 100 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> simulation time interval at which to take 'snapshots' used for summary analyses. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> summaryPeriod </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 0, 10 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> lower and upper end of the range of simulation times summarised and shown in the time-series figures; default is the whole run. The NRV is the last `nrvWindow` fraction of it. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> timeSeriesTimes </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> simulation times for which to build time series animations; default (NA) is start + 601:650 when the run is that long, otherwise the last 50 years of the run. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> vegLeadingProportion </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0.75 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> a number that defines whether a species is leading for a given pixel. Default: `LandR::leadingSpeciesProp()`, i.e. option `LandR.leadingSpeciesProp`, which takes `LandR.mixedwoodProp` (0.75) unless set. Setting it in one place moves every module and LandR function together. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .plots </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> screen </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Used by `SpaDES.core::Plots`, which can be optionally used here. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .plotInitialTime </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Describes the simulation time at which the first plot event should occur. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .plotInterval </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Describes the simulation time interval between plot events. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .studyAreaName </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Human-readable name for the study area used, or a hash of the study area obtained using `reproducible::studyAreaName()`. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .seed </td>
   <td style="text-align:left;"> list </td>
   <td style="text-align:left;">  </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Named list of seeds to use for each event (names). </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .useCache </td>
   <td style="text-align:left;"> logical </td>
   <td style="text-align:left;"> FALSE </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Should caching of events or module be used? </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
</tbody>
</table>

### Reporting by groups of the simulated species

When species are simulated separately but reported by groups of them, set `sppEquivColReporting`
to the column of `sim$sppEquiv` that holds the groups (LandWeb uses `"LandWebReport"`, its
reporting groups). In `mode = "multi"`, the vegetation-type maps that the `lm`, `lw` and `pm`
analyses read, for the simulated years and for current conditions, are then rebuilt from the saved
`cohortData` and `pixelGroupMap` with each species recoded to its group, and written under
`postprocess/_reportingMaps/`. Biomass is summed within a group before the leading type is decided.
`LandR::vegTypeMapGenerator()` sums biomass only within a species code, so relabelling the
species-level maps would not give the same result: a stand of 40% black spruce, 40% tamarack and
20% aspen is led by the group holding both conifers.

A simulated code in two groups, or a group holding both conifers and broadleaves, stops the run.
The groups' colours come from the optional input `sppColorVectReporting`. With
`sppEquivColReporting = NA` (the default), the analyses read the species-level maps the simulation
saved.

### Fragmentation: forest edge density

With `landscapeMap = "forest"` the `lm` event computes its landscape metrics (`landscapeMetricFuns`) on
forest / non-forest maps instead of the vegetation-type maps, and reports the forest class. With
`landscapeMetricFuns = "lsm_c_ed"` that is forest edge density (m of forest edge per ha). In `mode = "multi"` it is computed on
forest / non-forest maps built from the saved stand-age maps
(`standAgeMap`) of each summary year and of the current condition, and written under
`postprocess/_forestMaps/`. A pixel is non-forest if its stand age is below
`fragmentationAgeThreshold` (20 years by default), or it has no cohorts; every other pixel of the
reporting area is forest. The current condition leaves out urban pixels, as for the default metrics.
The metric's rows are in `lm_nrvComparison.csv`, `nrvInside.csv` and the figures, as for any other
landscape metric. With `landscapeMap = "vegType"` (the default) nothing changes.

### Events

In `mode = "multi"` the postprocessing events selected via the `postprocessEvents`
parameter run at the end of the simulation. Alongside the metric events (`lm`, `pm`,
`lw`, `bc`, ...), `"am"` produces a **stand-age time-series animation**: replicate 1's
saved `standAgeMap` layers for the `timeSeriesTimes` years are reclassified into age
classes (`ageClassCutOffs` / `ageClasses`, coloured young &rarr; old with `RdYlGn`) and
written to `standAge_animation.gif` under the module's figure path.

The animation is encoded with **`gifski`** (a pure-Rust GIF encoder bundled as an R
package), which needs no external tools. This deliberately avoids ImageMagick: the v2
`animation::saveGIF` path routinely failed with *"cache resources exhausted"* and required
raising ImageMagick's `policy.xml` memory/disk limits (see
[LandWeb #153](https://github.com/PredictiveEcology/LandWeb/issues/153)). With `gifski`
**no such system configuration is required**.

### Plotting

In `mode = "multi"`, `plotFun` writes these figures for each reporting-polygon layer, under
`postprocess/figures/`:

- `lm/<layer>/` and `pm/<layer>/`: the NRV envelope of each metric in each subregion, as a
  time series (`*_ribbon.png`: each replicate a thin grey line, the median over the replicates bold) and as a
  box-and-whisker per summary year (median and quartiles, whiskers from minimum to maximum),
  with the current condition (the year-0 snapshot) as a red dashed line where it has a value.
  Patch metrics have a panel per vegetation type. A patch-level metric (patch area, median stand
  age of a patch) enters as each replicate's mean over its patches, so the envelope spans the
  replicates, as for the class-level metrics.
- `lm/<layer>/per-metric/`: the envelopes of each landscape metric with a panel per subregion,
  up to 12 panels to a page.
- `pm/<layer>/per-metric/`: box and violin plots of each patch metric for each vegetation type,
  a panel per subregion, from the values of each replicate and summary year (a patch-level
  metric averaged over each replicate's patches), with the current condition as a red point.
  Patch area has no pages of its own: a replicate's mean patch area is the class's `area_mn`.
- `boxplots/<layer>/` and `histograms/<layer>/`: the LandWeb summaries (`lw`), with the current
  condition in red. Besides a boxplot per subregion and leading vegetation type,
  `boxplots/<layer>/<subregion> share of forest.png` has a panel per age class and a box per
  leading type of its share of the subregion's forested area.
- `sspm/<layer>/`: the BC seral patch metrics (`bc`), one paginated envelope figure-set per metric.

The y axes name each metric and its unit, and each envelope and per-class figure has a caption
saying what its marks show, with the numbers of replicates and simulation years drawn. A class
absent from a map has a class area (`ca`) of 0 ha: the `pm` event writes these zeros to the
aggregates, for each class a subregion shows in its current condition or in any replicate-year,
so the class-area figures count the replicate-years without the class. The `lw` event does the
same for the vegetation types in every `lw` metric (leading proportion, share of the forest,
large-patch count and area).

The `"am"` event additionally writes the stand-age animation GIF (see *Events*).

### Saving

Write what is saved.

### Module outputs

Description of the module outputs (Table \@ref(tab:moduleOutputs-NRV-summary)).

<table class="table" style="margin-left: auto; margin-right: auto;">
<caption>(\#tab:moduleOutputs-NRV-summary)(\#tab:moduleOutputs-NRV-summary)List of (ref:NRV-summary) outputs and their description.</caption>
 <thead>
  <tr>
   <th style="text-align:left;"> objectName </th>
   <th style="text-align:left;"> objectClass </th>
   <th style="text-align:left;"> desc </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> character(0) </td>
   <td style="text-align:left;"> c(":----------", ":-----------", ":----") </td>
   <td style="text-align:left;"> character(0) </td>
  </tr>
</tbody>
</table>

### Links to other modules

Describe any anticipated linkages to other modules, such as modules that supply input data or do post-hoc analysis.

### Getting help

- <https://github.com/FOR-CAST/NRV_summary/issues>
