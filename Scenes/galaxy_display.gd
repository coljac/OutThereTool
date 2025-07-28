extends Control
# signal next()
# TODO: Fits images not the right size up top
# TODO: Scaling
# TODO: COlor map
# TODO: Themes/dark mode

# Feedback:
	# NIRCAM?
	# Beams show
	# Seg map
	# Overlay a template - eazy
	# Comtam model unsubtracted

#@export var object_id: String = "uma-03_03269" #2122"
#var path = "./data/Good_example/"
@export var object_id: String = "uma-03_02484" # 2122"
var path = "./data/"

@onready var redshift_label: Label = $CanvasLayer/RedshiftLabel
@onready var tab_toolbar = $VBoxContainer/TabToolbar
@onready var spec_1d = get_node("VBoxContainer/MarginContainer5/Spec1d") as PlotDisplay
@onready var pofz = get_node("VBoxContainer/MarginContainer6/VBoxContainer/Redshift") as PlotDisplay
# @onready var spec2d = $VBoxContainer/MarginContainer4/Spec2Ds/Spec2D_1 as FitsImage
@onready var spec2d: VBoxContainer = %Spec2DContainer
@onready var slider = $VBoxContainer/MarginContainer6/VBoxContainer/MarginContainer/HSlider
var redshift = 1.0
@onready var otimg = preload("res://Scenes/ot_image.tscn")

var asset_helper: AssetHelper
# = AssetHelper.new()

# Leader key functionality
var leader_mode_active: bool = false
var leader_timer: Timer
var leader_timeout: float = 2.0
# Visibility flags for 1D plot series
var show_flux: bool = true
var show_bestfit: bool = true
var show_errors: bool = true
var show_contam: bool = true

# Store series indices for toggling
var flux_series: Array = []
var bestfit_series: Array = []
var error_series: Array = []
var contam_series: Array = []

# Store different sets of 2D spectrum images
var science_images: Array = [] # Regular image_data OTImages
var contam_images: Array = [] # contam_data OTImages
var model_images: Array = [] # model_data OTImages
var is_showing_science: bool = true # Toggle state

# Spectral line data loaded from JSON
var spectral_line_data: Dictionary = {}
var line_colors: Dictionary = {}

# Wavelength ranges for each filter in microns
const FILTER_WAVELENGTH_RANGES = {
	"F115W": {"x_min": 0.9, "x_max": 1.3},
	"F150W": {"x_min": 1.3, "x_max": 1.7},
	"F200W": {"x_min": 1.7, "x_max": 2.3}
}

# Function to determine optimal wavelength range based on available filters
func _get_wavelength_range_for_filters(available_filters: Array) -> Dictionary:
	if available_filters.is_empty():
		return {"x_min": 0.9, "x_max": 2.3} # Default full range
	
	var min_wavelength = INF
	var max_wavelength = - INF
	
	for filter_name in available_filters:
		if FILTER_WAVELENGTH_RANGES.has(filter_name):
			var range = FILTER_WAVELENGTH_RANGES[filter_name]
			min_wavelength = min(min_wavelength, range.x_min)
			max_wavelength = max(max_wavelength, range.x_max)
	
	return {"x_min": min_wavelength, "x_max": max_wavelength}

func set_object_id(new_id: String) -> void:
	object_id = new_id
	# Reload the object with the new ID
	$CanvasLayer/RedshiftLabel.text = ""
	if is_inside_tree():
		load_object()
	
	
# Flag to prevent multiple loads
var _is_loading = false

func _ready():
	# Load spectral line data from JSON
	_load_spectral_line_data()
	
	# Connect to the tab toolbar signals
	if tab_toolbar:
		tab_toolbar.zoom_in_pressed.connect(_on_zoom_in_pressed)
		tab_toolbar.zoom_out_pressed.connect(_on_zoom_out_pressed)
	set_process_input(true)
	$CanvasLayer/RedshiftLabel.text = ""
	
	# Initialize leader key timer
	leader_timer = Timer.new()
	leader_timer.wait_time = leader_timeout
	leader_timer.one_shot = true
	leader_timer.timeout.connect(_on_leader_timeout)
	add_child(leader_timer)
	
	# Connect the aligned_displayer to the plot_display
	var aligned_container = %Spec2DContainer
	for child in aligned_container.get_children():
		var aligned_displayer = child as AlignedDisplayer
		if aligned_displayer:
			aligned_displayer.add_to_group("spec2ds")
			aligned_displayer.plot_display_path = $VBoxContainer/MarginContainer5/Spec1d.get_path()
		# if child.name == "Spec2D_1":
			# %Spec2Ds = child
			# break

	# var aligned_displayer = %Spec2Ds
	# aligned_displayer.plot_display_path = $VBoxContainer/MarginContainer5/Spec1d.get_path()
	
	# Enable crosshair for the 1D spectrum plot
	spec_1d.show_crosshair = true
	
	# Enable cursor line in the aligned displayer
	# aligned_displayer.show_cursor_line = true
	# aligned_displayer.cursor_line_color = Color(1, 0, 0, 0.7) # Semi-transparent red
	# aligned_displayer.cursor_line_width = 2.0
	
	# Load the object with a slight delay to ensure all nodes are ready
	call_deferred("load_object")
	# load_object()
	for n in get_tree().get_nodes_in_group("spec2ds"): # .call_deferred("position_textures")
		n.call_deferred("position_textures")
	# %Spec2Ds.call_deferred("position_textures")

