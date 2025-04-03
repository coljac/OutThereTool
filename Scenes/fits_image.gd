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

@onready var fits_img: TextureRect = $FitsImageShow

var fits: FITSReader
var region_manager: RegionManager
var width: int = 0
var height: int = 0
var hdu: int = 1


var RA: float = 0.0
var dec: float = 0.0

var current_hdu = 1

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# region_manager = RegionManager.new()
	#add_child(region_manager)
	gui_input.connect(_on_gui_input)
	if fits_path:
		_load_fits()
	$Label.text = ""

# func _on_mouse_entered():
	# print("Mouse entered the TextureRect")
# 
# func _on_mouse_exited():
	# print("Mouse exited the TextureRect")

func set_label(s: String):
	$Label.text = s
func _on_gui_input(event):
	if event is InputEventMouseMotion:
		# Handle mouse movement
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.is_double_click():
					_set_scale_pc(99.5)
				else:
					scale_percent += 0.5
					if scale_percent > 99.5:
						scale_percent = 90
					_set_scale_pc(scale_percent)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				invert_color = not invert_color
				
				
func _handle_mouse_motion(event: InputEventMouseMotion):
	if is_2d_spectrum:
		return
	# Get local mouse position relative to the TextureRect
	var local_pos = event.position
	
	# Get the coordinates as a ratio of the texture size (0-1 range)
	var normalized_pos = Vector2(
		local_pos.x / size.x,
		local_pos.y / size.y
	)
	
		#if event is InputEventMouseMotion:
		#var local_pos = to_local(event.position)
	if get_rect().has_point(local_pos):
		#print(local_pos, fits.pixel_to_world(0, 0))
		var sky_pos: Vector2 = fits.pixel_to_world(local_pos.x + width / 2, height / 2 - local_pos.y)
		emit_signal("mouse_coords", sky_pos)
			
	
	#print("Mouse position: ", local_pos, " Normalized: ", normalized_pos)
	
	
func _load_fits():
	if fits_path:
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
	
func set_image(file_path: String):
	fits_path = file_path
	_load_fits()
	
func _make_texture():
	if fits:
		fits_img.texture = display_fits_image(fits.get_image_data_normalized(hdu), width, height, black_level, white_level)
	
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
		img.set_pixel(x, y, Color(val, val, val))
	
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
