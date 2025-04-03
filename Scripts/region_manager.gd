extends Node2D
class_name RegionManager

# Class to represent a parsed shape from the region file
class RegionShape:
	var name: String  # e.g. "circle", "box", etc.
	var coord_format: String  # e.g. "fk5", "image"
	var coord_list: Array  # coordinates and dimensions
	var attributes: Dictionary  # visual properties

# Main class variables
var shapes: Array = []  # Will hold RegionShape objects
var fits_viewer: Sprite2D  # Reference to parent FITS viewer

#func _ready():
	# Find the FITS viewer parent
	#fits_viewer = get_parent() as Sprite2D
	#if not fits_viewer:
		#push_error("RegionManager must be a child of a Sprite2D FITS viewer")

func load_region_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("Failed to open region file")
		print(FileAccess.get_open_error())
		return
		
	var lines = file.get_as_text().split("\n")
	file.close()
	
	shapes.clear()  # Clear existing shapes
	var current_coord_system = "image"  # default
	
	for line in lines:
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
			
		# Handle coordinate system changes
		if line.to_lower() in ["fk5", "image", "physical", "j2000"]:
			current_coord_system = line.to_lower()
			continue
			
		# Parse region definition
		parse_region_line(line, current_coord_system)
	
	# After parsing, request redraw
	queue_redraw()

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
	var attributes = {"color": Color.GREEN, "width": 0.4, "fill": false}
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
							if value in ["green", "red", "blue", "yellow", "white", "cyan", "magenta", "black"]:
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
						"font":
							attributes["font"] = value
						"point":
							# Format: point=circle 5
							var point_parts = value.split(" ")
							if point_parts.size() > 0:
								attributes["point_type"] = point_parts[0]
							if point_parts.size() > 1:
								attributes["point_size"] = float(point_parts[1])
						"dash":
							attributes["dash"] = value == "1"
						"dashlist":
							var dash_parts = value.split(" ")
							if dash_parts.size() >= 2:
								attributes["dash_on"] = float(dash_parts[0])
								attributes["dash_off"] = float(dash_parts[1])
						"line":
							var line_parts = value.split(" ")
							if line_parts.size() >= 2:
								attributes["arrow_start"] = line_parts[0] == "1"
								attributes["arrow_end"] = line_parts[1] == "1"
						"ruler":
							attributes["ruler_format"] = value
	
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
				# Try to parse as float, could be in degrees/hours notation
				if ":" in value:
					coord_list.append(parse_coord_notation(value))
				else:
					coord_list.append(float(value))
	
	var shape = RegionShape.new()
	shape.name = shape_type
	shape.coord_format = coord_system
	shape.coord_list = coord_list
	shape.attributes = attributes
	
	shapes.append(shape)

# Parse coordinate notation like 12:30:45.5 (hours:min:sec or deg:min:sec)
func parse_coord_notation(coord: String) -> float:
	var parts = coord.split(":")
	var value = 0.0
	
	if parts.size() >= 1:
		value += float(parts[0])
	if parts.size() >= 2:
		value += float(parts[1]) / 60.0
	if parts.size() >= 3:
		value += float(parts[2]) / 3600.0
		
	return value

func _draw():
	if not fits_viewer or not fits_viewer.fits:
		return
		
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
			"vector":
				draw_vector_region(shape)
			"point":
				draw_point_region(shape)
			"text":
				draw_text_region(shape)
			"ruler":
				draw_ruler_region(shape)
			"compass":
				draw_compass_region(shape)
			"annulus":
				draw_annulus_region(shape)
			"ellipse annulus":
				draw_ellipse_annulus_region(shape)
			"box annulus":
				draw_box_annulus_region(shape)
			"panda":
				draw_panda_region(shape)
			"epanda":
				draw_epanda_region(shape)
			"bpanda":
				draw_bpanda_region(shape)
			"segment":
				draw_segment_region(shape)
			"projection":
				draw_projection_region(shape)

# Convert world coordinates to local drawing coordinates
func world_to_drawing(ra: float, dec: float) -> Vector2:
	var pixel_coords = fits_viewer.fits.world_to_pixel(ra, dec)
	# Adjust for Sprite2D coordinates (center is the origin)
	pixel_coords.x -= fits_viewer.width/2
	pixel_coords.y = fits_viewer.height/2 - pixel_coords.y
	return pixel_coords

# Convert image coordinates to local drawing coordinates
func image_to_drawing(x: float, y: float) -> Vector2:
	# Adjust for Sprite2D coordinates (center is the origin)
	return Vector2(x - fits_viewer.width/2, fits_viewer.height/2 - y)

# Convert a world distance to pixel distance (approximately)
func world_dist_to_pixels(ra: float, dec: float, dist_deg: float) -> float:
	var center = fits_viewer.fits.world_to_pixel(ra, dec)
	var edge = fits_viewer.fits.world_to_pixel(ra + dist_deg, dec)
	return center.distance_to(edge)

