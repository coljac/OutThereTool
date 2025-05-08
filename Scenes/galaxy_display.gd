extends Control
signal next()
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
#var path = "./data/Good_example/outthere-hudfn_04375"
@export var object_id: String = "outthere-hudfn_04375" # 2122"
var path = "./data/"
@export var processed_data_path: String = "./processed/"
@export var use_preprocessed_data: bool = true

@onready var redshift_label: Label = $CanvasLayer/RedshiftLabel
@onready var tab_toolbar = $VBoxContainer/TabToolbar
@onready var spec_1d = get_node("VBoxContainer/MarginContainer5/Spec1d") as PlotDisplay
@onready var pofz = get_node("VBoxContainer/MarginContainer6/VBoxContainer/Redshift") as PlotDisplay
@onready var spec2d = $VBoxContainer/MarginContainer4/Spec2Ds/Spec2D_1 as FitsImage
@onready var slider = $VBoxContainer/MarginContainer6/VBoxContainer/MarginContainer/HSlider
var redshift = 1.0

# Data loader for pre-processed data
var data_loader: PreprocessedDataLoader

# Pre-processor for creating pre-processed data
var preprocessor = null

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
	
	# Initialize the data loader for pre-processed data
	data_loader = PreprocessedDataLoader.new()
	data_loader.initialize(processed_data_path)
	
	# Initialize the pre-processor
	preprocessor = load("res://Server/preprocess.gd").new()
	
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
		print("BAD")
		get_viewport().set_input_as_handled()
	
# func _unhandled_input(event: InputEvent) -> void:
# 	if Input.is_action_just_pressed("flag_bad"):
# 		print("Flag bad")
	
		
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
	redshift_label.text = "" # TODO figure this out, why it duplicates after a new object
	if _is_loading or not is_inside_tree():
		return
	if object_id == "":
		return
		
	_is_loading = true
	print("Loading object: ", object_id)
	
	# Clear any existing data
	if pofz:
		pofz.clear_series()
	if spec_1d:
		spec_1d.clear_series()
		
	get_node("VBoxContainer/MarginContainer/Label").text = object_id
	
	# Try to load pre-processed data first if enabled
	if use_preprocessed_data:
		# Check if pre-processed data exists
		var preprocessed_exists = FitsHelper.check_preprocessed_data_exists(object_id, processed_data_path)
		
		if preprocessed_exists:
			# Pre-processed data exists, load it
			if load_preprocessed_data():
				_is_loading = false
				print("Finished loading pre-processed data for object: ", object_id)
				return
		else:
			# Pre-processed data doesn't exist, create it
			print("No pre-processed data found, pre-processing and caching...")
			if preprocess_and_cache():
				# Now try to load the pre-processed data
				if load_preprocessed_data():
					_is_loading = false
					print("Finished loading pre-processed data for object: ", object_id)
					return
	
	# Fall back to loading from FITS files if pre-processing failed or is disabled
	print("Loading from FITS files...")
	load_from_fits()
	
	# Reset the loading flag
	_is_loading = false
	print("Finished loading object: ", object_id)

