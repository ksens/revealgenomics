#
# BEGIN_COPYRIGHT
#
# PARADIGM4 INC.
# This file is part of the Paradigm4 Enterprise SciDB distribution kit
# and may only be used with a valid Paradigm4 contract and in accord
# with the terms and conditions specified by that contract.
#
# Copyright (C) 2011 - 2019 Paradigm4 Inc.
# All Rights Reserved.
#
# END_COPYRIGHT
#

# Functions to upload measurement data to SciDB

#' Return sub indices
#' 
#' Split a vector 1:bigN into list of vectors each of length < len_subelem
#' 
#' @param bigN \code{c(1: bigN)} is the vector that needs to be split
#' @param len_subelem The maxiumum length of one of the split vectors
#' 
#' @examples 
#' return_sub_indices(bigN = 10, len_subelem = 4)
#'## [[1]]
#'## [1] 1 2 3 4
#'## 
#'## [[2]]
#'## [1] 5 6 7 8
#'## 
#'## [[3]]
#'## [1]  9 10
return_sub_indices = function(bigN, len_subelem) {
  starts = seq(1, bigN, len_subelem)
  ends   = c(tail(seq(0, bigN-1, len_subelem), -1), bigN)
  stopifnot(length(starts) == length(ends))
  lapply(1:length(starts), function(idx) {c(starts[idx]: ends[idx])})
}

upload_variant_data_in_steps = function(entitynm, var_gather, UPLOAD_N = 5000000, con = NULL) {
  con = use_ghEnv_if_null(con = con)
  steps = return_sub_indices(bigN = nrow(var_gather), len_subelem = UPLOAD_N)
  
  arrayname = full_arrayname(entitynm)
  for (upidx in 1:length(steps)) {
    step = steps[[upidx]]
    cat(paste0("Uploading variants. Sub-segment ", 
               upidx, " of ", length(steps), " segments\n\t", 
               "Rows: ", step[1], "-", tail(step, 1), "\n"))
    var_sc = as.scidb_int64_cols(db = con$db, 
                                 df1 = var_gather[c(step[1]:tail(step, 1)), ],
                                 int64_cols = colnames(var_gather)[!(colnames(var_gather) %in% 'val')])
    cat("Redimension and insert\n")
    iquery(con$db, paste0("insert(redimension(",
                          var_sc@name,
                          ", ", arrayname, "), ", arrayname, ")"))
    remove_old_versions_for_entity(entitynm = entitynm, con = con)
  }
}

