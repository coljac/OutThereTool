@tool
extends Control
class_name PlotDisplay
# Signals for mouse clicks in plot space
signal plot_left_clicked(position: Vector2)
signal plot_right_clicked(position: Vector2)
# Signal for when x-axis limits change
signal crosshair_moved(position: Vector2)
signal x_limits_changed(x_min: float, x_max: float)
signal zoomed

@export_category("Limits")
# Plot space limits
@export var x_min: float = 0.0
@export var x_max: float = 10.0
@export var y_min: float = 0.0
@export var y_max: float = 10.0

# Store original limits for reset
var original_x_min: float = 0.0
var original_x_max: float = 10.0
var original_y_min: float = 0.0
var original_y_max: float = 10.0
var original_x_tick_spacing: float = 1.0
var original_y_tick_spacing: float = 1.0

@export_category("Margins")
# Margins for axes and title
@export var margin_left: float = 60.0
@export var margin_right: float = 20.0
@export var margin_top: float = 40.0
@export var margin_bottom: float = 60.0

@export_category("Colours")
@export var plot_area_color: Color = Color.WHITE
@export var axes_area_color: Color = Color(0.95, 0.95, 0.95)

@export_category("Crosshair")
# Crosshair cursor properties
@export var show_crosshair: bool = false
@export var crosshair_color: Color = Color(0.5, 0.5, 0.5, 0.7)
@export var crosshair_line_width: float = 1.0
@export var crosshair_label_font_size: int = 12
var crosshair_position: Vector2 = Vector2.ZERO
var is_mouse_in_plot: bool = false

@export_category("Box")
# Box selection properties
var is_selecting: bool = false
var selection_start: Vector2 = Vector2.ZERO
var selection_end: Vector2 = Vector2.ZERO
var selection_color: Color = Color(0.3, 0.6, 1.0, 0.3)
var selection_border_color: Color = Color(0.2, 0.5, 0.9, 0.8)

@export_category("Axis properties")
# Axis properties
@export var show_axes: bool = true
@export var show_grid: bool = true
@export var x_tick_spacing: float = 1.0
@export var y_tick_spacing: float = 1.0
@export var x_tick_decimals: int = 1
@export var y_tick_decimals: int = 1
@export var tick_size: float = 5.0
@export var grid_color: Color = Color(0.8, 0.8, 0.8, 0.5)
@export var axis_color: Color = Color(0.2, 0.2, 0.2)
@export var tick_label_font_size: int = 12

@export_category("Labels")
# Title and axis label properties
@export var title: String = "Plot Title"
@export var title_font_size: int = 16
@export var x_label: String = ""
@export var y_label: String = ""
@export var axis_label_font_size: int = 14
@export var y_label_rotation: float = -90.0 # Rotated 90 degrees counter-clockwise
#
#@export_category("Misc")
#@export var show_lines: bool = false

# Series container
var series_list = []
var annotations = []
var constant_lines = []

# Internal nodes
var plot_area: Control
var title_label: Label
var x_axis_container: Control
var y_axis_container: Control


func _ready():
	# Create child nodes if they don't exist
	if Engine.is_editor_hint():
		return
	set_process(false) # Disable _process by default
		
	# Create plot area
	if not has_node("PlotArea"):
		plot_area = Control.new()
		plot_area.name = "PlotArea"
		add_child(plot_area)
	else:
		plot_area = get_node("PlotArea")
	
	# Create title label
	if not has_node("TitleLabel"):
		title_label = Label.new()
		title_label.name = "TitleLabel"
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(title_label)
	else:
		title_label = get_node("TitleLabel")
	
	# Create axis containers
	if not has_node("XAxisContainer"):
		x_axis_container = Control.new()
		x_axis_container.name = "XAxisContainer"
		add_child(x_axis_container)
	else:
		x_axis_container = get_node("XAxisContainer")
	
	if not has_node("YAxisContainer"):
		y_axis_container = Control.new()
		y_axis_container.name = "YAxisContainer"
		add_child(y_axis_container)
	else:
		y_axis_container = get_node("YAxisContainer")
	
	# Store original limits
	original_x_min = x_min
	original_x_max = x_max
	original_y_min = y_min
	original_y_max = y_max
	original_x_tick_spacing = x_tick_spacing
	original_y_tick_spacing = y_tick_spacing
	
	# Enable mouse input for crosshair and selection
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Update the display
	update_display()

