#' to be run in Travis after the following notebooks have been run
#' - `04-load-api.Rmd`
#' - `06-updating-deleting.Rmd`
#' - `07-experiments-measurements.Rmd`
library(revealgenomics)
rg_connect()
stopifnot(nrow(get_datasets()) == 1)
stopifnot(nrow(get_experimentset()) == 1)
stopifnot(nrow(get_experiments()) == 3)
stopifnot(nrow(get_measurements()) == 3)

# check mandatory fields flag
stopifnot(all(dim(get_datasets()) == c(1, 10)))
stopifnot(all(dim(get_datasets(mandatory_fields_only = T)) == c(1, 8)))
stopifnot(all(dim(get_individuals()) == c(3, 10)))
stopifnot(all(dim(get_individuals(mandatory_fields_only = T)) == c(3, 7)))
stopifnot(all(dim(get_biosamples()) == c(3, 11)))
stopifnot(all(dim(get_biosamples(mandatory_fields_only = T)) == c(3, 8)))

stopifnot(all(dim(get_measurements()) == c(3, 12)))
stopifnot(class(try({get_measurements(mandatory_fields_only=T)}, silent = T)) == 'try-error')
