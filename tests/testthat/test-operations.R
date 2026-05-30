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

test_that("as_sf converts to sf when available", {
  skip_if_not_installed("sf")
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/files/geojson" = "full.geojson"), {
    obj <- as_sf(tl_dataset(cl, "nl-domino-poi"))
    expect_s3_class(obj, "sf")
  })
})

test_that("addon-required errors surface as a typed condition", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 403,
      headers = list(`Content-Type` = "application/json"),
      body = charToRaw('{"statusCode":403,"message":"This endpoint requires the API_ACCESS add-on"}')
    )
  })
  ds <- tl_dataset(cl, "nl-domino-poi")
  err <- tryCatch(tl_geojson(ds), topolab_addon_required_error = function(e) e)
  expect_s3_class(err, "topolab_addon_required_error")
  expect_equal(err$addon, "API_ACCESS")
})
