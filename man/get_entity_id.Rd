% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/entity-schema.R
\name{get_entity_id}
\alias{get_entity_id}
\title{Get entity id}
\usage{
get_entity_id(entity)
}
\description{
Get entity id from entity name
}
\examples{
get_entity_id('PROJECT')                 # 1002
get_entity_id('VARIANT')                 # 8002
get_entity_id(c('PROJECT', 'VARIANT'))   # c(1002, 8002)
\dontrun{
get_entity_id(c('PROJECT', 'asdf'))      # Error
}
}
