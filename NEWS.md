# topolab 0.1.0

* Initial preview release.
* `tl_client()` with API-key auth (`TOPOLAB_API_KEY`), retries, and a typed
  `topolab_error` condition hierarchy.
* Dataset access: `tl_datasets()` (catalog), `tl_metadata()`, `tl_sample()`,
  `tl_geojson()`, and `tl_download()`.
* Spatial access over the OGC API – Features: `tl_items()` and `tl_items_all()`
  (auto-pagination), with slug → collection resolution.
* `as_sf()` converts a dataset or feature collection to an `sf` object
  (requires the suggested `sf` package).
