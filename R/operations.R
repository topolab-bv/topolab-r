#' List datasets (catalog)
#'
#' @param client A `topolab_client`.
#' @param page,limit,search,theme,country,sort_by,sort_order Query filters.
#' @return Parsed catalog list with `data` and `meta`.
#' @export
tl_datasets <- function(client, page = NULL, limit = NULL, search = NULL,
                        theme = NULL, country = NULL, sort_by = NULL, sort_order = NULL) {
  q <- list(page = page, limit = limit, search = search, theme = theme,
            country = country, sortBy = sort_by, sortOrder = sort_order)
  tl_perform_json(tl_req(client, "v1/dataset/all", q))
}

#' Dataset metadata
#'
#' @param dataset A `topolab_dataset`.
#' @param locale Optional locale ("en"/"nl").
#' @return Parsed dataset metadata (list).
#' @export
tl_metadata <- function(dataset, locale = NULL) {
  tl_perform_json(tl_req(dataset$client, paste0("v1/dataset/", dataset$slug),
                         list(locale = locale)))
}

#' Free dataset sample
#'
#' @param dataset A `topolab_dataset`.
#' @param format One of "csv","json","geojson","kml".
#' @return Parsed JSON/GeoJSON list, or a character string for csv/kml.
#' @export
tl_sample <- function(dataset, format = "geojson") {
  req <- tl_req(dataset$client, paste0("v1/dataset/", dataset$slug, "/sample/", format))
  resp <- httr2::req_perform(req)
  if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
  if (format %in% c("json", "geojson")) {
    httr2::resp_body_json(resp, simplifyVector = FALSE)
  } else {
    httr2::resp_body_string(resp)
  }
}

#' Full dataset as GeoJSON (requires API_ACCESS; consumes credits)
#'
#' @param dataset A `topolab_dataset`.
#' @return A parsed GeoJSON FeatureCollection (list).
#' @export
tl_geojson <- function(dataset) {
  tl_perform_json(tl_req(dataset$client, paste0("v1/dataset/", dataset$slug, "/files/geojson")))
}

# Formats accepted by the bulk file and archive routes.
.tl_bulk_formats <- c("csv", "json", "geojson", "kml", "shp")

.tl_check_bulk_format <- function(format) {
  if (length(format) != 1L || !is.character(format) || is.na(format) ||
      !format %in% .tl_bulk_formats) {
    stop(topolab_error(
      sprintf("Unsupported format '%s'. Use one of %s.",
              paste(format, collapse = ", "), paste(.tl_bulk_formats, collapse = ", ")),
      class = "topolab_validation_error"))
  }
  format
}

# Stream a request body to `path`. Downloads land in a temp file next to the
# destination so an error response is never written to `path`, and a partial
# download (connection dropped mid-body) cannot leave a truncated file at the
# destination. Status is checked before the atomic rename.
.tl_stream_to_file <- function(req, path) {
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".part")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  resp <- httr2::req_perform(req, path = tmp)
  if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
  }
  invisible(path)
}

#' Download a dataset export to disk
#'
#' An unsupported `format` is rejected client-side as a
#' `topolab_validation_error` rather than sent, matching the other Topolab SDKs
#' and the server's 400.
#'
#' @param dataset A `topolab_dataset`.
#' @param path Destination file path.
#' @param format One of "csv","json","geojson","kml","shp".
#' @return The path, invisibly.
#' @export
tl_download <- function(dataset, path, format = "geojson") {
  format <- .tl_check_bulk_format(format)
  req <- tl_req(dataset$client, paste0("v1/dataset/", dataset$slug, "/files/", format))
  .tl_stream_to_file(req, path)
}

# The OGC collectionId is the dataset slug (`table`), so the items endpoints are
# addressed by slug directly — no slug->uuid metadata round-trip.

# Build the query list for an items request (drops NULLs via tl_req's handling).
.tl_items_query <- function(page_size, offset, bbox, category, city, country) {
  q <- list(limit = page_size, offset = offset, category = category, city = city, country = country)
  if (!is.null(bbox)) q$bbox <- paste(bbox, collapse = ",")
  q
}