# Handle mouse input for crosshair and box selection
func _input(event):
	if Engine.is_editor_hint():
		return
	
	var plot_rect = get_plot_rect()
	var local_mouse_pos = get_local_mouse_position()
	var is_in_plot = false
	if plot_rect.abs() == plot_rect:
		#print(plot_rect)
	#if local_mouse_pos.abs() == local_mouse_pos:
		is_in_plot = plot_rect.has_point(local_mouse_pos)
	
	# Handle mouse motion
	if event is InputEventMouseMotion:
		# Update crosshair position
		if is_in_plot:
			is_mouse_in_plot = true
			crosshair_position = pixel_to_plot(local_mouse_pos)
			emit_signal("crosshair_moved", crosshair_position)
			queue_redraw() # Ensure the display updates with the new crosshair position
		elif is_mouse_in_plot:
			is_mouse_in_plot = false
			queue_redraw() # Ensure the display updates when mouse leaves the plot
		
		# Update selection box if selecting
		if is_selecting and is_in_plot:
			selection_end = pixel_to_plot(local_mouse_pos)
			queue_redraw()
	
	# Handle mouse button press
	elif event is InputEventMouseButton:
		if is_in_plot:
			# Get plot coordinates for the mouse position
			var plot_coords = pixel_to_plot(local_mouse_pos)
			
			# Left button press - start selection and emit signal
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					# Emit signal with plot coordinates
					emit_signal("plot_left_clicked", plot_coords)
					
					# Start selection
					is_selecting = true
					selection_start = plot_coords
					selection_end = selection_start
				else:
					# End selection and zoom if area is large enough
					if is_selecting:
						is_selecting = false
						var min_size = 5.0 # Minimum size in pixels to consider a valid selection
						var start_pixel = plot_to_pixel(selection_start)
						var end_pixel = plot_to_pixel(selection_end)
						var selection_size = (end_pixel - start_pixel).abs()
						
						if selection_size.x > min_size and selection_size.y > min_size:
							zoom_to_selection()
							zoomed.emit()
						
						queue_redraw()
			
			# Right button press - reset zoom and emit signal
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				# Emit signal with plot coordinates
				emit_signal("plot_right_clicked", plot_coords)
				
				reset_zoom()
				queue_redraw()

func _process(_delta):
	if Engine.is_editor_hint():
		queue_redraw()

func _draw():
	if not is_inside_tree():
		return
	
	# Draw background
	draw_rect(Rect2(0, 0, size.x, size.y), axes_area_color)
	
	# Draw plot area background
	var plot_rect = get_plot_rect()
	draw_rect(plot_rect, plot_area_color)
	
	# Draw grid if enabled
	if show_grid:
		draw_grid(plot_rect)
	
	# Draw axes if enabled
	if show_axes:
		draw_axes(plot_rect)
	
	# Draw constant lines
	draw_constant_lines(plot_rect)
	
	# Draw all series
	draw_series(plot_rect)
	
	# Draw annotations
	draw_annotations(plot_rect)
	
	# Draw selection box if selecting
	if is_selecting:
		draw_selection_box(plot_rect)
	
	# Draw crosshair if enabled and mouse is in plot
	if show_crosshair and is_mouse_in_plot:
		draw_crosshair(plot_rect)
	
	# Update title
	if title_label:
		title_label.text = title
		title_label.position.x = margin_left
		title_label.size.x = plot_rect.size.x
		title_label.position.y = 10
		title_label.add_theme_font_size_override("font_size", title_font_size)

# Get the rectangle representing the plot area
# Sometimes its negative, TODO
func get_plot_rect() -> Rect2:
	return Rect2(
		margin_left,
		margin_top,
		size.x - margin_left - margin_right,
		size.y - margin_top - margin_bottom
	)

# Convert plot coordinates to pixel coordinates
func plot_to_pixel(plot_point: Vector2) -> Vector2:
	var plot_rect = get_plot_rect()
	
	var x_ratio = (plot_point.x - x_min) / (x_max - x_min)
	var y_ratio = (plot_point.y - y_min) / (y_max - y_min)
	
	# Invert y-axis (pixel coordinates increase downward)
	y_ratio = 1.0 - y_ratio
	
	return Vector2(
		plot_rect.position.x + x_ratio * plot_rect.size.x,
		plot_rect.position.y + y_ratio * plot_rect.size.y
	)

