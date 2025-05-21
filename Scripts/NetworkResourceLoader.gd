extends Node
class_name NetworkResourceLoader

# Base URL for your resource server
const BASE_URL = "https://outthere.s3.amazonawms.com/your-resource-server.com/resources/"

# Signal emitted when a resource is loaded
signal resource_loaded(resource_id, resource)
signal resource_failed(resource_id, error)

# Cache for loaded resources
var _resource_cache = {}

# Load a resource by ID
func load_resource(resource_id: String, resource_type: String = "") -> void:
    # Check if resource is already cached
    if _resource_cache.has(resource_id):
        emit_signal("resource_loaded", resource_id, _resource_cache[resource_id])
        return
    
    # Create URL from ID
    var url = BASE_URL + resource_id
    
    # Create HTTP request
    var http_request = HTTPRequest.new()
    add_child(http_request)
    
    # Connect to the completed signal
    http_request.connect("request_completed", self, "_on_request_completed", [resource_id, resource_type, http_request])
    
    # Make the request
    var error = http_request.request(url)
    if error != OK:
        emit_signal("resource_failed", resource_id, "HTTP Request Error: " + str(error))
        http_request.queue_free()

# Handle the completed HTTP request
func _on_request_completed(result, response_code, headers, body, resource_id, resource_type, request_node):
    # Clean up the request node
    request_node.queue_free()
    
    # Check for errors
    if result != HTTPRequest.RESULT_SUCCESS:
        emit_signal("resource_failed", resource_id, "HTTP Request Failed: " + str(result))
        return
    
    if response_code != 200:
        emit_signal("resource_failed", resource_id, "HTTP Error: " + str(response_code))
        return
    
    # Process the resource based on type
    var resource
    
    # Determine file extension from headers or resource_id
    var file_extension = _get_file_extension(headers, resource_id)
    
    match file_extension:
        "png", "jpg", "jpeg", "webp":
            resource = _load_image(body)
        "ogg", "mp3", "wav":
            resource = _load_audio(body)
        "tres", "res":
            resource = _load_resource_file(body)
        "tscn":
            resource = _load_scene(body)
        _:
            # Try to load as specified resource type
            if resource_type != "":
                resource = _load_custom_resource(body, resource_type)
            else:
                emit_signal("resource_failed", resource_id, "Unknown resource type")
                return
    
    if resource:
        # Cache the resource
        _resource_cache[resource_id] = resource
        emit_signal("resource_loaded", resource_id, resource)
    else:
        emit_signal("resource_failed", resource_id, "Failed to load resource")

# Helper function to get file extension from headers or resource_id
func _get_file_extension(headers, resource_id):
    # Try to get content type from headers
    for header in headers:
        if header.to_lower().begins_with("content-type:"):
            var content_type = header.split(":")[1].strip_edges()
            # Map content type to extension
            if "image/png" in content_type:
                return "png"
            elif "image/jpeg" in content_type:
                return "jpg"
            elif "audio/ogg" in content_type:
                return "ogg"
            # Add more mappings as needed
    
    # Fallback to resource_id extension
    if "." in resource_id:
        return resource_id.get_extension().to_lower()
    
    return ""

# Load image from raw data
func _load_image(body):
    var image = Image.new()
    var error = image.load_png_from_buffer(body)
    
    if error != OK:
        error = image.load_jpg_from_buffer(body)
    
    if error != OK:
        error = image.load_webp_from_buffer(body)
    
    if error != OK:
        return null
    
    var texture = ImageTexture.new()
    texture.create_from_image(image)
    return texture

# Load audio from raw data
func _load_audio(body):
    # Save to temporary file
    var tmp_path = "user://temp_audio." + str(randi())
    var file = File.new()
    file.open(tmp_path, File.WRITE)
    file.store_buffer(body)
    file.close()
    
    # Load from file
    var stream
    if ResourceLoader.exists(tmp_path):
        stream = ResourceLoader.load(tmp_path)
    
    # Clean up temp file
    var dir = Directory.new()
    dir.remove(tmp_path)
    
    return stream

# Load a resource file
func _load_resource_file(body):
    # Save to temporary file
    var tmp_path = "user://temp_res." + str(randi())
    var file = File.new()
    file.open(tmp_path, File.WRITE)
    file.store_buffer(body)
    file.close()
    
    # Load from file
    var resource
    if ResourceLoader.exists(tmp_path):
        resource = ResourceLoader.load(tmp_path)
    
    # Clean up temp file
    var dir = Directory.new()
    dir.remove(tmp_path)
    
    return resource

# Load a scene
func _load_scene(body):
    # Similar to _load_resource_file but for scenes
    return _load_resource_file(body)

# Load a custom resource type
func _load_custom_resource(body, resource_type):
    # Implementation depends on the specific resource type
    # This is a placeholder
    return null

# Clear the cache for a specific resource or all resources
func clear_cache(resource_id = null):
    if resource_id:
        if _resource_cache.has(resource_id):
            _resource_cache.erase(resource_id)
    else:
        _resource_cache.clear()

