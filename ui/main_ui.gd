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

func _ready():
	# Connect signals from the top bar
	top_bar.more_options_pressed.connect(_on_more_options_pressed)
	top_bar.settings_pressed.connect(_on_settings_pressed)
	
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

func _add_initial_tab():
	# Add the first tab with a GalaxyDisplay
	var tab_index = tab_container.create_tab("Galaxy View")
	
	# Select the first tab
	tab_container.current_tab = tab_index

func _on_more_options_pressed():
	# Handle the more options button press
	print("More options pressed")

func _on_settings_pressed():
	# Handle the settings button press
	print("Settings pressed")

func _on_tab_added(tab_index):
	# Handle a new tab being added
	print("Tab added at index: ", tab_index)
	
	# Get the GalaxyDisplay instance in this tab
	var galaxy_display = tab_container.get_tab_control(tab_index)
	if galaxy_display:
		# Configure the GalaxyDisplay
		# Set the object_id for this tab
		if galaxy_display.has_method("set_object_id"):
			galaxy_display.set_object_id("uma-03_02484")

func _on_tab_closed(tab_index):
	# Handle a tab being closed
	print("Tab closed at index: ", tab_index)

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
	print("Applying filters - Redshift range: ", min_z, " to ", max_z)
	
	# Here you would apply the filters to the GalaxyDisplay
	# This is a placeholder for future implementation

