extends Control
@onready var comments: TextEdit = $MarginContainer/VBoxContainer/Comments
@onready var status: OptionButton = $MarginContainer/VBoxContainer/GridContainer/Status
@onready var class_options: OptionButton = %ClassOptions
@onready var spurious_checkbox: CheckBox = $MarginContainer/VBoxContainer/GridContainer/Spurious
@onready var redshift_input: SpinBox = %RedshiftInput
@onready var reset_button: Button = %ResetButton

signal save_galaxy(vals: Dictionary)
signal redshift_changed(value: float)

var original_redshift = 0.0

func _ready():
	mouse_filter = MOUSE_FILTER_PASS
	
	# Setup class dropdown options
	class_options.clear()
	class_options.add_item("Junk", 0)
	class_options.add_item("QSO", 1)
	class_options.add_item("ELG", 2)
	
	# Setup redshift input
	redshift_input.min_value = 0.0
	redshift_input.max_value = 20.0
	redshift_input.step = 0.001
	redshift_input.value = 0.0
	
	# Connect redshift signals
	redshift_input.value_changed.connect(_on_redshift_changed)
	reset_button.pressed.connect(_on_reset_pressed)

func set_galaxy_details(details: Dictionary):
	comments.text = details['comments'] if details['comments'] else ""
	status.select(details['status'])
	
	# Set class dropdown (default to 0 if not present)
	var galaxy_class = details.get('galaxy_class', 0)
	class_options.select(galaxy_class)
	
	# Set spurious checkbox (extract from checkboxes bitmask)
	var checkboxes = details.get('checkboxes', 0)
	spurious_checkbox.button_pressed = (checkboxes & 1) != 0
	
	# Set redshift input
	var galaxy_redshift = details.get('redshift', 0.0)
	if galaxy_redshift != null:
		original_redshift = float(galaxy_redshift)
		redshift_input.set_value_no_signal(original_redshift)
	else:
		original_redshift = 0.0
		redshift_input.set_value_no_signal(0.0)
	
	%TickRect.text = ""

func set_status(new_status: int):
	status.select(new_status)
	save()

func tick(on: bool):
	%TickRect.text = "Saved."

func save():
	%Comments.release_focus()
	
	# Build checkboxes bitmask (spurious is bit 0)
	var checkboxes = 0
	if spurious_checkbox.button_pressed:
		checkboxes |= 1
	
	var save_data = {
		"status": status.get_selected_id(),
		"comments": comments.text,
		"galaxy_class": class_options.get_selected_id(),
		"checkboxes": checkboxes,
		"redshift": redshift_input.value
	}
	
	save_galaxy.emit(save_data)

func _on_redshift_changed(value: float):
	redshift_changed.emit(value)
	save()

func _on_reset_pressed():
	redshift_input.value = original_redshift
	
func set_redshift(value: float):
	redshift_input.set_value_no_signal(value)
