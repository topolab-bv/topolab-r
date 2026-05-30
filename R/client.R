# Named API environments. Production is the shipped default; staging is one
# keyword away. Self-hosting / tests can still pass an explicit base_url.
.tl_environments <- c(
  production = "https://api.topolab.nl",
  staging    = "https://api-staging.topolab.nl"
)

.tl_environment_url <- function(name) {
  url <- .tl_environments[[tolower(name)]]
  if (is.null(url)) {
    stop(topolab_error(
      sprintf("Unknown environment '%s'. Use one of %s.",
              name, paste(names(.tl_environments), collapse = ", ")),
      class = "topolab_configuration_error"))
  }
  url
}

# Resolve the API base URL. Precedence (most specific first):
# explicit base_url > environment > TOPOLAB_BASE_URL > TOPOLAB_ENV > production.
.tl_resolve_base_url <- function(base_url, environment) {
  if (!is.null(base_url) && nzchar(base_url)) return(sub("/$", "", base_url))
  if (!is.null(environment) && nzchar(environment)) return(.tl_environment_url(environment))
  env_base <- Sys.getenv("TOPOLAB_BASE_URL")
  if (nzchar(env_base)) return(sub("/$", "", env_base))
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
