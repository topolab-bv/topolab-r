library(topolab)

tl <- tl_client() # reads TOPOLAB_API_KEY
cat("Datasets:\n")
page <- tl_datasets(tl, limit = 5)
print(vapply(page$data, function(d) d$table, character(1)))
