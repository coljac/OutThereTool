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

func set_object_id(new_id: String) -> void:
	object_id = new_id
	# Reload the object with the new ID
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
	if _is_loading or not is_inside_tree():
		return
	if object_id == "":
		return
		
	_is_loading = true
	print("Loading object: ", object_id)
	
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
	
	# Manifest is loaded, start loading all resources
	asset_helper.load_all_resources()
	
	# Initial UI setup
	get_node("VBoxContainer/MarginContainer/Label").text = object_id
	redshift_label.text = ""
	
	# Clear any existing data
	if pofz:
		pofz.clear_series()
	if spec_1d:
		spec_1d.clear_series()
	
	# Try to load resources that might already be cached
	_try_load_cached_resources()

func _on_resource_ready(resource_name: String) -> void:
	# A resource has been loaded, try to update the display
	print("Resource ready: ", resource_name)
	_try_load_cached_resources()

func _try_load_cached_resources() -> void:
	if not asset_helper or not asset_helper.manifest:
		return
	
	# Try to load redshift data
	var pz = asset_helper.get_pz()
	if pz:
		_load_redshift_data(pz)
	
	# Try to load 1D spectrum
	var oned_spec = asset_helper.get_1d_spectrum(true)
	if oned_spec.size() > 0:
		_load_1d_spectrum(oned_spec)
	
	# Try to load 2D spectra
	var data2d = asset_helper.get_2d_spectra()
	if data2d.size() > 0:
		_load_2d_spectra(data2d)
	
	# Try to load direct images
	var directs = asset_helper.get_directs()
	if directs.size() > 0:
		_load_direct_images(directs)
	
	# Check if loading is complete
	_check_loading_complete()

func _load_redshift_data(pz: Resource) -> void:
	if not pz or not ("log_pdf" in pz and "z_grid" in pz):
		return
	
	var logp = pz.log_pdf
	var peaks = asset_helper.peak_finding(logp, 50)
	
	# REDSHIFT
	var series = FitsHelper.zip_arr([Array(pz.z_grid), logp])
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
	for f in oned_spec:
		var data = oned_spec[f]
		if "max" in data:
			max_flux = max(max_flux, data["max"])
		
		spec_1d.add_series(data["fluxes"], Color(0.4 + xx, xx, 0.8), 2.0, false, 3.0, [], data.get("err", []), Color(1.0, 0.0, 0.0), 1.0, 5.0, true)
		spec_1d.add_series(data["bestfit"], Color(0.0, 1.0, 0.0, 0.5), 2.0, false, 3.0, [])
		xx += 0.2
	
	if max_flux > 0:
		%Spec1d.set_limits(%Spec1d.x_min, %Spec1d.x_max, %Spec1d.y_min, max_flux, true)

func _load_2d_spectra(data2d: Dictionary) -> void:
	# Clear existing spectra
	var aligned = %Spec2Ds1
	for child in aligned.get_children():
		child.queue_free()
	
	# Clear existing rows in the aligned displayer
	aligned.rows.clear()
	aligned.row_heights.clear()
	
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
				spec_display.visible = true
				# Add the spectrum to the row corresponding to its position angle
				%Spec2Ds1.add_spectrum(spec_display, pa_index)

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
	
	if pz and oned_spec.size() > 0:
		print("Basic loading complete for: ", object_id)
		_is_loading = false
		set_redshift(redshift)
		call_deferred("oned_zoomed")

func preload_next_object(next_object_id: String) -> void:
	# Preload resources for the next object in background
	if asset_helper:
		asset_helper.preload_next_object(next_object_id)

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
