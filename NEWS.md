Known issues: <https://github.com/FOR-CAST/NRV_summary/issues>

# NRV_summary (development version)

## Stable output keys via curated short names (`2.0.0.9020`)

- `refCode` (which names the `_aggregates/<refCode>/` parquet directory and the figure/CSV
  filenames) is now `LandWebUtils::refCodeFor(kind, layer)` = `<kind>_<slug(layer name)>`, instead
  of `paste0("<kind>_", abbreviate(layer, minlength = 8))`. `abbreviate()` was called one name at a
  time, and R only guarantees unique abbreviations *within a single call's vector* -- with the
  restored tenure x sub-region crossings, 68 of the 399 crossed FMA x ANSR names collided (e.g.
  `Canadian Forest Products Ltd. Alpine` and `Crowsnest Forest Products Ltd. Alpine` both ->
  `CFPLtd.A`), silently overwriting each other's aggregates and figures.
- Reporting-polygon layer names are now curated short names (`LandWebUtils::reportingPolygonLayers()$NAME_SHORT`,
  e.g. `ANSR`, or `SprayLake ANSR` for a crossed unit), so the on-disk key equals the label shown in
  figure titles and facet strips. **Existing `_aggregates/` and `figures/` directories carry the old
  keys and will be rebuilt.**
- Requires `LandWebUtils >= 1.0.3.9016`.

## Post-processing outputs reorganised; v2-form LandWeb-summary plots (`2.0.0.9009`)

- Multi-mode summary outputs now live under `outputs/<studyArea>/postprocess/` (a sibling of the
  mainSim rep dirs, which are still read from `outputPath(sim)`), with parallel `figures/` and `csv/`
  trees that mirror the same `<kind>/<layer>/` sub-structure (kind = lm / pm / boxplots / histograms;
  layer = the reporting-polygon-layer name). This replaces the flat `<refCode>_*.{csv,png}` files
  under `mainSim/`, so a figure and its data sit side by side and the dir path carries the context.
- The `lw` LandWeb summaries now render the v2 forms via `nrvtools::plot_leading_boxplot()` /
  `plot_largepatch_histogram()`: `figures/boxplots/<layer>/<subregion> <species>.png` (age-class
  boxplots + red CC dot) and `figures/histograms/<layer>/<size>/<subregion> <species>.png` (one file
  per species, four age-class panels, red CC line), replacing the busy distribution facets.
- `lm`/`pm` envelope figures relocate to `figures/<kind>/<layer>/{ribbon,boxplot}.png`.

## Save maps at `timeSeriesTimes` for the animation (`2.0.0.9008`)

- `mode = "single"` now generates and saves the `standAgeMap` / `vegTypeMap` at each
  `timeSeriesTimes` year (in addition to the summary times), so the `"am"` animation actually has
  its frames when read back in `mode = "multi"`. Previously the maps were only saved at
  `summaryPeriod` / `summaryInterval` times, so `timeSeriesTimes` outside that window produced no
  frames. The heavier `cohortData` / `pixelGroupMap` are still saved only at the summary analysis
  times, not at the (many) `timeSeriesTimes` years.

## Stand-age time-series animation (`2.0.0.9007`)