#' Upload expression matrix file 
#' 
#' filepath must exist on SciDB server. Altrnatively use
#' `register_expression_matrix_client`
#' 
#' @export
register_expression_matrix = function(filepath,
                                      measurementset_id,
                                      featureset_id,
                                      feature_type,
                                      dataset_version = NULL,
                                      only_test = FALSE,
                                      con = NULL){
  con = use_ghEnv_if_null(con)
  
  test_register_expression_matrix(filepath,
                                  measurementset_id,
                                  featureset_id,
                                  feature_type,
                                  dataset_version)
  if (!only_test) {
    if (is.null(dataset_version)) {
      rqset = get_measurementsets(measurementset_id = measurementset_id, con = con) # finds the latest version
      dataset_version = rqset$dataset_version
      cat("Dataset version not specified. Inferred version from measurementset_id as version:", dataset_version, "\n")
    } else {
      stopifnot(length(dataset_version) == 1)
      rqset = get_measurementsets(measurementset_id = measurementset_id,
                                  dataset_version = dataset_version, con = con)
    }
    dataset_id = rqset$dataset_id
    cat("Specified measurementset_id belongs to dataset:", dataset_id, "\n")
    
    arr_feature = full_arrayname(.ghEnv$meta$arrFeature)
    arr_biosample = full_arrayname(.ghEnv$meta$arrBiosample)
    arrayname = full_arrayname(.ghEnv$meta$arrRnaquantification)
    cat("======\n")
    cat(paste("Working on expression file:\n\t", filepath, "\n"))
    x = read.delim(file = filepath, nrows = 10)
    ncol(x)
    
    
    ##################
    # Do some simple checks on the column-names (only for debug purposes)
    length(colnames(x))
    length(grep(".*_BM", tail(colnames(x),-1) ))
    length(grep(".*_PB", colnames(x) ))
    
    colnames(x)[grep(".*_2_.*", colnames(x) )]
    
    colnames(x)[grep(".*2087.*", colnames(x) )]
    colnames(x)[grep(".*1179.*", colnames(x) )]
    ##################
    
    
    ############# START LOADING INTO SCIDB ########
    
    query = paste("aio_input('", filepath, "',
                  'num_attributes=" , length(colnames(x)), "',
                  'split_on_dimension=1')")
    # t1 = scidb(con$db, query)
    # t1 = con$db$between(srcArray = t1, lowCoord = "NULL, NULL, NULL, NULL", highCoord = R(paste("NULL, NULL, NULL,", length(colnames(x))-1)))
    t0 = scidb(con$db, paste0("between(", query, ", NULL, NULL, NULL, NULL, NULL, NULL, NULL, ", length(colnames(x))-1, ")")) 
    t1 = store(con$db, t0, temp=TRUE)
    
    # ================================
    ## Step 1. Join the SciDB feature ID
    
    # first form the list of features in current table
    # featurelist_curr = con$db$between(srcArray = t1, lowCoord = "NULL, NULL, NULL, 0", highCoord = "NULL, NULL, NULL, 0")
    featurelist_curr = scidb(con$db, paste0("filter(", t1@name, ", attribute_no = 0)"))
    cat(paste("number of feature_id-s in the current expression count table:", scidb_array_count(featurelist_curr, con = con)-1, "\n"))
    FEATUREKEY = scidb(con$db, arr_feature)
    cat(paste("number of feature_id-s in the SciDB feature ID list:", scidb_array_count(FEATUREKEY, con = con), "\n"))
    
    # sel_features = con$db$filter(FEATUREKEY, R(paste("feature_type='", feature_type, "' AND featureset_id = ", featureset_id, sep = "")))
    sel_features = scidb(con$db, paste0("filter(", FEATUREKEY@name, ", ", 
                                        "feature_type='", feature_type, "' AND featureset_id = ", featureset_id, ")"))
    cat(paste("number of feature_id-s in the SciDB feature ID list for transcript type: '", feature_type,
              "' and featureset_id: '", featureset_id, "' is:", scidb_array_count(sel_features, con = con), "\n", sep = ""))
    
    # ff = con$db$project(srcArray = sel_features, selectedAttr = "name")
    ff = scidb(con$db, paste0("project(", sel_features@name, ", name)"))
    
    qq2 = paste0("equi_join(",
                 ff@name, ", ",
                 featurelist_curr@name, ", ",
                 "'left_names=name', 'right_names=a', 'keep_dimensions=1')")
    
    qq2 = paste0("redimension(", qq2, 
                 ", <feature_id :int64>[tuple_no=0:*,10000000,0,dst_instance_id=0:63,1,0,src_instance_id=0:63,1,0])")
    
    joinBack1 = scidb(con$db,
                      paste("cross_join(",
                            t1@name, " as X, ",
                            qq2, " as Y, ",
                            "X.tuple_no, Y.tuple_no, X.dst_instance_id, Y.dst_instance_id, X.src_instance_id, Y.src_instance_id)", sep = ""))
    joinBack1@name
    
    joinBack1 = store(con$db, joinBack1, temp=TRUE)
    
    # Verify with
    # scidb_array_head(con$db$between(srcArray = joinBack1, lowCoord = "0, NULL, NULL, NULL", highCoord = "0, NULL, NULL, NULL"))
    
    cat("Number of features in study that matched with SciDB ID:\n")
    countFeatures = scidb_array_count(joinBack1) / ncol(x)
    print(countFeatures)
    
    stopifnot(countFeatures == (scidb_array_count(featurelist_curr, con = con)-1))
    # ================================
    ## Step 2. Join the SciDB patient ID
    # first form the list of patients in current table
    
    # patientlist_curr = con$db$between(t1, lowCoord = "0, 0, NULL, 1", highCoord = "0, 0, NULL, NULL")
    patientlist_curr = scidb(con$db, paste0("between(", t1@name, ", 0, 0, NULL, 1, 0, 0, NULL, NULL)"))
    # Check that the "public_id"_"spectrum_id" is unique enough, otherwise we have to consider the suffix "BM", "PB"
    stopifnot(length(unique(as.R(patientlist_curr)$a)) == (ncol(x)-1))
    
    scidb_array_head(patientlist_curr, con = con)
    
    cat(paste("number of biosamples in the expression count table:", scidb_array_count(patientlist_curr, con = con), "\n"))
    # PATIENTKEY = scidb(con$db, arr_biosample)
    # PATIENTKEY = con$db$filter(PATIENTKEY, R(paste('dataset_id=', dataset_id)))
    PATIENTKEY = scidb(con$db, paste0("filter(", arr_biosample, ", dataset_id = ", dataset_id, ")"))
    cat(paste("number of biosamples registered in database in selected namespace:" , scidb_array_count(PATIENTKEY), "\n"))
    
    
    # now do the joining
    qq = paste("equi_join(",
               patientlist_curr@name, ", ",
               "project(filter(", PATIENTKEY@name, ", dataset_version = ", dataset_version, "), name), ",
               "'left_names=a', 'right_names=name', 'keep_dimensions=1')")
    joinPatientName = scidb(con$db, qq)
    
    cat("number of matching public_id-s between expression-count table and PER_PATIENT csv file:\n")
    countMatches = scidb_array_count(joinPatientName)
    print(countMatches)
    
    
    
    # Verify
    # x1 = as.R(con$db$project(PATIENTKEY, "name"))
    x1 = iquery(con$db, paste0("project(", PATIENTKEY@name, ", name)"), return = T)
    x2 = as.R(patientlist_curr)
    
    stopifnot(countMatches == sum(x2$a %in% x1$name))
    
    # cat("The expression count table public_id-s that are not present in PER_PATIENT csv file: \n")
    # tt = x2$public_id %in% x1$PUBLIC_ID
    # print(x2$public_id[which(!tt)])
    
    # joinPatientName = con$db$redimension(joinPatientName,
    #                                      R(paste("<biosample_id:int64>
    #                                                 [attribute_no=0:", countMatches+1, ",",countMatches+2, ",0]", sep = "")))
    qq3 = paste0("redimension(", joinPatientName@name,
                 ", <biosample_id:int64>[attribute_no=0:", countMatches+1, ",",countMatches+2, ",0])")
    
    joinBack2 = scidb(con$db,
                      paste0("cross_join(",
                             joinBack1@name, " as X, ",
                             qq3, "as Y, ",
                             "X.attribute_no, Y.attribute_no)"))
    joinBack2@name
    
    joinBack2 = store(con$db, joinBack2, temp=TRUE)
    
    # Verify with
    # scidb_array_head(con$db$filter(joinBack2, "tuple_no = 0"))
    
    cat("Number of expression level values in current array:\n")
    countExpressions = scidb_array_count(joinBack2)
    print(countExpressions)
    stopifnot(countExpressions == countMatches*countFeatures)
    
    ####################
    # Redimension the expression level array
    gct_table = scidb(con$db,
                      paste("apply(",
                            joinBack2@name, ", ",
                            "value, dcast(a, float(null)), ",
                            "measurementset_id, ", measurementset_id,
                            ", dataset_id, ", dataset_id, 
                            ", dataset_version, ", dataset_version,
                            ")", sep = "")
    )
    
    # Need to insert the expression matrix table into one big array
    insertable_qq = paste0("redimension(", gct_table@name, ", ",
                           arrayname, ")") # TODO: would be good to not have this resolution clash
    
    if (scidb_exists_array(arrayname, con = con)) {
      cat(paste("Inserting expression matrix data into", arrayname, "at dataset_version", dataset_version, "\n"))
      iquery(con$db, paste("insert(", insertable_qq, ", ", arrayname, ")"))
    } else {
      stop("expression array does not exist")
    }
    
    remove_old_versions_for_entity(entitynm = .ghEnv$meta$arrRnaquantification, con = con)

    return(measurementset_id)
  } # end of if (!only_test)
}

