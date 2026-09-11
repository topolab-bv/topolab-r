# Errors

Failures are raised as **typed conditions** you can catch by class. Every class
inherits from `topolab_error`.

| Condition class | When |
|---|---|
| `topolab_authentication_error` | missing or invalid API key (401) |
| `topolab_insufficient_credits_error` | not enough credits — `$required` / `$available` (402) |
| `topolab_addon_required_error` | key lacks the add-on — `$addon` names it (403) |
| `topolab_access_denied_error` | dataset not accessible to your organization (403) |
| `topolab_not_found_error` | unknown dataset, collection, or archive month (404) |
| `topolab_query_timeout_error` | SQL query exceeded the server statement timeout (408) |
| `topolab_rate_limit_error` | rate limited — `$retry_after`, retried automatically (429) |
| `topolab_configuration_error` | client misconfiguration (missing key, invalid base URL) |
| `topolab_validation_error` | invalid request parameters (400/4xx), including ones caught client-side |
| `topolab_server_error` | upstream error (5xx), retried automatically |

```r
ds <- tl_dataset(tl, "nl-domino-poi")
result <- tryCatch(
  tl_geojson(ds),
  topolab_addon_required_error = function(e) {
    message("Your key needs: ", e$addon)
    NULL
  }
)
```

## The error envelope

Every failure carries the same body, produced by the API's global exception
filter:

```json
{ "code": 403, "message": "This endpoint requires the api-access add-on",
  "path": "/v1/dataset/{table}/files/geojson", "method": "GET",
  "time": "2026-09-08T23:42:15.819Z", "requestId": "25c2a6a1…" }
```

There is **no `statusCode` field** — `code` merely mirrors the HTTP status, so
the package maps conditions from the **HTTP status** and never from a body
field. Each condition carries:

| Field | Meaning |
|---|---|
| `$status` | HTTP status code |
| `$message` | Server message |
| `$request_id` | `X-Request-Id` header, falling back to the body's `requestId` |

Quote `$request_id` when reporting a problem.

## Recognising an add-on requirement

Two message shapes carry an add-on requirement, and a 403 that matches neither
is an access denial:

| Message | `$addon` |
|---|---|
| `This endpoint requires the api-access add-on` | `api-access` |
| `Archive access requires the Archived Data add-on. Please upgrade to access historical data.` | `archived-data` |

Add-on identifiers are hyphenated slugs (`api-access`, `gis-access`,
`archived-data`, `high-value-data`, `sql-access`). Both phrasings normalise to
the same slug, so you can branch on `$addon` directly:

```r
tryCatch(
  tl_archive(ds, "poi.zip"),
  topolab_addon_required_error = function(e) {
    if (identical(e$addon, "archived-data")) message("Archives need the Archived Data add-on.")
  }
)
```

## Failing fast, before the round trip

Some invalid arguments are rejected locally as a `topolab_validation_error`
rather than sent, which saves a round trip and — on metered routes — a credit:

- an archive `month` that is malformed or not a real calendar month
  (`"2026-13"`, `"2026-07-99"`, `"2026-02-29"`),
- an unsupported bulk `format` on `tl_download()` or `tl_archive()`,
- `limit` / `offset` / `page_size` / `max_rows` outside their allowed range.

## Retries

Transient statuses (`429`, `500`, `502`, `503`, `504`) are retried with backoff
via `httr2::req_retry`, honouring a `retryAfter` body field when present.
`max_retries` (default 3) is the number of retries **after** the first attempt.
A `408` query timeout is **not** retried — rerun a cheaper query instead.