# Load data from pre-processed files
func load_preprocessed_data() -> bool:
	# Load manifest
	var manifest = data_loader.load_manifest(object_id)
	if not manifest:
		print("No pre-processed manifest found for object: ", object_id)
		return false
	
	print("Found pre-processed data for object: ", object_id)
	
	var success = true
	var loaded_components = []
	
	# Load redshift data
	var redshift_resource = data_loader.load_redshift(object_id)
	if redshift_resource:
		# Display redshift data
		var series = data_loader.convert_redshift_for_plot(redshift_resource)
		pofz.add_series(series, Color(0.2, 0.4, 0.8), 2.0, false, 3.0)
		
		var peaks = data_loader.get_redshift_peaks_for_plot(redshift_resource)
		pofz.add_series(peaks, Color(1.0, 0.0, 0.0), 0.0, true, 7.0)
		
		redshift = redshift_resource.best_redshift
		slider.value = redshift
		loaded_components.append("redshift")
	else:
		print("Warning: Failed to load redshift data for object: ", object_id)
		# Continue anyway, as we can display partial data
	
	# Load 1D spectra
	var loaded_1d = false
	for filter_name in manifest.spectrum_1d_paths:
		var spectrum = data_loader.load_1d_spectrum(object_id, filter_name)
		if spectrum:
			loaded_1d = true
			var points = data_loader.convert_1d_spectrum_for_plot(spectrum)
			var color = Color(0.4, 0.6, 0.8)
			if filter_name == "F150W":
				color = Color(0.6, 0.4, 0.8)
			elif filter_name == "F200W":
				color = Color(0.8, 0.4, 0.6)
			
			spec_1d.add_series(points, color, 2.0, false, 3.0, [],
				spectrum.errors, Color(1.0, 0.0, 0.0), 1.0, 5.0, true)
	
	if loaded_1d:
		loaded_components.append("1D spectra")
	else:
		print("Warning: Failed to load any 1D spectra for object: ", object_id)
		# Continue anyway, as we can display partial data
	
	# Load 2D spectra
	var loaded_2d = false
	for filter_name in manifest.spectrum_2d_paths:
		for spec2d in get_tree().get_nodes_in_group("spec2ds"):
			var spec_display = spec2d.get_node("Spec2D_" + filter_name) as FitsImage
			if spec_display:
				var spectrum = data_loader.load_2d_spectrum(object_id, filter_name)
				var texture = data_loader.load_2d_spectrum_texture(object_id, filter_name)
				
				if spectrum and texture:
					spec_display.fits_img.texture = texture
					spec_display.scaling = spectrum.scaling
					spec_display.visible = true
					spec_display.set_label(filter_name)
					loaded_2d = true
	
	if loaded_2d:
		loaded_components.append("2D spectra")
	
	# Load direct images
	var loaded_images = false
	for filter_name in manifest.direct_image_paths:
		var nd = get_node("VBoxContainer/MarginContainer3/Imaging/IC" + filter_name + "/" + filter_name) as FitsImage
		if nd:
			var texture = data_loader.load_direct_image_texture(object_id, filter_name)
			if texture:
				nd.fits_img.texture = texture
				nd.visible = true
				nd.set_label(filter_name)
				loaded_images = true
			
			if filter_name == "F200W":
				nd = %SegMap
				var segmap_texture = data_loader.load_segmap_texture(object_id)
				if segmap_texture:
					nd.fits_img.texture = segmap_texture
					nd.visible = true
					nd.set_label("SegMap")
	
	if loaded_images:
		loaded_components.append("direct images")
	
	# Position textures and set redshift
	%Spec2Ds.position_textures()
	set_redshift(redshift)
	
	# Check if we loaded enough components to consider it a success
	if loaded_components.size() == 0:
		print("Error: Failed to load any data components for object: ", object_id)
		return false
	
	print("Successfully loaded components: ", ", ".join(loaded_components))
	return true

