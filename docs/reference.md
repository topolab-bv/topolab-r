# API reference

## Client

```r
tl_client(
  api_key = Sys.getenv("TOPOLAB_API_KEY"),
  base_url = NULL,        # explicit override (wins over environment)
  environment = NULL,     # "production" (default) | "staging"
  timeout = 60,           # seconds
  max_retries = 3
)

tl_dataset(client, slug)  # lazy handle for one dataset
```

## Functions

| Function | Returns | Notes |
|---|---|---|
| `tl_datasets(client, page, limit, search, theme, country, sort_by, sort_order)` | list | Catalog listing (`$data`, `$meta`) |
| `tl_datasets_owned(client, limit = NULL, offset = NULL)` | list | One page of licensed datasets (`$items`, `$total`, `$limit`, `$offset`); `limit` 1–200, `offset` ≥ 0 |
| `tl_datasets_owned_all(client, page_size = 50, total_limit = NULL)` | list | Every licensed dataset; total in `attr(x, "total")` |
| `tl_metadata(dataset, locale = NULL)` | list | Dataset metadata |
| `tl_sample(dataset, format = "geojson")` | list \| character | Free preview; `csv`/`json`/`geojson`/`kml` |
| `tl_geojson(dataset)` | list | Full dataset (requires `api-access`) |
| `tl_download(dataset, path, format = "geojson")` | path (invisibly) | Streamed; `csv`/`json`/`geojson`/`kml`/`shp`, checked client-side |
| `tl_archives(dataset)` | list | Monthly archives, newest first (`month`, `formats`, `archiveDate`) |
| `tl_archive(dataset, path, month = "latest", format = "geojson")` | path (invisibly) | Streamed zip; `month` is `latest`/`YYYY-MM`/`YYYY-MM-DD` |
| `tl_coordinates(dataset, limit = NULL, offset = NULL)` | list | Coordinate rows; paging in attributes; `limit` ≤ 50000 |
| `tl_sql(client, query, max_rows = NULL)` | data.frame | Enterprise `sql-access`; result metadata in attributes |
| `tl_items(dataset, bbox, limit = 100, offset, category, city, country)` | list | One page of OGC features |
| `tl_items_all(dataset, page_size = 100, total_limit = NULL, bbox, ..., parallel = TRUE, max_concurrency = 6)` | list | Auto-paginates; concurrent by default |
| `as_sf(dataset)` | `sf` | Requires the `sf` package |

## Owned datasets

`tl_datasets_owned()` returns the raw page. `total` counts **every** licensed
dataset, not the size of the page. Each item:

| Field | Meaning |
|---|---|
| `table` | Dataset slug — the identifier used everywhere else, and the OGC `collectionId` |
| `name` | Display name |
| `recordCount` | Rows in the current file |
| `latestArchiveMonth` | Newest archive month inside your retention window, or `NULL` |
| `latestArchiveFormats` | Formats that month is available in |
| `archiveMonthsAvailable` | How many archive months are inside the window |
| `links` | Absolute URLs: `current`, `archives`, `latestArchive` |

`links$current` and `links$latestArchive` contain a literal `{format}`
placeholder; `links$latestArchive` is `NULL` when no archive is in range.

`tl_datasets_owned_all()` pages on `offset` until `total` is reached, stopping
early on a short or empty page, and returns a flat list of those items with the
reported total in `attr(x, "total")`.

## Bulk formats

`tl_download()` and `tl_archive()` accept `csv`, `json`, `geojson`, `kml` and
`shp`, and share one client-side check: an unsupported format raises a
`topolab_validation_error` before the request is sent rather than costing a
round trip to be told 400 by the server. (`tl_sample()` is a different set —
`csv`, `json`, `geojson`, `kml` — and is not checked locally.)

## Archive months

`month` accepts `"latest"` (case-insensitive), `"YYYY-MM"`, or `"YYYY-MM-DD"`
(the month containing that date). Malformed and impossible values — `"2026-13"`,
`"2026-07-99"`, `"2026-02-29"` — are rejected client-side as a
`topolab_validation_error`, matching the server's 400. A well-formed month with
no archive available is a 404 (`topolab_not_found_error`); out-of-retention and
not-yet-started months are deliberately indistinguishable from it.

Team plans see a trailing 12 months of archives; Enterprise and full-history
add-ons see everything.

## Coordinate paging attributes

`tl_coordinates()` reads the paging facts from the `X-Total-Count`,
`X-Returned-Count` and `X-Offset` response headers and attaches them as
`attr(x, "total")`, `attr(x, "returned")` and `attr(x, "offset")`. A missing or
unparseable header falls back to the number of rows returned (`total`,
`returned`) or `0` (`offset`) rather than failing.

`latitude` and `longitude` are returned as **strings**, exactly as the API sends
them, and are not coerced. `location$coordinates` holds the same pair as numbers
in GeoJSON order (`lon, lat`).

## SQL result attributes

`tl_sql()` returns the rows as a data.frame. Columns whose values are all
scalars become ordinary vectors; anything else stays a list column, and JSON
nulls become `NA`. The rest of the response is kept as attributes:

| Attribute | Meaning |
|---|---|
| `columns` | Column names in server order |
| `row_count` | Rows returned |
| `truncated` | `TRUE` when `max_rows` cut the result short |
| `elapsed_ms` | Server-side query time |
| `datasets` | Dataset tables the query touched |

## Collections are addressed by slug

The OGC `collectionId` is the dataset's `table` slug (e.g. `nl-domino-poi`) — the
same value you pass to `tl_dataset()`. The package calls
`v1/ogc/collections/{slug}/items` directly; there is no slug→uuid resolution.
