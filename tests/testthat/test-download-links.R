# tl_download() and tl_archive() through the link route
# (POST /v1/dataset/:table/exports).
#
# The link route answers 200 with a 10-minute signed URL, or 202 while the file
# is being prepared. The SDK fetches the signed URL with a plain
# httr2::request(url) that sends no API key. A server without the route (404,
# or 405) gets today's call to the old route instead, decided on every call.
# 402, 403 and 5xx are raised.
#
# The 404 body is what staging answered on 2026-11-24 for
# POST /v1/dataset/dining_drinking_mcdonalds/exports.

.dl_table <- "dining_drinking_mcdonalds"
.dl_build <- "7d3f6c2a-1b4e-4c8d-9a0f-5e6b7c8d9e0f"
.dl_link <- paste0("POST /v1/dataset/", .dl_table, "/exports")
.dl_files_csv <- paste0("GET /v1/dataset/", .dl_table, "/files/csv")
.dl_archive_csv <- paste0("GET /v1/dataset/", .dl_table, "/archives/2026-11/csv")
.dl_signed_path <- paste0("/platform-staging-datasets/exports/", .dl_table,
                          "/2026-12/standard/20261202T020000Z-a1b2c3d4-w1/",
                          .dl_table, "_2026-12.csv")
.dl_signed_url <- paste0(
  "https://storage.googleapis.com", .dl_signed_path,
  "?X-Goog-Algorithm=GOOG4-RSA-SHA256",
  "&X-Goog-Credential=engine%40example.iam.gserviceaccount.com%2F20261203%2Fauto",
  "%2Fstorage%2Fgoog4_request&X-Goog-Date=20261203T100000Z&X-Goog-Expires=600",
  "&X-Goog-SignedHeaders=host&X-Goog-Signature=5f2d0c9e")
.dl_signed <- paste("GET", .dl_signed_path)
.dl_link_csv <- "id,location_name,city\n1,McDonald's Amsterdam Centraal,Amsterdam\n"
.dl_old_csv <- "id,location_name,city\n1,McDonald's Utrecht Centraal,Utrecht\n"
.dl_zip <- "PK\003\004dining_drinking_mcdonalds_2026-11.csv"

.dl_json <- function(status, body, headers = list()) {
  httr2::response(
    status_code = status,
    headers = c(list(`Content-Type` = "application/json"), headers),
    body = charToRaw(as.character(jsonlite::toJSON(body, auto_unbox = TRUE))))
}
.dl_bytes <- function(status, text, type = "text/csv", headers = list()) {
  httr2::response(status_code = status, headers = c(list(`Content-Type` = type), headers),
                  body = charToRaw(text))
}
.dl_ready <- function(month = "2026-12") {
  .dl_json(200, list(state = "ready", url = .dl_signed_url,
                     expiresAt = "2026-12-03T10:10:00.000Z",
                     filename = paste0(.dl_table, "_", month, ".csv"),
                     bytes = nchar(.dl_link_csv), sha256 = strrep("9b2f6a0c", 8),
                     tier = "standard", month = month, build = .dl_build))
}
.dl_preparing <- function(seconds = 4, headers = list()) {
  body <- list(state = "preparing", build = .dl_build,
               statusUrl = paste0("/v1/dataset/exports/", .dl_build))
  if (!is.null(seconds)) body$retryAfterSeconds <- seconds
  .dl_json(202, body, headers)
}
.dl_no_route <- function() {
  .dl_json(404, list(path = paste0("/v1/dataset/", .dl_table, "/exports"), method = "POST",
                     code = 404L,
                     message = paste0("Cannot POST /v1/dataset/", .dl_table, "/exports"),
                     time = "2026-11-23T23:43:35.228Z",
                     requestId = "2b12c5708156347fdeffee2d7be873a7"))
}
.dl_build_failed <- function() {
  .dl_json(503, list(code = "FILE_BUILD_FAILED", message = "This file could not be built.",
                     details = list(retryAfter = 0L,
                                    linkRoute = paste0("/v1/dataset/", .dl_table, "/exports"))),
           headers = list(`Retry-After` = "0"))
}

.dl_method <- function(req) {
  if (!is.null(req$method)) return(req$method)
  if (!is.null(req$body)) "POST" else "GET"
}

