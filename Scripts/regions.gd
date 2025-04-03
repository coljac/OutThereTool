extends Control

# Class to represent a parsed shape from the region file
class RegionShape:
	var name: String  # e.g. "circle", "box", etc.
	var coord_format: String  # e.g. "fk5", "image"
	var coord_list: Array  # coordinates and dimensions
	var attributes: Dictionary  # visual properties

# Main class variables
var shapes: Array = []  # Will hold RegionShape objects
var region_node: Node2D

func _ready():
	# Create a Node2D for drawing the regions
	region_node = Node2D.new()
	add_child(region_node)
	
	# Test by loading a region file
	load_region_file("res://test.reg")

func load_region_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Failed to open region file")
		print(FileAccess.get_open_error())
		return
		
	var lines = file.get_as_text().split("\n")
	file.close()
	
	var current_coord_system = "image"  # default
	
	for line in lines:
		line = line.strip_edges()
		if line.empty() or line.begins_with("#"):
			continue
			
		# Handle coordinate system changes
		if line.to_lower() in ["fk5", "image", "physical", "j2000"]:
			current_coord_system = line.to_lower()
			continue
			
		# Parse region definition
		parse_region_line(line, current_coord_system)
	
	# After parsing, create the visual elements
	region_node.queue_redraw()

func parse_region_line(line: String, coord_system: String) -> void:
	# Check for include/exclude property
	var is_exclude = line.begins_with("-")
	if is_exclude:
		line = line.substr(1)
	
	# Handle multiple regions on same line (separated by semicolon)
	if ";" in line:
		var sublines = line.split(";")
		for subline in sublines:
			subline = subline.strip_edges()
			if not subline.empty():
				parse_region_line(subline, coord_system)
		return
	
	# Extract attributes from comments
	var attributes = {"color": Color.GREEN, "width": 2.0, "fill": false}
	if "#" in line:
		var parts = line.split("#", true, 1)
		line = parts[0].strip_edges()
		
		if parts.size() > 1:
			var attr_text = parts[1].strip_edges()
			# Parse attributes like color=red width=2 etc.
			var attr_parts = attr_text.split(" ")
			for attr in attr_parts:
				if "=" in attr:
					var key_value = attr.split("=", true, 1)
					var key = key_value[0].strip_edges()
					var value = key_value[1].strip_edges()
					
					# Process attributes based on their types
					match key:
						"color":
							if value in ["green", "red", "blue", "yellow", "white"]:
								attributes["color"] = Color(value)
							elif value.begins_with("#"):
								attributes["color"] = Color(value)
						"width":
							attributes["width"] = float(value)
						"fill":
							attributes["fill"] = value == "1"
						"text":
							# Handle text with {} brackets
							if value.begins_with("{") and value.ends_with("}"):
								attributes["text"] = value.substr(1, value.length() - 2)
	
	# Basic parsing - extract shape and coordinates
	var shape_type = ""
	var coord_str = ""
	
	# Handle syntax with or without parentheses
	if "(" in line and ")" in line:
		var parts = line.split("(", true, 1)
		shape_type = parts[0].strip_edges()
		coord_str = parts[1].split(")", true, 1)[0].strip_edges()
	else:
		var parts = line.split(" ", true, 1)
		if parts.size() < 2:
			return
		shape_type = parts[0].strip_edges()
		coord_str = parts[1].strip_edges()
	
	# Normalize shape type names
	shape_type = shape_type.to_lower()
	
	# Convert coordinates to float array
	var coord_list = []
	for coord in coord_str.split(","):
		coord = coord.strip_edges()
		# Handle multiple spaces as separators
		for value in coord.split(" ", false):
			if not value.is_empty():
				coord_list.append(float(value))
	
	var shape = RegionShape.new()
	shape.name = shape_type
	shape.coord_format = coord_system
	shape.coord_list = coord_list
	shape.attributes = attributes
	
	shapes.append(shape)

# The Node2D will use this to draw all shapes
func _on_region_node_draw():
	for shape in shapes:
		match shape.name:
			"circle":
				draw_circle_region(shape)
			"box":
				draw_box_region(shape)
			"ellipse":
				draw_ellipse_region(shape) 
			"polygon":
				draw_polygon_region(shape)
			"line":
				draw_line_region(shape)
			"point":
				draw_point_region(shape)
			"text":
				draw_text_region(shape)

func draw_circle_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 3:
		return
		
	var center = Vector2(shape.coord_list[0], shape.coord_list[1])
	var radius = shape.coord_list[2]
	
	# If coordinates are in sky format, convert to pixels here
	if shape.coord_format in ["fk5", "j2000"]:
		# In a real implementation, you would convert WCS coordinates to pixels
		# center = wcs_to_pixels(center)
		pass
	
	if shape.attributes.fill:
		region_node.draw_circle(center, radius, shape.attributes.color)
	else:
		region_node.draw_arc(center, radius, 0, TAU, 64, shape.attributes.color, shape.attributes.width)

