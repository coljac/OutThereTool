extends Control
class_name Temporar
@export var res: Resource

@onready var fits_image: FitsImage = $FitsImage


func _ready() -> void:
	fits_image._set_file("data/uma-03_09452.stack.fits")
	var data2d = FitsHelper.get_2d_spectrum("./data/uma-03_09452.stack.fits")
	var path = fits_image.fits_path
	var f = "F200W"
	var spec_display = fits_image as FitsImage
	var pa = data2d.keys()[0]
	spec_display.fits = data2d[pa][f]['fits']
	spec_display.hdu = data2d[pa][f]['index']
	spec_display.set_image(path, data2d[pa][f]['index'])
	spec_display.visible = true
	spec_display.set_label("AAAA")
	spec_display._make_texture()
	queue_redraw()
	$OTImage._load_object()
	$OTImage._make_texture()
	# pass
