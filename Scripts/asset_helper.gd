extends Node
class_name AssetHelper

# Preload the ObjectBundle class to ensure it's available for casting
const ObjectBundle = preload("res://Server/object_bundle.gd")

# Import Logger
const Logger = preload("res://Scripts/logger.gd")

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

func zip_arr(inputs: Array[Array]) -> Array[Vector2]:
	var output = [] as Array[Vector2]
	for i in range(inputs[0].size()):
		output.append(Vector2(inputs[0][i], inputs[1][i]))
	return output

func set_object(objid: String) -> void:
	current_object_id = objid
	manifest = null
	is_loading_resources = false # Reset loading state for new object
	
	# Try to load bundled resource first (prefer .res, fallback to .tres), then manifest
	var bundle_id = objid + "_bundle.res"  # Try binary format first
	var bundle_id_tres = objid + "_bundle.tres"  # Fallback to text format
	var manifest_id = objid + "_manifest.tres"
	
	# Always try bundle first
	Logger.logger.info("AssetHelper: Loading object " + objid)
	Logger.logger.debug("AssetHelper: Attempting to load bundle: " + bundle_id)
	loader.load_resource(bundle_id)

func _on_resource_loaded(resource_id: String, resource: Resource) -> void:
	# Only handle resources for the current object
	if not resource_id.begins_with(current_object_id):
		return
		
	if resource_id.ends_with("_bundle.res") or resource_id.ends_with("_bundle.tres"):
		# Handle bundled resource
		Logger.logger.info("AssetHelper: Bundle resource received for " + current_object_id + ", type: " + (resource.get_class() if resource else "null"))
		
		# Debug: Check what properties the resource actually has
		if resource:
			Logger.logger.debug("AssetHelper: Resource script: " + str(resource.get_script()))
			Logger.logger.debug("AssetHelper: Resource has manifest property: " + str("manifest" in resource))
			Logger.logger.debug("AssetHelper: Resource has resources property: " + str("resources" in resource))
			if resource.has_method("get"):
				Logger.logger.debug("AssetHelper: Resource.get('manifest'): " + str(resource.get("manifest") != null))
				Logger.logger.debug("AssetHelper: Resource.get('resources'): " + str(resource.get("resources") != null))
		
		# Handle the bundle - it might come as a generic Resource due to serialization
		var bundle_loaded = false
		var bundle_manifest = null
		var bundle_resources = null
		
		# First try direct cast
		var bundle = resource as ObjectBundle
		if bundle:
			Logger.logger.debug("AssetHelper: Successfully cast to ObjectBundle")
			bundle_manifest = bundle.manifest
			bundle_resources = bundle.resources
			bundle_loaded = true
		# If direct cast fails, try accessing properties on generic Resource
		elif resource and "manifest" in resource and "resources" in resource:
			Logger.logger.debug("AssetHelper: Accessing bundle as generic Resource with properties")
			bundle_manifest = resource.manifest
			bundle_resources = resource.resources
			bundle_loaded = true
		# Last resort: try get() method
		elif resource and resource.has_method("get"):
			var test_manifest = resource.get("manifest")
			var test_resources = resource.get("resources")
			if test_manifest != null and test_resources != null:
				Logger.logger.debug("AssetHelper: Accessing bundle via get() method")
				bundle_manifest = test_manifest
				bundle_resources = test_resources
				bundle_loaded = true
		
		if bundle_loaded and bundle_manifest:
			manifest = bundle_manifest
			# Cache all bundled resources in memory
			if bundle_resources:
				for resource_key in bundle_resources:
					var bundled_resource = bundle_resources[resource_key]
					# Extract just the resource type and filter from the key
					# e.g., "1d_F115W" -> cache as "object_id_1d_F115W.res"
					var cache_key = current_object_id + "_" + resource_key + ".res"
					loader.memory_cache[cache_key] = bundled_resource
				Logger.logger.info("AssetHelper: Bundle loaded for " + current_object_id + " with " + str(bundle_resources.size()) + " resources")
			else:
				Logger.logger.warning("AssetHelper: Bundle manifest loaded but no resources found")
			object_loaded.emit(true)
		else:
			Logger.logger.warning("AssetHelper: Bundle resource could not be properly loaded")
			# Try .tres bundle format first, then fall back to manifest
			if resource_id.ends_with("_bundle.res"):
				Logger.logger.info("AssetHelper: .res bundle failed, trying .tres bundle for " + current_object_id)
				var bundle_tres_id = current_object_id + "_bundle.tres"
				loader.load_resource(bundle_tres_id)
			else:
				# Fall back to manifest loading
				Logger.logger.info("AssetHelper: Bundle failed, falling back to manifest for " + current_object_id)
				var manifest_id = current_object_id + "_manifest.tres"
				loader.load_resource(manifest_id)
	elif resource_id.ends_with("_manifest.tres"):
		manifest = resource
		Logger.logger.info("AssetHelper: Manifest loaded for " + current_object_id)
		object_loaded.emit(manifest != null)
	else:
		# Other resource loaded, emit signal only if we're still loading this object
		if current_object_id != "" and resource_id.begins_with(current_object_id):
			Logger.logger.debug("AssetHelper: Individual resource loaded: " + resource_id)
			resource_ready.emit(resource_id)

