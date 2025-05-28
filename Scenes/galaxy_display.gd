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

# Visibility flags for 1D plot series
var show_flux: bool = true
var show_bestfit: bool = true
var show_errors: bool = true

# Store series indices for toggling
var flux_series: Array = []
var bestfit_series: Array = []
var error_series: Array = []

func set_object_id(new_id: String) -> void:
	object_id = new_id
	# Reload the object with the new ID
	$CanvasLayer/RedshiftLabel.text = ""
	if is_inside_tree():
		load_object()
	
	
# Flag to prevent multiple loads
var _is_loading = false

func _ready():
	# Connect to the tab toolbar signals
	if tab_toolbar:
		tab_toolbar.zoom_in_pressed.connect(_on_zoom_in_pressed)
		tab_toolbar.zoom_out_pressed.connect(_on_zoom_out_pressed)
	set_process_input(true)
	$CanvasLayer/RedshiftLabel.text = ""
	
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
	
	# Clean up asset helper
	if asset_helper:
		asset_helper.cleanup_connections()
		asset_helper.queue_free()
		asset_helper = null


func _unhandled_input(event: InputEvent) -> void:
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
	print("Loading object: ", object_id)
	
	# Clean up existing asset helper
	if asset_helper:
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
	asset_helper.set_object(object_id)

func _on_object_loaded(success: bool) -> void:
	if not success:
		print("Can't load " + object_id)
		_is_loading = false
		return
	
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
		# Reset zoom to default when loading new object
		spec_1d.reset_zoom()
	
	# Check if all resources are already cached - if so, load synchronously
	if _all_resources_cached():
		print("All resources cached, loading synchronously for: ", object_id)
		_load_all_cached_resources_sync()
		_finalize_loading()
	else:
		print("Some resources not cached, loading asynchronously for: ", object_id)
		# Fall back to async loading
		asset_helper.load_all_resources()
		_try_load_cached_resources()

func _on_resource_ready(resource_name: String) -> void:
	# A resource has been loaded, try to update the display
	# print("Resource ready: ", resource_name)
	# Only update if this resource belongs to current object
	if resource_name.begins_with(object_id):
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
		
		print(Array(data['fluxes']).min())
		
		# Add flux series (without errors) and track index
		var flux_index = spec_1d.add_series(data["fluxes"], Color(0.4 + xx, xx, 0.8), 2.0, false, 3.0, [], [], Color.TRANSPARENT, 1.0, 5.0, false)
		flux_series.append(flux_index)
		
		# Add error bars as separate series and track index
		if data.has("err") and data["err"].size() > 0:
			var error_index = spec_1d.add_series(data["fluxes"], Color.TRANSPARENT, 0.0, false, 3.0, [], data["err"], Color(1.0, 0.0, 0.0), 1.0, 5.0, false)
			error_series.append(error_index)
		
		# Add bestfit series and track index
		var bestfit_index = spec_1d.add_series(data["bestfit"], Color(0.0, 1.0, 0.0, 0.5), 2.0, false, 3.0, [])
		bestfit_series.append(bestfit_index)
		var contam_index = spec_1d.add_series(data["contam"], Color(0.3, 1.0, 1.0, 0.5), 2.0, false, 3.0, [])
		
		xx += 0.2
	
	if max_flux > 0:
		# Set min value to 1.05 * min_value to accommodate negative values
		var y_min = min_flux * 1.05 if min_flux < 0 else min_flux * 0.95
		%Spec1d.set_limits(%Spec1d.x_min, %Spec1d.x_max, y_min, max_flux, true)

func _load_2d_spectra(data2d: Dictionary) -> void:
	# Clear existing spectra
	var aligned = %Spec2Ds1
	
	# Clear existing rows in the aligned displayer BEFORE freeing children
	aligned.rows.clear()
	aligned.row_heights.clear()
	
	for child in aligned.get_children():
		child.queue_free()
	
	# Add all spectra from different position angles
	var pa_index = 0
	for pa in data2d.keys():
		for f in ['F115W', 'F150W', 'F200W']:
			if f not in data2d[pa]:
				continue
			
			var spec_display: OTImage = otimg.instantiate()
			if spec_display:
				spec_display.color_map = OTImage.ColorMap.JET
				spec_display.is_2d_spectrum = true
				spec_display.res = data2d[pa][f]
				spec_display._load_object()
				spec_display.hide_label()
				# spec_display.set_label(str(pa))
				spec_display.visible = true
				# Add the spectrum to the row corresponding to its position angle
				%Spec2Ds1.add_spectrum(spec_display, pa_index)
				%Spec2Ds1.set_label(0, "PA 318°")

		pa_index += 1
	
	# Position all textures after adding all spectra
	%Spec2Ds1.position_textures()

