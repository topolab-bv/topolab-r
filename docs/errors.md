# Errors

Failures are raised as **typed conditions** you can catch by class. Every class
inherits from `topolab_error`.

| Condition class | When |
|---|---|
| `topolab_authentication_error` | missing or invalid API key (401) |
| `topolab_insufficient_credits_error` | not enough credits — `$required` / `$available` (402) |
| `topolab_addon_required_error` | key lacks the add-on — `$addon` names it (403) |
| `topolab_access_denied_error` | dataset not accessible to your organization (403) |
| `topolab_not_found_error` | unknown dataset or collection (404) |
| `topolab_rate_limit_error` | rate limited — `$retry_after`, retried automatically (429) |
| `topolab_configuration_error` | client misconfiguration (missing key, invalid base URL) |
| `topolab_validation_error` | invalid request parameters (400/4xx) |
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

## Retries

Transient statuses (`429`, `500`, `502`, `503`, `504`) are retried with backoff
via `httr2::req_retry`, honouring a `retryAfter` body field when present.
`max_retries` (default 3) is the number of retries **after** the first attempt.
