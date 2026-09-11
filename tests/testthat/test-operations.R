test_that("tl_datasets lists catalog", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/v1/dataset/all" = "catalog.json"), {
    page <- tl_datasets(cl, limit = 20)
    expect_equal(page$meta$totalItems, 1)
    expect_equal(page$data[[1]]$table, "nl-domino-poi")
  })
})

test_that("tl_items addresses the collection by slug and returns a FeatureCollection", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/v1/ogc/collections/" = "items.json"), {
    ds <- tl_dataset(cl, "nl-domino-poi")
    fc <- tl_items(ds, bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
    expect_equal(fc$type, "FeatureCollection")
    expect_true(length(fc$features) > 0)
  })
})

test_that("tl_items is slug-direct (no metadata round-trip)", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  meta_calls <- 0L
  item_path <- NA_character_
  httr2::local_mocked_responses(function(req) {
    path <- httr2::url_parse(req$url)$path
    if (grepl("/v1/ogc/collections/", path, fixed = TRUE)) {
      item_path <<- path
      return(httr2::response(200, headers = list(`Content-Type` = "application/json"),
                             body = charToRaw(fixture("items.json"))))
    }
    meta_calls <<- meta_calls + 1L
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(fixture("metadata.json")))
  })
  ds <- tl_dataset(cl, "nl-domino-poi")
  tl_items(ds, limit = 100)
  tl_items(ds, limit = 10)
  expect_equal(meta_calls, 0L) # collectionId IS the slug — no metadata round-trip
  expect_true(grepl("/v1/ogc/collections/nl-domino-poi/items", item_path, fixed = TRUE))
})

# Offset-aware items mock that reports a consistent `numberMatched`
# (= full_pages * features-per-page). The parallel pager is driven by
# numberMatched, and the sequential pager stops on the empty page, so both see
# the same total. `page` is the parsed items.json fixture (one page of features).
.paginating_mock <- function(page, full_pages = 2) {
  per <- length(page$features)
  total <- per * full_pages
  page$numberMatched <- total
  empty <- list(type = "FeatureCollection", numberMatched = total, features = list())
  function(req) {
    path <- httr2::url_parse(req$url)$path
    if (grepl("/v1/dataset/", path, fixed = TRUE)) {
      return(httr2::response(200, headers = list(`Content-Type` = "application/json"),
                             body = charToRaw(fixture("metadata.json"))))
    }
    offset <- as.integer(httr2::url_parse(req$url)$query$offset %||% "0")
    body <- jsonlite::toJSON(if (offset < total) page else empty, auto_unbox = TRUE)
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(body))
  }
}

test_that("tl_items_all concatenates pages until an empty page", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  page <- jsonlite::fromJSON(fixture("items.json"), simplifyVector = FALSE)
  httr2::local_mocked_responses(.paginating_mock(page))
  all <- tl_items_all(tl_dataset(cl, "nl-domino-poi"), page_size = 2)
  expect_equal(length(all$features), 4) # 2 pages x 2 features
})

test_that("tl_items_all honours total_limit", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  page <- jsonlite::fromJSON(fixture("items.json"), simplifyVector = FALSE)
  httr2::local_mocked_responses(.paginating_mock(page))
  capped <- tl_items_all(tl_dataset(cl, "nl-domino-poi"), page_size = 2, total_limit = 3)
  expect_equal(length(capped$features), 3)
})

test_that("tl_items_all fetches remaining pages in parallel (driven by numberMatched)", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  page <- jsonlite::fromJSON(fixture("items.json"), simplifyVector = FALSE) # numberMatched=4, 2 feats
  httr2::local_mocked_responses(.paginating_mock(page))
  # page_size 2, numberMatched 4 => 1 first page + 1 parallel page = 4 features.
  all <- tl_items_all(tl_dataset(cl, "nl-domino-poi"), page_size = 2, parallel = TRUE)
  expect_equal(length(all$features), 4)
})

