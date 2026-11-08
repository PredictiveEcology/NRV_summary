Known issues: <https://github.com/FOR-CAST/NRV_summary/issues>

# NRV_summary (development version)

- The century-block burn stability check reads burnSummaries' own per-block table (`burnSummaries_fireBlocks.csv`, found
  through the registered outputs) instead of an `areaBurnedHa` column that only fireSense writes. With LandMine or scfm
  fires the area burned was always 0, so the check always said "stable". `.burnBlockSeries()` is removed.

- `st_nrvComparison.csv` and `lm_nrvComparison.csv` have a `tested` column (FALSE for a leading type that is 0 in the
  current condition and the NRV), and `st_nrvComparison.csv` an integer `order` column (the order of the figure's rows).
  New `csv/all/nrvInside.csv`: per polygon, `nTests`, `nInside` and `pctInside` over the tested rows of `lm` and `st`.

- Stand-level (`st`) leading-type shares are now percent of the forested pixels, as in the annual series, not of all
  reporting pixels; the forested share of the area is still reported as `forested`. `lead_*` values, ranges and
  positions in `st*.csv` change; labels read "share of forested area (%)".

- Single mode registers each saved data file (cohortData, pixelGroupMap, standAgeMap, vegTypeMap, sppEquiv, sppColorVect,
  speciesLayers, flammableMap) with the name of the object it holds and the function that saved it. `outputs(sim)` had
  `NA` for the object name of all of them, so a replay could not load the archived files back as inputs.

- The `lm` and `pm` time-series figures (`<poly> <metric>_ribbon.png` and the per-metric `<metric>_ribbon_p<n>.png` pages)
  draw each replicate as its own thin grey line with the median over the replicates bold, as the stand-level figures
  do, instead of a min--max band and mean line. File names are unchanged; the current condition and the shaded NRV
  years are kept. The `bc` (`sspm`) figures keep their band: it spans patches, not replicates.

## Stand-level measures and the current condition against the NRV, in tables

- New multi-mode postprocess event `"st"` (add it to `postprocessEvents`): at each summary time of each rep and for
  the current condition, the share of forest in each age class, the forested share of the reporting area, the share
  led by each vegetation type and the total tree biomass (Tg), from the saved snapshots. It writes
  `csv/st/<studyArea>/st.csv`, `st_CC.csv` and `st_nrvComparison.csv`, draws `figures/st/<studyArea>/stand_age.png`,
  `stand_leading.png` and `stand_biomass.png`, and the stability check tests these series too.
- The `lm` event also writes `lm_nrvComparison.csv`: per metric the NRV range and mean, the current condition and
  whether it is inside, above or below the range (what the current-condition overview figure draws).
- Single mode, and so what each replicate writes, is unchanged.
- New event `postprocess_cc` (scheduled with `lm` or `st`, after them) draws `figures/all/current_condition_all.png`: every metric of the `lm` and `st` groups in one panel, each metric's NRV range rescaled to 0-1 (0 = lowest, 1 = highest simulated value), the current condition coloured by its position; points beyond one range width are drawn at the limit with an arrow and their value. With several polygons there is one file each, `current_condition_all_<polygon>.png`. The `mid` column of `lm_nrvComparison.csv` and `st_nrvComparison.csv`, and the tick on the overview figures, is now the median over the NRV years of the per-time means (it was their mean). Stand rows run biomass, age classes young to old, forested share, leading types. `pm` writes no comparison table, so it is not on the figure. The per-group overview figures are kept.
- The stand-level legends (`stand_age.png`, `stand_leading.png`, `stand_biomass.png`) name only the class ("Lodgepole pine"), on the right in as many columns as needed, so they are no longer cut off.
- The `st` event also draws one figure per leading type, the mixed class included, `figures/st/<studyArea>/species/lead_<code>.png` (replicates thin, median bold, current condition, NRV years shaded), and `figures/st/<studyArea>/current_condition_overview.png`. The `lw` event pools the NRV years, so it has no series over simulation years.
- The current condition is coloured by where it falls against the NRV range on the overview figures and the species figures: inside `#1b9e77`, below `#2166ac`, above `#7b3294`.
- Stability pages are sized to the panels they hold (a last page with one panel was a full blank canvas), and the bold line is the median, not the mean.

- Multi mode finds replicate folders named by the bare number (`.../370/16/`, as `SpaDES.project::pathBuild()` writes them), not only `rep16`: SpaDES.core >= 3.2.1.9057 (PredictiveEcology/SpaDES.core#515).

## Events scheduled once

- In "single" mode `map_generators` and `save_single` were scheduled twice at the same time when the start, the start of the summary period, the end or a `timeSeriesTimes` year coincided (and again by the `summaryInterval` reschedule when it reached one of them). Each is now scheduled once per distinct time, which saves duplicate work and lets reruns reuse the cache.

## Input checks at first use

- Mode 'single' no longer fails in init when `cohortData`, `pixelGroupMap` etc. are not yet made by the vegetation
  modules' init (cold cache); the objects are checked at the first `map_generators`, `save_single` or `annual_series`
  event, with an error naming the missing ones.
## Faster annual row

- The annual event takes the leading species per pixelGroup from `LandR::leadingByPixelGroup()` instead of
  `LandR::vegTypeGenerator()` plus a join onto every cohort row and `!duplicated()`; the row is identical.
  Needs the LandR with `leadingByPixelGroup()`.

## Autocorrelation time sets the thinning of the snapshots

- New annual event (`recordAnnualSeries = TRUE`, the default; mode 'single') writes `annualSeries.csv` per rep: the
  proportion of forest young and old, mean stand age, total biomass and the proportion led by each species, one
  row per year, no rasters.
- In mode 'multi' the new `postprocess_autocorr` event fits an exponential decay to each series over the NRV years
  (phi = mean over reps of the lag-1 autocorrelation, tau = (1 + phi) / (1 - phi), with `ar1Misfit` checking the fit
  against the empirical ACF at lags 1-50), reports the correlation r at lag `summaryInterval` (pooled, and the lowest
  and highest rep) and the effective number of independent snapshots n (1 - r) / (1 + r). The recommended thinning
  interval is the largest tau. Geyer's tau is kept as `tauGeyer` for comparison. Written to
  `csv/autocorrelation/autocorrelation.csv` and `figures/autocorrelation/`; `autocorrMaxLag` (default 200 years)
  is the longest lag shown.

## `nrvWindow`: the NRV is the last part of the summary period

- `summaryPeriod` now defaults to the whole run, `c(start(sim), end(sim))` (it was `start + c(700, 1000)`),
  and is the span summarised and shown in the time-series figures. **Breaking default**: set
  `summaryPeriod = start(sim) + c(700L, 1000L)` for the old summary years.
- New parameter `nrvWindow` (default 0.3, above 0 and at most 1): the NRV is the last `nrvWindow` fraction of
  `summaryPeriod`, so a 1000-year run has the NRV of years 700-1000, as the old default did. The NRV range and
  `current_condition_overview.png` use only the summary times in it (`.nrvPeriod()`). The LandWeb summaries (leading
  species, large patches), which pool over summary years, also use only the NRV years.
- Envelope figures show all of `summaryPeriod` and shade the NRV years ("shaded: NRV years"). The stability
  check keeps its own `stabilityWindow`, also a fraction of `summaryPeriod`.
- `.renderTasks()` now passes `.addNrvShading` to the detached figure renderer, as it does `.addCurrentCondition`; envelope figures failed with "could not find function" with `plotWorkers` of 1 and on workers.

## The NRV is the summary period; figures show real scales and full metric names

- The NRV range (min, max and mean of the envelope) uses all times in `summaryPeriod` again, not only the
  last `stabilityWindow` of it. `stabilityWindow` now only sets the span of the stability check; the
  "shaded: the stability window, which defines the NRV" shading is removed from the envelope figures.
- `current_condition_overview.png` is no longer rescaled to 0-1: one facet per metric on its own scale,
  grey bar from the NRV minimum to maximum, a tick at the NRV median and a red dot at the current condition.
- Figure titles, facets and axes show full metric names ("Aggregation index", "Mean patch area",
  "Median stand age", ...) from one lookup; CSVs and file names keep the codes.

## `timeSeriesTimes` default fits short runs

- `timeSeriesTimes` now defaults to `NA`, resolved at init to `start + 601:650` when the run is that
  long and to the last 50 years of the run otherwise. The fixed `start + 601:650` default made every run
  shorter than 650 years stop with "timeSeriesTimes values are outside the range of simulation times".
  An explicit value outside the run still stops.

## Current condition on the figures; a stability check (multi mode)

- The ribbon and boxplot figures of the landscape and patch metrics now draw the current condition as a
  dashed red line labelled "current condition", and each landscape-metric layer gets
  `current_condition_overview.png`: every metric with the NRV range, the NRV median and the current condition. The overview is saved through `SpaDES.core::Plots()`.
- New event `postprocess_stability` asks whether the run is long enough: for each landscape metric, each
  patch metric by class and the area burned per `summaryInterval` block (from burnSummaries'
  `burnSummaries_fireSizes_allReps.csv`) it tests for a directional trend over the last
  `stabilityWindow` (default 0.5) of `summaryPeriod`, Mann-Kendall on all reps pooled with the
  Theil-Sen slope. A series is "still changing" when the trend is significant (`stabilityAlpha`, 0.05)
  and the fitted change over the window is more than `stabilityMinChange` (0.10) of the series' range
  within the window.
  It writes `csv/stability/stability.csv` (metric, class, slope, p, change as % of range, flag), panels
  of each series with the window shaded and the verdict in the title, a summary figure (both through
  `Plots()`), and logs "N of M metrics still changing; consider a longer run".

## Multi mode: replicate counts and file locations

- `InitMulti()` takes each file once from `outputsDF`. A file registered twice (the last year is saved
  by the sim and again by the summary modules) repeated that replicate's row at that time, so
  `n_reps` in the envelopes was above the number of reps (7 at the last year for 4 reps).
- The files are sorted. `outputsDF` is in the order the files were saved, which differs between the
  veg-type and stand-age maps, and the patch metrics pair the two by position (a veg-type map of one
  year was analysed with the stand-age map of another).
- The year-0 and flammable rasters are read from the directory the replicate's outputs are in, not
  `<outputPath>/rep1`, which does not exist when `outputPath` ends in `_all`.
- Removed the `browser()` call in `postprocess_fd`; the event now says it is not implemented.
- `.planWithWorkers()` no longer passes `workers` to a sequential plan (it warned "unknown arguments").
- Requires SpaDES.core >= 3.2.1.9001 (`dirnamesFromSet()`, `resolveSimYears()`, `padYears()`).

## Missing packages in `reqdPkgs` (`2.0.0.9025`)

* `reqdPkgs` now lists `crayon`, `future` and `reproducible`, which the module's code uses.

## `vegLeadingProportion` default from options

- `vegLeadingProportion` now defaults to `LandR::leadingSpeciesProp()` (option
  `LandR.leadingSpeciesProp`, which takes `LandR.mixedwoodProp`, 0.75, unless set), so the
  leading-species threshold is set once for every module and LandR function instead of being
  hard-coded per module. **The default changes from 0.8 to 0.75**, which changes vegetation type
  maps. Requires LandR >= 1.2.0.9024 (PredictiveEcology/LandR#234).

* **The current condition's stand ages are today's, not the binned ages of the cohorts (`2.0.0.9034`).** In `mode = "single"`, the year-0 `standAgeMap` now comes from the age layer `sim$standAgeMap` (Biomass_borealDataPrep's, cropped to `pixelGroupMap`), on the pixels with cohorts. It came from the year-0 cohorts, whose ages Biomass_borealDataPrep bins (on WesternAlbertaUpland, ages above 70 to the nearest 20 years): there, 30.4% of the forest in the reporting area was 120 years or older by the cohorts, against 22.1% by the age layer. Each age is rounded half up and then floored to the decade, as `LandR::standAgeMapGenerator()` floors the stand ages of every simulated year, so the current condition has the 10-year resolution of the envelopes it is compared with. The flooring leaves the age-class shares unchanged (the class limits are multiples of 10) and lowers the patch ages: on WesternAlbertaUpland, the current condition's patch median age (`sam_mdn`), averaged over the patches of the reporting area, is 71.8 years, against 74.5 by the cohorts and 76.3 by unfloored ages. A pixel with cohorts but no value in the age layer keeps its cohort age. The simulated years keep the cohorts' ages. Of the summaries, only the current condition's patch ages (`pm`, `sam_mdn`) read this map; the `lw` summaries use time since fire. New parameter `ccStandAgeSource`: `"standAgeMap"` (the default) or `"cohortData"`, the former map; without `sim$standAgeMap` on a grid aligned with `pixelGroupMap`, the module warns and uses the cohorts. **This changes the year-0 stand-age map of every replicate and the current condition's `pm` age values.**
* **A figure of the leading vegetation types' shares of each subregion's forest, and absent types count as 0 in the `lw` summaries (`2.0.0.9033`).** `boxplots/<layer>/<subregion> share of forest.png` has a panel per age class and a box per leading type of its share of the subregion's forested area (`leadingShare`, from nrvtools >= 0.3.4.9002), with the current condition in red. Every box has the same denominator, so a type that leads on a few pixels has a small share, where its proportions by age class swing between 0 and 1. The nrvtools producers write rows only for the types present in a map, so a type that led in 7 of 105 replicate-years had its boxes and histograms drawn from those 7 alone (Fir in WAU's Subalpine ANC: median Old proportion 1). The `lw` aggregates now hold 0, in every metric, for each type a subregion shows (in its current condition or in any replicate-year) but lacks in a replicate-year, as the `pm` class areas do. In the leading-proportion boxplots such a replicate-year counts as 0 in every age class, so there the type's age classes sum to 0 rather than 1.
* **Patch metric envelopes span the replicates, and class areas count absent classes as 0 ha (`2.0.0.9032`).** The `pm` envelopes of a patch-level metric (`area`, `sam_mdn`) pooled every patch of every replicate, so the band ran from a single cell to the largest patch, and the current condition's patch mean and median, drawn on the ribbon and box figures, were up to 51 times apart. Each replicate, and the current condition, now contributes its mean over its patches (`nrvtools::nrv_replicate_values()`), as on the per-class pages; the envelope CSVs change accordingly, and their `n_reps` counts replicates, not patches. For `lm` and `pm`, `n_reps` counts the replicates with a value: one whose metric is undefined there (the standard deviation of a single patch, say) is left out. The per-class pages of `area` are dropped: a replicate's mean patch area is the class's mean patch area, `area_mn`, which has its own. landscapemetrics reports no class area for a class absent from a map, so the `ca` boxes and envelopes summarised only the replicate-years where the class occurs. After the `pm` aggregation, a class area of 0 is written (as `replicate=<id>/ca_zeros.parquet`) for each class that a subregion shows in its current condition or in any replicate-year but lacks in a replicate-year, the current condition included. Patch size, shape and age metrics stay undefined for an absent class. **This changes the `pm` envelopes, CSVs and figures.**
* **The NRV figures say what they show (`2.0.0.9032`).** The y axis gives the metric's plain name and unit (`nrvtools::nrv_metric_info()`; a patch-level metric adds "mean over patches") with thousands separators, the x axis of the envelopes reads "Simulation year", vegetation types are shown by their display names ("Bl Spruce"), and each figure has a caption built from its data: on the ribbons, "Grey band: range of <n> replicates at each simulation year; line: mean; red dashed line: current condition (simulation year 0)"; on the envelope boxplots, the median and quartiles of the replicates with whiskers from minimum to maximum; on the per-class pages, the median and quartiles of <n> replicates x <k> simulation years with whiskers to 1.5 x IQR, or their violins. The titles are unchanged (subregion or layer, then metric). A page has as many rows of four panels as it needs (up to three), with the canvas height to match, a single-panel figure a smaller canvas, and every envelope and per-class figure the same strip text size. The envelope quartiles are exact (nrvtools >= 0.3.4.9001), where they were Arrow's approximations.
* **One figure that fails no longer stops the others (`2.0.0.9032`).** A figure that fails to render warns with its file name. The pages of a metric are counted from the subregions (and classes) that have a value, the panels drawn, where a layer of 13 or more subregions could ask for a page that did not exist. The per-class pages are drawn only for a layer this run summarised, rather than from whatever aggregates were on disk. Two runs over the same `lm` and `pm` aggregates write identical envelope CSVs, class-area zero files and figures: the zero rows are sorted, and the per-replicate means no longer depend on the order in which Arrow reads the rows. Requires nrvtools >= 0.3.4.9001.
* **The envelope figures show the current condition, and the per-metric pages are back (`2.0.0.9031`).** Every `lm`, `pm` and `bc` envelope figure draws the current condition (the year-0 snapshot, `<refCode>_CC`) as a red dashed line in each panel where it has a value, matched by subregion, class and metric: the current-condition mean on the ribbon figures, its median on the box-and-whisker figures. The `lm` and `pm` analyses again write, for each metric, figures that set a layer's subregions side by side, 12 panels to a page, under `figures/<kind>/<layer>/per-metric/` (`<metric>_<type>_p<page>.png`). For `lm` these are the envelopes over time, a panel per subregion, skipped for a layer with one subregion. For `pm` they are box and violin plots of each vegetation type's values, a panel per subregion, with the current condition as a red point; the values are those of each replicate and summary year, a patch-level metric averaged over each replicate's patches. A vegetation type present today but in no replicate or summary year, or whose metric is undefined in all of them, keeps its point, without a box. Both views were dropped in the arrow rewire (`2.0.0`), where the box and violin plots had shown the across-replicate means of the summary years. Requires nrvtools >= 0.3.4.9000.
* **Year 0, the current condition, is saved before any time-0 dynamics (`2.0.0.9030`).** It was saved at `.last()`, after Biomass_core's growth and mortality when its `growthInitialTime` is `start(sim)`, so today's values held a simulated year of growth and old-age mortality and moved with the species traits (on WesternAlbertaUpland, that year changed the leading type of 4.4% of pixels). A `timeSeriesTimes` or `summaryPeriod` value equal to `start(sim)` no longer adds a second, later year-0 save. **This changes the year-0 files of every replicate and so the current-condition values.**
* **New parameter `sppEquivColReporting` reports vegetation types by groups of the simulated species (`2.0.0.9029`).** In `mode = "multi"`, the maps that the `lm`, `lw` and `pm` analyses read, for the simulated years and for current conditions, are rebuilt from the saved `cohortData` and `pixelGroupMap` with each species recoded to its group in that column of `sppEquiv`, and written under `postprocess/_reportingMaps/`. `LandR::vegTypeMapGenerator()` sums biomass only within a species code, so this differs from relabelling the species-level maps: a stand of 40% black spruce, 40% tamarack and 20% aspen is led by the group holding both conifers. A simulated code in two groups, or a group holding both conifers and broadleaves, stops the run. Colours come from the new optional input `sppColorVectReporting`. `NA`, the default, keeps the species-level maps. The grouping is `LandWebUtils::sppEquiv_groups()` and `recode_cohorts()` (LandWebUtils >= 1.0.3.9045), shared with LandMine.
* **`vegLeadingProportion` defaults to `LandR::leadingSpeciesProp()` (`2.0.0.9028`),** as in Biomass_core: option `LandR.leadingSpeciesProp`, which takes `LandR.mixedwoodProp` (0.75) unless set. **The default changes from 0.8 to 0.75, which changes the vegetation type maps** of a run that does not set it. With the old default, `paramCheckOtherMods()` stopped a run whose Biomass_* modules used 0.75. Requires LandR >= 1.2.0.9024.
* **`postprocessEvents` is checked at init (`2.0.0.9027`).** `'fd'` was scheduled as a stub that stopped in `browser()` after the other summaries had run, and any other unknown value was skipped without a word. Both now stop the run before any work, naming the values at fault.
* **The metric events set their worker count without a warning or an error (`2.0.0.9027`).** They tweaked `workers` on the caller's plan inline: under `sequential` that warned, and under a plan set as `plan(<backend>, workers = n)` it stopped with 'formal argument "workers" matched by multiple actual arguments', because future (<= 1.76.0) appends a tweak instead of replacing it. The BC seral event called `plan(workers = n)`, which changed nothing. All four now use `.planWithWorkers()`.
* **The current-condition urban correction now completes (`2.0.0.9026`).** `.maskCC()` wrote its masked copies as `_cc/cc_vegTypeMap.tif` etc., but nrvtools labels each per-map result from the path and requires `<rep>/<prefix>_year<YYYY>.tif`, so the landscape-metric summaries stopped with "cannot parse metric label(s)" the first time the correction ran (it had always been skipped before, because `LandTypeCC_reporting` was missing or on the wrong grid). The copies now keep the source's `<rep>/<file>` tail under `_cc/`, so their labels match the unmasked maps'.
* **`mode = "multi"` outputs are now registered with `registerOutputs()` (`2.0.0.9025`).** None were, so a targets stage running this module tracked 0 files: its outputs could change or disappear without the pipeline noticing, while `burnSummaries` tracked 557 MB for the same run. The parquet aggregates, envelope CSVs and stand-age animation are recorded as they are written and registered by the `postprocess` event, which was scheduled but had no handler. The figures were already registered by `plotFun()`, but the `plot` event called it without keeping the `sim` it returned, which discarded them. Tests cover the registration, the CSV bookkeeping and the `plot` event; the last fails if the result is dropped again.
* **Replaced the never-run test stub with metadata tests, and added testthat CI.** `tests/testthat/test-template.R` was the SpaDES boilerplate, unedited: paths from another machine, calls to `Event1`/`Event2` functions this module does not define, and assertions against placeholder strings. It had never been run and would have failed instantly, while making the module look tested. In its place, characterization tests over the module's public contract -- the input and output object names and classes, and the parameter names -- which is what a project binds to and what nothing checked until now. The expectations are GENERATED from the module's live metadata rather than transcribed, and were verified to fail when the contract changes.
* The contract test records that this module declares **no output objects**, which is by design rather than omission: everything it produces -- the per-refCode parquet aggregates, the envelope CSVs and the figures -- is written to `outputPath(sim)`, and nothing is handed back through the simList. A `createsOutput()` appearing later would be a real change in how it is consumed.

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

## Stability check ignores patch-level rows

- The stability series reader kept the patch-level rows of the pm aggregates (one per patch), so a series had many values per rep and time and the check failed. It now keeps only the landscape and class levels (`.seriesLevels()`).

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
