extends Node
var database: SQLite
signal updated_data(success: bool)

var current_field: String = "uma-03"


func _ready() -> void:
	Logger.logger.info("DataManager initializing")
	database = SQLite.new()
	database.path = OS.get_environment("OUTTHERE_DB")
	if database.path == "":
		database.path = "user://data.sqlite"
		Logger.logger.debug("Using default database path: " + database.path)
		if not FileAccess.file_exists(database.path):
			Logger.logger.info("Database file not found, copying from resources")
			_copy_db()
	else:
		Logger.logger.debug("Using environment database path: " + database.path)
	database.open_db()
	Logger.logger.info("DataManager initialized successfully")

func _copy_db():
	Logger.logger.info("Copying database from resources to user directory")
	if FileAccess.file_exists("res://data.sqlite"):
		Logger.logger.debug("Source database found at res://data.sqlite")
		if copy_file_from_res_to_user("data.sqlite"):
			Logger.logger.info("Database copied successfully from resources")
		else:
			Logger.logger.error("Failed to copy database from resources")
	else:
		Logger.logger.error("Initial database file not found in resources at res://data.sqlite")

	
func reset_db():
	# Remove db at user://data.sqlite and copy from res://data.sqlite
	# if FileAccess.file_exists("user://data.sqlite"):
		# FileAccess.remove("user://data.sqlite")
	_copy_db()

func copy_file_from_res_to_user(file_path: String) -> bool:
	var source_file = FileAccess.open("res://" + file_path, FileAccess.READ)
	if source_file == null:
		return false
	
	var content = source_file.get_buffer(source_file.get_length())
	source_file.close()
	
	var dir = DirAccess.open("user://")
	if dir == null:
		return false
	
	# Create directories if needed
	var directory_path = file_path.get_base_dir()
	if directory_path != "":
		dir.make_dir_recursive(directory_path)
	
	var dest_file = FileAccess.open("user://" + file_path, FileAccess.WRITE)
	if dest_file == null:
		return false
	
	dest_file.store_buffer(content)
	dest_file.close()
	
	return true

func get_gals(redshift_min: float = 0.0, redshift_max: float = 10.0, bands: int = 0, field: String = "") -> Array:
	var field_condition = ""
	if field != "" and field != "No fields":
		field_condition = " and field = '%s'" % field
	
	var condition = "status > -1 and redshift >= %.2f and redshift <= %.2f and filters >= %d%s" % [redshift_min, redshift_max, bands, field_condition]
	print(condition)
	
	var gals = database.select_rows("galaxy", condition, ["*"])
	return gals

func get_unique_fields() -> Array:
	var fields = database.select_rows("galaxy", "field IS NOT NULL", ["DISTINCT field"])
	var field_list = []
	for field_row in fields:
		field_list.append(field_row["FIELD"])
	field_list.sort()
	return field_list

func set_current_field(field: String) -> void:
	current_field = field

func get_current_field() -> String:
	return current_field

func get_gals_by_ids(object_ids: Array) -> Array:
	if object_ids.size() == 0:
		return []
	
	# Create condition for multiple IDs
	var id_conditions = []
	for id in object_ids:
		id_conditions.append("id = '" + str(id) + "'")
	var condition = "(" + " OR ".join(id_conditions) + ")"
	
	var gals = database.select_rows("galaxy", condition, ["*"])
	
	# Create a dictionary to preserve order of input IDs
	var id_to_gal = {}
	for gal in gals:
		id_to_gal[gal["id"]] = gal
	
	# Return objects in the same order as input IDs, skip missing ones
	var ordered_gals = []
	for id in object_ids:
		if id_to_gal.has(str(id)):
			ordered_gals.append(id_to_gal[str(id)])
	
	return ordered_gals

func update_gal(id: String, status: int, comment: String) -> void:
	database.update_rows("galaxy", "id = '" + id + "'", {"status": status, "comments": comment, "altered": 1})
	updated_data.emit(true)

func set_user_data(item: String, value: String) -> void:
	var existing = database.select_rows("userdata", "item = '" + item + "'", ["*"])
	if existing.size() > 0:
		database.update_rows("userdata", "item = '" + item + "'", {"item_value": value})
	else:
		database.insert_row("userdata", {"item": item, "item_value": value})

func get_user_data(item: String) -> String:
	var result = database.select_rows("userdata", "item = '" + item + "'", ["item_value"])
	if result.size() > 0:
		return result[0]["ITEM_VALUE"]
	return ""