# Build (but do not perform) an items request for a given offset.
.tl_items_req <- function(dataset, page_size, offset, bbox, category, city, country) {
  q <- .tl_items_query(page_size, offset, bbox, category, city, country)
  tl_req(dataset$client, paste0("v1/ogc/collections/", dataset$slug, "/items"), q)
}

#' Query features (OGC items; requires GIS_ACCESS)
#'
#' @param dataset A `topolab_dataset`.
#' @param bbox Numeric vector c(minLon,minLat,maxLon,maxLat).
#' @param limit,offset,category,city,country Query params.
#' @return A parsed GeoJSON FeatureCollection (list).
#' @export
tl_items <- function(dataset, bbox = NULL, limit = 100, offset = NULL,
                     category = NULL, city = NULL, country = NULL) {
  q <- .tl_items_query(limit, offset, bbox, category, city, country)
  tl_perform_json(tl_req(dataset$client, paste0("v1/ogc/collections/", dataset$slug, "/items"), q))
}

#' Auto-paginate all features
#'
#' Fetches every matching feature, paging transparently. When more than one page
#' is needed the remaining pages are fetched **concurrently** via
#' [httr2::req_perform_parallel()] (the server reports `numberMatched` on the
#' first page, so the full set of page offsets is known after one request). Set
#' `parallel = FALSE` to page strictly sequentially.
#'
#' @param dataset A `topolab_dataset`.
#' @param page_size Features per request (<=1000).
#' @param total_limit Max features overall (NULL = all).
#' @param bbox,category,city,country Filters.
#' @param parallel Fetch the remaining pages concurrently (default TRUE).
#' @param max_concurrency Max simultaneous in-flight requests when `parallel`.
#' @return A GeoJSON FeatureCollection (list) with all matched features.
#' @export
tl_items_all <- function(dataset, page_size = 100, total_limit = NULL,
                         bbox = NULL, category = NULL, city = NULL, country = NULL,
                         parallel = TRUE, max_concurrency = 6) {
  trim <- function(feats) {
    if (!is.null(total_limit) && length(feats) > total_limit) feats[seq_len(total_limit)] else feats
  }

  # First page is always fetched on its own — it returns numberMatched, which
  # tells us how many more pages exist (so the rest can go out concurrently).
  first <- tl_perform_json(.tl_items_req(dataset, page_size, 0, bbox, category, city, country))
  feats <- first$features %||% list()
  if (length(feats) < page_size) {
    return(list(type = "FeatureCollection", features = trim(feats)))
  }

  matched <- suppressWarnings(as.numeric(first$numberMatched))
  target <- if (!is.null(total_limit)) {
    if (!is.na(matched)) min(total_limit, matched) else total_limit
  } else {
    matched
  }

  # Sequential fallback: either requested, or we can't tell how many pages remain
  # (no usable numberMatched), so we must page until an empty/short page.
  if (!isTRUE(parallel) || is.na(target)) {
    offset <- page_size
    repeat {
      if (!is.null(total_limit) && length(feats) >= total_limit) break
      page <- tl_perform_json(.tl_items_req(dataset, page_size, offset, bbox, category, city, country))
      pf <- page$features %||% list()
      if (length(pf) == 0) break
      feats <- c(feats, pf)
      if (length(pf) < page_size) break
      offset <- offset + page_size
    }
    return(list(type = "FeatureCollection", features = trim(feats)))
  }

  # Parallel path: we know the target count, so enumerate the remaining page
  # offsets and fetch them concurrently. (Guard the seq so it never gets a
  # wrong-sign `by` when the first page already covers the target.)
  offsets <- if (target > page_size) seq(page_size, target - 1, by = page_size) else numeric(0)
  if (length(offsets) > 0) {
    reqs <- lapply(offsets, function(off)
      httr2::req_error(.tl_items_req(dataset, page_size, off, bbox, category, city, country),
                       is_error = function(resp) FALSE))
    resps <- httr2::req_perform_parallel(reqs, max_active = max_concurrency, on_error = "return")
    for (resp in resps) {
      if (inherits(resp, "error")) stop(resp)
      if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
      pf <- httr2::resp_body_json(resp, simplifyVector = FALSE)$features %||% list()
      feats <- c(feats, pf)
    }
  }
  list(type = "FeatureCollection", features = trim(feats))
}