# Pre-process and cache data for the current object
func preprocess_and_cache() -> bool:
	if not preprocessor:
		print("Error: Pre-processor not initialized")
		return false
	
	print("Pre-processing object: ", object_id)
	
	# Check if input files exist
	var spec_1d_path = path + object_id + ".1D.fits"
	var spec_2d_path = path + object_id + ".stack.fits"
	var direct_path = path + object_id + ".beams.fits"
	var redshift_path = path + object_id + ".full.fits"
	
	var missing_files = []
	if not FileAccess.file_exists(spec_1d_path):
		missing_files.append("1D spectrum")
	if not FileAccess.file_exists(spec_2d_path):
		missing_files.append("2D spectrum")
	if not FileAccess.file_exists(direct_path):
		missing_files.append("Direct images")
	if not FileAccess.file_exists(redshift_path):
		missing_files.append("Redshift data")
	
	if missing_files.size() > 0:
		print("Warning: Missing input files for object ", object_id, ": ", ", ".join(missing_files))
		# Continue anyway, as we can process partial data
	
	# Ensure the processed data directory exists
	var dir = DirAccess.open(processed_data_path)
	if not dir:
		var result = DirAccess.make_dir_recursive_absolute(processed_data_path)
		if result != OK:
			print("Error: Failed to create processed data directory: ", processed_data_path)
			return false
	
	# Run the pre-processor
	var manifest_path = preprocessor.preprocess_object(object_id, path, processed_data_path)
	
	if manifest_path.is_empty():
		print("Error: Failed to pre-process object: ", object_id)
		return false
	
	print("Successfully pre-processed object: ", object_id)
	return true

# Load data directly from FITS files
func load_from_fits() -> void:
	var pz = FitsHelper.get_pz(path + object_id + ".full.fits")
	var logp = Array(pz[1]).map(func(i): return FitsHelper.log10(i))
	var peaks = FitsHelper.peak_finding(logp, 50)
	
	# REDSHIFT
	var series = FitsHelper.zip_arr([Array(pz[0]), logp])
	pofz.add_series(series, Color(0.2, 0.4, 0.8), 2.0, false, 3.0)
	var z_maxes = [] as Array[Vector2]
	var max_peak = -1.0
	for peak in peaks:
		z_maxes.append(
			Vector2(pz[0][peak['x']], float(peak['max']))
		)
		if peak['max'] > max_peak:
			redshift = pz[0][peak['x']]
	slider.value = redshift
	pofz.add_series(
		z_maxes, Color(1.0, 0.0, 0.0), 0.0, true, 7.0
	)
	
	# SPEC 1D
	var oned_spec = FitsHelper.get_1d_spectrum(path + object_id + ".1D.fits", true)
	var xx = 0.2
	for f in oned_spec:
		spec_1d.add_series(oned_spec[f]['fluxes'], Color(0.4 + xx, xx, 0.8), 2.0, false, 3.0, [],
		oned_spec[f]['err'], Color(1.0, 0.0, 0.0), 1.0, 5.0, true)
		xx += 0.2
		
	# Spec2D
	var data2d = FitsHelper.get_2d_spectrum(path + object_id + ".stack.fits")
	for k in ['F115W', 'F150W', 'F200W']:
		for spec2d in get_tree().get_nodes_in_group("spec2ds"):
			var spec_display = spec2d.get_node("Spec2D_" + k) as FitsImage
			spec_display.visible = k in data2d
			if k in data2d:
				print("Setting k ", k, " ", data2d[k])
				spec_display.hdu = data2d[k]
				spec_display.set_image(path + object_id + ".stack.fits", data2d[k])
				spec_display.visible = true
				spec_display.set_label(k)
		
	# Directs
	var x = FitsHelper.get_directs(path + object_id + ".beams.fits")
	for filt in x:
		var nd = get_node("VBoxContainer/MarginContainer3/Imaging/IC" + filt + "/" + filt) as FitsImage
		nd.hdu = x[filt]
		nd._set_file(path + object_id + ".beams.fits")
		nd._set_scale_pc(99.5)
		nd.visible = true
		nd.set_label(filt)
		if filt == "F200W":
			nd = %SegMap
			nd.hdu = x[filt] + 1
			nd._set_file(path + object_id + ".beams.fits")
			# nd._set_scale_pc(99.5)
			nd.visible = true
			nd.set_label("SegMap")
				
			
	%Spec2Ds.position_textures()
	set_redshift(redshift)


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
			spec_1d.add_annotation(Vector2(lambda, (y_off * 0.075) + spec_1d.original_x_max * 0.7),
				ln, Color.WHEAT, 12)
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