test_that("tl_items_all parallel = FALSE pages sequentially to the same result", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  page <- jsonlite::fromJSON(fixture("items.json"), simplifyVector = FALSE)
  httr2::local_mocked_responses(.paginating_mock(page))
  all <- tl_items_all(tl_dataset(cl, "nl-domino-poi"), page_size = 2, parallel = FALSE)
  expect_equal(length(all$features), 4)
})

test_that("tl_geojson returns a parsed FeatureCollection", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/files/geojson" = "full.geojson"), {
    fc <- tl_geojson(tl_dataset(cl, "nl-domino-poi"))
    expect_equal(fc$type, "FeatureCollection")
    expect_equal(length(fc$features), 2)
  })
})

test_that("tl_download rejects an unsupported format without a round trip", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    httr2::response(200, headers = list(`Content-Type` = "application/geo+json"),
                    body = charToRaw("{}"))
  })
  path <- withr::local_tempfile(fileext = ".gpkg")
  expect_error(tl_download(tl_dataset(cl, "nl-domino-poi"), path, format = "gpkg"),
               class = "topolab_validation_error")
  expect_equal(calls, 0L)
})

test_that("as_sf converts to sf when available", {
  skip_if_not_installed("sf")
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/files/geojson" = "full.geojson"), {
    obj <- as_sf(tl_dataset(cl, "nl-domino-poi"))
    expect_s3_class(obj, "sf")
  })
})

# The engine's error envelope is {code, message, path, method, time, requestId} —
# there is no `statusCode` field, so the mapping branches on the HTTP status.
.error_mock <- function(status, message, headers = list(), request_id = "req-1") {
  function(req) {
    body <- jsonlite::toJSON(
      list(code = status, message = message, path = "/v1/dataset/x", method = "GET",
           time = "2026-09-08T23:42:15.819Z", requestId = request_id),
      auto_unbox = TRUE)
    httr2::response(status_code = status,
                    headers = c(list(`Content-Type` = "application/json"), headers),
                    body = charToRaw(body))
  }
}

test_that("addon-required errors surface as a typed condition (endpoint phrasing)", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
  httr2::local_mocked_responses(
    .error_mock(403, "This endpoint requires the api-access add-on"))
  err <- tryCatch(tl_geojson(tl_dataset(cl, "nl-domino-poi")),
                  topolab_addon_required_error = function(e) e)
  expect_s3_class(err, "topolab_addon_required_error")
  expect_equal(err$addon, "api-access")   # hyphenated slug survives the capture
  expect_equal(err$status, 403)
})

test_that("addon-required errors surface as a typed condition (archive phrasing)", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
  httr2::local_mocked_responses(.error_mock(
    403,
    "Archive access requires the Archived Data add-on. Please upgrade to access historical data."))
  err <- tryCatch(tl_archives(tl_dataset(cl, "nl-domino-poi")),
                  topolab_addon_required_error = function(e) e)
  expect_s3_class(err, "topolab_addon_required_error")
  expect_equal(err$addon, "archived-data")   # spaced, title-cased name normalises
})

test_that("a 403 without an add-on message is an access denial", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
  httr2::local_mocked_responses(
    .error_mock(403, "Your organization does not have access to this dataset"))
  err <- tryCatch(tl_geojson(tl_dataset(cl, "nl-domino-poi")),
                  topolab_access_denied_error = function(e) e)
  expect_s3_class(err, "topolab_access_denied_error")
  expect_null(err$addon)
})

test_that("the request id comes from the header, falling back to the body", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
  httr2::local_mocked_responses(.error_mock(
    404, "Archive file not found for 2026-13 in csv format",
    headers = list(`X-Request-Id` = "from-header"), request_id = "from-body"))
  err <- tryCatch(tl_metadata(tl_dataset(cl, "nl-domino-poi")),
                  topolab_not_found_error = function(e) e)
  expect_equal(err$request_id, "from-header")

  httr2::local_mocked_responses(.error_mock(404, "not found", request_id = "from-body"))
  err <- tryCatch(tl_metadata(tl_dataset(cl, "nl-domino-poi")),
                  topolab_not_found_error = function(e) e)
  expect_equal(err$request_id, "from-body")
})