func get_user_credentials() -> Dictionary:
	var username = get_user_data("user.name")
	var password = get_user_data("user.password")
	return {"username": username, "password": password}

func pre_cache_field(field: String, progress: CacheProgress) -> void:
	Logger.logger.info("Starting pre-cache operation for field: " + field)
	Logger.logger.debug("Pre-cache strategy: attempting bulk field download first, fallback to individual galaxy caching")
	
	# Try to download and unzip the entire field
	# The download_and_unzip_field method will handle completion asynchronously
	var download_started = download_and_unzip_field(field, progress)
	
	if not download_started:
		# If download couldn't start, fall back to individual galaxy caching immediately
		Logger.logger.warning("Field download could not start for " + field + ", falling back to individual galaxy caching")
		_fallback_to_individual_caching(field, progress)
	else:
		Logger.logger.info("Field download initiated successfully for: " + field)
	
	# Note: If download started successfully, the zip_download_completed handler
	# will take care of extraction or fallback to individual caching

# Store current download context
var current_download_field: String = ""
var current_download_progress: CacheProgress = null
var current_download_http_request: HTTPRequest = null
var current_download_zip_path: String = ""
var current_download_total_size: int = 0
var download_progress_timer: Timer = null


func download_and_unzip_field(field: String, progress: CacheProgress) -> bool:
	"""
	Initiates download of a field zip file from the server.
	Returns true if download started successfully, false otherwise.
	"""
	var base_url = NetworkConfig.get_base_url()
	var zip_url = base_url + field + ".zip"
	var cache_dir = "user://cache/"
	var zip_path = cache_dir + field + ".zip"
	
	Logger.logger.info("Initiating field zip download for: " + field)
	Logger.logger.debug("Download URL: " + zip_url)
	Logger.logger.debug("Target cache path: " + zip_path)
	progress.update(5.0, "Starting download: " + field)
	
	# Store context for completion handler
	current_download_field = field
	current_download_progress = progress
	current_download_zip_path = zip_path
	current_download_total_size = 0
	
	# Create HTTPRequest for downloading
	var http_request = HTTPRequest.new()
	add_child(http_request)
	current_download_http_request = http_request
	
	# Configure for better performance
	http_request.use_threads = true
	http_request.body_size_limit = -1  # No limit
	http_request.download_chunk_size = 65536  # 64KB chunks
	
	# Set up the request
	http_request.download_file = zip_path
	
	# Connect completion signal
	http_request.request_completed.connect(zip_download_completed)
	
	# Make the request with headers to disable compression for accurate progress
	var headers = ["Accept-Encoding: identity"]
	var request_error = http_request.request(zip_url, headers)
	if request_error != OK:
		Logger.logger.error("Failed to start HTTP request for field " + field + ": " + str(request_error))
		_cleanup_download_request()
		return false
	
	# Start progress tracking timer
	_start_download_progress_tracking()
	Logger.logger.debug("HTTP request started successfully, progress tracking enabled")
	
	progress.update(10.0, "Connecting...")
	return true


func _start_download_progress_tracking() -> void:
	"""Start timer to track download progress."""
	if download_progress_timer:
		download_progress_timer.queue_free()
	
	download_progress_timer = Timer.new()
	add_child(download_progress_timer)
	download_progress_timer.wait_time = 2.0 # Update every 2 seconds to reduce overhead
	download_progress_timer.timeout.connect(_update_download_progress)
	download_progress_timer.start()


func _update_download_progress() -> void:
	"""Update download progress based on file size."""
	if not current_download_progress or current_download_zip_path == "":
		return
	
	# Use DirAccess to get file size without opening the file
	var dir = DirAccess.open(current_download_zip_path.get_base_dir())
	if not dir:
		return
	
	var file_name = current_download_zip_path.get_file()
	if not dir.file_exists(file_name):
		return
	
	# This is more efficient than opening the file
	var current_size = FileAccess.get_file_as_bytes(current_download_zip_path).size()
	
	if current_size == 0:
		return
	
	# If we don't know total size yet, just show current size
	if current_download_total_size == 0:
		var size_mb = current_size / (1024.0 * 1024.0)
		current_download_progress.update(15.0, "Downloading: %.1f MB" % size_mb)
		Logger.logger.debug("Download progress (unknown total): %.1f MB" % size_mb)
	else:
		# Calculate progress percentage (10% to 60% range for download)
		var progress_percent = (float(current_size) / current_download_total_size) * 50.0 + 10.0
		progress_percent = min(progress_percent, 60.0) # Cap at 60%
		
		var current_mb = current_size / (1024.0 * 1024.0)
		var total_mb = current_download_total_size / (1024.0 * 1024.0)
		
		current_download_progress.update(progress_percent, "Downloading: %.1f MB / %.1f MB" % [current_mb, total_mb])
		Logger.logger.debug("Download progress: %.1f%% (%.1f MB / %.1f MB)" % [progress_percent, current_mb, total_mb])


