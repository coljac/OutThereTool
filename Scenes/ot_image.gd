extends Control
class_name OTImage

signal mouse_coords(Vector2)
signal settings_changed(Dictionary)
#@export var fits_file: String

@export_range(0.0, 1.0) var black_level: float = 0.0: set = _set_black
@export var white_level: float = 100.0: set = _set_white
@export_range(90, 99.5, 0.5) var scale_percent: float = 99.5: set = _set_scale_pc
@export var invert_color: bool = false: set = _set_invert
@export var is_2d_spectrum: bool = false
@export var scaling = {"left": - 1.0, "right": 10.0}
enum ColorMap {GRAYSCALE, VIRIDIS, PLASMA, INFERNO, MAGMA, JET, HOT, COOL, RAINBOW}
@export var color_map: ColorMap = ColorMap.GRAYSCALE: set = _set_colormap

@onready var fits_img: TextureRect = $FitsImageShow

# var fits: Texture2D
@export var res: Resource
var show_scales = [90.0, 92.0, 93.0, 94.0, 95.0, 96.0, 97.0, 98.0, 99.0, 99.5]
var width: int = 0
var height: int = 0
var hdu: int = 1
var segmap: bool = false

# Variables for shader control
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO
var shader_material: ShaderMaterial
var z_min: float = 0.0
var z_max: float = 1.0

# Variables for drag timer
var drag_timer: Timer
var potential_drag: bool = false
var drag_threshold: float = 0.10 # Time in seconds before considering it a drag
var click_position: Vector2 = Vector2.ZERO
var current_scale_index: int = 0 # Index to track position in show_scales array

# Context menu
var context_menu: PopupMenu
var colormap_submenu: PopupMenu
var zscale_dialog: AcceptDialog
var z_min_input: SpinBox
var z_max_input: SpinBox
var zscale_params_dialog: AcceptDialog
var contrast_slider: HSlider
var samples_slider: HSlider
var samples_per_line_slider: HSlider

# Scale parameters dialog
var scale_params_dialog: AcceptDialog
var scale_min_input: SpinBox
var scale_max_input: SpinBox
var histogram_display: Control
var clip_min: float = 0.0
var clip_max: float = 1.0
var use_clipping_limits: bool = false

# ZScale parameters with DS9 defaults
var zscale_contrast: float = 0.25
var zscale_samples: int = 600
var zscale_samples_per_line: int = 120
var is_zscale_active: bool = false
var applying_settings: bool = false

var RA: float = 0.0
var dec: float = 0.0

var current_hdu = 1
var image_data: PackedFloat32Array
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process(false) # Disable _process by default
	# region_manager = RegionManager.new()
	#add_child(region_manager)
	gui_input.connect(_on_gui_input)
	if res:
		_load_object()
	
	# Initialize shader
	_init_shader()
	
	# Initialize drag timer
	drag_timer = Timer.new()
	drag_timer.one_shot = true
	drag_timer.timeout.connect(_on_drag_timer_timeout)
	add_child(drag_timer)
	
	# Initialize context menu
	_create_context_menu()
	add_to_group("images")
	settings_changed.connect(get_tree().current_scene.image_settings_changed)
	var main_ui = get_tree().current_scene
	settings_changed.connect(main_ui.image_settings_changed)
	if main_ui.locked and main_ui.image_settings.size() > 0:
		use_settings(main_ui.image_settings)
	# white_level = get_percentile(fits.get_image_data_normalized(hdu), 95.5)

func _set_image(tex: Texture2D) -> void:
	fits_img.texture = tex
	_init_shader()
	
# func _on_mouse_entered():
	# print("Mouse entered the TextureRect")
# 
# func _on_mouse_exited():
	# print("Mouse exited the TextureRect")

func _init_shader() -> void:
	# Create shader material if it doesn't exist
	if not shader_material:
		shader_material = ShaderMaterial.new()
		shader_material.shader = load("res://Resources/zscale.gdshader")
		shader_material.set_shader_parameter("z_min", z_min)
		shader_material.set_shader_parameter("z_max", z_max)
		
	# Apply shader to the texture rect
	fits_img.material = shader_material

func _reset_shader() -> void:
	z_min = 0.0
	z_max = 1.0
	if shader_material:
		shader_material.set_shader_parameter("z_min", z_min)
		shader_material.set_shader_parameter("z_max", z_max)

func _on_gui_input(event):
	if event is InputEventMouseMotion:
		# Handle mouse movement
		_handle_mouse_motion(event)
		
		# If we're in potential drag state and mouse has moved significantly, start actual drag
		if potential_drag and event.position.distance_to(click_position) > 5:
			potential_drag = false
			is_dragging = true
			drag_start_position = click_position # Use the original click position
			drag_timer.stop()
			
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.is_double_click():
					_set_scale_pc(99.5)
					_reset_shader()
					is_zscale_active = false
					current_scale_index = show_scales.size() - 1 # Reset index to last element (99.5)
				else:
					# Start potential drag
					potential_drag = true
					is_dragging = false
					click_position = event.position
					drag_timer.start(drag_threshold)
			else:
				# On release
				drag_timer.stop()
				
				# If we're still in potential drag state, it was a quick click
				if potential_drag:
					_handle_quick_click(event.position)
				
				# Reset states
				potential_drag = false
				is_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Show context menu instead of directly inverting
			_show_context_menu(event.global_position)


