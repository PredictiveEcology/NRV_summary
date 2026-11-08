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

test_that("nrvInside counts the tests of every group inside the NRV range, per polygon", {
  cmp <- data.frame(
    poly = rep(c("E1", "E2"), c(5, 3)), group = "stand",
    metric = c("ai", "age_Old", "lead_A", "lead_Zero", "forested", "ai", "lead_Zero", "lead_A"),
    position = c("inside", "above", "inside", "inside", "below", "inside", "inside", "inside"),
    tested = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE))
  r <- .nrvInside(cmp)
  expect_identical(names(r), c("poly", "nTests", "nInside", "pctInside"))
  expect_identical(r$poly, c("E1", "E2"))
  expect_identical(r$nTests, c(4L, 2L))
  expect_identical(r$nInside, c(2L, 2L))
  expect_equal(r$pctInside, c(50, 100))
})

test_that("nrvInside.csv is written with one row per polygon", {
  cmp <- data.frame(poly = c("E1", "E1", "E2"), position = c("inside", "below", "inside"), tested = TRUE)
  f <- .writeNrvInside(cmp, withr::local_tempdir())
  expect_identical(basename(f), "nrvInside.csv")
  d <- utils::read.csv(f)
  expect_identical(names(d), c("poly", "nTests", "nInside", "pctInside"))
  expect_equal(d$pctInside, c(50, 100))
})
