# Typed condition system mirroring the SDK error model.

`%||%` <- function(a, b) if (is.null(a)) b else a

topolab_error <- function(message, class, status = NULL, ..., call = NULL) {
  structure(
    class = c(class, "topolab_error", "error", "condition"),
    list(message = message, call = call, status = status, ...)
  )
}

abort_from_response <- function(resp) {
  status <- httr2::resp_status(resp)
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  msg <- body$message %||% body$error %||% "request failed"
  cls <- switch(
    as.character(status),
    "401" = "topolab_authentication_error",
    "402" = "topolab_insufficient_credits_error",
    "403" = if (grepl("add-?on", msg, ignore.case = TRUE)) "topolab_addon_required_error" else "topolab_access_denied_error",
    "404" = "topolab_not_found_error",
    "429" = "topolab_rate_limit_error",
    "400" = if (grepl("organization", msg, ignore.case = TRUE)) "topolab_configuration_error" else "topolab_validation_error",
    if (status >= 500) "topolab_server_error" else "topolab_validation_error"
  )
  extra <- list(status = status)
  if (identical(cls, "topolab_addon_required_error")) {
    m <- regmatches(msg, regexec("requires the (\\w+) add-?on", msg, ignore.case = TRUE))[[1]]
    if (length(m) >= 2) extra$addon <- m[2]
  }
  if (identical(cls, "topolab_insufficient_credits_error")) {
    extra$required <- body$details$required
    extra$available <- body$details$available
  }
  if (identical(cls, "topolab_rate_limit_error")) extra$retry_after <- body$retryAfter
  stop(do.call(topolab_error, c(list(message = msg, class = cls), extra)))
}