# A mock server: "METHOD /path" -> a list of responses answered in turn (the
# last repeats). Every request is recorded with its headers, JSON body and retry
# policy. An unknown route is a 599, so a stray call fails loudly instead of
# looking like a fallback.
#
# httr2's mocked responses return before req_retry() runs, so a mocked 503 is
# never retried here. The specs assert instead that each request carries
# today's retry policy (4 tries on 429 and 5xx, honouring Retry-After).
.dl_server <- function(routes, env = parent.frame()) {
  state <- new.env()
  state$seen <- list()
  state$served <- list()
  httr2::local_mocked_responses(function(req) {
    route <- paste(.dl_method(req), httr2::url_parse(req$url)$path)
    state$seen[[length(state$seen) + 1L]] <- list(
      route = route, url = req$url, headers = req$headers, body = req$body$data,
      policies = req$policies)
    replies <- routes[[route]]
    if (is.null(replies)) return(.dl_bytes(599, paste("unmocked", route), "text/plain"))
    if (inherits(replies, "httr2_response")) replies <- list(replies)
    n <- (state$served[[route]] %||% 0L) + 1L
    state$served[[route]] <- n
    replies[[min(n, length(replies))]]
  }, env = env)
  list(
    seen = function(route) Filter(function(s) identical(s$route, route), state$seen),
    count = function(route) length(Filter(function(s) identical(s$route, route), state$seen)),
    all = function() vapply(state$seen, function(s) s$route, character(1))
  )
}

# Record the poll waits instead of sleeping; the clock moves with them.
.dl_clock <- function(env = parent.frame()) {
  state <- new.env()
  state$now <- 1000
  state$waits <- numeric(0)
  testthat::local_mocked_bindings(
    .tl_sleep = function(seconds) {
      state$waits <- c(state$waits, seconds)
      state$now <- state$now + seconds
      invisible(NULL)
    },
    .tl_now = function() state$now,
    .env = env)
  state
}

.dl_dataset <- function() {
  tl_dataset(tl_client(api_key = "tlb_test_key", base_url = "https://api.topolab.nl"), .dl_table)
}
.dl_read <- function(path) readChar(path, file.info(path)$size, useBytes = TRUE)
# TRUE when the recorded request retries like every other SDK request.
.dl_retries_as_today <- function(seen) {
  p <- seen$policies
  identical(as.numeric(p$retry_max_tries), 4) &&
    all(vapply(c(429, 500, 502, 503, 504),
               function(code) p$retry_is_transient(httr2::response(code)), logical(1))) &&
    !p$retry_is_transient(httr2::response(404)) &&
    identical(p$retry_after, .tl_retry_after)
}
.dl_header <- function(seen, name) {
  h <- seen$headers
  hit <- names(h)[tolower(names(h)) == tolower(name)]
  if (length(hit) == 0) NULL else h[[hit[[1]]]]
}

# --- ready ----------------------------------------------------------------------

test_that("tl_download posts the link route and fetches the signed URL without the key", {
  clock <- .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_ready(), .dl_bytes(200, .dl_link_csv), .dl_bytes(200, .dl_old_csv)),
    c(.dl_link, .dl_signed, .dl_files_csv)))
  path <- withr::local_tempfile(fileext = ".csv")

  expect_equal(tl_download(.dl_dataset(), path, format = "csv"), path)

  expect_equal(.dl_read(path), .dl_link_csv)
  posted <- srv$seen(.dl_link)[[1]]
  expect_equal(.dl_header(posted, "X-API-Key"), "tlb_test_key")
  expect_equal(posted$body, list(format = "csv", bundle = "file"))
  fetched <- srv$seen(.dl_signed)[[1]]
  expect_null(.dl_header(fetched, "X-API-Key"))
  expect_null(.dl_header(fetched, "Authorization"))
  expect_equal(fetched$url, .dl_signed_url)  # the signed query, byte for byte
  expect_equal(srv$count(.dl_files_csv), 0L)
  expect_equal(clock$waits, numeric(0))
})

