## The stand-level measures of the `st` event, from synthetic snapshot values.

test_that("a snapshot's stand-level row: age classes of forest, forested and leading shares of the area, biomass", {
  ## 6 reporting-area pixels: 4 forested (ages 10, 50, 90, 150), one with no age, one with pixel group 0
  sam <- c(10, 50, 90, 150, NA, 30)
  pgm <- c(1L, 1L, 2L, 2L, 3L, 0L)
  vtm <- c("Pice_mar", "Pice_mar", "Mixed", "Pice_mar", NA, NA)
  cd <- data.frame(pixelGroup = c(1L, 1L, 2L), B = c(100, 200, 1000)) ## g/m2: 300 in group 1, 1000 in group 2
  r <- .standRow(sam, vtm, pgm, cd, pixelHa = 6.25, ageClassCutOffs = c(0, 40, 80, 120),
                 ageClasses = c("Young", "Immature", "Mature", "Old"))
  v <- setNames(r$value, r$metric)
  expect_equal(v[paste0("age_", c("Young", "Immature", "Mature", "Old"))], setNames(rep(25, 4), paste0("age_", c("Young", "Immature", "Mature", "Old"))))
  expect_equal(v[["forested"]], 100 * 4 / 6)
  ## leading types are shares of the forested pixels (4), as the annual series
  expect_equal(v[["lead_Pice_mar"]], 100 * 3 / 4)
  expect_equal(v[["lead_Mixed"]], 100 * 1 / 4)
  ## B over the pixels: 2 x 300 + 2 x 1000 g/m2, x 6.25 ha x 1e4 m2/ha, in Tg
  expect_equal(v[["biomassTg"]], (2 * 300 + 2 * 1000) * 6.25 * 1e4 / 1e12)
})

test_that("snapshot files pair by rep folder and year", {
  f <- function(kind, ext) c(sprintf("o/rep2/%s_year2120.%s", kind, ext), sprintf("o/rep1/%s_year2020.%s", kind, ext),
                             sprintf("o/rep1/%s_year2120.%s", kind, ext))
  s <- .snapshotTable(f("standAgeMap", "tif"), f("vegTypeMap", "tif"), f("pixelGroupMap", "tif"), f("cohortData", "qs2"))
  expect_identical(nrow(s), 3L)
  i <- s$rep == "rep2"
  expect_identical(s$time[i], 2120)
  expect_identical(s$cd[i], "o/rep2/cohortData_year2120.qs2")
  expect_identical(s$vtm[i], "o/rep2/vegTypeMap_year2120.tif")
})

test_that("a type absent from a snapshot leads 0% of it, also one found only in the current condition", {
  rows <- data.frame(rep = c(1, 1, 2), time = c(0, 100, 0), metric = c("lead_A", "lead_B", "lead_A"), value = c(5, 7, 3))
  out <- .fillAbsentMetrics(rows, "lead_C")
  expect_identical(nrow(out), 2L * 2L * 3L)
  expect_equal(out$value[out$rep == 2 & out$time == 100 & out$metric == "lead_A"], 0)
  expect_equal(sum(out$value[out$metric == "lead_C"]), 0)
})

test_that("the current condition is inside, above or below the NRV range of the NRV years only", {
  env <- data.frame(poly = "E", metric = rep(c("a", "b", "c"), each = 3), time = rep(c(0, 700, 1000), 3),
                    mean = 5, min = c(0, 2, 3, 0, 2, 3, 0, 2, 3), max = c(100, 8, 9, 100, 8, 9, 100, 8, 9))
  cc <- data.frame(poly = "E", metric = c("a", "b", "c"), mean = c(9, 50, 1))
  r <- .nrvComparison(env, cc, c(700, 1000))
  r <- r[order(r$metric), ]
  expect_identical(r$position, c("inside", "above", "below")) ## 9 is the top of the range: inside
  expect_equal(r$lo, rep(2, 3))
  expect_equal(r$hi, rep(9, 3))
})