func _exit_tree() -> void:
	print_debug("Exiting tree")
	$CanvasLayer/RedshiftLabel.text = ""
	
	# Clean up leader timer
	if leader_timer:
		leader_timer.queue_free()
		leader_timer = null
	
	# Clean up asset helper
	if asset_helper:
		asset_helper.cleanup_connections()
		asset_helper.queue_free()
		asset_helper = null


func _unhandled_input(event: InputEvent) -> void:
	# Handle leader key input first
	if _handle_leader_key_input(event):
		get_viewport().set_input_as_handled()
		return
	
	# Handle leader key activation
	if event.is_action_pressed("leader_pressed"):
		Logger.logger.debug("Leader key pressed - activating leader mode")
		leader_mode_active = true
		leader_timer.start()
		get_viewport().set_input_as_handled()
		return
	
	if event.is_action_pressed("flag_bad"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("flag_good"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("flag_ok"):
		get_viewport().set_input_as_handled()
	
# func _unhandled_input(event: InputEvent) -> void:
# 	if Input.is_action_just_pressed("flag_bad"):
# 		print("Flag bad")
	
func oned_zoomed():
	toggle_lines(false)
	toggle_lines(true)


func set_redshift(z: float) -> void:
	$CanvasLayer/RedshiftLabel.text = ""
	if z == redshift:
		return
	redshift = z
	pofz.constant_lines = []
	pofz.add_constant_line(z, true, Color.RED, 2.0, true)
	toggle_lines(false)
	toggle_lines(true)
	redshift_label.text = "z = " + "%.*f" % [3, z]
	
	
#func _process(delta: float) -> void:
	#load_object()
	
func load_object() -> void:
	if not is_inside_tree():
		return
	if object_id == "":
		return
		
	# Reset loading state for new object (don't check _is_loading to prevent stuckness)
	_is_loading = true
	Logger.logger.info("GalaxyDisplay: Loading object: " + object_id)
	
	# Clean up existing asset helper
	if asset_helper:
		Logger.logger.debug("GalaxyDisplay: Cleaning up existing asset helper")
		asset_helper.cleanup_connections()
		asset_helper.queue_free()
		asset_helper = null
	
	# Create new asset helper
	asset_helper = AssetHelper.new()
	add_child(asset_helper)
	
	# Connect to asset helper signals
	asset_helper.object_loaded.connect(_on_object_loaded)
	asset_helper.resource_ready.connect(_on_resource_ready)
	
	# Start loading the object
	Logger.logger.debug("GalaxyDisplay: Starting asset helper load for: " + object_id)
	asset_helper.set_object(object_id)

func _on_object_loaded(success: bool) -> void:
	if not success:
		Logger.logger.error("GalaxyDisplay: Failed to load object: " + object_id)
		_is_loading = false
		return
	
	Logger.logger.info("GalaxyDisplay: Object loaded successfully: " + object_id)
	
	# Initial UI setup
	get_node("VBoxContainer/MarginContainer/Label").text = object_id
	redshift_label.text = ""
	
	# Clear any existing data
	if pofz:
		pofz.clear_series()
	if spec_1d:
		spec_1d.clear_series()
		# Clear series tracking arrays
		flux_series.clear()
		bestfit_series.clear()
		error_series.clear()
		contam_series.clear()
		# Reset zoom to default when loading new object
		spec_1d.reset_zoom()
	
	# Check if all resources are already cached - if so, load synchronously
	if _all_resources_cached():
		Logger.logger.info("GalaxyDisplay: All resources cached, loading synchronously for: " + object_id)
		_load_all_cached_resources_sync()
		_finalize_loading()
	else:
		Logger.logger.info("GalaxyDisplay: Some resources not cached, loading asynchronously for: " + object_id)
		# Fall back to async loading
		asset_helper.load_all_resources()
		_try_load_cached_resources()

func _on_resource_ready(resource_name: String) -> void:
	# A resource has been loaded, try to update the display
	Logger.logger.debug("GalaxyDisplay: Resource ready: " + resource_name)
	# Only update if this resource belongs to current object
	if resource_name.begins_with(object_id):
		Logger.logger.debug("GalaxyDisplay: Updating display for resource: " + resource_name)
		_update_single_resource(resource_name)

func _update_single_resource(resource_name: String) -> void:
	if not asset_helper or not asset_helper.manifest:
		return
	
	# Update only the specific resource that was loaded
	if resource_name.find("redshift") != -1:
		var pz = asset_helper.get_pz()
		if pz:
			_load_redshift_data(pz)
	elif resource_name.find("1d_") != -1:
		_try_update_1d_spectra()
	elif resource_name.find("direct_") != -1:
		_try_update_direct_images()
	elif resource_name.find("2d_") != -1:
		_try_update_2d_spectra()

func _try_load_cached_resources() -> void:
	if not asset_helper or not asset_helper.manifest:
		return
	
	# Try to load redshift data
	var pz = asset_helper.get_pz()
	if pz:
		_load_redshift_data(pz)
	
	_try_update_1d_spectra()
	_try_update_direct_images()
	_try_update_2d_spectra()

func _try_update_1d_spectra() -> void:
	# Try to load 1D spectrum
	var oned_spec = asset_helper.get_1d_spectrum(true)
	if oned_spec.size() > 0:
		_load_1d_spectrum(oned_spec)

func _try_update_2d_spectra() -> void:
	# Try to load 2D spectra
	var data2d = asset_helper.get_2d_spectra()
	if data2d.size() > 0:
		_load_2d_spectra(data2d)

func _try_update_direct_images() -> void:
	# Try to load direct images
	var directs = asset_helper.get_directs()
	if directs.size() > 0:
		_load_direct_images(directs)

func _load_redshift_data(pz: Resource) -> void:
	if not pz or not ("log_pdf" in pz and "z_grid" in pz):
		return
	
	var logp = pz.log_pdf
	var peaks = asset_helper.peak_finding(logp, 50)
	
	# REDSHIFT
	var series = asset_helper.zip_arr([Array(pz.z_grid), logp])
	pofz.add_series(series, Color(0.2, 0.4, 0.8), 2.0, false, 3.0)
	var z_maxes = [] as Array[Vector2]
	var max_peak = -1.0
	for peak in peaks:
		z_maxes.append(
			Vector2(pz.z_grid[peak['x']], float(peak['max']))
		)
		if peak['max'] > max_peak:
			redshift = pz.z_grid[peak['x']]
	slider.value = redshift
	pofz.add_series(
		z_maxes, Color(1.0, 0.0, 0.0), 0.0, true, 7.0
	)

func _load_1d_spectrum(oned_spec: Dictionary) -> void:
	var xx = 0.2
	var max_flux = 0.0
	var min_flux = 0.0
	var first_data = true
	
	# Collect available filters to determine wavelength range
	var available_filters = []
	for f in oned_spec:
		available_filters.append(f)
	
	# Determine wavelength range based on available filters
	var wavelength_range = _get_wavelength_range_for_filters(available_filters)
	if Logger and Logger.logger:
		Logger.logger.info("GalaxyDisplay: Setting wavelength range based on filters " + str(available_filters) + ": " + str(wavelength_range.x_min) + "-" + str(wavelength_range.x_max) + " μm")
	else:
		print("GalaxyDisplay: Setting wavelength range based on filters " + str(available_filters) + ": " + str(wavelength_range.x_min) + "-" + str(wavelength_range.x_max) + " μm")
	
	for f in oned_spec:
		var data = oned_spec[f]
		if "max" in data:
			max_flux = max(max_flux, data["max"])
		if "min" in data:
			if first_data:
				min_flux = data["min"]
				first_data = false
			else:
				min_flux = min(min_flux, data["min"])
		
		# Add flux series (without errors) and track index
		var flux_index = spec_1d.add_series(data["fluxes"], Color(0.4 + xx, xx, 0.8), 2.0, false, 3.0, [], [], Color.TRANSPARENT, 1.0, 5.0, true)
		flux_series.append(flux_index)
		
		# Add error bars as separate series and track index
		if data.has("err") and data["err"].size() > 0:
			var error_index = spec_1d.add_series(data["fluxes"], Color.TRANSPARENT, 0.0, false, 3.0, [], data["err"], Color(1.0, 0.0, 0.0), 1.0, 5.0, true)
			error_series.append(error_index)
		
		# Add bestfit series and track index
		var bestfit_index = spec_1d.add_series(data["bestfit"], Color(0.0, 1.0, 0.0, 0.5), 2.0, false, 3.0, [], [], Color.TRANSPARENT, 1.0, 5.0, true)
		bestfit_series.append(bestfit_index)
		
		# Add contam series and track index
		var contam_index = spec_1d.add_series(data["contam"], Color(0.3, 1.0, 1.0, 0.5), 2.0, false, 3.0, [], [], Color.TRANSPARENT, 1.0, 5.0, true)
		contam_series.append(contam_index)
		
		xx += 0.2
	
	if max_flux > 0:
		# Set min value to 1.05 * min_value to accommodate negative values
		var y_min = min_flux * 1.05 if min_flux < 0 else min_flux * 0.95
		# First set original limits to establish baseline using filter-based wavelength range
		%Spec1d.set_limits(wavelength_range.x_min, wavelength_range.x_max, y_min, max_flux, true)
		# Then set limits again without marking as original to ensure adaptive tick spacing is applied
		%Spec1d.set_limits(wavelength_range.x_min, wavelength_range.x_max, y_min, max_flux, false)

func _load_2d_spectra(data2d: Dictionary) -> void:
	# Clear existing spectra
	var aligned = %Spec2Ds1
	
	# Clear existing rows in the aligned displayer BEFORE freeing children
	aligned.rows.clear()
	aligned.row_heights.clear()

	aligned.free_children()
	
	# Clear our image arrays
	science_images.clear()
	contam_images.clear()
	model_images.clear()
	
	# Create all image types but only add science images to aligned displayer initially
	var pa_index = 0
	for pa in data2d.keys():
		for f in ['F115W', 'F150W', 'F200W']:
			if f not in data2d[pa]:
				continue
			
			# Create science image (regular image_data)
			var spec_display: OTImage = _create_spectrum_image(data2d[pa][f], "image_data")
			if spec_display:
				science_images.append(spec_display)
				%Spec2Ds1.add_spectrum(spec_display, pa_index)
				%Spec2Ds1.set_label(0, "PA 318°")
				
			# For blank PA (""), also create contamination and model images (but don't add to displayer yet)
			if pa == "":
				# Create contamination image
				var contam_display: OTImage = _create_spectrum_image(data2d[pa][f], "contam_data")
				if contam_display:
					print("Created contam image for filter: ", f)
					contam_images.append(contam_display)
				else:
					print("Failed to create contam image for filter: ", f)
					
				# Create model image
				var model_display: OTImage = _create_spectrum_image(data2d[pa][f], "model_data")
				if model_display:
					print("Created model image for filter: ", f)
					model_images.append(model_display)
				else:
					print("Failed to create model image for filter: ", f)

		pa_index += 1
	
	# Reset to science mode
	is_showing_science = true
	
	# Position all textures after adding all spectra
	%Spec2Ds1.position_textures()

# Helper function to create a spectrum image from a resource using specific data type
func _create_spectrum_image(resource: Resource, data_type: String) -> OTImage:
	if not resource or not (data_type in resource):
		print("Resource missing or no ", data_type, " field")
		return null
	
	# Check if the requested data exists and has content
	var data_array = resource.get(data_type)
	if not data_array or data_array.size() == 0:
		print(data_type, " exists but is empty or null")
		return null
	
	print("Successfully creating image for ", data_type, " with ", data_array.size(), " elements")
	print("Scaling info: ", resource.scaling if "scaling" in resource else "no scaling")
	print("Dimensions: ", resource.width, "x", resource.height, " filter: ", resource.filter_name if "filter_name" in resource else "unknown")
	
	# Create a new resource with the specified data type as image_data
	var modified_resource = resource.duplicate()
	modified_resource.image_data = data_array
	
	# Fix dimensions for contam/model data which may differ from science image
	if data_type != "image_data":
		# Use the proper dimensions stored in the resource
		if data_type == "contam_data" and "contam_width" in resource and "contam_height" in resource:
			modified_resource.width = resource.contam_width
			modified_resource.height = resource.contam_height
			print("Using stored contam dimensions: ", modified_resource.width, "x", modified_resource.height)
		elif data_type == "model_data" and "model_width" in resource and "model_height" in resource:
			modified_resource.width = resource.model_width
			modified_resource.height = resource.model_height
			print("Using stored model dimensions: ", modified_resource.width, "x", modified_resource.height)
		else:
			# Fallback: calculate dimensions from data array size
			var total_pixels = data_array.size()
			var science_aspect_ratio = float(resource.width) / float(resource.height)
			
			var new_height = sqrt(total_pixels / science_aspect_ratio)
			var new_width = total_pixels / new_height
			
			modified_resource.width = int(new_width)
			modified_resource.height = int(new_height)
			
			print("Calculated dimensions for ", data_type, ": ", modified_resource.width, "x", modified_resource.height, " (was ", resource.width, "x", resource.height, ")")
	
	var spec_display: OTImage = otimg.instantiate()
	if spec_display:
		spec_display.color_map = OTImage.ColorMap.GRAYSCALE
		spec_display.is_2d_spectrum = true
		spec_display.res = modified_resource
		spec_display._load_object()
		spec_display.hide_label()
		spec_display.visible = true
	
	return spec_display

func _load_direct_images(directs: Dictionary) -> void:
	# Hide all direct image containers first to handle missing bands
	var all_filters = ["F115W", "F150W", "F200W"]
	for filt in all_filters:
		var container_name = "VBoxContainer/MarginContainer3/Imaging/IC%s" % filt
		var container_node = get_node_or_null(container_name)
		if container_node:
			container_node.visible = false
	
	# Hide segmap by default
	var segmap_node = %SegMap
	if segmap_node:
		segmap_node.visible = false
	
	# Show and load only available direct images
	for filt in directs:
		var direct = directs[filt]
		if direct:
			# Show the container
			var container_name = "VBoxContainer/MarginContainer3/Imaging/IC%s" % filt
			var container_node = get_node_or_null(container_name)
			if container_node:
				container_node.visible = true
			
			# Load the direct image
			var node_name = "VBoxContainer/MarginContainer3/Imaging/IC%s/Direct%s" % [filt, filt]
			var direct_node = get_node_or_null(node_name) as OTImage
			if direct_node:
				direct_node.res = direct
				direct_node._load_object()
				direct_node._set_scale_pc(99.5)
				direct_node.visible = true
				direct_node.set_label(filt)
				
				# Handle segmap for F200W
				if filt == "F200W":
					if segmap_node:
						segmap_node.res = direct
						segmap_node.segmap = true
						segmap_node.visible = true
						segmap_node._load_object()
						segmap_node.set_label("SegMap")

func _check_loading_complete() -> void:
	# Check if we have loaded the basic required resources
	var pz = asset_helper.get_pz()
	var oned_spec = asset_helper.get_1d_spectrum(true)
	
	# Only complete if we actually have the required resources AND we're still loading the right object
	if pz and oned_spec.size() > 0 and _is_loading and asset_helper.current_object_id == object_id:
		print("Async loading complete for: ", object_id)
		_finalize_loading()

func preload_next_object(next_object_id: String) -> void:
	# Preload resources for the next object in background
	Logger.logger.info("GalaxyDisplay: Preloading next object: " + next_object_id)
	if asset_helper:
		asset_helper.preload_next_object(next_object_id)

func get_performance_stats() -> Dictionary:
	if asset_helper:
		return asset_helper.get_performance_stats()
	return {}

# Check if all required resources are already in memory cache
func _all_resources_cached() -> bool:
	if not asset_helper or not asset_helper.manifest:
		return false
	
	var loader = asset_helper.loader
	var manifest = asset_helper.manifest
	
	# Check redshift
	if "redshift_path" in manifest:
		var resource_id = asset_helper.extract_resource_id(manifest.redshift_path)
		if not loader.memory_cache.has(resource_id):
			return false
	
	# Check 1D spectra
	if "spectrum_1d_paths" in manifest:
		for filt in manifest.spectrum_1d_paths:
			var resource_id = asset_helper.extract_resource_id(manifest.spectrum_1d_paths[filt])
			if not loader.memory_cache.has(resource_id):
				return false
	
	# Check direct images
	if "direct_image_paths" in manifest:
		for filt in manifest.direct_image_paths:
			var resource_id = asset_helper.extract_resource_id(manifest.direct_image_paths[filt])
			if not loader.memory_cache.has(resource_id):
				return false
	
	# Check 2D spectra
	if "spectrum_2d_paths_by_pa" in manifest:
		for pa in manifest.spectrum_2d_paths_by_pa:
			for filt in manifest.spectrum_2d_paths_by_pa[pa]:
				var resource_id = asset_helper.extract_resource_id(manifest.spectrum_2d_paths_by_pa[pa][filt])
				if not loader.memory_cache.has(resource_id):
					return false
	
	return true

# Load all cached resources synchronously (no async calls)
func _load_all_cached_resources_sync() -> void:
	var start_time = Time.get_ticks_msec()
	Logger.logger.info("GalaxyDisplay: Starting synchronous loading of cached resources for: " + object_id)
	
	# Load redshift data
	var pz = asset_helper.get_pz()
	if pz:
		Logger.logger.debug("GalaxyDisplay: Loading redshift data from cache")
		_load_redshift_data(pz)
	
	# Load 1D spectrum
	var oned_spec = asset_helper.get_1d_spectrum(true)
	if oned_spec.size() > 0:
		Logger.logger.debug("GalaxyDisplay: Loading 1D spectrum data from cache (" + str(oned_spec.size()) + " filters)")
		_load_1d_spectrum(oned_spec)
	
	# Load 2D spectra
	var data2d = asset_helper.get_2d_spectra()
	if data2d.size() > 0:
		Logger.logger.debug("GalaxyDisplay: Loading 2D spectra from cache (" + str(data2d.size()) + " position angles)")
		_load_2d_spectra(data2d)
	
	# Load direct images
	var directs = asset_helper.get_directs()
	if directs.size() > 0:
		Logger.logger.debug("GalaxyDisplay: Loading direct images from cache (" + str(directs.size()) + " filters)")
		_load_direct_images(directs)
	
	var load_time = Time.get_ticks_msec() - start_time
	Logger.logger.info("GalaxyDisplay: Synchronous loading completed in " + str(load_time) + "ms for: " + object_id)

# Finalize loading (called after sync or async loading is complete)
func _finalize_loading() -> void:
	Logger.logger.info("GalaxyDisplay: Finalizing loading for: " + object_id)
	_is_loading = false
	set_redshift(redshift)
	call_deferred("oned_zoomed")
	
	# Apply locked image settings if enabled
	# var main_ui = get_tree().current_scene
	# if main_ui and main_ui.locked and main_ui.image_settings.size() > 0:
	# 	main_ui.image_settings_changed(main_ui.image_settings)

# func _unhandled_input(event: InputEvent) -> void:
# 	if Input.is_action_just_pressed("flag_bad"):
# 		print("Flag bad")
	
		
func _load_spectral_line_data():
	"""Load spectral line data from JSON file, copying from resources if needed"""
	var user_file_path = "user://spectral_lines.json"
	var resource_file_path = "res://spectral_lines.json"
	
	# Check if user file exists, if not copy from resources
	if not FileAccess.file_exists(user_file_path):
		Logger.logger.info("Spectral lines file not found in user directory, copying from resources")
		if FileAccess.file_exists(resource_file_path):
			# Get DataManager instance to use its copy function
			var data_manager = get_node("/root/DataManager")
			if data_manager and data_manager.copy_file_from_res_to_user("spectral_lines.json"):
				Logger.logger.info("Spectral lines file copied successfully from resources")
			else:
				Logger.logger.error("Failed to copy spectral lines file from resources")
				_load_default_spectral_lines()
				return
		else:
			Logger.logger.error("Spectral lines file not found in resources")
			_load_default_spectral_lines()
			return
	
	# Load the JSON file
	var file = FileAccess.open(user_file_path, FileAccess.READ)
	if file == null:
		Logger.logger.error("Failed to open spectral lines file: " + user_file_path)
		_load_default_spectral_lines()
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		Logger.logger.error("Failed to parse spectral lines JSON: " + json.get_error_message())
		_load_default_spectral_lines()
		return
	
	var data = json.data
	if not data.has("lines") or not data.has("line_colors"):
		Logger.logger.error("Invalid spectral lines JSON structure")
		_load_default_spectral_lines()
		return
	
	# Convert line_colors from arrays to Color objects
	line_colors.clear()
	for color_key in data.line_colors:
		var color_array = data.line_colors[color_key]
		if color_array.size() >= 3:
			var alpha = color_array[3] if color_array.size() > 3 else 1.0
			line_colors[int(color_key)] = Color(color_array[0], color_array[1], color_array[2], alpha)
	
	spectral_line_data = data.lines
	Logger.logger.info("Loaded " + str(spectral_line_data.size()) + " spectral lines from JSON")

func _load_default_spectral_lines():
	"""Fallback to hardcoded spectral line data if JSON loading fails"""
	Logger.logger.info("Loading default hardcoded spectral line data")
	line_colors = {1: Color.RED, 2: Color.GREEN, 6: Color.BLUE, 7: Color.YELLOW}
	spectral_line_data = {
		"Lyα": {"wl": 1215.6709, "color": 7, "shortcut": "l"},
		"Lyβ": {"wl": 1025.7222, "color": 2, "shortcut": ""},
		"Lyγ": {"wl": 972.5367, "color": 1, "shortcut": ""},
		"Lyδ": {"wl": 949.743, "color": 1, "shortcut": ""},
		"Lyε": {"wl": 937.8034, "color": 1, "shortcut": ""},
		"Lyman Break": {"wl": 911.753, "color": 7, "shortcut": ""},
		"Hα": {"wl": 6564.633, "color": 7, "shortcut": "a"},
		"Hβ": {"wl": 4862.688, "color": 7, "shortcut": "b"},
		"Hγ": {"wl": 4341.682, "color": 2, "shortcut": ""},
		"Hδ": {"wl": 4102.897, "color": 1, "shortcut": ""},
		"H7": {"wl": 3971.195, "color": 1, "shortcut": ""},
		"H8": {"wl": 3890.151, "color": 2, "shortcut": ""},
		"H9": {"wl": 3836.47, "color": 2, "shortcut": ""},
		"H10": {"wl": 3798.98, "color": 2, "shortcut": ""},
		"H11": {"wl": 3771.7, "color": 1, "shortcut": ""},
		"Paα": {"wl": 18756.1, "color": 7, "shortcut": ""},
		"Paβ": {"wl": 12821.6, "color": 7, "shortcut": ""},
		"Paγ": {"wl": 10941.1, "color": 1, "shortcut": ""},
		"Paδ": {"wl": 10052.1, "color": 1, "shortcut": ""},
		"Paε": {"wl": 9548.6, "color": 1, "shortcut": ""},
		"Pa10": {"wl": 9231.5, "color": 1, "shortcut": ""},
		"Pa11": {"wl": 9017.4, "color": 1, "shortcut": ""},
		"Pa12": {"wl": 8865.2, "color": 1, "shortcut": ""},
		"Brα": {"wl": 40522.6, "color": 1, "shortcut": ""},
		"Brβ": {"wl": 26258.7, "color": 1, "shortcut": ""},
		"Brγ": {"wl": 21661.2, "color": 7, "shortcut": ""},
		"Brδ": {"wl": 19450.9, "color": 1, "shortcut": ""},
		"Brε": {"wl": 18179.1, "color": 1, "shortcut": ""},
		"Br10": {"wl": 17366.9, "color": 1, "shortcut": ""},
		"Br11": {"wl": 16811.1, "color": 1, "shortcut": ""},
		"Br12": {"wl": 16411.7, "color": 1, "shortcut": ""},
		"Pfβ": {"wl": 46537.8, "color": 1, "shortcut": ""},
		"Pfγ": {"wl": 37405.6, "color": 1, "shortcut": ""},
		"Pfδ": {"wl": 32969.9, "color": 1, "shortcut": ""},
		"Pfε": {"wl": 30392.0, "color": 1, "shortcut": ""},
		"Pf11": {"wl": 28730.0, "color": 1, "shortcut": ""},
		"Pf12": {"wl": 27582.7, "color": 1, "shortcut": ""},
		"Pf13": {"wl": 26751.3, "color": 1, "shortcut": ""},
		"Pf14": {"wl": 26126.5, "color": 1, "shortcut": ""},
		"He I 3889": {"wl": 3889.751, "color": 2, "shortcut": ""},
		"He I 5877": {"wl": 5877.243, "color": 1, "shortcut": ""},
		"He I 6680": {"wl": 6679.996, "color": 1, "shortcut": ""},
		"He I 7067": {"wl": 7067.125, "color": 1, "shortcut": ""},
		"He I 10831": {"wl": 10832.057, "color": 1, "shortcut": ""},
		"He I 10832": {"wl": 10833.306, "color": 1, "shortcut": ""},
		"He II 1640": {"wl": 1640.4, "color": 2, "shortcut": ""},
		"He II 4687": {"wl": 4687.3, "color": 1, "shortcut": ""},
		"[O II] 3727": {"wl": 3727.092, "color": 7, "shortcut": "o"},
		"[O II] 3729": {"wl": 3729.875, "color": 7, "shortcut": ""},
		"[O III] 4960": {"wl": 4960.30, "color": 7, "shortcut": ""},
		"[O III] 5008": {"wl": 5008.24, "color": 7, "shortcut": "O"},
		"[O III] 4363": {"wl": 4363.44, "color": 1, "shortcut": ""},
		"[S II] 6718": {"wl": 6718.294, "color": 1, "shortcut": ""},
		"[S II] 6732": {"wl": 6732.673, "color": 1, "shortcut": ""},
		"[S III] 9071": {"wl": 9071.1, "color": 1, "shortcut": ""},
		"[S III] 9533": {"wl": 9533.2, "color": 1, "shortcut": ""},
		"[N II] 6549": {"wl": 6549.86, "color": 1, "shortcut": ""},
		"[N II] 6585": {"wl": 6585.27, "color": 1, "shortcut": ""},
		"N V 1239": {"wl": 1238.81, "color": 1, "shortcut": ""},
		"N V 1243": {"wl": 1242.80, "color": 1, "shortcut": ""},
		"C III] 1907": {"wl": 1906.683, "color": 1, "shortcut": ""},
		"C III] 1909": {"wl": 1908.734, "color": 7, "shortcut": ""},
		"C IV 1548": {"wl": 1548.187, "color": 7, "shortcut": "c"},
		"C IV 1551": {"wl": 1550.770, "color": 7, "shortcut": ""},
		"CO(2–0)": {"wl": 22935.00, "color": 1, "shortcut": ""},
		"CO(3–1)": {"wl": 23227.00, "color": 1, "shortcut": ""},
		"CO(4–2)": {"wl": 23525.00, "color": 1, "shortcut": ""},
		"CO(5–3)": {"wl": 23829.00, "color": 1, "shortcut": ""},
		"CO(6–4)": {"wl": 24127.00, "color": 1, "shortcut": ""},
		"CO(7–5)": {"wl": 24425.00, "color": 1, "shortcut": ""},
		"Mg II 2796": {"wl": 2796.35, "color": 6, "shortcut": "m"},
		"Mg II 2804": {"wl": 2803.53, "color": 6, "shortcut": ""},
		"[Ne III] 3870": {"wl": 3870.16, "color": 1, "shortcut": ""},
		"[Fe II] 12570": {"wl": 12570.0, "color": 1, "shortcut": ""},
		"[Fe II] 16440": {"wl": 16440.0, "color": 7, "shortcut": ""},
		"PAH 3.3μm": {"wl": 32900.00, "color": 1, "shortcut": ""}
	}

func toggle_lines(on: bool = true):
	if on:
		# Use loaded spectral line data from JSON
		var y_off = 0
		for ln in spectral_line_data:
			var line_info = spectral_line_data[ln]
			var wl = line_info["wl"]
			var color_group = int(line_info['color'])
			var lambda = wl / 10000
			lambda = lambda * (1 + redshift)
			
			# Get color from loaded line_colors dictionary
			var line_color = line_colors.get(color_group, Color.WHITE)
			spec_1d.add_constant_line(lambda, true, line_color, 2.0, false)
			
			# Add annotation
			var yval = (spec_1d.y_max * 0.9) + (y_off * spec_1d.y_max * 0.05)
			spec_1d.add_annotation(Vector2(lambda, yval), ln, Color.WHEAT, 12)
			y_off += 1
			y_off = y_off % 4
	else:
		spec_1d.constant_lines = []
		spec_1d.annotations = []

func _on_h_slider_value_changed(value: float) -> void:
	set_redshift(value)


func _on_zoom_in_pressed() -> void:
	# Handle zoom in
	print("Zoom in pressed")

func _on_zoom_out_pressed() -> void:
	# Handle zoom out
	print("Zoom out pressed")

func _on_redshift_plot_left_clicked(position: Vector2) -> void:
	set_redshift(position.x)

# Toggle methods for 1D plot series
func toggle_flux_visibility(visible: bool) -> void:
	show_flux = visible
	for index in flux_series:
		spec_1d.set_series_visible(index, visible)

func toggle_bestfit_visibility(visible: bool) -> void:
	show_bestfit = visible
	for index in bestfit_series:
		spec_1d.set_series_visible(index, visible)

func toggle_errors_visibility(visible: bool) -> void:
	show_errors = visible
	for index in error_series:
		spec_1d.set_series_visible(index, visible)

func toggle_contam_visibility(visible: bool) -> void:
	show_contam = visible
	for index in contam_series:
		spec_1d.set_series_visible(index, visible)

# Toggle between showing science data and contamination/model data in 2D spectra
func toggle_2d_data() -> void:
	is_showing_science = !is_showing_science
	_rebuild_2d_display()

# Rebuild the 2D display based on current mode
func _rebuild_2d_display() -> void:
	var aligned = %Spec2Ds1
	
	# Clear existing rows but don't free the stored images
	aligned.rows.clear()
	aligned.row_heights.clear()
	aligned.clear_labels()
	
	# Remove all children temporarily
	for child in aligned.get_children():
		aligned.remove_child(child)
	
	if is_showing_science:
		# Recreate the original PA-based organization
		# Group science images by PA and add them properly
		var images_by_pa = {}
		for img in science_images:
			if is_instance_valid(img):
				var img_pa = img.res.position_angle if "position_angle" in img.res else ""
				if not images_by_pa.has(img_pa):
					images_by_pa[img_pa] = []
				images_by_pa[img_pa].append(img)
		
		# Add images PA by PA (same as original loading logic)
		var pa_index = 0
		for pa in images_by_pa.keys():
			for img in images_by_pa[pa]:
				img.visible = true
				aligned.add_spectrum(img, pa_index) # add_spectrum handles add_child
			
			# Set label for this PA
			if pa != "":
				aligned.set_label(pa_index, "PA 318°")
			pa_index += 1
		
	else:
		# Add contam/model images with fixed row organization
		# Row 0: Contamination
		print("Adding ", contam_images.size(), " contamination images")
		for img in contam_images:
			if is_instance_valid(img):
				print("Adding contam image for filter: ", img.res.filter_name if "filter_name" in img.res else "unknown")
				img.visible = true
				aligned.add_spectrum(img, 0) # add_spectrum handles add_child
		if contam_images.size() > 0:
			aligned.set_label(0, "Contamination")
		
		# Row 1: Model  
		print("Adding ", model_images.size(), " model images")
		for img in model_images:
			if is_instance_valid(img):
				print("Adding model image for filter: ", img.res.filter_name if "filter_name" in img.res else "unknown")
				img.visible = true
				aligned.add_spectrum(img, 1) # add_spectrum handles add_child
		if model_images.size() > 0:
			aligned.set_label(1, "Model")
	
	# Don't call organize_rows() since we've manually assigned rows
	# Just position the textures with our existing row structure
	aligned.position_textures()


func _on_tab_toolbar_reference_pressed():
	toggle_2d_data()

# Leader key functionality
func _on_leader_timeout():
	"""Called when the leader key timer expires"""
	leader_mode_active = false
	Logger.logger.debug("Leader mode timeout - deactivated")

func _handle_leader_key_input(event: InputEvent) -> bool:
	"""Handle input during leader mode. Returns true if event was consumed."""
	if not leader_mode_active:
		return false
	
	if event is InputEventKey and event.pressed:
		var key_char = char(event.unicode).to_lower()
		Logger.logger.debug("Leader mode: received key '" + key_char + "'")
		
		# Look for spectral line with matching shortcut
		for line_name in spectral_line_data:
			var line_info = spectral_line_data[line_name]
			if line_info.has("shortcut") and line_info["shortcut"] == key_char:
				Logger.logger.info("Leader mode: Found matching line '" + line_name + "' for shortcut '" + key_char + "'")
				_set_redshift_for_line(line_name, line_info)
				leader_mode_active = false
				leader_timer.stop()
				return true
		
		Logger.logger.debug("Leader mode: No matching spectral line found for shortcut '" + key_char + "'")
		leader_mode_active = false
		leader_timer.stop()
		return true
	
	return false

func _set_redshift_for_line(line_name: String, line_info: Dictionary):
	"""Set redshift so that the specified spectral line appears at the cursor position"""
	if not spec_1d or not spec_1d.show_crosshair:
		Logger.logger.warning("Cannot set redshift for line - no 1D spectrum or crosshair not active")
		return
	
	var rest_wavelength = line_info["wl"] / 10000.0  # Convert from Angstroms to microns
	var observed_wavelength = spec_1d.crosshair_position.x  # Current cursor x position (wavelength)
	
	# Calculate redshift: z = (observed_wavelength / rest_wavelength) - 1
	var new_redshift = (observed_wavelength / rest_wavelength) - 1.0
	
	# Ensure redshift is reasonable (positive and not too extreme)
	if new_redshift < 0:
		Logger.logger.warning("Calculated negative redshift (" + str(new_redshift) + ") for line " + line_name + " - setting to 0")
		new_redshift = 0.0
	elif new_redshift > 20:
		Logger.logger.warning("Calculated very high redshift (" + str(new_redshift) + ") for line " + line_name + " - capping at 20")
		new_redshift = 20.0
	
	Logger.logger.info("Setting redshift to " + str(new_redshift) + " to place " + line_name + " at cursor position " + str(observed_wavelength) + " μm")
	set_redshift(new_redshift)