func _handle_mouse_motion(event: InputEventMouseMotion):
	# if is_2d_spectrum:
		# return
	# Get local mouse position relative to the TextureRect
	var local_pos = event.position
	
	# Handle shader parameter adjustment if dragging
	if is_dragging and shader_material:
		var delta = local_pos - drag_start_position
		
		# Adjust z_max based on horizontal movement (right increases, left decreases)
		z_max = clamp(z_max + delta.x * 0.001, 0.0, 1.0)
		
		# Adjust z_min based on vertical movement (up decreases, down increases)
		z_min = clamp(z_min - delta.y * 0.001, 0.0, 1.0)
		
		# Update shader parameters
		shader_material.set_shader_parameter("z_min", z_min)
		shader_material.set_shader_parameter("z_max", z_max)
		
		# Update drag start position for next frame
		drag_start_position = local_pos
	
	# Get the coordinates as a ratio of the texture size (0-1 range)
	var normalized_pos = Vector2(
		local_pos.x / size.x,
		local_pos.y / size.y
	)
	
	
# Set the canonical HDR data, read in metadata
func _load_object() -> void:
	if res:
		width = res.width
		height = res.height
		
		if "image_data" in res and res.image_data.size() > 0:
			# Normalise so there's something to see
			image_data = res.segmap_data if segmap else res.image_data
			var t = Array(image_data)
			var m = t.max()
			image_data = t.map(func(x): return x / m)
			# Initialize zscale parameters to data range
			z_min = 0.0
			z_max = 1.0
			
			# Initialize clipping limits to data range
			var data_min = image_data[0]
			var data_max = image_data[0]
			for value in image_data:
				if is_finite(value):
					data_min = min(data_min, value)
					data_max = max(data_max, value)
			clip_min = data_min
			clip_max = data_max

		white_level = get_percentile(95.5)
		var wcs: Dictionary
		if is_2d_spectrum:
			# print(fits_img.texture.get_image().get_data())
			# print("--------------------")
			if "wcs_info" in res:
				wcs = res['wcs_info']
			else:
				wcs = res['header_info']
			# var wcs = res['wcs_info']
			# var crpix = float(wcs['CRPIX1'])
			# var crval = float(wcs['CRVAL1'])
			# var cdelt = float(wcs['CD1_1'])
			scaling = res['scaling']
			# print(scaling)
			# scaling = {"left": - crpix * cdelt + crval, "right": (width - crpix) * cdelt + crval}
			
			# Apply filter-based trimming for 2D spectra
			_apply_filter_trimming()
			
		if res and "position_angle" in res and res.position_angle != "":
			set_label("PA " + str(res.position_angle))
		else:
			set_label("STACK")
			
	_make_texture()


func set_texture_scale(t: Vector2):
	fits_img.scale = t

func _settings_changed():
	settings_changed.emit({
		"scale": scale_percent,
		"colormap": color_map,
		"invert_color": invert_color,
		"z_min": z_min,
		"z_max": z_max,
		"is_zscale_active": is_zscale_active,
		"zscale_contrast": zscale_contrast,
		"zscale_samples": zscale_samples,
		"zscale_samples_per_line": zscale_samples_per_line,
		"clip_min": clip_min,
		"clip_max": clip_max,
		"use_clipping_limits": use_clipping_limits
	})

func set_label(t: String):
	$Label.text = t
	if t != "" and is_2d_spectrum:
		show_label()
	
func show_label():
	$Label.visible = true

func hide_label():
	$Label.visible = false

func _make_texture():
	if image_data and fits_img:
		fits_img.texture = display_fits_image(width, height, black_level, white_level)
		# Disable texture filtering for crisp, unsmoothed pixels
		fits_img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Re-apply shader after texture update
		_init_shader()
	
func _set_scale_pc(p: float):
	scale_percent = p
	if image_data:
		white_level = get_percentile(p)
		_make_texture()
		# if not external:
			# settings_changed.emit({"scale": p})

func use_settings(settings: Dictionary):
	if applying_settings:
		return  # Prevent recursive calls
	
	applying_settings = true
	
	if "is_zscale_active" in settings:
		is_zscale_active = settings['is_zscale_active']
	if "zscale_contrast" in settings:
		zscale_contrast = settings['zscale_contrast']
	if "zscale_samples" in settings:
		zscale_samples = settings['zscale_samples']
	if "zscale_samples_per_line" in settings:
		zscale_samples_per_line = settings['zscale_samples_per_line']
	
	if is_zscale_active:
		# If zscale is active, apply it without triggering settings change
		var limits = _calculate_zscale_limits(image_data, width, height, zscale_contrast, zscale_samples, zscale_samples_per_line)
		z_min = limits[0]
		z_max = limits[1]
		if shader_material:
			shader_material.set_shader_parameter("z_min", z_min)
			shader_material.set_shader_parameter("z_max", z_max)
	else:
		# Use regular scaling
		if "scale" in settings:
			_set_scale_pc(settings['scale'])
		_reset_shader()
	
	if 'colormap' in settings:
		_set_colormap(settings['colormap'])
	if "invert_color" in settings:
		_set_invert(settings['invert_color'])
	if "z_min" in settings and not is_zscale_active:
		z_min = settings['z_min']
		if shader_material:
			shader_material.set_shader_parameter("z_min", z_min)
	if "z_max" in settings and not is_zscale_active:
		z_max = settings['z_max']
		if shader_material:
			shader_material.set_shader_parameter("z_max", z_max)
	
	# Apply clipping limit settings
	if "clip_min" in settings:
		clip_min = settings['clip_min']
	if "clip_max" in settings:
		clip_max = settings['clip_max']
	if "use_clipping_limits" in settings:
		use_clipping_limits = settings['use_clipping_limits']
	
	applying_settings = false
	
func _set_black(b: float):
	black_level = b
	if image_data:
		_make_texture()
	
func _set_white(w: float):
	white_level = w
	if image_data:
		_make_texture()

func _set_invert(i: bool):
	invert_color = i
	if image_data:
		_make_texture()

func _set_colormap(cm: ColorMap):
	color_map = cm
	if image_data:
		_make_texture()
		
