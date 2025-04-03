@tool
extends EditorScript

const ThemeUtils = preload("res://theme/ThemeUtils.gd")

func _run():
	# Generate the theme
	var theme = ThemeUtils.generate_theme()
	
	# Save the theme resource
	var err = ResourceSaver.save(theme, "res://theme/theme.tres")
	if err != OK:
		print("Error saving theme resource: ", err)
	else:
		print("Theme resource saved successfully!")