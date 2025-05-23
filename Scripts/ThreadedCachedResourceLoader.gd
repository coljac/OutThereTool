extends Node
class_name ThreadedCachedResourceLoader

# Base URL for resources
const BASE_URL = "https://outthere.s3.us-east-1.amazonaws.com/processed/"
const MAX_CONCURRENT_REQUESTS = 4

# Cache directory in user space
var cache_dir: String = "user://cache/"

# In-memory cache for quick access
var memory_cache = {}

# Currently loading resources to prevent duplicate requests
var loading_resources = {}

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
	# Check in-memory cache first
	if memory_cache.has(resource_id):
		print("Loading from memory cache: ", resource_id)
		resource_loaded.emit(resource_id, memory_cache[resource_id])
		return
	
	# Check if already loading
	if loading_resources.has(resource_id):
		print("Already loading: ", resource_id)
		return
	
	# Check file cache asynchronously
	var cache_path = cache_dir + resource_id
	if FileAccess.file_exists(cache_path):
		print("Loading from file cache: ", resource_id)
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
	var resource = ResourceLoader.load(cache_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	
	# Call back to main thread
	call_deferred("_on_cache_loaded", resource_id, resource, cache_path)

func _on_cache_loaded(resource_id: String, resource: Resource, cache_path: String) -> void:
	loading_resources.erase(resource_id)
	
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
		resource_failed.emit(resource_id, "HTTP Request Failed: " + str(result))
		return
	
	if response_code != 200:
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