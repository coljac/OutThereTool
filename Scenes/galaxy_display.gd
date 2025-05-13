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
var path = "./processed/" # Path to processed data directory
var data_loader = PreprocessedDataLoader.new()

@onready var redshift_label: Label = $CanvasLayer/RedshiftLabel
@onready var tab_toolbar = $VBoxContainer/TabToolbar
@onready var spec_1d = get_node("VBoxContainer/MarginContainer5/Spec1d") as PlotDisplay
@onready var pofz = get_node("VBoxContainer/MarginContainer6/VBoxContainer/Redshift") as PlotDisplay
# @onready var spec2d = $VBoxContainer/MarginContainer4/Spec2Ds/Spec2D_1 as FitsImage
@onready var spec2d: VBoxContainer = %Spec2DContainer
@onready var slider = $VBoxContainer/MarginContainer6/VBoxContainer/MarginContainer/HSlider
var redshift = 1.0


func set_object_id(new_id: String) -> void:
	object_id = new_id
	# Reload the object with the new ID
	if is_inside_tree():
		load_object()
	
	
# Flag to prevent multiple loads
var _is_loading = false

func _ready():
	# Initialize the data loader
	data_loader.initialize(path)
	
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
	
	# Load manifest
	var manifest = data_loader.load_manifest(object_id)
	if not manifest:
		print("Error: Failed to load manifest for object: ", object_id)
		_is_loading = false
		return
	
	# REDSHIFT
	var redshift_resource = data_loader.load_redshift(object_id)
	if redshift_resource:
		# Plot redshift data
		var points = data_loader.convert_redshift_for_plot(redshift_resource)
		pofz.add_series(points, Color(0.2, 0.4, 0.8), 2.0, false, 3.0)
		
		# Plot peaks
		var peak_points = data_loader.get_redshift_peaks_for_plot(redshift_resource)
		pofz.add_series(peak_points, Color(1.0, 0.0, 0.0), 0.0, true, 7.0)
		
		# Set redshift to best value
		redshift = redshift_resource.best_redshift
		slider.value = redshift
	
	# SPEC 1D
	var max_flux = 0.0
	var xx = 0.2
	for filter_name in manifest.spectrum_1d_paths.keys():
		var spectrum = data_loader.load_1d_spectrum(object_id, filter_name)
		if spectrum:
			# Plot flux data
			var points = data_loader.convert_1d_spectrum_for_plot(spectrum)
			
			# Create error data
			var y_errors = []
			for i in range(spectrum.errors.size()):
				y_errors.append(spectrum.errors[i])
			
			# Add series with errors
			spec_1d.add_series(points, Color(0.4 + xx, xx, 0.8), 2.0, false, 3.0,
				[], y_errors, Color(1.0, 0.0, 0.0), 1.0, 5.0, true)
			
			# Find max flux for scaling
			for flux in spectrum.fluxes:
				max_flux = max(max_flux, flux)
			
			xx += 0.2
	
	%Spec1d.y_max = max_flux
	
	# SPEC 2D
	var row: int = 1
	var filters = ['F115W', 'F150W', 'F200W']
	
	# We need to handle the PA (position angle) structure differently
	# Since we don't have the same structure as the FITS data
	for i in range(1, 4): # Assuming 3 PAs as in the original code
		var aligned = spec2d.get_node("Spec2Ds%d"%i)
		if not aligned:
			continue
			
		for filter_name in filters:
			var spec_display = aligned.get_node("Spec2D_" + filter_name) as FitsImage
			if not spec_display:
				continue
				
			spec_display.visible = false
			
			# Check if we have this spectrum
			if not filter_name in manifest.spectrum_2d_paths:
				continue
				
			# Load the 2D spectrum
			var spectrum = data_loader.load_2d_spectrum(object_id, filter_name)
			if not spectrum:
				continue
				
			# Load the texture
			var texture = data_loader.load_2d_spectrum_texture(object_id, filter_name)
			if not texture:
				continue
				
			# Set the texture on the TextureRect inside FitsImage
			spec_display.fits_img.texture = texture
			
			# Set scaling information for 2D spectrum alignment
			spec_display.scaling = spectrum.scaling
			
			spec_display.visible = true
			spec_display.set_label(filter_name)
	
	# DIRECT IMAGES
	for filter_name in manifest.direct_image_paths.keys():
		# Load direct image
		var direct_image = data_loader.load_direct_image(object_id, filter_name)
		if not direct_image:
			continue
			
		# Load texture
		var texture = data_loader.load_direct_image_texture(object_id, filter_name)
		if not texture:
			continue
			
		# Set texture on the FitsImage
		var nd = get_node("VBoxContainer/MarginContainer3/Imaging/IC" + filter_name + "/Direct" + filter_name) as FitsImage
		if nd:
			nd.fits_img.texture = texture
			nd._set_scale_pc(99.5)
			nd.visible = true
			nd.set_label(filter_name)
			
		# Handle segmentation map for F200W
		if filter_name == "F200W" and not direct_image.segmap_path.is_empty():
			var segmap_texture = data_loader.load_segmap_texture(object_id)
			if segmap_texture:
				var segmap = %SegMap
				if segmap:
					segmap.fits_img.texture = segmap_texture
					segmap.visible = true
					segmap.set_label("SegMap")
	
	# Position textures
	%Spec2Ds1.position_textures()
	%Spec2Ds2.position_textures()
	%Spec2Ds3.position_textures()
	
	# Reset the loading flag
	_is_loading = false
	set_redshift(redshift)
	print("Finished loading object: ", object_id)


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
