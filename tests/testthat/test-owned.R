# Owned datasets, archives, coordinates and SQL — the backend integration loop.
# Fixtures are the golden bodies from the SDK spec (`fixtures/owned/`).

# Offset-aware /v1/dataset/owned mock over a synthetic catalogue of `total`
# datasets, so paging can be checked for repeats, gaps and termination.
.owned_mock <- function(total, requests = NULL) {
  function(req) {
    query <- httr2::url_parse(req$url)$query
    limit <- as.integer(query$limit %||% "50")
    offset <- as.integer(query$offset %||% "0")
    if (!is.null(requests)) requests$offsets <- c(requests$offsets, offset)
    idx <- seq_len(total)
    idx <- idx[idx > offset][seq_len(min(limit, max(total - offset, 0)))]
    idx <- idx[!is.na(idx)]
    items <- lapply(idx, function(i) list(table = sprintf("ds_%03d", i), name = paste("Dataset", i)))
    body <- jsonlite::toJSON(
      list(items = items, total = total, limit = limit, offset = offset),
      auto_unbox = TRUE
    )
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(body))
  }
}

test_that("tl_datasets_owned returns the page, the full total and nested links", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/v1/dataset/owned" = "owned.json"), {
    page <- tl_datasets_owned(cl, limit = 2)
    expect_equal(page$total, 193)          # every licensed dataset, not the page
    expect_equal(page$limit, 2)
    expect_equal(page$offset, 0)
    expect_equal(length(page$items), 2)
    first <- page$items[[1]]
    expect_equal(first$table, "business_professional_services_autocrew")
    expect_equal(first$latestArchiveMonth, "2026-07")
    expect_equal(first$archiveMonthsAvailable, 11)
    # links stay nested and absolute, with the literal {format} placeholder
    expect_true(grepl("^https://", first$links$archives))
    expect_true(grepl("{format}", first$links$current, fixed = TRUE))
    expect_true(grepl("{format}", first$links$latestArchive, fixed = TRUE))
  })
})

test_that("tl_datasets_owned validates limit and offset client-side", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  expect_error(tl_datasets_owned(cl, limit = 201), class = "topolab_validation_error")
  expect_error(tl_datasets_owned(cl, limit = 0), class = "topolab_validation_error")
  expect_error(tl_datasets_owned(cl, offset = -1), class = "topolab_validation_error")
})

test_that("tl_datasets_owned_all pages the whole catalogue without repeats or gaps", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  seen <- new.env()
  seen$offsets <- integer(0)
  httr2::local_mocked_responses(.owned_mock(23, seen))
  all <- tl_datasets_owned_all(cl, page_size = 10)
  tables <- vapply(all, function(d) d$table, character(1))
  expect_equal(length(tables), 23)
  expect_equal(anyDuplicated(tables), 0L)
  expect_equal(tables, sprintf("ds_%03d", 1:23))   # ordered, no gaps
  expect_equal(attr(all, "total"), 23)
  expect_equal(seen$offsets, c(0L, 10L, 20L))      # terminates on the short page
})

test_that("tl_datasets_owned_all stops on an exact-multiple total", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  seen <- new.env()
  seen$offsets <- integer(0)
  httr2::local_mocked_responses(.owned_mock(20, seen))
  all <- tl_datasets_owned_all(cl, page_size = 10)
  expect_equal(length(all), 20)
  # `total` is reached exactly, so no wasted request for an empty third page
  expect_equal(seen$offsets, c(0L, 10L))
})

test_that("tl_datasets_owned_all honours total_limit", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(.owned_mock(23))
  capped <- tl_datasets_owned_all(cl, page_size = 10, total_limit = 12)
  expect_equal(length(capped), 12)
  expect_equal(vapply(capped, function(d) d$table, character(1)), sprintf("ds_%03d", 1:12))
})

test_that("tl_datasets_owned_all handles an empty catalogue", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(.owned_mock(0))
  all <- tl_datasets_owned_all(cl)
  expect_equal(length(all), 0)
  expect_equal(attr(all, "total"), 0)
})

test_that("tl_archives lists months newest first", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/archives/list" = "archives.json"), {
    archives <- tl_archives(tl_dataset(cl, "business_professional_services_autocrew"))
    months <- vapply(archives, function(a) a$month, character(1))
    expect_equal(length(months), 11)
    expect_equal(months[1], "2026-07")
    expect_equal(months, sort(months, decreasing = TRUE))   # newest first
    expect_true("shp" %in% unlist(archives[[1]]$formats))
    expect_equal(archives[[1]]$archiveDate, "2026-07-01")
  })
})

