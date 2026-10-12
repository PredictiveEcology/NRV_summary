## render_one runs detached from the module namespace, so every module helper it calls must be
## re-assigned into its environment by .renderTasks(). An envelope task with an NRV period calls
## .addCurrentCondition and .addNrvShading. A package attached on the search path (as load_all does)
## would hide a missing one, because the detached environment sits under globalenv(), so the test
## runs with the package detached, as it is in a simulation.

test_that(".renderTasks() renders an envelope figure with NRV shading and a current condition", {
  g <- expand.grid(time = c(100, 200, 300), class = "Pine", stringsAsFactors = FALSE)
  df <- data.frame(time = g$time, poly = "ELF", class = g$class, metric = "area_mn", metric.1 = NA_character_,
                   mean = 10, min = 8, max = 12, q25 = 9, median = 10, q75 = 11)
  cc <- data.frame(poly = "ELF", class = "Pine", metric = "area_mn", metric.1 = NA_character_, mean = 11)
  file <- file.path(withr::local_tempdir(), "env.png")
  task <- list(plotter = "envelope", df = df, type = "ribbon", facet = c("class", "metric.1"),
               ylab = "y", title = "t", page = NULL, nrvPeriod = c(200, 300), cc = cc,
               file = file, width = 5, height = 4)
  pkgEnv <- paste0("package:", getNamespaceName(topenv(environment(.renderTasks))))
  if (pkgEnv %in% search()) {
    attached <- as.environment(pkgEnv)
    pos <- match(pkgEnv, search())
    detach(pkgEnv, character.only = TRUE)
    withr::defer(attach(attached, pos = pos, name = pkgEnv, warn.conflicts = FALSE))
  }
  testthat::local_mocked_bindings(.plotWorkers = function(sim, nTasks) 1L)
  out <- .renderTasks(NULL, list(task))
  expect_equal(out, file)
  expect_true(file.exists(file))
})
