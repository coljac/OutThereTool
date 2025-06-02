extends PanelContainer

const ThemeUtils = preload("res://theme/ThemeUtils.gd")

# Signals
signal zoom_in_pressed
signal zoom_out_pressed
signal reference_pressed

# Node references
@onready var visuals_button = $ViewportOptions/LeftMenu/Visuals
@onready var reference_button = $ViewportOptions/LeftMenu/Reference
@onready var snap_button = $ViewportOptions/LeftMenu/Snapping/SnapButton
@onready var zoom_out_button = $ViewportOptions/ZoomContainer/ZoomOutButton
@onready var zoom_in_button = $ViewportOptions/ZoomContainer/ZoomInButton
@onready var zoom_label = $ViewportOptions/ZoomContainer/ZoomLabel

# Current zoom level
var zoom_level = 100

func _ready():
	# Connect signals
	zoom_in_button.pressed.connect(_on_zoom_in_button_pressed)
	zoom_out_button.pressed.connect(_on_zoom_out_button_pressed)
	
	# Set up the toolbar style
	_setup_toolbar_style()

func _setup_toolbar_style():
	# Create a stylebox for the toolbar
	var toolbar_stylebox = StyleBoxFlat.new()
	toolbar_stylebox.bg_color = ThemeUtils.common_panel_inner_color.lerp(Color.WHITE, 0.01)
	toolbar_stylebox.set_content_margin_all(4)
	add_theme_stylebox_override("panel", toolbar_stylebox)

func _on_zoom_in_button_pressed():
	zoom_level = min(zoom_level + 25, 500)
	zoom_label.text = str(zoom_level) + "%"
	emit_signal("zoom_in_pressed")

func _on_zoom_out_button_pressed():
	zoom_level = max(zoom_level - 25, 25)
	zoom_label.text = str(zoom_level) + "%"
	emit_signal("zoom_out_pressed")

func _on_reference_pressed():
	reference_pressed.emit()