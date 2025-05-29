extends Node
class_name ThreadedCachedResourceLoader

# Base URL for resources (from centralized config)
var BASE_URL: String = NetworkConfig.get_base_url()
const MAX_CONCURRENT_REQUESTS = 8

# Preload the ObjectBundle class to ensure it's available for .res loading
const ObjectBundle = preload("res://Server/object_bundle.gd")

# Cache directory in user space
var cache_dir: String = "user://cache/"

# In-memory cache for quick access
var memory_cache = {}

# Currently loading resources to prevent duplicate requests
var loading_resources = {}

# Failed resources to prevent infinite retry loops
var failed_resources = {}

# HTTP request pool for better performance
var http_request_pool: Array[HTTPRequest] = []
var available_requests: Array[HTTPRequest] = []

# Thread pool for file operations
var worker_threads: Array[WorkerThread] = []
var thread_pool_size = 2

# Signals
signal resource_loaded(resource_id: String, resource: Resource)
signal resource_failed(resource_id: String, error: String)

# Custom worker thread class for file operations
class WorkerThread:
	var thread: Thread
	var mutex: Mutex
	var semaphore: Semaphore
	var should_quit: bool = false
	var tasks: Array = []
	
	func _init():
		thread = Thread.new()
		mutex = Mutex.new()
		semaphore = Semaphore.new()
		thread.start(_worker_loop)
	
	func add_task(task: Callable):
		mutex.lock()
		tasks.append(task)
		mutex.unlock()
		semaphore.post()
	
	func _worker_loop():
		while not should_quit:
			semaphore.wait()
			if should_quit:
				break
			
			mutex.lock()
			if tasks.size() > 0:
				var task = tasks.pop_front()
				mutex.unlock()
				task.call()
			else:
				mutex.unlock()
	
	func quit():
		should_quit = true
		semaphore.post()
		thread.wait_to_finish()

func _ready():
	# Create cache directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	
	# Initialize HTTP request pool
	_init_http_pool()
	
	# Initialize worker threads
	_init_worker_threads()

func _init_http_pool():
	for i in range(MAX_CONCURRENT_REQUESTS):
		var http_request = HTTPRequest.new()
		add_child(http_request)
		http_request_pool.append(http_request)
		available_requests.append(http_request)

func _init_worker_threads():
	for i in range(thread_pool_size):
		var worker = WorkerThread.new()
		worker_threads.append(worker)

func _exit_tree():
	# Clean up worker threads
	for worker in worker_threads:
		worker.quit()

# Load a resource, checking cache first, then network
func load_resource(resource_id: String) -> void:
	# Check if this resource has failed before
	if failed_resources.has(resource_id):
		print("Resource previously failed, skipping: ", resource_id)
		resource_failed.emit(resource_id, "Resource previously failed")
		return
	
	# Check in-memory cache first
	if memory_cache.has(resource_id):
		print("Loading from memory cache: ", resource_id)
		resource_loaded.emit(resource_id, memory_cache[resource_id])
		return
	
	# Check if already loading
	if loading_resources.has(resource_id):
		# print("Already loading: ", resource_id)
		return
	
	# Check file cache asynchronously
	var cache_path = cache_dir + resource_id
	if FileAccess.file_exists(cache_path):
		# print_debug("Loading from file cache: ", resource_id)
		_load_from_cache_async(resource_id, cache_path)
		return
	
	# Not in cache, fetch from network
	print("Fetching from network: ", resource_id)
	_fetch_from_network(resource_id)

# Load resource from file cache asynchronously
func _load_from_cache_async(resource_id: String, cache_path: String) -> void:
	loading_resources[resource_id] = true
	
	# Get a worker thread to load the resource
	var worker = _get_available_worker()
	worker.add_task(func(): _load_cache_worker(resource_id, cache_path))

