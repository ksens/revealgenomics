% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/functions.R
\name{join_info}
\alias{join_info}
\title{Join flex fields}
\usage{
join_info(qq, arrayname, mandatory_fields_only = FALSE,
  replicate_query_on_info_array = FALSE, con = NULL)
}
\arguments{
\item{replicate_query_on_info_array}{when joining info array, replicate query carried
out on primary array
e.g. \code{filter(gh_secure.BIOSAMPLE, dataset_id=32)}
replicates to \code{filter(gh_secure.BIOSAMPLE_INFO, dataset_id=32)}.
Turned off by default}
}
\description{
Join flex fields
}
