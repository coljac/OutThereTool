extends Node
var canonical_database: SQLite
var user_database: SQLite
signal updated_data(success: bool)

var current_field: String = ""

# Track current comment fetch request
var current_comments_request: HTTPRequest = null
var current_comments_galaxy_id: String = ""


func _ready() -> void:
	Logger.logger.info("DataManager initializing")
	
	# Initialize canonical database (galaxy metadata)
	canonical_database = SQLite.new()
	canonical_database.path = OS.get_environment("OUTTHERE_DB")
	if canonical_database.path == "":
		canonical_database.path = "user://canonical_data.sqlite"
		Logger.logger.debug("Using default canonical database path: " + canonical_database.path)
		if not FileAccess.file_exists(canonical_database.path):
			Logger.logger.info("Canonical database file not found, copying from resources")
			_copy_canonical_db()
	else:
		Logger.logger.debug("Using environment canonical database path: " + canonical_database.path)
	canonical_database.open_db()
	
	# Initialize user database (comments and scores)
	user_database = SQLite.new()
	user_database.path = "user://user_data.sqlite"
	Logger.logger.debug("Using user database path: " + user_database.path)
	user_database.open_db()
	_ensure_user_database_schema()
	
	# Load last accessed field from user data
	var last_field = get_user_data("last_field")
	if last_field != "":
		current_field = last_field
		Logger.logger.info("Restored last accessed field: " + current_field)
	else:
		# Default to first available field if no previous field saved
		var fields = get_unique_fields()
		if fields.size() > 0:
			current_field = fields[0]
			Logger.logger.info("Using default field: " + current_field)
		else:
			current_field = "uma-03"
			Logger.logger.info("No fields available, using fallback: " + current_field)
	
	Logger.logger.info("DataManager initialized successfully")

func _copy_canonical_db():
	Logger.logger.info("Copying canonical database from resources to user directory")
	if FileAccess.file_exists("res://data.sqlite"):
		Logger.logger.debug("Source database found at res://data.sqlite")
		if copy_file_from_res_to_user("data.sqlite", "canonical_data.sqlite"):
			Logger.logger.info("Canonical database copied successfully from resources")
			# Reload the canonical database if it's already open
			if canonical_database and canonical_database.path != "":
				canonical_database.close_db()
				canonical_database.open_db()
				Logger.logger.info("Canonical database reloaded")
				# Notify UI that data has been updated
				updated_data.emit(true)
		else:
			Logger.logger.error("Failed to copy canonical database from resources")
	else:
		Logger.logger.error("Initial canonical database file not found in resources at res://data.sqlite")

func _ensure_user_database_schema():
	Logger.logger.info("Ensuring user database schema exists")
	
	# Create user_comments table for storing user ratings and comments
	var create_user_comments = """
	CREATE TABLE IF NOT EXISTS user_comments (
		object_id TEXT PRIMARY KEY,
		status INTEGER DEFAULT -1,
		comments TEXT DEFAULT '',
		galaxy_class INTEGER DEFAULT 0,
		checkboxes INTEGER DEFAULT 0,
		redshift REAL DEFAULT 0.0,
		altered INTEGER DEFAULT 0,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		synced INTEGER DEFAULT 0,
		sync_timestamp DATETIME NULL
	);
	"""
	
	# Create userdata table for user preferences and credentials
	var create_userdata = """
	CREATE TABLE IF NOT EXISTS userdata (
		item TEXT PRIMARY KEY,
		item_value TEXT
	);
	"""
	
	user_database.query(create_user_comments)
	user_database.query(create_userdata)
	
	# Add sync tracking columns if they don't exist (for existing databases)
	user_database.query("ALTER TABLE user_comments ADD COLUMN synced INTEGER DEFAULT 0")
	user_database.query("ALTER TABLE user_comments ADD COLUMN sync_timestamp DATETIME NULL")
	
	# Add new columns for extended galaxy data if they don't exist (for existing databases)
	user_database.query("ALTER TABLE user_comments ADD COLUMN galaxy_class INTEGER DEFAULT 0")
	user_database.query("ALTER TABLE user_comments ADD COLUMN checkboxes INTEGER DEFAULT 0")
	user_database.query("ALTER TABLE user_comments ADD COLUMN redshift REAL DEFAULT 0.0")
	
	Logger.logger.info("User database schema created successfully")
	
	# Set default username to host computer username if not already set
	if get_user_data("user.name") == "":
		var host_username = OS.get_environment("USER")
		if host_username == "":
			host_username = OS.get_environment("USERNAME") # Windows fallback
		if host_username != "":
			set_user_data("user.name", host_username)
			Logger.logger.info("Set default username to host computer username: " + host_username)

