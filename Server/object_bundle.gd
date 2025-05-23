extends Resource
class_name ObjectBundle

## A bundled resource containing all data for a single astronomical object
##
## This resource type combines the manifest and all individual resources
## (1D spectra, 2D spectra, direct images, redshift data) into a single file
## for improved loading performance and reduced network requests.

## The object manifest containing metadata and resource organization
@export var manifest: ObjectManifest

## Dictionary containing all individual resources, keyed by resource type
## Keys follow the pattern:
## - "redshift" - RedshiftResource
## - "1d_<filter>" - Spectrum1DResource for each filter
## - "direct_<filter>" - DirectImageResource for each filter  
## - "2d_PA<pa>_<filter>" - Spectrum2DResource for each PA/filter combination
@export var resources: Dictionary = {}

## Get a specific resource by type and filter/PA
##
## @param resource_type The type of resource ("redshift", "1d", "direct", "2d")
## @param filter_name The filter name (for 1d, direct, 2d resources)
## @param position_angle The position angle (for 2d resources only)
## @return The requested resource, or null if not found
func get_resource(resource_type: String, filter_name: String = "", position_angle: String = "") -> Resource:
	var key = ""
	
	match resource_type:
		"redshift":
			key = "redshift"
		"1d":
			key = "1d_" + filter_name
		"direct":
			key = "direct_" + filter_name
		"2d":
			key = "2d_PA" + position_angle + "_" + filter_name
		_:
			print("Unknown resource type: ", resource_type)
			return null
	
	if key in resources:
		return resources[key]
	else:
		print("Resource not found: ", key)
		return null

## Get all resources of a specific type
##
## @param resource_type The type of resource to get all instances of
## @return Dictionary of resources matching the type
func get_resources_of_type(resource_type: String) -> Dictionary:
	var result = {}
	var prefix = resource_type + "_"
	
	if resource_type == "redshift":
		if "redshift" in resources:
			result["redshift"] = resources["redshift"]
		return result
	
	for key in resources:
		if key.begins_with(prefix):
			result[key] = resources[key]
	
	return result

## Get the total size of all bundled resources (for debugging)
func get_bundle_size() -> int:
	var total_size = 0
	for key in resources:
		var resource = resources[key]
		if resource:
			# Rough estimate - would need actual serialization for exact size
			total_size += 1024  # Placeholder
	return total_size

## Get statistics about the bundle
func get_bundle_stats() -> Dictionary:
	var stats = {
		"total_resources": resources.size(),
		"redshift_resources": 0,
		"1d_resources": 0,
		"direct_resources": 0,
		"2d_resources": 0
	}
	
	for key in resources:
		if key == "redshift":
			stats.redshift_resources += 1
		elif key.begins_with("1d_"):
			stats["1d_resources"] += 1
		elif key.begins_with("direct_"):
			stats.direct_resources += 1
		elif key.begins_with("2d_"):
			stats["2d_resources"] += 1
	
	return stats