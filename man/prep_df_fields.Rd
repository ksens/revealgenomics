% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/helper-functions.R
\name{prep_df_fields}
\alias{prep_df_fields}
\title{Compare with mandatory fields passed by user}
\usage{
prep_df_fields(df, mandatory_fields)
}
\description{
Rename remaining columns of dataframe as info_<column-name>
Take the info columns that are non-string and convert to string
}
