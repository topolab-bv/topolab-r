# Errors

Failures are raised as **typed conditions** you can catch by class. Every class
inherits from `topolab_error`.

| Condition class | When |
|---|---|
| `topolab_authentication_error` | missing or invalid API key (401) |
| `topolab_insufficient_credits_error` | not enough credits — `$required` / `$available` (402) |
| `topolab_addon_required_error` | key lacks the add-on — `$addon` names it (403) |
| `topolab_access_denied_error` | dataset not accessible to your organization, or the monthly spending limit is reached (`$code == "SPENDING_LIMIT_EXCEEDED"`) (403) |
| `topolab_not_found_error` | unknown dataset, collection, or archive month (404) |
| `topolab_query_timeout_error` | SQL query exceeded the server statement timeout (408) |
| `topolab_rate_limit_error` | rate limited (`$code` `RATE_LIMIT_EXCEEDED`) or the key's usage quota is used up (`USAGE_QUOTA_EXCEEDED`) — `$retry_after`, retried automatically (429) |
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

```json
{ "code": "SPENDING_LIMIT_EXCEEDED",
  "message": "Organization monthly spending limit exceeded",
  "details": { "limit": 5000, "consumed": 4995, "remaining": 5,
               "periodEnd": "2026-11-30T23:59:59.999Z" },
  "path": "/v1/dataset/{table}/files/geojson", "method": "GET",
  "time": "2026-11-07T11:52:28.000Z", "requestId": "8f0c41d2…" }
```

There is **no `statusCode` field**. `code` is a **string** when the error has its
own code (upper-snake, such as `SPENDING_LIMIT_EXCEEDED`) and otherwise the
**numeric HTTP status**, so it does not always equal the status. The package
chooses the condition class from the **HTTP status**, never from a body field,
and `$code` refines the meaning inside a class: a 403 with
`SPENDING_LIMIT_EXCEEDED` is still a `topolab_access_denied_error`.

Each condition built from a response carries:

| Field | Type | Meaning |
|---|---|---|
| `$status` | integer | HTTP status of the response. Use this for numeric checks. |
| `$code` | character or integer | The envelope's `code`; the HTTP status when the body has none (for example a proxy's error page). |
| `$details` | named list or `NULL` | The envelope's allow-listed `details`, when present. |
| `$message` | character | Server message |
| `$request_id` | character | `X-Request-Id` header, falling back to the body's `requestId` |

Conditions raised before a request is sent (client-side validation, a missing
key) carry no `$status`, `$code` or `$details`. Quote `$request_id` when
reporting a problem.

```r
ds <- tl_dataset(tl, "nl-domino-poi")
tryCatch(
  tl_download(ds, "poi.geojson"),
  topolab_access_denied_error = function(e) {
    if (identical(e$code, "SPENDING_LIMIT_EXCEEDED")) {
      message("Monthly limit reached; resets at ", e$details$periodEnd)
    } else {
      stop(e)
    }
  }
)
```

Compare string codes with `identical()` (or `==` after checking
`is.character(e$code)`). If you used to read the body's `code` as the HTTP
status, read `e$status` instead.

## Known string codes

Codes this package's calls can return:

| Status | `$code` | Raised as | Meaning | `$details` |
|---|---|---|---|---|
| 403 | `SPENDING_LIMIT_EXCEEDED` | `topolab_access_denied_error` | A metered call (download, SQL) would pass the organization's monthly spending limit. | `limit`, `consumed`, `remaining` (numbers), `periodEnd` (ISO 8601 timestamp) |
| 400 | `SQL_DATA_ERROR` | `topolab_validation_error` | The SQL query raised a data error while evaluating a value, such as a bad cast. The message names the SQLSTATE. | none |
| 400 | `MAX_NODES_EXCEEDED`, `MAX_DEPTH_EXCEEDED`, `MAX_ARRAY_LENGTH_EXCEEDED`, `MAX_KEYS_EXCEEDED` | `topolab_validation_error` | A JSON request body is larger or deeper than the server accepts. | none |
| 400 | `PROTOTYPE_POLLUTION_KEY` | `topolab_validation_error` | A JSON request body contains a forbidden key (`__proto__`, `constructor`, `prototype`). | none |
| 429 | `RATE_LIMIT_EXCEEDED` | `topolab_rate_limit_error` | The API key passed its per-minute rate limit. The response also carries a `Retry-After` header. | `retryAfter` (seconds), `limit`, `remaining` (numbers), `resetAt` (ISO 8601 timestamp) |
| 429 | `USAGE_QUOTA_EXCEEDED` | `topolab_rate_limit_error` | The API key has used up its usage quota. Waiting does not help; `$retry_after` is `NULL`. | `quota`, `used` (numbers) |

Numeric codes that carry `$details`:

| `$code` | Raised as | `$details` |
|---|---|---|
| `402` | `topolab_insufficient_credits_error` (also on `$required` / `$available`) | `required`, `available` |
| `413` | `topolab_validation_error` | `quotaBytes`, `usageBytes`, `additionalBytes` (Data Studio uploads) |

Other parts of the API use further codes, listed in the
[SDK conventions](https://github.com/topolab-bv/topolab-sdk-spec/blob/main/conventions.md#known-string-codes):
`HIGH_VALUE_DATA_REQUIRED` (403, `details.columns` / `details.datasetIds`),
`REGENERATE_REQUIRED` (410) and `METADATA_NOT_READABLE` (400) from Data Studio,
`SSO_REQUIRED` (403) and `SSO_CHECK_UNAVAILABLE` (503) from sign-in, and the
order add-on and delivery-destination codes. The chat API reports a failed turn
on its event stream with lower-snake codes such as `ai_busy`, `ai_interrupted`
and `ai_cancelled`; this package does not call it.

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
via `httr2::req_retry`. When the server says how long to wait, the package waits
that long instead, reading in order the `Retry-After` header (seconds, or an HTTP
date), `details.retryAfter`, and the top-level `retryAfter` that engines older
than the `RATE_LIMIT_EXCEEDED` code send. `$retry_after` holds the same value.
`max_retries` (default 3) is the number of retries **after** the first attempt.
A `408` query timeout is **not** retried — rerun a cheaper query instead.
