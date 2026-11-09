# Follow-ups to engine #650 (429s carry a string code, details and a
# Retry-After header) and to out-of-range numeric codes.

.raw_mock <- function(status, json, headers = list()) {
  function(req) {
    httr2::response(status_code = status,
                    headers = c(list(`Content-Type` = "application/json"), headers),
                    body = charToRaw(json))
  }
}

# Serve the given responses in order, one per request.
.sequence_mock <- function(...) {
  responses <- list(...)
  i <- 0L
  function(req) {
    i <<- i + 1L
    responses[[min(i, length(responses))]]
  }
}

.resp <- function(status, json, headers = list()) {
  httr2::response(status_code = status,
                  headers = c(list(`Content-Type` = "application/json"), headers),
                  body = charToRaw(json))
}

.rate_limited_json <- '{"code": "RATE_LIMIT_EXCEEDED", "message": "Rate limit exceeded",
  "details": {"retryAfter": 42, "limit": 300, "remaining": 0,
              "resetAt": "2026-11-07T12:01:00.000Z"}, "requestId": "r429"}'

.quota_json <- '{"code": "USAGE_QUOTA_EXCEEDED", "message": "API key usage quota exceeded",
  "details": {"quota": 10, "used": 10}, "requestId": "q429"}'

.metadata_ok <- '{"id": "uuid-1", "table": "nl-domino-poi"}'

.no_retry_client <- function() {
  tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 0)
}

test_that("a numeric code too large for an integer falls back to the status", {
  for (json in c('{"code": 2147483648, "message": "x"}', '{"code": -2147483649, "message": "x"}',
                 '{"code": 1e300, "message": "x"}')) {
    httr2::local_mocked_responses(.raw_mock(403, json))
    expect_no_warning(
      err <- tryCatch(tl_metadata(tl_dataset(.no_retry_client(), "nl-domino-poi")),
                      topolab_error = function(e) e)
    )
    expect_identical(err$code, 403L, info = json)
  }
})

test_that("a 429 takes its wait from details.retryAfter and keeps the code", {
  httr2::local_mocked_responses(.raw_mock(429, .rate_limited_json))
  err <- tryCatch(tl_metadata(tl_dataset(.no_retry_client(), "nl-domino-poi")),
                  topolab_rate_limit_error = function(e) e)
  expect_s3_class(err, "topolab_rate_limit_error")
  expect_identical(err$code, "RATE_LIMIT_EXCEEDED")
  expect_equal(err$retry_after, 42)
  expect_equal(err$details$limit, 300)
})

test_that("a 429 prefers the Retry-After header", {
  httr2::local_mocked_responses(.raw_mock(429, .rate_limited_json, list(`Retry-After` = "43")))
  err <- tryCatch(tl_metadata(tl_dataset(.no_retry_client(), "nl-domino-poi")),
                  topolab_rate_limit_error = function(e) e)
  expect_equal(err$retry_after, 43)
})

test_that("a used-up quota has no wait but keeps its details", {
  httr2::local_mocked_responses(.raw_mock(429, .quota_json))
  err <- tryCatch(tl_metadata(tl_dataset(.no_retry_client(), "nl-domino-poi")),
                  topolab_rate_limit_error = function(e) e)
  expect_identical(err$code, "USAGE_QUOTA_EXCEEDED")
  expect_null(err$retry_after)
  expect_equal(err$details, list(quota = 10L, used = 10L))
})

test_that("the wait is read from the header, then details, then the older body field", {
  expect_equal(.tl_retry_after(.resp(429, .rate_limited_json, list(`Retry-After` = "9"))), 9)
  expect_equal(.tl_retry_after(.resp(429, .rate_limited_json)), 42)
  expect_equal(.tl_retry_after(.resp(429, '{"message": "x", "retryAfter": 5}')), 5)
  expect_true(is.na(.tl_retry_after(.resp(429, .quota_json))))
  expect_true(is.na(.tl_retry_after(.resp(503, "<html>down</html>"))))
  expect_true(is.na(.tl_retry_after(.resp(429, '{"details": {"retryAfter": -1}}'))))
})

# A proxy can send a Retry-After that is neither seconds nor an HTTP date. That
# is not a usable wait: the body's wait applies, or NA, and nothing warns (the
# function is also the req_retry() callback, so a warning would reach the caller
# on every retry).
test_that("an unusable Retry-After header is skipped without a warning", {
  expect_no_warning(
    wait <- .tl_retry_after(.resp(429, '{"code": 429}', list(`Retry-After` = "soon")))
  )
  expect_true(is.na(wait))
  expect_no_warning(
    wait <- .tl_retry_after(.resp(429, .rate_limited_json, list(`Retry-After` = "soon")))
  )
  expect_equal(wait, 42)
  expect_no_warning(
    wait <- .tl_retry_after(.resp(429, '{"code": 429}', list(`Retry-After` = "Someday, maybe")))
  )
  expect_true(is.na(wait))
})

test_that("a Retry-After HTTP date is measured against the Date header", {
  wait <- .tl_retry_after(.resp(429, '{"code": 429}', list(
    `Retry-After` = "Sat, 07 Nov 2026 12:01:30 GMT",
    Date = "Sat, 07 Nov 2026 12:01:00 GMT"
  )))
  expect_equal(wait, 30)
})

# httr2 mocks bypass req_retry(), so the retry policy is checked directly. httr2
# requires the `after` callback to return a single number or NA; returning NULL
# (as 0.2.0 did whenever the body had no top-level retryAfter) makes httr2 abort
# instead of retrying.
test_that("the retry policy always returns a single number or NA", {
  cl <- tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
  after <- tl_req(cl, "/v1/dataset/nl-domino-poi")$policies$retry_after
  responses <- list(
    .resp(429, .rate_limited_json),
    .resp(429, .quota_json),
    .resp(503, '{"code": 503, "message": "down"}'),
    .resp(502, "<html>bad gateway</html>"),
    .resp(429, '{"code": 429}', list(`Retry-After` = "7"))
  )
  for (r in responses) {
    v <- after(r)
    expect_true(is.numeric(v) && length(v) == 1L)
  }
  expect_equal(after(responses[[1]]), 42)
  expect_true(is.na(after(responses[[3]])))
  expect_equal(after(responses[[5]]), 7)
})
