# Guide

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

`tl_download()` streams to a temp file and renames atomically, so an interrupted
transfer never leaves a truncated file at the destination.

## Spatial objects (`sf`)

```r
library(sf)
poi <- as_sf(ds)        # sf data frame
```
