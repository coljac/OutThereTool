extends Control # or Node2D depending on your needs
class_name AlignedDisplayer

@export var left_boundary = 1.05 # left boundary in wavelength space, microns
@export var right_boundary = 2.5 # right boundary in wavelength space, microns
@export var plot_display_path: NodePath # Path to the PlotDisplay node
@export var show_cursor_line: bool = false # Whether to show a vertical line at the cursor position
@export var cursor_line_color: Color = Color(0.0, 0.0, 1.0, 1.0) # Color of the cursor line
@export var cursor_line_width: float = 2.0 # Width of the cursor line
@export var max_rows: int = 3 # Maximum number of rows to use
@export var row_spacing: float = 5.0 # Spacing between rows
@export var max_y_scale: float = 2.0 # Maximum y-scale factor

var plot_display: PlotDisplay # Reference to the PlotDisplay node
var cursor_wavelength: float = 0.0 # Current wavelength position for the cursor line
var cursor_height: int = 0 # Height for cursor line, calculated based on displayed images
var row_heights: Array[float] = [] # Heights for each row
var rows: Array[Array] = [] # Array of arrays containing children organized by row
var row_labels: Array[Label] = [] # Label nodes for each row

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
	
	for c in get_children():
		c.set_draw_behind_parent(true)
	
	# Handle resizing
	resized.connect(_on_resized)
	
	# Organize children into rows and calculate row heights
	organize_rows()

func add_spectrum(spectrum: OTImage, row: int = -1) -> void:
	# Add a spectrum to the display
	if row == -1:
		row = rows.size() - 1 # Default to the last row
	
	# Ensure we have enough rows
	while row >= rows.size():
		rows.append([])
		row_heights.append(0.0)
	
	if row >= 0:
		# If the spectrum is not already a child, add it
		if not spectrum.is_inside_tree() or spectrum.get_parent() != self:
			add_child(spectrum)
		
		# Add to the appropriate row
		rows[row].append(spectrum)
		spectrum.set_draw_behind_parent(true)
		
		# Update row height if needed
		if spectrum.height > row_heights[row]:
			row_heights[row] = spectrum.height
		
		# Don't position immediately - will be done in position_textures()
		queue_redraw() # Request redraw to update the display


# Organize children into rows
func organize_rows() -> void:
	rows.clear()
	row_heights.clear()
	# Clear labels when reorganizing
	clear_labels()
	
	# Get all visible OTImage children
	var visible_children = []
	for child in get_children():
		var img = child as OTImage
		if img and is_instance_valid(img) and img.visible and img.scaling and img.fits_img.texture:
			visible_children.append(img)
	
	if visible_children.size() == 0:
		return
	
	# Calculate how many rows we need (up to max_rows)
	var num_rows = min(max_rows, max(1, visible_children.size()))
	
	# Initialize rows arrays
	for i in range(num_rows):
		rows.append([])
		row_heights.append(0.0)
	
	# Distribute children to rows
	# Try to keep children with similar wavelength ranges in the same row
	var children_by_wavelength = visible_children.duplicate()
	children_by_wavelength.sort_custom(func(a, b):
		if not is_instance_valid(a) or not is_instance_valid(b) or not a.scaling or not b.scaling:
			return false
		return a.scaling['left'] < b.scaling['left']
	)
	
	# Distribute children evenly across rows
	var items_per_row = ceil(float(visible_children.size()) / num_rows)
	for i in range(children_by_wavelength.size()):
		var row_index = min(floor(i / items_per_row), num_rows - 1)
		rows[row_index].append(children_by_wavelength[i])
		
		# Update row height (will be used for scaling)
		if children_by_wavelength[i].height > row_heights[row_index]:
			row_heights[row_index] = children_by_wavelength[i].height
	
	# The cursor should span the entire height of the control
	cursor_height = size.y

# Called when the control is resized
func _on_resized() -> void:
	position_textures()
	_position_labels()
	queue_redraw()

# Called when the plot display's crosshair position changes
func _on_plot_display_crosshair_moved(position: Vector2):
	if show_cursor_line:
		cursor_wavelength = position.x
		queue_redraw() # Request redraw to update the cursor line

func _draw():
	if show_cursor_line and cursor_wavelength >= left_boundary and cursor_wavelength <= right_boundary:
		# Convert wavelength to pixel position
		var x_pixel = _microns_to_pixels(cursor_wavelength)
		
		# Draw vertical line
		draw_line(
			Vector2(x_pixel, 0),
			Vector2(x_pixel, size.y),
			cursor_line_color,
			cursor_line_width
		)

