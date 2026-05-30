#' Read Topolab data as an sf object
#'
#' Materializes features as an `sf` object with geometry in WGS84 (EPSG:4326).
#' Dispatches on a `topolab_dataset` handle (which is downloaded first) or a
#' parsed GeoJSON feature-collection list.
#'
#' @param x A `topolab_dataset` or a parsed GeoJSON feature collection list.
#' @param ... Unused; present for S3 method consistency.
#' @return An `sf` object with geometry in WGS84 (EPSG:4326).
#' @export
as_sf <- function(x, ...) {
  UseMethod("as_sf")
}

#' @rdname as_sf
#' @export
as_sf.topolab_dataset <- function(x, ...) {
  as_sf(tl_geojson(x), ...)
}

#' @rdname as_sf
#' @export
as_sf.default <- function(x, ...) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop(topolab_error(
      "as_sf() requires the 'sf' package. Install it with install.packages('sf').",
      class = "topolab_configuration_error"))
  }
  # Write to a temp file and read with st_read():
  #   * a real .geojson file is GDAL's portable read path (reading inline JSON
  #     strings is undocumented/GDAL-version-dependent),
  #   * st_read() returns a plain sf data.frame, so we don't pull in the
  #     'tibble' package the way read_sf() does.
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"), tmp)
  sf::st_read(tmp, quiet = TRUE)
}
