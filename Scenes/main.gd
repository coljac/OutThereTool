extends Control

# Title not showing
# Sideways ticks

@onready var plot = $PlotDisplay

func _ready():
	# Set up the plot
	#plot.set_limits(-5.0, 15.0, -2.0, 10.0)
	#plot.set_tick_spacing(1.0, 1.0)
	plot.set_title("Example Plot")
	plot.set_limits(5000, 8000, 0.0, 2.0, true)
	plot.set_tick_spacing(500, 0.1)

	var spec = load_a_spectrum()
	# Add a sine wave series
	var sine_points = spec
	#for x in range(-50, 151):
		#var x_val = x / 10.0
		#var y_val = sin(x_val) * 3.0 + 4.0
		#sine_points.append(Vector2(x_val, y_val))
	#
	plot.add_series(sine_points, Color(0.2, 0.4, 0.8), 1.0, false, 3.0)
	
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
	
	# You can also update the plot dynamically
	# Uncomment to see animation
	# set_process(true)

# Example of dynamic plot update
func _process(delta):
	# Add a moving point
	var time = Time.get_ticks_msec() / 1000.0
	var x = 5 + 3 * sin(time)
	var y = 5 + 3 * cos(time)
	
	var points = [Vector2(x, y)]
	
	# Clear previous dynamic points and add new one
	# This assumes the last series is our dynamic point
	if plot.series_list.size() > 2:
		plot.remove_series(2)
	
	plot.add_series(points, Color(0, 0.8, 0), 2.0, true, 6.0)


func _on_h_slider_value_changed(value: float) -> void:
	#plot.set_tick_spacing(1.0 * value/100, 1.0)
	var pts = plot.series_list[0].points
	for x in range(pts.size()):
		pts[x][0] += value/10
		#print(x)
	#print(plot.series_list[0])
	
func load_a_spectrum() -> Array:
	var file = FileAccess.open("res://spec2.csv", FileAccess.READ)
	var results = []
	
	while true:
		var line = file.get_csv_line()
		if line[0] == "":
			break
		results.append(Vector2(float(line[0]), float(line[1])))
		
	
	return results
