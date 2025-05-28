extends Node
# Global manager for OTImage settings synchronization and persistence

signal settings_changed(settings: Dictionary)

# Current global settings that can be applied to all images
var global_settings: Dictionary = {
	"black_level": 0.0,
	"white_level": 100.0,
	"scale_percent": 99.5,
	"invert_color": false,
	"color_map": 0  # ColorMap.GRAYSCALE
}

# Default settings for reset functionality
var default_settings: Dictionary = {
	"black_level": 0.0,
	"white_level": 100.0,
	"scale_percent": 99.5,
	"invert_color": false,
	"color_map": 0  # ColorMap.GRAYSCALE
}

# Flags to control behavior
var lock_settings: bool = false  # Persist settings across objects
var apply_to_all: bool = false   # Apply changes to all images
var is_updating: bool = false    # Prevent recursive updates

# Track all OTImage instances for synchronization
var tracked_images: Array[OTImage] = []

func _ready():
	# Connect to main UI for control updates
	pass

func set_lock_settings(enabled: bool) -> void:
	lock_settings = enabled

func set_apply_to_all(enabled: bool) -> void:
	apply_to_all = enabled

func reset_all_to_defaults() -> void:
	global_settings = default_settings.duplicate()
	_apply_settings_to_all_images()

func register_image(image: OTImage) -> void:
	if image not in tracked_images:
		tracked_images.append(image)
		
		# Apply current global settings if lock is enabled
		if lock_settings:
			_apply_settings_to_image(image, global_settings)
		
		# Connect to image change signals
		_connect_image_signals(image)

func unregister_image(image: OTImage) -> void:
	if image in tracked_images:
		tracked_images.erase(image)
		_disconnect_image_signals(image)

func _connect_image_signals(image: OTImage) -> void:
	# Connect to all the property setters
	if not image.is_connected("tree_exiting", _on_image_tree_exiting):
		image.tree_exiting.connect(_on_image_tree_exiting.bind(image))

func _disconnect_image_signals(image: OTImage) -> void:
	if image.is_connected("tree_exiting", _on_image_tree_exiting):
		image.tree_exiting.disconnect(_on_image_tree_exiting)

func _on_image_tree_exiting(image: OTImage) -> void:
	unregister_image(image)

func on_image_setting_changed(source_image: OTImage, setting_name: String, value) -> void:
	if is_updating:
		return
	
	# Update global settings
	global_settings[setting_name] = value
	
	# If apply_to_all is enabled, propagate to other images
	if apply_to_all:
		is_updating = true
		for image in tracked_images:
			if image != source_image and is_instance_valid(image):
				_apply_single_setting_to_image(image, setting_name, value)
		is_updating = false
	
	# Emit signal for any other listeners
	settings_changed.emit(global_settings)

func _apply_settings_to_all_images() -> void:
	is_updating = true
	for image in tracked_images:
		if is_instance_valid(image):
			_apply_settings_to_image(image, global_settings)
	is_updating = false

func _apply_settings_to_image(image: OTImage, settings: Dictionary) -> void:
	# Use the new batch method to apply all settings efficiently
	image.apply_settings_batch(settings)

func _apply_single_setting_to_image(image: OTImage, setting_name: String, value) -> void:
	# For individual setting changes (apply to all), suppress notifications to prevent loops
	image.suppress_notifications = true
	
	match setting_name:
		"black_level":
			image.black_level = value
		"white_level":
			image.white_level = value
		"scale_percent":
			image.scale_percent = value
			if image.image_data:
				image.white_level = image.get_percentile(value)
		"invert_color":
			image.invert_color = value
		"color_map":
			image.color_map = value
	
	image.suppress_notifications = false
	
	if image.image_data:
		image._make_texture()

func get_current_settings() -> Dictionary:
	return global_settings.duplicate()

func clear_tracked_images() -> void:
	# Disconnect all signals before clearing
	for image in tracked_images:
		if is_instance_valid(image):
			_disconnect_image_signals(image)
	tracked_images.clear()