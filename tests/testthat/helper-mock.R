# Test helper: serve bundled JSON fixtures via httr2's native response mocking,
# matching on the request URL path. Avoids httptest2's filesystem path mapping
# (which produced non-portable >100-byte paths and brittle lookups).

fixture <- function(name) {
  readChar(test_path("fixtures", name), file.info(test_path("fixtures", name))$size)
}

# Map a URL path substring -> fixture file. First match wins.
mock_router <- function(routes) {
  function(req) {
    path <- httr2::url_parse(req$url)$path
    for (pat in names(routes)) {
      if (grepl(pat, path, fixed = TRUE)) {
        return(httr2::response(
          status_code = 200,
          headers = list(`Content-Type` = "application/json"),
          body = charToRaw(fixture(routes[[pat]]))
        ))
      }
    }
    httr2::response(status_code = 404,
                    headers = list(`Content-Type` = "application/json"),
                    body = charToRaw('{"code":404,"message":"no mock"}'))
  }
}

with_mocks <- function(routes, code) {
  httr2::local_mocked_responses(mock_router(routes), env = parent.frame())
  force(code)
}
