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
  resp <- httr2::req_perform(req, path = path)
  if (httr2::resp_status(resp) >= 400) abort_from_response(resp)
  invisible(path)
}

.tl_collection_id <- function(dataset) {
  if (is.null(dataset$collection_id)) {
    md <- tl_metadata(dataset)
    paste0("dataset-", md$id)
  } else {
    dataset$collection_id
  }
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
  cid <- .tl_collection_id(dataset)
  q <- list(limit = limit, offset = offset, category = category, city = city, country = country)
  if (!is.null(bbox)) q$bbox <- paste(bbox, collapse = ",")
  tl_perform_json(tl_req(dataset$client, paste0("v1/ogc/collections/", cid, "/items"), q))
}

#' Auto-paginate all features
#'
#' @param dataset A `topolab_dataset`.
#' @param page_size Features per request (<=1000).
#' @param total_limit Max features overall (NULL = all).
#' @param bbox,category,city,country Filters.
#' @return A GeoJSON FeatureCollection (list) with all matched features.
#' @export
tl_items_all <- function(dataset, page_size = 100, total_limit = NULL,
                         bbox = NULL, category = NULL, city = NULL, country = NULL) {
  cid <- .tl_collection_id(dataset)
  all <- list()
  offset <- 0
  repeat {
    q <- list(limit = page_size, offset = offset, category = category, city = city, country = country)
    if (!is.null(bbox)) q$bbox <- paste(bbox, collapse = ",")
    fc <- tl_perform_json(tl_req(dataset$client, paste0("v1/ogc/collections/", cid, "/items"), q))
    feats <- fc$features
    if (length(feats) == 0) break
    all <- c(all, feats)
    if (!is.null(total_limit) && length(all) >= total_limit) {
      all <- all[seq_len(total_limit)]
      break
    }
    if (length(feats) < page_size) break
    offset <- offset + page_size
  }
  list(type = "FeatureCollection", features = all)
}