test_that("stand-level labels name the leading type by sppEquiv", {
  se <- data.frame(LandR = "Pice_mar", EN_generic_full = "Black spruce")
  expect_identical(.standLabel(c("lead_Pice_mar", "age_Old", "forested", "biomassTg"), se),
                   c("Black spruce leading, share of forested area (%)", "Old forest, share of forested area (%)",
                     "Forested share of the area (%)", "Total tree biomass (Tg)"))
})

test_that("the stand-level figure draws reps, their median and the current condition", {
  s <- data.frame(rep = rep(1:2, each = 3), time = rep(c(0, 500, 1000), 2), class = "Old", value = 1:6)
  g <- .standSeriesPanels(list(series = s, cc = data.frame(time = 0, class = "Old", value = 2),
                               period = c(700, 1000), title = "t", ylab = "y"))
  expect_s3_class(g, "ggplot")
  expect_silent(ggplot2::ggplot_build(g))
})

test_that("legend entries are the class only, on the right, in columns that keep them on the figure", {
  se <- data.frame(LandR = "Pinu_con", EN_generic_full = "Lodgepole pine")
  expect_identical(.standClass(c("lead_Pinu_con", "lead_Mixed", "age_Old", "forested", "biomassTg"), se),
                   c("Lodgepole pine", "Mixed", "Old", "Forested", "Total tree biomass"))
  expect_identical(.standClass(c("lead_Pinu_con", "lead_Mixed")), c("Pinu con", "Mixed")) ## no sppEquiv: one name each
  cls <- paste0("Species number ", 1:30)
  s <- expand.grid(rep = 1:2, time = c(0, 500), class = cls, stringsAsFactors = FALSE)
  s$value <- 1
  g <- .standSeriesPanels(list(series = s, cc = data.frame(time = 0, class = cls, value = 1),
                               period = c(300, 500), title = "t", ylab = "y"))
  expect_identical(g$theme$legend.position, "right")
  expect_identical(g$guides$guides$colour$params$ncol, 3) ## 30 entries: 12 to a column
  expect_identical(as.character(unique(ggplot2::ggplot_build(g)$plot$data$class))[1], "Species number 1")
})

test_that("a position colours the current condition: inside green, below blue, above purple", {
  expect_identical(unname(.positionColour[c("inside", "below", "above")]), c("#1b9e77", "#2166ac", "#7b3294"))
  s <- data.frame(rep = rep(1:2, each = 3), time = rep(c(0, 500, 1000), 2), class = "Old", value = 1:6)
  g <- .standSeriesPanels(list(series = s, cc = data.frame(time = 0, class = "Old", value = 2, position = "above"),
                               period = c(700, 1000), title = "t", ylab = "y"))
  b <- ggplot2::ggplot_build(g)
  pt <- b$data[[length(b$data)]]
  expect_identical(pt$fill, "#7b3294")
})

test_that("each leading type, the mixed class included, gets a figure with its position", {
  g <- expand.grid(rep = 1:5, time = c(0, 100), metric = c("lead_A", "lead_Mixed", "lead_Z", "age_Old"),
                   stringsAsFactors = FALSE)
  g$value <- ifelse(g$metric == "lead_Z", 0, 5)
  g$class <- .standClass(g$metric)
  cc <- data.frame(metric = c("lead_A", "lead_Mixed", "lead_Z", "age_Old"), time = 0, value = c(1, 5, 0, 5))
  cc$class <- .standClass(cc$metric)
  cmp <- data.frame(metric = cc$metric, position = c("below", "inside", "inside", "inside"))
  f <- .speciesFigData(g, cc, cmp, c(50, 100), "ELF")
  expect_identical(names(f), c("lead_A", "lead_Mixed")) ## not an age class, nor a type that never leads
  expect_identical(f$lead_A$cc$position, "below")
  expect_identical(unique(f$lead_A$series$rep), 1:5)
  expect_silent(ggplot2::ggplot_build(.standSeriesPanels(f$lead_A)))
})

