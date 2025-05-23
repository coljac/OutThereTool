extends Node
class_name CachedResourceLoader

# Base URL for resources (from centralized config)
var BASE_URL: String = NetworkConfig.get_base_url()

# Cache directory in user space
var cache_dir: String = "user://cache/"

# In-memory cache for quick access
var memory_cache = {}

# Currently loading resources to prevent duplicate requests
var loading_resources = {}

# Signals
signal resource_loaded(resource_id: String, resource: Resource)
signal resource_failed(resource_id: String, error: String)

func _ready():
	# Create cache directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)

# Load a resource, checking cache first, then network
func load_resource(resource_id: String) -> void:
	# Check in-memory cache first
	if memory_cache.has(resource_id):
		print("Loading from memory cache: ", resource_id)
		resource_loaded.emit(resource_id, memory_cache[resource_id])
		return
	
	# Check if already loading
	if loading_resources.has(resource_id):
		print("Already loading: ", resource_id)
		return
	
	# Check file cache
	var cache_path = cache_dir + resource_id
	if FileAccess.file_exists(cache_path):
		print_debug("Loading from file cache: ", resource_id)
		_load_from_cache(resource_id, cache_path)
		return
	
	# Not in cache, fetch from network
	print("Fetching from network: ", resource_id)
	_fetch_from_network(resource_id)

# Load resource from file cache
func _load_from_cache(resource_id: String, cache_path: String) -> void:
	var resource = ResourceLoader.load(cache_path)
	if resource:
		memory_cache[resource_id] = resource
		resource_loaded.emit(resource_id, resource)
	else:
		print("Failed to load from cache, fetching from network: ", resource_id)
		# Cache file might be corrupted, try network
		_remove_from_cache(resource_id)
		_fetch_from_network(resource_id)

# Fetch resource from network
func _fetch_from_network(resource_id: String) -> void:
	loading_resources[resource_id] = true
	
	var url = BASE_URL + resource_id
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Connect to completion signal
	http_request.request_completed.connect(_on_network_request_completed.bind(resource_id, http_request))
	
	# Make the request
	var error = http_request.request(url)
	if error != OK:
		_cleanup_request(resource_id, http_request)
		resource_failed.emit(resource_id, "HTTP Request Error: " + str(error))

# Handle network request completion
func _on_network_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, resource_id: String, http_request: HTTPRequest) -> void:
	_cleanup_request(resource_id, http_request)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		resource_failed.emit(resource_id, "HTTP Request Failed: " + str(result))
		return
	
	if response_code != 200:
		resource_failed.emit(resource_id, "HTTP Error: " + str(response_code))
		return
	
	# Save to cache
	var cache_path = cache_dir + resource_id
	_save_to_cache(cache_path, body)
	
	# Load the resource
	var resource = ResourceLoader.load(cache_path)
	if resource:
		memory_cache[resource_id] = resource
		resource_loaded.emit(resource_id, resource)
	else:
		resource_failed.emit(resource_id, "Failed to load resource after download")

# Save data to cache file
func _save_to_cache(cache_path: String, data: PackedByteArray) -> void:
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if file:
		file.store_buffer(data)
		file.close()
	else:
		print("Failed to save to cache: ", cache_path)

# Remove a resource from cache
func _remove_from_cache(resource_id: String) -> void:
	var cache_path = cache_dir + resource_id
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)
	
	if memory_cache.has(resource_id):
		memory_cache.erase(resource_id)

# Cleanup request resources
func _cleanup_request(resource_id: String, http_request: HTTPRequest) -> void:
	loading_resources.erase(resource_id)
	http_request.queue_free()

# Check if resource exists in cache
func is_cached(resource_id: String) -> bool:
	return memory_cache.has(resource_id) or FileAccess.file_exists(cache_dir + resource_id)

# Preload a resource (async, for prefetching)
func preload_resource(resource_id: String) -> void:
	if not is_cached(resource_id) and not loading_resources.has(resource_id):
		load_resource(resource_id)

# Clear all caches
func clear_cache() -> void:
	memory_cache.clear()
	var dir = DirAccess.open(cache_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()

# Get cache size in bytes
func get_cache_size() -> int:
	var total_size = 0
	var dir = DirAccess.open(cache_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var file_path = cache_dir + file_name
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					total_size += file.get_length()
					file.close()
			file_name = dir.get_next()
	return total_size