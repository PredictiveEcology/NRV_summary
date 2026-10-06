## Figures show full metric names; CSVs and file names keep the codes.

test_that("the landscapemetrics and module codes have full names", {
  codes <- c("ca", "area_sd", "ai", "condent", "iji", "ed", "cohesion", "core_mn", "core_sd", "core_cv",
             "area_mn", "area_cv", "sam_mdn")
  expect_identical(
    unname(.metricLabel(codes)),
    c("Class area", "Patch area SD", "Aggregation index", "Conditional entropy",
      "Interspersion-juxtaposition index", "Edge density", "Patch cohesion index", "Mean core area",
      "Core area SD", "Core area CV", "Mean patch area", "Patch area CV", "Median stand age")
  )
})

test_that("a code without a name is shown as it is", {
  expect_identical(.metricLabel(c("ai", "Npatch_ge100")), c("Aggregation index", "Npatch_ge100"))
})