test_that("series and current condition of a stand-level row are on one scale (percent), so a snapshot is inside its own range", {
  sam <- c(10, 50, 90, 150); pgm <- 1:4; vtm <- c("A", "A", "B", "B")
  cd <- data.frame(pixelGroup = 1:4, B = 100)
  r <- .standRow(sam, vtm, pgm, cd, 6.25, c(0, 40, 80, 120), c("Young", "Immature", "Mature", "Old"))
  env <- data.frame(poly = "E", metric = r$metric, time = 1000, mean = r$value, min = r$value * 0.9, max = r$value * 1.1)
  cmp <- .nrvComparison(env, data.frame(poly = "E", metric = r$metric, mean = r$value), c(0, 2000))
  expect_true(all(cmp$position == "inside"))
  expect_equal(sum(cmp$current[grepl("^age_", cmp$metric)]), 100) ## shares of the forest, not proportions
  expect_equal(sum(cmp$current[grepl("^lead_", cmp$metric)]), 100) ## forested everywhere here
})

test_that("a comparison row says whether it is a test: a leading type that leads nowhere is not", {
  env <- data.frame(poly = "E", metric = rep(c("lead_A", "lead_Zero", "age_Old"), each = 2), time = rep(c(0, 100), 3),
                    mean = c(5, 5, 0, 0, 0, 0), min = c(4, 4, 0, 0, 0, 0), max = c(6, 6, 0, 0, 0, 0))
  cc <- data.frame(poly = "E", metric = c("lead_A", "lead_Zero", "age_Old"), mean = c(5, 0, 0))
  r <- .nrvComparison(env, cc, c(0, 100))
  expect_identical(setNames(r$tested, r$metric)[c("lead_A", "lead_Zero", "age_Old")],
                   c(lead_A = TRUE, lead_Zero = FALSE, age_Old = TRUE)) ## age_Old at 0 is a real test
  ## the combined figure drops exactly the rows that are not tests
  r$group <- "stand"; r$label <- r$metric
  expect_false("lead_Zero" %in% .currentConditionAllData(r)$metric)
})

test_that("the stand-level order is biomass, age classes young to old, forested, then leading types by label", {
  m <- c("lead_B", "age_Old", "forested", "lead_A", "age_Young", "biomassTg", "age_Mature")
  lab <- c("Beta", "Old", "Forested", "Alpha", "Young", "Biomass", "Mature")
  o <- .standOrder(m, lab)
  expect_type(o, "integer")
  expect_identical(m[order(o)], c("biomassTg", "age_Young", "age_Mature", "age_Old", "forested", "lead_A", "lead_B"))
})

test_that("nrvInside counts the tests inside the NRV range, per polygon and group", {
  cmp <- data.frame(
    poly = rep(c("E1", "E2"), c(7, 3)),
    group = c("landscape", "landscape", rep("stand", 5), "landscape", "stand", "stand"),
    metric = c("ai", "np", "ai", "age_Old", "lead_A", "lead_Zero", "forested", "ai", "lead_Zero", "lead_A"),
    position = c("below", "inside", "inside", "above", "inside", "inside", "below", "inside", "inside", "inside"),
    tested = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE))
  r <- .nrvInside(cmp)
  expect_identical(names(r), c("poly", "group", "nTests", "nInside", "pctInside"))
  expect_identical(r$poly, c("E1", "E1", "E2", "E2"))
  expect_identical(r$group, c("landscape", "stand", "landscape", "stand"))
  expect_identical(r$nTests, c(2L, 4L, 1L, 1L))
  expect_identical(r$nInside, c(1L, 2L, 1L, 1L))
  expect_equal(r$pctInside, c(50, 50, 100, 100))
  ## summed over the groups: the polygon's pooled count
  pooled <- stats::aggregate(cbind(nTests, nInside) ~ poly, r, sum)
  expect_identical(pooled$nTests, c(6L, 2L))
  expect_identical(pooled$nInside, c(3L, 2L))
})

