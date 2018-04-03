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

# HELPER FUNCTIONS functions specifically for interpreting / parsing the Excel template sheet

#' Storing columns that link different sheets
#' 
#' what columns link FeatureSets between featureset_choices sheet and Pipelines sheet
#' `api_choices_col` is same as `choices_col` if not specified
template_linker = list(
    featureset = list(
      choices_sheet      = 'featureset_choices',
      choices_col = 'featureset_name',
      api_choices_col    = 'featureset_scidb',
      pipelines_sel_col  = 'featureset_choice'
    ),
    filter = list(
      choices_sheet      = 'filter_choices',
      choices_col        = 'filter_name',
      pipelines_sel_col  = 'filter_choice'
    ),
    pipeline = list(
      choices_sheet      = 'pipeline_choices',
      choices_col        = 'pipeline_scidb',
      pipelines_sel_col  = 'pipeline_choice'
    )
  )

#' Helper function to load Excel workbook into memory
#' 
#' @param filename path to Excel workbook
#' 
#' @export
myExcelLoader = function(filename) {
  tryCatch({
    workbook = XLConnect::loadWorkbook(filename = filename)
  },
  error = function(e) {
    cat("Could not open file at file path:", filename)
    return(NULL)
  })
  
  required_sheets = c("Definitions",           "Studies",               "Subjects",             
                      "Samples",               "Pipelines",             "Contrasts",            
                      "pipeline_choices",      "featureset_choices",    "filter_choices" )
  
  if (! all(required_sheets %in% XLConnect::getSheets(workbook)) ) {
    stop("Following required sheet(s) not present: ", 
         paste0(required_sheets[!(required_sheets %in% XLConnect::getSheets(workbook))],
                collapse = ", "))
  }
  
  wb = list()
  for (sheet_nm in required_sheets) {
    cat("Reading sheet: ", sheet_nm, "\n")
    wb[[sheet_nm]] = XLConnect::readWorksheet(object = workbook, sheet = sheet_nm, 
                                              check.names = FALSE, 
                                              useCachedValues = TRUE)
    # cleanup string literals 
    # 
    # convert columns in a dataframe from string vector of 'TRUE'/'FALSE' to logicals
    convert_string_columns_to_logicals = function(dfx, colnms) {
      # custom converter from TRUE or FALSE strings to logical
      # 
      # param vec character vector containing 'TRUE' or 'FALSE'
      as.logical_custom = function(vec) {
        cat("Converting string TRUE or FALSE to logical\n")
        res = sapply(vec, function(val) {
          switch (val,
                  'TRUE' = TRUE,
                  'FALSE' = FALSE,
                  stop("value must be 'TRUE' or 'FALSE'")
          )}
        )
        names(res) = NULL
        res
      }
      
      if (!all(sapply(dfx, class)[colnms] == 'logical')) {
        colnms_x = colnms[which(sapply(dfx, class)[colnms] != 'logical')]
        for (colnm in colnms_x) {
          cat("column:", colnm, "\n\t")
          dfx[, colnm] = as.logical_custom(dfx[, colnm])
        }
      }
      dfx
    }
    if (sheet_nm == 'Definitions') {
      wb[[sheet_nm]] = convert_string_columns_to_logicals(dfx = wb[[sheet_nm]],
                                  colnms = grep("attribute_in_", colnames(wb[[sheet_nm]]), value = TRUE)
                                                          )
    } else if (sheet_nm == 'Studies') {
      wb[[sheet_nm]] = convert_string_columns_to_logicals(dfx = wb[[sheet_nm]],
                                                          colnms = 'is_study_public')
    }
  }
  wb
}

