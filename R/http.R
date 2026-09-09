# httr2 request building with retry + typed errors.

.tl_user_agent <- function() "topolab-r/0.1.0 (+https://docs.topolab.nl)"

tl_req <- function(client, path, query = list()) {
  query <- query[!vapply(query, is.null, logical(1))]
  req <- httr2::request(client$base_url)
  req <- httr2::req_url_path_append(req, path)
  if (length(query) > 0) req <- httr2::req_url_query(req, !!!query)
  req <- httr2::req_headers(req, `X-API-Key` = client$api_key, Accept = "application/json")
  req <- httr2::req_user_agent(req, .tl_user_agent())
  req <- httr2::req_timeout(req, client$timeout)
  req <- httr2::req_retry(
    # httr2's max_tries is the TOTAL attempt count; max_retries is the number of
    # *retries* after the first try, matching the Python/TS SDKs (default 3).
    req,
    max_tries = client$max_retries + 1L,
    is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504),
    after = function(resp) {
      body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
      if (!is.null(body$retryAfter)) as.numeric(body$retryAfter) else NULL
    }
  )
  # We map errors ourselves rather than letting httr2 abort.
  httr2::req_error(req, is_error = function(resp) FALSE)
}

# Same request, with a JSON body posted to `path`. `body` is a plain list;
# NULL entries are dropped so optional fields are omitted from the payload
# rather than sent as JSON null.
tl_req_post <- function(client, path, body = list()) {
  body <- body[!vapply(body, is.null, logical(1))]
  req <- tl_req(client, path)
  httr2::req_body_json(req, body, auto_unbox = TRUE)
}

# Perform a request and return the raw response, so callers that need response
# headers (paging counts) or a non-JSON body can read them. Errors are mapped
# before the response is handed back.
tl_perform_resp <- function(req) {
  resp <- httr2::req_perform(req)
  if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
  resp
}

tl_perform_json <- function(req) {
  httr2::resp_body_json(tl_perform_resp(req), simplifyVector = FALSE)
}

# Read an integer response header, falling back to `default` when the header is
# absent or does not parse. Paging metadata must never turn a good response into
# an error.
tl_resp_header_int <- function(resp, name, default) {
  raw <- tryCatch(httr2::resp_header(resp, name), error = function(e) NULL)
  if (is.null(raw) || !nzchar(raw)) return(default)
  value <- suppressWarnings(as.integer(raw))
  if (is.na(value)) default else value
}
