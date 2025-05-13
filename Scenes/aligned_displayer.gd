extends Control # or Node2D depending on your needs
class_name AlignedDisplayer
#


@export var left_boundary = 1.05 # left boundary in wavelength space, microns
@export var right_boundary = 2.5 # right boundary in wavelength space, microns
@export var plot_display_path: NodePath # Path to the PlotDisplay node
@export var show_cursor_line: bool = false # Whether to show a vertical line at the cursor position
@export var cursor_line_color: Color = Color(0.0, 0.0, 1.0, 1.0) # Color of the cursor line
@export var cursor_line_width: float = 2.0 # Width of the cursor line

var plot_display: PlotDisplay # Reference to the PlotDisplay node
var cursor_wavelength: float = 0.0 # Current wavelength position for the cursor line
var cursor_height: int = 70 #

func _ready():
	# Get reference to the PlotDisplay
	clip_contents = true

	if plot_display_path:
		plot_display = get_node(plot_display_path)
		if plot_display:
			# Connect to the x_limits_changed signal
			plot_display.x_limits_changed.connect(_on_plot_display_x_limits_changed)
			# Connect to the crosshair_moved signal
			plot_display.crosshair_moved.connect(_on_plot_display_crosshair_moved)
			# Initial sync with plot display
			_on_plot_display_x_limits_changed(plot_display.x_min, plot_display.x_max)
			
			# Set up to receive mouse movement updates
			set_process(true)
	for c in self.get_children():
		c.set_draw_behind_parent(true)
		

# Called when the plot display's crosshair position changes
func _on_plot_display_crosshair_moved(position: Vector2):
	if show_cursor_line:
		cursor_wavelength = position.x
		queue_redraw() # Request redraw to update the cursor line

# We can remove the _process method since we're now using signals
# func _process(_delta):
# 	if plot_display and show_cursor_line:
# 		# Update cursor position from plot display's crosshair position
# 		cursor_wavelength = plot_display.crosshair_position.x
# 		queue_redraw()  # Request redraw to update the cursor line

func _draw():
	if show_cursor_line and cursor_wavelength >= left_boundary and cursor_wavelength <= right_boundary:
		# Convert wavelength to pixel position
		var x_pixel = _microns_to_pixels(cursor_wavelength)
		
		#cursor_height = get_children()[0].get_children()[0].height # texture.get_height()
		# Draw vertical line
		draw_line(
			Vector2(x_pixel, 0),
			Vector2(x_pixel, cursor_height), # .y/2.0),
			cursor_line_color,
			cursor_line_width
		)

# Called when the plot display's x-axis limits change
func _on_plot_display_x_limits_changed(new_x_min: float, new_x_max: float):
	left_boundary = new_x_min
	right_boundary = new_x_max
	position_textures() # Reposition and rescale all textures
	queue_redraw() # Redraw to update cursor line position

func _microns_to_pixels(microns: float) -> int:
	if plot_display:
		# Convert wavelength to plot coordinates
		var plot_point = Vector2(microns, 0)
		# Convert plot coordinates to pixel coordinates
		var pixel_point = plot_display.plot_to_pixel(plot_point)
		# Return the x-coordinate
		return int(pixel_point.x)
	else:
		# Fallback to the original implementation
		push_error("No plot display defined on Galaxy display.")
		print_debug("Viewport: ", get_viewport().size.x, " w: ")
		var x_pixel = int((microns - left_boundary) / (right_boundary - left_boundary) * get_viewport().size.x)
		return x_pixel

func position_textures():
	for child in get_children():
		var f = child as FitsImage
		if f and f.visible and f.scaling and f.fits_img.texture: #TODO

			# Calculate the pixel positions for the left and right boundaries of the image
			var left_pixel = _microns_to_pixels(f.scaling['left'])
			var right_pixel = _microns_to_pixels(f.scaling['right'])
			var pixel_width = right_pixel - left_pixel
			
			# Calculate the scale factor to make the image fit the pixel width
			var scale = float(f.fits_img.texture.get_width()) / max(1, pixel_width)
			
			# print(f.fits_img.texture.get_width())
			# print(f.scaling['left'], " -> ", f.scaling['right'])
			# print(_microns_to_pixels(1.0), ",", _microns_to_pixels(1.7), ",", _microns_to_pixels(2.5))
			# print("Scale: ", scale, "  ", 1.0 / scale)
			
			# Apply the scale and position
			f.scale.x = 1.0 / scale
			f.position.x = left_pixel
			
			# print("Texture width: ", f.fits_img.texture.get_width())
	#
	## Define your x positions
	#var x1 = 100  # Left boundary
	#var x2 = 500  # Right boundary
	#
	## For the first texture
	#var microns_left = 2.5
	#var texture_width = texture_rect1.texture.get_width()
	#var scale_factor = 1.0  # Adjust as needed
	#
	## Set position and scale
	## texture_rect1.size.x = texture_width * scale_factor
	#texture_rect1.position.x = _microns_to_pixels(texture_rect1.scaling['left']) - texture_width/ 2.0
	#
	## For the second texture 
	## (adjust patterns for however many textures you have)
	#texture_width = texture_rect2.texture.get_width()
	#scale_factor = 1.0  # Adjust for this texture
	#
	#texture_rect2.size.x = texture_width * scale_factor
	#texture_rect2.position.x = x2 - texture_rect2.size.x  # Right-aligned at x2


func position_multiple_textures(texture_rects, x1, x2):
	var total_width = x2 - x1
	var spacing = 10 # Optional spacing between textures
	
	# Calculate available width for all textures
	var available_width = total_width - (spacing * (texture_rects.size() - 1))
	
	var current_x = x1
	for rect in texture_rects:
		# Set texture scale as needed
		var scale_factor = 1.0 # Calculate your scale factor here
		var texture_width = rect.texture.get_width() * scale_factor
		
		rect.size.x = texture_width
		rect.position.x = current_x
		
		current_x += texture_width + spacing