# 1. Circle Region
func draw_circle_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 3:
		return
	
	var center: Vector2
	var radius: float
	
	# Handle different coordinate systems
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		radius = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[2]/3600.0)  # Assuming radius is in arcsec
	else:
		# Image coordinates
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		radius = shape.coord_list[2]
	
	if shape.attributes.fill:
		draw_circle(center, radius, shape.attributes.color)
	else:
		if shape.attributes.get("dash", false):
			draw_dashed_arc(center, radius, 0, TAU, 64, shape.attributes.color, 
						 shape.attributes.width,
						 shape.attributes.get("dash_on", 10),
						 shape.attributes.get("dash_off", 5))
		else:
			draw_arc(center, radius, 0, TAU, 64, shape.attributes.color, shape.attributes.width)

# 2. Box Region
func draw_box_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x, y, width, height (angle optional)
		return
	
	var center: Vector2
	var width: float
	var height: float
	var angle = 0.0
	
	# Handle different coordinate systems
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		# Convert width/height from degrees/arcsec to pixels
		width = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[2]/3600.0) * 2  # Assuming width is in arcsec
		height = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[3]/3600.0) * 2  # Assuming height is in arcsec
	else:
		# Image coordinates
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		width = shape.coord_list[2]
		height = shape.coord_list[3]
	
	if shape.coord_list.size() >= 5:
		angle = deg_to_rad(shape.coord_list[4])
	
	# Save current transform
	draw_set_transform(center, angle, Vector2.ONE)
	
	var rect = Rect2(Vector2(-width/2, -height/2), Vector2(width, height))
	
	if shape.attributes.fill:
		draw_rect(rect, shape.attributes.color, true)
	else:
		if shape.attributes.get("dash", false):
			draw_dashed_rect(rect, shape.attributes.color, shape.attributes.width,
						  shape.attributes.get("dash_on", 10),
						  shape.attributes.get("dash_off", 5))
		else:
			draw_rect(rect, shape.attributes.color, false, shape.attributes.width)
	
	# Restore transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# 3. Ellipse Region
func draw_ellipse_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x, y, radius_x, radius_y (angle optional)
		return
	
	var center: Vector2
	var radius_x: float
	var radius_y: float
	var angle = 0.0
	
	# Handle different coordinate systems
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		radius_x = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[2]/3600.0)  # Assuming radius_x is in arcsec
		radius_y = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[3]/3600.0)  # Assuming radius_y is in arcsec
	else:
		# Image coordinates
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		radius_x = shape.coord_list[2]
		radius_y = shape.coord_list[3]
	
	if shape.coord_list.size() >= 5:
		angle = deg_to_rad(shape.coord_list[4])
	
	# Save current transform
	draw_set_transform(center, angle, Vector2.ONE)
	
	if shape.attributes.fill:
		draw_ellipse_filled(Vector2.ZERO, radius_x, radius_y, shape.attributes.color)
	else:
		if shape.attributes.get("dash", false):
			draw_dashed_ellipse(Vector2.ZERO, radius_x, radius_y, shape.attributes.color, 
							 shape.attributes.width,
							 shape.attributes.get("dash_on", 10),
							 shape.attributes.get("dash_off", 5))
		else:
			draw_ellipse(Vector2.ZERO, radius_x, radius_y, shape.attributes.color, shape.attributes.width)
	
	# Restore transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func draw_polygon_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 6:  # Need at least 3 points (x1,y1,x2,y2,x3,y3)
		return
	
	var points = []
	for i in range(0, shape.coord_list.size(), 2):
		if i + 1 < shape.coord_list.size():
			if shape.coord_format in ["fk5", "j2000"]:
				points.append(world_to_drawing(shape.coord_list[i], shape.coord_list[i+1]))
			else:
				points.append(image_to_drawing(shape.coord_list[i], shape.coord_list[i+1]))
	
	if shape.attributes.fill:
		draw_colored_polygon(points, shape.attributes.color)
	else:
		for i in range(points.size()):
			var start = points[i]
			var end = points[(i + 1) % points.size()]
			
			if shape.attributes.get("dash", false):
				draw_dashed_line(start, end, shape.attributes.color, 
							  shape.attributes.width,
							  shape.attributes.get("dash_on", 10),
							  shape.attributes.get("dash_off", 5))
			else:
				draw_line(start, end, shape.attributes.color, shape.attributes.width)

# 5. Line Region
func draw_line_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x1, y1, x2, y2
		return
	
	var start: Vector2
	var end: Vector2
	
	if shape.coord_format in ["fk5", "j2000"]:
		start = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		end = world_to_drawing(shape.coord_list[2], shape.coord_list[3])
	else:
		start = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		end = image_to_drawing(shape.coord_list[2], shape.coord_list[3])
	
	if shape.attributes.get("dash", false):
		draw_dashed_line(start, end, shape.attributes.color, 
					  shape.attributes.width,
					  shape.attributes.get("dash_on", 10),
					  shape.attributes.get("dash_off", 5))
	else:
		draw_line(start, end, shape.attributes.color, shape.attributes.width)
	
	# Draw arrows if specified
	if shape.attributes.get("arrow_start", false):
		draw_arrow(start, end, shape.attributes.color, shape.attributes.width)
	
	if shape.attributes.get("arrow_end", false):
		draw_arrow(end, start, shape.attributes.color, shape.attributes.width)