func _on_resource_failed(resource_id: String, error: String) -> void:
	# Only handle failures for the current object
	if not resource_id.begins_with(current_object_id):
		return
		
	Logger.logger.warning("AssetHelper: Failed to load resource " + resource_id + " - Error: " + error)
	
	if resource_id.ends_with("_bundle.res"):
		# .res bundle failed, try .tres bundle
		Logger.logger.info("AssetHelper: .res bundle failed, trying .tres bundle for " + current_object_id)
		var bundle_tres_id = current_object_id + "_bundle.tres"
		loader.load_resource(bundle_tres_id)
	elif resource_id.ends_with("_bundle.tres"):
		# Both bundle formats failed, try manifest instead
		Logger.logger.info("AssetHelper: All bundle formats failed, falling back to manifest for " + current_object_id)
		var manifest_id = current_object_id + "_manifest.tres"
		loader.load_resource(manifest_id)
	elif resource_id.ends_with("_manifest.tres"):
		Logger.logger.error("AssetHelper: Both bundle and manifest failed for " + current_object_id)
		object_loaded.emit(false)
	else:
		# Individual resource failed - this is normal for async loading
		Logger.logger.debug("AssetHelper: Individual resource failed (expected during async loading): " + resource_id)

func get_pz() -> Resource:
	if manifest and "redshift_path" in manifest:
		# Check if already cached
		var resource_id = _extract_resource_id(manifest.redshift_path)
		if loader.memory_cache.has(resource_id):
			Logger.logger.debug("AssetHelper: Redshift data found in memory cache: " + resource_id)
			return loader.memory_cache[resource_id]
		# Otherwise load it (will be async)
		Logger.logger.debug("AssetHelper: Loading redshift data asynchronously: " + resource_id)
		loader.load_resource(resource_id)
	return null

func _extract_resource_id(path: String) -> String:
	# Convert local path to resource ID
	# e.g., "./processed/uma-03_16420_pz.tres" -> "uma-03_16420_pz.tres"
	var parts = path.split("/")
	var filename = parts[-1]
	# Replace .tres with .res for new format
	if filename.ends_with(".tres"):
		filename = filename.replace(".tres", ".tres")
	return filename

# Public method to extract resource ID (for external use)
func extract_resource_id(path: String) -> String:
	return _extract_resource_id(path)


func get_1d_spectrum(microns: bool = false) -> Dictionary:
	if not manifest or not "spectrum_1d_paths" in manifest:
		return {}
	
	var oneds = manifest.spectrum_1d_paths
	var res = {}
	Logger.logger.debug("AssetHelper: Getting 1D spectra for " + str(oneds.size()) + " filters")
	
	for filt in oneds:
		var resource_id = _extract_resource_id(oneds[filt])
		if loader.memory_cache.has(resource_id):
			Logger.logger.debug("AssetHelper: 1D spectrum found in memory cache for filter " + filt + ": " + resource_id)
			var spec = loader.memory_cache[resource_id] as Spectrum1DResource
			if not spec:
				Logger.logger.warning("AssetHelper: Failed to cast 1D spectrum resource for filter " + filt)
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
			Logger.logger.debug("AssetHelper: Processed 1D spectrum for filter " + filt + " with " + str(waves.size()) + " wavelength points")
		else:
			# Load resource asynchronously
			Logger.logger.debug("AssetHelper: Loading 1D spectrum asynchronously for filter " + filt + ": " + resource_id)
			loader.load_resource(resource_id)
	
	return res

func get_directs() -> Dictionary:
	if not manifest or not "direct_image_paths" in manifest:
		return {}
	var res = {}
	Logger.logger.debug("AssetHelper: Getting direct images for " + str(manifest.direct_image_paths.size()) + " filters")
	
	for filt in manifest.direct_image_paths:
		var resource_id = _extract_resource_id(manifest.direct_image_paths[filt])
		if loader.memory_cache.has(resource_id):
			Logger.logger.debug("AssetHelper: Direct image found in memory cache for filter " + filt + ": " + resource_id)
			res[filt] = loader.memory_cache[resource_id]
		else:
			# Load resource asynchronously
			Logger.logger.debug("AssetHelper: Loading direct image asynchronously for filter " + filt + ": " + resource_id)
			loader.load_resource(resource_id)
	return res


