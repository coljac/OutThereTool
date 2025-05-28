extends Control
class_name OTImage

signal mouse_coords(Vector2)
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
			
		if res and "position_angle" in res:
			set_label(res.position_angle)
	_make_texture()

func set_label(t: String):
	$Label.text = t
	# show_label()
	
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
	# Approximation of the viridis colormap
	var r = clamp(0.267004 + 0.004334 * val + 0.609877 * pow(val, 2) - 0.291263 * pow(val, 3), 0.0, 1.0)
	var g = clamp(0.004974 + 0.856206 * val - 0.836809 * pow(val, 2) + 0.202110 * pow(val, 3), 0.0, 1.0)
	var b = clamp(0.329415 + 1.742050 * val - 3.090907 * pow(val, 2) + 1.852183 * pow(val, 3), 0.0, 1.0)
	return Color(r, g, b)

# Plasma colormap
func plasma_colormap(val: float) -> Color:
	# Approximation of the plasma colormap
	var r = clamp(0.050383 + 2.429896 * val - 2.969058 * pow(val, 2) + 0.871852 * pow(val, 3), 0.0, 1.0)
	var g = clamp(-0.164585 + 1.750407 * val - 0.505266 * pow(val, 2) - 0.827736 * pow(val, 3), 0.0, 1.0)
	var b = clamp(0.563629 + 0.232551 * val - 1.087553 * pow(val, 2) + 0.307658 * pow(val, 3), 0.0, 1.0)
	return Color(r, g, b)

# Inferno colormap
func inferno_colormap(val: float) -> Color:
	# Approximation of the inferno colormap
	var r = clamp(0.001462 + 1.385754 * val - 0.100330 * pow(val, 2) - 0.575560 * pow(val, 3), 0.0, 1.0)
	var g = clamp(0.000624 + 0.236365 * val + 0.338594 * pow(val, 2) - 0.370683 * pow(val, 3), 0.0, 1.0)
	var b = clamp(0.013866 + 0.068177 * val + 0.066156 * pow(val, 2) + 0.123915 * pow(val, 3), 0.0, 1.0)
	return Color(r, g, b)

# Magma colormap
func magma_colormap(val: float) -> Color:
	# Approximation of the magma colormap
	var r = clamp(0.001462 + 1.427008 * val - 0.470891 * pow(val, 2) - 0.106833 * pow(val, 3), 0.0, 1.0)
	var g = clamp(0.000363 + 0.121604 * val + 0.529396 * pow(val, 2) - 0.533976 * pow(val, 3), 0.0, 1.0)
	var b = clamp(0.013866 + 0.269113 * val - 0.103900 * pow(val, 2) - 0.055130 * pow(val, 3), 0.0, 1.0)
	return Color(r, g, b)

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
	
	# Set the new scale
	_set_scale_pc(new_scale)

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
	context_menu.add_separator()
	
	# Add invert option
	context_menu.add_item("Invert Colors", 4)
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

func _show_context_menu(global_pos: Vector2) -> void:
	# Update checkmarks for current settings
	_update_context_menu_checkmarks()
	
	# Show the context menu at the mouse position
	context_menu.popup(Rect2i(global_pos, Vector2i.ZERO))

func _update_context_menu_checkmarks() -> void:
	# Clear all checkmarks first
	for i in range(context_menu.get_item_count()):
		context_menu.set_item_checked(i, false)
	
	# Check the current scale option
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
	context_menu.set_item_checked(4, invert_color)
	
	# Update colormap submenu checkmarks
	for i in range(colormap_submenu.get_item_count()):
		colormap_submenu.set_item_checked(i, false)
	colormap_submenu.set_item_checked(color_map, true)

func _on_context_menu_item_selected(id: int) -> void:
	match id:
		0: # Scale 90%
			_set_scale_pc(90.0)
			current_scale_index = show_scales.find(90.0)
		1: # Scale 95%
			_set_scale_pc(95.0)
			current_scale_index = show_scales.find(95.0)
		2: # Scale 99%
			_set_scale_pc(99.0)
			current_scale_index = show_scales.find(99.0)
		3: # Scale 99.5%
			_set_scale_pc(99.5)
			current_scale_index = show_scales.find(99.5)
		4: # Invert
			invert_color = not invert_color

func _on_colormap_selected(colormap_id: int) -> void:
	color_map = colormap_id

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