# 6. Vector Region
func draw_vector_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x1, y1, length, angle
		return
	
	var start: Vector2
	var length: float
	var angle: float = deg_to_rad(shape.coord_list[3])
	
	if shape.coord_format in ["fk5", "j2000"]:
		start = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		length = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[2]/3600.0)
	else:
		start = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		length = shape.coord_list[2]
	
	var end = start + Vector2(cos(angle), sin(angle)) * length
	
	if shape.attributes.get("dash", false):
		draw_dashed_line(start, end, shape.attributes.color, 
					  shape.attributes.width,
					  shape.attributes.get("dash_on", 10),
					  shape.attributes.get("dash_off", 5))
	else:
		draw_line(start, end, shape.attributes.color, shape.attributes.width)
	
	# Always draw arrow at the end for vector
	draw_arrow(end, start, shape.attributes.color, shape.attributes.width)

# 7. Point Region
func draw_point_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 2:  # Need x, y
		return
	
	var point: Vector2
	
	if shape.coord_format in ["fk5", "j2000"]:
		point = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
	else:
		point = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
	
	var size = shape.attributes.get("point_size", 5.0)
	var point_type = shape.attributes.get("point_type", "circle")
	
	match point_type:
		"circle":
			draw_circle(point, size, shape.attributes.color)
		"box":
			var rect = Rect2(point - Vector2(size/2, size/2), Vector2(size, size))
			draw_rect(rect, shape.attributes.color, true)
		"diamond":
			var points = [
				point + Vector2(0, -size),
				point + Vector2(size, 0),
				point + Vector2(0, size),
				point + Vector2(-size, 0)
			]
			draw_colored_polygon(points, shape.attributes.color)
		"cross":
			draw_line(point - Vector2(size, 0), point + Vector2(size, 0), 
				   shape.attributes.color, shape.attributes.width)
			draw_line(point - Vector2(0, size), point + Vector2(0, size), 
				   shape.attributes.color, shape.attributes.width)
		"x":
			draw_line(point - Vector2(size, size), point + Vector2(size, size), 
				   shape.attributes.color, shape.attributes.width)
			draw_line(point - Vector2(size, -size), point + Vector2(size, -size), 
				   shape.attributes.color, shape.attributes.width)
		"arrow":
			var end_point = point + Vector2(size, 0)
			draw_line(point, end_point, shape.attributes.color, shape.attributes.width)
			draw_arrow(end_point, point, shape.attributes.color, shape.attributes.width)
		"boxcircle":
			draw_circle(point, size, shape.attributes.color)
			var rect = Rect2(point - Vector2(size, size), Vector2(size*2, size*2))
			draw_rect(rect, shape.attributes.color, false)

# 8. Text Region
func draw_text_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 2:  # Need x, y
		return
	
	var position: Vector2
	
	if shape.coord_format in ["fk5", "j2000"]:
		position = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
	else:
		position = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
	
	var text = shape.attributes.get("text", "")
	if text.is_empty():
		return
	
	var font_size = 16  # Default font size
	var font = SystemFont.new()
	
	# Process font attribute if present
	if "font" in shape.attributes:
		var font_str = shape.attributes.font
		if font_str.find(" ") >= 0:
			var font_parts = font_str.split(" ")
			for part in font_parts:
				if part.is_valid_int():
					font_size = int(part)
	
	# Apply rotation if specified
	var angle = 0.0
	if "textangle" in shape.attributes:
		angle = deg_to_rad(float(shape.attributes.textangle))
	
	if angle != 0.0:
		draw_set_transform(position, angle, Vector2.ONE)
		draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shape.attributes.color)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shape.attributes.color)

# 9. Ruler Region
func draw_ruler_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need x1, y1, x2, y2
		return
	
	var start: Vector2
	var end: Vector2
	
	if shape.coord_format in ["fk5", "j2000"]:
		start = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		end = world_to_drawing(shape.coord_list[2], shape.coord_list[3])
	else:
		start = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		end = image_to_drawing(shape.coord_list[2], shape.coord_list[3])
	
	# Draw the line
	draw_line(start, end, shape.attributes.color, shape.attributes.width)
	
	# Calculate distance based on ruler format
	var distance_text = ""
	var ruler_format = shape.attributes.get("ruler_format", "pixels")
	
	if shape.coord_format in ["fk5", "j2000"] and ruler_format != "pixels":
		# Calculate angular distance
		var ra1 = shape.coord_list[0]
		var dec1 = shape.coord_list[1]
		var ra2 = shape.coord_list[2]
		var dec2 = shape.coord_list[3]
		
		# Haversine formula for angular distance
		var d_ra = deg_to_rad(ra2 - ra1)
		var d_dec = deg_to_rad(dec2 - dec1)
		var a = sin(d_dec/2) * sin(d_dec/2) + cos(deg_to_rad(dec1)) * cos(deg_to_rad(dec2)) * sin(d_ra/2) * sin(d_ra/2)
		var c = 2 * atan2(sqrt(a), sqrt(1-a))
		var distance_deg = rad_to_deg(c)
		
		match ruler_format:
			"degrees":
				distance_text = "%0.3f°" % distance_deg
			"arcmin":
				distance_text = "%0.2f'" % (distance_deg * 60)
			"arcsec":
				distance_text = "%0.1f\"" % (distance_deg * 3600)
	else:
		# Pixel distance
		var distance_px = start.distance_to(end)
		distance_text = "%0.1f px" % distance_px
	
	# Draw the distance text
	var mid_point = (start + end) / 2
	var offset = Vector2(0, -10)  # Offset text upward
	draw_string(SystemFont.new(), mid_point + offset, distance_text, 
			 HORIZONTAL_ALIGNMENT_CENTER, -1, 14, shape.attributes.color)