func get_2d_spectra() -> Dictionary:
	if not manifest or not "spectrum_2d_paths_by_pa" in manifest:
		return {}
	var res = {}
	var total_spectra = 0
	for pa in manifest.spectrum_2d_paths_by_pa:
		total_spectra += manifest.spectrum_2d_paths_by_pa[pa].size()
	Logger.logger.debug("AssetHelper: Getting 2D spectra for " + str(manifest.spectrum_2d_paths_by_pa.size()) + " position angles, " + str(total_spectra) + " total spectra")
	
	for pa in manifest.spectrum_2d_paths_by_pa:
		if pa not in res:
			res[pa] = {}
		for filt in manifest.spectrum_2d_paths_by_pa[pa]:
			var resource_id = _extract_resource_id(manifest.spectrum_2d_paths_by_pa[pa][filt])
			if loader.memory_cache.has(resource_id):
				Logger.logger.debug("AssetHelper: 2D spectrum found in memory cache for PA " + pa + ", filter " + filt + ": " + resource_id)
				res[pa][filt] = loader.memory_cache[resource_id]
			else:
				# Load resource asynchronously
				Logger.logger.debug("AssetHelper: Loading 2D spectrum asynchronously for PA " + pa + ", filter " + filt + ": " + resource_id)
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
	
	Logger.logger.info("AssetHelper: Preloading resources for next object: " + next_object_id)
	
	# Try to preload bundle first (prefer .res), fall back to manifest
	var bundle_id = next_object_id + "_bundle.res"
	var bundle_id_tres = next_object_id + "_bundle.tres"
	var manifest_id = next_object_id + "_manifest.tres"
	
	Logger.logger.debug("AssetHelper: Preloading bundle (.res): " + bundle_id)
	loader.preload_resource(bundle_id)
	Logger.logger.debug("AssetHelper: Preloading bundle (.tres): " + bundle_id_tres)
	loader.preload_resource(bundle_id_tres)
	Logger.logger.debug("AssetHelper: Preloading manifest: " + manifest_id)
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
	Logger.logger.info("AssetHelper: Starting to load all resources for: " + current_object_id)
	
	var total_resources = 0
	
	# Load redshift data
	if "redshift_path" in manifest:
		var resource_id = _extract_resource_id(manifest.redshift_path)
		Logger.logger.debug("AssetHelper: Loading redshift resource: " + resource_id)
		loader.load_resource(resource_id)
		total_resources += 1
	
	# Load 1D spectra
	if "spectrum_1d_paths" in manifest:
		Logger.logger.debug("AssetHelper: Loading " + str(manifest.spectrum_1d_paths.size()) + " 1D spectra")
		for filt in manifest.spectrum_1d_paths:
			var resource_id = _extract_resource_id(manifest.spectrum_1d_paths[filt])
			Logger.logger.debug("AssetHelper: Loading 1D spectrum for filter " + filt + ": " + resource_id)
			loader.load_resource(resource_id)
			total_resources += 1
	
	# Load direct images
	if "direct_image_paths" in manifest:
		Logger.logger.debug("AssetHelper: Loading " + str(manifest.direct_image_paths.size()) + " direct images")
		for filt in manifest.direct_image_paths:
			var resource_id = _extract_resource_id(manifest.direct_image_paths[filt])
			Logger.logger.debug("AssetHelper: Loading direct image for filter " + filt + ": " + resource_id)
			loader.load_resource(resource_id)
			total_resources += 1
	
	# Load 2D spectra
	if "spectrum_2d_paths_by_pa" in manifest:
		var spectra_2d_count = 0
		for pa in manifest.spectrum_2d_paths_by_pa:
			spectra_2d_count += manifest.spectrum_2d_paths_by_pa[pa].size()
		Logger.logger.debug("AssetHelper: Loading " + str(spectra_2d_count) + " 2D spectra across " + str(manifest.spectrum_2d_paths_by_pa.size()) + " position angles")
		for pa in manifest.spectrum_2d_paths_by_pa:
			for filt in manifest.spectrum_2d_paths_by_pa[pa]:
				var resource_id = _extract_resource_id(manifest.spectrum_2d_paths_by_pa[pa][filt])
				Logger.logger.debug("AssetHelper: Loading 2D spectrum for PA " + pa + ", filter " + filt + ": " + resource_id)
				loader.load_resource(resource_id)
				total_resources += 1
	
	Logger.logger.info("AssetHelper: Initiated loading of " + str(total_resources) + " total resources for " + current_object_id)

func zip_p32(inputs: Array[PackedFloat32Array]) -> Array[Vector2]:
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
