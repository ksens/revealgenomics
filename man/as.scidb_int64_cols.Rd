% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/scidb-helper-functions.R
\name{as.scidb_int64_cols}
\alias{as.scidb_int64_cols}
\title{wrapper for as.scidb when supplying int64 types

When type argument of as.scidb has int64-s, there are issues uploading
with both \code{input} and \code{aio_input} (see https://github.com/Paradigm4/SciDBR/issues/189)
Avoid this by converting int64 fields in R before upload.}
\usage{
as.scidb_int64_cols(db, df1, int64_cols, ...)
}
\arguments{
\item{db}{database connection object}

\item{df1}{dataframe to be uploaded}

\item{int64_cols}{columns which need to be converted to int64-s}
}
\description{
wrapper for as.scidb when supplying int64 types

When type argument of as.scidb has int64-s, there are issues uploading
with both \code{input} and \code{aio_input} (see https://github.com/Paradigm4/SciDBR/issues/189)
Avoid this by converting int64 fields in R before upload.
}
