# topolab 0.2.0

* **Conditions carry `$code` and `$details`.** The engine's error envelope now
  carries a string `code` when the error has its own (upper-snake, such as
  `SPENDING_LIMIT_EXCEEDED`), and otherwise the numeric HTTP status, so `code` no
  longer always equals the status. `$code` is a character string or an integer,
  falling back to the HTTP status when the body has no usable code. `$details`
  is the envelope's allow-listed `details` as a named list, or `NULL`. `$status`
  stays the HTTP status, and condition classes are still chosen from it: a 403
  with `SPENDING_LIMIT_EXCEEDED` is a `topolab_access_denied_error`.
  `docs/errors.md` lists the known string codes and what they mean.
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
