extends Control

#@onready var fits = $FitsImage
#@onready var plot = $PlotDisplay
@onready var oned = $OneD
@onready var gal_display = preload("res://Scenes/galaxy_display.tscn")

var objects = [
	["./data/Good_example/", "uma-03_02122"],
	["./data/Good_example/", "uma-03_02379"],
	["./data/Good_example/", "uma-03_02624"],
	["./data/Good_example/", "uma-03_03269"],
	["./data/Needrefit_example/", "uma-03_02484"],
	["./data/Needrefit_example/", "uma-03_03763"],
	["./data/Needrefit_example/", "uma-03_03917"],
	["./data/Needrefit_example/", "uma-03_04365"]
]
var obj_index = 0

var object_id: String = "./data/Good_example/uma-03_02122"
var object_id2: String = "./data/Good_example/uma-03_02122"
#var object_id2: String = "./data/outthere-hudfn_04375"

func _ready() -> void:
	print("I LIVEEEEEEEEEEEEE")
	set_process_input(true)

func pofz_pressed(pos):
	print(pos)
	
# func _unhandled_input(event: InputEvent) -> void:
# 	if event.is_action_pressed("next"):
# 		print("NEXT")
# 		next_object()
# 		get_viewport().set_input_as_handled()


# func next_object() -> void:
# 	for ch in $VBoxContainer/MarginContainer.get_children():
# 		ch.queue_free()
# 	#if $VBoxContainer/MarginContainer/GalaxyDisplay:
# 		#$VBoxContainer/MarginContainer/GalaxyDisplay.queue_free()
# 	var newbox = gal_display.instantiate()
# 	obj_index += 1
# 	if obj_index >= objects.size():
# 		obj_index = 0
# 	newbox.path = objects[obj_index][0]
# 	newbox.object_id = objects[obj_index][1]
# 	#newbox.object_id = "uma-03_02122"
# 	newbox.name = "GalaxyDisplay"
# 	$VBoxContainer/MarginContainer.add_child(newbox)
# 	newbox.load_object()