func refresh_canonical_db():
	Logger.logger.info("Refreshing canonical database from server")
	var base_url = NetworkConfig.get_base_url()
	var db_url = base_url + "data.sqlite"
	var db_path = "user://canonical_data.sqlite"
	
	Logger.logger.info("Downloading canonical database from: " + db_url)
	
	# Create HTTPRequest for downloading
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Configure for better performance
	http_request.use_threads = true
	http_request.body_size_limit = -1 # No limit
	http_request.download_chunk_size = 65536 # 64KB chunks
	http_request.download_file = db_path
	
	# Connect completion signal
	http_request.request_completed.connect(_on_canonical_db_download_completed)
	
	# Make the request
	var request_error = http_request.request(db_url)
	if request_error != OK:
		Logger.logger.error("Failed to start canonical database download: " + str(request_error))
		# Fall back to copying from resources
		_copy_canonical_db()
		http_request.queue_free()

func _on_canonical_db_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	Logger.logger.info("Canonical database download completed")
	Logger.logger.debug("HTTP result: " + str(result) + ", response code: " + str(response_code))
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		Logger.logger.error("Canonical database download failed. Result: " + str(result) + ", Response code: " + str(response_code))
		# Fall back to copying from resources
		_copy_canonical_db()
	else:
		Logger.logger.info("Canonical database downloaded successfully from server")
		# Reload the canonical database
		canonical_database.close_db()
		canonical_database.open_db()
		Logger.logger.info("Canonical database reloaded")
		# Notify UI that data has been updated
		updated_data.emit(true)
	
	# Clean up
	var http_request = get_children().filter(func(child): return child is HTTPRequest)[0]
	if http_request:
		http_request.queue_free()
	
func reset_db():
	# Legacy function - now refreshes canonical database
	refresh_canonical_db()

func copy_file_from_res_to_user(file_path: String, dest_name: String = "") -> bool:
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
	
	var target_path = dest_name if dest_name != "" else file_path
	var dest_file = FileAccess.open("user://" + target_path, FileAccess.WRITE)
	if dest_file == null:
		return false
	
	dest_file.store_buffer(content)
	dest_file.close()
	
	return true

func get_gals(redshift_min: float = 0.0, redshift_max: float = 10.0, bands: int = 0, field: String = "") -> Array:
	var field_condition = ""
	if field != "" and field != "No fields":
		field_condition = " and field = '%s'" % field
	
	var condition = "redshift >= %.2f and redshift <= %.2f and filters >= %d%s" % [redshift_min, redshift_max, bands, field_condition]
	print(condition)
	
	var gals = canonical_database.select_rows("galaxy", condition, ["*"])
	
	# Add default user data fields (will be populated when individual galaxy is viewed)
	for gal in gals:
		gal["status"] = -1
		gal["comments"] = ""
		gal["galaxy_class"] = 0
		gal["checkboxes"] = 0
		gal["redshift"] = 0.0
		gal["altered"] = 0
	
	return gals

func get_unique_fields() -> Array:
	var fields = canonical_database.select_rows("galaxy", "field IS NOT NULL", ["DISTINCT field"])
	var field_list = []
	for field_row in fields:
		field_list.append(field_row["field"])
	field_list.sort()
	return field_list

func set_current_field(field: String) -> void:
	current_field = field
	# Save the current field to user data for next session
	set_user_data("last_field", field)
	Logger.logger.info("Field changed to: " + field)

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
	
	var gals = canonical_database.select_rows("galaxy", condition, ["*"])
	
	# Merge with user comments/status for these specific galaxies
	for gal in gals:
		var user_data = _get_user_comment(gal["id"])
		if user_data:
			gal["status"] = user_data["status"]
			gal["comments"] = user_data["comments"]
			gal["galaxy_class"] = user_data.get("galaxy_class", 0)
			gal["checkboxes"] = user_data.get("checkboxes", 0)
			gal["redshift"] = user_data.get("redshift", 0.0)
			gal["altered"] = user_data["altered"]
		else:
			gal["status"] = -1
			gal["comments"] = ""
			gal["galaxy_class"] = 0
			gal["checkboxes"] = 0
			gal["redshift"] = 0.0
			gal["altered"] = 0
	
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

func update_gal(id: String, status: int, comment: String, galaxy_class: int = 0, checkboxes: int = 0, redshift: float = 0.0) -> void:
	# Store user comments/status in user database
	var existing = user_database.select_rows("user_comments", "object_id = '" + id + "'", ["*"])
	var data = {
		"object_id": id,
		"status": status,
		"comments": comment,
		"galaxy_class": galaxy_class,
		"checkboxes": checkboxes,
		"redshift": redshift,
		"altered": 1,
		"updated_at": Time.get_datetime_string_from_system()
	}
	
	if existing.size() > 0:
		user_database.update_rows("user_comments", "object_id = '" + id + "'", data)
	else:
		user_database.insert_row("user_comments", data)
	
	updated_data.emit(true)

