# Guide

## Pull what you own

This is the loop the package exists for: ask what your organization licences,
then pull each dataset's newest snapshot. No hard-coded slugs, and nothing to
keep in sync — `tl_datasets_owned_all()` is filtered by the same licence check
the download routes enforce, so everything it returns is downloadable.

```r
tl <- tl_client()                       # reads TOPOLAB_API_KEY

for (owned in tl_datasets_owned_all(tl)) {
  ds <- tl_dataset(tl, owned$table)
  tl_archive(ds, paste0(owned$table, ".zip"), month = "latest", format = "geojson")
}
```

One page at a time, if you would rather drive the paging yourself:

```r
page <- tl_datasets_owned(tl, limit = 50, offset = 0)
page$total                              # every licensed dataset, not this page
vapply(page$items, function(d) d$table, character(1))
```

Each entry also carries absolute `links`, so an integration can follow URLs
instead of building paths:

```r
owned <- page$items[[1]]
owned$links$archives                    # .../archives/list
owned$links$latestArchive               # .../archives/latest/{format}
owned$links$current                     # .../files/{format}
```

`current` and `latestArchive` contain a literal `{format}` placeholder;
`latestArchive` is `NULL` when no archive falls inside your retention window.

## Monthly archives

`tl_archives()` lists the snapshots you can actually reach, newest month first:

```r
ds <- tl_dataset(tl, "nl-domino-poi")
archives <- tl_archives(ds)
archives[[1]]$month                     # "2026-07"
archives[[1]]$formats                   # "csv", "geojson", "json", "kml", "shp"
```

### Addressing an archive

`month` accepts three forms:

| Value | Meaning |
|---|---|
| `"latest"` | Newest archive inside your retention window (case-insensitive) |
| `"YYYY-MM"` | That month |
| `"YYYY-MM-DD"` | The month containing that date |

```r
tl_archive(ds, "poi-latest.zip")                          # latest, geojson
tl_archive(ds, "poi-2026-07.zip", month = "2026-07", format = "csv")
tl_archive(ds, "poi-july.zip",    month = "2026-07-15")   # the month containing the date
```

A malformed or impossible month (`"2026-13"`, `"2026-07-99"`, `"2026-02-29"` —
2026 is not a leap year) is a **400**, and the package rejects it locally with a
`topolab_validation_error` before spending the round trip. A real month with no
archive available is a **404**: months outside your retention window and months
that have not started both answer 404 and are deliberately indistinguishable, so
the response never reveals an archive you cannot access.

### Retention

Team plans see a trailing 12 months of archives; Enterprise and full-history
add-ons see everything. `tl_archives()` already reflects your window, so it never
lists a month that would 404.

## Coordinates

`tl_coordinates()` returns raw coordinate rows with their attribute bag. The
paging facts arrive in response headers rather than an envelope, and the package
attaches them as attributes:

```r
rows <- tl_coordinates(ds, limit = 1000, offset = 0)
attr(rows, "total")      # all rows in the dataset, regardless of paging
attr(rows, "returned")   # rows in this response
attr(rows, "offset")     # offset applied
```

Omit both arguments to take the whole dataset in one response (capped at 50000
rows). `latitude` and `longitude` come back as **strings**, exactly as the API
sends them, and are not coerced — convert explicitly when you need numbers:

```r
lat <- as.numeric(rows[[1]]$latitude)
lon <- as.numeric(rows[[1]]$longitude)
rows[[1]]$location$coordinates          # numeric c(lon, lat), GeoJSON order
```

## SQL (Enterprise)

`tl_sql()` runs one read-only `SELECT` (or `WITH`) against the datasets you
licence. It requires the `sql-access` entitlement, which is part of the
Enterprise plan and is not sold separately.

```r
df <- tl_sql(tl, "SELECT city, count(*) AS n FROM nl_domino_poi GROUP BY city", max_rows = 500)
attr(df, "row_count")
attr(df, "truncated")    # TRUE when max_rows cut the result short
attr(df, "elapsed_ms")
attr(df, "datasets")     # the dataset tables the query touched
```

Rows come back as a data.frame; the rest of the response is kept as attributes.
A query that exceeds the server statement timeout raises
`topolab_query_timeout_error`.

## Browse the catalog

```r
page <- tl_datasets(tl, country = "NL", limit = 10)
page$data[[1]]$table
```

## Dataset metadata and samples

```r
ds <- tl_dataset(tl, "nl-domino-poi")
meta <- tl_metadata(ds)
sample <- tl_sample(ds, "geojson")   # csv/json/geojson/kml
```

## Query features in an area (spatial, paged)

`tl_items()` addresses the collection by slug directly — the OGC `collectionId`
**is** the dataset slug, so there is no metadata round-trip.

```r
fc <- tl_items(ds, bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
```

### Fetch everything (concurrent paging)

`tl_items_all()` fetches the first page, then pulls the remaining pages
**concurrently** via `httr2::req_perform_parallel` (driven by `numberMatched`):

```r
all <- tl_items_all(ds, page_size = 500)               # parallel by default
all <- tl_items_all(ds, page_size = 500, parallel = FALSE)  # strictly sequential
all <- tl_items_all(ds, page_size = 500, total_limit = 2000)
```

Tune the number of simultaneous requests with `max_concurrency` (default 6).

## Pull a whole dataset (bulk)

```r
fc <- tl_geojson(ds)                          # parsed FeatureCollection (list)
tl_download(ds, "dominos-nl.geojson", "geojson")
```

`tl_download()` and `tl_archive()` stream to a temp file and rename atomically,
so an interrupted transfer never leaves a truncated file at the destination.

## Spatial objects (`sf`)

```r
library(sf)
poi <- as_sf(ds)        # sf data frame
```