func _load_direct_images(directs: Dictionary) -> void:
	for filt in directs:
		var direct = directs[filt]
		if direct:
			var node_name = "VBoxContainer/MarginContainer3/Imaging/IC%s/Direct%s" % [filt, filt]
			var direct_node = get_node_or_null(node_name) as OTImage
			if direct_node:
				direct_node.res = direct
				direct_node._load_object()
				direct_node._set_scale_pc(99.5)
				direct_node.visible = true
				direct_node.set_label(filt)
				if filt == "F200W":
					var segmap_node = %SegMap
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
	
	# Load redshift data
	var pz = asset_helper.get_pz()
	if pz:
		_load_redshift_data(pz)
	
	# Load 1D spectrum
	var oned_spec = asset_helper.get_1d_spectrum(true)
	if oned_spec.size() > 0:
		_load_1d_spectrum(oned_spec)
	
	# Load 2D spectra
	var data2d = asset_helper.get_2d_spectra()
	if data2d.size() > 0:
		_load_2d_spectra(data2d)
	
	# Load direct images
	var directs = asset_helper.get_directs()
	if directs.size() > 0:
		_load_direct_images(directs)
	
	var load_time = Time.get_ticks_msec() - start_time
	print("Synchronous loading completed in ", load_time, "ms for: ", object_id)

# Finalize loading (called after sync or async loading is complete)
func _finalize_loading() -> void:
	print("Finalizing loading for: ", object_id)
	_is_loading = false
	set_redshift(redshift)
	call_deferred("oned_zoomed")

# func _unhandled_input(event: InputEvent) -> void:
# 	if Input.is_action_just_pressed("flag_bad"):
# 		print("Flag bad")
	
		
func toggle_lines(on: bool = true):
	if on:
		var lines = {
			"LyA": 1215.6709,
			"LyB": 1025.7222,
			"LyG": 972.5367,
			"LyD": 949.7430,
			"LyE": 937.8034,
			"Lyman Break": 911.753,
			
			"Ha": 6564.633,
			"Hb": 4862.688,
			"Hg": 4341.682,
			"Hd": 4102.897,
			"H7": 3971.195,
			"H8": 3890.151,
			"H9": 3836.470,
			"H10": 3798.980,
			"H11": 3771.700,
			
			"PaA": 18756.1,
			"PaB": 12821.6,
			"PaG": 10941.1,
			"PaD": 10052.1,
			"PaE": 9548.6,
			"Pa10": 9231.5,
			"Pa11": 9017.4,
			"Pa12": 8865.2,
			
			"BrA": 40522.6,
			"BrB": 26258.7,
			"BrG": 21661.2,
			"BrD": 19450.9,
			"BrE": 18179.1,
			"Br10": 17366.9,
			"Br11": 16811.1,
			"Br12": 16411.7,
			
			"PfB": 46537.8,
			"PfG": 37405.6,
			"PfD": 32969.9,
			"PfE": 30392.0,
			"Pf11": 28730.0,
			"Pf12": 27582.7,
			"Pf13": 26751.3,
			"Pf14": 26126.5,
			
			"HeI-3890": 3889.751,
			"HeI-5877": 5877.243,
			"HeI-6680": 6679.996,
			"HeI-7067": 7067.125,
			"HeI-10831": 10832.057,
			"HeI-10832": 10833.306,
			
			"HeII-1640": 1640.4,
			"HeII-4687": 4687.3,
			
			"OII 1": 3727.092,
			"OII 2": 3729.875,
			"OIII 1": 4960.30,
			"OIII 2": 5008.24,
			"OIII-4363": 4363.44,
			
			"SII 1": 6718.294,
			"SII 2": 6732.673,
			"SIII 1": 9071.1,
			"SIII 2": 9533.2,
			
			"NII 1": 6549.86,
			"NII 2": 6585.27,
			"NV 1": 1238.81,
			"NV 2": 1242.80,
			
			"CIII 1": 1906.683,
			"CIII 2": 1908.734,
			"CIV 1": 1548.187,
			"CIV 2": 1550.770,
			
			"CO(2-0)": 22935.00,
			"CO(3-1)": 23227.00,
			"CO(4-2)": 23525.00,
			"CO(5-3)": 23829.00,
			"CO(6-4)": 24127.00,
			"CO(7-5)": 24425.00,
			
			"MgII 1": 2796.35,
			"MgII 2": 2803.53,
			
			"NeIII": 3870.16,
			
			"FeII-12570": 12570.0,
			"FeII-16440": 16440.0,
			
			"PAH 3.3mum": 32900.00
		}
		var y_off = 0
		for ln in lines:
			var lambda = lines[ln] / 10000
			lambda = lambda * (1 + redshift)
			spec_1d.add_constant_line(lambda, true, Color.RED, 2.0, false)
			# spec_1d.add_annotation(Vector2(lambda, (y_off * 0.075) + spec_1d.original_x_max * 0.7),
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
