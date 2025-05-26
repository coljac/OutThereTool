extends HBoxContainer

signal more_options_pressed
signal settings_pressed

@onready var more_options_button = $LeftSide/MoreOptions
@onready var settings_button = $LeftSide/SettingsButton

func _ready():
	more_options_button.pressed.connect(_on_more_options_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

func _on_more_options_pressed():
	emit_signal("more_options_pressed")
	
	# Create a popup menu with placeholder items
	var popup = PopupMenu.new()
	popup.add_item("Open", 0)
	popup.add_item("Save", 1)
	popup.add_item("Export", 2)
	popup.add_separator()
	popup.add_item("About", 3)
	
	# Connect the popup's id_pressed signal
	popup.id_pressed.connect(_on_popup_id_pressed)
	
	# Show the popup below the more options button
	var global_pos = more_options_button.global_position
	var size = more_options_button.size
	popup.position = global_pos + Vector2(0, size.y)
	
	# Add the popup to the scene tree and show it
	add_child(popup)
	popup.popup()

func _on_settings_pressed():
	emit_signal("settings_pressed")
	
	# Create a popup menu with placeholder items
	var popup = PopupMenu.new()
	# popup.add_item("Display Settings", 0)
	# popup.add_item("Theme Settings", 1)
	# popup.add_separator()
	popup.add_item("Preferences", 2)
	
	# Connect the popup's id_pressed signal
	popup.id_pressed.connect(_on_settings_popup_id_pressed)
	
	# Show the popup below the settings button
	var global_pos = settings_button.global_position
	var size = settings_button.size
	popup.position = global_pos + Vector2(0, size.y)
	
	# Add the popup to the scene tree and show it
	add_child(popup)
	popup.popup()

func _on_popup_id_pressed(id):
	match id:
		0: # Open
			print("Open selected")
		1: # Save
			print("Save selected")
		2: # Export
			print("Export selected")
		3: # About
			print("About selected")

func _on_settings_popup_id_pressed(id):
	match id:
		0: # Display Settings
			print("Display Settings selected")
		1: # Theme Settings
			print("Theme Settings selected")
		2: # Preferences
			print("Preferences selected")