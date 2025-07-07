extends Node
class_name StreamingDownloader

## High-performance streaming downloader that processes data in chunks
## This avoids loading the entire file into memory and provides accurate progress

signal download_completed(success: bool, file_path: String)
signal download_progress(bytes_downloaded: int, total_bytes: int, speed_mbps: float)

const CHUNK_SIZE = 1048576  # 1MB chunks for processing
const PROGRESS_UPDATE_INTERVAL = 1.0  # Update every second

var http_client: HTTPClient
var download_thread: Thread
var should_cancel: bool = false
var current_url: String
var current_save_path: String
var download_start_time: int
var last_progress_time: int
var last_bytes_count: int

func download_file(url: String, save_path: String) -> bool:
	"""
	Start a high-performance streaming download.
	Returns true if download started successfully.
	"""
	if download_thread and download_thread.is_started():
		Logger.logger.error("Download already in progress")
		return false
	
	current_url = url
	current_save_path = save_path
	should_cancel = false
	
	# Start download in a separate thread
	download_thread = Thread.new()
	var error = download_thread.start(_download_thread_func)
	
	if error != OK:
		Logger.logger.error("Failed to start download thread: " + str(error))
		return false
	
	Logger.logger.info("Started streaming download: " + url)
	return true

func _download_thread_func():
	"""Thread function that performs the actual download."""
	var success = false
	var error_message = ""
	
	# Parse URL
	var regex = RegEx.new()
	regex.compile("^(https?)://([^/]+)(/.*)$")
	var result = regex.search(current_url)
	
	if not result:
		error_message = "Invalid URL format"
		call_deferred("_download_complete", false, error_message)
		return
	
	var protocol = result.get_string(1)
	var host = result.get_string(2)
	var path = result.get_string(3)
	var port = 443 if protocol == "https" else 80
	
	# Extract port if specified
	if ":" in host:
		var parts = host.split(":")
		host = parts[0]
		port = int(parts[1])
	
	# Create HTTP client
	http_client = HTTPClient.new()
	
	# Connect to host
	var err = http_client.connect_to_host(host, port, protocol == "https")
	if err != OK:
		error_message = "Failed to connect: " + str(err)
		call_deferred("_download_complete", false, error_message)
		return
	
	# Wait for connection
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		OS.delay_msec(10)
		if should_cancel:
			call_deferred("_download_complete", false, "Cancelled")
			return
	
	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		error_message = "Connection failed with status: " + str(http_client.get_status())
		call_deferred("_download_complete", false, error_message)
		return
	
	# Make request
	var headers = ["Accept-Encoding: identity", "User-Agent: Godot/4.0"]
	err = http_client.request(HTTPClient.METHOD_GET, path, headers)
	if err != OK:
		error_message = "Request failed: " + str(err)
		call_deferred("_download_complete", false, error_message)
		return
	
	# Wait for response
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		http_client.poll()
		OS.delay_msec(10)
		if should_cancel:
			call_deferred("_download_complete", false, "Cancelled")
			return
	
	if not http_client.has_response():
		error_message = "No response from server"
		call_deferred("_download_complete", false, error_message)
		return
	
	# Get response code and headers
	var response_code = http_client.get_response_code()
	if response_code != 200:
		error_message = "HTTP error: " + str(response_code)
		call_deferred("_download_complete", false, error_message)
		return
	
	# Get content length
	var total_size = 0
	var response_headers = http_client.get_response_headers()
	for header in response_headers:
		if header.to_lower().begins_with("content-length:"):
			total_size = int(header.split(":")[1].strip_edges())
			break
	
	# Open file for writing
	var file = FileAccess.open(current_save_path, FileAccess.WRITE)
	if not file:
		error_message = "Cannot create file: " + current_save_path
		call_deferred("_download_complete", false, error_message)
		return
	
	# Start timing
	download_start_time = Time.get_ticks_msec()
	last_progress_time = download_start_time
	last_bytes_count = 0
	
	# Download body
	var bytes_downloaded = 0
	var body_buffer = PackedByteArray()
	
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		
		if should_cancel:
			file.close()
			DirAccess.remove_absolute(current_save_path)
			call_deferred("_download_complete", false, "Cancelled")
			return
		
		var chunk = http_client.read_response_body_chunk()
		if chunk.size() > 0:
			file.store_buffer(chunk)
			bytes_downloaded += chunk.size()
			
			# Update progress
			var current_time = Time.get_ticks_msec()
			if current_time - last_progress_time >= PROGRESS_UPDATE_INTERVAL * 1000:
				var elapsed = (current_time - download_start_time) / 1000.0
				var speed = (bytes_downloaded - last_bytes_count) / (1024.0 * 1024.0) / PROGRESS_UPDATE_INTERVAL
				
				call_deferred("_emit_progress", bytes_downloaded, total_size, speed)
				
				last_progress_time = current_time
				last_bytes_count = bytes_downloaded
		else:
			OS.delay_msec(10)  # Small delay to avoid busy waiting
	
	file.close()
	
	# Final progress update
	var total_time = (Time.get_ticks_msec() - download_start_time) / 1000.0
	var avg_speed = (bytes_downloaded / (1024.0 * 1024.0)) / total_time if total_time > 0 else 0
	
	Logger.logger.info("Download completed: %.1f MB in %.1f seconds (%.1f MB/s avg)" % [
		bytes_downloaded / (1024.0 * 1024.0),
		total_time,
		avg_speed
	])
	
	call_deferred("_download_complete", true, "")

func _emit_progress(bytes: int, total: int, speed: float):
	"""Emit progress signal on main thread."""
	download_progress.emit(bytes, total, speed)

func _download_complete(success: bool, error: String):
	"""Handle download completion on main thread."""
	if not success:
		Logger.logger.error("Download failed: " + error)
	
	download_completed.emit(success, current_save_path)
	
	# Clean up
	if download_thread and download_thread.is_started():
		download_thread.wait_to_finish()
	download_thread = null
	http_client = null

func cancel_download():
	"""Cancel the current download."""
	should_cancel = true