test_that("tl_archive sends the month and asks for the zip", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_ready("2026-11"), .dl_bytes(200, .dl_zip, "application/zip"),
         .dl_bytes(200, .dl_zip, "application/zip")),
    c(.dl_link, .dl_signed, .dl_archive_csv)))
  ds <- .dl_dataset()
  path <- withr::local_tempfile(fileext = ".zip")

  tl_archive(ds, path, month = "2026-11", format = "csv")
  tl_archive(ds, withr::local_tempfile(fileext = ".zip"), month = "LATEST")

  bodies <- lapply(srv$seen(.dl_link), function(s) s$body)
  expect_equal(bodies, list(list(format = "csv", month = "2026-11", bundle = "zip"),
                            list(format = "geojson", month = "latest", bundle = "zip")))
  expect_equal(.dl_read(path), .dl_zip)
  expect_equal(srv$count(.dl_archive_csv), 0L)
})

# --- preparing ------------------------------------------------------------------

test_that("the link route is polled honouring retryAfterSeconds", {
  clock <- .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(list(.dl_preparing(4), .dl_preparing(2), .dl_ready()), .dl_bytes(200, .dl_link_csv)),
    c(.dl_link, .dl_signed)))
  path <- withr::local_tempfile(fileext = ".csv")

  tl_download(.dl_dataset(), path, format = "csv")

  expect_equal(clock$waits, c(4, 2))
  expect_equal(srv$count(.dl_link), 3L)
  expect_equal(srv$count(.dl_signed), 1L)
  expect_equal(.dl_read(path), .dl_link_csv)
})

test_that("the poll wait reads the header when the body has none, and never spins", {
  clock <- .dl_clock()
  .dl_server(stats::setNames(
    list(list(.dl_preparing(NULL, list(`Retry-After` = "7")), .dl_preparing(NULL),
              .dl_preparing(0), .dl_ready()),
         .dl_bytes(200, .dl_link_csv)),
    c(.dl_link, .dl_signed)))

  tl_download(.dl_dataset(), withr::local_tempfile(fileext = ".csv"), format = "csv")

  # header 7 s; nothing at all: 5 s; a zero: the 1 s floor.
  expect_equal(clock$waits, c(7, 5, 1))
})

test_that("a file still preparing after the wait budget raises FILE_PREPARING", {
  clock <- .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_preparing(700), .dl_bytes(200, .dl_link_csv)), c(.dl_link, .dl_signed)))
  path <- withr::local_tempfile(fileext = ".csv")

  err <- expect_error(tl_download(.dl_dataset(), path, format = "csv"),
                      class = "topolab_server_error")

  expect_equal(err$code, "FILE_PREPARING")
  expect_equal(err$status, 202L)
  expect_equal(err$details, list(build = .dl_build, retryAfter = 700))
  expect_equal(clock$waits, c(700, 700))  # a third wait would end at 2,100 s, past 1,800 s
  expect_equal(srv$count(.dl_link), 3L)
  expect_equal(srv$count(.dl_signed), 0L)
  expect_false(file.exists(path))
})

# --- failed and unexpected answers -----------------------------------------------

test_that("a failed build is raised and never falls back", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_build_failed(), .dl_bytes(200, .dl_old_csv)), c(.dl_link, .dl_files_csv)))
  path <- withr::local_tempfile(fileext = ".csv")

  err <- expect_error(tl_download(.dl_dataset(), path, format = "csv"),
                      class = "topolab_server_error")

  expect_equal(err$code, "FILE_BUILD_FAILED")
  expect_equal(err$status, 503L)
  expect_true(.dl_retries_as_today(srv$seen(.dl_link)[[1]]))  # a 503 is retried as today
  expect_equal(srv$count(.dl_files_csv), 0L)
  expect_false(file.exists(path))
})

test_that("a server error from the link route never falls back", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_json(500, list(code = 500L, message = "Internal server error"),
                  list(`Retry-After` = "0")),
         .dl_bytes(200, .dl_old_csv)),
    c(.dl_link, .dl_files_csv)))

  expect_error(tl_download(.dl_dataset(), withr::local_tempfile(fileext = ".csv"), format = "csv"),
               class = "topolab_server_error")
  expect_true(.dl_retries_as_today(srv$seen(.dl_link)[[1]]))
  expect_equal(srv$count(.dl_files_csv), 0L)
})

