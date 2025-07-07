extends Node
class_name OptimizedDownloader

## Optimized downloader for large files with minimal overhead

signal download_completed(success: bool, file_path: String)
signal download_progress(bytes_downloaded: int, total_bytes: int, speed_mbps: float)

const PROGRESS_UPDATE_INTERVAL = 2.0  # Update progress every 2 seconds instead of 0.5
const BUFFER_SIZE = 65536  # 64KB buffer for better performance

var http_request: HTTPRequest
var download_start_time: int
var last_progress_update: int
var last_bytes_downloaded: int
var current_download_path: String
var current_total_size: int
var progress_timer: Timer

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	# Configure for better performance
	http_request.use_threads = true
	http_request.body_size_limit = -1  # No limit
	http_request.download_chunk_size = BUFFER_SIZE
	
	progress_timer = Timer.new()
	add_child(progress_timer)
	progress_timer.wait_time = PROGRESS_UPDATE_INTERVAL
	progress_timer.timeout.connect(_emit_progress_update)

func download_file(url: String, save_path: String) -> bool:
	"""
	Download a file with optimized performance.
	Returns true if download started successfully.
	"""
	Logger.logger.info("Starting optimized download: " + url)
	
	current_download_path = save_path
	current_total_size = 0
	download_start_time = Time.get_ticks_msec()
	last_progress_update = download_start_time
	last_bytes_downloaded = 0
	
	# Don't use download_file property - we'll handle it manually for better control
	http_request.download_file = ""
	
	# Connect signals
	if not http_request.request_completed.is_connected(_on_request_completed):
		http_request.request_completed.connect(_on_request_completed)
	
	# Start the request
	var headers = ["Accept-Encoding: identity"]  # Disable compression for accurate progress
	var error = http_request.request(url, headers)
	
	if error != OK:
		Logger.logger.error("Failed to start download: " + str(error))
		return false
	
	# Start progress monitoring
	progress_timer.start()
	
	return true

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	"""Handle download completion."""
	progress_timer.stop()
	
	var success = result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	
	if success and body.size() > 0:
		# Write the file in one operation
		var file = FileAccess.open(current_download_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			
			var download_time = (Time.get_ticks_msec() - download_start_time) / 1000.0
			var size_mb = body.size() / (1024.0 * 1024.0)
			var speed_mbps = size_mb / download_time if download_time > 0 else 0
			
			Logger.logger.info("Download completed: %.1f MB in %.1f seconds (%.1f MB/s)" % [size_mb, download_time, speed_mbps])
		else:
			success = false
			Logger.logger.error("Failed to write downloaded file")
	
	download_completed.emit(success, current_download_path)

func _emit_progress_update():
	"""Emit progress update with minimal overhead."""
	# This is called less frequently to reduce overhead
	if current_download_path == "":
		return
	
	# For body-based downloads, we can't get accurate progress during download
	# So we just indicate that download is in progress
	var current_time = Time.get_ticks_msec()
	var elapsed_seconds = (current_time - download_start_time) / 1000.0
	
	download_progress.emit(0, current_total_size, 0.0)

func cancel_download():
	"""Cancel the current download."""
	http_request.cancel_request()
	progress_timer.stop()
	current_download_path = ""