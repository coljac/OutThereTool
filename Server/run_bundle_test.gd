extends SceneTree

func _init():
	# Load and run the new bundle fix test
	var test_script = preload("res://Server/test_bundle_fix.gd")
	var test = test_script.new()
	
	# The test will run automatically in its _init() function
	# and will call quit() when done