test_that("nrvInside.csv is written with one row per polygon and group", {
  cmp <- data.frame(poly = c("E1", "E1", "E2"), group = c("landscape", "stand", "stand"),
                    position = c("inside", "below", "inside"), tested = TRUE)
  f <- .writeNrvInside(cmp, withr::local_tempdir())
  expect_identical(basename(f), "nrvInside.csv")
  d <- utils::read.csv(f)
  expect_identical(names(d), c("poly", "group", "nTests", "nInside", "pctInside"))
  expect_equal(d$pctInside, c(100, 0, 100))
})

test_that("a snapshot's big-treed old, young and recently burned shares", {
  ## 4 forested pixels (ages 10, 50, 130, 150) of 5; old (>= 120): pixel groups 3 (B 500) and 4 (B 900)
  sam <- c(10, 50, 130, 150, NA)
  pgm <- c(1L, 2L, 3L, 4L, 0L)
  cd <- data.frame(pixelGroup = 1:4, B = c(100, 200, 500, 900))
  expect_equal(.bigTreedThreshold(sam, pgm, cd, oldAge = 120, q = 0.75), 800) ## of 500 and 900
  r <- .standRow(sam, rep("Pice_mar", 5), pgm, cd, pixelHa = 6.25, ageClassCutOffs = c(0, 40, 80, 120),
                 ageClasses = c("Young", "Immature", "Mature", "Old"), bigTreedB = 800, recentYears = 40L,
                 recentBurn = c(TRUE, FALSE, FALSE, FALSE, TRUE))
  v <- setNames(r$value, r$metric)
  expect_equal(v[["bigOld"]], 100 * 1 / 4)       ## of the forested
  expect_equal(v[["youngRecent"]], 100 * 1 / 5)  ## of the area
  expect_equal(v[["burnedRecent"]], 100 * 2 / 5) ## of the area
  ## without them, the row is as before
  r0 <- .standRow(sam, rep("Pice_mar", 5), pgm, cd, 6.25, c(0, 40, 80, 120), c("Young", "Immature", "Mature", "Old"))
  expect_false(any(c("bigOld", "youngRecent", "burnedRecent") %in% r0$metric))
})

test_that("rows are labelled by the State of the Forest indicators they speak to", {
  expect_identical(
    .sofIndicator(c("age_Old", "bigOld", "burnedRecent", "biomassTg", "lead_Pice_mar")),
    c("SoF-1 old growth", "SoF-1 old growth", "SoF-5 boreal caribou", "SoF-6 forest carbon", NA)
  )
  expect_identical(.sofIndicator(c("age_Old", "forested"), "Protected"),
                   c("SoF-1 old growth; SoF-3 protected areas", "SoF-3 protected areas"))
  expect_identical(.sofIndicator("burnedRecent", "BorealCaribou"), "SoF-5 boreal caribou")
  expect_identical(.sofIndicator("bigOld", "Intact"), "SoF-1 old growth; SoF-2 primary forest")
  expect_identical(.sofIndicator("ai", "ELF"), NA_character_)
})

