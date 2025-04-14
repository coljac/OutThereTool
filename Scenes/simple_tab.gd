@tool
extends TabContainer

signal new_tab_requested
var galaxy_display = preload("res://Scenes/galaxy_display.tscn")

# Counter for naming new tabs
var new_tab_counter = 1
var plus_tab: Control

func _ready():
	# Connect to the tab_changed signal
	tab_changed.connect(_on_tab_changed)
	
	# Add the "+" tab
	plus_tab = Control.new()
	plus_tab.name = "+"
	add_child(plus_tab)
	set_tab_title(get_tab_count() - 1, "+")

func _process(_delta):
	# Ensure the "+" tab is always the last tab
	if plus_tab and plus_tab.get_index() != get_tab_count() - 1:
		move_child(plus_tab, get_tab_count() - 1)

func _on_tab_changed(tab_index: int):
	# If the "+" tab is selected, create a new tab and select it
	if tab_index == plus_tab.get_index():
		var new_tab_index = _create_new_tab()
		current_tab = new_tab_index

func _create_new_tab() -> int:
	# Create a new tab with a default name
	var new_tab = galaxy_display.instantiate()
	var tab_name = "New" + str(new_tab_counter)
	new_tab.name = tab_name
	new_tab_counter += 1
	
	# Insert the new tab before the "+" tab
	add_child(new_tab)
	move_child(new_tab, get_tab_count() - 2)
	
	# Emit signal
	new_tab_requested.emit()
	
	return get_tab_count() - 2
