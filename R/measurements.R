#' register all measurements for all / a specific dataset
#' 
#' The function should be called after loading the \code{MeasurementData} arrays` (e.g. Variant, RNA-seq etc.).
#' The \code{MEASUREMENT} entity records one entry for each entry in a \code{MeasurementData} array per biosample,
#' per pipeline
#' 
#' (A \code{MEASUREMENT} combines both Experiment and Pipeline information) 
#' 
#' @param dataset_id restrict population of measurement entries to one study (default \code{NULL}: populate for all studies)
#' @export
populate_measurements = function(dataset_id = NULL, con = NULL) {
  con = use_ghEnv_if_null(con)
  db = con$db
  df_info = get_entity_info()
  df_info_msrmt = df_info[df_info$class == 'measurementdata',]
  df_info_msrmt$entity = as.character(df_info_msrmt$entity)
  
  for (idx in 1:nrow(df_info_msrmt)){
    msrmnt_entity = df_info_msrmt[idx, ]$entity
    # stopifnot(is_entity_secured(msrmnt_entity))
    cat("Measurement entity: ", msrmnt_entity, "\n")
    
    msrmt_array = full_arrayname(msrmnt_entity)
    msrmt_set_nm = df_info_msrmt[idx, ]$search_by_entity
    msrmt_set_idnm = get_base_idname(msrmt_set_nm)
    t1 = proc.time()
    if (is.null(dataset_id)) {
      res = iquery(db,
                   paste("aggregate(", custom_scan(), "(", msrmt_array, 
                         "), count(*), biosample_id, ", 
                         msrmt_set_idnm, 
                         ", dataset_version)"), 
                   return = T)
    } else {
      stopifnot(length(dataset_id) == 1)
      res = iquery(db,
                   paste("aggregate(filter(", 
                         custom_scan(), "(", msrmt_array, 
                         "), dataset_id = ", dataset_id, "), count(*), biosample_id, ", 
                         msrmt_set_idnm, 
                         ", dataset_version)"), 
                   return = T)
    }
    proc.time()-t1
    if (nrow(res) > 0) {
      cat("----Number of rows: ", nrow(res), "\n")
      
      stopifnot(all(res$count > 0))
      res$count = NULL
      res$measurement_entity = msrmnt_entity
      head(res)
      
      msrmt_set_DF = get_entity(entity = msrmt_set_nm, 
                                           id = sort(unique(res[, msrmt_set_idnm])),  
                                           all_versions = TRUE)
      
      res2 = merge(msrmt_set_DF[, c('dataset_id', 'dataset_version', msrmt_set_idnm, 'experimentset_id', 'name')], 
                   res, 
                   by = c(msrmt_set_idnm, 'dataset_version'),
                   all.x = TRUE)
      if (nrow(res) != nrow(res2)) stop("Data for entity: ", msrmnt_entity, " was registered without corresponding measurement set!")
      colnames(res2)[which(colnames(res2) == msrmt_set_idnm)] = 'measurementset_id'
      colnames(res2)[which(colnames(res2) == 'name')] = 'measurementset_name'
      
      # Run following only for studies that were loaded without Excel sheet
      def = get_definitions()
      if (nrow(def) > 0) { # subset accordingly
        res2 = res2[!(res2$dataset_id %in% unique(def$dataset_id)), ]
      }
      
      if (nrow(res2) > 0) {
        cat("======\n")
        cat("Registering", nrow(res2), "experiment-pipeline entries\n")
        for (dataset_idi in sort(unique(res2$dataset_id))) {
          res2_sel1 = res2[res2$dataset_id == dataset_idi, ]
          for (dataset_version in sort(unique(res2_sel1$dataset_version))) {
            res2_sel2 = res2_sel1[res2_sel1$dataset_version == dataset_version, ]
            res2_sel2$dataset_version = NULL
            res2_sel2$file_path = 'NA' # introduce filepath as NA
            cat("======------======\n")
            cat("Registering", nrow(res2_sel2), 
                "experiment-pipeline entries for dataset_id:", dataset_idi, "at version:", dataset_version, "\n")
            are_definitions_present = ifelse(
              nrow(search_definitions(dataset_id = dataset_idi)) > 0,
              TRUE, 
              FALSE
            )
            if (!are_definitions_present) {
              measurement_record = register_measurement(df = res2_sel2, 
                                                        dataset_version = dataset_version)
            } else {
              cat("Measurementset for study:", dataset_idi, " ", 
                  get_datasets(dataset_id = dataset_idi)$name, 
                  "should be regiestered by Excel loader\n")
            }
          }
        }
      }
    }
  }
}

