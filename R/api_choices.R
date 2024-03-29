#' classes to handle different choices sheets in Excel template
#' 
#' e.g. pipeline_choices, filter_choices, featureset_choices

Choices = R6::R6Class(
  classname = 'Choices',
  public = list(
    initialize = function(choices_df, keyname) {
      if (length(unique(choices_df[, keyname])) != nrow(choices_df)) {
        cat("Choices in choices sheet under column `", keyname, "` must be unique\n")
        print(table(choices_df[, keyname]))
        stop("...")
      }
      private$.choices_df = choices_df
      private$.keyname = keyname
    }
  ), 
  private = list(
    #' multiple matches at a time
    get_selected_rows = function(keys) {
      m1 = find_matches_and_return_indices(keys, private$.choices_df[, private$.keyname])
      if (length(m1$source_unmatched_idx) != 0) {
        stop("Unmatched keys: ", pretty_print(keys[m1$source_unmatched_idx]))
      }
      private$.choices_df[m1$target_matched_idx, ]
    },
    .choices_df = NULL,
    .keyname = NULL
  )
)

#' extract relevant info pertaining to pipeline_choices sheet
#' 
#' @export
PipelineChoices = R6::R6Class(
  classname = 'PipelineChoices',
  inherit = Choices,
  public = list(
    initialize = function(pipeline_choices_df) {
      super$initialize(choices_df = pipeline_choices_df, 
                       keyname = template_linker$pipeline$choices_col)
    },
    get_measurement_entity = function(keys) {
      private$get_selected_rows(keys = keys)$measurement_entity
    },
    get_data_subtype = function(keys) {
      private$get_selected_rows(keys = keys)$data_subtype
    },
    get_pipeline_metadata = function(keys) {
      private$get_selected_rows(keys = keys)
    }
  )
)

#' extract relevant info pertaining to filter_choices sheet
#' 
#' @export
FilterChoices = R6::R6Class(
  classname = 'FilterChoices',
  inherit = Choices,
  public = list(
    initialize = function(filter_choices_df) {
      super$initialize(choices_df = filter_choices_df, 
                       keyname = template_linker$filter$choices_col)
    },
    get_quantification_level = function(keys) {
      private$get_selected_rows(keys = keys)$quantification_level
    },
    get_quantification_unit = function(keys) {
      private$get_selected_rows(keys = keys)$quantification_unit
    },
    get_measurement_entity = function(keys) {
      private$get_selected_rows(keys = keys)$measurement_entity
    },
    get_filter_metadata = function(keys) {
      private$get_selected_rows(keys = keys)
    }
  )
)

#' extract relevant info pertaining to featureset_choices sheet
#' 
#' @export
FeaturesetChoices = R6::R6Class(
  classname = 'FeaturesetChoices',
  inherit = Choices,
  public = list(
    initialize = function(featureset_choices_df) {
      super$initialize(choices_df = featureset_choices_df, 
                       keyname = template_linker$featureset$choices_col)
    },
    get_featureset_name = function(keys) {
      private$get_selected_rows(keys = keys)$featureset_name
    },
    get_featureset_metadata = function(keys) {
      private$get_selected_rows(keys = keys)
    }
  )
)
