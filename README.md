# topolab (R)

Official R client for the [Topolab](https://topolab.nl) dataset and geospatial API. Reads datasets and OGC API - Features collections into R, returning GeoJSON and optionally `sf` objects.

```r
install.packages("topolab")
```

## Quickstart

```r
# Read Domino's locations into an sf object
library(topolab)

tl <- tl_client(api_key = "tlb_prod_...")
poi <- tl_dataset(tl, "nl-domino-poi") |> as_sf()
plot(poi["city"])
```

The key carries your scope and addons — feature access needs `GIS_ACCESS`,
downloads need `API_ACCESS`, and data routes require an organization-scoped key.
Read it from the environment with `tl_client(api_key = Sys.getenv("TOPOLAB_API_KEY"))`.

## Browsing & spatial queries

```r
page <- tl_datasets(tl, country = "NL", limit = 10)

ds <- tl_dataset(tl, "nl-domino-poi")
fc  <- tl_items(ds, bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
all <- tl_items_all(ds, page_size = 500)   # auto-paginates
```

## Errors

Failures raise a classed `topolab_error` condition carrying the HTTP status —
e.g. `topolab_addon_required_error` (with `$addon`),
`topolab_insufficient_credits_error`, `topolab_rate_limit_error`. Catch with
`tryCatch(..., topolab_error = function(e) ...)`.

MIT licensed. `as_sf()` requires the `sf` package (a Suggests dependency).
