# Topolab R Package

`topolab` reads [Topolab](https://topolab.nl) datasets and OGC API - Features
collections into R, returning GeoJSON and optionally `sf` objects for spatial
analysis. It is a thin, dependency-light wrapper over `httr2`.

!!! info "Full platform docs"
    This site is the technical reference for the R package. The full platform
    documentation lives at [docs.topolab.nl](https://docs.topolab.nl).

## Install

```r
install.packages("topolab")
```

> **Pre-release:** until the first version is on CRAN, install from GitHub:
> `remotes::install_github("topolab-bv/topolab-r")`

`as_sf()` needs the [`sf`](https://r-spatial.github.io/sf/) package (a `Suggests`
dependency); on Linux you may also need the system GDAL, GEOS, and PROJ libraries.

## Quickstart

```r
library(topolab)

# Page Domino's locations within an Amsterdam bounding box
tl <- tl_client(api_key = "tlb_prod_...")
fc <- tl_items(tl_dataset(tl, "nl-domino-poi"),
               bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
length(fc$features)
```

Your API key carries your scope and add-ons — spatial queries need `GIS_ACCESS`,
downloads need `API_ACCESS`, and data routes require an organization-scoped key.
Prefer the environment over hard-coding (`tl_client()` reads `TOPOLAB_API_KEY`
by default):

```r
Sys.setenv(TOPOLAB_API_KEY = "tlb_prod_...")
tl <- tl_client()
```

## Staging vs production

The client targets **production** (`https://api.topolab.nl`) by default. Switch
with the `environment` argument:

```r
tl <- tl_client(api_key = "tlb_staging_...", environment = "staging")
```

Or set `TOPOLAB_ENV=staging`. An explicit `base_url` always wins. Precedence:
`base_url` → `environment` → `TOPOLAB_BASE_URL` → `TOPOLAB_ENV` → production.
