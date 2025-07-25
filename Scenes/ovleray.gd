extends Control

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var x_pixel = get_parent()._microns_to_pixels(get_parent().cursor_wavelength)
	var cursor_line_color = get_parent().cursor_line_color
	var cursor_line_width = get_parent().cursor_line_width

	draw_line(
		Vector2(x_pixel, 0),
		Vector2(x_pixel, size.y),
		cursor_line_color,
		cursor_line_width
	)
