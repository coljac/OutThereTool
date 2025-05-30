class_name ObjectManifest
extends Resource

## Resource for storing references to all data for an object
##
## This manifest resource serves as an index for all pre-processed data
## related to a specific astronomical object.

## The ID of the object
@export var object_id: String

## Object name (if different from ID)
@export var object_name: String

## Number of bands/filters available for this object
@export var band_count: int

## Date when the observation was taken
@export var observation_date: String

## Best redshift value for this object
@export var redshift: float

## Paths to 1D spectrum resources, keyed by filter name
@export var spectrum_1d_paths: Dictionary  # filter_name -> resource_path

## Paths to 2D spectrum resources, keyed by filter name
@export var spectrum_2d_paths: Dictionary  # filter_name -> resource_path

## Paths to 2D spectrum resources, organized by position angle and filter
## This is a nested dictionary: {PA -> {filter_name -> resource_path}}
@export var spectrum_2d_paths_by_pa: Dictionary  # pa -> filter_name -> resource_path

## Paths to direct image resources, keyed by filter name
@export var direct_image_paths: Dictionary  # filter_name -> resource_path

## Path to the redshift resource
@export var redshift_path: String

## Additional metadata about the object
@export var metadata: Dictionary

## Returns a list of all available filters for this object
func get_available_filters() -> Array:
    var filters = []
    for filter_name in spectrum_1d_paths.keys():
        if not filter_name in filters:
            filters.append(filter_name)
    for filter_name in spectrum_2d_paths.keys():
        if not filter_name in filters:
            filters.append(filter_name)
    for filter_name in direct_image_paths.keys():
        if not filter_name in filters:
            filters.append(filter_name)
    return filters

## Returns a list of all available position angles for 2D spectra
func get_available_position_angles() -> Array:
    return spectrum_2d_paths_by_pa.keys()

## Returns a list of filters available for a specific position angle
func get_filters_for_position_angle(pa: String) -> Array:
    if not pa in spectrum_2d_paths_by_pa:
        return []
    return spectrum_2d_paths_by_pa[pa].keys()