#' Register in-memory matrix
#' 
#' Register in-memory matrix (Expression, Proteomics etc.) into corresponding entity
#' 
#' @param mat in-memory matrix of feature_id (rows) by biosample_id (columns) and (expression/Proteomics/...) value
#' @param measurementset data.frame containing information about MeasurementSet
#' 
#' @export
register_in_memory_matrix = function(mat, measurementset) {
  stopifnot(nrow(measurementset) == 1)
  THRESHOLD = 50 # can upload x MB at a time
  NSTEPS = ceiling(as.numeric(object.size(mat))/1024/1024/THRESHOLD)
  
  steps = revealgenomics:::return_sub_indices(bigN = ncol(mat), len_subelem = round(ncol(mat)/NSTEPS))
  
  # Verify that indices exist
  bios_ids = sort(unique(as.integer(colnames(mat))))
  stopifnot(
    nrow(get_biosamples(biosample_id = bios_ids, mandatory_fields_only = T)) == ncol(mat)
  )
  
  ftr_ids = sort(unique(as.integer(rownames(mat))))
  stopifnot(
    nrow(get_features(feature_id = ftr_ids, mandatory_fields_only = T)) == nrow(mat)
  )
  
  if (measurementset$entity %in% get_entity_names()) {
    entitynm = measurementset$entity
  } else {
    stop("case not covered")
  }
  for (upidx in 1:length(steps)) {
    step = steps[[upidx]]
    cat(paste0("Uploading sub-segment ", 
               upidx, " of ", length(steps), " segments\n\t", 
               "Rows: ", step[1], "-", tail(step, 1), "\n"))
    
    if (step[1] == tail(step, 1)) {
      stop("Need to cover this corner case of only column to upload in this sub index\n")
    }
    # -------- Convert to data.frame and upload ----------
    cat("Converting matrix to dataframe\n")
    expr_df = as.data.frame(as.table(mat[, c(step[1]:tail(step, 1))]), stringsAsFactors = FALSE)
    cat("Labeling columns and adding more metadata columns\n")
    colnames(expr_df) = c('feature_id', 'biosample_id', 'value')
    expr_df$feature_id = as.integer(expr_df$feature_id)
    expr_df$biosample_id = as.integer(expr_df$biosample_id)
    expr_df$dataset_id = as.integer(measurementset$dataset_id)
    expr_df$measurementset_id = as.integer(measurementset$measurementset_id)
    # sapply(expr_df, class)
    
    message("Registering ", as.integer(object.size(expr_df)/1024/1024),
            " MB of data at measurementset_id: ", measurementset$measurementset_id,
            " -- Pipeline: ", measurementset$name)
    register_expression_dataframe(df1 = expr_df, dataset_version = 1)
  }
}

