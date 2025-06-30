extends Node
var database: SQLite
signal updated_data(success: bool)

var current_field: String = "uma-03"


func _ready() -> void:
	database = SQLite.new()
	database.path = OS.get_environment("OUTTHERE_DB")
	if database.path == "":
		database.path = "user://data.sqlite"
		if not FileAccess.file_exists(database.path):
			_copy_db()
	database.open_db()

func _copy_db():
	if FileAccess.file_exists("res://data.sqlite"):
		if copy_file_from_res_to_user("data.sqlite"):
			print("Database reset successfully.")
		else:
			print("Failed to reset database.")
	else:
		print("Initial database file not found in resources.")

	
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
	print("Pre-caching data for field: ", field)
	
	# Try to download and unzip the entire field
	# The download_and_unzip_field method will handle completion asynchronously
	var download_started = download_and_unzip_field(field, progress)
	
	if not download_started:
		# If download couldn't start, fall back to individual galaxy caching immediately
		print("Field download could not start, falling back to individual galaxy caching for: ", field)
		_fallback_to_individual_caching(field, progress)
	
	# Note: If download started successfully, the zip_download_completed handler
	# will take care of extraction or fallback to individual caching

# Store current download context
var current_download_field: String = ""
var current_download_progress: CacheProgress = null
var current_download_http_request: HTTPRequest = null

func download_and_unzip_field(field: String, progress: CacheProgress) -> bool:
	"""
	Initiates download of a field zip file from the server.
	Returns true if download started successfully, false otherwise.
	"""
	var base_url = NetworkConfig.get_base_url()
	var zip_url = base_url + field + ".zip"
	var cache_dir = "user://cache/"
	var zip_path = cache_dir + field + ".zip"
	
	print("Attempting to download field zip: ", zip_url)
	progress.update(10.0, "Downloading field: " + field)
	
	# Store context for completion handler
	current_download_field = field
	current_download_progress = progress
	
	# Create HTTPRequest for downloading
	var http_request = HTTPRequest.new()
	add_child(http_request)
	current_download_http_request = http_request
	
	# Set up the request
	http_request.download_file = zip_path
	
	# Connect completion signal
	http_request.request_completed.connect(zip_download_completed)
	
	# Make the request
	var request_error = http_request.request(zip_url)
	if request_error != OK:
		print("Failed to start HTTP request: ", request_error)
		_cleanup_download_request()
		return false
	
	progress.update(30.0, "Downloading...")
	return true

func zip_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""
	Handles completion of field zip download and initiates extraction.
	"""
	var field = current_download_field
	var progress = current_download_progress
	var cache_dir = "user://cache/"
	var zip_path = cache_dir + field + ".zip"
	
	# Clean up HTTP request
	_cleanup_download_request()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Failed to download field zip. Result: ", result, " Response code: ", response_code)
		# Clean up partial download
		if FileAccess.file_exists(zip_path):
			DirAccess.remove_absolute(zip_path)
		
		# Fall back to individual galaxy caching
		_fallback_to_individual_caching(field, progress)
		return
	
	print("Field zip download completed successfully")
	progress.update(60.0, "Download complete, extracting...")
	
	# Extract the zip file
	_extract_field_zip(zip_path, cache_dir, progress)

func _cleanup_download_request() -> void:
	"""Clean up the current download HTTP request."""
	if current_download_http_request:
		if current_download_http_request.request_completed.is_connected(zip_download_completed):
			current_download_http_request.request_completed.disconnect(zip_download_completed)
		current_download_http_request.queue_free()
		current_download_http_request = null
	
	current_download_field = ""
	current_download_progress = null

func _extract_field_zip(zip_path: String, extract_to: String, progress: CacheProgress) -> void:
	"""
	Extracts the field zip file asynchronously.
	"""
	var extract_success = await extract_zip_file(zip_path, extract_to, progress)
	
	# Clean up zip file after extraction
	if FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)
	
	if extract_success:
		progress.update(100.0, "Field cached successfully")
		print("Successfully downloaded and cached field: ", current_download_field)
	else:
		print("Failed to extract field zip: ", zip_path)
		# Fall back to individual galaxy caching
		_fallback_to_individual_caching(current_download_field, progress)

func _fallback_to_individual_caching(field: String, progress: CacheProgress) -> void:
	"""
	Falls back to individual galaxy caching when field download fails.
	"""
	print("Field download failed, falling back to individual galaxy caching for: ", field)
	var gals = get_gals(0.0, 10.0, 0, field)
	
	if gals.size() == 0:
		print("No galaxies found to pre-cache for field %s" % field)
		progress.update(100.0, "No galaxies found")
		return
	
	_cache_individual_galaxies(gals, progress)

func _cache_individual_galaxies(gals: Array, progress: CacheProgress) -> void:
	"""
	Caches individual galaxies with progress updates.
	"""
	for i in range(gals.size()):
		var gal = gals[i]
		var progress_value = (float(i) + 1) / gals.size() * 100.0
		progress.update(progress_value, "Caching galaxy: " + gal["id"])
		await get_tree().process_frame # Yield to allow UI updates
		# Individual galaxy caching logic would go here
		# print("Caching galaxy ID: ", gal["id"])

	print("Pre-cached %d galaxies individually" % gals.size())

func extract_zip_file(zip_path: String, extract_to: String, progress: CacheProgress) -> bool:
	"""
	Extracts a zip file to the specified directory.
	Returns true if successful, false otherwise.
	"""
	print("Extracting zip file: ", zip_path, " to: ", extract_to)
	
	# Check if zip file exists
	if not FileAccess.file_exists(zip_path):
		print("Zip file does not exist: ", zip_path)
		return false
	
	# Create a FileAccess to read the zip
	var zip_file = FileAccess.open(zip_path, FileAccess.READ)
	if not zip_file:
		print("Cannot open zip file: ", zip_path)
		return false
	
	#var zip_data = zip_file.get_buffer(zip_file.get_length())
	#zip_file.close()
	
	# Use Godot's built-in ZIPReader
	var zip_reader = ZIPReader.new()
	var open_result = zip_reader.open(zip_path)
	
	if open_result != OK:
		print("Failed to open zip data: ", open_result)
		return false
	
	var files = zip_reader.get_files()
	print("Found ", files.size(), " files in zip")
	
	if files.size() == 0:
		zip_reader.close()
		return false
	
	# Extract each file
	var extracted_count = 0
	for i in range(files.size()):
		var file_path = files[i]
		var file_data = zip_reader.read_file(file_path)
		
		if file_data.size() == 0:
			print("Warning: Empty file in zip: ", file_path)
			continue
		
		# Create full path for extraction
		var full_extract_path = extract_to + file_path
		
		# Create directories if needed
		var dir_path = full_extract_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		
		# Write the file
		var output_file = FileAccess.open(full_extract_path, FileAccess.WRITE)
		if output_file:
			output_file.store_buffer(file_data)
			output_file.close()
			extracted_count += 1
			
			# Update progress
			var extract_progress = 60.0 + (float(i + 1) / files.size()) * 35.0
			progress.update(extract_progress, "Extracting: " + file_path.get_file())
			await get_tree().process_frame
		else:
			print("Failed to create output file: ", full_extract_path)
	
	zip_reader.close()
	
	print("Successfully extracted ", extracted_count, " files from ", files.size(), " total files")
	return extracted_count > 0
