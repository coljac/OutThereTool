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
@onready var field_list = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBoxContainer/FieldList
@onready var cb_flux = %CBFlux
@onready var cb_bestfit = %CBBestfit
@onready var cb_errors = %CBErrors
@onready var cb_contam = %CBContam
var all_lock = false
var locked = false
var image_settings = {}

# Path to the GalaxyDisplay scene
const GALAXY_DISPLAY_SCENE = "res://Scenes/galaxy_display.tscn"

# Current zoom level
var zoom_level = 100

var objects = []
var obj_index = 0
var dialog_open = false

func _ready():
	# Connect signals from the left panel	
	# Connect signals from the top bar
	top_bar.more_options_pressed.connect(_on_more_options_pressed)
	top_bar.settings_pressed.connect(_on_settings_pressed)
	top_bar.preferences_selected.connect(show_settings)
	
	# Initialize field selection
	_populate_field_list()
	_set_objects(DataManager.get_gals(0.0, 10.0, 0, DataManager.get_current_field()))

	# Connect signals from the tab container
	tab_container.tab_added.connect(_on_tab_added)
	tab_container.tab_closed.connect(_on_tab_closed)
	
	# Connect signals from the left panel
	search_button.pressed.connect(_on_search_button_pressed)
	apply_filters_button.pressed.connect(_on_apply_filters_button_pressed)
	field_list.item_selected.connect(_on_field_selected)
	
	# Connect checkbox signals
	cb_flux.toggled.connect(_on_flux_toggled)
	cb_bestfit.toggled.connect(_on_bestfit_toggled)
	cb_errors.toggled.connect(_on_errors_toggled)
	cb_contam.toggled.connect(_on_contam_toggled)
	
	# Set default checkbox states
	cb_flux.button_pressed = true
	cb_bestfit.button_pressed = true
	cb_errors.button_pressed = true
	cb_contam.button_pressed = true
	# Set the tab scene for the tab container
	tab_container.set_tab_scene(GALAXY_DISPLAY_SCENE)
	# Add an initial tab
	_add_initial_tab()
	set_process_input(true)
	if objects.size() > 0:
		var galaxy_with_user_data = DataManager.get_galaxy_with_user_data(objects[obj_index]['id'])
		%ObjectViewing.set_galaxy_details(galaxy_with_user_data)
	DataManager.connect("updated_data", %ObjectViewing.tick)
	DataManager.connect("updated_data", update_cache)
	set_process(false) # Disable _process by default
	_goto_object(0)
	for otimage in get_tree().get_nodes_in_group("images"):
		if otimage as OTImage:
			otimage.settings_changed.connect(image_settings_changed)

func image_settings_changed(settings: Dictionary):
	image_settings = settings
	if all_lock:
		for otimage in get_tree().get_nodes_in_group("images"):
			if otimage as OTImage:
				otimage.use_settings(settings)

func update_cache(success: bool):
	if success:
		_set_objects(DataManager.get_gals(0.0, 10.0, 0, DataManager.get_current_field()))

func _unhandled_input(event: InputEvent) -> void:
	# Block all input when dialog is open
	if dialog_open:
		return
		
	if event.is_action_released("next"):
		print("NEXT")
		next_object()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("prev"):
		prev_object()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("help"):
		if $HelpPanel.visible:
			$HelpPanel.hide()
		else:
			$HelpPanel.show()
		get_viewport().set_input_as_handled()
	if event.is_action("qop_1"):
		update_status(0)
		get_viewport().set_input_as_handled()
	if event.is_action("qop_2"):
		update_status(1)
		get_viewport().set_input_as_handled()
	if event.is_action("qop_3"):
		update_status(2)
		get_viewport().set_input_as_handled()
	if event.is_action("qop_4"):
		update_status(3)
		get_viewport().set_input_as_handled()
	if event.is_action("qop_5"):
		update_status(4)
		get_viewport().set_input_as_handled()
	if event.is_action("qop_1"):
		update_status(0)
		get_viewport().set_input_as_handled()
	if event.is_action("flag_bad"): # is_action_pressed("flag_bad"):
		update_status(2)
		get_viewport().set_input_as_handled()
	if event.is_action("flag_good"):
		update_status(0)
		get_viewport().set_input_as_handled()
	if event.is_action("flag_ok"):
		update_status(1)
		get_viewport().set_input_as_handled()
	if event.is_action("comment") and not event.shift_pressed:
		%ObjectViewing.get_node("%Comments").grab_focus()


func update_status(status: int):
	%ObjectViewing.set_status(status)


func save_galaxy(vals: Dictionary):
	var gal_id = objects[obj_index]['id']
	DataManager.update_gal(gal_id, vals['status'], vals['comments'])


func get_object(obj: String) -> void:
	var gal_display = %SimpleTab.get_tab_control(0)
	obj_index += 1
	gal_display.set_object_id(obj)
	gal_display.name = obj
	var index: int = %ObjectsList.selected - 1
	obj_index = index
	var galaxy_with_user_data = DataManager.get_galaxy_with_user_data(objects[index]['id'])
	%ObjectViewing.set_galaxy_details(galaxy_with_user_data)
	%ObjectsList.selected = 0