# Called when the plot display's x-axis limits change
func _on_plot_display_x_limits_changed(new_x_min: float, new_x_max: float):
	left_boundary = new_x_min
	right_boundary = new_x_max
	# organize_rows() # Re-organize the rows when limits change
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
		# Calculate the pixel position based on the wavelength range and control size
		var plot_width = size.x
		var x_pixel = int((microns - left_boundary) / (right_boundary - left_boundary) * plot_width)
		return x_pixel

func position_textures():
	# Skip if rows are not organized yet
	if rows.size() == 0:
		organize_rows()
		if rows.size() == 0:
			return
	
	# Calculate available height per row
	var available_height = size.y
	var total_spacing = (rows.size() - 1) * row_spacing
	var height_per_row = (available_height - total_spacing) / rows.size()
	
	var current_y_pos = 0.0
	
	# Position textures in each row
	for row_index in range(rows.size()):
		var row_children = rows[row_index]
		
		# Skip empty rows
		if row_children.size() == 0:
			current_y_pos += height_per_row + row_spacing
			continue
		
		# Sort children by wavelength range for better organization
		row_children.sort_custom(func(a, b):
			if not is_instance_valid(a) or not is_instance_valid(b) or not a.scaling or not b.scaling:
				return false
			return a.scaling['left'] < b.scaling['left']
		)
		
		for child in row_children:
			var f = child as OTImage
			if not f or not is_instance_valid(f) or not f.scaling or not f.scaling.has('left') or not f.scaling.has('right'):
				continue
			
			# Calculate the pixel positions for the left and right boundaries of the image
			var left_pixel = _microns_to_pixels(f.scaling['left'])
			var right_pixel = _microns_to_pixels(f.scaling['right'])
			var pixel_width = max(1, right_pixel - left_pixel)
			
			# Calculate x scale to fit the wavelength range precisely
			# The issue is that we need to ensure the image width exactly matches the pixel width
			var texture_width = f.fits_img.texture.get_width() if f.fits_img.texture else f.width
			var x_scale = float(pixel_width) / texture_width
			
			# Apply the x scale - we want to stretch the image to match the wavelength range
			f.scale.x = x_scale
			# print("----" , pixel_width, ", ", texture_width, ", ", x_scale, ", ",
				# f.scaling['left'], ", ", f.scaling['right'], ", ", left_pixel, ", ", right_pixel)
			# print(left_pixel, ", ", texture_width*x_scale, ", ", right_pixel)
			# Calculate y scale to fill the row height (up to max_y_scale)
			var target_height = min(height_per_row, f.height * max_y_scale)
			var y_scale = target_height / f.height
			
			# Ensure a reasonable minimum scale
			f.scale.y = max(0.2, y_scale)
			
			# Apply a consistent size for better readability
			if height_per_row > 40: # Only if we have enough space
				f.scale.y = max(f.scale.y, 0.5)
			
			# Position the image
			f.position.x = left_pixel
			# if row_index > 0:
				# f.position.x = left_pixel + texture_width
				
			f.position.y = current_y_pos
		
		# Move to next row
		current_y_pos += height_per_row + row_spacing
	
	# Apply overlap clipping after positioning and scaling
	apply_overlap_clipping()

func apply_overlap_clipping() -> void:
	# Clip overlapping images at their midpoints to eliminate visual overlap
	for row_index in range(rows.size()):
		var row_children = rows[row_index]
		
		if row_children.size() <= 1:
			# Reset any existing clipping for single images
			for child in row_children:
				var img = child as OTImage
				if img:
					reset_image_clipping(img)
			continue
		
		# Process each pair of adjacent images in wavelength order
		for i in range(row_children.size() - 1):
			var current_img = row_children[i] as OTImage
			var next_img = row_children[i + 1] as OTImage
			
			if not current_img or not next_img or not current_img.scaling or not next_img.scaling:
				continue
			
			# Check if images overlap in wavelength space
			var current_right = current_img.scaling['right']
			var next_left = next_img.scaling['left']
			
			if current_right > next_left:
				# Images overlap - calculate midpoint for clipping
				var midpoint = (current_right + next_left) / 2.0
				
				# Clip the current image's right side at the midpoint
				clip_image_right(current_img, midpoint)
				
				# Clip the next image's left side at the midpoint  
				clip_image_left(next_img, midpoint)

func reset_image_clipping(img: OTImage) -> void:
	# Reset any clipping on an image
	if not img or not img.fits_img:
		return
	
	# Create a clipping Control node if it doesn't exist
	var clipper = img.get_node_or_null("Clipper")
	if clipper:
		# Remove the clipping wrapper and restore original structure
		var texture_rect = clipper.get_node_or_null("FitsImageShow")
		if texture_rect:
			clipper.remove_child(texture_rect)
			img.add_child(texture_rect)
			texture_rect.name = "FitsImageShow"
			img.fits_img = texture_rect
		clipper.queue_free()

