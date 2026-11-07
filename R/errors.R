# Typed condition system mirroring the SDK error model.

`%||%` <- function(a, b) if (is.null(a)) b else a

topolab_error <- function(message, class, status = NULL, ..., call = NULL) {
  structure(
    class = c(class, "topolab_error", "error", "condition"),
    list(message = message, call = call, status = status, ...)
  )
}

# Extract the add-on slug from a 403 message, or NULL when the message does not
# carry an add-on requirement. Add-on identifiers are hyphenated slugs
# ("api-access", "archived-data", ...), so the capture must not stop at the
# hyphen — a `\w+` capture matches nothing at all. The engine phrases the
# requirement two ways:
#   "This endpoint requires the api-access add-on"
#   "Archive access requires the Archived Data add-on. Please upgrade ..."
# Both normalise to the same slug: trim, lower-case, spaces to hyphens.
.tl_addon_slug <- function(msg) {
  if (is.null(msg) || !is.character(msg) || length(msg) != 1L) return(NULL)
  m <- regmatches(msg, regexec("requires the (.+?) add-?on", msg, ignore.case = TRUE))[[1]]
  if (length(m) < 2) return(NULL)
  slug <- tolower(gsub("[[:space:]]+", "-", trimws(m[2])))
  if (!nzchar(slug)) NULL else slug
}

# The envelope's `code`: a string such as "SPENDING_LIMIT_EXCEEDED" when the
# engine throws a named code, otherwise the numeric HTTP status. Anything else
# (absent, empty, logical, a list) falls back to the HTTP status, so a proxy's
# error page still yields a usable code.
.tl_envelope_code <- function(code, status) {
  if (is.character(code) && length(code) == 1L && !is.na(code) && nzchar(code)) {
    return(code)
  }
  # A whole number inside R's integer range; anything larger would become NA
  # (with a warning) on conversion, so it falls back to the status instead.
  if (is.numeric(code) && length(code) == 1L && is.finite(code) && code == round(code) &&
      abs(code) <= .Machine$integer.max) {
    return(as.integer(code))
  }
  as.integer(status)
}

# A non-negative, finite number of seconds from a number or a numeric string,
# or NULL.
.tl_seconds <- function(x) {
  if (is.null(x) || length(x) != 1L || is.logical(x)) return(NULL)
  n <- suppressWarnings(as.numeric(x))
  if (is.na(n) || !is.finite(n) || n < 0) NULL else n
}

# How long the server asked the client to wait, in seconds, or NA_real_ when it
# did not say. The Retry-After header comes first (seconds, or an HTTP date):
# the engine sends it on every 429 that carries a wait, rounded up. Then
# details.retryAfter (engine #650 and later), then a top-level retryAfter from
# older engines. This is also the `after` callback for httr2::req_retry(), which
# requires a single number or NA, never NULL.
.tl_retry_after <- function(resp) {
  header <- tryCatch(httr2::resp_header(resp, "Retry-After"), error = function(e) NULL)
  secs <- .tl_seconds(header)
  if (is.null(secs) && !is.null(header)) {
    # An HTTP date; httr2 measures it against the response's Date header.
    secs <- .tl_seconds(tryCatch(httr2::resp_retry_after(resp), error = function(e) NULL))
  }
  if (is.null(secs)) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
    if (is.list(body)) {
      details <- body$details
      if (is.list(details)) secs <- .tl_seconds(details$retryAfter)
      if (is.null(secs)) secs <- .tl_seconds(body$retryAfter)
    }
  }
  if (is.null(secs)) NA_real_ else secs
}

# The envelope's allow-listed `details` object as a named list, or NULL.
.tl_envelope_details <- function(details) {
  if (is.list(details) && !is.null(names(details))) details else NULL
}

# The engine's error envelope is {code, message, path, method, time, requestId},
# plus `details` for some errors. There is no `statusCode` field, and `code` is a
# string code or the numeric status, so the class below is chosen from the
# *HTTP status* and never from a body field; `$code` only refines it (a 403 with
# SPENDING_LIMIT_EXCEEDED is still a topolab_access_denied_error).
abort_from_response <- function(resp) {
  status <- httr2::resp_status(resp)
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  msg <- body$message %||% body$error %||% "request failed"
  addon <- if (status == 403) .tl_addon_slug(msg) else NULL
  cls <- switch(
    as.character(status),
    "401" = "topolab_authentication_error",
    "402" = "topolab_insufficient_credits_error",
    "403" = if (!is.null(addon)) "topolab_addon_required_error" else "topolab_access_denied_error",
    "404" = "topolab_not_found_error",
    "408" = "topolab_query_timeout_error",
    "429" = "topolab_rate_limit_error",
    "400" = if (grepl("organization", msg, ignore.case = TRUE)) "topolab_configuration_error" else "topolab_validation_error",
    if (status >= 500) "topolab_server_error" else "topolab_validation_error"
  )
  # The request id is returned both as a header and in the body; fall back to the
  # body so it survives proxies that strip the header.
  request_id <- tryCatch(httr2::resp_header(resp, "X-Request-Id"), error = function(e) NULL)
  details <- .tl_envelope_details(body$details)
  extra <- list(
    status = status,
    code = .tl_envelope_code(body$code, status),
    details = details,
    request_id = request_id %||% body$requestId
  )
  if (identical(cls, "topolab_addon_required_error")) extra$addon <- addon
  if (identical(cls, "topolab_insufficient_credits_error")) {
    extra$required <- details$required
    extra$available <- details$available
  }
  if (identical(cls, "topolab_rate_limit_error")) {
    wait <- .tl_retry_after(resp)
    if (!is.na(wait)) extra$retry_after <- wait
  }
  stop(do.call(topolab_error, c(list(message = msg, class = cls), extra)))
}
