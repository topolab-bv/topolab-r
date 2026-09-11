<p align="center">
  <img src="assets/banner.png" alt="Topolab R" width="100%">
</p>

<p align="center">
  <a href="https://cran.r-project.org/package=topolab"><img src="https://img.shields.io/cran/v/topolab?color=1E3A8A&label=CRAN" alt="CRAN version"></a>
  <a href="https://github.com/topolab-bv/topolab-r/actions/workflows/R-CMD-check.yml"><img src="https://img.shields.io/github/actions/workflow/status/topolab-bv/topolab-r/R-CMD-check.yml?branch=main&label=R-CMD-check" alt="R-CMD-check"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <a href="https://docs.topolab.nl"><img src="https://img.shields.io/badge/docs-topolab.nl-1E3A8A" alt="Documentation"></a>
</p>

<h1 align="center">topolab</h1>

<p align="center">
  The official <b>R</b> client for the <a href="https://topolab.nl">Topolab</a> dataset and geospatial API.<br>
  Reads datasets and OGC API – Features collections into R, as GeoJSON or <code>sf</code>.
</p>

---

## Install

📖 **Docs:** [topolab-bv.github.io/topolab-r](https://topolab-bv.github.io/topolab-r/) · full platform docs at [docs.topolab.nl](https://docs.topolab.nl)

```r
install.packages("topolab")
```

> **Pre-release:** until the first version is on CRAN, install from GitHub:
> `remotes::install_github("topolab-bv/topolab-r")`

`as_sf()` needs the [`sf`](https://r-spatial.github.io/sf/) package (a `Suggests`
dependency); on Linux you may also need the system GDAL, GEOS, and PROJ
libraries that `sf` requires.

## Quickstart

```r
# Read Domino's locations into an sf object
library(topolab)

tl  <- tl_client(api_key = "tlb_prod_...")
poi <- tl_dataset(tl, "nl-domino-poi") |> as_sf()
plot(poi["city"])
```

Your API key carries your scope and add-ons — feature access needs `GIS_ACCESS`,
downloads need `API_ACCESS`, and data routes require an organization-scoped key.
Read it from the environment rather than committing it to a script:

```r
tl <- tl_client(api_key = Sys.getenv("TOPOLAB_API_KEY"))
```

## Staging vs production

The client targets **production** (`https://api.topolab.nl`) by default. Point it
at staging with the `environment` argument:

```r
tl <- tl_client(api_key = "tlb_staging_...", environment = "staging") # https://api-staging.topolab.nl
```

Or set `TOPOLAB_ENV=staging`. An explicit `base_url=` always wins (self-hosting /
tests). Precedence: `base_url` → `environment` → `TOPOLAB_BASE_URL` →
`TOPOLAB_ENV` → production.

## Pull what you own

The integration loop the package is built for — ask what your organization
licences, then pull each dataset's newest monthly archive. No hard-coded slugs:

```r
for (owned in tl_datasets_owned_all(tl)) {
  ds <- tl_dataset(tl, owned$table)
  tl_archive(ds, paste0(owned$table, ".zip"), month = "latest", format = "geojson")
}
```

`month` takes `"latest"`, `"YYYY-MM"`, or `"YYYY-MM-DD"` (the month containing
that date). Team plans see a trailing 12 months of archives; Enterprise and
full-history add-ons see everything.

## What you can do

```r
# Browse the catalogue
page <- tl_datasets(tl, country = "NL", limit = 10)

# Everything your organization licences
tl_datasets_owned(tl, limit = 50)                 # one page ($items, $total)
tl_datasets_owned_all(tl)                         # all of them, paged for you

ds <- tl_dataset(tl, "nl-domino-poi")

tl_metadata(ds)                                   # dataset metadata
tl_sample(ds, format = "geojson")                 # free sample, no credits
tl_geojson(ds)                                    # full dataset as GeoJSON
tl_download(ds, "dominos.geojson")                # save an export to disk

# Monthly archives
tl_archives(ds)                                   # available months, newest first
tl_archive(ds, "dominos-2026-07.zip", month = "2026-07", format = "csv")

# Raw coordinates + attributes (paging facts in attributes)
rows <- tl_coordinates(ds, limit = 1000)
attr(rows, "total")

# Read-only SQL over the datasets you licence (Enterprise `sql-access`)
tl_sql(tl, "SELECT city, count(*) AS n FROM nl_domino_poi GROUP BY city")

# Spatial query (paged) over the OGC API
tl_items(ds, bbox = c(4.7, 52.2, 5.1, 52.5), limit = 100)
tl_items_all(ds, page_size = 500)                 # auto-paginate everything

as_sf(ds)                                         # materialize as an sf object
```

## Errors

Failures raise a classed `topolab_error` condition carrying the HTTP status, so
you can branch on the kind of failure:

| Condition class | When |
|---|---|
| `topolab_authentication_error` | missing or invalid API key (401) |
| `topolab_addon_required_error` | key lacks the add-on — `$addon` names it (403) |
| `topolab_access_denied_error` | dataset not accessible to your organization (403) |
| `topolab_insufficient_credits_error` | not enough credits (402) |
| `topolab_query_timeout_error` | SQL query exceeded the server statement timeout (408) |
| `topolab_rate_limit_error` | rate limited — `$retry_after`, retried automatically (429) |

```r
tryCatch(
  tl_geojson(ds),
  topolab_addon_required_error = function(e) message("Your key needs: ", e$addon)
)
```

`$addon` is the hyphenated add-on slug (`api-access`, `gis-access`,
`archived-data`, `high-value-data`, `sql-access`). Every condition also carries
`$status` and `$request_id` — quote the request id when reporting a problem.

## Documentation

- **Full docs:** [docs.topolab.nl](https://docs.topolab.nl)
- The bulk vs. spatial access patterns, credits, and add-ons are described in the
  [SDK conventions](https://docs.topolab.nl) and the
  [`topolab-sdk-spec`](../topolab-sdk-spec) repository.
- A runnable example lives in [`inst/examples/quickstart.R`](inst/examples/quickstart.R).

## Contributing

Issues and pull requests are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
Check the package locally with `R CMD check`.

## License

[MIT](LICENSE) © Topolab B.V.
