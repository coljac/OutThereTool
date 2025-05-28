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
var label_overlay: Control # Overlay container for spectrum labels
var spectrum_labels: Array[Label] = [] # Label nodes for each spectrum

func _ready():
	# Get reference to the PlotDisplay
	clip_contents = true
	# Allow mouse events to pass through to children
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Ensure this control draws on top for cursor line
	z_index = 100
	
	# Create label overlay
	_setup_label_overlay()

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
	
	# Removed set_draw_behind_parent to fix input handling
	
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
		# Removed set_draw_behind_parent to fix input handling
		
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
	clear_spectrum_labels()
	
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
	update_all_spectrum_labels()
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
	
	# Update spectrum label positions after repositioning
	update_all_spectrum_labels()
	
	# Note: Clipping is now handled by texture trimming in OTImage

# Clipping logic removed - now handled by texture trimming in OTImage

func _setup_label_overlay() -> void:
	# Create overlay container that sits above all spectrum images
	label_overlay = Control.new()
	label_overlay.name = "LabelOverlay"
	label_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE # Allow clicks to pass through
	label_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label_overlay)
	# Set moderate z_index so cursor line can still draw on top
	label_overlay.z_index = 50

func clear_spectrum_labels() -> void:
	# Remove all existing spectrum labels
	for label in spectrum_labels:
		if is_instance_valid(label):
			label.queue_free()
	spectrum_labels.clear()
	
	# Don't destroy the overlay itself, just clear its children
	if is_instance_valid(label_overlay):
		for child in label_overlay.get_children():
			child.queue_free()

func add_spectrum_label(spectrum: OTImage, text: String) -> void:
	# Ensure label overlay exists and is valid
	if not is_instance_valid(label_overlay):
		_setup_label_overlay()
	
	print("Adding spectrum label: ", text)
	
	# Create a new label for this spectrum
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	
	# Add to overlay, not to the aligned displayer directly
	label_overlay.add_child(label)
	spectrum_labels.append(label)
	
	print("Label added, positioning at spectrum pos: ", spectrum.position)
	
	# Position the label at the spectrum's top-left corner
	_position_spectrum_label(spectrum, label)

func _position_spectrum_label(spectrum: OTImage, label: Label) -> void:
	if not is_instance_valid(spectrum) or not is_instance_valid(label):
		return
	
	# Calculate where the spectrum's top-left corner appears in our coordinate space
	var spectrum_pos = spectrum.position
	
	# Position label with small offset from spectrum's top-left
	label.position.x = spectrum_pos.x + 5
	label.position.y = spectrum_pos.y + 5

func update_all_spectrum_labels() -> void:
	# Update positions of all spectrum labels after layout changes
	if not is_instance_valid(label_overlay):
		return
		
	var label_index = 0
	for row in rows:
		for spectrum in row:
			if label_index < spectrum_labels.size() and is_instance_valid(spectrum_labels[label_index]):
				_position_spectrum_label(spectrum, spectrum_labels[label_index])
			label_index += 1