func get_color_from_map(val: float) -> Color:
	match color_map:
		ColorMap.GRAYSCALE:
			return Color(val, val, val)
		ColorMap.VIRIDIS:
			return viridis_colormap(val)
		ColorMap.PLASMA:
			return plasma_colormap(val)
		ColorMap.INFERNO:
			return inferno_colormap(val)
		ColorMap.MAGMA:
			return magma_colormap(val)
		ColorMap.JET:
			return jet_colormap(val)
		ColorMap.HOT:
			return hot_colormap(val)
		ColorMap.COOL:
			return cool_colormap(val)
		ColorMap.RAINBOW:
			return rainbow_colormap(val)
		_:
			return Color(val, val, val)

# Viridis colormap (perceptually uniform, good for scientific visualization)
func viridis_colormap(val: float) -> Color:
	# More accurate polynomial approximation of the viridis colormap
	# Based on fitting actual matplotlib viridis data
	var v = clamp(val, 0.0, 1.0)
	var r = 0.26700401 + 2.0813724 * v - 3.4556669 * pow(v, 2) + 4.1645133 * pow(v, 3) - 2.2514525 * pow(v, 4) + 0.4188656 * pow(v, 5)
	var g = 0.00487433 + 0.08400179 * v + 2.8667383 * pow(v, 2) - 5.7218461 * pow(v, 3) + 5.0475832 * pow(v, 4) - 1.5259156 * pow(v, 5)
	var b = 0.32941519 + 2.2148102 * v - 4.6480078 * pow(v, 2) + 5.0897212 * pow(v, 3) - 3.2540218 * pow(v, 4) + 0.8866533 * pow(v, 5)
	return Color(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0))

# Plasma colormap
func plasma_colormap(val: float) -> Color:
	# More accurate polynomial approximation of the plasma colormap
	var v = clamp(val, 0.0, 1.0)
	var r = 0.05873234 + 2.176514 * v - 2.689460 * pow(v, 2) + 3.524820 * pow(v, 3) - 2.483986 * pow(v, 4) + 0.659330 * pow(v, 5)
	var g = 0.02333670 + 0.155659 * v + 1.575416 * pow(v, 2) - 2.379453 * pow(v, 3) + 2.050183 * pow(v, 4) - 0.745367 * pow(v, 5)
	var b = 0.53314923 - 0.093745 * v - 0.965607 * pow(v, 2) + 4.050445 * pow(v, 3) - 4.434278 * pow(v, 4) + 1.512320 * pow(v, 5)
	return Color(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0))

# Inferno colormap
func inferno_colormap(val: float) -> Color:
	# More accurate polynomial approximation of the inferno colormap
	var v = clamp(val, 0.0, 1.0)
	var r = 0.0002189 + 1.065619 * v + 1.463551 * pow(v, 2) - 3.267431 * pow(v, 3) + 3.584930 * pow(v, 4) - 1.248952 * pow(v, 5)
	var g = 0.0016117 + 0.018343 * v + 1.260232 * pow(v, 2) - 0.577150 * pow(v, 3) - 0.508420 * pow(v, 4) + 0.347009 * pow(v, 5)
	var b = 0.0146755 + 3.547456 * v - 9.310138 * pow(v, 2) + 14.281655 * pow(v, 3) - 11.108198 * pow(v, 4) + 3.384018 * pow(v, 5)
	return Color(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0))

# Magma colormap
func magma_colormap(val: float) -> Color:
	# More accurate polynomial approximation of the magma colormap
	var v = clamp(val, 0.0, 1.0)
	var r = -0.0002466 + 1.4693055 * v - 0.0958300 * pow(v, 2) - 2.0391170 * pow(v, 3) + 3.1307341 * pow(v, 4) - 1.1621249 * pow(v, 5)
	var g = 0.0013756 + 0.0305279 * v + 1.2864551 * pow(v, 2) - 1.8471288 * pow(v, 3) + 1.8360190 * pow(v, 4) - 0.7805973 * pow(v, 5)
	var b = 0.0142064 + 1.6458197 * v - 3.8294083 * pow(v, 2) + 6.5912053 * pow(v, 3) - 5.5844279 * pow(v, 4) + 1.7450316 * pow(v, 5)
	return Color(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0))

# Jet colormap (similar to MATLAB's jet)
func jet_colormap(val: float) -> Color:
	var r = clamp(1.5 - abs(4.0 * val - 3.0), 0.0, 1.0)
	var g = clamp(1.5 - abs(4.0 * val - 2.0), 0.0, 1.0)
	var b = clamp(1.5 - abs(4.0 * val - 1.0), 0.0, 1.0)
	return Color(r, g, b)

# Hot colormap (black-red-yellow-white)
func hot_colormap(val: float) -> Color:
	var r = clamp(3.0 * val, 0.0, 1.0)
	var g = clamp(3.0 * val - 1.0, 0.0, 1.0)
	var b = clamp(3.0 * val - 2.0, 0.0, 1.0)
	return Color(r, g, b)

# Cool colormap (cyan to magenta)
func cool_colormap(val: float) -> Color:
	var r = clamp(val, 0.0, 1.0)
	var g = clamp(1.0 - val, 0.0, 1.0)
	var b = 1.0
	return Color(r, g, b)

# Rainbow colormap
func rainbow_colormap(val: float) -> Color:
	var r = clamp(abs(2.0 * val - 0.5) * 2.0, 0.0, 1.0)
	var g = clamp(sin(val * PI), 0.0, 1.0)
	var b = clamp(cos(0.5 * val * PI), 0.0, 1.0)
	return Color(r, g, b)
	
func get_percentile(percentile: float) -> float:
	var sorted_data = image_data.duplicate()
	sorted_data.sort()
	var idx = int(ceil(percentile / 100.0 * sorted_data.size())) - 1
	return sorted_data[idx]