# Convert pixel coordinates to plot coordinates
func pixel_to_plot(pixel_point: Vector2) -> Vector2:
	var plot_rect = get_plot_rect()
	
	var x_ratio = (pixel_point.x - plot_rect.position.x) / plot_rect.size.x
	var y_ratio = (pixel_point.y - plot_rect.position.y) / plot_rect.size.y
	
	# Invert y-axis (pixel coordinates increase downward)
	y_ratio = 1.0 - y_ratio
	
	return Vector2(
		x_min + x_ratio * (x_max - x_min),
		y_min + y_ratio * (y_max - y_min)
	)

# Draw the grid
func draw_grid(plot_rect: Rect2):
	# Draw vertical grid lines (x-axis)
	var x_start = ceil(x_min / x_tick_spacing) * x_tick_spacing
	var x = x_start
	
	while x <= x_max:
		var pixel_x = plot_to_pixel(Vector2(x, 0)).x
		draw_line(
			Vector2(pixel_x, plot_rect.position.y),
			Vector2(pixel_x, plot_rect.position.y + plot_rect.size.y),
			grid_color
		)
		x += x_tick_spacing
	
	# Draw horizontal grid lines (y-axis)
	var y_start = ceil(y_min / y_tick_spacing) * y_tick_spacing
	var y = y_start
	
	while y <= y_max:
		var pixel_y = plot_to_pixel(Vector2(0, y)).y
		draw_line(
			Vector2(plot_rect.position.x, pixel_y),
			Vector2(plot_rect.position.x + plot_rect.size.x, pixel_y),
			grid_color
		)
		y += y_tick_spacing

