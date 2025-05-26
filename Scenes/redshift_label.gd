extends Label

func _ready() -> void:
	print("LABEL IN")
	
func _exit_tree() -> void:
	print("-------------------------- LABEL OUT")