func display_fits_image(width: int, height: int, black_level: float, white_level: float) -> ImageTexture:
	var float_data
	
	# Get the raw data from the resource
	# if "image_data" in res and res.image_data.size() > 0:
		# float_data = res.image_data
	# else:
		# Fallback to getting data from the texture if available
		# float_data = fits.get_image().data['data']
	float_data = image_data

	var img = Image.create(width, height, false, Image.FORMAT_RGBAF)
	var inv_range = 1.0 / max(0.000001, white_level - black_level)

	for i in range(width * height):
		if i >= float_data.size():
			break
			
		var val = (float_data[i] - black_level) * inv_range
		val = clamp(val, 0.0, 1.0)
		if invert_color:
			val = 1.0 - val
		var x = i % width
		var y = int(i / width)
		
		var color = get_color_from_map(val)
		img.set_pixel(x, y, color)
	
	var tex = ImageTexture.create_from_image(img)
	return tex
	
func _unhandled_input(event: InputEvent) -> void:
	if event as InputEventMouseMotion:
		pass
		# print(event)

func _on_drag_timer_timeout() -> void:
	# If we're still in potential drag state after the timer expires,
	# convert to actual drag
	if potential_drag:
		potential_drag = false
		is_dragging = true
		drag_start_position = click_position

# Handle quick click (non-drag) action
func _handle_quick_click(position: Vector2) -> void:
	# Cycle through the show_scales list
	current_scale_index = (current_scale_index + 1) % show_scales.size()
	var new_scale = show_scales[current_scale_index]
	
	# Set the new scale and reset shader
	_set_scale_pc(new_scale)
	_reset_shader()
	is_zscale_active = false
	_settings_changed()

func _create_context_menu() -> void:
	# Create main context menu
	context_menu = PopupMenu.new()
	add_child(context_menu)
	context_menu.connect("id_pressed", _on_context_menu_item_selected)
		
	# Add scale options
	context_menu.add_item("Scale 90%", 0)
	context_menu.add_item("Scale 95%", 1)
	context_menu.add_item("Scale 99%", 2)
	context_menu.add_item("Scale 99.5%", 3)
	context_menu.add_item("ZScale", 4)
	context_menu.add_separator()
	
	# Add zscale option
	context_menu.add_item("Set Z-Scale...", 5)
	context_menu.add_item("Scale Parameters...", 7)
	context_menu.add_separator()
	
	# Add invert option
	context_menu.add_item("Invert Colors", 6)
	context_menu.add_separator()
	
	# Create colormap submenu
	colormap_submenu = PopupMenu.new()
	colormap_submenu.name = "ColorMapSubmenu"
	colormap_submenu.connect("id_pressed", _on_colormap_selected)
	
	# Add colormap options
	colormap_submenu.add_item("Grayscale", ColorMap.GRAYSCALE)
	colormap_submenu.add_item("Viridis", ColorMap.VIRIDIS)
	colormap_submenu.add_item("Plasma", ColorMap.PLASMA)
	colormap_submenu.add_item("Inferno", ColorMap.INFERNO)
	colormap_submenu.add_item("Magma", ColorMap.MAGMA)
	colormap_submenu.add_item("Jet", ColorMap.JET)
	colormap_submenu.add_item("Hot", ColorMap.HOT)
	colormap_submenu.add_item("Cool", ColorMap.COOL)
	colormap_submenu.add_item("Rainbow", ColorMap.RAINBOW)
	
	# Add colormap submenu to main menu - submenu must be added as child first
	context_menu.add_child(colormap_submenu)
	context_menu.add_submenu_node_item("Color Map", colormap_submenu)
	
	# Create zscale dialog
	_create_zscale_dialog()
	_create_zscale_params_dialog()

func _show_context_menu(global_pos: Vector2) -> void:
	# Update checkmarks for current settings
	_update_context_menu_checkmarks()
	
	# Show the context menu at the mouse position
	context_menu.popup(Rect2i(global_pos, Vector2i.ZERO))

func _update_context_menu_checkmarks() -> void:
	# Clear all checkmarks first
	for i in range(context_menu.get_item_count()):
		context_menu.set_item_checked(i, false)
	
	# Check the current scale option or zscale
	if is_zscale_active:
		context_menu.set_item_checked(4, true)  # ZScale
	else:
		var current_scale = scale_percent
		if abs(current_scale - 90.0) < 0.1:
			context_menu.set_item_checked(0, true)
		elif abs(current_scale - 95.0) < 0.1:
			context_menu.set_item_checked(1, true)
		elif abs(current_scale - 99.0) < 0.1:
			context_menu.set_item_checked(2, true)
		elif abs(current_scale - 99.5) < 0.1:
			context_menu.set_item_checked(3, true)
	
	# Check invert option
	context_menu.set_item_checked(6, invert_color)
	
	# Update colormap submenu checkmarks
	for i in range(colormap_submenu.get_item_count()):
		colormap_submenu.set_item_checked(i, false)
	colormap_submenu.set_item_checked(color_map, true)

func _on_context_menu_item_selected(id: int) -> void:
	match id:
		0: # Scale 90%
			_set_scale_pc(90.0)
			current_scale_index = show_scales.find(90.0)
			_reset_shader()
			is_zscale_active = false
		1: # Scale 95%
			_set_scale_pc(95.0)
			current_scale_index = show_scales.find(95.0)
			_reset_shader()
			is_zscale_active = false
		2: # Scale 99%
			_set_scale_pc(99.0)
			current_scale_index = show_scales.find(99.0)
			_reset_shader()
			is_zscale_active = false
		3: # Scale 99.5%
			_set_scale_pc(99.5)
			current_scale_index = show_scales.find(99.5)
			_reset_shader()
			is_zscale_active = false
		4: # ZScale
			_apply_zscale()
			is_zscale_active = true
		5: # Set Z-Scale
			_show_zscale_params_dialog()
		6: # Invert
			invert_color = not invert_color
		7: # Scale Parameters
			_show_scale_parameters_dialog()
	_settings_changed()

