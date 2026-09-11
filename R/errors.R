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

# The engine's error envelope is {code, message, path, method, time, requestId}.
# There is no `statusCode` field, and `code` merely mirrors the HTTP status, so
# the mapping below branches on the *HTTP status* and never on a body field.
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
  extra <- list(status = status, request_id = request_id %||% body$requestId)
  if (identical(cls, "topolab_addon_required_error")) extra$addon <- addon
  if (identical(cls, "topolab_insufficient_credits_error")) {
    extra$required <- body$details$required
    extra$available <- body$details$available
  }
  if (identical(cls, "topolab_rate_limit_error")) extra$retry_after <- body$retryAfter
  stop(do.call(topolab_error, c(list(message = msg, class = cls), extra)))
}
