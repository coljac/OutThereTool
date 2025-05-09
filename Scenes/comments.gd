extends TextEdit

func _unhandled_input(event):
	if not event is InputEventKey:
		return
	if has_focus():
		get_viewport().set_input_as_handled()

func _input(event):
	if has_focus():
		if event is InputEventKey:
			if event.pressed:
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
					release_focus()
					get_viewport().set_input_as_handled()
				elif event.keycode == KEY_ENTER and event.ctrl_pressed:
					release_focus()
					get_parent().owner.save()
					get_viewport().set_input_as_handled()