func _on_colormap_selected(colormap_id: int) -> void:
	color_map = colormap_id
	_settings_changed()

func _create_zscale_dialog() -> void:
	zscale_dialog = AcceptDialog.new()
	zscale_dialog.title = "Set Z-Scale Parameters"
	zscale_dialog.size = Vector2i(300, 150)
	add_child(zscale_dialog)
	
	# Create dialog content
	var vbox = VBoxContainer.new()
	zscale_dialog.add_child(vbox)
	
	# Z Min input
	var z_min_label = Label.new()
	z_min_label.text = "Z Min:"
	vbox.add_child(z_min_label)
	
	z_min_input = SpinBox.new()
	z_min_input.min_value = 0.0
	z_min_input.max_value = 1.0
	z_min_input.step = 0.001
	z_min_input.value = z_min
	vbox.add_child(z_min_input)
	
	# Z Max input
	var z_max_label = Label.new()
	z_max_label.text = "Z Max:"
	vbox.add_child(z_max_label)
	
	z_max_input = SpinBox.new()
	z_max_input.min_value = 0.0
	z_max_input.max_value = 1.0
	z_max_input.step = 0.001
	z_max_input.value = z_max
	vbox.add_child(z_max_input)
	
	# Connect dialog signals
	zscale_dialog.connect("confirmed", _on_zscale_dialog_confirmed)

func _show_zscale_dialog() -> void:
	# Update dialog inputs with current values
	z_min_input.value = z_min
	z_max_input.value = z_max
	
	# Show the dialog
	zscale_dialog.popup_centered()

func _on_zscale_dialog_confirmed() -> void:
	# Get values from inputs
	var new_z_min = z_min_input.value
	var new_z_max = z_max_input.value
	
	# Validate values (ensure min < max)
	if new_z_min >= new_z_max:
		print("Z Min must be less than Z Max")
		return
	
	# Update shader parameters
	z_min = new_z_min
	z_max = new_z_max
	
	if shader_material:
		shader_material.set_shader_parameter("z_min", z_min)
		shader_material.set_shader_parameter("z_max", z_max)
	
	# Propagate settings to other images
	_settings_changed()

func _apply_zscale() -> void:
	# Apply zscale algorithm with current parameters
	if use_clipping_limits:
		_apply_zscale_with_limits()
	else:
		_apply_zscale_with_params(zscale_contrast, zscale_samples, zscale_samples_per_line)

func _apply_zscale_with_params(contrast: float, n_samples: int, samples_per_line: int) -> void:
	if not image_data or image_data.size() == 0:
		print("Error: No image data available for zscale")
		return
	
	print("Applying zscale with contrast=", contrast, " samples=", n_samples, " data_size=", image_data.size())
	
	# Calculate zscale limits using the proper algorithm
	var limits = _calculate_zscale_limits(image_data, width, height, contrast, n_samples, samples_per_line)
	
	# Validate limits
	if limits[0] == limits[1]:
		print("Warning: zscale limits are identical, using small range")
		limits[1] = limits[0] + 0.001
	
	# Update shader parameters
	z_min = limits[0]
	z_max = limits[1]
	
	print("ZScale limits: z_min=", z_min, " z_max=", z_max)
	
	if shader_material:
		shader_material.set_shader_parameter("z_min", z_min)
		shader_material.set_shader_parameter("z_max", z_max)
	
	# Propagate settings to other images
	_settings_changed()

func _calculate_zscale_limits(data: PackedFloat32Array, img_width: int, img_height: int, contrast: float, n_samples: int, samples_per_line: int) -> Array:
	# Implementation of the zscale algorithm as described
	if not data or data.size() == 0:
		print("Error: No image data available for zscale calculation")
		return [0.0, 1.0]
	
	var total_pixels = data.size()
	
	# Sample approximately n_samples pixels evenly distributed
	var samples = PackedFloat32Array()
	var step = max(1, total_pixels / n_samples)
	
	for i in range(0, total_pixels, step):
		if i < data.size():
			var value = data[i]
			if is_finite(value):
				samples.append(value)
	
	if samples.size() < 5:
		# Not enough samples, find min/max from original data
		var min_val = data[0]
		var max_val = data[0]
		for value in data:
			if is_finite(value):
				min_val = min(min_val, value)
				max_val = max(max_val, value)
		print("Warning: Not enough valid samples for zscale, using data range: ", min_val, " to ", max_val)
		return [min_val, max_val]
	
	# Sort samples to form I(i) function
	samples.sort()
	var npoints = samples.size()
	var midpoint = npoints / 2
	
	# Create index array for fitting
	var indices = PackedFloat32Array()
	for i in range(npoints):
		indices.append(float(i))
	
	# Iterative fitting with rejection
	var max_reject = 0.5
	var krej = 2.5
	var max_iterations = 5
	var min_npixels = max(5, int(npoints * (1.0 - max_reject)))
	
	var good_indices = range(npoints)
	var ngoodpix = npoints
	var last_ngoodpix = npoints + 1
	var iteration = 0
	var slope = 0.0
	var intercept = 0.0
	
	while ngoodpix > min_npixels and ngoodpix != last_ngoodpix and iteration < max_iterations:
		# Fit linear function I(i) = intercept + slope * (i - midpoint)
		var sum_x = 0.0
		var sum_y = 0.0
		var sum_xy = 0.0
		var sum_xx = 0.0
		var n = good_indices.size()
		
		for idx in good_indices:
			var x = float(idx - midpoint)
			var y = samples[idx]
			sum_x += x
			sum_y += y
			sum_xy += x * y
			sum_xx += x * x
		
		if n > 1 and sum_xx != 0:
			slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
			intercept = (sum_y - slope * sum_x) / n
		else:
			slope = 0.0
			intercept = samples[midpoint]
		
		# Calculate residuals and reject outliers
		var residuals = []
		for idx in good_indices:
			var expected = intercept + slope * (idx - midpoint)
			var resid = samples[idx] - expected
			residuals.append(resid)
		
		# Calculate standard deviation of residuals
		var mean_resid = 0.0
		for resid in residuals:
			mean_resid += resid
		mean_resid /= residuals.size()
		
		var std_resid = 0.0
		for resid in residuals:
			std_resid += (resid - mean_resid) * (resid - mean_resid)
		std_resid = sqrt(std_resid / residuals.size())
		
		# Reject outliers
		last_ngoodpix = ngoodpix
		var threshold = krej * std_resid
		var new_good_indices = []
		
		for i in range(good_indices.size()):
			if abs(residuals[i]) <= threshold:
				new_good_indices.append(good_indices[i])
		
		good_indices = new_good_indices
		ngoodpix = good_indices.size()
		iteration += 1
	
	# Calculate final z1 and z2
	var z1: float
	var z2: float
	
	if ngoodpix >= min_npixels and slope != 0.0:
		# Use the fitted line with contrast adjustment
		var median_value = samples[midpoint]
		var adjusted_slope = slope / contrast if contrast > 0 else 0.0
		
		z1 = median_value + adjusted_slope * (1 - midpoint)
		z2 = median_value + adjusted_slope * (npoints - midpoint)
		
		# Ensure limits are within the original sample range
		z1 = max(z1, samples[0])
		z2 = min(z2, samples[npoints - 1])
	else:
		# No well-defined slope, use full range
		z1 = samples[0]
		z2 = samples[npoints - 1]
	
	return [z1, z2]