## The stand-level event on 4 x 4 pixels of 6.25 ha, one pixel group each, in two reps; the left half is a
## `Protected` unit, `ELFlayer` the whole reporting area. Returns the run's output folder.
## `species`: the species of each pixel (default: Pice_mar everywhere); `params`: more module parameters; `sppEquiv`.
runStandFixture <- function(sofIndicators, standPolyNames, fetch, env = parent.frame(), species = rep("Pice_mar", 16),
                            params = list(), sppEquiv = NULL) {
  ## 4 x 4 pixels of 6.25 ha, one pixel group each; the left half is protected
  r0 <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 1000, ymin = 0, ymax = 1000, crs = "EPSG:3978")
  out <- withr::local_tempdir(.local_envir = env)
  w <- function(vals, f, cat = FALSE) {
    r <- terra::setValues(r0, vals)
    if (cat) levels(r) <- data.frame(ID = seq_along(unique(species)), code = unique(species))
    terra::writeRaster(r, f, overwrite = TRUE)
    f
  }
  ages0 <- rep(c(150, 10, 60, 130), each = 4)      ## rows: old, young, mature, old
  B <- c(100, 200, 300, 400, rep(50, 8), 500, 600, 700, 800)
  for (rp in c("rep1", "rep2")) {
    d <- file.path(out, rp)
    dir.create(d)
    for (yr in c("000", "100")) {
      w(1:16, file.path(d, paste0("pixelGroupMap_year", yr, ".tif")))
      w(match(species, unique(species)), file.path(d, paste0("vegTypeMap_year", yr, ".tif")), cat = TRUE)
      w(if (yr == "000") ages0 else ages0 + 100, file.path(d, paste0("standAgeMap_year", yr, ".tif")))
      ## year 0: no time since fire in pixel 1; year 100: the top row burned 10 years before
      w(if (yr == "000") c(NA, rep(50, 15)) else c(rep(10, 4), rep(200, 12)),
        file.path(d, paste0("rstTimeSinceFire_year", yr, ".tif")))
      qs2::qs_save(data.frame(pixelGroup = 1:16, speciesCode = species, B = B), file.path(d, paste0("cohortData_year", yr, ".qs2")))
    }
  }
  sq <- function(x1) sf::st_sf(Name = c(ELFlayer = "ELF", Protected = "Protected")[[x1]],
                               geometry = sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = if (x1 == "ELFlayer") 1000 else 500, ymax = 1000), crs = 3978)))
  snap <- function(kind, ext) file.path(out, c("rep1", "rep2"), paste0(kind, "_year100.", ext))
  mod <- new.env()
  mod$sam <- snap("standAgeMap", "tif"); mod$vtm <- snap("vegTypeMap", "tif")
  mod$pgm <- snap("pixelGroupMap", "tif"); mod$cd <- snap("cohortData", "qs2")
  mod$rep1Dir <- file.path(out, "rep1")
  mod$fsam0 <- file.path(out, "rep1", "standAgeMap_year000.tif")
  mod$fvtm0 <- file.path(out, "rep1", "vegTypeMap_year000.tif")
  mod$ftsf0 <- file.path(out, "rep1", "rstTimeSinceFire_year000.tif")
  mod$standPolyNames <- standPolyNames
  mod$reportingPolygons <- list(ELFlayer = sq("ELFlayer"), Protected = sq("Protected"))
  ## NBAC: one fire over the top-left two pixels (pixel 1 has no time since fire, so only pixel 2 counts)
  testthat::local_mocked_bindings(fetch_nbac_polys = fetch, .package = "fireregimetools", .env = env)
  sar <- sq("ELFlayer")
  fn <- moduleFn("standMetrics", mod)
  ## outside an event there is no current module, for standMetrics() and the helpers it calls
  testthat::local_mocked_bindings(P = function(sim, ...) SpaDES.core::params(sim)$NRV_summary, .env = env)
  environment(fn)$P <- P
  zoneOutputs <- moduleFn(".standZoneOutputs", mod) ## it, and the recorder it calls, read and write `mod`
  environment(zoneOutputs)$.recordComparison <- moduleFn(".recordComparison", mod)
  environment(fn)$.standZoneOutputs <- zoneOutputs
  sim <- SpaDES.core::simInit(
    times = list(start = 0, end = 100),
    params = list(NRV_summary = utils::modifyList(
      list(mode = "multi", reps = 1:2, .plots = "png", .studyAreaName = "ELF",
           simTimes = c(0, 100), summaryPeriod = c(0L, 100L), nrvWindow = 0.5, sofIndicators = sofIndicators),
      params)),
    modules = moduleName, paths = utils::modifyList(testPaths, list(outputPath = file.path(out, "mainSim"))),
    objects = list(reportingPolygons = list(ELFlayer = sq("ELFlayer"), Protected = sq("Protected")),
                   studyAreaReporting = sar, sppEquiv = sppEquiv)
  )
  sim <- fn(sim)
  out
}

nbacTopLeft <- function(study_area, fire_years, dest, ...) {
  ## NBAC: one fire over the top-left two pixels (pixel 1 has no time since fire, so only pixel 2 counts)
  terra::vect("POLYGON ((0 750, 500 750, 500 1000, 0 1000, 0 750))", crs = "EPSG:3978")
}