test_that("a 200 without a link is a server error", {
  .dl_clock()
  .dl_server(stats::setNames(list(.dl_json(200, list(state = "ready"))), .dl_link))

  err <- expect_error(tl_download(.dl_dataset(), withr::local_tempfile(fileext = ".csv"),
                                  format = "csv"),
                      class = "topolab_server_error")
  expect_equal(err$status, 200L)
})

# --- fallback on 404 and 405 ------------------------------------------------------

test_that("a 404 from the link route falls back to the files route", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_no_route(), .dl_bytes(200, .dl_old_csv), .dl_bytes(200, .dl_link_csv)),
    c(.dl_link, .dl_files_csv, .dl_signed)))
  path <- withr::local_tempfile(fileext = ".csv")

  expect_equal(tl_download(.dl_dataset(), path, format = "csv"), path)

  expect_equal(.dl_read(path), .dl_old_csv)
  expect_equal(srv$count(.dl_link), 1L)
  expect_equal(srv$count(.dl_files_csv), 1L)
  expect_equal(.dl_header(srv$seen(.dl_files_csv)[[1]], "X-API-Key"), "tlb_test_key")
  expect_equal(srv$count(.dl_signed), 0L)
})

test_that("a 405 from the link route falls back to the archive route", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_json(405, list(code = 405L, message = "Method Not Allowed")),
         .dl_bytes(200, .dl_zip, "application/zip")),
    c(.dl_link, .dl_archive_csv)))
  path <- withr::local_tempfile(fileext = ".zip")

  tl_archive(.dl_dataset(), path, month = "2026-11", format = "csv")

  expect_equal(.dl_read(path), .dl_zip)
  expect_equal(srv$count(.dl_archive_csv), 1L)
})

test_that("the fallback keeps the old route's retries and answer", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_no_route(),
         .dl_json(503, list(code = "FILE_PREPARING", message = "This file is being prepared.",
                            details = list(retryAfter = 20L)),
                  list(`Retry-After` = "20"))),
    c(.dl_link, .dl_files_csv)))
  path <- withr::local_tempfile(fileext = ".csv")

  err <- expect_error(tl_download(.dl_dataset(), path, format = "csv"),
                      class = "topolab_server_error")

  expect_equal(err$code, "FILE_PREPARING")
  expect_true(.dl_retries_as_today(srv$seen(.dl_files_csv)[[1]]))
  expect_false(file.exists(path))
})

test_that("a 404 from the old route after the fallback is raised", {
  .dl_clock()
  .dl_server(stats::setNames(
    list(.dl_no_route(), .dl_json(404, list(code = 404L, message = "No archive for 2026-11"))),
    c(.dl_link, .dl_archive_csv)))

  expect_error(tl_archive(.dl_dataset(), withr::local_tempfile(fileext = ".zip"),
                          month = "2026-11", format = "csv"),
               class = "topolab_not_found_error")
})

test_that("the fallback is decided on every call", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(list(.dl_no_route(), .dl_ready()), .dl_bytes(200, .dl_old_csv),
         .dl_bytes(200, .dl_link_csv)),
    c(.dl_link, .dl_files_csv, .dl_signed)))
  ds <- .dl_dataset()
  first <- withr::local_tempfile(fileext = ".csv")
  second <- withr::local_tempfile(fileext = ".csv")

  tl_download(ds, first, format = "csv")
  tl_download(ds, second, format = "csv")

  expect_equal(.dl_read(first), .dl_old_csv)
  expect_equal(.dl_read(second), .dl_link_csv)
  expect_equal(c(srv$count(.dl_link), srv$count(.dl_files_csv), srv$count(.dl_signed)),
               c(2L, 1L, 1L))
})

# --- 402 and 403 are raised -------------------------------------------------------

test_that("a 403 from the link route is raised without a fallback", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_json(403, list(code = 403L,
                            message = "Your organization has no licence for this dataset")),
         .dl_bytes(200, .dl_old_csv)),
    c(.dl_link, .dl_files_csv)))
  path <- withr::local_tempfile(fileext = ".csv")

  expect_error(tl_download(.dl_dataset(), path, format = "csv"),
               class = "topolab_access_denied_error")
  expect_equal(srv$count(.dl_files_csv), 0L)
  expect_false(file.exists(path))
})

