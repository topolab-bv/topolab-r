#' Create a Topolab API client
#'
#' @param api_key Organization-scoped API key. Defaults to env var TOPOLAB_API_KEY.
#' @param base_url API base URL. Defaults to https://api.topolab.nl
#' @param timeout Request timeout (seconds).
#' @param max_retries Max retry attempts for transient failures.
#' @return A `topolab_client` object.
#' @export
tl_client <- function(api_key = Sys.getenv("TOPOLAB_API_KEY"),
                      base_url = Sys.getenv("TOPOLAB_BASE_URL", unset = "https://api.topolab.nl"),
                      timeout = 60, max_retries = 3) {
  if (is.null(api_key) || !nzchar(api_key)) {
    stop(topolab_error("No API key. Pass api_key or set TOPOLAB_API_KEY.",
                       class = "topolab_configuration_error"))
  }
  if (!nzchar(base_url)) base_url <- "https://api.topolab.nl"
  structure(
    list(api_key = api_key, base_url = sub("/$", "", base_url),
         timeout = timeout, max_retries = max_retries),
    class = "topolab_client"
  )
}

#' Reference a dataset by table/slug
#'
#' @param client A `topolab_client`.
#' @param slug The dataset table identifier, e.g. "nl-domino-poi".
#' @return A `topolab_dataset` handle.
#' @export
tl_dataset <- function(client, slug) {
  structure(list(client = client, slug = slug, collection_id = NULL),
            class = "topolab_dataset")
}
