extends Control
class_name FitsImage

signal mouse_coords(Vector2)
#@export var fits_file: String
@export_range(0.0, 1.0) var black_level: float = 0.0: set = _set_black
@export var white_level: float = 100.0: set = _set_white
@export_file("*.fits") var fits_path: set = _set_file
@export_range(90, 99.5, 0.5) var scale_percent: float = 99.5: set = _set_scale_pc
@export var invert_color: bool = false: set = _set_invert
@export var is_2d_spectrum: bool = false
@export var scaling = {"left": - 1.0, "right": 10.0}
enum ColorMap {GRAYSCALE, VIRIDIS, PLASMA, INFERNO, MAGMA, JET, HOT, COOL, RAINBOW}
@export var color_map: ColorMap = ColorMap.GRAYSCALE: set = _set_colormap

@onready var fits_img: TextureRect = $FitsImageShow

var fits: FITSReader
var region_manager: RegionManager
var width: int = 0
var height: int = 0
var hdu: int = 1

# Variables for shader control
var is_dragging: bool = false
var drag_start_position: Vector2 = Vector2.ZERO
var shader_material: ShaderMaterial
var z_min: float = 0.0
var z_max: float = 1.0


var RA: float = 0.0
var dec: float = 0.0

var current_hdu = 1

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process(false) # Disable _process by default
	# region_manager = RegionManager.new()
	#add_child(region_manager)
	gui_input.connect(_on_gui_input)
	if fits_path:
		_load_fits()
	$Label.text = ""
	
	# Initialize shader
	_init_shader()

# func _on_mouse_entered():
	# print("Mouse entered the TextureRect")
# 
# func _on_mouse_exited():
	# print("Mouse exited the TextureRect")

func set_label(s: String):
	$Label.text = s

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
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.is_double_click():
					_set_scale_pc(99.5)
					_reset_shader()
				else:
					# Start dragging
					is_dragging = true
					drag_start_position = event.position
			else:
				# Stop dragging on release
				is_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			invert_color = not invert_color


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
	
	if get_rect().has_point(local_pos):
		if fits:
			var sky_pos: Vector2 = fits.pixel_to_world(local_pos.x + width / 2, height / 2 - local_pos.y)
			emit_signal("mouse_coords", sky_pos)
	
func _load_fits(fits: FITSReader = null) -> void:
	if fits_path or fits:
		if not fits:
			fits = FITSReader.new()
		
		if fits.load_fits(str(fits_path)): # .substr(6, -1)): # TODO res://
			#print("FITS file loaded")
			var header = fits.get_header_info(hdu)
			#print("Header info: ", header)
			#var data = fits.get_image_data()
			#print("Got image data of size: ", data.size())

			width = int(header['NAXIS1'])
			height = int(header['NAXIS2'])
			white_level = get_percentile(fits.get_image_data_normalized(hdu), 95.5)
			#print(log(fits.get_image_data(hdu)[0])/log(10))

			#var black_level = 0.0
			#var white_level = get_percentile(float_data, 99.5)
			_make_texture() # var tex = display_fits_image(fits.get_image_data(), width, height, black_level, white_level)
			#texture = tex
			#fits.read_spectrum()
			# print(fits.pixel_to_world(50, 50))
			if is_2d_spectrum:
				var crpix = float(header['CRPIX1'])
				var crval = float(header['CRVAL1'])
				var cdelt = float(header['CD1_1'])
				scaling = {"left": - crpix * cdelt + crval, "right": (width - crpix) * cdelt + crval}

func _set_file(file: String):
	fits_path = file
	_load_fits()
	
func set_image(file_path: String, image_hdu: int = 1):
	hdu = image_hdu
	fits_path = file_path
	_load_fits()

func set_image_data(image_data: PackedFloat32Array, image_hdu: int = 1):
	hdu = image_hdu
	width = int(fits.get_header_info(hdu)['NAXIS1'])
	height = int(fits.get_header_info(hdu)['NAXIS2'])
	white_level = get_percentile(fits.get_image_data_normalized(hdu), 95.5)
	_make_texture()


func _make_texture():
	if fits:
		fits_img.texture = display_fits_image(fits.get_image_data_normalized(hdu), width, height, black_level, white_level)
		# Re-apply shader after texture update
		_init_shader()
	
func _set_scale_pc(p: float):
	scale_percent = p
	if fits:
		white_level = get_percentile(fits.get_image_data_normalized(hdu), p)
		_make_texture()
	
func _set_black(b: float):
	black_level = b
	if fits:
		_make_texture()
	
func _set_white(w: float):
	white_level = w
	if fits:
		_make_texture()

func _set_invert(i: bool):
	invert_color = i
	if fits:
		_make_texture()

func _set_colormap(cm: ColorMap):
	color_map = cm
	if fits:
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
	
func get_percentile(data: PackedFloat32Array, percentile: float) -> float:
	var sorted_data = data.duplicate()
	sorted_data.sort()
	var idx = int(ceil(percentile / 100.0 * sorted_data.size())) - 1
	return sorted_data[idx]

func display_fits_image(float_data: PackedFloat32Array, width: int, height: int, black_level: float, white_level: float) -> ImageTexture:
	var img = Image.create(width, height, false, Image.FORMAT_RGBAF)
	var inv_range = 1.0 / max(0.000001, white_level - black_level)

	for i in range(width * height):
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

#func _input(event):
	#if event is InputEventMouseMotion:
		#var local_pos = to_local(event.position)
		#if get_rect().has_point(local_pos):
			##print(local_pos, fits.pixel_to_world(0, 0))
			#var sky_pos: Vector2 = fits.pixel_to_world(local_pos.x + width/2, height/2 - local_pos.y)
			#emit_signal("mouse_coords", sky_pos)

# Add these methods for region handling
func load_region_file(path: String) -> void:
	print("load region")
	if not fits:
		print("FITS data must be loaded before loading regions")
		return
	region_manager.load_region_file(path)

func add_region(type: String, coord_format: String, coords: Array, attributes: Dictionary = {}) -> void:
	print("add region")
	if not fits:
		print("FITS data must be loaded before adding regions")
		return
	region_manager.add_region(type, coord_format, coords, attributes)

func clear_regions() -> void:
	print("clr")
	if region_manager:
		region_manager.clear_regions()
