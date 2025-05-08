extends Control

# Node references
@onready var top_bar = $VBoxContainer/TopBar
@onready var tab_container = $VBoxContainer/HSplitContainer/MainPanel/TabContainer
@onready var left_panel = $VBoxContainer/HSplitContainer/LeftPanel
@onready var object_id_edit = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBoxContainer/ObjectIDEdit
@onready var search_button = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBoxContainer/SearchButton
@onready var apply_filters_button = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBoxContainer/ApplyFiltersButton
@onready var min_redshift = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBoxContainer/RedshiftRangeContainer/MinRedshift
@onready var max_redshift = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBoxContainer/RedshiftRangeContainer/MaxRedshift

# Path to the GalaxyDisplay scene
const GALAXY_DISPLAY_SCENE = "res://Scenes/galaxy_display.tscn"

# Current zoom level
var zoom_level = 100

var objects = []
var obj_index = 0

func _ready():
	# Connect signals from the left panel	
	# Connect signals from the top bar
	top_bar.more_options_pressed.connect(_on_more_options_pressed)
	top_bar.settings_pressed.connect(_on_settings_pressed)
	
	objects = DataManager.get_gals()

	# Connect signals from the tab container
	tab_container.tab_added.connect(_on_tab_added)
	tab_container.tab_closed.connect(_on_tab_closed)
	
	# Connect signals from the left panel
	search_button.pressed.connect(_on_search_button_pressed)
	apply_filters_button.pressed.connect(_on_apply_filters_button_pressed)
	
	# Set the tab scene for the tab container
	tab_container.set_tab_scene(GALAXY_DISPLAY_SCENE)
	
	# Add an initial tab
	_add_initial_tab()
	set_process_input(true)
	%ObjectViewing.set_galaxy_details(objects[obj_index])
	DataManager.connect("updated_data", %ObjectViewing.tick)
	set_process(false) # Disable _process by default


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next"):
		print("NEXT")
		next_object()
		get_viewport().set_input_as_handled()


func save_galaxy(vals: Dictionary):
	var gal_id = objects[obj_index]['id']
	DataManager.update_gal(gal_id, vals['status'], vals['comments'])


func next_object() -> void:
	# for ch in $VBoxContainer/MarginContainer.get_children():
		# ch.queue_free()
	var gal_display = %SimpleTab.get_tab_control(0)
	# var newbox = gal_display.instantiate()
	obj_index += 1
	if obj_index >= objects.size():
		obj_index = 0
	gal_display.set_object_id(objects[obj_index]['id'])
	%ObjectViewing.set_galaxy_details(objects[obj_index])

	# newbox.path = objects[obj_index][0]
	# newbox.object_id = objects[obj_index][1]
	# newbox.object_id = "uma-03_02122"
	# newbox.name = "GalaxyDisplay"
	# $VBoxContainer/MarginContainer.add_child(newbox)
	# newbox.load_object()
# 
func _add_initial_tab():
	# Add the first tab with a GalaxyDisplay
	var tab_index = tab_container.create_tab("GalaxyView")
	
	# Select the first tab
	tab_container.current_tab = tab_index

func _on_more_options_pressed():
	# Handle the more options button press
	print("Moreoptionspressed")

func _on_settings_pressed():
	# Handle the settings button press
	print("Settingspressed")

func _on_tab_added(tab_index):
	# Handle a new tab being added
	print("Tabaddedatindex: ", tab_index)
	
	# Get the GalaxyDisplay instance in this tab
	var galaxy_display = tab_container.get_tab_control(tab_index)
	if galaxy_display:
		# Configure the GalaxyDisplay
		# Set the object_id for this tab
		if galaxy_display.has_method("set_object_id"):
			galaxy_display.set_object_id("outthere-hudfn_04375")

func _on_tab_closed(tab_index):
	# Handle a tab being closed
	print("Tabclosedatindex: ", tab_index)

func _on_search_button_pressed():
	# Get the object ID from the text field
	var object_id = object_id_edit.text
	print("Searching for object: ", object_id)
	
	# Get the current tab's GalaxyDisplay
	var current_tab_index = tab_container.current_tab
	var galaxy_display = tab_container.get_tab_control(current_tab_index)
	
	# Set the object ID
	if galaxy_display and galaxy_display.has_method("set_object_id"):
		galaxy_display.set_object_id(object_id)

func _on_apply_filters_button_pressed():
	# Get the redshift range
	var min_z = min_redshift.value
	var max_z = max_redshift.value
	print("Applyingfilters - Redshiftrange: ", min_z, "to", max_z)
	
	# Here you would apply the filters to the GalaxyDisplay
	# This is a placeholder for future implementation