#' Upload data into gene expression, protein expression, copy number matrix arrays
#' 
#' @export
register_expression_dataframe = function(df1, dataset_version, con = NULL){
  con = use_ghEnv_if_null(con)
  
  test_register_expression_dataframe(df1, con = con)
  
  ms_id = unique(df1$measurementset_id)
  if (length(ms_id) != 1) {
    stop("Expected to upload data for one measurementset_id (pipeline) at a time")
  }
  mset = get_measurementsets(measurementset_id = ms_id, 
                             con = con)
  stopifnot(nrow(mset) == 1)
  entity = mset$entity
  allowed_entities = c(.ghEnv$meta$arrRnaquantification, 
                       .ghEnv$meta$arrProteomics, 
                       .ghEnv$meta$arrCopynumber_mat, 
                       .ghEnv$meta$arrCopynumber_mat_string, 
                       .ghEnv$meta$arrCytometry_cytof)
  if (!(entity %in% allowed_entities)) {
    stop("Expect to use this function to upload data for: ",
         pretty_print(allowed_entities), " only")
  }
  
  dataset_id = unique(df1$dataset_id)
  stopifnot(length(ms_id) == 1)
  
  df1 = df1[, c('biosample_id', 
                'feature_id', 'value')]
  df1 = plyr::rename(df1, c('value' = 'value__'))
  
  temp_arr_nm = paste0("temp_df_", stringi::stri_rand_strings(1, 6))
  adf_expr0 = as.scidb_int64_cols(db = con$db,
                                  df1 = df1,
                                  int64_cols = c('biosample_id', 
                                                 'feature_id'),
                                  chunk_size=nrow(df1), 
                                  name = temp_arr_nm, 
                                  use_aio_input = TRUE)
  
  attr_type = .ghEnv$meta$L$array[[entity]]$attributes$value
  qq2 = paste0("apply(", 
               adf_expr0@name, 
               ", value, ", attr_type, "(value__)", 
               ", dataset_version, ", dataset_version, 
               ", dataset_id, ", dataset_id, 
               ", measurementset_id, ", ms_id, 
               ")")
  
  fullnm = full_arrayname(entitynm = entity)
  qq2 = paste0("redimension(", qq2, ", ", fullnm, ")")
  
  cat("inserting data for", nrow(df1), "expression values into", fullnm, 
      "array at measurementset_id =", ms_id, "\n")
  iquery(con$db, paste("insert(", qq2, ", ", fullnm, ")"))
  iquery(con$db, paste0("remove(", temp_arr_nm, ")"))
  
  remove_old_versions_for_entity(entitynm = entity, con = con)
}

