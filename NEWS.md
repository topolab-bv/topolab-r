# topolab (development version)

* `tl_download()` and `tl_archive()` fetch files through the link route,
  `POST /v1/dataset/{table}/exports`: `tl_download()` asks for the current
  month's file (`bundle = "file"`), `tl_archive()` for one month's zip
  (`month`, `bundle = "zip"`). A 200 names a 10-minute signed link, fetched
  with a plain `httr2::request(url)` that sends no API key. A 202 means the file
  is being prepared: the SDK waits `retryAfterSeconds` (at least 1 second, 5
  when absent) and asks again, for at most 30 minutes, then raises a
  `topolab_server_error` with `$code` `"FILE_PREPARING"` and `$details$build`.
* A 404 or 405 from the link route (a server without it) falls back, on that
  call only, to the old route (`GET .../files/{format}` or
  `GET .../archives/{month}/{format}`) with today's behaviour and retries. 402,
  403 and 5xx answers from the link route are raised, never a fallback.
* An error while fetching the signed link is raised with the class of its
  status and a message that does not repeat the storage host's body.
* A download now always writes the response body to the destination, also when
  httr2 keeps it in memory (a mocked response), so no rename warning is left.
* `tl_sample()` and `tl_geojson()` are unchanged.
* `docs/errors.md` lists `FILE_PREPARING`, `FILE_BUILD_FAILED` and
  `FILE_TOO_LARGE`.

* The staging base URL is now `https://api.topolab.dev` (was
  `https://api-staging.topolab.nl`). `environment = "staging"` resolves to it.

# topolab 0.2.1

* Fixed: a retryable response (429, 500, 502, 503, 504) whose body had no
  top-level `retryAfter` made `httr2::req_retry()` abort with "The `after`
  callback to `req_retry()` must return a single number or NA, not `NULL`"
  instead of retrying. The callback now returns `NA` when the server gives no
  wait, so httr2 falls back to its backoff.
* 429 handling follows the engine's `RATE_LIMIT_EXCEEDED` and
  `USAGE_QUOTA_EXCEEDED` codes. The wait is read from the `Retry-After` header
  (seconds or an HTTP date), then `details.retryAfter`, then the older top-level
  `retryAfter`; `$retry_after` and the retry delay use the same rule.
* Fixed: a `Retry-After` header that is neither seconds nor an HTTP date (such
  as `soon` from a proxy) raised "NAs introduced by coercion" on every error and
  every retry. It is now skipped silently and the body's wait applies.
* Fixed: a numeric `code` outside R's integer range became `NA` with a coercion
  warning. It now falls back to the HTTP status.
* `docs/errors.md` lists both 429 codes and their `details`.
* `docs/errors.md` names the chat API's stream error codes in upper-snake case
  (`AI_BUSY`, `AI_INTERRUPTED`, `AI_CANCELLED`), matching the engine, which
  renamed every chat error code from lower-snake.

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