func _create_zscale_params_dialog() -> void:
	zscale_params_dialog = AcceptDialog.new()
	zscale_params_dialog.title = "ZScale Parameters"
	zscale_params_dialog.size = Vector2i(400, 300)
	add_child(zscale_params_dialog)
	
	# Create dialog content
	var vbox = VBoxContainer.new()
	zscale_params_dialog.add_child(vbox)
	
	# Contrast slider
	var contrast_label = Label.new()
	contrast_label.text = "Contrast: 0.25"
	vbox.add_child(contrast_label)
	
	contrast_slider = HSlider.new()
	contrast_slider.min_value = 0.1
	contrast_slider.max_value = 1.0
	contrast_slider.step = 0.01
	contrast_slider.value = 0.25
	contrast_slider.value_changed.connect(func(value): contrast_label.text = "Contrast: %.2f" % value)
	vbox.add_child(contrast_slider)
	
	# Samples slider
	var samples_label = Label.new()
	samples_label.text = "Number of Samples: 600"
	vbox.add_child(samples_label)
	
	samples_slider = HSlider.new()
	samples_slider.min_value = 100
	samples_slider.max_value = 2000
	samples_slider.step = 50
	samples_slider.value = 600
	samples_slider.value_changed.connect(func(value): samples_label.text = "Number of Samples: %d" % value)
	vbox.add_child(samples_slider)
	
	# Samples per line slider
	var samples_per_line_label = Label.new()
	samples_per_line_label.text = "Samples per Line: 120"
	vbox.add_child(samples_per_line_label)
	
	samples_per_line_slider = HSlider.new()
	samples_per_line_slider.min_value = 50
	samples_per_line_slider.max_value = 500
	samples_per_line_slider.step = 10
	samples_per_line_slider.value = 120
	samples_per_line_slider.value_changed.connect(func(value): samples_per_line_label.text = "Samples per Line: %d" % value)
	vbox.add_child(samples_per_line_slider)
	
	# Connect dialog signals
	zscale_params_dialog.connect("confirmed", _on_zscale_params_dialog_confirmed)

func _show_zscale_params_dialog() -> void:
	if not zscale_params_dialog:
		_create_zscale_params_dialog()
	
	# Update sliders with current values and their labels
	contrast_slider.value = zscale_contrast
	samples_slider.value = zscale_samples
	samples_per_line_slider.value = zscale_samples_per_line
	
	# Update the labels to show current values
	var vbox = zscale_params_dialog.get_child(0)
	var contrast_label = vbox.get_child(0)
	var samples_label = vbox.get_child(2)
	var samples_per_line_label = vbox.get_child(4)
	
	contrast_label.text = "Contrast: %.2f" % zscale_contrast
	samples_label.text = "Number of Samples: %d" % zscale_samples
	samples_per_line_label.text = "Samples per Line: %d" % zscale_samples_per_line
	
	# Show the dialog
	zscale_params_dialog.popup_centered()

func _on_zscale_params_dialog_confirmed() -> void:
	# Store the selected parameters
	zscale_contrast = contrast_slider.value
	zscale_samples = int(samples_slider.value)
	zscale_samples_per_line = int(samples_per_line_slider.value)
	
	# Apply zscale with the selected parameters
	_apply_zscale_with_params(zscale_contrast, zscale_samples, zscale_samples_per_line)