#' Upload expression matrix file 
#' 
#' This wrapper function shows an example of how to call the internal upload function 
#' \code{register_expression_dataframe}
#' 
#' @param filepath can exist on SciDB server or client
#' @param measurementset dataframe containing pipeline information for measurementset_id at which to insert expression data; 
#'                       retrieve using `get_measurementsets(measurementset_id = measurementset_id)`
#' @param featureset dataframe containing featureSet information for featureset_id at which to insert expression data; 
#'                       retrieve using `get_featureset(featureset_id = featureset_id)`
#' @param file_format must be `tall` or `wide`
#' @param biosample_ref (optional) reference data-frame containing information for all biosamples in current study / dataset
#' @param feature_ref (optional) reference data-frame containing information for all features in current featureSet
#' 
#' @export
register_expression_matrix_client = function(filepath,
                                             measurementset,
                                             featureset,
                                             file_format = c('tall', 'wide'),
                                             biosample_ref = NULL,
                                             feature_ref = NULL,
                                             con = NULL) {
  con = use_ghEnv_if_null(con = con)
  file_format = match.arg(file_format)                                          
  if (length(file_format) != 1) stop("file_format parameter must be `tall` or `wide")
  
  stopifnot(nrow(measurementset) == 1)
  stopifnot(nrow(featureset) == 1)
  
  dataset_id = measurementset$dataset_id
  dataset_version = measurementset$dataset_version
  
  if (is.null(feature_ref)) {
    feature_ref = search_features(featureset_id = featureset$featureset_id) 
  } else {
    feature_ref   =   feature_ref[feature_ref$featureset_id == featureset$featureset_id, ]
  }
  if (is.null(biosample_ref)) {
    biosample_ref = search_biosamples(dataset_id = dataset_id)
  } else {
    biosample_ref = biosample_ref[biosample_ref$dataset_id ==  dataset_id, ] 
  }
  
  if (file_format == 'wide') {
    cat("Reading wide format matrix file\n")
  } else {
    cat("Reading tall TSV file. Expecting columns `GENE_ID`, `biosample_name`, `value`\n")
  }
  expr_df = read.delim(file = filepath, sep = "\t", check.names=FALSE)
  if (file_format == 'wide') {
    cat("Converting wide format to tall format\n")
    expr_df = tidyr::gather(data = expr_df,
                            key = 'biosample_name',
                            value='value',
                            colnames(expr_df)[2:length(colnames(expr_df))])
  } 
  stopifnot(all(c('biosample_name', 'value', 'GENE_ID') %in% colnames(expr_df)))
  
  expr_df$feature_id =   feature_ref[match(expr_df$GENE_ID, feature_ref$name), ]$feature_id
  if (any(is.na(expr_df$feature_id))) {
    stop("All features in expression matrix file (row names) must have been uploaded before to the featureset: ",
         featureset$featureset_id)
  }
  expr_df$biosample_id = biosample_ref[match(expr_df$biosample_name, biosample_ref$name), ]$biosample_id
  if (any(is.na(expr_df$biosample_id))) {
    stop("All samples in expression matrix file (column names) must have been uploaded before to study / dataset id: ",
         dataset_id)
  }
  expr_df$dataset_id = dataset_id
  expr_df$measurementset_id = measurementset_id
  register_expression_dataframe(df1 = expr_df, dataset_version = 1, con = con)
  
}

