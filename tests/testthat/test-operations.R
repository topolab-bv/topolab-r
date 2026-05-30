test_that("tl_datasets lists catalog", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httptest2::with_mock_dir(test_path("fixtures/catalog"), {
    page <- tl_datasets(cl, limit = 20)
    expect_equal(page$meta$totalItems, 1)
    expect_equal(page$data[[1]]$table, "nl-domino-poi")
  })
})

test_that("tl_items resolves slug to collection id and returns a FeatureCollection", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httptest2::with_mock_dir(test_path("fixtures/items"), {
    ds <- tl_dataset(cl, "nl-domino-poi")
    fc <- tl_items(ds, bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
    expect_equal(fc$type, "FeatureCollection")
    expect_true(length(fc$features) > 0)
  })
})

test_that("as_sf converts to sf when available", {
  skip_if_not_installed("sf")
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  httptest2::with_mock_dir(test_path("fixtures/geojson"), {
    obj <- as_sf(tl_dataset(cl, "nl-domino-poi"))
    expect_s3_class(obj, "sf")
  })
})