func clip_image_right(img: OTImage, clip_wavelength: float) -> void:
	# Clip the right side of an image at the specified wavelength using Control clipping
	if not img or not img.fits_img or not img.fits_img.texture or not img.scaling:
		return
	
	var img_left = img.scaling['left']
	var img_right = img.scaling['right']
	var img_width_wavelength = img_right - img_left
	
	# Calculate what fraction of the image to keep (from left edge to clip point)
	var keep_fraction = (clip_wavelength - img_left) / img_width_wavelength
	keep_fraction = clamp(keep_fraction, 0.0, 1.0)
	
	# Create or get clipping wrapper
	var clipper = setup_clipper(img)
	
	# Set the clipper size to show only the fraction we want to keep
	var original_width = img.fits_img.texture.get_width() * img.scale.x
	clipper.size.x = original_width * keep_fraction
	clipper.size.y = img.fits_img.texture.get_height() * img.scale.y
	
	# Update the image's scaling to reflect the new boundaries
	img.scaling['right'] = clip_wavelength

func clip_image_left(img: OTImage, clip_wavelength: float) -> void:
	# Clip the left side of an image at the specified wavelength using Control clipping
	if not img or not img.fits_img or not img.fits_img.texture or not img.scaling:
		return
	
	var img_left = img.scaling['left']
	var img_right = img.scaling['right']
	var img_width_wavelength = img_right - img_left
	
	# Calculate what fraction of the image to remove from the left
	var remove_fraction = (clip_wavelength - img_left) / img_width_wavelength
	remove_fraction = clamp(remove_fraction, 0.0, 1.0)
	
	# Create or get clipping wrapper
	var clipper = setup_clipper(img)
	
	# Move the texture rect to the left to hide the portion we want to clip
	var original_width = img.fits_img.texture.get_width() * img.scale.x
	img.fits_img.position.x = -original_width * remove_fraction
	
	# Set clipper size to show only the remaining portion
	clipper.size.x = original_width * (1.0 - remove_fraction)
	clipper.size.y = img.fits_img.texture.get_height() * img.scale.y
	
	# Update the image's scaling to reflect the new boundaries
	img.scaling['left'] = clip_wavelength
	
	# Adjust the image position to account for the clipped left portion
	var left_pixel = _microns_to_pixels(clip_wavelength)
	img.position.x = left_pixel

func setup_clipper(img: OTImage) -> Control:
	# Create a Control node that will clip its contents
	var clipper = img.get_node_or_null("Clipper")
	
	if not clipper:
		clipper = Control.new()
		clipper.name = "Clipper"
		clipper.clip_contents = true
		
		# Move the texture rect into the clipper
		var texture_rect = img.fits_img
		img.remove_child(texture_rect)
		clipper.add_child(texture_rect)
		img.add_child(clipper)
		
		# Reset texture rect position
		texture_rect.position = Vector2.ZERO
		
		# Update reference
		img.fits_img = texture_rect
	
	return clipper

func clear_labels() -> void:
	# Remove all existing row labels
	for label in row_labels:
		if is_instance_valid(label):
			label.queue_free()
	row_labels.clear()

func set_label(row: int, text: String) -> void:
	# Ensure we have enough labels
	while row >= row_labels.size():
		var new_label = Label.new()
		new_label.add_theme_color_override("font_color", Color.WHITE)
		new_label.add_theme_font_size_override("font_size", 44)
		new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(new_label)
		# Ensure labels draw in front of other children
		new_label.z_index = 100
		row_labels.append(new_label)
	
	# Set the text for the specified row
	if row < row_labels.size():
		row_labels[row].text = text
		_position_labels()

func _position_labels() -> void:
	# Position labels at the left edge of each row
	if rows.size() == 0:
		return
	
	var available_height = size.y
	var total_spacing = (rows.size() - 1) * row_spacing
	var height_per_row = (available_height - total_spacing) / rows.size()
	var current_y_pos = 0.0
	
	for i in range(min(row_labels.size(), rows.size())):
		if is_instance_valid(row_labels[i]):
			row_labels[i].position.x = 5 # Small margin from the left edge
			row_labels[i].position.y = current_y_pos + (height_per_row / 2) - (row_labels[i].size.y / 2)
			row_labels[i].size.x = 0 # Let it auto-size based on text
		
		current_y_pos += height_per_row + row_spacing