test_that("a 402 from the link route is raised without a fallback", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_json(402, list(code = 402L, message = "Insufficient credits",
                            details = list(required = 20L, available = 3L))),
         .dl_bytes(200, .dl_zip, "application/zip")),
    c(.dl_link, .dl_archive_csv)))

  err <- expect_error(tl_archive(.dl_dataset(), withr::local_tempfile(fileext = ".zip"),
                                 month = "2026-11", format = "csv"),
                      class = "topolab_insufficient_credits_error")
  expect_equal(err$required, 20L)
  expect_equal(srv$count(.dl_archive_csv), 0L)
})

# --- the signed URL ------------------------------------------------------------------

test_that("an error from the signed URL is raised without its body and leaves no file", {
  .dl_clock()
  .dl_server(stats::setNames(
    list(.dl_ready(),
         .dl_bytes(400, paste0("<?xml version='1.0' encoding='UTF-8'?><Error><Code>ExpiredToken",
                               "</Code><Details>X-Goog-Signature=5f2d0c9e</Details></Error>"),
                   "application/xml")),
    c(.dl_link, .dl_signed)))
  dir <- withr::local_tempdir()
  path <- file.path(dir, "x.csv")

  err <- expect_error(tl_download(.dl_dataset(), path, format = "csv"), class = "topolab_error")

  expect_equal(err$status, 400L)
  expect_false(grepl("X-Goog-Signature", conditionMessage(err), fixed = TRUE))
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), character(0))
})

test_that("the signed URL request retries like every other request", {
  .dl_clock()
  srv <- .dl_server(stats::setNames(
    list(.dl_ready(), .dl_bytes(200, .dl_link_csv)), c(.dl_link, .dl_signed)))
  path <- withr::local_tempfile(fileext = ".csv")

  tl_download(.dl_dataset(), path, format = "csv")

  expect_true(.dl_retries_as_today(srv$seen(.dl_signed)[[1]]))
  expect_equal(.dl_read(path), .dl_link_csv)
})

# --- the signed query never reaches a condition --------------------------------------
#
# The query of a signed link is its signature: a working bearer link to the file
# for ten minutes. A failure to reach the storage host is raised as a
# topolab_connection_error whose message, printed form and fields carry no part
# of the query (httr2's own failure keeps the whole request, URL included).

.dl_query <- sub("^[^?]*[?]", "", .dl_signed_url)
.dl_query_parts <- c("X-Goog-Signature", "5f2d0c9e", "X-Goog-Credential", .dl_query)

.dl_condition_text <- function(err) {
  fields <- unlist(lapply(unclass(err), function(x) {
    tryCatch(paste(deparse(x, nlines = -1L), collapse = "\n"), error = function(e) "")
  }))
  paste(c(conditionMessage(err), utils::capture.output(print(err)), fields,
          if (!is.null(err$parent)) conditionMessage(err$parent)), collapse = "\n")
}

# The link route answers a ready link to `url`; the signed request goes out to
# the real network (a local address) instead of the mock.
.dl_ready_at <- function(url, env = parent.frame()) {
  httr2::local_mocked_responses(function(req) {
    if (grepl("/exports$", req$url)) {
      return(.dl_json(200, list(state = "ready", url = url, build = .dl_build)))
    }
    NULL
  }, env = env)
}

.dl_closed_port <- function() {
  for (port in sample(49152:65000, 20)) {
    sock <- tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(sock)) {
      close(sock)
      return(port)
    }
  }
  skip("no free local port")
}

test_that("a refused connection to the storage host carries no part of the query", {
  .dl_clock()
  url <- paste0("http://127.0.0.1:", .dl_closed_port(), .dl_signed_path, "?", .dl_query)
  .dl_ready_at(url)
  dir <- withr::local_tempdir()

  err <- expect_error(tl_download(.dl_dataset(), file.path(dir, "x.csv"), format = "csv"),
                      class = "topolab_connection_error")

  expect_s3_class(err, "topolab_error")
  text <- .dl_condition_text(err)
  for (part in .dl_query_parts) expect_false(grepl(part, text, fixed = TRUE), info = part)
  expect_null(err$request)
  # It still says where it failed: the host and the path.
  expect_true(grepl(.dl_signed_path, conditionMessage(err), fixed = TRUE))
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), character(0))
})