func _load_cache_worker(resource_id: String, cache_path: String) -> void:
	# This runs in a worker thread
	var resource = null
	var error_msg = ""
	
	# Check if file exists and is readable
	if not FileAccess.file_exists(cache_path):
		error_msg = "Cache file does not exist"
	else:
		var file = FileAccess.open(cache_path, FileAccess.READ)
		if not file:
			error_msg = "Cannot open cache file for reading"
		else:
			var file_size = file.get_length()
			file.close()
			
			if file_size == 0:
				error_msg = "Cache file is empty"
			else:
				# Try to load the resource with different approaches
				# First try normal loading
				resource = ResourceLoader.load(cache_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				if not resource:
					# For .res files, try loading without cache mode restriction
					resource = ResourceLoader.load(cache_path)
					
				if not resource:
					# Try loading with explicit type hint for bundle files
					if resource_id.ends_with("_bundle.tres") or resource_id.ends_with("_bundle.tres"):
						resource = ResourceLoader.load(cache_path, "ObjectBundle")
					elif resource_id.ends_with("_manifest.tres") or resource_id.ends_with("_manifest.tres"):
						resource = ResourceLoader.load(cache_path, "ObjectManifest")
					
				if not resource:
					# Final attempt: try loading without any type hint
					resource = ResourceLoader.load(cache_path, "", ResourceLoader.CACHE_MODE_REUSE)
					if resource:
						print("Loaded with CACHE_MODE_REUSE: ", resource.get_class())
					
					if not resource:
						# Try completely fresh load
						resource = ResourceLoader.load(cache_path, "", ResourceLoader.CACHE_MODE_REPLACE)
						if resource:
							print("Loaded with CACHE_MODE_REPLACE: ", resource.get_class())
					
					if not resource:
						# Get more specific error info
						var loader_error = ResourceLoader.get_resource_uid(cache_path)
						error_msg = "ResourceLoader failed to load resource file (UID check: " + str(loader_error) + ")"
						
						# Try to read first few bytes to see if it's a valid file
						var debug_file = FileAccess.open(cache_path, FileAccess.READ)
						if debug_file:
							var first_bytes = debug_file.get_buffer(16)
							debug_file.close()
							error_msg += " First bytes: " + str(first_bytes.slice(0, min(8, first_bytes.size())))
	
	# Call back to main thread
	call_deferred("_on_cache_loaded", resource_id, resource, cache_path, error_msg)

func _on_cache_loaded(resource_id: String, resource: Resource, cache_path: String, error_msg: String = "") -> void:
	loading_resources.erase(resource_id)
	
	if resource:
		memory_cache[resource_id] = resource
		resource_loaded.emit(resource_id, resource)
	else:
		print("Failed to load from cache: ", resource_id, " - ", error_msg)
		print("Cache file path: ", cache_path)
		
		# Mark as failed to prevent infinite retry loops
		failed_resources[resource_id] = true
		
		# Check if this is a .res file that might not be a valid Godot resource
		if resource_id.ends_with(".tres"):
			print("Marking .res file as failed - might need preprocessor fix: ", resource_id)
			resource_failed.emit(resource_id, "Failed to load .res file: " + error_msg)
		else:
			# Cache file might be corrupted, try network
			_remove_from_cache(resource_id)
			_fetch_from_network(resource_id)

# Fetch resource from network
func _fetch_from_network(resource_id: String) -> void:
	var http_request = _get_available_http_request()
	if not http_request:
		print("No available HTTP requests, queuing: ", resource_id)
		# Could implement a queue here, for now just fail
		resource_failed.emit(resource_id, "No available HTTP requests")
		return
	
	loading_resources[resource_id] = true
	
	var url = BASE_URL + resource_id
	
	# Connect to completion signal
	if http_request.request_completed.is_connected(_on_network_request_completed):
		http_request.request_completed.disconnect(_on_network_request_completed)
	http_request.request_completed.connect(_on_network_request_completed.bind(resource_id, http_request))
	
	# Make the request
	var error = http_request.request(url)
	if error != OK:
		_return_http_request(http_request)
		loading_resources.erase(resource_id)
		resource_failed.emit(resource_id, "HTTP Request Error: " + str(error))

# Get an available HTTP request from the pool
func _get_available_http_request() -> HTTPRequest:
	if available_requests.size() > 0:
		return available_requests.pop_back()
	return null

# Return HTTP request to the pool
func _return_http_request(http_request: HTTPRequest) -> void:
	if http_request.request_completed.is_connected(_on_network_request_completed):
		http_request.request_completed.disconnect(_on_network_request_completed)
	available_requests.append(http_request)

# Get an available worker thread (round-robin)
func _get_available_worker() -> WorkerThread:
	var index = randi() % worker_threads.size()
	return worker_threads[index]

# Handle network request completion
func _on_network_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, resource_id: String, http_request: HTTPRequest) -> void:
	_return_http_request(http_request)
	loading_resources.erase(resource_id)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		failed_resources[resource_id] = true
		resource_failed.emit(resource_id, "HTTP Request Failed: " + str(result))
		return
	
	if response_code != 200:
		failed_resources[resource_id] = true
		resource_failed.emit(resource_id, "HTTP Error: " + str(response_code))
		return
	
	# Save to cache asynchronously
	var cache_path = cache_dir + resource_id
	var worker = _get_available_worker()
	worker.add_task(func(): _save_cache_worker(cache_path, body, resource_id))

func _save_cache_worker(cache_path: String, data: PackedByteArray, resource_id: String) -> void:
	# This runs in a worker thread
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	var save_success = false
	if file:
		file.store_buffer(data)
		file.close()
		save_success = true
	
	# Call back to main thread
	call_deferred("_on_cache_saved", resource_id, cache_path, save_success)

func _on_cache_saved(resource_id: String, cache_path: String, save_success: bool) -> void:
	if not save_success:
		print("Failed to save to cache: ", cache_path)
		resource_failed.emit(resource_id, "Failed to save to cache")
		return
	
	# Load the resource asynchronously
	_load_from_cache_async(resource_id, cache_path)

# Remove a resource from cache
func _remove_from_cache(resource_id: String) -> void:
	var cache_path = cache_dir + resource_id
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)
	
	if memory_cache.has(resource_id):
		memory_cache.erase(resource_id)

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

# Get statistics for debugging
func get_stats() -> Dictionary:
	return {
		"memory_cache_size": memory_cache.size(),
		"loading_resources": loading_resources.size(),
		"available_http_requests": available_requests.size(),
		"worker_threads": worker_threads.size()
	}