# 10. Compass Region
func draw_compass_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 3:  # Need x, y, length
		return
	
	var center: Vector2
	var length: float
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		length = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[2]/3600.0)
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		length = shape.coord_list[2]
	
	# North direction (up)
	var north_end = center + Vector2(0, -length)
	draw_line(center, north_end, shape.attributes.color, shape.attributes.width)
	draw_arrow(north_end, center, shape.attributes.color, shape.attributes.width)
	draw_string(SystemFont.new(), north_end + Vector2(0, -10), "N", 
			 HORIZONTAL_ALIGNMENT_CENTER, -1, 14, shape.attributes.color)
	
	# East direction (right)
	var east_end = center + Vector2(length, 0)
	draw_line(center, east_end, shape.attributes.color, shape.attributes.width)
	draw_arrow(east_end, center, shape.attributes.color, shape.attributes.width)
	draw_string(SystemFont.new(), east_end + Vector2(10, 0), "E", 
			 HORIZONTAL_ALIGNMENT_LEFT, -1, 14, shape.attributes.color)

# 11. Annulus Region
func draw_annulus_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 3:  # Need center_x, center_y, inner_radius (at minimum)
		return
	
	var center: Vector2
	var radii: Array = []
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		for i in range(2, shape.coord_list.size()):
			radii.append(world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[i]/3600.0))
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		for i in range(2, shape.coord_list.size()):
			radii.append(shape.coord_list[i])
	
	# Draw each circle
	for radius in radii:
		draw_arc(center, radius, 0, TAU, 64, shape.attributes.color, shape.attributes.width)

func draw_ellipse_annulus_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 6:  # Need center_x, center_y, rx1, ry1, rx2, ry2
		return
	
	var center: Vector2
	var rx_list: Array = []
	var ry_list: Array = []
	var angle = 0.0
	
	if shape.coord_list.size() >= 7:
		angle = deg_to_rad(shape.coord_list[shape.coord_list.size() - 1])
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		for i in range(2, shape.coord_list.size() - (1 if angle != 0 else 0), 2):
			if i + 1 < shape.coord_list.size():
				rx_list.append(world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[i]/3600.0))
				ry_list.append(world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[i+1]/3600.0))
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		for i in range(2, shape.coord_list.size() - (1 if angle != 0 else 0), 2):
			if i + 1 < shape.coord_list.size():
				rx_list.append(shape.coord_list[i])
				ry_list.append(shape.coord_list[i+1])
	
	# Save current transform
	draw_set_transform(center, angle, Vector2.ONE)
	
	# Draw each ellipse
	for i in range(rx_list.size()):
		draw_ellipse(Vector2.ZERO, rx_list[i], ry_list[i], shape.attributes.color, shape.attributes.width)
	
	# Restore transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# 13. Box Annulus Region
func draw_box_annulus_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 6:  # Need center_x, center_y, w1, h1, w2, h2
		return
	
	var center: Vector2
	var width_list: Array = []
	var height_list: Array = []
	var angle = 0.0
	
	if shape.coord_list.size() >= 7:
		angle = deg_to_rad(shape.coord_list[shape.coord_list.size() - 1])
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		for i in range(2, shape.coord_list.size() - (1 if angle != 0 else 0), 2):
			if i + 1 < shape.coord_list.size():
				width_list.append(world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[i]/3600.0) * 2)
				height_list.append(world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[i+1]/3600.0) * 2)
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		for i in range(2, shape.coord_list.size() - (1 if angle != 0 else 0), 2):
			if i + 1 < shape.coord_list.size():
				width_list.append(shape.coord_list[i])
				height_list.append(shape.coord_list[i+1])
	
	# Save current transform
	draw_set_transform(center, angle, Vector2.ONE)
	
	# Draw each box
	for i in range(width_list.size()):
		var rect = Rect2(Vector2(-width_list[i]/2, -height_list[i]/2), Vector2(width_list[i], height_list[i]))
		draw_rect(rect, shape.attributes.color, false, shape.attributes.width)
	
	# Restore transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# 14. Panda Region (Pie Annulus)