test_that("the stand-level event reports the reporting area and each unit of each layer, with the new measures", {
  withr::local_package("SpaDES.core")
  out <- runStandFixture(TRUE, c("ELFlayer", "Protected"), nbacTopLeft)

  csv <- file.path(out, "postprocess", "csv", "st")
  read <- function(...) utils::read.csv(file.path(csv, ...))
  cc <- function(d) setNames(d$value, d$metric)
  ## the reporting area: old is 8 of 16 pixels; the threshold is the 0.75 quantile of their B (625)
  ccSA <- cc(read("ELF", "st_CC.csv"))
  expect_equal(ccSA[["bigOld"]], 100 * 2 / 16)       ## B 700 and 800
  expect_equal(ccSA[["youngRecent"]], 100 * 4 / 16)  ## the age-10 row
  expect_equal(ccSA[["burnedRecent"]], 100 * 1 / 16) ## NBAC pixel 2
  ## the protected half: pixels 1, 2, 5, 6, 9, 10, 13, 14
  ccP <- cc(read("Protected", "Protected", "st_CC.csv"))
  expect_equal(ccP[["bigOld"]], 0)                   ## its old pixels have B 100, 200, 500, 600
  expect_equal(ccP[["youngRecent"]], 100 * 2 / 8)
  expect_equal(ccP[["burnedRecent"]], 100 * 1 / 8)
  ## simulated year 100: the burned top row
  s <- read("Protected", "Protected", "st.csv")
  expect_equal(unique(s$value[s$metric == "burnedRecent"]), 100 * 2 / 8)
  ## the layer that is the reporting area itself is not reported again
  expect_false(dir.exists(file.path(csv, "ELFlayer")))
  ## the comparisons carry the indicator labels
  cmp <- read("Protected", "Protected", "st_nrvComparison.csv")
  expect_identical(cmp$sofIndicator[cmp$metric == "bigOld"], "SoF-1 old growth; SoF-3 protected areas")
  expect_identical(read("ELF", "st_nrvComparison.csv")$sofIndicator[cmp$metric == "biomassTg"], "SoF-6 forest carbon")
  expect_true(file.exists(file.path(out, "postprocess", "figures", "st", "Protected", "Protected",
                                    "current_condition_overview.png")))
})

test_that("by default the stand-level outputs are those of the base module: no new measures, column, figure or fetch", {
  withr::local_package("SpaDES.core")
  out <- runStandFixture(FALSE, character(0), function(...) stop("NBAC fetched with sofIndicators = FALSE"))
  csv <- file.path(out, "postprocess", "csv", "st")
  expect_identical(list.files(csv), "ELF") ## no unit of any layer
  cc <- utils::read.csv(file.path(csv, "ELF", "st_CC.csv"))
  expect_setequal(cc$metric, c(paste0("age_", c("Young", "Immature", "Mature", "Old")), "forested", "biomassTg",
                               "lead_Pice_mar"))
  cmp <- utils::read.csv(file.path(csv, "ELF", "st_nrvComparison.csv"))
  expect_false("sofIndicator" %in% names(cmp))
  ## readers take the lead-nowhere rule from the file, never re-apply it
  expect_type(cmp$tested, "logical")
  expect_identical(cmp$tested, !(grepl("^lead_", cmp$metric) & cmp$current == 0 & cmp$hi == 0))
  figs <- list.files(file.path(out, "postprocess", "figures", "st", "ELF"))
  expect_false("stand_disturbance.png" %in% figs)
  expect_true("stand_age.png" %in% figs)
})

