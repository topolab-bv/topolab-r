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

#' Download a dataset export to disk
#'
#' @param dataset A `topolab_dataset`.
#' @param path Destination file path.
#' @param format One of "csv","json","geojson","kml","shp".
#' @return The path, invisibly.
#' @export
tl_download <- function(dataset, path, format = "geojson") {
  req <- tl_req(dataset$client, paste0("v1/dataset/", dataset$slug, "/files/", format))
  # Stream to a temp file so an error response is never written to `path`, and a
  # partial download (connection dropped mid-body) cannot leave a truncated file
  # at the destination. Status is checked before the atomic rename.
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".part")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  resp <- httr2::req_perform(req, path = tmp)
  if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
  }
  invisible(path)
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