func draw_box_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x, y, width, height (angle optional)
		return
		
	var center = Vector2(shape.coord_list[0], shape.coord_list[1])
	var width = shape.coord_list[2]
	var height = shape.coord_list[3]
	var angle = 0.0
	if shape.coord_list.size() >= 5:
		angle = deg_to_rad(shape.coord_list[4])
	
	if shape.coord_format in ["fk5", "j2000"]:
		# Convert coordinates using your WCS system
		pass
	
	var rect = Rect2(center - Vector2(width/2, height/2), Vector2(width, height))
	
	# Save current transform
	region_node.draw_set_transform(center, angle, Vector2.ONE)
	
	if shape.attributes.fill:
		region_node.draw_rect(rect, shape.attributes.color, true)
	else:
		region_node.draw_rect(rect, shape.attributes.color, false, shape.attributes.width)
	
	# Restore transform
	region_node.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func draw_ellipse_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x, y, radiusX, radiusY (angle optional)
		return
		
	var center = Vector2(shape.coord_list[0], shape.coord_list[1])
	var radiusX = shape.coord_list[2]
	var radiusY = shape.coord_list[3]
	var angle = 0.0
	if shape.coord_list.size() >= 5:
		angle = deg_to_rad(shape.coord_list[4])
	
	# Save current transform
	region_node.draw_set_transform(center, angle, Vector2.ONE)
	
	# Draw the ellipse
	if shape.attributes.fill:
		draw_ellipse_filled(region_node, Vector2.ZERO, radiusX, radiusY, shape.attributes.color)
	else:
		draw_ellipse_outline(region_node, Vector2.ZERO, radiusX, radiusY, 
							shape.attributes.color, shape.attributes.width)
	
	# Restore transform
	region_node.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# Helper for drawing ellipse outlines
func draw_ellipse_outline(node: Node2D, center: Vector2, radiusX: float, radiusY: float, 
						 color: Color, width: float = 1.0, point_count: int = 32) -> void:
	var points = []
	for i in range(point_count + 1):
		var angle = i * TAU / point_count
		var point = Vector2(cos(angle) * radiusX, sin(angle) * radiusY)
		points.append(center + point)
	
	for i in range(point_count):
		node.draw_line(points[i], points[i + 1], color, width)

# Helper for drawing filled ellipses
func draw_ellipse_filled(node: Node2D, center: Vector2, radiusX: float, radiusY: float, 
					   color: Color, point_count: int = 32) -> void:
	var points = []
	for i in range(point_count):
		var angle = i * TAU / point_count
		var point = Vector2(cos(angle) * radiusX, sin(angle) * radiusY)
		points.append(center + point)
	
	node.draw_polygon(points, [color])

func draw_polygon_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 6:  # Need at least 3 points (x1,y1,x2,y2,x3,y3)
		return
	
	var points = []
	for i in range(0, shape.coord_list.size(), 2):
		if i + 1 < shape.coord_list.size():
			points.append(Vector2(shape.coord_list[i], shape.coord_list[i+1]))
	
	if shape.attributes.fill:
		region_node.draw_polygon(points, [shape.attributes.color])
	else:
		for i in range(points.size()):
			var start = points[i]
			var end = points[(i + 1) % points.size()]
			region_node.draw_line(start, end, shape.attributes.color, shape.attributes.width)

func draw_line_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x1, y1, x2, y2
		return
	
	var start = Vector2(shape.coord_list[0], shape.coord_list[1])
	var end = Vector2(shape.coord_list[2], shape.coord_list[3])
	
	region_node.draw_line(start, end, shape.attributes.color, shape.attributes.width)

func draw_point_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 2:  # Need x, y
		return
	
	var point = Vector2(shape.coord_list[0], shape.coord_list[1])
	var size = 5.0  # Default size
	
	# Check if a size is specified in attributes
	if "size" in shape.attributes:
		size = shape.attributes.size
	
	# Default to a circle if point type not specified
	var point_type = "circle"
	if "point_type" in shape.attributes:
		point_type = shape.attributes.point_type
	
	match point_type:
		"circle":
			region_node.draw_circle(point, size, shape.attributes.color)
		"box":
			var rect = Rect2(point - Vector2(size/2, size/2), Vector2(size, size))
			region_node.draw_rect(rect, shape.attributes.color, true)
		"cross":
			region_node.draw_line(point - Vector2(size, 0), point + Vector2(size, 0), 
							   shape.attributes.color, shape.attributes.width)
			region_node.draw_line(point - Vector2(0, size), point + Vector2(0, size), 
							   shape.attributes.color, shape.attributes.width)

func draw_text_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 2:  # Need x, y
		return
	
	var position = Vector2(shape.coord_list[0], shape.coord_list[1])
	var text = ""
	
	if "text" in shape.attributes:
		text = shape.attributes.text
	
	if not text.is_empty():
		region_node.draw_string(SystemFont.new(), position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, shape.attributes.color)

# Override _draw to call our Region Node's draw method
func _draw():
	_on_region_node_draw()
