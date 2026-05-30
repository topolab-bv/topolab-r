# Named API environments. Production is the shipped default; staging is one
# keyword away. Self-hosting / tests can still pass an explicit base_url.
.tl_environments <- c(
  production = "https://api.topolab.nl",
  staging    = "https://api-staging.topolab.nl"
)

.tl_environment_url <- function(name) {
  key <- tolower(name)
  # `[[` on a named character vector throws "subscript out of bounds" for an
  # unknown name, so check membership explicitly before indexing.
  if (!key %in% names(.tl_environments)) {
    stop(topolab_error(
      sprintf("Unknown environment '%s'. Use one of %s.",
              name, paste(names(.tl_environments), collapse = ", ")),
      class = "topolab_configuration_error"))
  }
  unname(.tl_environments[[key]])
}

.tl_loopback_hosts <- c("localhost", "127.0.0.1", "::1")

# Reject base URLs that could exfiltrate the API key to an attacker-controlled
# host: require https (http only for loopback), and forbid embedded credentials.
.tl_validate_base_url <- function(url) {
  parsed <- httr2::url_parse(url)
  scheme <- tolower(parsed$scheme %||% "")
  if (!scheme %in% c("https", "http")) {
    stop(topolab_error(sprintf("base_url must use http(s); got '%s'", url),
                       class = "topolab_configuration_error"))
  }
  has_user <- !is.null(parsed$username) && nzchar(parsed$username)
  has_pass <- !is.null(parsed$password) && nzchar(parsed$password)
  if (has_user || has_pass) {
    stop(topolab_error("base_url must not contain credentials (userinfo)",
                       class = "topolab_configuration_error"))
  }
  host <- tolower(parsed$hostname %||% "")
  if (scheme == "http" && !host %in% .tl_loopback_hosts) {
    stop(topolab_error(
      sprintf("base_url must use https for non-loopback host '%s'", host),
      class = "topolab_configuration_error"))
  }
  sub("/$", "", url)
}

# Resolve the API base URL. Precedence (most specific first):
# explicit base_url > environment > TOPOLAB_BASE_URL > TOPOLAB_ENV > production.
# User-supplied URLs (base_url, TOPOLAB_BASE_URL) are validated; the named
# environments and the production default are trusted https constants.
.tl_resolve_base_url <- function(base_url, environment) {
  if (!is.null(base_url) && nzchar(base_url)) return(.tl_validate_base_url(base_url))
  if (!is.null(environment) && nzchar(environment)) return(.tl_environment_url(environment))
  env_base <- Sys.getenv("TOPOLAB_BASE_URL")
  if (nzchar(env_base)) return(.tl_validate_base_url(env_base))
  env_name <- Sys.getenv("TOPOLAB_ENV")
  if (nzchar(env_name)) return(.tl_environment_url(env_name))
  .tl_environments[["production"]]
}

#' Create a Topolab API client
#'
#' @param api_key Organization-scoped API key. Defaults to env var TOPOLAB_API_KEY.
#' @param base_url Explicit API base URL (overrides `environment`). For self-hosting
#'   or testing; defaults to the production environment.
#' @param environment Named environment: "production" (default) or "staging".
#' @param timeout Request timeout (seconds).
#' @param max_retries Max retry attempts for transient failures.
#' @return A `topolab_client` object.
#' @export
tl_client <- function(api_key = Sys.getenv("TOPOLAB_API_KEY"),
                      base_url = NULL, environment = NULL,
                      timeout = 60, max_retries = 3) {
  if (is.null(api_key) || !nzchar(api_key)) {
    stop(topolab_error("No API key. Pass api_key or set TOPOLAB_API_KEY.",
                       class = "topolab_configuration_error"))
  }
  structure(
    list(api_key = api_key, base_url = .tl_resolve_base_url(base_url, environment),
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
  # `cache` is an environment (by-reference) so the resolved OGC collection id
  # persists across calls on the same handle — a plain list field would be lost
  # to R's copy-on-modify semantics.
  structure(list(client = client, slug = slug, cache = new.env(parent = emptyenv())),
            class = "topolab_dataset")
}