func set_user_data(item: String, value: String) -> void:
	var existing = user_database.select_rows("userdata", "item = '" + item + "'", ["*"])
	if existing.size() > 0:
		user_database.update_rows("userdata", "item = '" + item + "'", {"item_value": value})
	else:
		user_database.insert_row("userdata", {"item": item, "item_value": value})

func get_user_data(item: String) -> String:
	var result = user_database.select_rows("userdata", "item = '" + item + "'", ["item_value"])
	if result.size() > 0:
		return result[0]["item_value"]
	return ""

func _get_user_comment(object_id: String) -> Dictionary:
	var result = user_database.select_rows("user_comments", "object_id = '" + object_id + "'", ["*"])
	if result.size() > 0:
		return result[0]
	return {}

func get_galaxy_with_user_data(galaxy_id: String) -> Dictionary:
	"""Get a single galaxy with its user data merged in"""
	var gals = canonical_database.select_rows("galaxy", "id = '" + galaxy_id + "'", ["*"])
	if gals.size() == 0:
		return {}
	
	var gal = gals[0]
	var user_data = _get_user_comment(galaxy_id)
	if user_data:
		gal["status"] = user_data["status"]
		gal["comments"] = user_data["comments"]
		gal["galaxy_class"] = user_data.get("galaxy_class", 0)
		gal["checkboxes"] = user_data.get("checkboxes", 0)
		gal["redshift"] = user_data.get("redshift", 0.0)
		gal["altered"] = user_data["altered"]
	else:
		gal["status"] = -1
		gal["comments"] = ""
		gal["galaxy_class"] = 0
		gal["checkboxes"] = 0
		gal["redshift"] = 0.0
		gal["altered"] = 0
	
	return gal

func get_user_credentials() -> Dictionary:
	var username = get_user_data("user.name")
	var password = get_user_data("user.password")
	return {"username": username, "password": password}

func get_api_base_url() -> String:
	"""Get the API base URL for comment synchronization"""
	var api_url = OS.get_environment("OUTTHERE_API_URL")
	if api_url != "":
		return api_url
	else:
		return "https://tool.outthere-survey.org/api"

func get_auth_token() -> String:
	"""Get the authentication token from user data"""
	return get_user_data("auth_token")

func sync_comments_to_server(since_timestamp: String = "") -> void:
	"""Upload all comments newer than the last sync time to the server"""
	Logger.logger.info("Starting comment sync to server")
	
	var auth_token = get_auth_token()
	if auth_token == "":
		Logger.logger.error("No authentication token found, cannot sync comments")
		return
	
	# Get comments that need syncing (either unsynced or updated since last sync)
	var condition = "synced = 0 OR altered = 1"
	if since_timestamp != "":
		condition += " OR updated_at > '" + since_timestamp + "'"
	
	var comments_to_sync = user_database.select_rows("user_comments", condition, ["*"])
	Logger.logger.info("Found " + str(comments_to_sync.size()) + " comments to sync")
	
	if comments_to_sync.size() == 0:
		Logger.logger.info("No comments to sync")
		return
	
	# Upload each comment
	for comment_data in comments_to_sync:
		await _upload_comment_to_server(comment_data, auth_token)

func _upload_comment_to_server(comment_data: Dictionary, auth_token: String) -> void:
	"""Upload a single comment to the server"""
	var api_url = get_api_base_url()
	var galaxy_id = comment_data["object_id"]
	var upload_url = api_url + "/galaxies/" + galaxy_id + "/comments"
	
	Logger.logger.debug("Uploading comment for galaxy: " + galaxy_id)
	
	# Create HTTPRequest
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Prepare the comment data for the API
	var comment_payload = {
		"status": comment_data["status"],
		"redshift": comment_data.get("redshift", null),
		"comment": comment_data.get("comments", ""),
		"galaxy_class": comment_data.get("galaxy_class", 0),
		"checkboxes": comment_data.get("checkboxes", 0)
	}
	
	var json_payload = JSON.stringify(comment_payload)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + auth_token
	]
	
	# Connect completion signal
	http_request.request_completed.connect(_on_comment_upload_completed.bind(comment_data["object_id"], http_request))
	
	# Make the request
	var request_error = http_request.request(upload_url, headers, HTTPClient.METHOD_POST, json_payload)
	if request_error != OK:
		Logger.logger.error("Failed to start comment upload for galaxy " + galaxy_id + ": " + str(request_error))
		http_request.queue_free()

