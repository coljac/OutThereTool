# Test script to verify filter range logic
extends RefCounted

# Wavelength ranges for each filter in microns
const FILTER_WAVELENGTH_RANGES = {
	"F115W": {"x_min": 0.9, "x_max": 1.3},
	"F150W": {"x_min": 1.3, "x_max": 1.7}, 
	"F200W": {"x_min": 1.7, "x_max": 2.3}
}

# Function to determine optimal wavelength range based on available filters
static func _get_wavelength_range_for_filters(available_filters: Array) -> Dictionary:
	if available_filters.is_empty():
		return {"x_min": 0.9, "x_max": 2.3}  # Default full range
	
	var min_wavelength = INF
	var max_wavelength = -INF
	
	for filter_name in available_filters:
		if FILTER_WAVELENGTH_RANGES.has(filter_name):
			var range = FILTER_WAVELENGTH_RANGES[filter_name]
			min_wavelength = min(min_wavelength, range.x_min)
			max_wavelength = max(max_wavelength, range.x_max)
	
	return {"x_min": min_wavelength, "x_max": max_wavelength}

func _ready():
	# Test cases
	print("Testing filter range logic:")
	
	# Test single filter
	var result1 = _get_wavelength_range_for_filters(["F115W"])
	print("F115W only: ", result1)  # Should be 0.9-1.3
	
	# Test two filters
	var result2 = _get_wavelength_range_for_filters(["F115W", "F150W"])
	print("F115W + F150W: ", result2)  # Should be 0.9-1.7
	
	# Test all filters
	var result3 = _get_wavelength_range_for_filters(["F115W", "F150W", "F200W"])
	print("All filters: ", result3)  # Should be 0.9-2.3
	
	# Test empty
	var result4 = _get_wavelength_range_for_filters([])
	print("No filters: ", result4)  # Should be 0.9-2.3 (default)
	
	# Test unknown filter
	var result5 = _get_wavelength_range_for_filters(["UNKNOWN"])
	print("Unknown filter: ", result5)  # Should be 0.9-2.3 (default)