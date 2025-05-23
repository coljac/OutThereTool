extends Node
class_name AssetHelper

var c_log10 = log(10)

var manifest: Resource
var loader: ThreadedCachedResourceLoader
var current_object_id: String
var is_loading_resources: bool = false

# Signals
signal object_loaded(success: bool)
signal resource_ready(resource_name: String)

func _ready():
	loader = GlobalResourceCache.get_loader()
	loader.resource_loaded.connect(_on_resource_loaded)
	loader.resource_failed.connect(_on_resource_failed)

func set_object(objid: String) -> void:
	current_object_id = objid
	manifest = null
	is_loading_resources = false  # Reset loading state for new object
	
	# Try to load bundled resource first, fall back to manifest
	var bundle_id = objid + "_bundle.res"
	var manifest_id = objid + "_manifest.res"
	
	# Check if bundle exists in cache
	if loader.is_cached(bundle_id):
		print("Loading bundled resource for: ", objid)
		loader.load_resource(bundle_id)
	else:
		print("Loading manifest for: ", objid)
		loader.load_resource(manifest_id)

func _on_resource_loaded(resource_id: String, resource: Resource) -> void:
	# Only handle resources for the current object
	if not resource_id.begins_with(current_object_id):
		return
		
	if resource_id.ends_with("_bundle.res"):
		# Handle bundled resource
		var bundle = resource as ObjectBundle
		if bundle:
			manifest = bundle.manifest
			# Cache all bundled resources in memory
			for resource_key in bundle.resources:
				var bundled_resource = bundle.resources[resource_key]
				var cache_key = current_object_id + "_" + resource_key + ".res"
				loader.memory_cache[cache_key] = bundled_resource
			print("Bundle loaded for: ", current_object_id, " with ", bundle.resources.size(), " resources")
			object_loaded.emit(true)
	elif resource_id.ends_with("_manifest.res"):
		manifest = resource
		print("Manifest loaded for: ", current_object_id)
		object_loaded.emit(manifest != null)
	else:
		# Other resource loaded, emit signal only if we're still loading this object
		if current_object_id != "" and resource_id.begins_with(current_object_id):
			resource_ready.emit(resource_id)

func _on_resource_failed(resource_id: String, error: String) -> void:
	# Only handle failures for the current object
	if not resource_id.begins_with(current_object_id):
		return
		
	print("Failed to load resource: ", resource_id, " Error: ", error)
	
	if resource_id.ends_with("_bundle.res"):
		# Bundle failed, try manifest instead
		print("Bundle failed, trying manifest for: ", current_object_id)
		var manifest_id = current_object_id + "_manifest.res"
		loader.load_resource(manifest_id)
	elif resource_id.ends_with("_manifest.res"):
		object_loaded.emit(false)

func get_pz() -> Resource:
	if manifest and "redshift_path" in manifest:
		# Check if already cached
		var resource_id = _extract_resource_id(manifest.redshift_path)
		if loader.memory_cache.has(resource_id):
			return loader.memory_cache[resource_id]
		# Otherwise load it (will be async)
		loader.load_resource(resource_id)
	return null

func _extract_resource_id(path: String) -> String:
	# Convert local path to resource ID
	# e.g., "./processed/uma-03_16420_pz.tres" -> "uma-03_16420_pz.res"
	var parts = path.split("/")
	var filename = parts[-1]
	# Replace .tres with .res for new format
	if filename.ends_with(".tres"):
		filename = filename.replace(".tres", ".res")
	return filename

# Public method to extract resource ID (for external use)
func extract_resource_id(path: String) -> String:
	return _extract_resource_id(path)


func get_1d_spectrum(microns: bool = false) -> Dictionary:
	if not manifest or not "spectrum_1d_paths" in manifest:
		return {}
	
	var oneds = manifest.spectrum_1d_paths
	var res = {}
	for filt in oneds:
		var resource_id = _extract_resource_id(oneds[filt])
		if loader.memory_cache.has(resource_id):
			var spec = loader.memory_cache[resource_id] as Spectrum1DResource
			if not spec:
				continue
			var waves = spec.wavelengths
			var fluxes = spec.fluxes
			var errors = spec.errors
			var bestfit = spec.bestfit
			
			var max = Array(fluxes).max()
			
			res[filt] = {
				"fluxes": zip_p32([waves, fluxes]),
				"err": errors,
				"bestfit": zip_p32([waves, spec.bestfit]),
				"cont": zip_p32([waves, spec.continuum]),
				"contam": zip_p32([waves, spec.contam]),
				"flat": spec.flat,
				"max": max
			}
		else:
			# Load resource asynchronously
			loader.load_resource(resource_id)
	
	return res

func get_directs() -> Dictionary:
	if not manifest or not "direct_image_paths" in manifest:
		return {}
	var res = {}
	for filt in manifest.direct_image_paths:
		var resource_id = _extract_resource_id(manifest.direct_image_paths[filt])
		if loader.memory_cache.has(resource_id):
			res[filt] = loader.memory_cache[resource_id]
		else:
			# Load resource asynchronously
			loader.load_resource(resource_id)
	return res