func _stop_download_progress_tracking() -> void:
	"""Stop the download progress timer."""
	if download_progress_timer:
		download_progress_timer.queue_free()
		download_progress_timer = null


func zip_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""
	Handles completion of field zip download and initiates extraction.
	"""
	var field = current_download_field
	var progress = current_download_progress
	var cache_dir = "user://cache/"
	var zip_path = cache_dir + field + ".zip"
	
	Logger.logger.info("Field zip download completed for: " + field)
	Logger.logger.debug("HTTP result: " + str(result) + ", response code: " + str(response_code))
	
	# Stop progress tracking
	_stop_download_progress_tracking()
	
	# Extract total size from headers if available
	for header in headers:
		if header.to_lower().begins_with("content-length:"):
			var size_str = header.split(":")[1].strip_edges()
			current_download_total_size = size_str.to_int()
			Logger.logger.debug("Content-Length header found: " + str(current_download_total_size) + " bytes")
			break
	
	# Clean up HTTP request
	_cleanup_download_request()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		Logger.logger.error("Field zip download failed for " + field + ". Result: " + str(result) + ", Response code: " + str(response_code))
		# Clean up partial download
		if FileAccess.file_exists(zip_path):
			Logger.logger.debug("Removing partial download file: " + zip_path)
			DirAccess.remove_absolute(zip_path)
		
		# Fall back to individual galaxy caching
		Logger.logger.info("Falling back to individual galaxy caching due to download failure")
		_fallback_to_individual_caching(field, progress)
		return
	
	# Show final download size
	if FileAccess.file_exists(zip_path):
		var file = FileAccess.open(zip_path, FileAccess.READ)
		if file:
			var final_size = file.get_length()
			var size_mb = final_size / (1024.0 * 1024.0)
			file.close()
			Logger.logger.info("Field zip download completed successfully for " + field + ": %.1f MB" % size_mb)
			progress.update(60.0, "Downloaded %.1f MB, extracting..." % size_mb)
		else:
			Logger.logger.warning("Field zip download completed but cannot read file size for: " + field)
			progress.update(60.0, "Download complete, extracting...")
	else:
		Logger.logger.warning("Field zip download completed but file not found at: " + zip_path)
		progress.update(60.0, "Download complete, extracting...")
	
	# Extract the zip file
	Logger.logger.info("Starting zip extraction for field: " + field)
	_extract_field_zip(zip_path, cache_dir, progress)

func _cleanup_download_request() -> void:
	"""Clean up the current download HTTP request."""
	Logger.logger.debug("Cleaning up download request for field: " + current_download_field)
	# Stop progress tracking
	_stop_download_progress_tracking()
	
	if current_download_http_request:
		if current_download_http_request.request_completed.is_connected(zip_download_completed):
			current_download_http_request.request_completed.disconnect(zip_download_completed)
		current_download_http_request.queue_free()
		current_download_http_request = null
	
	current_download_field = ""
	current_download_progress = null
	current_download_zip_path = ""
	current_download_total_size = 0

func _extract_field_zip(zip_path: String, extract_to: String, progress: CacheProgress) -> void:
	"""
	Extracts the field zip file asynchronously.
	"""
	Logger.logger.info("Extracting field zip: " + zip_path + " to: " + extract_to)
	var extract_success = await extract_zip_file(zip_path, extract_to, progress)
	
	# Clean up zip file after extraction
	if FileAccess.file_exists(zip_path):
		Logger.logger.debug("Cleaning up zip file after extraction: " + zip_path)
		DirAccess.remove_absolute(zip_path)
	
	if extract_success:
		progress.update(100.0, "Field cached successfully")
		Logger.logger.info("Successfully downloaded and cached field: " + current_download_field)
	else:
		Logger.logger.error("Failed to extract field zip: " + zip_path)
		Logger.logger.info("Falling back to individual galaxy caching due to extraction failure")
		# Fall back to individual galaxy caching
		_fallback_to_individual_caching(current_download_field, progress)

func _fallback_to_individual_caching(field: String, progress: CacheProgress) -> void:
	"""
	Falls back to individual galaxy caching when field download fails.
	"""
	Logger.logger.info("Initiating fallback to individual galaxy caching for field: " + field)
	var gals = get_gals(0.0, 10.0, 0, field)
	
	if gals.size() == 0:
		Logger.logger.warning("No galaxies found to pre-cache for field: " + field)
		progress.update(100.0, "No galaxies found")
		return
	
	Logger.logger.info("Found " + str(gals.size()) + " galaxies to cache individually for field: " + field)
	_cache_individual_galaxies(gals, progress)

func _cache_individual_galaxies(gals: Array, progress: CacheProgress) -> void:
	"""
	Caches individual galaxies with progress updates.
	"""
	Logger.logger.info("Starting individual galaxy caching for " + str(gals.size()) + " galaxies")
	for i in range(gals.size()):
		var gal = gals[i]
		var progress_value = (float(i) + 1) / gals.size() * 100.0
		progress.update(progress_value, "Caching galaxy: " + gal["id"])
		Logger.logger.debug("Caching galaxy " + str(i + 1) + "/" + str(gals.size()) + ": " + gal["id"])
		await get_tree().process_frame # Yield to allow UI updates
		# Individual galaxy caching logic would go here
		# print("Caching galaxy ID: ", gal["id"])

	Logger.logger.info("Completed individual caching of " + str(gals.size()) + " galaxies")

func extract_zip_file(zip_path: String, extract_to: String, progress: CacheProgress) -> bool:
	"""
	Extracts a zip file to the specified directory.
	Returns true if successful, false otherwise.
	"""
	Logger.logger.info("Starting zip extraction: " + zip_path + " to: " + extract_to)
	
	# Check if zip file exists
	if not FileAccess.file_exists(zip_path):
		Logger.logger.error("Zip file does not exist: " + zip_path)
		return false
	
	# Create a FileAccess to read the zip
	var zip_file = FileAccess.open(zip_path, FileAccess.READ)
	if not zip_file:
		Logger.logger.error("Cannot open zip file: " + zip_path)
		return false
	
	#var zip_data = zip_file.get_buffer(zip_file.get_length())
	#zip_file.close()
	
	# Use Godot's built-in ZIPReader
	var zip_reader = ZIPReader.new()
	var open_result = zip_reader.open(zip_path)
	
	if open_result != OK:
		Logger.logger.error("Failed to open zip data: " + str(open_result))
		return false
	
	var files = zip_reader.get_files()
	Logger.logger.info("Found " + str(files.size()) + " files in zip archive")
	
	if files.size() == 0:
		Logger.logger.warning("Zip archive is empty")
		zip_reader.close()
		return false
	
	# Extract each file
	var extracted_count = 0
	for i in range(files.size()):
		var file_path = files[i]
		var file_data = zip_reader.read_file(file_path)
		
		if file_data.size() == 0:
			Logger.logger.warning("Empty file in zip archive: " + file_path)
			continue
		
		# Create full path for extraction
		var full_extract_path = extract_to + file_path
		
		# Create directories if needed
		var dir_path = full_extract_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			Logger.logger.debug("Creating directory: " + dir_path)
			DirAccess.make_dir_recursive_absolute(dir_path)
		
		# Write the file
		var output_file = FileAccess.open(full_extract_path, FileAccess.WRITE)
		if output_file:
			output_file.store_buffer(file_data)
			output_file.close()
			extracted_count += 1
			Logger.logger.debug("Extracted file " + str(i + 1) + "/" + str(files.size()) + ": " + file_path + " (" + str(file_data.size()) + " bytes)")
			
			# Update progress
			var extract_progress = 60.0 + (float(i + 1) / files.size()) * 35.0
			progress.update(extract_progress, "Extracting: " + file_path.get_file())
			await get_tree().process_frame
		else:
			Logger.logger.error("Failed to create output file: " + full_extract_path)
	
	zip_reader.close()
	
	Logger.logger.info("Zip extraction completed: " + str(extracted_count) + "/" + str(files.size()) + " files extracted successfully")
	return extracted_count > 0