- New `"am"` `postprocessEvents` option (mode `"multi"`) ports the v2 `LandWeb_summary`
  animation: replicate 1's saved `standAgeMap` layers for the `timeSeriesTimes` years are
  reclassified into age classes (`ageClassCutOffs` / `ageClasses`, RdYlGn young &rarr; old,
  ggplot2 + `tidyterra`) and written to `standAge_animation.gif`. Encoded with **`gifski`**
  (pure-Rust) instead of `animation`/ImageMagick, so it needs no `policy.xml` cache
  configuration (the v2 path failed with "cache resources exhausted"; see LandWeb #153).
  Adds `gifski`, `RColorBrewer`, and `tidyterra` to `reqdPkgs`.

## `patchDirections` knob for lw large-patch connectivity (`2.0.0.9006`)

- New `patchDirections` parameter (integer, default `4L`) controls the patch
  connectivity of the `lw` large-patch analysis, passed through to
  `nrvtools::largePatchCounts()` / `landscapemetrics::get_patches()`: `4` = rook
  (4-connected) or `8` = queen (8-connected). **Departure from v2:** the v2
  `LandWeb_summary` large-patch analysis was fixed at 4-connectivity (GDAL
  `polygonize`'s default); the default `4L` reproduces v2, and `8L` (queen) is a
  deliberate v3-only option.

## LandWeb summaries: Leading + LargePatches (`2.0.0.9005`)

- `postprocess_lw` now runs the ported v2 `LandWeb_summary` analyses via `nrvtools` (>= 0.2.0):
  leading-vegetation-by-age-class and large-patch counts, keyed `lw_<poly>` (with a `_CC`
  current-conditions twin). The age basis is **time-since-fire** (`rstTimeSinceFire`, from
  burnSummaries), matching v2. The NRV distribution pools across replicates **and** summary years
  (summarized with `time` excluded from the id columns, via a new `.buildRepDataset(id_cols=)`
  passthrough). `plotFun` renders these as distribution histograms with a current-condition
  reference line (`plot_nrv_distribution()`) rather than time envelopes.

## Drop reporting-polygon features with no grouping label (`2.0.0.9003`)

* `landscapeMetrics` (lm) + `patchMetrics` (pm) now drop features whose grouping column (`Name`) is
  `NA` before summarising, and skip a layer entirely if none remain within the study area. An NA
  `polyName` made the metric producers select an empty subpoly (`summaryPolys[[col]] == NA`), so
  `crop()` returned NULL and the metric functions errored on `values(NULL)`.

## Landscape + patch metrics keyed on the reporting-polygon layer (`2.0.0.9002`)

* `landscapeMetrics` (lm) and `patchMetrics` (pm) now group by the `"Name"` column that
  `LandWebUtils::buildReportingPolygons()` sets and key each output `refCode` on the reporting-polygon
  **layer name** (`abbreviate(p)`), matching the `bc` (seral) event. Previously they hard-coded
  `polyCol = "NAME"` and keyed on `rptPoly[["ID"]]`, but the built reporting polygons carry neither a
  `NAME` nor an `ID` column, so a run errored inside `nrv_metrics_landscape`
  (`'names' attribute [1] must be the same length as the vector [0]`).

## Current-conditions reference = the saved year-0 state (`2.0.0.9001`)

* The `mode = "multi"` current-conditions (CC) snapshot now reads the simulation's saved year-0
  state (`rep01/vegTypeMap_year0000.tif` + `standAgeMap_year0000.tif`, the deterministic initial
  condition) instead of regenerating a VTM from `speciesLayers` in `patchMetrics` and reading a
  `reportingPolygons[["CC SAM"]]` stand-age. This removes (a) the write-before-read ordering bug
  where `landscapeMetrics` read the CC VTM before `patchMetrics` wrote it (a standalone run errored
  with `file does not exist: .../vegTypeMap_year0.tif`), and (b) the un-wired `"CC SAM"` dependency.
  The CC file paths are resolved once in `InitMulti`.

# NRV_summary 2.0.0

This is a breaking release that adopts the Arrow-native, memory-bounded NRV
summary path from `FOR-CAST/nrvtools (>= 0.1.0)` (which removed the former
in-memory `calculateLandscapeMetrics()` / `summarizePatchMetrics()` /
`summarizePatchMetricsSeral()`).

* landscape, patch, and seral patch metrics are now computed *raw* per replicate
  (`nrvtools::nrv_metrics_landscape()`, `calculatePatchMetrics()`,
  `calculatePatchMetricsSeral()`), written to per-replicate parquet partitions
  under `<outputPath>/_aggregates/<refCode>/replicate=<rep>/`, and reduced across
  replicates by `nrvtools::summarize_nrv()`, so the per-replicate rows are never
  all held in memory at once (the point of the change: large study areas x many
  replicates no longer blow up RAM).
* BREAKING output change: the former per-`funList` summary CSVs
  (`<refCode>_<funList>.csv`) and raw CSVs (`<refCode>_<funList>_raw.csv`) are
  replaced by a per-`refCode` envelope CSV (`<refCode>.csv`), one CSV per
  landscapemetrics metric (`<refCode>_<metric>.csv`), and the parquet dataset.
  The envelope columns are now `n_reps`/`mean`/`sd`/`min`/`q25`/`median`/`q75`/
  `max`/`se`/`ci` (the former `N`/`mn`/`mm`/`q1`/`md`/`q3`/`mx` are gone).
  Downstream readers must be updated.
* NRV plots use `nrvtools::plot_nrv_envelope()`, producing both a min-max ribbon
  (`<refCode>_ribbon.png`) and a box-and-whisker that shows the median and
  quartiles (`<refCode>_boxplot.png`) per reporting unit. The former paginated
  per-metric box/violin/over-time plots and the current-conditions overlay are
  pending re-addition (the `<refCode>_CC` envelope is still computed and saved).
* `SeralTable.csv` is unchanged in shape; its pooled total area is now
  `sum(n_reps * mean)` (identical to the former `sum(N * mn)`).
* removed the development `browser()` breakpoints from the postprocessing
  functions; requires `FOR-CAST/nrvtools (>= 0.1.0)`.

# NRV_summary 1.1.3

* current development version; consolidated NRV post-processing module that
  supersedes and absorbs the roles of `LandWeb_summary`, `timeSinceFire`, and
  `LandWeb_output`.
* run modes finalized: `mode = "single"` runs as part of a simulation (custom
  in-sim saving); `mode = "multi"` runs as post-processing across multiple runs.
* made `timeSeriesTimes` and `summaryPeriod` `start(sim)`-relative, with
  validation that both fall within the simulation's `start(sim)`..`end(sim)`
  range (reverted an interim change that had dropped the `start(sim)` offset).
* moved input-object existence checks out of `.inputObjects()` and into `init`.
* wired `standAgeMap` and `vegTypeMap` through `mod` and added them to the
  module's output objects; added missing module object dependencies.
* added `loadOrder` metadata; merged the upstream `startSim` branch;
  consistency tweaks.

# NRV_summary 1.1.2

* major refactor for combined single/multi use: added a `mode` parameter
  ("single" vs "multi") to select in-simulation vs post-processing behaviour,
  restructuring the module around the new params.
* replaced the `ml` map-list "god object" with a named `reportingPolygons`
  list; removed the `ml` output object and switched summaries to read polygon
  identity from the `reportingPolygons` "field" attribute.
* moved `summaryPeriod` from an expected input to a module parameter.
* added custom saving in single mode.

# NRV_summary 1.1.1

* added `sieveThresh` parameter and used `terra::sieve()` to merge singleton
  patches with neighbouring large patches; fixed `sieveThresh` usage and output
  filenames.
* bumped required `nrvtools` version for seral-stage map creation/fixes.
* removed the `sppEquivCol` parameter (cannot be user-defined).
* fixed grep regex used in file matching.

# NRV_summary 1.1.0

* minor release marking the stabilized seral-stage / `nrvtools`-based summary
  and mapping workflow.

# NRV_summary 1.0.0

* first stable release.
* seral-stage map creation and improved BC summaries against the latest
  `nrvtools`.
* fixed `refCodeCC` handling and `write.csv()` calls; removed redundant "CC"
  from CSV filenames; ungroup before `dplyr::summarize()` and pipe fixes;
  removed stray `browser()` calls.

# NRV_summary 0.0.6

* added `postprocessEvent` parameter to specify which post-processing events to
  run.
* added seral-stage patch figures; `standAgeMap` now taken from the `ml` object
  (`SAM`).
* stopped using package prefixes in `funList`.

# NRV_summary 0.0.1

* initial version: converted the BC NRV post-processing script into a SpaDES
  module (depends on `LandWebUtils`).
* landscape and patch metrics summaries by reporting polygon, including by LU,
  by BEC, and for arbitrary polygons supplied via `ml`; handled reporting
  subpolygons with empty data.frames and reported missing files.
* migrated to `terra`/`sf`; added violin plots and multi-page plots for patch
  metrics.
* parallel-processing improvements: core-count control via `future`, generalized
  `rasterListByPoly`, flammable map passed as a file for use in parallel; masked
  non-flammable pixels in TSF maps that otherwise skewed ages very old.