func draw_panda_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 7:  # Need x, y, angle1, angle2, nangle, r1, r2, nradius
		return
	
	var center: Vector2
	var start_angle = deg_to_rad(shape.coord_list[2])
	var end_angle = deg_to_rad(shape.coord_list[3])
	var n_angles = int(shape.coord_list[4])
	var inner_radius: float
	var outer_radius: float
	var n_radii = 0
	
	if shape.coord_list.size() >= 8:
		n_radii = int(shape.coord_list[7])
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		inner_radius = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[5]/3600.0)
		outer_radius = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[6]/3600.0)
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		inner_radius = shape.coord_list[5]
		outer_radius = shape.coord_list[6]
	
	# Draw radial sections (pie slices)
	var angle_step = (end_angle - start_angle) / n_angles
	for i in range(n_angles):
		var angle1 = start_angle + i * angle_step
		var angle2 = start_angle + (i + 1) * angle_step
		
		# Draw arc for inner radius
		draw_arc(center, inner_radius, angle1, angle2, 32, shape.attributes.color, shape.attributes.width)
		
		# Draw arc for outer radius
		draw_arc(center, outer_radius, angle1, angle2, 32, shape.attributes.color, shape.attributes.width)
		
		# Draw radial lines
		var inner_point1 = center + Vector2(cos(angle1), sin(angle1)) * inner_radius
		var outer_point1 = center + Vector2(cos(angle1), sin(angle1)) * outer_radius
		draw_line(inner_point1, outer_point1, shape.attributes.color, shape.attributes.width)
		
		var inner_point2 = center + Vector2(cos(angle2), sin(angle2)) * inner_radius
		var outer_point2 = center + Vector2(cos(angle2), sin(angle2)) * outer_radius
		draw_line(inner_point2, outer_point2, shape.attributes.color, shape.attributes.width)
	
	# Draw concentric circles if n_radii > 0
	if n_radii > 0:
		var radius_step = (outer_radius - inner_radius) / n_radii
		for i in range(1, n_radii):
			var radius = inner_radius + i * radius_step
			draw_arc(center, radius, start_angle, end_angle, 64, shape.attributes.color, shape.attributes.width)

# 15. EPanda Region (Elliptical Pie Annulus)
func draw_epanda_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 11:  # Need more parameters than regular panda
		return
	
	var center: Vector2
	var start_angle = deg_to_rad(shape.coord_list[2])
	var end_angle = deg_to_rad(shape.coord_list[3])
	var n_angles = int(shape.coord_list[4])
	var inner_rx: float
	var inner_ry: float
	var outer_rx: float
	var outer_ry: float
	var n_radii = int(shape.coord_list[9])
	var rotation_angle = 0.0
	
	if shape.coord_list.size() >= 11:
		rotation_angle = deg_to_rad(shape.coord_list[10])
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		inner_rx = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[5]/3600.0)
		inner_ry = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[6]/3600.0)
		outer_rx = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[7]/3600.0)
		outer_ry = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[8]/3600.0)
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		inner_rx = shape.coord_list[5]
		inner_ry = shape.coord_list[6]
		outer_rx = shape.coord_list[7]
		outer_ry = shape.coord_list[8]
	
	# Save transform for rotation
	draw_set_transform(center, rotation_angle, Vector2.ONE)
	
	# Draw radial sections (pie slices)
	var angle_step = (end_angle - start_angle) / n_angles
	for i in range(n_angles):
		var angle1 = start_angle + i * angle_step
		var angle2 = start_angle + (i + 1) * angle_step
		
		# Draw inner and outer elliptical arcs segments
		draw_ellipse_arc(Vector2.ZERO, inner_rx, inner_ry, angle1, angle2, shape.attributes.color, shape.attributes.width)
		draw_ellipse_arc(Vector2.ZERO, outer_rx, outer_ry, angle1, angle2, shape.attributes.color, shape.attributes.width)
		
		# Draw radial lines
		var inner_point1 = Vector2(cos(angle1) * inner_rx, sin(angle1) * inner_ry)
		var outer_point1 = Vector2(cos(angle1) * outer_rx, sin(angle1) * outer_ry)
		draw_line(inner_point1, outer_point1, shape.attributes.color, shape.attributes.width)
		
		var inner_point2 = Vector2(cos(angle2) * inner_rx, sin(angle2) * inner_ry)
		var outer_point2 = Vector2(cos(angle2) * outer_rx, sin(angle2) * outer_ry)
		draw_line(inner_point2, outer_point2, shape.attributes.color, shape.attributes.width)
	
	# Draw intermediate ellipses if n_radii > 0
	if n_radii > 0:
		var rx_step = (outer_rx - inner_rx) / n_radii
		var ry_step = (outer_ry - inner_ry) / n_radii
		for i in range(1, n_radii):
			var rx = inner_rx + i * rx_step
			var ry = inner_ry + i * ry_step
			draw_ellipse_arc(Vector2.ZERO, rx, ry, start_angle, end_angle, shape.attributes.color, shape.attributes.width)
	
	# Restore transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	