# ---------------------------------------------------------------------------
# Backend integration: pull what the organization owns, on its own schedule.
# ---------------------------------------------------------------------------

# Validate an optional whole-number parameter client-side, so an out-of-range
# page size fails before it costs a round trip (and, on metered routes, a credit).
.tl_check_count <- function(value, name, min, max = NULL) {
  if (is.null(value)) return(NULL)
  if (length(value) != 1L || !is.numeric(value) || is.na(value) || value != trunc(value)) {
    stop(topolab_error(sprintf("%s must be a single whole number", name),
                       class = "topolab_validation_error"))
  }
  n <- as.integer(value)
  if (n < min || (!is.null(max) && n > max)) {
    msg <- if (is.null(max)) {
      sprintf("%s must be >= %d; got %d", name, min, n)
    } else {
      sprintf("%s must be between %d and %d; got %d", name, min, max, n)
    }
    stop(topolab_error(msg, class = "topolab_validation_error"))
  }
  n
}

# Validate an archive month client-side: "latest" (case-insensitive), "YYYY-MM"
# or "YYYY-MM-DD". The server enforces exactly this and answers 400, so failing
# fast here saves a round trip.
#
# The regex fixes the *shape* (as.Date() is lenient — it accepts "2026-7-1" and
# ignores trailing text), and as.Date() then rejects impossible *calendar*
# values: it returns NA for 2026-13, 2026-07-99 and 2026-02-29 while accepting
# the real leap day 2024-02-29.
.tl_check_month <- function(month) {
  invalid <- function() {
    stop(topolab_error(
      sprintf("Invalid month '%s'. Use \"latest\", YYYY-MM (e.g. 2026-07), or YYYY-MM-DD.",
              paste(month, collapse = ", ")),
      class = "topolab_validation_error"))
  }
  if (length(month) != 1L || !is.character(month) || is.na(month)) invalid()
  if (grepl("^latest$", month, ignore.case = TRUE)) return("latest")
  probe <- if (grepl("^[0-9]{4}-[0-9]{2}$", month)) {
    paste0(month, "-01")
  } else if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", month)) {
    month
  } else {
    invalid()
  }
  if (is.na(as.Date(probe, format = "%Y-%m-%d"))) invalid()
  month
}

#' List the datasets your organization licences
#'
#' The entry point for a backend integration: page through everything the
#' organization owns, then follow each entry's `links` (or its `table` slug) to
#' pull current files or monthly archives. The listing is filtered by the same
#' licence check the download routes enforce, so every entry is downloadable.
#'
#' @param client A `topolab_client`.
#' @param limit Page size, 1-200 (server default 50).
#' @param offset Row offset, >= 0 (server default 0).
#' @return A list with `items`, `total`, `limit` and `offset`. `total` counts
#'   every licensed dataset, not the size of this page. Each item carries
#'   `table`, `name`, `recordCount`, `latestArchiveMonth`,
#'   `latestArchiveFormats`, `archiveMonthsAvailable` and a nested `links` list
#'   (`current`, `archives`, `latestArchive`). The link URLs are absolute;
#'   `current` and `latestArchive` contain a literal `\{format\}` placeholder, and
#'   `latestArchive` is `NULL` when no archive is inside your retention window.
#' @export
tl_datasets_owned <- function(client, limit = NULL, offset = NULL) {
  q <- list(limit = .tl_check_count(limit, "limit", 1L, 200L),
            offset = .tl_check_count(offset, "offset", 0L))
  tl_perform_json(tl_req(client, "v1/dataset/owned", q))
}

