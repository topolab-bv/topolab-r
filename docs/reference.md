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
| `tl_metadata(dataset, locale = NULL)` | list | Dataset metadata |
| `tl_sample(dataset, format = "geojson")` | list \| character | Free preview; `csv`/`json`/`geojson`/`kml` |
| `tl_geojson(dataset)` | list | Full dataset (requires `API_ACCESS`) |
| `tl_download(dataset, path, format = "geojson")` | path (invisibly) | Streamed; `csv`/`json`/`geojson`/`kml`/`shp` |
| `tl_items(dataset, bbox, limit = 100, offset, category, city, country)` | list | One page of OGC features |
| `tl_items_all(dataset, page_size = 100, total_limit = NULL, bbox, ..., parallel = TRUE, max_concurrency = 6)` | list | Auto-paginates; concurrent by default |
| `as_sf(dataset)` | `sf` | Requires the `sf` package |

## Collections are addressed by slug

The OGC `collectionId` is the dataset's `table` slug (e.g. `nl-domino-poi`) — the
same value you pass to `tl_dataset()`. The package calls
`v1/ogc/collections/{slug}/items` directly; there is no slug→uuid resolution.