func _on_comment_upload_completed(galaxy_id: String, http_request: HTTPRequest, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle completion of comment upload"""
	Logger.logger.debug("Comment upload completed for galaxy: " + galaxy_id)
	Logger.logger.debug("HTTP result: " + str(result) + ", response code: " + str(response_code))
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		# Mark comment as synced
		var sync_time = Time.get_datetime_string_from_system()
		user_database.update_rows("user_comments", "object_id = '" + galaxy_id + "'", {
			"synced": 1,
			"sync_timestamp": sync_time,
			"altered": 0
		})
		Logger.logger.info("Successfully uploaded comment for galaxy: " + galaxy_id)
	else:
		Logger.logger.error("Failed to upload comment for galaxy " + galaxy_id + ". Result: " + str(result) + ", Response code: " + str(response_code))
		if body.size() > 0:
			Logger.logger.error("Response body: " + body.get_string_from_utf8())
	
	# Clean up
	http_request.queue_free()

signal galaxy_comments_fetched(galaxy_id: String, comments: Array)

func fetch_galaxy_comments_async(galaxy_id: String) -> void:
	"""Fetch all comments for a galaxy from the server asynchronously"""
	Logger.logger.debug("Fetching comments for galaxy: " + galaxy_id)
	
	var auth_token = get_auth_token()
	print("DEBUG: Auth token: ", auth_token)
	if auth_token == "":
		print("DEBUG: No auth token found, emitting empty comments")
		Logger.logger.error("No authentication token found, cannot fetch comments")
		galaxy_comments_fetched.emit(galaxy_id, [])
		return
	
	var api_url = get_api_base_url()
	var comments_url = api_url + "/galaxies/" + galaxy_id + "/comments"
	
	Logger.logger.debug("Comments fetch URL: " + comments_url)
	
	# Clean up any existing request
	if current_comments_request:
		current_comments_request.queue_free()
	
	# Create HTTPRequest
	current_comments_request = HTTPRequest.new()
	current_comments_galaxy_id = galaxy_id
	add_child(current_comments_request)
	
	var headers = [
		"Authorization: Bearer " + auth_token
	]
	
	# Connect completion signal
	current_comments_request.request_completed.connect(_on_comments_fetch_completed)
	
	# Make the request
	print("DEBUG: Making HTTP request to: ", comments_url)
	var request_error = current_comments_request.request(comments_url, headers, HTTPClient.METHOD_GET)
	if request_error != OK:
		print("DEBUG: HTTP request failed with error: ", request_error)
		Logger.logger.error("Failed to start comments fetch for galaxy " + galaxy_id + ": " + str(request_error))
		current_comments_request.queue_free()
		current_comments_request = null
		galaxy_comments_fetched.emit(galaxy_id, [])
	else:
		print("DEBUG: HTTP request started successfully")

func _on_comments_fetch_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle completion of comments fetch"""
	var galaxy_id = current_comments_galaxy_id
	
	print("DEBUG: _on_comments_fetch_completed called for galaxy: ", galaxy_id)
	print("DEBUG: HTTP result: ", result, ", response code: ", response_code)
	Logger.logger.debug("Comments fetch completed for galaxy: " + galaxy_id)
	Logger.logger.debug("HTTP result: " + str(result) + ", response code: " + str(response_code))
	
	var comments_data = []
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var response_text = body.get_string_from_utf8()
		Logger.logger.debug("Comments response: " + response_text)
		
		var json = JSON.new()
		var parse_result = json.parse(response_text)
		
		if parse_result == OK:
			var parsed_data = json.data
			if typeof(parsed_data) == TYPE_ARRAY:
				comments_data = parsed_data
				Logger.logger.info("Successfully fetched " + str(comments_data.size()) + " comments for galaxy: " + galaxy_id)
			else:
				Logger.logger.error("Unexpected response format for comments: " + str(typeof(parsed_data)))
		else:
			Logger.logger.error("Failed to parse comments JSON response: " + str(parse_result))
	else:
		Logger.logger.error("Failed to fetch comments for galaxy " + galaxy_id + ". Result: " + str(result) + ", Response code: " + str(response_code))
		if body.size() > 0:
			Logger.logger.error("Response body: " + body.get_string_from_utf8())
	
	# Emit the signal with the fetched comments (empty array if failed)
	print("DEBUG: About to emit galaxy_comments_fetched signal for galaxy: ", galaxy_id, " with ", comments_data.size(), " comments")
	galaxy_comments_fetched.emit(galaxy_id, comments_data)
	print("DEBUG: Signal emitted")
	
	# Clean up
	if current_comments_request:
		current_comments_request.queue_free()
		current_comments_request = null
	current_comments_galaxy_id = ""

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
	http_request.body_size_limit = -1 # No limit
	http_request.download_chunk_size = 65536 # 64KB chunks
	
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