test_that("the landscape-metric comparisons of a national layer carry its indicator", {
  withr::local_package("SpaDES.core")
  mod <- new.env()
  fn <- moduleFn(".writeNrvComparisonCSV", mod)
  environment(fn)$.recordComparison <- moduleFn(".recordComparison", mod)
  testthat::local_mocked_bindings(P = function(sim, ...) SpaDES.core::params(sim)$NRV_summary)
  out <- withr::local_tempdir()
  sim <- SpaDES.core::simInit(times = list(start = 0, end = 100),
                              params = list(NRV_summary = list(mode = "multi", reps = 1L, summaryPeriod = c(0L, 100L))),
                              modules = moduleName, objects = list(reportingPolygons = list(ELF = "placeholder")),
                              paths = utils::modifyList(testPaths, list(outputPath = file.path(out, "mainSim"))))
  env <- data.frame(poly = "Chinchaga", metric = "ai", time = c(80, 100), mean = 5, min = 1, max = 9)
  SpaDES.core::params(sim)$NRV_summary$nationalReportingLayers <- "BorealCaribou"
  fn(sim, env, data.frame(poly = "Chinchaga", metric = "ai", mean = 4), "lm", "BorealCaribou")
  ## by default, no indicator column
  f <- file.path(out, "postprocess", "csv", "lm", "BorealCaribou", "lm_nrvComparison.csv")
  expect_false("sofIndicator" %in% names(utils::read.csv(f)))
  SpaDES.core::params(sim)$NRV_summary$sofIndicators <- TRUE
  mod$nrvComparisons <- NULL
  fn(sim, env, data.frame(poly = "Chinchaga", metric = "ai", mean = 4), "lm", "BorealCaribou")
  cmp <- utils::read.csv(file.path(out, "postprocess", "csv", "lm", "BorealCaribou", "lm_nrvComparison.csv"))
  expect_identical(cmp$sofIndicator, "SoF-5 boreal caribou")
  ## a national layer is not one of the ELF's own: it stays out of the ELF's combined figure and nrvInside.csv
  expect_length(mod$nrvComparisons, 0L)
  fn(sim, transform(env, poly = "ELF"), data.frame(poly = "ELF", metric = "ai", mean = 4), "lm", "ELF")
  expect_identical(names(mod$nrvComparisons), "lm ELF")
})

test_that("the intact-forest extent gives each year's area, share and loss since 2000", {
  withr::local_package("SpaDES.core")
  mod <- new.env()
  fn <- moduleFn(".intactExtent", mod)
  testthat::local_mocked_bindings(P = function(sim, ...) SpaDES.core::params(sim)$NRV_summary)
  out <- withr::local_tempdir()
  ## a 10 x 10 km reporting area; 50 km2 intact in 2000, 30 km2 in 2025
  sq <- function(x, nm = "Intact") sf::st_sf(Name = nm, geometry = sf::st_sfc(sf::st_polygon(list(
    rbind(c(0, 0), c(x, 0), c(x, 10000), c(0, 10000), c(0, 0)))), crs = 3978))
  sim <- SpaDES.core::simInit(times = list(start = 0, end = 100),
                              params = list(NRV_summary = list(mode = "multi", reps = 1L, summaryPeriod = c(0L, 100L))),
                              modules = moduleName,
                              objects = list(reportingPolygons = list(ELF = "placeholder"),
                                             studyAreaReporting = terra::vect(sq(10000))),
                              paths = utils::modifyList(testPaths, list(outputPath = file.path(out, "mainSim"))))
  national <- list(Intact = sq(3000), Intact2000 = sq(5000, "Intact2000"))
  SpaDES.core::params(sim)$NRV_summary$nationalReportingLayers <- c("Intact", "Intact2000")
  ## by default, no table
  expect_null(fn(sim, national))
  SpaDES.core::params(sim)$NRV_summary$sofIndicators <- TRUE
  d <- fn(sim, national)
  f <- file.path(out, "postprocess", "csv", "sof", "Intact", "intact_extent.csv")
  expect_identical(utils::read.csv(f)$layer, c("Intact2000", "Intact"))
  expect_identical(d$year, c(2000L, 2025L))
  expect_equal(d$area_km2, c(50, 30))
  expect_equal(d$share_pct, c(50, 30))
  expect_equal(d$loss_km2, c(0, 20))
  expect_equal(d$loss_pct, c(0, 40))
  expect_true(f %in% mod$ppFiles)
  ## a year with no intact forest left in the reporting area counts as none
  expect_equal(fn(sim, national["Intact2000"])$area_km2, c(50, 0))
  expect_identical(.sofIndicator("bigOld", "Intact2000"), "SoF-1 old growth; SoF-2 primary forest")
})