#' @export
register_variant = function(df1, dataset_version = NULL, only_test = FALSE, con = NULL){
  con = use_ghEnv_if_null(con)
  # Step 1
  # Identify three groups of column-names
  # - `dimensions`: indices of the multi-dimensional array
  # - `attr_mandatory`: VCF attribute fields that are mandatory
  # - `attr_flex`: VCF attrubute fields that are not mandatory 
  cols_dimensions = get_idname(.ghEnv$meta$arrVariant)[!(
    get_idname(.ghEnv$meta$arrVariant) %in% 'key_id')]
  cols_attr_mandatory = c('chromosome', 
                          'start', 'end',
                          'id', 'reference', 'alternate')
  cols_attr_flex = colnames(df1)[!(colnames(df1) %in% 
                                     c(cols_dimensions, cols_attr_mandatory))]
  # Step 2
  # Run tests
  cat("Step 2 -- run tests\n")
  test_register_variant(df1, variant_attr_cols = cols_attr_mandatory)
  if (!only_test) {
    # Step 3
    # Introduce `per_gene_variant_number` column
    if (!('per_gene_variant_number' %in% colnames(df1))) {
      # specify dplyr mutate as per https://stackoverflow.com/a/33593868
      df1 = df1 %>% group_by(feature_id, biosample_id) %>% dplyr::mutate(per_gene_variant_number = row_number())
    }
    df1 = as.data.frame(df1)
    
    # Step 4
    # Introduce `dataset_version` column
    if (is.null(dataset_version)) {
      dataset_version = get_dataset_max_version(dataset_id = unique(df1$dataset_id), updateCache = TRUE, con = con)
      if (is.null(dataset_version)) stop("Expected non-null dataset_version at this point")
      cat("dataset_version was not specified. Registering at version", dataset_version, "of dataset", unique(df1$dataset_id), "\n")
    }
    df1$dataset_version = dataset_version
    
    # Step 5A
    # Introduce `key_id` and `val` columns i.e. handle VariantKeys 
    # -- First register any new keys
    cat("Step 5A -- Register the variant attribute columns as variant keys\n")
    variant_key_id = register_variant_key(
      df1 = data.frame(
        key = c(cols_attr_mandatory, cols_attr_flex), 
        stringsAsFactors = FALSE))
    if (!identical(
      get_variant_key(variant_key_id = variant_key_id)$key,
      c(cols_attr_mandatory, cols_attr_flex))) {
      stop("Faced issue registering variant keys")
    }
    
    # Step 5B
    # Match key with key_id-s
    cat("Step 5B -- Converting wide data.frame to tall data.frame\n")
    VAR_KEY = get_variant_key()
    var_gather = tidyr::gather(data = df1, key = "key", value = "val", 
                               c(cols_attr_mandatory, cols_attr_flex))
    M = find_matches_and_return_indices(var_gather$key, VAR_KEY$key)
    stopifnot(length(M$source_unmatched_idx) == 0)
    var_gather$key_id = VAR_KEY$key_id[M$target_matched_idx]
    var_gather$key = NULL # drop the key column
    var_gather = var_gather[, c(cols_dimensions, 'key_id', 'val')]
    
    # Step 6
    # Remove rows that are effectively empty
    cat("Step 6 -- Calculating empty markers\n")
    empty_markers = c('.', 'None')
    non_null_indices = which(!(var_gather$val %in% empty_markers))
    if (length(non_null_indices) != nrow(var_gather)) {
      cat(paste0("From total: ", nrow(var_gather), " key-value pairs, retaining: ", 
                 length(non_null_indices), " non-null pairs.\n\tSavings = ", 
                 (nrow(var_gather) - length(non_null_indices)) / nrow(var_gather) * 100, "%\n"))
      var_gather = var_gather[non_null_indices, ] 
    }
    
    # Step 7
    # Upload and insert the data
    cat("Step 7 -- Upload and insert the data\n")
    upload_variant_data_in_steps(entitynm = .ghEnv$meta$arrVariant, 
                                 var_gather = var_gather)
  } # end of if (!only_test)
}

