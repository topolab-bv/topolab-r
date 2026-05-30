test_that("tl_client reads key and builds base url", {
  cl <- tl_client(api_key = "tlb_test_x", base_url = "https://api.topolab.nl")
  expect_equal(cl$api_key, "tlb_test_x")
  expect_equal(cl$base_url, "https://api.topolab.nl")
})

test_that("tl_client errors without a key", {
  withr::local_envvar(TOPOLAB_API_KEY = "")
  expect_error(tl_client(), "API key")
})

test_that("tl_client defaults to production", {
  withr::local_envvar(TOPOLAB_BASE_URL = "", TOPOLAB_ENV = "")
  expect_equal(tl_client(api_key = "k")$base_url, "https://api.topolab.nl")
})

test_that("tl_client selects staging via environment", {
  withr::local_envvar(TOPOLAB_BASE_URL = "", TOPOLAB_ENV = "")
  expect_equal(tl_client(api_key = "k", environment = "staging")$base_url,
               "https://api-staging.topolab.nl")
})

test_that("tl_client errors on an unknown environment", {
  expect_error(tl_client(api_key = "k", environment = "dev"), "Unknown environment")
})

test_that("TOPOLAB_ENV env var selects staging", {
  withr::local_envvar(TOPOLAB_BASE_URL = "", TOPOLAB_ENV = "staging")
  expect_equal(tl_client(api_key = "k")$base_url, "https://api-staging.topolab.nl")
})

test_that("explicit base_url beats environment", {
  withr::local_envvar(TOPOLAB_BASE_URL = "", TOPOLAB_ENV = "")
  cl <- tl_client(api_key = "k", base_url = "https://self.example/api", environment = "staging")
  expect_equal(cl$base_url, "https://self.example/api")
})

test_that("base_url rejects plain-http remote", {
  expect_error(tl_client(api_key = "k", base_url = "http://evil.example/api"), "https")
})

test_that("base_url rejects embedded credentials", {
  expect_error(tl_client(api_key = "k", base_url = "https://user:pass@evil.example"), "credentials")
})

test_that("base_url rejects a non-http(s) scheme", {
  expect_error(tl_client(api_key = "k", base_url = "ftp://api.topolab.nl"), "http")
})

test_that("base_url allows plain-http loopback", {
  cl <- tl_client(api_key = "k", base_url = "http://127.0.0.1:8080")
  expect_equal(cl$base_url, "http://127.0.0.1:8080")
})

test_that("TOPOLAB_BASE_URL env is validated", {
  withr::local_envvar(TOPOLAB_BASE_URL = "http://evil.example", TOPOLAB_ENV = "")
  expect_error(tl_client(api_key = "k"), "https")
})

test_that("tl_metadata returns parsed fields", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl")
  with_mocks(list("/v1/dataset/nl-domino-poi" = "metadata.json"), {
    md <- tl_metadata(tl_dataset(cl, "nl-domino-poi"))
    expect_equal(md$table, "nl-domino-poi")
    expect_true(nzchar(md$id))
  })
})