func next_object():
	_goto_object(1)


func prev_object():
	_goto_object(-1)


func _goto_object(step: int = 1) -> void:
	# for ch in $VBoxContainer/MarginContainer.get_children():
		# ch.queue_free()
	var gal_display = %SimpleTab.get_tab_control(0)
	# var newbox = gal_display.instantiate()
	obj_index += step
	if obj_index >= objects.size():
		obj_index = 0
	if obj_index < 0:
		obj_index = objects.size() - 1
	print("DEBUG: About to set object ID to: ", objects[obj_index]['id'])
	gal_display.set_object_id(objects[obj_index]['id'])
	print("DEBUG: Called set_object_id, updating details...")
	var galaxy_with_user_data = DataManager.get_galaxy_with_user_data(objects[obj_index]['id'])
	%ObjectViewing.set_galaxy_details(galaxy_with_user_data)
	gal_display.name = objects[obj_index]['id']
	print("DEBUG: Object switch completed")


	# Preload next object in background
	_preload_next_object()

	# newbox.path = objects[obj_index][0]
	# newbox.object_id = objects[obj_index][1]
	# newbox.object_id = "uma-03_02122"
	# newbox.name = "GalaxyDisplay"
	# $VBoxContainer/MarginContainer.add_child(newbox)
	# newbox.load_object()
# 
func _add_initial_tab():
	# Use the existing GalaxyDisplay in SimpleTab instead of creating a new one
	# The SimpleTab already has a pre-instantiated GalaxyDisplay
	pass

func _on_more_options_pressed():
	# Handle the more options button press
	print("Moreoptionspressed")

func _on_settings_pressed():
	# This just opens the dropdown menu - actual preferences dialog 
	# is triggered by the preferences_selected signal
	pass

func _on_tab_added(tab_index):
	# Handle a new tab being added
	print("Tabaddedatindex: ", tab_index)
	
	# Get the GalaxyDisplay instance in this tab
	var galaxy_display = tab_container.get_tab_control(tab_index)
	if galaxy_display:
		# Configure the GalaxyDisplay
		# Set the object_id for this tab
		if galaxy_display.has_method("set_object_id"):
			pass
			# galaxy_display.set_object_id("outthere-hudfn_04375")

func _on_tab_closed(tab_index):
	# Handle a tab being closed
	print("Tabclosedatindex: ", tab_index)

func _on_import_button_pressed():
	# Handle the import button press
	print("Import button pressed")
	
	# Create and configure file dialog
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.txt", "Text files")
	file_dialog.add_filter("*.csv", "CSV files")
	file_dialog.title = "Import Object IDs"
	
	# Add to scene tree temporarily
	add_child(file_dialog)
	
	# Connect signal and show dialog
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_file_selected(path: String):
	print("Selected file: ", path)
	
	# Read the file
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file: " + path)
		return
	
	var object_ids = []
	var line_number = 0
	
	# Parse file line by line to extract object IDs
	while not file.eof_reached():
		line_number += 1
		var line = file.get_line().strip_edges()
		
		# Skip empty lines
		if line.length() == 0:
			continue
			
		# Handle CSV - take first column if comma-separated
		if path.ends_with(".csv"):
			var parts = line.split(",")
			if parts.size() > 0:
				line = parts[0].strip_edges()
		
		object_ids.append(line)
	
	file.close()
	
	print("Found ", object_ids.size(), " object IDs, querying database...")
	
	# Query full object data from database
	var imported_objects = DataManager.get_gals_by_ids(object_ids)
	
	print("Successfully imported ", imported_objects.size(), " objects from database")
	
	# Replace current objects with imported ones
	_set_objects(imported_objects)
	
	# Reset to first object and load it
	obj_index = 0
	if imported_objects.size() > 0:
		_goto_object(0)
	
	# Clean up file dialog
	for child in get_children():
		if child is FileDialog:
			child.queue_free()
	
func _on_search_button_pressed():
	# Get the object ID from the text field
	var object_id = object_id_edit.text
	if object_id.length() == 0:
		return
	print("Searching for object: ", object_id)
	for obj in objects:
		if obj['id'].contains(object_id):
			get_object(obj['id'])
			object_id_edit.text = ""
			break
	# # Get the current tab's GalaxyDisplay
	# var current_tab_index = tab_container.current_tab
	# var galaxy_display = tab_container.get_tab_control(current_tab_index)
	
	# # Set the object ID
	# if galaxy_display and galaxy_display.has_method("set_object_id"):
	# 	galaxy_display.set_object_id(object_id)

