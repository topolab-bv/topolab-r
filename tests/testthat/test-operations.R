test_that("tl_datasets lists catalog", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/v1/dataset/all" = "catalog.json"), {
    page <- tl_datasets(cl, limit = 20)
    expect_equal(page$meta$totalItems, 1)
    expect_equal(page$data[[1]]$table, "nl-domino-poi")
  })
})

test_that("tl_items resolves slug to collection id and returns a FeatureCollection", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  # metadata lookup (slug -> uuid) then the OGC items call; route by path order
  with_mocks(list(
    "/v1/ogc/collections/" = "items.json",
    "/v1/dataset/nl-domino-poi" = "metadata.json"
  ), {
    ds <- tl_dataset(cl, "nl-domino-poi")
    fc <- tl_items(ds, bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
    expect_equal(fc$type, "FeatureCollection")
    expect_true(length(fc$features) > 0)
  })
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
