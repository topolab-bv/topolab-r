# Downloads through the link route, with a per-call fallback to the old routes.
#
# POST /v1/dataset/{table}/exports answers 200 with a short-lived signed URL to
# a ready file, or 202 while the file is being prepared. The signed URL is
# fetched with a plain httr2::request(url) that sends no API key.
#
# A server without the link route answers it with 404 (or 405). The call then
# goes to the old route (GET .../files/{format} or
# GET .../archives/{month}/{format}) with today's behaviour and retries.
# Nothing is remembered between calls, so a script keeps working while servers
# gain or lose the route. Every other error (402, 403, 5xx, ...) is raised.

# Answers from the link route that mean "this server has no link route".
.tl_link_fallback_status <- c(404L, 405L)
# Wait between polls when the server names no wait, and the shortest wait.
.tl_link_default_poll <- 5
.tl_link_min_poll <- 1
# How long one call waits for a file that is being prepared, in seconds. The
# build keeps going on the server, so a later call finds the file ready.
.tl_link_max_wait <- 30 * 60

# Time, behind functions the tests replace.
.tl_sleep <- function(seconds) Sys.sleep(seconds)
.tl_now <- function() as.numeric(Sys.time())

# The signed link as a request: a plain httr2::request(url) with no header of
# ours (the link carries its own authorisation, so the API key never reaches
# the storage host), and the same timeout and retries as every other request.
.tl_signed_req <- function(client, url) {
  if (!grepl("^https?://", url)) {
    url <- paste0(sub("/+$", "", client$base_url), "/", sub("^/+", "", url))
  }
  req <- httr2::request(url)
  req <- httr2::req_timeout(req, client$timeout)
  req <- httr2::req_retry(
    req,
    max_tries = client$max_retries + 1L,
    is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504),
    after = .tl_retry_after
  )
  httr2::req_error(req, is_error = function(resp) FALSE)
}

# A failed signed-link fetch: the condition class follows the status as
# everywhere else; the message never repeats the storage host's body, which can
# quote the link's signature.
.tl_abort_signed_link <- function(resp) {
  status <- httr2::resp_status(resp)
  cnd <- tryCatch(abort_from_response(resp), topolab_error = function(e) e)
  cnd$message <- sprintf(
    "Fetching the file from its signed link failed with HTTP %d. Call again for a new link.",
    status)
  stop(cnd)
}

# A signed link the storage host could not be reached on (refused, timed out,
# ...): a topolab_connection_error whose message names the host and path and
# never the query. The query is the link's signature, a working bearer link to
# the file for ten minutes; httr2's own failure keeps the request, URL
# included, so neither it nor its parent is kept.
.tl_abort_signed_link_failure <- function(e, url) {
  cause <- if (!is.null(e$parent)) conditionMessage(e$parent) else conditionMessage(e)
  cause <- .tl_without_url_queries(.tl_without_query(cause, url))
  stop(topolab_error(
    sprintf("Could not fetch the file from its signed link (%s): %s",
            sub("[?#].*$", "", url), trimws(gsub("[[:space:]]+", " ", cause))),
    class = "topolab_connection_error"))
}

# `text` without any copy of `url`'s query.
.tl_without_query <- function(text, url) {
  query <- sub("#.*$", "", sub("^[^?]*[?]?", "", url))
  if (!grepl("?", url, fixed = TRUE) || !nzchar(query)) return(text)
  text <- gsub(paste0("?", query), "", text, fixed = TRUE)
  gsub(query, "[query removed]", text, fixed = TRUE)
}

# `text` without the query of any absolute URL it quotes: from the "?" up to the
# next space or quote, leaving punctuation that closes the sentence (a ")" after
# the URL) in place. The storage host can redirect to a second signed link,
# whose query is a signature too.
.tl_without_url_queries <- function(text) {
  gsub("(?i)(\\b[a-z][a-z0-9+.-]*://[^\\s?#\"'<>]*)\\?[^\\s\"'<>]*?(?=[)\\]}>,;.:!]*(?:[\\s\"'<>]|$))",
       "\\1", text, perl = TRUE)
}

.tl_link_seconds <- function(x) {
  if (is.null(x) || length(x) != 1L || !is.numeric(x) || !is.finite(x) || x < 0) NULL else x
}

.tl_link_unexpected <- function(resp) {
  status <- httr2::resp_status(resp)
  stop(topolab_error(
    sprintf("The link route answered HTTP %d without a ready link or a preparing state.", status),
    class = "topolab_server_error", status = status, code = as.integer(status)))
}

# Read a 200 or 202 from the link route: list(state = "ready", url) or
# list(state = "preparing", wait, build, status).
.tl_link_answer <- function(resp) {
  status <- httr2::resp_status(resp)
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  if (!is.list(body) || is.null(names(body))) .tl_link_unexpected(resp)
  if (status == 202L || identical(body$state, "preparing")) {
    wait <- .tl_link_seconds(body$retryAfterSeconds)
    if (is.null(wait)) {
      header <- tryCatch(httr2::resp_header(resp, "Retry-After"), error = function(e) NULL)
      wait <- .tl_seconds(header)
    }
    if (is.null(wait)) wait <- .tl_link_default_poll
    return(list(state = "preparing", wait = max(wait, .tl_link_min_poll),
                build = body$build, status = status))
  }
  url <- body$url
  if (status == 200L && identical(body$state, "ready") && is.character(url) &&
      length(url) == 1L && !is.na(url) && nzchar(url)) {
    return(list(state = "ready", url = url))
  }
  .tl_link_unexpected(resp)
}

.tl_link_still_preparing <- function(answer) {
  stop(topolab_error(
    sprintf(paste0("The file is still being prepared, and the next wait would pass this ",
                   "call's %d-minute limit. It keeps building on the server; call again later."),
            as.integer(round(.tl_link_max_wait / 60))),
    class = "topolab_server_error", status = as.integer(answer$status), code = "FILE_PREPARING",
    details = list(build = answer$build, retryAfter = answer$wait)))
}

# Write the file the link route names to `path`, or the old route's file on a
# server without the link route. Returns `path` invisibly.
.tl_fetch_via_link <- function(dataset, body, fallback_path, path) {
  client <- dataset$client
  started <- .tl_now()
  repeat {
    resp <- httr2::req_perform(
      tl_req_post(client, paste0("v1/dataset/", dataset$slug, "/exports"), body))
    status <- httr2::resp_status(resp)
    if (status %in% .tl_link_fallback_status) {
      return(.tl_stream_to_file(tl_req(client, fallback_path), path))
    }
    if (status >= 400) abort_from_response(resp)
    answer <- .tl_link_answer(resp)
    if (identical(answer$state, "ready")) {
      req <- .tl_signed_req(client, answer$url)
      return(tryCatch(
        .tl_stream_to_file(req, path, on_error = .tl_abort_signed_link, verbosity = 0L),
        httr2_failure = function(e) .tl_abort_signed_link_failure(e, req$url)))
    }
    if (.tl_now() - started + answer$wait > .tl_link_max_wait) .tl_link_still_preparing(answer)
    .tl_sleep(answer$wait)
  }
}