func draw_bpanda_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 11:  # Similar to EPanda
		return
	
	var center: Vector2
	var start_angle = deg_to_rad(shape.coord_list[2])
	var end_angle = deg_to_rad(shape.coord_list[3])
	var n_angles = int(shape.coord_list[4])
	var inner_width: float
	var inner_height: float
	var outer_width: float
	var outer_height: float
	var n_radii = int(shape.coord_list[9])
	var rotation_angle = 0.0
	
	if shape.coord_list.size() >= 11:
		rotation_angle = deg_to_rad(shape.coord_list[10])
	
	if shape.coord_format in ["fk5", "j2000"]:
		center = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		inner_width = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[5]/3600.0) * 2
		inner_height = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[6]/3600.0) * 2
		outer_width = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[7]/3600.0) * 2
		outer_height = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[8]/3600.0) * 2
	else:
		center = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		inner_width = shape.coord_list[5]
		inner_height = shape.coord_list[6]
		outer_width = shape.coord_list[7]
		outer_height = shape.coord_list[8]
	
	# This is a simplification - in reality, BPanda is more complex as it needs
	# box segments at different angles. Here we just draw boxes and lines
	
	# Save transform for rotation
	draw_set_transform(center, rotation_angle, Vector2.ONE)
	
	# Draw inner and outer boxes
	var inner_rect = Rect2(Vector2(-inner_width/2, -inner_height/2), Vector2(inner_width, inner_height))
	var outer_rect = Rect2(Vector2(-outer_width/2, -outer_height/2), Vector2(outer_width, outer_height))
	
	draw_rect(inner_rect, shape.attributes.color, false, shape.attributes.width)
	draw_rect(outer_rect, shape.attributes.color, false, shape.attributes.width)

	var angle_step = (end_angle - start_angle) / n_angles
	for i in range(n_angles + 1):
		var angle = start_angle + i * angle_step
		
		# This is an approximation - would need actual box-line intersections for accuracy
		var ray_length = max(outer_width, outer_height)
		var ray_dir = Vector2(cos(angle), sin(angle))
		var ray_end = ray_dir * ray_length
		
		# Find intersections with both boxes (simplified approach)
		var inner_t = box_ray_intersection(inner_width/2, inner_height/2, Vector2.ZERO, ray_dir)
		var outer_t = box_ray_intersection(outer_width/2, outer_height/2, Vector2.ZERO, ray_dir)
		
		if inner_t > 0 and outer_t > 0:
			var inner_point = ray_dir * inner_t
			var outer_point = ray_dir * outer_t
			draw_line(inner_point, outer_point, shape.attributes.color, shape.attributes.width)
	
	# Draw intermediate boxes if n_radii > 0
	if n_radii > 0:
		var width_step = (outer_width - inner_width) / n_radii
		var height_step = (outer_height - inner_height) / n_radii
		for i in range(1, n_radii):
			var width = inner_width + i * width_step
			var height = inner_height + i * height_step
			var rect = Rect2(Vector2(-width/2, -height/2), Vector2(width, height))
			draw_rect(rect, shape.attributes.color, false, shape.attributes.width)
	
	# Restore transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# Helper for BPanda: Find intersection of ray with box
func box_ray_intersection(width: float, height: float, ray_origin: Vector2, ray_dir: Vector2) -> float:
	var t_min = 0.0
	var t_max = 1e10  # A very large number
	
	# Check x bounds
	if abs(ray_dir.x) > 0.0001:
		var t1 = (-width - ray_origin.x) / ray_dir.x
		var t2 = (width - ray_origin.x) / ray_dir.x
		t_min = max(t_min, min(t1, t2))
		t_max = min(t_max, max(t1, t2))
	
	# Check y bounds
	if abs(ray_dir.y) > 0.0001:
		var t1 = (-height - ray_origin.y) / ray_dir.y
		var t2 = (height - ray_origin.y) / ray_dir.y
		t_min = max(t_min, min(t1, t2))
		t_max = min(t_max, max(t1, t2))
	
	# Check if intersection exists
	if t_max >= t_min and t_max > 0:
		return t_min if t_min > 0 else t_max
	
	return -1  # No intersection

# 17. Segment Region
func draw_segment_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 4:  # Need at least two points
		return
	
	var points = []
	for i in range(0, shape.coord_list.size(), 2):
		if i + 1 < shape.coord_list.size():
			if shape.coord_format in ["fk5", "j2000"]:
				points.append(world_to_drawing(shape.coord_list[i], shape.coord_list[i+1]))
			else:
				points.append(image_to_drawing(shape.coord_list[i], shape.coord_list[i+1]))
	
	# Draw the line segments
	for i in range(points.size() - 1):
		if shape.attributes.get("dash", false):
			draw_dashed_line(points[i], points[i+1], shape.attributes.color, 
						 shape.attributes.width,
						 shape.attributes.get("dash_on", 10),
						 shape.attributes.get("dash_off", 5))
		else:
			draw_line(points[i], points[i+1], shape.attributes.color, shape.attributes.width)

