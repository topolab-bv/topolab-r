# Since engine #641 the envelope's `code` is a string when the error has its own
# code (upper-snake, such as SPENDING_LIMIT_EXCEEDED) and otherwise the numeric
# HTTP status. Bodies are inlined so these tests do not depend on fixtures that
# land in topolab-sdk-spec separately.

.json_mock <- function(status, json) {
  function(req) {
    httr2::response(status_code = status,
                    headers = list(`Content-Type` = "application/json"),
                    body = charToRaw(json))
  }
}

.spending_limit_json <- '{
  "path": "/v1/dataset/nl-domino-poi/files/geojson", "method": "GET",
  "code": "SPENDING_LIMIT_EXCEEDED",
  "message": "Organization monthly spending limit exceeded",
  "details": {"limit": 5000, "consumed": 4995, "remaining": 5,
              "periodEnd": "2026-11-30T23:59:59.999Z"},
  "time": "2026-11-07T11:52:28.000Z", "requestId": "8f0c41d2"
}'

.credits_json <- '{
  "path": "/v1/dataset/nl-domino-poi/files/geojson", "method": "GET",
  "code": 402, "message": "Insufficient credits",
  "details": {"required": 10, "available": 0},
  "time": "2026-11-07T11:52:28.000Z", "requestId": "6a1b3c5d"
}'

.client <- function() {
  tl_client(api_key = "k", base_url = "https://api.topolab.nl", max_retries = 1)
}

test_that("a string code is kept and the status comes from the response", {
  httr2::local_mocked_responses(.json_mock(403, .spending_limit_json))
  err <- tryCatch(tl_geojson(tl_dataset(.client(), "nl-domino-poi")),
                  topolab_error = function(e) e)
  # The class still follows the HTTP status; the code refines it.
  expect_s3_class(err, "topolab_access_denied_error")
  expect_identical(err$code, "SPENDING_LIMIT_EXCEEDED")
  expect_true(is.character(err$code))
  expect_equal(err$status, 403)
  expect_equal(err$details$limit, 5000)
  expect_equal(err$details$consumed, 4995)
  expect_equal(err$details$remaining, 5)
  expect_identical(err$details$periodEnd, "2026-11-30T23:59:59.999Z")
  expect_identical(err$request_id, "8f0c41d2")
})

test_that("a numeric code is the status and details are exposed", {
  httr2::local_mocked_responses(.json_mock(402, .credits_json))
  err <- tryCatch(tl_geojson(tl_dataset(.client(), "nl-domino-poi")),
                  topolab_error = function(e) e)
  expect_s3_class(err, "topolab_insufficient_credits_error")
  expect_identical(err$code, 402L)
  expect_true(is.numeric(err$code))
  expect_equal(err$status, 402)
  expect_equal(err$details, list(required = 10L, available = 0L))
  expect_equal(err$required, 10)
  expect_equal(err$available, 0)
})

test_that("a string code without details leaves $details NULL", {
  httr2::local_mocked_responses(.json_mock(400, '{
    "path": "/v1/sql/query", "method": "POST", "code": "SQL_DATA_ERROR",
    "message": "The query raised a data error (SQLSTATE 22P02) while evaluating a value.",
    "time": "2026-11-07T11:52:28.000Z", "requestId": "3c5e7a9b"}'))
  err <- tryCatch(tl_sql(.client(), "SELECT 'x'::int"), topolab_error = function(e) e)
  expect_s3_class(err, "topolab_validation_error")
  expect_identical(err$code, "SQL_DATA_ERROR")
  expect_equal(err$status, 400)
  expect_null(err$details)
})

test_that("the code falls back to the HTTP status when the body has none", {
  bodies <- c('{"message": "no code at all"}', '{"code": null, "message": "x"}',
              '{"code": "", "message": "x"}', '{"code": true, "message": "x"}',
              '{"code": {"nested": 1}, "message": "x"}')
  for (b in bodies) {
    httr2::local_mocked_responses(.json_mock(404, b))
    err <- tryCatch(tl_metadata(tl_dataset(.client(), "nl-domino-poi")),
                    topolab_error = function(e) e)
    expect_s3_class(err, "topolab_not_found_error")
    expect_identical(err$code, 404L, info = b)
    expect_null(err$details)
  }
})

test_that("non-object details are ignored", {
  expect_null(.tl_envelope_details(list("a", "b")))
  expect_null(.tl_envelope_details("x"))
  expect_equal(.tl_envelope_details(list(a = 1)), list(a = 1))
})