#' Fetch every owned dataset, paging transparently
#'
#' Pages `tl_datasets_owned()` on `offset` until the reported `total` is
#' reached, stopping early on a short or empty page.
#'
#' @param client A `topolab_client`.
#' @param page_size Datasets per request, 1-200 (default 50).
#' @param total_limit Max datasets overall (NULL = all).
#' @return A list of owned-dataset entries, in server order. The reported total
#'   is attached as `attr(x, "total")`.
#' @export
tl_datasets_owned_all <- function(client, page_size = 50, total_limit = NULL) {
  page_size <- .tl_check_count(page_size, "page_size", 1L, 200L)
  total_limit <- .tl_check_count(total_limit, "total_limit", 1L)

  items <- list()
  total <- NA_integer_
  offset <- 0L
  repeat {
    page <- tl_datasets_owned(client, limit = page_size, offset = offset)
    if (is.na(total)) {
      reported <- suppressWarnings(as.integer(page$total %||% NA))
      if (length(reported) == 1L && !is.na(reported)) total <- reported
    }
    batch <- page$items %||% list()
    if (length(batch) == 0) break
    items <- c(items, batch)
    if (!is.null(total_limit) && length(items) >= total_limit) break
    if (length(batch) < page_size) break            # short page: nothing follows
    if (!is.na(total) && length(items) >= total) break
    offset <- offset + page_size
  }
  if (!is.null(total_limit) && length(items) > total_limit) {
    items <- items[seq_len(total_limit)]
  }
  attr(items, "total") <- if (is.na(total)) length(items) else total
  items
}

#' List a dataset's monthly archives
#'
#' Free — no credits are charged. The listing already reflects your retention
#' window (Team plans see a trailing 12 months; Enterprise and full-history
#' add-ons see everything), so it never lists a month that would 404.
#'
#' @param dataset A `topolab_dataset`.
#' @return A list of archive entries, newest month first. Each entry has
#'   `month` ("YYYY-MM"), `formats` and `archiveDate`.
#' @export
tl_archives <- function(dataset) {
  tl_perform_json(tl_req(dataset$client, paste0("v1/dataset/", dataset$slug, "/archives/list")))
}

#' Download one monthly archive to disk
#'
#' `month` is addressable three ways, so an integration can pull the newest
#' snapshot without listing first:
#' \describe{
#'   \item{`"latest"`}{Newest archive inside your retention window (case-insensitive).}
#'   \item{`"YYYY-MM"`}{That month.}
#'   \item{`"YYYY-MM-DD"`}{The month containing that date.}
#' }
#'
#' Malformed and impossible months (`"2026-13"`, `"2026-07-99"`, `"2026-02-29"`)
#' are rejected client-side with a `topolab_validation_error`, matching the
#' server's 400. A well-formed month with no archive available is a
#' `topolab_not_found_error` (404) — months outside your retention window and
#' months that have not started both answer 404 and are deliberately
#' indistinguishable, so the response never reveals an archive you cannot access.
#'
#' @param dataset A `topolab_dataset`.
#' @param path Destination file path; the archive is a zip.
#' @param month "latest" (default), "YYYY-MM" or "YYYY-MM-DD".
#' @param format One of "csv","json","geojson","kml","shp".
#' @return The path, invisibly.
#' @export
tl_archive <- function(dataset, path, month = "latest", format = "geojson") {
  month <- .tl_check_month(month)
  format <- .tl_check_bulk_format(format)
  req <- tl_req(dataset$client,
                paste0("v1/dataset/", dataset$slug, "/archives/", month, "/", format))
  .tl_stream_to_file(req, path)
}

