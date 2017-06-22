
At commit d54f3e5
==============

Recent changes:

1. The following external-facing API formulates a table containing information about
entities in the hierarchy

```R
get_entity_info()
#                  entity               class     search_by_entity     delete_by_entity
# 1               PROJECT            metadata                 <NA>              PROJECT
# 2               DATASET            metadata              PROJECT              DATASET
# ...
# 7     RNAQUANTIFICATION                data RNAQUANTIFICATIONSET RNAQUANTIFICATIONSET
```

2. Delete of measurement data is now working as 

```R
delete_entity(entity = 'RNAQUANTIFICATION', 
            ids = 2, dataset_version = 1, 
            delete_by_entity = 'RNAQUANTIFICATIONSET')
# RnaQuantification data can be deleted by the parent RnaQuantificationSet

delete_entity(entity = 'VARIANT', 
            ids = 1, dataset_version = 2, 
            delete_by_entity = 'VARIANTSET')
# Variant data can be deleted by the parent VariantSet

# The earlier API for metadata and feature-data continues to work
delete_entity(entity = 'DATASET', id = 1, dataset_version = 2)
delete_entity(entity = 'ONTOLOGY', id = 1)
```

3. Change in `delete_entity()` and `get_entity()` API: 
parameter `ids` is now called `id`
(to be consistent with other calls in the API)

4. Two internal API to infer hierarchy and delete preferences
```R
## parent entity by which one would search an entity 
scidb4gh:::get_search_by_entity(entity = 'RNAQUANTIFICATION')
# [1] "RNAQUANTIFICATIONSET"
scidb4gh:::get_search_by_entity(entity = 'RNAQUANTIFICATIONSET')
# [1] "DATASET"
```
    
```R
## entity by which one would delete an entity 
scidb4gh:::get_delete_by_entity(entity = 'RNAQUANTIFICATION')
# [1] "RNAQUANTIFICATIONSET"
scidb4gh:::get_delete_by_entity(entity = 'RNAQUANTIFICATIONSET')
# [1] "RNAQUANTIFICATIONSET"
```
5. `search_copynumberset(dataset_id = ..)` was throwing an error earlier when there 
were no CopyNumberSets in a dataset. This should be fixed now.