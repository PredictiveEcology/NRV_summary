test_that("the module code contains no browser() call", {
  parsed <- parse(file.path(moduleRoot, paste0(moduleName, ".R")), keep.source = TRUE)
  calls <- unlist(lapply(parsed, function(e) all.names(e)))
  expect_false("browser" %in% calls)
})

test_that(".planWithWorkers() does not warn on a sequential plan, and its result restores the plan", {
  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)
  expect_no_warning(prev <- .planWithWorkers(3L))
  expect_true(inherits(future::plan(), "sequential"))
  future::plan(prev) ## what the callers do on exit
  expect_true(inherits(future::plan(), "sequential"))
})