#' @export
register_fusion = function(df1, measurementset, only_test = FALSE, con = NULL){
  entitynm = .ghEnv$meta$arrFusion
  con = use_ghEnv_if_null(con)
  # Step 1
  # Identify three groups of column-names
  # - `dimensions`: indices of the multi-dimensional array
  # - `attr_mandatory`: attribute fields that are mandatory
  # - `attr_flex`: attrubute fields that are not mandatory 
  cols_dimensions = get_idname(entitynm)[!(
    get_idname(entitynm) %in% 
      c('key_id', 'per_gene_pair_fusion_number'))]
  cols_attr_mandatory = c('gene_left', 'chromosome_left', 'start_left', 'end_left',
                          'gene_right', 'chromosome_right', 'start_right', 'end_right',
                          'num_spanning_reads', 'num_mate_pairs', 'num_mate_pairs_fusion')
  cols_attr_flex = colnames(df1)[!(colnames(df1) %in% 
                                     c(cols_dimensions, cols_attr_mandatory))]
  # Step 2
  # Run tests
  cat("Step 2 -- run tests\n")
  test_register_fusion(df1, fusion_attr_cols = cols_attr_mandatory)
  if (!only_test) {
    # Step 3 
    # Introduce `per_gene_pair_fusion_number` column
    if (!('per_gene_pair_fusion_number' %in% colnames(df1))) {
      # specify dplyr mutate as per https://stackoverflow.com/a/33593868
      df1 = df1 %>% 
        group_by(feature_id_left, feature_id_right, biosample_id) %>% 
          dplyr::mutate(per_gene_pair_fusion_number = row_number())
    }
    df1 = as.data.frame(df1)
    
    # Step 4
    # Introduce `dataset_version` column
    df1$dataset_version = measurementset$dataset_version
    
    # Step 5A
    # Introduce `key_id` and `val` columns i.e. handle VariantKeys 
    # -- First register any new keys
    cat("Step 5A -- Register the variant attribute columns as variant keys\n")
    variant_key_id = register_variant_key(
      df1 = data.frame(
        key = c(cols_attr_mandatory, cols_attr_flex), 
        stringsAsFactors = FALSE))
    if (!identical(
      get_variant_key(variant_key_id = variant_key_id)$key,
      c(cols_attr_mandatory, cols_attr_flex))) {
      stop("Faced issue registering variant keys")
    }
    
    # Step 5B
    # Match key with key_id-s
    cat("Step 5B -- Converting wide data.frame to tall data.frame\n")
    VAR_KEY = get_variant_key()
    var_gather = tidyr::gather(data = df1, key = "key", value = "val", 
                               c(cols_attr_mandatory, cols_attr_flex))
    M = find_matches_and_return_indices(var_gather$key, VAR_KEY$key)
    stopifnot(length(M$source_unmatched_idx) == 0)
    var_gather$key_id = VAR_KEY$key_id[M$target_matched_idx]
    var_gather$key = NULL # drop the key column
    var_gather = var_gather[, c(cols_dimensions, 'key_id', 'val')]
    
    # Step 6
    # Remove rows that are effectively empty
    cat("Step 6 -- Calculating empty markers\n")
    empty_markers = c('.', 'None')
    non_null_indices = which(!(var_gather$val %in% empty_markers))
    if (length(non_null_indices) != nrow(var_gather)) {
      cat(paste0("From total: ", nrow(var_gather), " key-value pairs, retaining: ", 
                 length(non_null_indices), " non-null pairs.\n\tSavings = ", 
                 (nrow(var_gather) - length(non_null_indices)) / nrow(var_gather) * 100, "%\n"))
      var_gather = var_gather[non_null_indices, ] 
    }
    
    # Step 7
    # Upload and insert the data
    cat("Step 7 -- Upload and insert the data\n")
    upload_variant_data_in_steps(entitynm = entitynm, 
                                 var_gather = var_gather)
  } # end of if (!only_test)
}

