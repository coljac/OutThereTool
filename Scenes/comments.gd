extends TextEdit

func _ready():
    # Connect to text_changed signal
    # text_changed.connect(_on_text_changed)
    # For the button
    # $YourButton.pressed.connect(_on_button_pressed)
    pass

func _input(event):
    if has_focus():
        if event is InputEventKey and event.pressed:
            if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
                release_focus()
                get_viewport().set_input_as_handled()

# func _on_button_pressed():
    # release_focus()