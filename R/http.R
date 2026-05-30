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
    req,
    max_tries = client$max_retries,
    is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504),
    after = function(resp) {
      body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
      if (!is.null(body$retryAfter)) as.numeric(body$retryAfter) else NULL
    }
  )
  # We map errors ourselves rather than letting httr2 abort.
  httr2::req_error(req, is_error = function(resp) FALSE)
}

tl_perform_json <- function(req) {
  resp <- httr2::req_perform(req)
  if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}