## 16 pixels, one cohort each: 6 black spruce, 4 pine, 3 aspen, 2 birch, 1 white spruce
topFixtureSpecies <- c(rep("Pice_mar", 6), rep("Pinu_con", 4), rep("Popu_tre", 3), rep("Betu_pap", 2), "Pice_gla")
topFixtureEquiv <- function() {
  data.table::data.table(LandR = c("Pice_mar", "Pinu_con", "Popu_tre", "Betu_pap", "Pice_gla"),
                         Type = c("Conifer", "Conifer", "Deciduous", "Deciduous", "Conifer"))
}
leadMetrics <- function(out) {
  d <- utils::read.csv(file.path(out, "postprocess", "csv", "st", "ELF", "st_CC.csv"))
  setNames(d$value, d$metric)[grepl("^lead_", d$metric)]
}

test_that("standTopSpecies keeps only the most abundant species of the current condition", {
  withr::local_package("SpaDES.core")
  all <- leadMetrics(runStandFixture(FALSE, character(0), function(...) stop("NBAC"), species = topFixtureSpecies,
                                     sppEquiv = topFixtureEquiv()))
  expect_setequal(names(all), paste0("lead_", unique(topFixtureSpecies)))
  top <- runStandFixture(FALSE, character(0), function(...) stop("NBAC"), species = topFixtureSpecies, sppEquiv = topFixtureEquiv(),
                         params = list(standTopSpecies = 3L))
  expect_setequal(names(leadMetrics(top)), c("lead_Pice_mar", "lead_Pinu_con", "lead_Popu_tre"))
  ## the comparison table and the series drop the others too
  csv <- file.path(top, "postprocess", "csv", "st", "ELF")
  expect_false(any(grepl("Betu_pap|Pice_gla", utils::read.csv(file.path(csv, "st_nrvComparison.csv"))$metric)))
  expect_false(any(grepl("Betu_pap|Pice_gla", utils::read.csv(file.path(csv, "st.csv"))$metric)))
})

test_that("standGroupsCol adds the groups, Mixed included, beside the species, labelled and tested", {
  withr::local_package("SpaDES.core")
  out <- runStandFixture(FALSE, character(0), function(...) stop("NBAC"), species = topFixtureSpecies, sppEquiv = topFixtureEquiv(),
                         params = list(standGroupsCol = "Type", standTopSpecies = 2L))
  v <- leadMetrics(out)
  ## the species (2 of them) and the groups: 11 conifer pixels (6 + 4 + 1), 5 deciduous, none mixed
  expect_setequal(names(v), c("lead_Pice_mar", "lead_Pinu_con", "lead_Type-Conifer", "lead_Type-Deciduous"))
  expect_equal(v[["lead_Type-Conifer"]], 100 * 11 / 16)
  expect_equal(v[["lead_Type-Deciduous"]], 100 * 5 / 16)
  cmp <- utils::read.csv(file.path(out, "postprocess", "csv", "st", "ELF", "st_nrvComparison.csv"))
  g <- cmp[cmp$metric == "lead_Type-Conifer", ]
  expect_identical(g$label, "Conifer (Type) leading, share of forested area (%)")
  expect_true(g$tested)
  expect_true(file.exists(file.path(out, "postprocess", "figures", "st", "ELF", "species", "lead_Type-Conifer.png")))
})

test_that("a pixel where neither type leads is Mixed in the groups", {
  ## 2 pixel groups of the cohorts: conifer 50 / deciduous 50 is Mixed
  grp <- LandWebUtils::sppEquiv_groups(topFixtureEquiv(), "LandR", "Type")
  cd <- data.frame(pixelGroup = c(1L, 1L, 2L), speciesCode = c("Pice_mar", "Popu_tre", "Pice_mar"), B = c(50, 50, 100))
  expect_identical(.groupCodes(c(1L, 2L, 3L), cd, grp, NULL, 2L), c("Mixed", "Conifer", NA))
})