# 18. Projection Region
func draw_projection_region(shape: RegionShape) -> void:
	if shape.coord_list.size() < 5:  # Need x1, y1, x2, y2, width
		return
	
	var start: Vector2
	var end: Vector2
	var width: float
	
	if shape.coord_format in ["fk5", "j2000"]:
		start = world_to_drawing(shape.coord_list[0], shape.coord_list[1])
		end = world_to_drawing(shape.coord_list[2], shape.coord_list[3])
		width = world_dist_to_pixels(shape.coord_list[0], shape.coord_list[1], shape.coord_list[4]/3600.0)
	else:
		start = image_to_drawing(shape.coord_list[0], shape.coord_list[1])
		end = image_to_drawing(shape.coord_list[2], shape.coord_list[3])
		width = shape.coord_list[4]
	
	# Direction vector of the line
	var dir = (end - start).normalized()
	# Perpendicular vector
	var perp = Vector2(-dir.y, dir.x) * (width / 2)
	
	# Draw the main line
	draw_line(start, end, shape.attributes.color, shape.attributes.width)
	
	# Draw the width indicators at both ends
	draw_line(start - perp, start + perp, shape.attributes.color, shape.attributes.width)
	draw_line(end - perp, end + perp, shape.attributes.color, shape.attributes.width)

# Helper Drawing Methods

# Draw an ellipse outline
func draw_ellipse(center: Vector2, rx: float, ry: float, color: Color, width: float = 1.0, segments: int = 32) -> void:
	var points = []
	for i in range(segments + 1):
		var angle = i * TAU / segments
		var point = Vector2(cos(angle) * rx, sin(angle) * ry)
		points.append(center + point)
	
	for i in range(segments):
		draw_line(points[i], points[i + 1], color, width)

# Draw a filled ellipse
func draw_ellipse_filled(center: Vector2, rx: float, ry: float, color: Color, segments: int = 32) -> void:
	var points = []
	for i in range(segments):
		var angle = i * TAU / segments
		var point = Vector2(cos(angle) * rx, sin(angle) * ry)
		points.append(center + point)
	
	draw_colored_polygon(points, color)

# Draw a dashed ellipse
func draw_dashed_ellipse(center: Vector2, rx: float, ry: float, color: Color, width: float = 1.0,
					  dash_length: float = 10.0, gap_length: float = 5.0, segments: int = 32) -> void:
	var points = []
	for i in range(segments + 1):
		var angle = i * TAU / segments
		var point = Vector2(cos(angle) * rx, sin(angle) * ry)
		points.append(center + point)
	
	# Calculate total perimeter (approximation)
	var perimeter = 0.0
	for i in range(segments):
		perimeter += points[i].distance_to(points[i + 1])
	
	# Draw dashed segments
	var dash_size = dash_length + gap_length
	var dash_count = int(perimeter / dash_size)
	var current_length = 0.0
	var dash_start_idx = 0
	var is_drawing = true  # Start with drawing
	
	for i in range(segments):
		var segment_length = points[i].distance_to(points[i + 1])
		var next_length = current_length + segment_length
		
		# Check if we're in a dash or gap
		while current_length < next_length:
			var dash_boundary = (int(current_length / dash_size) + (1 if is_drawing else 0)) * dash_size
			
			if dash_boundary < next_length:
				# We cross a dash/gap boundary in this segment
				var t = (dash_boundary - current_length) / segment_length
				var mid_point = points[i].lerp(points[i + 1], t)
				
				if is_drawing:
					draw_line(points[i].lerp(points[i + 1], (current_length - (int(current_length / dash_size) * dash_size)) / segment_length), 
						   mid_point, color, width)
				
				current_length = dash_boundary
				is_drawing = !is_drawing
			else:
				# This segment stays in the same dash/gap
				if is_drawing:
					draw_line(points[i], points[i + 1], color, width)
				break
		
		current_length = next_length

# Draw an elliptical arc
func draw_ellipse_arc(center: Vector2, rx: float, ry: float, start_angle: float, end_angle: float, 
					color: Color, width: float = 1.0, segments: int = 32) -> void:
	var points = []
	var angle_range = end_angle - start_angle
	
	for i in range(segments + 1):
		var angle = start_angle + (i * angle_range / segments)
		var point = Vector2(cos(angle) * rx, sin(angle) * ry)
		points.append(center + point)
	
	for i in range(segments):
		draw_line(points[i], points[i + 1], color, width)

# Draw a dashed line
func draw_dashed_line_region(from: Vector2, to: Vector2, color: Color, width: float = 1.0, 
				   dash_length: float = 10.0, gap_length: float = 5.0) -> void:
	var length = from.distance_to(to)
	var normal = (to - from).normalized()
	
	var dash_size = dash_length + gap_length
	var dash_count = int(length / dash_size)
	var remainder = length - (dash_count * dash_size)
	
	var start = from
	for i in range(dash_count):
		var end = start + normal * dash_length
		draw_line(start, end, color, width)
		start = start + normal * dash_size
	
	# Draw the remaining dash if it fits
	if remainder > dash_length:
		var end = start + normal * dash_length
		draw_line(start, end, color, width)
	elif remainder > 0:
		var end = start + normal * remainder
		draw_line(start, end, color, width)

