# topolab (development version)

* Backend integration surface for pulling what your organization licences:
  `tl_datasets_owned()` and `tl_datasets_owned_all()` (auto-paging),
  `tl_archives()` and `tl_archive()` for monthly snapshots, `tl_coordinates()`
  for raw coordinate rows, and `tl_sql()` for read-only SQL (Enterprise
  `sql-access`).
* `tl_archive()` validates `month` (`"latest"`, `"YYYY-MM"`, `"YYYY-MM-DD"`) and
  `format` client-side, rejecting impossible calendar values such as `2026-13`,
  `2026-07-99` and `2026-02-29` before the request is sent.
* **Behaviour change:** `tl_download()` now validates `format` client-side
  against `csv`, `json`, `geojson`, `kml` and `shp`, sharing one check with
  `tl_archive()`. An unsupported format previously cost a round trip and came
  back as a server 400 (`topolab_validation_error` with `$status == 400`); it
  now raises a `topolab_validation_error` locally, with no `$status`, before the
  request is sent. This matches the Python, TypeScript and Go SDKs.
* `tl_coordinates()` attaches the `X-Total-Count` / `X-Returned-Count` /
  `X-Offset` paging headers as attributes, falling back safely when a header is
  absent or unparseable.
* Fixed add-on detection: add-on identifiers are hyphenated slugs, and the
  previous `\w+` capture stopped at the hyphen, so every add-on 403 degraded to
  a plain access denial. Both server phrasings now normalise to the same slug
  on `$addon` (`api-access`, `archived-data`, ...).
* Errors now carry `$request_id`, taken from the `X-Request-Id` header and
  falling back to the body's `requestId`. Conditions are mapped from the HTTP
  status; the error envelope has no `statusCode` field.
* New `topolab_query_timeout_error` condition for HTTP 408 (a SQL query over the
  server statement timeout).

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
