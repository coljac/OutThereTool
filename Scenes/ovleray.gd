extends Control
# var x_pixel: float = 0.0
# var cursor_line_color: Color = Color(1, 0, 0, 1)
# var cursor_line_width: float = 1.0

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