# Draw a dashed rect
func draw_dashed_rect(rect: Rect2, color: Color, width: float = 1.0, 
				   dash_length: float = 10.0, gap_length: float = 5.0) -> void:
	var top_left = rect.position
	var top_right = Vector2(rect.position.x + rect.size.x, rect.position.y)
	var bottom_left = Vector2(rect.position.x, rect.position.y + rect.size.y)
	var bottom_right = rect.position + rect.size
	
	draw_dashed_line(top_left, top_right, color, width, dash_length, gap_length)
	draw_dashed_line(top_right, bottom_right, color, width, dash_length, gap_length)
	draw_dashed_line(bottom_right, bottom_left, color, width, dash_length, gap_length)
	draw_dashed_line(bottom_left, top_left, color, width, dash_length, gap_length)

# Draw an arrow head
func draw_arrow(pos: Vector2, direction: Vector2, color: Color, width: float = 1.0) -> void:
	var dir = (direction - pos).normalized()
	var arrow_size = max(width * 3, 8.0)
	
	var arrow_point1 = pos - dir.rotated(PI/4) * arrow_size
	var arrow_point2 = pos - dir.rotated(-PI/4) * arrow_size
	
	draw_line(pos, arrow_point1, color, width)
	draw_line(pos, arrow_point2, color, width)

# Helper for adding regions programmatically
func add_region(type: String, coord_format: String, coords: Array, attributes: Dictionary = {}) -> void:
	var shape = RegionShape.new()
	shape.name = type
	shape.coord_format = coord_format
	shape.coord_list = coords
	
	# Set default attributes
	shape.attributes = {
		"color": Color.GREEN, 
		"width": 2.0, 
		"fill": false
	}
	
	# Override with provided attributes
	for key in attributes:
		shape.attributes[key] = attributes[key]
	
	shapes.append(shape)
	queue_redraw()

# Clear all regions
func clear_regions() -> void:
	shapes.clear()
	queue_redraw()

# Save regions to file
func save_regions(path: String, format: String = "ds9") -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		print("Failed to open file for writing")
		return
	
	# Write header
	if format == "ds9":
		file.store_line("# Region file format: DS9 version 4.1")
		file.store_line("global color=green dashlist=8 3 width=1 font=\"helvetica 10 normal roman\" select=1 highlite=1 dash=0 fixed=0 edit=1 move=1 delete=1 include=1 source=1")
		file.store_line("image")
		
		# Write each region
		for shape in shapes:
			var line = shape.name
			var coords_str = ""
			
			# Format coordinates properly for each shape type
			match shape.name:
				"circle":
					if shape.coord_list.size() >= 3:
						coords_str = "(%f,%f,%f)" % [shape.coord_list[0], shape.coord_list[1], shape.coord_list[2]]
				"box":
					if shape.coord_list.size() >= 4:
						coords_str = "(%f,%f,%f,%f" % [shape.coord_list[0], shape.coord_list[1], shape.coord_list[2], shape.coord_list[3]]
						if shape.coord_list.size() >= 5:
							coords_str += ",%f" % shape.coord_list[4]
						coords_str += ")"
				"ellipse":
					if shape.coord_list.size() >= 4:
						coords_str = "(%f,%f,%f,%f" % [shape.coord_list[0], shape.coord_list[1], shape.coord_list[2], shape.coord_list[3]]
						if shape.coord_list.size() >= 5:
							coords_str += ",%f" % shape.coord_list[4]
				
# Draw a dashed arc
func draw_dashed_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, 
				  segments: int = 32, color: Color = Color.WHITE, width: float = 1.0, 
				  dash_length: float = 10.0, gap_length: float = 5.0) -> void:
	var points = []
	var angle_range = end_angle - start_angle
	
	# Generate points along the arc
	for i in range(segments + 1):
		var angle = start_angle + (i * angle_range / segments)
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		points.append(point)
	
	# Calculate total arc length (approximation)
	var arc_length = 0.0
	for i in range(segments):
		arc_length += points[i].distance_to(points[i + 1])
	
	# Draw dashed segments
	var dash_size = dash_length + gap_length
	var current_length = 0.0
	var is_drawing = true  # Start with drawing
	
	for i in range(segments):
		var segment_length = points[i].distance_to(points[i + 1])
		var next_length = current_length + segment_length
		
		# Check if we're in a dash or gap
		while current_length < next_length:
			var dash_boundary = (int(current_length / dash_size) + (1 if is_drawing else 0)) * dash_size
			
			if dash_boundary < next_length:
				# We cross a dash/gap boundary in this segment
				var t = (dash_boundary - current_length) / segment_length
				var mid_point = points[i].lerp(points[i + 1], t)
				
				if is_drawing:
					var start_t = (current_length - (int(current_length / dash_size) * dash_size)) / segment_length
					var start_point = points[i].lerp(points[i + 1], start_t if start_t >= 0 else 0)
					draw_line(start_point, mid_point, color, width)
				
				current_length = dash_boundary
				is_drawing = !is_drawing
			else:
				# This segment stays in the same dash/gap
				if is_drawing:
					draw_line(points[i], points[i + 1], color, width)
				break
		
		current_length = next_length
