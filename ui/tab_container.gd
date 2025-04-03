extends TabContainer

signal tab_added(tab_index)
signal tab_closed(tab_index)

var tab_scene = null # Will be set by the main UI script
var tab_count = 0
var tabs_data = [] # To keep track of our tabs
# Flag to prevent recursive tab creation
var _is_processing_tab_change = false
# Add tab button
var add_tab_button: Button

func _ready():
	# Connect to the tab_changed signal
	tab_changed.connect(_on_tab_changed)
	
	# Create the add tab button
	_create_add_tab_button()
func _create_add_tab_button():
	# Create a button to add new tabs
	add_tab_button = Button.new()
	add_tab_button.icon = load("res://GodSVG/assets/icons/CreateTab.svg")
	add_tab_button.tooltip_text = "Add Tab"
	add_tab_button.focus_mode = Control.FOCUS_NONE
	add_tab_button.flat = true
	add_tab_button.custom_minimum_size = Vector2(24, 24)
	add_tab_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_tab_button.theme_type_variation = "IconButton"
	
	# Position the button to the right of the tabs
	add_child(add_tab_button)
	
	# Connect the button's pressed signal
	add_tab_button.pressed.connect(_on_add_tab_button_pressed)
	
	# Make sure the button is always visible
	resized.connect(_update_add_tab_button_position)
func _update_add_tab_button_position():
	if add_tab_button:
		# Position the button to the right of the tabs
		var last_tab_idx = get_tab_count() - 1
		var last_tab_pos = 0
		
		if last_tab_idx >= 0:
			# Calculate the position based on the number of tabs
			# Each tab has approximately the same width
			var tab_width = 150  # Approximate width of a tab
			last_tab_pos = (last_tab_idx + 1) * tab_width
		
		add_tab_button.position = Vector2(last_tab_pos + 5, 0)
		add_tab_button.position = Vector2(last_tab_pos + 5, 0)

func create_tab(title: String) -> int:
	var tab_index = get_tab_count()
	
	# Create a new instance of the tab scene
	if tab_scene:
		var tab_instance = tab_scene.instantiate()
		tab_instance.name = "Tab" + str(tab_count)
		add_child(tab_instance)
		
		# Set the tab title
		set_tab_title(tab_index, title)
		
		# Create a close button for this tab
		# Note: In Godot 4, we need to handle close buttons differently
		# We'll add this functionality in a future update
		
		tab_count += 1
		emit_signal("tab_added", tab_index)
		
		# Update the add tab button position
		_update_add_tab_button_position()
	
	return tab_index

func _on_add_tab_button_pressed():
	# Add a new tab
	var new_tab_index = create_tab("Galaxy View " + str(tab_count + 1))
	
	# Select the new tab
	current_tab = new_tab_index

func _on_tab_changed(tab_index: int):
	# Update the add tab button position when tabs change
	_update_add_tab_button_position()

func _on_close_button_pressed(tab_index: int):
	# Get the tab control
	var tab_control = get_tab_control(tab_index)
	if tab_control:
		# Remove the tab control
		remove_child(tab_control)
		tab_control.queue_free()
		
		# Update our tab management logic
		tab_count -= 1
		
		# Emit the signal
		emit_signal("tab_closed", tab_index)

func set_tab_scene(scene_path: String):
	tab_scene = load(scene_path)