#' Helper function to read sheet from Excel workbook
#' 
#' note usage of the useCachedValues parameter
#' otherwise, was throwing warnings about the concatenation field
#' 
#' @export
myExcelReader = function(workbook, sheet_name) {
  if (class(workbook) == 'workbook') {
    readWorksheet(object = workbook, 
                  sheet = sheet_name, 
                  check.names = FALSE, 
                  useCachedValues = TRUE)
  } else if (class(workbook) == 'list') {
    if (sheet_name %in% names(workbook)) {
      workbook[[sheet_name]]
    } else {
      stop("No sheet by name: ", sheet_name, " in workbook. \n\nAvailable sheets: ",
           paste0(names(workbook), collapse = ", "))
    }
  } else {
    stop("Workbook must be of type `XLConnect::workbook` (loaded by `XLConnect::loadWorkbook()`)\n 
         or of type `list` (loaded by `scidb4gh::myExcelLoader()`)")
  }
}

#' Enforce that columns in any data sheet have definitions in Definitions sheet
#' 
template_helper_enforce_columns_defined = function(data_df, definitions) {
  attrs_defi = sort(definitions$attribute_name)
  attrs_data = sort(colnames(data_df))
  unmatched1 = attrs_defi[!(attrs_defi %in% attrs_data)]
  unmatched2 = attrs_data[!(attrs_data %in% attrs_defi)]
  if (length(unmatched1) !=0 | length(unmatched2) != 0) {
    cat("Following items exist in definitions sheet, but not in data sheet:\n\t")
    cat(pretty_print(unmatched1))
    cat("\n\nFollowing items exist in data sheet, but not in definitions sheet:\n\t")
    cat(pretty_print(unmatched2))
    cat("\n")
    stop("Above columns in data sheet not defined in Definitions seet")
  }
}


#' extract definitions corresponding to a specific sheet
#' 
#' Find the definitions for a specific sheet (e.g. Subjects, Samples)
#' by consulting the relevant column (e.g. attribute_in_Subjects, attribute_in_Samples)
template_helper_extract_definitions = function(sheetName, def) {
  col_for_pick = paste0("attribute_in_", sheetName)
  defi = def[def[, col_for_pick], ]
  cat("From", nrow(def), "rows of definitions sheet, picked out", nrow(defi), "rows for current entity\n")
  defi
}

#' Enforce that mandatory columns listed in Definitions sheet are present in data
template_helper_enforce_mandatory_columns_present = function(data_df, definitions) {
  mandatory_columns = definitions[definitions$importance == 1, ]$attribute_name
  if (!all(mandatory_columns %in% colnames(data_df))) {
    stop("Following attributes defined as mandatory in Definitions sheet, but not present in data:\n\t",
        pretty_print(mandatory_columns[!(mandatory_columns %in% colnames(data_df))]), "\n")
  }
}

#' Extract pipeline meta information 
#' 
#' Given rows from Pipelines sheet, extract the unique keys for pipeline, filter and featurset-s.
#' Then find the matching and relevant rows in `pipeline_choices`, `filter_choices` and 
#' `featureset_choices`
#' 
#' @param pipelines_df data-frame containing rows in Pipelines sheet corresponding to a 
#'                     `[project_id, study_id, study_version]` record
#' @param choicesObj list containing instantiated objects of PipelineChoices, FilterChoices
#'                   and FeaturesetChoices classes
template_helper_extract_pipeline_meta_info = function(pipelines_df, choicesObj) {
  selector_col_pipeline_choice = template_linker$pipeline$pipelines_sel_col
  selector_col_filter_choice   = template_linker$filter$pipelines_sel_col
  selector_col_featureset_choice = template_linker$featureset$pipelines_sel_col
  
  msmtset_selector = unique(
    pipelines_df[, c(selector_col_pipeline_choice,
                     selector_col_filter_choice,
                     selector_col_featureset_choice)])
  
  pipeline_df =
    drop_na_columns(
      do.call(what = 'rbind',
              args = lapply(msmtset_selector[, selector_col_pipeline_choice],
                            function(choice) {
                              choicesObj$pipelineChoicesObj$get_pipeline_metadata(keys = choice)
                            })
      )
    )
  
  filter_df =
    drop_na_columns(
      do.call(what = 'rbind',
              args = lapply(msmtset_selector[, selector_col_filter_choice],
                            function(choice) {
                              choicesObj$filterChoicesObj$get_filter_metadata(keys = choice)
                            })
      )
    )
  # drop some local information
  filter_df$filter_id = NULL 
  filter_df$measurement_entity = NULL 
  
  msmtset_df = cbind(pipeline_df,
                     filter_df)
  msmtset_df$featureset_name = sapply(msmtset_selector[, selector_col_featureset_choice],
                                      function(choice) {
                                        choicesObj$featuresetChoicesObj$get_featureset_name(keys = choice)
                                      })
  msmtset_df$dataset_id = record$dataset_id
  msmtset_df$measurement_entity = 
    template_helper_convert_names(external_name = msmtset_df$measurement_entity)
  
  msmtset_df
}

#' extract information pertaining to a project-study record
#' 
#' Helper function for template Excel sheet. 
#' 
#' Given a project-study record [project_id, dataset_id, dataset_version]
#' find the information from a target sheet (e.g. Subjects, Samples, Pipelines) pertaining
#' to that record
template_helper_extract_record_related_rows = function(workbook, sheetName, record) {
  masterSheet = 'Studies'
  stopifnot(nrow(record) == 1)
  
  project_id = record$project_id
  dataset_id = record$dataset_id
  dataset_version = record$dataset_version
  
  dataset = get_datasets(dataset_id = dataset_id, dataset_version = dataset_version, 
                         all_versions = FALSE)
  
  stopifnot(nrow(dataset) == 1)
  stopifnot(project_id == dataset$project_id)
  
  # data0 = readWorksheet(workbook, sheet = sheetName,
  #                       check.names = FALSE,
  #                       useCachedValues = TRUE)
  data0 = myExcelReader(workbook = workbook, sheet_name = sheetName)
  data0 = data0[!duplicated(data0), ]
  # study = readWorksheet(workbook, sheet = masterSheet,
  #                       check.names = FALSE,
  #                       useCachedValues = TRUE)
  study = myExcelReader(workbook = workbook, sheet_name = masterSheet)
  
  study_loc = study[study[, 'study_name'] == dataset$name &
                      study[, 'study_version'] == dataset_version, ]
  study_id_loc = study_loc$study_id
  proj_id_loc = study_loc$project_id
  
  data = data0[data0$study_id == study_id_loc &
                 data0$project_id == proj_id_loc &
                 data0$study_version == dataset_version, ]
  cat("From", nrow(data0), tolower(sheetName), "-- working on", nrow(data), tolower(sheetName), 
      "belonging to \n\t project_id:", proj_id_loc, "(local), \n\t study_id:", study_id_loc, "(local id), ",
      dataset_id, "(scidb) \n\t at version", dataset_version, "\n")
  
  data
}

#' Convert external (human-readable names) to API internal names
#' 
#' external                   API
#' Gene Expression            RNAQUANTIFICATION
#' Variant                    VARIANT
#' Rearrangement              FUSION
#' Copy Number Variation      COPYNUMBER_MAT
template_helper_convert_names = function(api_name = NULL, external_name = NULL) {
  if (is.null(api_name) & is.null(external_name)) {
    stop("Must supply at least one parameter")
  } else if (!is.null(api_name) & !is.null(external_name)) {
    stop("Must supply only one parameter")
  }
  df1 = data.frame(
    api_names = c(.ghEnv$meta$arrRnaquantification,
                  .ghEnv$meta$arrVariant, 
                  .ghEnv$meta$arrFusion,
                  .ghEnv$meta$arrCopynumber_mat),
    external_name = c('Gene Expression',
                      'Variant',
                      'Rearrangement',
                      'Copy Number Variation'),
    stringsAsFactors = FALSE
  )
  if (!is.null(api_name)) {
    m1 = find_matches_and_return_indices(api_name, df1$api_name)
    if (length(m1$source_unmatched_idx) != 0) {
      stop("Unexpected internal names provided for conversion: ",
          pretty_print(api_name[m1$source_unmatched_idx]))
    }
    df1$external_name[m1$target_matched_idx]
  } else if (!is.null(external_name)) {
    m1 = find_matches_and_return_indices(external_name, df1$external_name)
    if (length(m1$source_unmatched_idx) != 0) {
      stop("Unexpected external names provided for conversion: ",
          pretty_print(external_name[m1$source_unmatched_idx]))
    }
    df1$api_name[m1$target_matched_idx]
  }
}