func _set_objects(new_objects: Array) -> void:
	# Set the objects to be displayed
	objects = new_objects
	%ObjectsList.clear()
	%ObjectsList.add_item("%d objects" % objects.size())
	# get_item_index(0).set_text("%d objects" % objects.size())
	for i in range(objects.size()):
	# for i in range(min(objects.size(), 100)):
		%ObjectsList.add_item(objects[i]['id'])

	# Update the GalaxyDisplay with the new objects
	var current_tab_index = tab_container.current_tab
	var galaxy_display = tab_container.get_tab_control(current_tab_index)
	if galaxy_display and galaxy_display.has_method("set_galaxy_details"):
		galaxy_display.set_galaxy_details(objects[obj_index])


func _populate_field_list():
	var fields = DataManager.get_unique_fields()
	field_list.clear()
	
	if fields.size() > 0:
		# Populate the dropdown
		var current_field = DataManager.get_current_field()
		var selected_index = 0
		
		for i in range(fields.size()):
			var field = fields[i]
			field_list.add_item(field)
			# If this is the current field from DataManager, select it
			if field == current_field:
				selected_index = i
		
		field_list.selected = selected_index
	else:
		# No fields available
		field_list.add_item("No fields")
		DataManager.set_current_field("")

func _on_field_selected(index: int):
	var selected_field = field_list.get_item_text(index)
	DataManager.set_current_field(selected_field)
	# Refresh the objects list with the new field filter
	var min_z = min_redshift.value
	var max_z = max_redshift.value
	var filters = %FiltersSelect.selected + 1
	_set_objects(DataManager.get_gals(min_z, max_z, filters, selected_field))
	# Reset to first object when changing fields
	obj_index = 0
	if objects.size() > 0:
		_goto_object(0)

func _on_apply_filters_button_pressed():
	# Get the redshift range
	var min_z = min_redshift.value
	var max_z = max_redshift.value
	var filters = %FiltersSelect.selected + 1
	var current_field = DataManager.get_current_field()
	print("Applying filters - Redshift range: ", min_z, "to", max_z, " with filters: ", filters, " field: ", current_field)
	_set_objects(DataManager.get_gals(min_z, max_z, filters, current_field))


func _preload_next_object() -> void:
	# Preload just the next object to avoid overwhelming HTTP pool
	print("Starting background preload from index: ", obj_index)
	
	var next_index = obj_index + 1
	if next_index >= objects.size():
		next_index = 0 # Wrap around
	
	if next_index < objects.size():
		var next_object_id = objects[next_index]['id']
		
		# Use the global cache loader directly for background preloading
		var loader = GlobalResourceCache.get_loader()
		
		# Only preload bundle (not individual resources)
		var bundle_id = next_object_id + "_bundle.tres"
		
		if not loader.is_cached(bundle_id):
			print("Background preloading bundle: ", next_object_id)
			loader.preload_resource(bundle_id)

func _on_objects_list_item_selected(index: int) -> void:
	if index == 0:
		return
	var obj = %ObjectsList.get_item_text(index)
	get_object(obj)

# Checkbox callbacks for 1D plot visibility
func _on_flux_toggled(pressed: bool) -> void:
	var galaxy_display = %SimpleTab.get_tab_control(0)
	if galaxy_display and galaxy_display.has_method("toggle_flux_visibility"):
		galaxy_display.toggle_flux_visibility(pressed)

func _on_bestfit_toggled(pressed: bool) -> void:
	var galaxy_display = %SimpleTab.get_tab_control(0)
	if galaxy_display and galaxy_display.has_method("toggle_bestfit_visibility"):
		galaxy_display.toggle_bestfit_visibility(pressed)

func _on_errors_toggled(pressed: bool) -> void:
	var galaxy_display = %SimpleTab.get_tab_control(0)
	if galaxy_display and galaxy_display.has_method("toggle_errors_visibility"):
		galaxy_display.toggle_errors_visibility(pressed)

func _on_contam_toggled(pressed: bool) -> void:
	var galaxy_display = %SimpleTab.get_tab_control(0)
	if galaxy_display and galaxy_display.has_method("toggle_contam_visibility"):
		galaxy_display.toggle_contam_visibility(pressed)

func show_settings():
	# Show the settings dialog
	dialog_open = true
	%UserEntry.show()
	
	# Load existing user data if available
	var credentials = DataManager.get_user_credentials()
	%UserEntry.get_node("%Username").text = credentials.username
	%UserEntry.get_node("%Password").text = credentials.password

func set_user_details(user: String, password: String) -> void:
	%UserEntry.hide()
	dialog_open = false
	print("User details set: ", user)
	DataManager.set_user_data("user.name", user)
	DataManager.set_user_data("user.password", password)

func on_cb_lock_toggled(on: bool) -> void:
	locked = on

func on_cb_all_toggled(on: bool) -> void:
	all_lock = on

func pre_cache_current_field():
	# Pre-cache the current field's data
	var current_field = DataManager.get_current_field()
	%CacheProgress.show()
	if current_field:
		print("Pre-caching field: ", current_field)
		DataManager.pre_cache_field(current_field, %CacheProgress)
	else:
		print("No field selected for pre-caching")
