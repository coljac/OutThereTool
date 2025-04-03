extends Node

const ThemeUtils = preload("res://theme/ThemeUtils.gd")

func _ready():
	# Apply the theme to the application
	ThemeUtils.generate_and_apply_theme()
	print("Theme applied successfully!")