test_that("a storage host that never answers carries no part of the query", {
  .dl_clock()
  port <- .dl_closed_port()
  hang <- serverSocket(port)
  on.exit(close(hang), add = TRUE)
  url <- paste0("http://127.0.0.1:", port, .dl_signed_path, "?", .dl_query)
  .dl_ready_at(url)
  ds <- tl_dataset(tl_client(api_key = "tlb_test_key", base_url = "https://api.topolab.nl",
                             timeout = 1, max_retries = 0), .dl_table)

  err <- expect_error(tl_archive(ds, withr::local_tempfile(fileext = ".zip"),
                                 month = "2026-11", format = "csv"),
                      class = "topolab_connection_error")

  text <- .dl_condition_text(err)
  for (part in .dl_query_parts) expect_false(grepl(part, text, fixed = TRUE), info = part)
})

test_that("an API request's connection failure is left as httr2 raises it", {
  port <- .dl_closed_port()
  ds <- tl_dataset(tl_client(api_key = "tlb_test_key",
                             base_url = paste0("http://127.0.0.1:", port), max_retries = 0),
                   .dl_table)

  err <- expect_error(tl_download(ds, withr::local_tempfile(fileext = ".csv"), format = "csv"))

  expect_s3_class(err, "httr2_failure")
})

# --- tl_sample() is unchanged -------------------------------------------------------

test_that("tl_sample reads the sample route and never the link route", {
  srv <- .dl_server(stats::setNames(
    list(.dl_json(200, list(type = "FeatureCollection", features = list()))),
    paste0("GET /v1/dataset/", .dl_table, "/sample/geojson")))

  out <- tl_sample(.dl_dataset())

  expect_equal(out$type, "FeatureCollection")
  expect_equal(srv$all(), paste0("GET /v1/dataset/", .dl_table, "/sample/geojson"))
})

test_that("a failure that quotes a redirect's signed link carries no part of its query", {
  # The storage host can redirect to a second signed link (a mirror, another
  # bucket), whose query is a signature too.
  .dl_clock()
  second <- "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=R2KEY%2F20261203&X-Amz-Signature=c0ffee77"
  httr2::local_mocked_responses(function(req) {
    if (grepl("/exports$", req$url)) {
      return(.dl_json(200, list(state = "ready", url = .dl_signed_url, build = .dl_build)))
    }
    rlang::abort("Failed to perform HTTP request.", class = c("httr2_failure", "httr2_error"),
                 parent = simpleError(paste0("proxy refused https://mirror.example/x.csv?", second)),
                 request = req)
  })

  err <- expect_error(tl_download(.dl_dataset(), withr::local_tempfile(fileext = ".csv"), format = "csv"),
                      class = "topolab_connection_error")

  text <- .dl_condition_text(err)
  for (part in c(.dl_query_parts, "X-Amz-Signature", "c0ffee77", "R2KEY")) {
    expect_false(grepl(part, text, fixed = TRUE), info = part)
  }
  expect_true(grepl("https://mirror.example/x.csv", conditionMessage(err), fixed = TRUE))
})

test_that("httr2's verbose output of the signed fetch carries no part of the query", {
  # A script with options(httr2_verbosity = 1) prints every request line httr2
  # sends; the signed link's line would hold its signature.
  .dl_clock()
  withr::local_options(httr2_verbosity = 1)
  port <- .dl_closed_port()
  hang <- serverSocket(port)
  on.exit(close(hang), add = TRUE)
  url <- paste0("http://127.0.0.1:", port, .dl_signed_path, "?", .dl_query)
  .dl_ready_at(url)
  ds <- tl_dataset(tl_client(api_key = "tlb_test_key", base_url = "https://api.topolab.nl",
                             timeout = 1, max_retries = 0), .dl_table)

  said <- character(0)
  out <- utils::capture.output(
    withCallingHandlers(
      tryCatch(tl_download(ds, withr::local_tempfile(fileext = ".csv"), format = "csv"),
               topolab_connection_error = function(e) NULL),
      message = function(m) {
        said <<- c(said, conditionMessage(m))
        invokeRestart("muffleMessage")
      }),
    type = "output")

  text <- paste(c(out, said), collapse = "\n")
  for (part in .dl_query_parts) expect_false(grepl(part, text, fixed = TRUE), info = part)
})