#' Register CNV data of variable columns subtype
#' 
#' Function to register CNV data when the underlying data is a table of variable columns
register_copynumbervariant_variable_columns = function(df1, measurementset, only_test = FALSE, con = NULL){
  entitynm = .ghEnv$meta$arrCopynumber_variant
  con = use_ghEnv_if_null(con)
  # Step 1
  # Identify three groups of column-names
  # - `dimensions`: indices of the multi-dimensional array
  # - `attr_mandatory`: attribute fields that are mandatory
  # - `attr_flex`: attrubute fields that are not mandatory 
  cols_dimensions = get_idname(entitynm)[!(
    get_idname(entitynm) %in% 
      c('key_id', 'per_gene_copynumbervariant_number'))]
  cols_attr_mandatory = c('type')
  cols_attr_flex = colnames(df1)[!(colnames(df1) %in% 
                                     c(cols_dimensions, cols_attr_mandatory))]
  # Step 2
  # Run tests
  cat("Step 2 -- run tests\n")
  test_register_copynumbervariant_variable_columns(df1, cnv_attr_cols = cols_attr_mandatory)
  if (!only_test) {
    # Step 3 
    # Introduce `per_gene_pair_fusion_number` column
    if (!('per_gene_copynumbervariant_number' %in% colnames(df1))) {
      # specify dplyr mutate as per https://stackoverflow.com/a/33593868
      df1 = df1 %>% 
        group_by(feature_id, biosample_id) %>% 
        dplyr::mutate(per_gene_copynumbervariant_number = row_number())
    }
    df1 = as.data.frame(df1)
    
    # Step 4
    # Introduce `dataset_version` column
    df1$dataset_version = measurementset$dataset_version
    
    # Step 5A
    # Introduce `key_id` and `val` columns i.e. handle VariantKeys 
    # -- First register any new keys
    cat("Step 5A -- Register the variant attribute columns as variant keys\n")
    variant_key_id = register_variant_key(
      df1 = data.frame(
        key = c(cols_attr_mandatory, cols_attr_flex), 
        stringsAsFactors = FALSE))
    if (!identical(
      get_variant_key(variant_key_id = variant_key_id)$key,
      c(cols_attr_mandatory, cols_attr_flex))) {
      stop("Faced issue registering variant keys")
    }
    
    # Step 5B
    # Match key with key_id-s
    cat("Step 5B -- Converting wide data.frame to tall data.frame\n")
    VAR_KEY = get_variant_key()
    var_gather = tidyr::gather(data = df1, key = "key", value = "val", 
                               c(cols_attr_mandatory, cols_attr_flex))
    M = find_matches_and_return_indices(var_gather$key, VAR_KEY$key)
    stopifnot(length(M$source_unmatched_idx) == 0)
    var_gather$key_id = VAR_KEY$key_id[M$target_matched_idx]
    var_gather$key = NULL # drop the key column
    var_gather = var_gather[, c(cols_dimensions, 'key_id', 'val')]
    
    # Step 6
    # Remove rows that are effectively empty
    cat("Step 6 -- Calculating empty markers\n")
    empty_markers = c('.', 'None')
    non_null_indices = which(!(var_gather$val %in% empty_markers))
    if (length(non_null_indices) != nrow(var_gather)) {
      cat(paste0("From total: ", nrow(var_gather), " key-value pairs, retaining: ", 
                 length(non_null_indices), " non-null pairs.\n\tSavings = ", 
                 (nrow(var_gather) - length(non_null_indices)) / nrow(var_gather) * 100, "%\n"))
      var_gather = var_gather[non_null_indices, ] 
    }
    
    # Step 7
    # Upload and insert the data
    cat("Step 7 -- Upload and insert the data\n")
    upload_variant_data_in_steps(entitynm = entitynm, 
                                 var_gather = var_gather)
  } # end of if (!only_test)
}