#' Retrieve data from `Measurement` entity
#' 
#' Function `populate_measurements()` must be called before calling this function.
#' See more details about `Measurement` entity in documentation for `populate_measurements()`
#' @export
get_measurements = function(measurement_id = NULL, dataset_version = NULL, 
                           all_versions = TRUE, con = NULL){
  msrmt = get_versioned_secure_metadata_entity(entity = .ghEnv$meta$arrMeasurement, 
                                               id = measurement_id, 
                                               dataset_version, all_versions, 
                                               con = con)
  if (is.null(msrmt)) {
    stop("Measurement entity not populated. Try calling function: `populate_measurements()`")
  }
  # Merge with datasets info to join in study category
  d = get_datasets(con = con)
  # Use `DAS` as an alternate column for `study category`
  if (!('study category' %in% colnames(d)) & # neither study category / DAS column is present 
        !('DAS' %in% colnames(d))) {
    d$`study category` = NA
  } else if (!('study category' %in% colnames(d)) & # DAS column is present, but no `study category`
      ('DAS' %in% colnames(d))) {
    d$`study category` = d$DAS
  } else if (('study category' %in% colnames(d)) & #  `study category` column is present, but no DAS
      !('DAS' %in% colnames(d))) {
    d$`study category` = d$`study category`
  } else if (('study category' %in% colnames(d)) & #  `study category` and DAS columns are both present
      ('DAS' %in% colnames(d))) {
    # make sure they do not overlap
    idx_not_na_das = which(!is.na(d$DAS))
    stopifnot(all(is.null(d[idx_not_na_das, ]$`study category`)
                  | is.na(d[idx_not_na_das, ]$`study category`)))
    
    idx_not_na_study_category = which(!is.na(d$`study category`))
    stopifnot(all(is.null(d[idx_not_na_study_category, ]$DAS)
                  | is.na(d[idx_not_na_study_category, ]$DAS)))
    
    d$`study category`[idx_not_na_das] = d$DAS[idx_not_na_das]
  }
  
  if (any(is.na(d$`study category`))) {
    d[which(is.na(d$`study category`)), ]$`study category` = NA
  }
  msrmt2 = merge(msrmt, 
                 d[, c('dataset_id', 'dataset_version', 'study category')], 
                 by = c('dataset_id', 'dataset_version'))
  if (nrow(msrmt2) != nrow(msrmt)) stop("Some measurements did not belong to specific dataset_id-s")
  msrmt2
}

#' retrieve all the experiments available to logged in user
#' 
#' joins `Measurement`, `Dataset` (for `study category` field if available), and `ExperimentSet` arrays
#' to return experiment information to user
#' 
#' @examples 
#' experiments = get_experiments()
#' cat("Categorization of experiments by major type\n")
#' table(experiments$measurement_entity)
#' cat("Categorization of experiments by sub type\n")
#' table(paste(experiments$measurement_entity, experiments$name, sep = ": "))
#' cat("Categorization of experiments by sub type\n")
#' table(experiments$`study category`)
#' 
#' @export
get_experiments = function(con = NULL) {
  con = use_ghEnv_if_null(con)
  
  info_key = 'study category'
  con = use_ghEnv_if_null(con)
  
  qq = paste("equi_join(", 
             "grouped_aggregate(", custom_scan(), "(", full_arrayname(.ghEnv$meta$arrMeasurement), "), ", 
             "count(*),", 
             "dataset_id, dataset_version, experimentset_id, measurement_entity, biosample_id) as X, ", 
             "filter(", custom_scan(), "(", full_arrayname(.ghEnv$meta$arrDataset), "_INFO), key='", info_key, "'),",
             "'left_names=dataset_id,dataset_version',",
             "'right_names=dataset_id,dataset_version', 'left_outer=true')", 
             sep = "")
  
  qq2 = paste("equi_join(", 
              qq, ", ", 
              "project(
              apply(", custom_scan(), "(", full_arrayname(.ghEnv$meta$arrExperimentSet), "), experimentset_id_, experimentset_id), 
              experimentset_id_, name), ", 
              "'left_names=experimentset_id,dataset_version', ", 
              "'right_names=experimentset_id_,dataset_version')")
  
  xx = iquery(con$db, 
              qq2, 
              return = T, only_attributes = T)
  stopifnot(unique(xx$key) == info_key | is.na(unique(xx$key)))
  xx$key = NULL
  colnames(xx)[which(colnames(xx) == 'val')] = info_key
  xx
}