func _create_scale_parameters_dialog() -> void:
	scale_params_dialog = AcceptDialog.new()
	scale_params_dialog.title = "Scale Parameters"
	scale_params_dialog.size = Vector2i(500, 400)
	add_child(scale_params_dialog)
	
	# Create main container
	var vbox = VBoxContainer.new()
	scale_params_dialog.add_child(vbox)
	
	# Title label
	var title_label = Label.new()
	title_label.text = "Set Min/Max values for clipping and scaling"
	vbox.add_child(title_label)
	
	# Min value input
	var min_container = HBoxContainer.new()
	vbox.add_child(min_container)
	
	var min_label = Label.new()
	min_label.text = "Min Value:"
	min_label.custom_minimum_size.x = 80
	min_container.add_child(min_label)
	
	scale_min_input = SpinBox.new()
	scale_min_input.min_value = -1000.0
	scale_min_input.max_value = 1000.0
	scale_min_input.step = 0.001
	scale_min_input.value = clip_min
	scale_min_input.value_changed.connect(_on_scale_param_changed)
	min_container.add_child(scale_min_input)
	
	# Max value input
	var max_container = HBoxContainer.new()
	vbox.add_child(max_container)
	
	var max_label = Label.new()
	max_label.text = "Max Value:"
	max_label.custom_minimum_size.x = 80
	max_container.add_child(max_label)
	
	scale_max_input = SpinBox.new()
	scale_max_input.min_value = -1000.0
	scale_max_input.max_value = 1000.0
	scale_max_input.step = 0.001
	scale_max_input.value = clip_max
	scale_max_input.value_changed.connect(_on_scale_param_changed)
	max_container.add_child(scale_max_input)
	
	# Auto percentile buttons
	var percentile_container = HBoxContainer.new()
	vbox.add_child(percentile_container)
	
	var percentile_label = Label.new()
	percentile_label.text = "Quick Set:"
	percentile_container.add_child(percentile_label)
	
	var p95_button = Button.new()
	p95_button.text = "95%"
	p95_button.pressed.connect(func(): _set_percentile_limits(2.5, 97.5))
	percentile_container.add_child(p95_button)
	
	var p99_button = Button.new()
	p99_button.text = "99%"
	p99_button.pressed.connect(func(): _set_percentile_limits(0.5, 99.5))
	percentile_container.add_child(p99_button)
	
	var full_range_button = Button.new()
	full_range_button.text = "Full Range"
	full_range_button.pressed.connect(func(): _set_full_range_limits())
	percentile_container.add_child(full_range_button)
	
	# Histogram display
	histogram_display = Control.new()
	histogram_display.custom_minimum_size = Vector2(450, 150)
	histogram_display.draw.connect(_draw_histogram)
	vbox.add_child(histogram_display)
	
	# Connect dialog signals
	scale_params_dialog.connect("confirmed", _on_scale_params_dialog_confirmed)

func _show_scale_parameters_dialog() -> void:
	if not scale_params_dialog:
		_create_scale_parameters_dialog()
	
	# Update inputs with current values
	scale_min_input.value = clip_min
	scale_max_input.value = clip_max
	
	# Update histogram
	histogram_display.queue_redraw()
	
	# Show the dialog
	scale_params_dialog.popup_centered()

func _on_scale_param_changed(value: float):
	# Live update the image when parameters change
	clip_min = scale_min_input.value
	clip_max = scale_max_input.value
	
	# Ensure min < max
	if clip_min >= clip_max:
		if scale_min_input.has_focus():
			clip_max = clip_min + 0.001
			scale_max_input.value = clip_max
		else:
			clip_min = clip_max - 0.001
			scale_min_input.value = clip_min
	
	use_clipping_limits = true
	histogram_display.queue_redraw()
	
	# Apply the scaling immediately for live preview
	_apply_current_scaling()

func _on_scale_params_dialog_confirmed() -> void:
	# Apply the final settings
	clip_min = scale_min_input.value
	clip_max = scale_max_input.value
	use_clipping_limits = true
	
	# Apply current scaling method with new limits
	_apply_current_scaling()
	_settings_changed()

func _set_percentile_limits(min_percentile: float, max_percentile: float) -> void:
	if not image_data or image_data.size() == 0:
		return
	
	var sorted_data = image_data.duplicate()
	sorted_data.sort()
	
	var min_idx = int((min_percentile / 100.0) * sorted_data.size())
	var max_idx = int((max_percentile / 100.0) * sorted_data.size()) - 1
	
	min_idx = clamp(min_idx, 0, sorted_data.size() - 1)
	max_idx = clamp(max_idx, 0, sorted_data.size() - 1)
	
	clip_min = sorted_data[min_idx]
	clip_max = sorted_data[max_idx]
	
	scale_min_input.value = clip_min
	scale_max_input.value = clip_max
	
	use_clipping_limits = true
	histogram_display.queue_redraw()
	_apply_current_scaling()

func _set_full_range_limits() -> void:
	if not image_data or image_data.size() == 0:
		return
	
	var min_val = image_data[0]
	var max_val = image_data[0]
	
	for value in image_data:
		if is_finite(value):
			min_val = min(min_val, value)
			max_val = max(max_val, value)
	
	clip_min = min_val
	clip_max = max_val
	
	scale_min_input.value = clip_min
	scale_max_input.value = clip_max
	
	use_clipping_limits = true
	histogram_display.queue_redraw()
	_apply_current_scaling()

func _apply_current_scaling() -> void:
	# Apply the current scaling method (zscale or percentile) with clipping limits
	if is_zscale_active:
		_apply_zscale_with_limits()
	else:
		# For percentile scaling, the limits are applied directly through shader
		if use_clipping_limits:
			var data_min = image_data[0]
			var data_max = image_data[0]
			for value in image_data:
				if is_finite(value):
					data_min = min(data_min, value)
					data_max = max(data_max, value)
			
			if data_max > data_min:
				z_min = (clip_min - data_min) / (data_max - data_min)
				z_max = (clip_max - data_min) / (data_max - data_min)
				z_min = clamp(z_min, 0.0, 1.0)
				z_max = clamp(z_max, 0.0, 1.0)
				if shader_material:
					shader_material.set_shader_parameter("z_min", z_min)
					shader_material.set_shader_parameter("z_max", z_max)

func _apply_zscale_with_limits() -> void:
	if not image_data or image_data.size() == 0:
		return
	
	var data_to_use = image_data
	
	# If using clipping limits, pre-filter the data
	if use_clipping_limits:
		var filtered_data = PackedFloat32Array()
		for value in image_data:
			if value >= clip_min and value <= clip_max:
				filtered_data.append(value)
		
		if filtered_data.size() > 0:
			data_to_use = filtered_data
	
	# Calculate zscale limits on the (potentially filtered) data
	var limits = _calculate_zscale_limits(data_to_use, width, height, zscale_contrast, zscale_samples, zscale_samples_per_line)
	
	# Update shader parameters
	z_min = limits[0]
	z_max = limits[1]
	
	if shader_material:
		shader_material.set_shader_parameter("z_min", z_min)
		shader_material.set_shader_parameter("z_max", z_max)