# Draw the axes
func draw_axes(plot_rect: Rect2):
	var font = get_theme_default_font()
	
	# Draw x-axis
	draw_line(
		Vector2(plot_rect.position.x, plot_rect.position.y + plot_rect.size.y),
		Vector2(plot_rect.position.x + plot_rect.size.x, plot_rect.position.y + plot_rect.size.y),
		axis_color,
		2.0
	)
	
	# Draw y-axis
	draw_line(
		Vector2(plot_rect.position.x, plot_rect.position.y),
		Vector2(plot_rect.position.x, plot_rect.position.y + plot_rect.size.y),
		axis_color,
		2.0
	)
	
	# Draw x-axis ticks and labels
	var x_start = ceil(x_min / x_tick_spacing) * x_tick_spacing
	var x = x_start
	
	while x <= x_max:
		var pixel_x = plot_to_pixel(Vector2(x, 0)).x
		
		# Draw tick
		draw_line(
			Vector2(pixel_x, plot_rect.position.y + plot_rect.size.y),
			Vector2(pixel_x, plot_rect.position.y + plot_rect.size.y + tick_size),
			axis_color,
			2.0
		)
		
		# Draw labela
	
		var label_text = format_number(x, x_tick_decimals)
		var font_size = tick_label_font_size
		var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		
		draw_string(
			font,
			Vector2(pixel_x - text_size.x / 2, plot_rect.position.y + plot_rect.size.y + tick_size + text_size.y),
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			axis_color
		)
		
		x += x_tick_spacing
	
	# Draw y-axis ticks and labels
	var y_start = ceil(y_min / y_tick_spacing) * y_tick_spacing
	var y = y_start
	
	while y <= y_max:
		var pixel_y = plot_to_pixel(Vector2(0, y)).y
		
		# Draw tick
		draw_line(
			Vector2(plot_rect.position.x, pixel_y),
			Vector2(plot_rect.position.x - tick_size, pixel_y),
			axis_color,
			2.0
		)
		
		# Draw label
		var label_text = format_number(y, y_tick_decimals)
		var font_size = tick_label_font_size
		var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size)
		
		draw_string(
			font,
			Vector2(plot_rect.position.x - tick_size - 5 - text_size.x, pixel_y + text_size.y / 2),
			label_text,
			HORIZONTAL_ALIGNMENT_RIGHT,
			-1,
			font_size,
			axis_color
		)
		
		y += y_tick_spacing
	
	# Draw x-axis label if set
	if x_label != "":
		var font_size = axis_label_font_size
		var text_size = font.get_string_size(x_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		
		# Position the label in the center below the x-axis
		var label_x = plot_rect.position.x + plot_rect.size.x / 2 - text_size.x / 2
		var label_y = plot_rect.position.y + plot_rect.size.y + tick_size + tick_label_font_size * 2 + 10
		
		draw_string(
			font,
			Vector2(label_x, label_y),
			x_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			axis_color
		)
	
	# Draw y-axis label if set
	if y_label != "":
		var font_size = axis_label_font_size
		var text_size = font.get_string_size(y_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		
		# Position the label to the left of the y-axis, rotated 90 degrees counter-clockwise
		var label_x = plot_rect.position.x - tick_size - tick_label_font_size * 3 - 10
		var label_y = plot_rect.position.y + plot_rect.size.y / 2 + text_size.x / 2
		
		# Save the current transform
		var transform = get_canvas_transform()
		
		# Translate to the label position, rotate, and draw
		var rotation_center = Vector2(label_x, label_y)
		draw_set_transform(rotation_center, y_label_rotation * PI / 180.0, Vector2.ONE)
		
		draw_string(
			font,
			Vector2(0, 0), # Draw at the rotation center
			y_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			font_size,
			axis_color
		)
		
		# Restore the transform
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# Add a series to the plot
func add_series(points: Array, color: Color = Color(0, 0, 1), line_width: float = 2.0,
				draw_points: bool = false, point_size: float = 4.0,
				x_errors: Array = [], y_errors: Array = [],
				error_color: Color = Color.TRANSPARENT, error_line_width: float = 1.0,
				error_cap_size: float = 5.0, draw_as_steps: bool = false) -> int:
	var series = {
		"points": points,
		"color": color,
		"line_width": line_width,
		"draw_points": draw_points,
		"point_size": point_size,
		"x_errors": x_errors,
		"y_errors": y_errors,
		"error_color": error_color if error_color != Color.TRANSPARENT else color,
		"error_line_width": error_line_width,
		"error_cap_size": error_cap_size,
		"draw_as_steps": draw_as_steps
	}
	
	series_list.append(series)
	queue_redraw()
	return series_list.size() - 1

# Remove a series by index
func remove_series(index: int) -> bool:
	if index >= 0 and index < series_list.size():
		series_list.remove_at(index)
		queue_redraw()
		return true
	return false

# Clear all series
func clear_series():
	series_list.clear()
	queue_redraw()

# Check if a point is within the plot limits
func is_point_in_plot_limits(point: Vector2) -> bool:
	return (
		point.x >= x_min and point.x <= x_max and
		point.y >= y_min and point.y <= y_max
	)

# Calculate the intersection of a line segment with a plot boundary
# Returns null if no intersection, or a Vector2 with the intersection point
func line_boundary_intersection(p1: Vector2, p2: Vector2, boundary: String) -> Variant:
	# Line equation: p = p1 + t * (p2 - p1), where 0 <= t <= 1
	var direction = p2 - p1
	var t: float
	var intersection: Vector2
	
	match boundary:
		"left":
			if direction.x == 0: # Line is vertical
				return null
			t = (x_min - p1.x) / direction.x
			if t < 0 or t > 1:
				return null
			intersection = p1 + t * direction
			if intersection.y < y_min or intersection.y > y_max:
				return null
			return intersection
		"right":
			if direction.x == 0: # Line is vertical
				return null
			t = (x_max - p1.x) / direction.x
			if t < 0 or t > 1:
				return null
			intersection = p1 + t * direction
			if intersection.y < y_min or intersection.y > y_max:
				return null
			return intersection
		"bottom":
			if direction.y == 0: # Line is horizontal
				return null
			t = (y_min - p1.y) / direction.y
			if t < 0 or t > 1:
				return null
			intersection = p1 + t * direction
			if intersection.x < x_min or intersection.x > x_max:
				return null
			return intersection
		"top":
			if direction.y == 0: # Line is horizontal
				return null
			t = (y_max - p1.y) / direction.y
			if t < 0 or t > 1:
				return null
			intersection = p1 + t * direction
			if intersection.x < x_min or intersection.x > x_max:
				return null
			return intersection
	
	return null

# Clip a line segment to the plot boundaries
# Returns an array with 0, 1, or 2 points representing the visible portion of the line
func clip_line_to_plot(p1: Vector2, p2: Vector2) -> Array:
	var p1_in = is_point_in_plot_limits(p1)
	var p2_in = is_point_in_plot_limits(p2)
	
	# Both points inside the plot - no clipping needed
	if p1_in and p2_in:
		return [p1, p2]
	
	# Both points outside - check if line passes through the plot
	if not p1_in and not p2_in:
		var intersections = []
		
		# Check all four boundaries
		var left_intersection = line_boundary_intersection(p1, p2, "left")
		var right_intersection = line_boundary_intersection(p1, p2, "right")
		var bottom_intersection = line_boundary_intersection(p1, p2, "bottom")
		var top_intersection = line_boundary_intersection(p1, p2, "top")
		
		# Collect valid intersections
		if left_intersection != null:
			intersections.append(left_intersection)
		if right_intersection != null:
			intersections.append(right_intersection)
		if bottom_intersection != null:
			intersections.append(bottom_intersection)
		if top_intersection != null:
			intersections.append(top_intersection)
		
		# If we have exactly 2 intersections, the line passes through the plot
		if intersections.size() == 2:
			return intersections
		
		# Otherwise, the line doesn't intersect the plot
		return []
	
	# One point inside, one outside - find the intersection
	var outside_point = p2 if p1_in else p1
	var inside_point = p1 if p1_in else p2
	
	var intersections = []
	
	# Check all four boundaries
	var left_intersection = line_boundary_intersection(inside_point, outside_point, "left")
	var right_intersection = line_boundary_intersection(inside_point, outside_point, "right")
	var bottom_intersection = line_boundary_intersection(inside_point, outside_point, "bottom")
	var top_intersection = line_boundary_intersection(inside_point, outside_point, "top")
	
	# Collect valid intersections
	if left_intersection != null:
		intersections.append(left_intersection)
	if right_intersection != null:
		intersections.append(right_intersection)
	if bottom_intersection != null:
		intersections.append(bottom_intersection)
	if top_intersection != null:
		intersections.append(top_intersection)
	
	# We should have exactly one intersection
	if intersections.size() == 1:
		return [inside_point, intersections[0]]
	
	# Fallback - shouldn't happen with valid input
	return [inside_point]

# Draw all series
func draw_series(plot_rect: Rect2):
	for series in series_list:
		var points = series.points
		var color = series.color
		var line_width = series.line_width
		var draw_points = series.draw_points
		var point_size = series.point_size
		var x_errors = series.x_errors
		var y_errors = series.y_errors
		var error_color = series.error_color
		var error_line_width = series.error_line_width
		var error_cap_size = series.error_cap_size
		var draw_as_steps = series.draw_as_steps
		
		if points.size() < 1:
			continue
		
		# Draw lines between points
		if points.size() > 1:
			if draw_as_steps:
				# Draw as steps (histogram-like)
				for i in range(points.size() - 1):
					var plot_p1 = points[i]
					var plot_p2 = points[i + 1]
					
					# Create the step points (horizontal line then vertical line)
					var step_h_start = Vector2(plot_p1.x, plot_p1.y)
					var step_h_end = Vector2(plot_p2.x, plot_p1.y)
					var step_v_start = Vector2(plot_p2.x, plot_p1.y)
					var step_v_end = Vector2(plot_p2.x, plot_p2.y)
					
					# Clip the horizontal segment
					var clipped_h = clip_line_to_plot(step_h_start, step_h_end)
					if clipped_h.size() == 2:
						var pixel_h1 = plot_to_pixel(clipped_h[0])
						var pixel_h2 = plot_to_pixel(clipped_h[1])
						draw_line(pixel_h1, pixel_h2, color, line_width)
					
					# Clip the vertical segment
					var clipped_v = clip_line_to_plot(step_v_start, step_v_end)
					if clipped_v.size() == 2:
						var pixel_v1 = plot_to_pixel(clipped_v[0])
						var pixel_v2 = plot_to_pixel(clipped_v[1])
						draw_line(pixel_v1, pixel_v2, color, line_width)
			else:
				# Draw regular lines
				for i in range(points.size() - 1):
					var plot_p1 = points[i]
					var plot_p2 = points[i + 1]
					
					# Clip the line to the plot boundaries
					var clipped_points = clip_line_to_plot(plot_p1, plot_p2)
					
					# If we have a visible line segment, draw it
					if clipped_points.size() == 2:
						var pixel_p1 = plot_to_pixel(clipped_points[0])
						var pixel_p2 = plot_to_pixel(clipped_points[1])
						draw_line(pixel_p1, pixel_p2, color, line_width)
		
		# Draw points if enabled
		if draw_points:
			for i in range(points.size()):
				var point = points[i]
				# Only draw if point is within the plot limits
				if is_point_in_plot_limits(point):
					var pixel_point = plot_to_pixel(point)
					draw_circle(pixel_point, point_size, color)
		
		# Draw error bars
		if (x_errors.size() > 0 or y_errors.size() > 0) and points.size() > 0:
			for i in range(points.size()):
				var point = points[i]
				var error_point = point
				
				# For step plots (except the last point), position error bars in the middle of the step
				if draw_as_steps and i < points.size() - 1:
					# Calculate the midpoint of the horizontal step
					var next_point = points[i + 1]
					var mid_x = (point.x + next_point.x) / 2.0
					error_point = Vector2(mid_x, point.y)
				
				# Skip points outside the plot limits
				if not is_point_in_plot_limits(error_point):
					continue
				
				var pixel_point = plot_to_pixel(error_point)
				
				# Draw x error bars if available
				if i < x_errors.size() and x_errors[i] > 0:
					var x_error = x_errors[i]
					var left_point = Vector2(error_point.x - x_error, error_point.y)
					var right_point = Vector2(error_point.x + x_error, error_point.y)
					
					# Clip error bar to plot boundaries
					if is_point_in_plot_limits(left_point):
						var pixel_left = plot_to_pixel(left_point)
						draw_line(pixel_left, pixel_point, error_color, error_line_width)
						
						# Draw cap
						draw_line(
							Vector2(pixel_left.x, pixel_left.y - error_cap_size / 2),
							Vector2(pixel_left.x, pixel_left.y + error_cap_size / 2),
							error_color,
							error_line_width
						)
					
					if is_point_in_plot_limits(right_point):
						var pixel_right = plot_to_pixel(right_point)
						draw_line(pixel_point, pixel_right, error_color, error_line_width)
						
						# Draw cap
						draw_line(
							Vector2(pixel_right.x, pixel_right.y - error_cap_size / 2),
							Vector2(pixel_right.x, pixel_right.y + error_cap_size / 2),
							error_color,
							error_line_width
						)
				
				# Draw y error bars if available
				if i < y_errors.size() and y_errors[i] > 0:
					var y_error = y_errors[i]
					var bottom_point = Vector2(error_point.x, error_point.y - y_error)
					var top_point = Vector2(error_point.x, error_point.y + y_error)
					
					# Clip error bar to plot boundaries
					if is_point_in_plot_limits(bottom_point):
						var pixel_bottom = plot_to_pixel(bottom_point)
						draw_line(pixel_bottom, pixel_point, error_color, error_line_width)
						
						# Draw cap
						draw_line(
							Vector2(pixel_bottom.x - error_cap_size / 2, pixel_bottom.y),
							Vector2(pixel_bottom.x + error_cap_size / 2, pixel_bottom.y),
							error_color,
							error_line_width
						)
					
					if is_point_in_plot_limits(top_point):
						var pixel_top = plot_to_pixel(top_point)
						draw_line(pixel_point, pixel_top, error_color, error_line_width)
						
						# Draw cap
						draw_line(
							Vector2(pixel_top.x - error_cap_size / 2, pixel_top.y),
							Vector2(pixel_top.x + error_cap_size / 2, pixel_top.y),
							error_color,
							error_line_width
						)

# Add an annotation (text) to the plot
func add_annotation(position: Vector2, text: String, color: Color = Color(0, 0, 0), font_size: int = 12) -> int:
	var annotation = {
		"position": position,
		"text": text,
		"color": color,
		"font_size": font_size
	}
	
	annotations.append(annotation)
	queue_redraw()
	return annotations.size() - 1

# Remove an annotation by index
func remove_annotation(index: int) -> bool:
	if index >= 0 and index < annotations.size():
		annotations.remove_at(index)
		queue_redraw()
		return true
	return false

# Clear all annotations
func clear_annotations():
	annotations.clear()
	queue_redraw()

# Draw all annotations
func draw_annotations(plot_rect: Rect2):
	for annotation in annotations:
		var position = plot_to_pixel(annotation.position)
		var text = annotation.text
		var color = annotation.color
		var font_size = annotation.font_size
		
		# Only draw if position is within the plot area
		if plot_rect.has_point(position):
			var font = get_theme_default_font()
			draw_string(
				font,
				position,
				text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				color
			)

# Add a constant line (vertical or horizontal)
func add_constant_line(value: float, is_vertical: bool = true, color: Color = Color(1, 0, 0), line_width: float = 1.0, dashed: bool = false) -> int:
	var line = {
		"value": value,
		"is_vertical": is_vertical,
		"color": color,
		"line_width": line_width,
		"dashed": dashed
	}
	
	constant_lines.append(line)
	queue_redraw()
	return constant_lines.size() - 1

# Remove a constant line by index
func remove_constant_line(index: int) -> bool:
	if index >= 0 and index < constant_lines.size():
		constant_lines.remove_at(index)
		queue_redraw()
		return true
	return false

# Clear all constant lines
func clear_constant_lines():
	constant_lines.clear()
	queue_redraw()

# Draw all constant lines
func draw_constant_lines(plot_rect: Rect2):
	for line in constant_lines:
		var value = line.value
		var is_vertical = line.is_vertical
		var color = line.color
		var line_width = line.line_width
		var dashed = line.dashed
		
		if is_vertical:
			# Vertical line (constant x)
			if value >= x_min and value <= x_max:
				var pixel_x = plot_to_pixel(Vector2(value, 0)).x
				
				if dashed:
					draw_dash_line(
						Vector2(pixel_x, plot_rect.position.y),
						Vector2(pixel_x, plot_rect.position.y + plot_rect.size.y),
						color,
						line_width
					)
				else:
					draw_line(
						Vector2(pixel_x, plot_rect.position.y),
						Vector2(pixel_x, plot_rect.position.y + plot_rect.size.y),
						color,
						line_width
					)
		else:
			# Horizontal line (constant y)
			if value >= y_min and value <= y_max:
				var pixel_y = plot_to_pixel(Vector2(0, value)).y
				
				if dashed:
					draw_dash_line(
						Vector2(plot_rect.position.x, pixel_y),
						Vector2(plot_rect.position.x + plot_rect.size.x, pixel_y),
						color,
						line_width
					)
				else:
					draw_line(
						Vector2(plot_rect.position.x, pixel_y),
						Vector2(plot_rect.position.x + plot_rect.size.x, pixel_y),
						color,
						line_width
					)

# Helper function to draw dashed lines
func draw_dash_line(from: Vector2, to: Vector2, color: Color, width: float, dash_length: float = 5.0, gap_length: float = 3.0):
	var length = from.distance_to(to)
	var normal = (to - from).normalized()
	var dash_count = floor(length / (dash_length + gap_length))
	
	var current = from
	for i in range(dash_count):
		var dash_start = current
		var dash_end = dash_start + normal * dash_length
		
		draw_line(dash_start, dash_end, color, width)
		current = dash_end + normal * gap_length
	
	# Draw the remaining dash if any
	if current.distance_to(to) > 0:
		draw_line(current, to, color, width)

# Set the plot limits
func set_limits(new_x_min: float, new_x_max: float, new_y_min: float, new_y_max: float,
			original: bool = false):
	var x_changed = new_x_min != x_min || new_x_max != x_max
	
	x_min = new_x_min
	x_max = new_x_max
	y_min = new_y_min
	y_max = new_y_max
	if original:
		original_x_min = x_min
		original_x_max = x_max
		original_y_min = y_min
		original_y_max = y_max
	
	# Emit signal if x limits changed
	if x_changed:
		emit_signal("x_limits_changed", x_min, x_max)
		
	queue_redraw()

# Set the tick spacing
func set_tick_spacing(new_x_spacing: float, new_y_spacing: float):
	x_tick_spacing = new_x_spacing
	y_tick_spacing = new_y_spacing
	queue_redraw()

# Set the plot title
func set_title(new_title: String):
	title = new_title
	queue_redraw()

# Set the x-axis label
func set_x_label(label: String):
	x_label = label
	queue_redraw()

# Set the y-axis label
func set_y_label(label: String):
	y_label = label
	queue_redraw()

# Set both axis labels
func set_axis_labels(x_label_text: String, y_label_text: String):
	x_label = x_label_text
	y_label = y_label_text
	queue_redraw()

# Set the background color
func set_background_color(color: Color):
	# This would be expanded to support textures as well
	modulate = color
	queue_redraw()

# Draw the crosshair cursor
func draw_crosshair(plot_rect: Rect2):
	# Get pixel coordinates of the crosshair position
	var pixel_pos = plot_to_pixel(crosshair_position)
	
	# Draw small crosshair at cursor position
	var small_size = 5.0
	draw_line(
		Vector2(pixel_pos.x - small_size, pixel_pos.y),
		Vector2(pixel_pos.x + small_size, pixel_pos.y),
		crosshair_color,
		crosshair_line_width
	)
	draw_line(
		Vector2(pixel_pos.x, pixel_pos.y - small_size),
		Vector2(pixel_pos.x, pixel_pos.y + small_size),
		crosshair_color,
		crosshair_line_width
	)
	
	# Draw horizontal line across the plot
	draw_line(
		Vector2(plot_rect.position.x, pixel_pos.y),
		Vector2(plot_rect.position.x + plot_rect.size.x, pixel_pos.y),
		crosshair_color,
		crosshair_line_width
	)
	
	# Draw vertical line across the plot
	draw_line(
		Vector2(pixel_pos.x, plot_rect.position.y),
		Vector2(pixel_pos.x, plot_rect.position.y + plot_rect.size.y),
		crosshair_color,
		crosshair_line_width
	)
	
	# Format the coordinate values
	var x_value_text = format_number(crosshair_position.x, x_tick_decimals)
	var y_value_text = format_number(crosshair_position.y, y_tick_decimals)
	
	# Draw x-value label above x-axis
	var font = get_theme_default_font()
	var font_size = crosshair_label_font_size
	var x_text_size = font.get_string_size(x_value_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	
	# Draw background for x-value label
	var x_label_rect = Rect2(
		pixel_pos.x - x_text_size.x / 2 - 2,
		plot_rect.position.y + plot_rect.size.y - x_text_size.y - 2,
		x_text_size.x + 4,
		x_text_size.y + 4
	)
	draw_rect(x_label_rect, Color(1, 1, 1, 0.7))
	draw_rect(x_label_rect, crosshair_color, false)
	
	draw_string(
		font,
		Vector2(pixel_pos.x - x_text_size.x / 2, plot_rect.position.y + plot_rect.size.y - 2),
		x_value_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		crosshair_color
	)
	
	# Draw y-value label to the right of y-axis
	var y_text_size = font.get_string_size(y_value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	
	# Draw background for y-value label
	var y_label_rect = Rect2(
		plot_rect.position.x + 2,
		pixel_pos.y - y_text_size.y / 2 - 2,
		y_text_size.x + 4,
		y_text_size.y + 4
	)
	draw_rect(y_label_rect, Color(1, 1, 1, 0.7))
	draw_rect(y_label_rect, crosshair_color, false)
	
	draw_string(
		font,
		Vector2(plot_rect.position.x + 4, pixel_pos.y + y_text_size.y / 2 - 2),
		y_value_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		crosshair_color
	)

# Toggle the crosshair cursor on/off
func toggle_crosshair(enabled: bool = true):
	show_crosshair = enabled
	queue_redraw()
	return show_crosshair

# Draw the selection box
func draw_selection_box(plot_rect: Rect2):
	if not is_selecting:
		return
	
	# Convert selection points to pixel coordinates
	var start_pixel = plot_to_pixel(selection_start)
	var end_pixel = plot_to_pixel(selection_end)
	
	# Create selection rectangle
	var selection_rect = Rect2(
		min(start_pixel.x, end_pixel.x),
		min(start_pixel.y, end_pixel.y),
		abs(end_pixel.x - start_pixel.x),
		abs(end_pixel.y - start_pixel.y)
	)
	
	# Draw filled rectangle with semi-transparent color
	draw_rect(selection_rect, selection_color)
	
	# Draw border with solid color
	draw_rect(selection_rect, selection_border_color, false)

# Zoom to the selected area
func zoom_to_selection():
	# Ensure selection_start.x <= selection_end.x and selection_start.y <= selection_end.y
	var new_x_min = min(selection_start.x, selection_end.x)
	var new_x_max = max(selection_start.x, selection_end.x)
	var new_y_min = min(selection_start.y, selection_end.y)
	var new_y_max = max(selection_start.y, selection_end.y)
	
	# Apply new limits (this will emit x_limits_changed signal)
	set_limits(new_x_min, new_x_max, new_y_min, new_y_max)
	
	# Update tick spacing based on new range
	var x_range = new_x_max - new_x_min
	var y_range = new_y_max - new_y_min
	
	# Calculate appropriate tick spacing (approximately 5-10 ticks)
	var x_magnitude = pow(10, floor(log(x_range / 5) / log(10)))
	var y_magnitude = pow(10, floor(log(y_range / 5) / log(10)))
	
	set_tick_spacing(x_magnitude, y_magnitude)

# Reset zoom to original limits
func reset_zoom():
	# This will emit x_limits_changed signal
	set_limits(original_x_min, original_x_max, original_y_min, original_y_max)
	
	# Reset tick spacing based on original range
	var x_range = original_x_max - original_x_min
	var y_range = original_y_max - original_y_min
	
	# Calculate appropriate tick spacing (approximately 5-10 ticks)
	#var x_magnitude = pow(10, floor(log(x_range / 5) / log(10)))
	#var y_magnitude = pow(10, floor(log(y_range / 5) / log(10)))
	
	#set_tick_spacing(x_magnitude, y_magnitude)
	set_tick_spacing(original_x_tick_spacing, original_y_tick_spacing)

# Helper function to format numbers with specified decimals
func format_number(value: float, decimals: int) -> String:
	return "%.*f" % [decimals, value]

# Update the display
func update_display():
	queue_redraw()
