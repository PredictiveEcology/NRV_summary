## `userReportingLayers`: the user's own reporting polygons, clipped to the reporting area like the national layers.

sq <- function(x0, y0, x1, y1) sprintf("POLYGON ((%s %s, %s %s, %s %s, %s %s, %s %s))", x0, y0, x1, y0, x1, y1, x0, y1, x0, y0)
crsSA <- "EPSG:3347" # Statistics Canada Lambert
sar <- terra::vect(sq(0, 0, 10000, 10000), crs = crsSA)

## A inside (two features, one unit), B half outside
userLayer <- function() {
  v <- terra::vect(c(sq(1000, 1000, 3000, 3000), sq(3000, 1000, 4000, 2000), sq(5000, 5000, 15000, 7000)), crs = crsSA)
  v$eco <- c("A", "A", "B")
  v
}

test_that("a user layer is clipped to the reporting area, transformed, and dissolved by its label", {
  userLayers <- moduleFn(".userLayers", new.env())
  f <- file.path(withr::local_tempdir(), "user.gpkg")
  terra::writeVector(terra::project(userLayer(), "EPSG:4269"), f) # read from file, another CRS
  out <- userLayers(list(Mine = list(x = f, label = "eco")), sar)
  expect_named(out, "Mine")
  v <- out$Mine
  expect_true(terra::same.crs(v, sar))
  expect_setequal(v$Name, c("A", "B"))
  a <- setNames(terra::expanse(v, transform = FALSE), v$Name)
  expect_equal(unname(a["A"]), 5e6, tolerance = 0.01) # 4e6 + 1e6, one unit
  expect_equal(unname(a["B"]), 1e7, tolerance = 0.01) # the half inside (5 km x 2 km)
})

test_that("without a label each feature is its own unit; sf is accepted", {
  userLayers <- moduleFn(".userLayers", new.env())
  out <- userLayers(list(Mine = sf::st_as_sf(userLayer())), sar)
  expect_setequal(out$Mine$Name, c("1", "2", "3"))
})

test_that("a layer outside the reporting area is skipped with a message", {
  userLayers <- moduleFn(".userLayers", new.env())
  far <- terra::vect(sq(50000, 50000, 60000, 60000), crs = crsSA)
  far$eco <- "far"
  expect_message(out <- userLayers(list(Far = list(x = far, label = "eco"), Mine = userLayer()), sar),
                 "Far does not intersect")
  expect_named(out, "Mine")
})

test_that("bad names and labels fail clearly", {
  userLayers <- moduleFn(".userLayers", new.env())
  expect_error(userLayers(list(userLayer()), sar), "unique names")
  expect_error(userLayers(list(Intact = userLayer()), sar, taken = "Intact"), "unique names")
  expect_error(userLayers(list(Mine = list(x = userLayer(), label = "nope")), sar), "no column")
})