# httr2's mock layer returns the mocked response before `req_perform()` ever
# looks at its `path=` argument, so a mocked download writes no file and
# `expect_true(file.exists(path))` here can never pass — do not "fix" these
# tests by adding one. What they assert instead is the URL the download streams
# from and the returned path; the rename warning from the absent stream is a
# mocking artefact and is suppressed.
test_that("tl_archive addresses the requested month and format", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  requested <- NA_character_
  httr2::local_mocked_responses(function(req) {
    requested <<- httr2::url_parse(req$url)$path
    httr2::response(200, headers = list(`Content-Type` = "application/zip"),
                    body = charToRaw("PK"))
  })
  path <- withr::local_tempfile(fileext = ".zip")
  out <- suppressWarnings(
    tl_archive(tl_dataset(cl, "nl-domino-poi"), path, month = "2026-07", format = "csv"))
  expect_equal(out, path)
  expect_equal(requested, "/v1/dataset/nl-domino-poi/archives/2026-07/csv")
})

test_that("tl_archive normalises 'latest' and defaults to the newest geojson", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  requested <- NA_character_
  httr2::local_mocked_responses(function(req) {
    requested <<- httr2::url_parse(req$url)$path
    httr2::response(200, headers = list(`Content-Type` = "application/zip"),
                    body = charToRaw("PK"))
  })
  path <- withr::local_tempfile(fileext = ".zip")
  suppressWarnings(tl_archive(tl_dataset(cl, "nl-domino-poi"), path, month = "LATEST"))
  expect_equal(requested, "/v1/dataset/nl-domino-poi/archives/latest/geojson")
})

test_that("tl_archive accepts the three month forms", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = list(`Content-Type` = "application/zip"),
                    body = charToRaw("PK"))
  })
  ds <- tl_dataset(cl, "nl-domino-poi")
  for (month in c("latest", "Latest", "2026-07", "2026-07-15", "2024-02-29", "1999-12-31")) {
    path <- withr::local_tempfile(fileext = ".zip")
    expect_equal(suppressWarnings(tl_archive(ds, path, month = month, format = "csv")), path)
  }
})

test_that("tl_archive rejects malformed and impossible months without a round trip", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    httr2::response(200, headers = list(`Content-Type` = "application/zip"),
                    body = charToRaw("PK"))
  })
  ds <- tl_dataset(cl, "nl-domino-poi")
  path <- withr::local_tempfile(fileext = ".zip")
  bad <- c("julyish", "2026-13", "2026-00", "2026-07-99", "2026-07-00",
           "2026-02-29",   # 2026 is not a leap year
           "2026-7", "2026", "26-07", "2026-07-01x", "", "latest ")
  for (month in bad) {
    expect_error(tl_archive(ds, path, month = month),
                 class = "topolab_validation_error", info = month)
  }
  expect_equal(calls, 0L)
})

test_that("tl_archive rejects an unsupported format", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  path <- withr::local_tempfile(fileext = ".zip")
  expect_error(tl_archive(tl_dataset(cl, "nl-domino-poi"), path, format = "gpkg"),
               class = "topolab_validation_error")
})

# Coordinates responses carry their paging facts in headers, not an envelope.
.coordinates_mock <- function(headers) {
  function(req) {
    httr2::response(200,
                    headers = c(list(`Content-Type` = "application/json"), headers),
                    body = charToRaw(fixture("coordinates.json")))
  }
}

test_that("tl_coordinates attaches the paging headers and keeps lat/lon as strings", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(.coordinates_mock(list(
    `X-Total-Count` = "119", `X-Returned-Count` = "2", `X-Offset` = "40"
  )))
  rows <- tl_coordinates(tl_dataset(cl, "business_professional_services_autocrew"),
                         limit = 2, offset = 40)
  expect_equal(length(rows), 2)
  expect_equal(attr(rows, "total"), 119L)
  expect_equal(attr(rows, "returned"), 2L)
  expect_equal(attr(rows, "offset"), 40L)
  # latitude/longitude arrive as JSON strings and are not coerced
  expect_type(rows[[1]]$latitude, "character")
  expect_equal(rows[[1]]$latitude, "51.49638600")
  expect_equal(rows[[1]]$location$type, "Point")
  expect_equal(rows[[1]]$metadata$city, "Middelburg")
})

test_that("tl_coordinates falls back when the paging headers are missing", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(.coordinates_mock(list()))
  rows <- tl_coordinates(tl_dataset(cl, "nl-domino-poi"))
  expect_equal(attr(rows, "total"), 2L)      # falls back to the row count
  expect_equal(attr(rows, "returned"), 2L)
  expect_equal(attr(rows, "offset"), 0L)
})

