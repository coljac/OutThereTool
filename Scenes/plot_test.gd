extends Control

@onready var plot = $PlotDisplay

func _ready():
	# Set up the plot
	plot.set_limits(-5.0, 15.0, -2.0, 10.0)
	plot.set_tick_spacing(1.0, 1.0)
	plot.set_title("Plot Demo - C: toggle crosshair, Left-drag: zoom, Right-click: reset")
	
	# Set axis labels
	plot.set_x_label("Wavelength (μm)")
	plot.set_y_label("Flux (arbitrary units)")
	
	# Enable input processing for keyboard shortcuts
	set_process_input(true)
	
	# Add a sine wave series
	var sine_points = []
	for x in range(-50, 151):
		var x_val = x / 10.0
		var y_val = sin(x_val) * 3.0 + 4.0
		sine_points.append(Vector2(x_val, y_val))
	
	plot.add_series(sine_points, Color(0.2, 0.4, 0.8), 2.0, true, 3.0)
	
	# Add a linear series
	var linear_points = []
	for x in range(-50, 151):
		var x_val = x / 10.0
		var y_val = 0.5 * x_val + 1.0
		linear_points.append(Vector2(x_val, y_val))
	
	plot.add_series(linear_points, Color(0.8, 0.2, 0.2), 2.0)
	
	# Add some annotations
	plot.add_annotation(Vector2(0, 0), "Origin", Color(0, 0, 0), 14)
	plot.add_annotation(Vector2(10, 5), "Point (10,5)", Color(0, 0.5, 0), 14)
	
	# Add constant lines
	plot.add_constant_line(0, true, Color(0, 0, 0, 0.5), 1.0, true)  # Vertical line at x=0
	plot.add_constant_line(0, false, Color(0, 0, 0, 0.5), 1.0, true)  # Horizontal line at y=0
	plot.add_constant_line(5, true, Color(1, 0, 0, 0.7), 1.0)  # Vertical line at x=5
	
	# Add a test case for clipping - a line that crosses the plot diagonally
	var clipping_test_points = [
		Vector2(-20, -10),  # Far outside bottom-left
		Vector2(30, 20)     # Far outside top-right
	]
	plot.add_series(clipping_test_points, Color(0.8, 0.8, 0.2), 3.0)
	
	# Add another test case - a zigzag line that enters and exits the plot multiple times
	var zigzag_points = []
	for i in range(-10, 30):
		var x = i
		var y = 15 if i % 4 < 2 else -5  # Alternates between y=15 (outside top) and y=-5 (outside bottom)
		zigzag_points.append(Vector2(x, y))
	plot.add_series(zigzag_points, Color(0.5, 0.2, 0.8), 2.0)
	
	# Add a series with error bars (simulating spectral data)
	var spectral_points = []
	var y_errors = []
	for x in range(0, 100, 10):
		var x_val = x / 10.0
		var y_val = 3.0 + 0.5 * sin(x_val)
		var error = 0.2 + 0.1 * randf()  # Random error between 0.2 and 0.3
		
		spectral_points.append(Vector2(x_val, y_val))
		y_errors.append(error)
	
	plot.add_series(
		spectral_points,
		Color(0.2, 0.6, 0.8),
		2.0,
		true,  # draw points
		4.0,   # point size
		[],    # no x errors
		y_errors,
		Color(0.2, 0.6, 0.8, 0.7)  # slightly transparent error bars
	)
	
	# Add a series drawn as steps (histogram-like) with error bars
	var step_points = []
	var step_y_errors = []
	for x in range(0, 110, 10):
		var x_val = x / 10.0
		var y_val = 7.0 + randf() * 2.0  # Random value between 7 and 9
		step_points.append(Vector2(x_val, y_val))
		step_y_errors.append(0.4)  # Constant error for demonstration
	
	plot.add_series(
		step_points,
		Color(0.8, 0.4, 0.0),  # orange color
		2.0,
		true,   # draw points
		4.0,
		[],     # no x errors
		step_y_errors,  # y errors
		Color(0.8, 0.4, 0.0, 0.7),  # slightly transparent error bars
		1.0,
		5.0,
		true    # draw as steps
	)
	
	# Enable dynamic updates to see animation
	set_process(true)

# Handle input for toggling crosshair
func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_C:
			# Toggle crosshair
			plot.toggle_crosshair(not plot.show_crosshair)
			
			# Update title to show crosshair status
			var status = "ON" if plot.show_crosshair else "OFF"
			plot.set_title("Example Plot - Crosshair: %s (Press C to toggle)" % status)

# Example of dynamic plot update
func _process(delta):
	# Add a moving line that goes in and out of the plot area
	var time = Time.get_ticks_msec() / 1000.0
	
	# Create a line that moves in and out of the plot area
	var dynamic_points = []
	
	# First point - fixed outside the left edge
	dynamic_points.append(Vector2(-10, 5))
	
	# Second point - moves in a circle with large radius, going in and out of the plot
	var x = 5 + 12 * sin(time)
	var y = 5 + 12 * cos(time)
	dynamic_points.append(Vector2(x, y))
	
	# Clear previous dynamic points and add new ones
	# This assumes the last series is our dynamic line
	if plot.series_list.size() > 6:  # We now have 6 static series
		plot.remove_series(6)
	
	plot.add_series(dynamic_points, Color(0, 0.8, 0), 2.0, true, 6.0)
	
	# Update the title to show the current coordinates
	plot.set_title("Example Plot - Dynamic Point: (%.1f, %.1f)" % [x, y])