#' Paginated coordinates with attributes
#'
#' Omit both parameters to receive the whole dataset in one response (capped at
#' 50000 rows); pass either to page.
#'
#' The paging facts arrive in response headers rather than an envelope, and are
#' attached to the result as attributes: `attr(x, "total")` (all rows in the
#' dataset, regardless of paging), `attr(x, "returned")` and `attr(x, "offset")`.
#' A missing or unparseable header falls back to the number of rows returned
#' (`total`, `returned`) or 0 (`offset`) rather than failing.
#'
#' `latitude` and `longitude` come back as **strings**, exactly as the API sends
#' them; they are not coerced. Use `as.numeric()` when you need numbers — the
#' numeric pair is also available as `row$location$coordinates`
#' (`c(longitude, latitude)`, GeoJSON order).
#'
#' @param dataset A `topolab_dataset`.
#' @param limit Rows per request, 1-50000.
#' @param offset Row offset, >= 0.
#' @return A list of rows, each with `id`, `location` (GeoJSON geometry),
#'   `latitude`, `longitude` and `metadata`, carrying the paging attributes
#'   described above.
#' @export
tl_coordinates <- function(dataset, limit = NULL, offset = NULL) {
  q <- list(limit = .tl_check_count(limit, "limit", 1L, 50000L),
            offset = .tl_check_count(offset, "offset", 0L))
  resp <- tl_perform_resp(tl_req(dataset$client,
                                 paste0("v1/dataset/", dataset$slug, "/coordinates"), q))
  rows <- httr2::resp_body_json(resp, simplifyVector = FALSE) %||% list()
  attr(rows, "total") <- tl_resp_header_int(resp, "X-Total-Count", length(rows))
  attr(rows, "returned") <- tl_resp_header_int(resp, "X-Returned-Count", length(rows))
  attr(rows, "offset") <- tl_resp_header_int(resp, "X-Offset", 0L)
  rows
}

# Build one data.frame column from the SQL row objects. Scalars are simplified
# to an atomic vector; anything with a non-scalar value stays a list column so
# no data is lost. JSON nulls and absent keys become NA.
.tl_sql_column <- function(rows, name) {
  if (length(rows) == 0) return(logical(0))
  values <- lapply(rows, function(row) {
    value <- if (name %in% names(row)) row[[name]] else NULL
    if (is.null(value) || length(value) == 0) NA else value
  })
  scalar <- all(lengths(values) == 1L) &&
    all(vapply(values, function(v) is.atomic(v) && !is.list(v), logical(1)))
  if (scalar) unlist(values, use.names = FALSE) else I(values)
}

.tl_sql_frame <- function(result) {
  columns <- as.character(unlist(result$columns %||% list(), use.names = FALSE))
  rows <- result$rows %||% list()
  if (length(columns) == 0 && length(rows) > 0) columns <- names(rows[[1]])
  if (length(columns) == 0) {
    df <- data.frame()
  } else {
    cols <- lapply(columns, function(nm) .tl_sql_column(rows, nm))
    names(cols) <- columns
    df <- as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
  }
  attr(df, "columns") <- columns
  attr(df, "row_count") <- result$rowCount %||% nrow(df)
  attr(df, "truncated") <- isTRUE(result$truncated)
  attr(df, "elapsed_ms") <- result$elapsedMs
  attr(df, "datasets") <- as.character(unlist(result$datasets %||% list(), use.names = FALSE))
  df
}

#' Run a read-only SQL query (Enterprise)
#'
#' Executes one read-only `SELECT` (or `WITH`) against the datasets your
#' organization licences. Requires the `sql-access` entitlement, which is part
#' of the Enterprise plan and is not sold separately; without it the call raises
#' a `topolab_addon_required_error` with `$addon == "sql-access"`. A query that
#' exceeds the server statement timeout raises a `topolab_query_timeout_error`.
#'
#' @param client A `topolab_client`.
#' @param query A single read-only SQL statement.
#' @param max_rows Max rows to return, 1-10000 (server default 10000).
#' @return A data.frame of result rows, with the rest of the response kept as
#'   attributes: `columns`, `row_count`, `truncated`, `elapsed_ms` and
#'   `datasets` (the dataset tables the query touched).
#' @export
tl_sql <- function(client, query, max_rows = NULL) {
  if (length(query) != 1L || !is.character(query) || is.na(query) || !nzchar(trimws(query))) {
    stop(topolab_error("query must be a single non-empty SQL string",
                       class = "topolab_validation_error"))
  }
  max_rows <- .tl_check_count(max_rows, "max_rows", 1L, 10000L)
  result <- tl_perform_json(tl_req_post(client, "v1/sql/query",
                                        list(sql = query, maxRows = max_rows)))
  .tl_sql_frame(result)
}