func _apply_filter_trimming() -> void:
	# Apply hardcoded filter boundaries for alignment
	# F115W: trim above 1.3 microns
	# F150W: trim between 1.3 and 1.7 microns  
	# F200W: trim before 1.7 microns
	if not scaling or not scaling.has('left') or not scaling.has('right'):
		return
	
	var original_left = scaling['left']
	var original_right = scaling['right']
	var original_width_microns = original_right - original_left
	
	# Determine filter type based on wavelength range
	var new_left = original_left
	var new_right = original_right
	
	# F115W: left < 1.2, right covers ~1.3 region - trim above 1.3
	if original_left < 1.2 and original_right > 1.25:
		new_right = min(original_right, 1.3)
	
	# F150W: left >= 1.2, right <= 1.8 - trim below 1.3 and above 1.7
	elif original_left >= 1.2 and original_left < 1.35 and original_right <= 1.8:
		new_left = max(original_left, 1.3)
		new_right = min(original_right, 1.7)
	
	# F200W: left >= 1.6 - trim before 1.7
	elif original_left >= 1.6:
		new_left = max(original_left, 1.7)
	
	# Only trim if boundaries actually changed
	if abs(new_left - original_left) > 0.001 or abs(new_right - original_right) > 0.001:
		_trim_texture_data(new_left, new_right, original_left, original_right)
		
		# Update scaling to reflect new boundaries
		scaling['left'] = new_left
		scaling['right'] = new_right

func _trim_texture_data(new_left: float, new_right: float, original_left: float, original_right: float) -> void:
	# Trim the image_data array to remove pixels outside the new wavelength boundaries
	var original_width_microns = original_right - original_left
	var new_width_microns = new_right - new_left
	
	# Calculate pixel boundaries
	var left_trim_fraction = (new_left - original_left) / original_width_microns
	var right_trim_fraction = (original_right - new_right) / original_width_microns
	
	var pixels_to_trim_left = int(left_trim_fraction * width)
	var pixels_to_trim_right = int(right_trim_fraction * width)
	var new_width = width - pixels_to_trim_left - pixels_to_trim_right
	
	# Create new trimmed image data
	var new_image_data = PackedFloat32Array()
	new_image_data.resize(new_width * height)
	
	# Copy relevant pixels row by row
	for y in range(height):
		for x in range(new_width):
			var original_x = x + pixels_to_trim_left
			var old_index = y * width + original_x
			var new_index = y * new_width + x
			
			if old_index < image_data.size():
				new_image_data[new_index] = image_data[old_index]
	
	# Update image data and width
	image_data = new_image_data
	width = new_width

func _draw_histogram():
	if not image_data or image_data.size() == 0:
		return
	
	var hist_size = histogram_display.size
	if hist_size.x <= 0 or hist_size.y <= 0:
		return
	
	# Calculate histogram
	var num_bins = 100
	var min_val = image_data[0]
	var max_val = image_data[0]
	
	# Find data range
	for value in image_data:
		if is_finite(value):
			min_val = min(min_val, value)
			max_val = max(max_val, value)
	
	if max_val == min_val:
		max_val = min_val + 1.0
	
	var bin_width = (max_val - min_val) / num_bins
	var bins = []
	bins.resize(num_bins)
	for i in range(num_bins):
		bins[i] = 0
	
	# Fill histogram
	for value in image_data:
		if is_finite(value):
			var bin_idx = int((value - min_val) / bin_width)
			bin_idx = clamp(bin_idx, 0, num_bins - 1)
			bins[bin_idx] += 1
	
	# Find max count for scaling
	var max_count = 0
	for count in bins:
		max_count = max(max_count, count)
	
	if max_count == 0:
		return
	
	# Draw histogram
	var margin = 10
	var plot_width = hist_size.x - 2 * margin
	var plot_height = hist_size.y - 2 * margin
	var bin_pixel_width = plot_width / num_bins
	
	# Draw background
	histogram_display.draw_rect(Rect2(Vector2.ZERO, hist_size), Color.BLACK)
	
	# Draw histogram bars
	for i in range(num_bins):
		var bar_height = (bins[i] / float(max_count)) * plot_height
		var x = margin + i * bin_pixel_width
		var y = hist_size.y - margin - bar_height
		
		histogram_display.draw_rect(
			Rect2(x, y, bin_pixel_width - 1, bar_height),
			Color.WHITE
		)
	
	# Draw clipping limit lines if active
	if use_clipping_limits:
		var min_x = margin + ((clip_min - min_val) / (max_val - min_val)) * plot_width
		var max_x = margin + ((clip_max - min_val) / (max_val - min_val)) * plot_width
		
		# Draw min limit line
		histogram_display.draw_line(
			Vector2(min_x, margin),
			Vector2(min_x, hist_size.y - margin),
			Color.RED, 2
		)
		
		# Draw max limit line
		histogram_display.draw_line(
			Vector2(max_x, margin),
			Vector2(max_x, hist_size.y - margin),
			Color.RED, 2
		)
	
	# Draw labels
	var font = ThemeDB.fallback_font
	var font_size = 12
	
	# Min value label
	histogram_display.draw_string(
		font,
		Vector2(margin, hist_size.y - 2),
		"%.3f" % min_val,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)
	
	# Max value label
	histogram_display.draw_string(
		font,
		Vector2(hist_size.x - margin, hist_size.y - 2),
		"%.3f" % max_val,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		font_size,
		Color.WHITE
	)
