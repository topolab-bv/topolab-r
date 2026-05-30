#' Read a dataset (or feature collection) as an sf object
#'
#' @param x A `topolab_dataset` or a parsed GeoJSON feature collection list.
#' @return An `sf` object with geometry in WGS84 (EPSG:4326).
#' @export
as_sf <- function(x) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop(topolab_error(
      "as_sf() requires the 'sf' package. Install it with install.packages('sf').",
      class = "topolab_configuration_error"))
  }
  fc <- if (inherits(x, "topolab_dataset")) tl_geojson(x) else x
  sf::read_sf(jsonlite::toJSON(fc, auto_unbox = TRUE, null = "null"))
}
