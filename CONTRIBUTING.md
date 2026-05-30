# Contributing to topolab (R)

Thanks for your interest in improving the Topolab R package.

## Development setup

The package wraps the API with [`httr2`](https://httr2.r-lib.org/). For local
development you'll want:

```r
install.packages(c("httr2", "jsonlite", "testthat", "withr", "roxygen2", "pkgload"))
# optional, for as_sf():
install.packages("sf")
```

## Checks

```r
pkgload::load_all(".")                 # load the package for interactive work
testthat::test_dir("tests/testthat")   # run the test suite
roxygen2::roxygenise(".")              # regenerate man/ and NAMESPACE
```

Then the full CRAN-style check:

```bash
R CMD build .
_R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran topolab_*.tar.gz
```

Tests mock HTTP with `httr2::local_mocked_responses` against the JSON fixtures in
`tests/testthat/fixtures/` and fail gracefully with no network, per CRAN policy.

## Conventions

The public surface is shared across the Python, TypeScript, and R SDKs and is
defined in [`topolab-sdk-spec/conventions.yaml`](../topolab-sdk-spec). Keep the R
function names (`tl_client`, `tl_dataset`, `tl_items`, `as_sf`, …) aligned with
that file when you change the API.

## Before opening a PR

- `R CMD check` reports no errors or warnings
- New behaviour has a `testthat` test
- `man/` and `NAMESPACE` are regenerated via roxygen

## Releasing

Releases are gated until publishing is enabled. The pre-CRAN channel is
[r-universe](https://r-universe.dev/); formal CRAN submission is a later manual
step.