func get_2d_spectra() -> Dictionary:
	if not manifest or not "spectrum_2d_paths_by_pa" in manifest:
		return {}
	var res = {}
	for pa in manifest.spectrum_2d_paths_by_pa:
		if pa not in res:
			res[pa] = {}
		for filt in manifest.spectrum_2d_paths_by_pa[pa]:
			var resource_id = _extract_resource_id(manifest.spectrum_2d_paths_by_pa[pa][filt])
			if loader.memory_cache.has(resource_id):
				res[pa][filt] = loader.memory_cache[resource_id]
			else:
				# Load resource asynchronously
				loader.load_resource(resource_id)
	return res


func load_2ds():
	if manifest:
		print("2D spectra by filter: ", manifest['spectrum_2d_paths'])
		print("2D spectra by PA: ", manifest['spectrum_2d_paths_by_pa'])

		
func get_2d_spectra_by_pa(pa: String) -> Dictionary:
	if not manifest or not "spectrum_2d_paths_by_pa" in manifest:
		return {}
	
	if not pa in manifest.spectrum_2d_paths_by_pa:
		return {}
	
	return manifest.spectrum_2d_paths_by_pa[pa]

# Preload resources for the next object (background loading)
func preload_next_object(next_object_id: String) -> void:
	if next_object_id == "" or next_object_id == current_object_id:
		return
	
	print("Preloading resources for next object: ", next_object_id)
	
	# Try to preload bundle first, fall back to manifest
	var bundle_id = next_object_id + "_bundle.res"
	var manifest_id = next_object_id + "_manifest.res"
	
	loader.preload_resource(bundle_id)
	loader.preload_resource(manifest_id)

# Cleanup connections when destroying this instance
func cleanup_connections() -> void:
	if loader:
		if loader.resource_loaded.is_connected(_on_resource_loaded):
			loader.resource_loaded.disconnect(_on_resource_loaded)
		if loader.resource_failed.is_connected(_on_resource_failed):
			loader.resource_failed.disconnect(_on_resource_failed)

# Debug function to check loader performance
func get_performance_stats() -> Dictionary:
	if loader and loader.has_method("get_stats"):
		return loader.get_stats()
	return {}

func get_available_position_angles() -> Array:
	if not manifest or not "spectrum_2d_paths_by_pa" in manifest:
		return []
	
	return manifest.spectrum_2d_paths_by_pa.keys()

# Load all resources for current object
func load_all_resources() -> void:
	if not manifest or is_loading_resources:
		return
	
	is_loading_resources = true
	print("Starting to load all resources for: ", current_object_id)
	
	# Load redshift data
	if "redshift_path" in manifest:
		var resource_id = _extract_resource_id(manifest.redshift_path)
		loader.load_resource(resource_id)
	
	# Load 1D spectra
	if "spectrum_1d_paths" in manifest:
		for filt in manifest.spectrum_1d_paths:
			var resource_id = _extract_resource_id(manifest.spectrum_1d_paths[filt])
			loader.load_resource(resource_id)
	
	# Load direct images
	if "direct_image_paths" in manifest:
		for filt in manifest.direct_image_paths:
			var resource_id = _extract_resource_id(manifest.direct_image_paths[filt])
			loader.load_resource(resource_id)
	
	# Load 2D spectra
	if "spectrum_2d_paths_by_pa" in manifest:
		for pa in manifest.spectrum_2d_paths_by_pa:
			for filt in manifest.spectrum_2d_paths_by_pa[pa]:
				var resource_id = _extract_resource_id(manifest.spectrum_2d_paths_by_pa[pa][filt])
				loader.load_resource(resource_id)

func zip_p32(inputs: Array[PackedFloat32Array]) -> Array[Vector2]:
	var output = [] as Array[Vector2]
	for i in range(inputs[0].size()):
		output.append(Vector2(inputs[0][i], inputs[1][i]))
	return output
		

func zip_arr(inputs: Array[Array]) -> Array[Vector2]:
	var output = [] as Array[Vector2]
	for i in range(inputs[0].size()):
		output.append(Vector2(inputs[0][i], inputs[1][i]))
	return output

	
func peak_finding(data, window_size):
	"""
	Find values and positions of peaks in a given time series data.
	Return an array of dictionaries [{x=x1, max=max1}, {x=x2, max=max2},...,{x=xn, max=maxn}]

	data:        An array containing time series data
	window_size: Look for peaks in a box of "window_size" size
	"""
	# Create extended array with zeros at beginning and end
	var data_extended = []
	
	# Add leading zeros
	for i in range(window_size):
		data_extended.append(0)
	
	# Add original data
	for value in data:
		data_extended.append(value)
	
	# Add trailing zeros  
	for i in range(window_size):
		data_extended.append(0)
	
	var max_list = []
	
	for i in range(len(data_extended)):
		if i >= window_size and i < len(data_extended) - window_size:
			# Find max value in left window
			var max_left = 0
			for j in range(i - window_size, i + 1):
				max_left = max(max_left, data_extended[j])
			
			# Find max value in right window
			var max_right = 0
			for j in range(i, i + window_size + 1):
				max_right = max(max_right, data_extended[j])
			
			var check_value = data_extended[i] - ((max_left + max_right) / 2)
			
			if check_value >= 0:
				# In GDScript, let's return a dictionary instead of a tuple
				max_list.append({"x": i - window_size, "max": data[i - window_size]})
	
	return max_list
