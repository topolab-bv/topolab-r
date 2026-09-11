library(topolab)

tl <- tl_client() # reads TOPOLAB_API_KEY

cat("Datasets:\n")
page <- tl_datasets(tl, limit = 5)
print(vapply(page$data, function(d) d$table, character(1)))

# The integration loop: everything the organization licences, then each
# dataset's newest monthly archive.
owned <- tl_datasets_owned_all(tl, total_limit = 3)
cat("\nLicensed datasets (", attr(owned, "total"), " in total):\n", sep = "")
for (entry in owned) {
  month <- entry$latestArchiveMonth
  cat(sprintf("  %-45s %s\n", entry$table,
              if (is.null(month)) "no archive in range" else month))
}

dir.create("archives", showWarnings = FALSE)
for (entry in owned) {
  # month: "latest", "YYYY-MM" or "YYYY-MM-DD" (the month containing that date)
  path <- tl_archive(tl_dataset(tl, entry$table),
                     file.path("archives", paste0(entry$table, ".zip")),
                     month = "latest", format = "geojson")
  cat("Downloaded ", path, "\n", sep = "")
}