test_that("tl_coordinates ignores unparseable paging headers", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(.coordinates_mock(list(
    `X-Total-Count` = "many", `X-Returned-Count` = "", `X-Offset` = "n/a"
  )))
  rows <- tl_coordinates(tl_dataset(cl, "nl-domino-poi"))
  expect_equal(attr(rows, "total"), 2L)
  expect_equal(attr(rows, "returned"), 2L)
  expect_equal(attr(rows, "offset"), 0L)
})

test_that("tl_coordinates validates limit and offset client-side", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  ds <- tl_dataset(cl, "nl-domino-poi")
  expect_error(tl_coordinates(ds, limit = 50001), class = "topolab_validation_error")
  expect_error(tl_coordinates(ds, limit = 0), class = "topolab_validation_error")
  expect_error(tl_coordinates(ds, offset = -1), class = "topolab_validation_error")
})

test_that("tl_sql posts the query and returns a data frame with result metadata", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  sent <- NULL
  method <- NA_character_
  path <- NA_character_
  httr2::local_mocked_responses(function(req) {
    method <<- httr2::req_get_method(req)
    path <<- httr2::url_parse(req$url)$path
    sent <<- req$body$data
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(fixture("sql-result.json")))
  })
  df <- tl_sql(cl, "SELECT city, count(*) AS n FROM t GROUP BY city", max_rows = 500)

  expect_equal(method, "POST")
  expect_equal(path, "/v1/sql/query")
  expect_equal(sent$sql, "SELECT city, count(*) AS n FROM t GROUP BY city")
  expect_equal(sent$maxRows, 500L)

  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), 2)
  expect_equal(names(df), c("city", "n"))
  expect_equal(df$city, c("Amsterdam", "Rotterdam"))
  expect_equal(df$n, c(412, 233))
  expect_equal(attr(df, "row_count"), 2)
  expect_false(attr(df, "truncated"))
  expect_equal(attr(df, "elapsed_ms"), 41.7)
  expect_equal(attr(df, "datasets"), "business_professional_services_autocrew")
})

test_that("tl_sql omits maxRows when it is not set", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  sent <- NULL
  httr2::local_mocked_responses(function(req) {
    sent <<- req$body$data
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(fixture("sql-result.json")))
  })
  tl_sql(cl, "SELECT 1")
  expect_equal(names(sent), "sql")
})

test_that("tl_sql returns an empty frame with the declared columns", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(function(req) {
    body <- '{"columns":["city","n"],"rows":[],"rowCount":0,"truncated":false,"elapsedMs":3,"datasets":[]}'
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(body))
  })
  df <- tl_sql(cl, "SELECT city, n FROM t WHERE false")
  expect_equal(nrow(df), 0)
  expect_equal(names(df), c("city", "n"))
  expect_equal(attr(df, "columns"), c("city", "n"))
})

test_that("tl_sql keeps JSON nulls as NA and validates its arguments", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httr2::local_mocked_responses(function(req) {
    body <- '{"columns":["a","b"],"rows":[{"a":1,"b":null},{"a":2,"b":"x"}],"rowCount":2,"truncated":true,"elapsedMs":9,"datasets":["t"]}'
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(body))
  })
  df <- tl_sql(cl, "SELECT a, b FROM t")
  expect_equal(df$a, c(1, 2))
  expect_true(is.na(df$b[1]))
  expect_true(attr(df, "truncated"))

  expect_error(tl_sql(cl, "   "), class = "topolab_validation_error")
  expect_error(tl_sql(cl, "SELECT 1", max_rows = 0), class = "topolab_validation_error")
  expect_error(tl_sql(cl, "SELECT 1", max_rows = 10001), class = "topolab_validation_error")
})

test_that("a SQL query over the server time limit raises a query-timeout condition", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 0)
  httr2::local_mocked_responses(function(req) {
    httr2::response(408, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(paste0(
                      '{"code":408,"message":"Query exceeded the server time limit",',
                      '"path":"/v1/sql/query","method":"POST","requestId":"abc123"}')))
  })
  err <- tryCatch(tl_sql(cl, "SELECT pg_sleep(60)"),
                  topolab_query_timeout_error = function(e) e)
  expect_s3_class(err, "topolab_query_timeout_error")
  expect_s3_class(err, "topolab_error")
  expect_equal(err$status, 408)
  expect_equal(err$request_id, "abc123")
})
