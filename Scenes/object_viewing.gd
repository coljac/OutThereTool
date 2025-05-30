extends Control
@onready var comments: TextEdit = $MarginContainer/VBoxContainer/Comments
@onready var status: OptionButton = $MarginContainer/VBoxContainer/GridContainer/Status
@onready var check_box: CheckBox = $MarginContainer/VBoxContainer/GridContainer/CheckBox

signal save_galaxy(vals: Dictionary)

func _ready():
	mouse_filter = MOUSE_FILTER_PASS

func set_galaxy_details(details: Dictionary):
	comments.text = details['comments'] if details['comments'] else ""
	status.select(details['status'])
	%TickRect.text = ""

func set_status(new_status: int):
	status.select(new_status)
	save()

func tick(on: bool):
	%TickRect.text = "Saved."


func save():
	%Comments.release_focus()
	save_galaxy.emit({"status": status.get_selected_id(), "comments": comments.text})
