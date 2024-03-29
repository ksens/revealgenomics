#
# BEGIN_COPYRIGHT
#
# PARADIGM4 INC.
# This file is part of the Paradigm4 Enterprise SciDB distribution kit
# and may only be used with a valid Paradigm4 contract and in accord
# with the terms and conditions specified by that contract.
#
# Copyright (C) 2011 - 2018 Paradigm4 Inc.
# All Rights Reserved.
#
# END_COPYRIGHT
#

# Lower level functions for interpreting data in worksheet before ingesting into SciDB
# -- Not meant to be called directly by the API user.

#' helper function to rename columns
#' 
#' rename columns from excel template into revealgenomics format
#' 
#' 
load_helper_column_rename = function(dfx, revealgenomics_fields, worksheet_fields) {
  stopifnot(worksheet_fields %in% colnames(dfx))
  cat("Renaming columns:\n\t")
  cat(paste(worksheet_fields[worksheet_fields != revealgenomics_fields], 
            revealgenomics_fields[worksheet_fields != revealgenomics_fields], sep = " --> ", collapse = "\n\t"))
  cat("\n")
  x = revealgenomics_fields
  names(x) = worksheet_fields
  
  plyr::rename(dfx, replace = x)
}

#' Wrapper function combining common actions for preparing dataframe for loading to scidb
#' 
#' Applicable to `Individuals`, `Biosamples` and `Measurements` that are directly loaded 
#' from each row of `Subjects`, `Samples` and `Pipelines` sheet
load_helper_prepare_dataframe = function(workbook, record, def, 
                                         sheetName, entityName, worksheet_fields, 
                                         con = NULL) {
  data_df = template_helper_extract_record_related_rows(workbook = workbook,
                                                        sheetName = sheetName, 
                                                        record = record)
  # Extract relevant definitions 
  defi = template_helper_extract_definitions(sheetName = sheetName, 
                                             def = def)
  
  # Enforce that columns in data are defined in Definitions sheet
  template_helper_enforce_columns_defined(data_df = data_df, 
                                          definitions = defi)
  
  # Enforce that mandatory columns listed in Definitions sheet are present in data
  template_helper_enforce_mandatory_columns_present(data_df = data_df,
                                                    definitions = defi)
  
  # IMPORTANT (replace local indexes with scidb index)
  data_df = load_helper_replace_local_ids(data_df = data_df, 
                                          record = record)
  
  # Custom work per entity
  data_df = load_helper_do_entity_specific_work(data_df = data_df, 
                                                entity = entityName,
                                                record = record, 
                                                con = con)
  
  # Assign ontology id-s
  data_df = load_helper_assign_ontology_ids(data_df = data_df, 
                                            definitions = defi, 
                                            entity = entityName,
                                            con = con)
  
  # Rename columns from external custom fields to revealgenomics fields
  data_df = load_helper_column_rename(dfx = data_df,
                              revealgenomics_fields = mandatory_fields()[[entityName]], 
                              worksheet_fields = worksheet_fields)
  
  # Handle duplicates
  data_df = load_helper_handle_duplicates(data_df = data_df, 
                                          entity = entityName)
  
}
#' Drop duplicate rows before importing
load_helper_handle_duplicates = function(data_df, entity) {
  isDuplicated = duplicated(data_df[, unique_fields()[[entity]]])
  duplicates = data_df[isDuplicated, ]
  if (nrow(duplicates) > 0) {
    cat(nrow(duplicates), "rows of duplicates exist in the data along columns:", 
        pretty_print(unique_fields()[[entity]]), 
        "\n. Printing some of the duplicates below:\n")
    print(head(duplicates))
    data_df = data_df[!isDuplicated, ]
  } else {
    cat("No duplicates in data along columns: ",
        pretty_print(unique_fields()[[entity]]), 
        "\n")
  }
  data_df
}


#' get rid of local indexes
#' 
#' NOTE: need to run this function at the right point, where do not need to access
#' local id-s anymore
load_helper_replace_local_ids = function(data_df, record) {
  cat("Dropping local_ids of worksheet, and assigning scidb id-s\n")
  data_df$study_id = NULL
  data_df$study_version = NULL
  data_df$project_id = NULL
  
  data_df$dataset_id = record$dataset_id
  
  data_df
}

#' Record all entity specific work per entity in one place
load_helper_do_entity_specific_work = function(data_df, entity, record, con = NULL) {
  cat("\t assigning some mandatory columns that are not typically present in external data\n")
  # Currently, all entities need to have a description
  if (! 'description' %in% colnames(data_df)) data_df$description = '...' 
  
  if (entity == .ghEnv$meta$arrIndividuals) {
    if (class(data_df$subject_id) != 'character') {
      data_df$subject_id = as.character(data_df$subject_id)
    }
  } else if (entity == .ghEnv$meta$arrBiosample) {
    # BEGIN: assign individual_id based on subject_id
    cat("\t assigning individual_id-s to biosample-s\n")
    individuals = search_individuals(dataset_id = record$dataset_id, 
                                     dataset_version = record$dataset_version, 
                                     con = con)
    
    individual_name_col = 'subject_id'
    
    matches = match(data_df[, individual_name_col], individuals$name)
    unmatched_rows = which(is.na(matches))
    
    if (length(unmatched_rows) > 0) {
      cat("From", nrow(data_df), "rows of Sample information,", 
          length(unmatched_rows), "rows have unmatched subject_id-s. Dropping those\n")
      cat("\tUnmatched rows:", 
          pretty_print(data_df[unmatched_rows, ][, individual_name_col]), "\n")
    }
    
    matched_rows = which(!is.na(matches))
    data_df = data_df[matched_rows, ]
    data_df$individual_id = individuals[matches[matched_rows], ]$individual_id
    
    data_df[, individual_name_col] = NULL
    # END: assign individual_id based on subject_id
  }
  data_df
}

load_helper_assign_ontology_ids = function(data_df, definitions, entity, con = NULL) {
  controlled_fields = definitions[!is.na(definitions$controlled_vocabulary), ]$attribute_name
  data_df2 = data_df
  if (length(controlled_fields) > 0) {
    cat("Following fields are controlled fields:", 
        pretty_print(controlled_fields), "\n")
    for (field in controlled_fields) {
      # if (field == 'SEX') {
      #   cat("controlled vocabulary for gender has been enforced earlier -- see function:
      #       `load_helper_do_entity_specific_work()` under `INDIVIDUAL` entity\n")
      #   next
      # }
      vec = as.character(data_df[, field])
      vec[is.na(vec)] = 'NA'
      
      vec_ont = search_ontology(terms = vec, 
                                category = field)
      
      if (any(is.na(vec_ont))) {
        stop("unknown ontology field. 
        Should have run api_register_ontology_from_definition_sheet() first for the term(s):\n\t",
             pretty_print(vec[which(is.na(vec_ont))]), 
             "\nat category:\n\t", 
             field)
      }
      
      data_df2[, field] = vec_ont
    }
  } else {
    cat("No controlled fields specified by loader Excel file for entity:", entity, "\n")
  }
  
  data_df2
}

