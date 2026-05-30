test_that("tl_client reads key and builds base url", {
  cl <- tl_client(api_key = "tlb_test_x", base_url = "https://api.topolab.nl")
  expect_equal(cl$api_key, "tlb_test_x")
  expect_equal(cl$base_url, "https://api.topolab.nl")
})

test_that("tl_client errors without a key", {
  withr::local_envvar(TOPOLAB_API_KEY = "")
  expect_error(tl_client(), "API key")
})

test_that("tl_metadata returns parsed fields", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/v1/dataset/nl-domino-poi" = "metadata.json"), {
    md <- tl_metadata(tl_dataset(cl, "nl-domino-poi"))
    expect_equal(md$table, "nl-domino-poi")
    expect_true(nzchar(md$id))
  })
})
