extends Control

# Preload icons
const plus_icon = preload("res://theme/assets/icons/Plus.svg")
const close_icon = preload("res://theme/assets/icons/Close.svg")
const scroll_forwards_icon = preload("res://theme/assets/icons/ScrollForwards.svg")
const scroll_backwards_icon = preload("res://theme/assets/icons/ScrollBackwards.svg")

# Tab dimensions
const DEFAULT_TAB_WIDTH = 140.0
const MIN_TAB_WIDTH = 70.0
const CLOSE_BUTTON_MARGIN = 2

# Canvas item for drawing
var ci := get_canvas_item()

# Scrolling variables
var current_scroll := 0.0
var scrolling_backwards := false
var scrolling_forwards := false
var active_controls: Array[Control] = []

# Tab dragging
var proposed_drop_idx := -1:
	set(new_value):
		if proposed_drop_idx != new_value:
			proposed_drop_idx = new_value
			queue_redraw()

# Signals
signal tab_added
signal tab_closed(tab_index)
signal tab_selected(tab_index)

# Tab data
var tabs = []
var active_tab_index = 0

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(queue_redraw)
	set_process(false)

func _draw() -> void:
	# Draw background
	var background_stylebox: StyleBoxFlat = get_theme_stylebox("tab_unselected", "TabContainer").duplicate()
	background_stylebox.corner_radius_top_left += 1
	background_stylebox.corner_radius_top_right += 1
	background_stylebox.bg_color = Color(ThemeUtils.common_panel_inner_color, 0.4)
	draw_style_box(background_stylebox, get_rect())
	
	var mouse_pos := get_local_mouse_position()
	
	# Draw tabs
	for tab_index in range(tabs.size()):
		var rect := get_tab_rect(tab_index)
		if not rect.has_area():
			continue
		
		var current_tab_name = tabs[tab_index].title
		
		if tab_index == active_tab_index:
			# Draw active tab
			draw_style_box(get_theme_stylebox("tab_selected", "TabContainer"), rect)
			var text_line_width := rect.size.x - size.y
			if text_line_width > 0:
				var text_line := TextLine.new()
				text_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				text_line.add_string(current_tab_name, ThemeUtils.regular_font, 13)
				text_line.width = text_line_width
				text_line.draw(ci, rect.position + Vector2(4, 3),
						get_theme_color("font_selected_color", "TabContainer"))
			
			# Draw close button for active tab
			var close_rect := get_close_button_rect()
			if close_rect.has_area():
				var close_icon_size := close_icon.get_size()
				draw_texture_rect(close_icon, Rect2(close_rect.position +
						(close_rect.size - close_icon_size) / 2.0, close_icon_size), false)
		else:
			# Draw inactive tab
			var is_hovered := rect.has_point(mouse_pos)
			var tab_style := "tab_hovered" if is_hovered else "tab_unselected"
			draw_style_box(get_theme_stylebox(tab_style, "TabContainer"), rect)
			
			var text_line_width := rect.size.x - 8
			if text_line_width > 0:
				var text_color := get_theme_color("font_hovered_color" if is_hovered else
						"font_unselected_color", "TabContainer")
				
				var text_line := TextLine.new()
				text_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				text_line.add_string(current_tab_name, ThemeUtils.regular_font, 13)
				text_line.width = text_line_width
				text_line.draw(ci, rect.position + Vector2(4, 3), text_color)
	
	# Draw add button
	var add_button_rect := get_add_button_rect()
	if add_button_rect.has_area():
		var plus_icon_size := plus_icon.get_size()
		draw_texture_rect(plus_icon, Rect2(add_button_rect.position +
				(add_button_rect.size - plus_icon_size) / 2.0, plus_icon_size), false)
	
	# Draw scroll backwards button
	var scroll_backwards_rect := get_scroll_backwards_area_rect()
	if scroll_backwards_rect.has_area():
		var scroll_backwards_icon_size := scroll_backwards_icon.get_size()
		var icon_modulate := Color.WHITE
		if is_scroll_backwards_disabled():
			icon_modulate = get_theme_color("icon_disabled_color", "Button")
		else:
			var line_x := scroll_backwards_rect.end.x + 1
			draw_line(Vector2(line_x, 0), Vector2(line_x, size.y),
					ThemeUtils.common_panel_border_color)
			if scroll_backwards_rect.has_point(mouse_pos):
				var stylebox_theme := "pressed" if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else "hover"
				get_theme_stylebox(stylebox_theme, "FlatButton").draw(ci, scroll_backwards_rect)
		draw_texture_rect(scroll_backwards_icon, Rect2(scroll_backwards_rect.position +
				(scroll_backwards_rect.size - scroll_backwards_icon_size) / 2.0,
				scroll_backwards_icon_size), false, icon_modulate)
	
	# Draw scroll forwards button
	var scroll_forwards_rect := get_scroll_forwards_area_rect()
	if scroll_forwards_rect.has_area():
		var scroll_forwards_icon_size := scroll_forwards_icon.get_size()
		var icon_modulate := Color.WHITE
		if is_scroll_forwards_disabled():
			icon_modulate = get_theme_color("icon_disabled_color", "Button")
		else:
			var line_x := scroll_forwards_rect.position.x
			draw_line(Vector2(line_x, 0), Vector2(line_x, size.y),
					ThemeUtils.common_panel_border_color)
			if scroll_forwards_rect.has_point(mouse_pos):
				var stylebox_theme := "pressed" if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else "hover"
				get_theme_stylebox(stylebox_theme, "FlatButton").draw(ci, scroll_forwards_rect)
		draw_texture_rect(scroll_forwards_icon, Rect2(scroll_forwards_rect.position +
				(scroll_forwards_rect.size - scroll_forwards_icon_size) / 2.0,
				scroll_forwards_icon_size), false, icon_modulate)
	
	# Draw drop indicator for tab dragging
	if proposed_drop_idx != -1:
		var prev_tab_rect := get_tab_rect(proposed_drop_idx - 1)
		var x_pos: float
		if prev_tab_rect.has_area():
			x_pos = prev_tab_rect.end.x
		else:
			x_pos = get_tab_rect(proposed_drop_idx).position.x
		draw_line(Vector2(x_pos, 0), Vector2(x_pos, size.y), Color(0, 0.5, 1), 4)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	
	queue_redraw()
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
				scroll_backwards()
			if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
				scroll_forwards()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var hovered_idx := get_hovered_index()
				if hovered_idx != -1:
					if hovered_idx != active_tab_index:
						set_active_tab(hovered_idx)
				
				# Check for scroll buttons
				var scroll_backwards_area_rect := get_scroll_backwards_area_rect()
				if scroll_backwards_area_rect.has_area() and scroll_backwards_area_rect.has_point(event.position) and not is_scroll_backwards_disabled():
					scrolling_backwards = true
					set_process(true)
					return
				
				var scroll_forwards_area_rect := get_scroll_forwards_area_rect()
				if scroll_forwards_area_rect.has_area() and scroll_forwards_area_rect.has_point(event.position) and not is_scroll_forwards_disabled():
					scrolling_forwards = true
					set_process(true)
					return
				
				# Check for add button
				var add_button_rect := get_add_button_rect()
				if add_button_rect.has_area() and add_button_rect.has_point(event.position):
					add_tab("New Tab")
					return
			
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				var hovered_idx := get_hovered_index()
				if hovered_idx != -1:
					close_tab(hovered_idx)
		
		elif event.button_index == MOUSE_BUTTON_LEFT and event.is_released():
			scrolling_backwards = false
			scrolling_forwards = false
			set_process(false)

# Autoscroll when the dragged tab is hovered beyond the tabs area
func _process(_delta: float) -> void:
	var mouse_pos := get_local_mouse_position()
	var scroll_forwards_area_rect := get_scroll_forwards_area_rect()
	if ((scrolling_forwards and scroll_forwards_area_rect.has_point(mouse_pos)) or (mouse_pos.x > size.x - get_add_button_rect().size.x - scroll_forwards_area_rect.size.x)) and scroll_forwards_area_rect.has_area():
		scroll_forwards()
		return
	
	var scroll_backwards_area_rect := get_scroll_backwards_area_rect()
	if ((scrolling_backwards and scroll_backwards_area_rect.has_point(mouse_pos)) or (mouse_pos.x < scroll_backwards_area_rect.size.x)) and scroll_backwards_area_rect.has_area():
		scroll_backwards()
		return

func _on_mouse_entered() -> void:
	activate()

func _on_mouse_exited() -> void:
	cleanup()

func cleanup() -> void:
	for control in active_controls:
		control.queue_free()
	active_controls = []
	queue_redraw()

func scroll_backwards() -> void:
	set_scroll(current_scroll - 5.0)

func scroll_forwards() -> void:
	set_scroll(current_scroll + 5.0)

func scroll_to_active() -> void:
	var idx: int = active_tab_index
	set_scroll(clampf(current_scroll, MIN_TAB_WIDTH * (idx + 1) - size.x + get_add_button_rect().size.x + get_scroll_forwards_area_rect().size.x + get_scroll_backwards_area_rect().size.x, MIN_TAB_WIDTH * idx))

func set_scroll(new_value: float) -> void:
	if get_scroll_limit() < 0:
		new_value = 0.0
	else:
		new_value = clampf(new_value, 0, get_scroll_limit())
	if current_scroll != new_value:
		current_scroll = new_value
		queue_redraw()
		activate()

func get_tab_rect(idx: int) -> Rect2:
	# Things that can take space
	var add_button_width := get_add_button_rect().size.x
	var scroll_backwards_button_width := get_scroll_backwards_area_rect().size.x
	var scroll_forwards_button_width := get_scroll_forwards_area_rect().size.x
	
	var left_limit := scroll_backwards_button_width
	var right_limit := size.x - add_button_width - scroll_forwards_button_width
	
	var tab_width := clampf((size.x - add_button_width - scroll_backwards_button_width - scroll_forwards_button_width) / max(1, tabs.size()), MIN_TAB_WIDTH, DEFAULT_TAB_WIDTH)
	var unclamped_tab_start := tab_width * idx - current_scroll + left_limit
	var tab_start := clampf(unclamped_tab_start, left_limit, right_limit)
	var tab_end := clampf(unclamped_tab_start + tab_width, left_limit, right_limit)
	
	if tab_end <= tab_start:
		return Rect2()
	return Rect2(tab_start, 0, tab_end - tab_start, size.y)

func get_close_button_rect() -> Rect2:
	var tab_rect := get_tab_rect(active_tab_index)
	var side := size.y - CLOSE_BUTTON_MARGIN * 2
	var left_coords := tab_rect.position.x + tab_rect.size.x - CLOSE_BUTTON_MARGIN - side
	if left_coords < get_scroll_backwards_area_rect().size.x or tab_rect.size.x < size.y - CLOSE_BUTTON_MARGIN:
		return Rect2()
	return Rect2(left_coords, CLOSE_BUTTON_MARGIN, side, side)

func get_add_button_rect() -> Rect2:
	var tab_count := tabs.size()
	var max_tabs = 20  # Set a reasonable maximum number of tabs
	if tab_count >= max_tabs:
		return Rect2()
	return Rect2(minf(DEFAULT_TAB_WIDTH * tab_count, size.x - size.y), 0, size.y, size.y)

func get_scroll_forwards_area_rect() -> Rect2:
	var add_button_width := get_add_button_rect().size.x
	if size.x - add_button_width > tabs.size() * MIN_TAB_WIDTH:
		return Rect2()
	var width := size.y / 1.5
	return Rect2(size.x - add_button_width - width, 0, width, size.y)

func is_scroll_forwards_disabled() -> bool:
	return current_scroll >= get_scroll_limit()

func get_scroll_backwards_area_rect() -> Rect2:
	if size.x - get_add_button_rect().size.x > tabs.size() * MIN_TAB_WIDTH:
		return Rect2()
	return Rect2(0, 0, size.y / 1.5, size.y)

func is_scroll_backwards_disabled() -> bool:
	return current_scroll <= 0.0

func get_scroll_limit() -> float:
	var add_button_width := get_add_button_rect().size.x
	var scroll_backwards_button_width := get_scroll_backwards_area_rect().size.x
	var scroll_forwards_button_width := get_scroll_forwards_area_rect().size.x
	
	var available_area := size.x - add_button_width - scroll_backwards_button_width - scroll_forwards_button_width
	return clampf(available_area / max(1, tabs.size()), MIN_TAB_WIDTH, DEFAULT_TAB_WIDTH) * tabs.size() - available_area

func get_hovered_index() -> int:
	return get_tab_index_at(get_local_mouse_position())

func activate() -> void:
	cleanup()
	
	var close_rect := get_close_button_rect()
	if close_rect.has_area():
		var close_button := Button.new()
		close_button.theme_type_variation = "FlatButton"
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.position = close_rect.position
		close_button.size = close_rect.size
		close_button.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(close_button)
		active_controls.append(close_button)
		close_button.pressed.connect(func() -> void:
			close_tab(active_tab_index)
		)
	
	var add_rect := get_add_button_rect()
	if add_rect.has_area():
		var add_button := Button.new()
		add_button.theme_type_variation = "FlatButton"
		add_button.focus_mode = Control.FOCUS_NONE
		add_button.position = add_rect.position
		add_button.size = add_rect.size
		add_button.mouse_filter = Control.MOUSE_FILTER_PASS
		add_button.tooltip_text = "Create a new tab"
		add_child(add_button)
		active_controls.append(add_button)
		add_button.pressed.connect(func() -> void:
			add_tab("New Tab")
		)

func get_tab_index_at(pos: Vector2) -> int:
	if not get_close_button_rect().has_point(pos):
		for tab_index in range(tabs.size()):
			var tab_rect := get_tab_rect(tab_index)
			if tab_rect.has_area() and tab_rect.has_point(pos):
				return tab_index
	return -1

# Tab management functions
func add_tab(title: String) -> int:
	var tab_data = {
		"title": title,
		"id": tabs.size()
	}
	tabs.append(tab_data)
	
	# Set as active tab
	set_active_tab(tabs.size() - 1)
	
	queue_redraw()
	emit_signal("tab_added")
	return tabs.size() - 1

func close_tab(tab_index: int) -> void:
	if tab_index < 0 or tab_index >= tabs.size():
		return
	
	tabs.remove_at(tab_index)
	
	# Update active tab if needed
	if active_tab_index >= tabs.size():
		active_tab_index = max(0, tabs.size() - 1)
	
	queue_redraw()
	emit_signal("tab_closed", tab_index)

func set_active_tab(tab_index: int) -> void:
	if tab_index < 0 or tab_index >= tabs.size():
		return
	
	active_tab_index = tab_index
	scroll_to_active()
	queue_redraw()
	emit_signal("tab_selected", tab_index)

func get_tab_count() -> int:
	return tabs.size()

func get_active_tab_index() -> int:
	return active_tab_index

# Tab dragging support
class TabDropData extends RefCounted:
	var index := -1
	func _init(new_index: int) -> void:
		index = new_index

func get_drop_index_at(pos: Vector2) -> int:
	var add_button_width := get_add_button_rect().size.x
	var scroll_backwards_button_width := get_scroll_backwards_area_rect().size.x
	var scroll_forwards_button_width := get_scroll_forwards_area_rect().size.x
	
	if pos.x < scroll_backwards_button_width or pos.x > size.x - scroll_forwards_button_width - add_button_width:
		return -1
	
	var first_tab_with_area := 0
	for idx in range(tabs.size()):
		if get_tab_rect(idx).has_area():
			first_tab_with_area = idx
			break
	
	var tab_width := clampf((size.x - add_button_width - scroll_backwards_button_width - scroll_forwards_button_width) / max(1, tabs.size()), MIN_TAB_WIDTH, DEFAULT_TAB_WIDTH)
	
	for idx in range(first_tab_with_area, tabs.size()):
		var tab_rect := get_tab_rect(idx)
		if not tab_rect.has_area() or tab_width * (idx + 0.5) - current_scroll + scroll_backwards_button_width > pos.x:
			return idx
	return tabs.size()

func _get_drag_data(at_position: Vector2) -> Variant:
	var tab_index_at_position := get_tab_index_at(at_position)
	if tab_index_at_position == -1:
		return
	
	var tab_width := get_tab_rect(tab_index_at_position).size.x
	# Roughly mimics the tab drawing
	var preview := Panel.new()
	preview.modulate = Color(1, 1, 1, 0.85)
	preview.custom_minimum_size = Vector2(tab_width, size.y)
	preview.add_theme_stylebox_override("panel", get_theme_stylebox("tab_selected", "TabContainer"))
	var label := Label.new()
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.text = tabs[tab_index_at_position].title
	preview.add_child(label)
	label.position = Vector2(4, 3)
	label.size.x = tab_width - 8
	
	set_drag_preview(preview)
	set_process(true)
	return TabDropData.new(tab_index_at_position)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is TabDropData:
		proposed_drop_idx = -1
		return false
	var current_drop_idx := get_drop_index_at(at_position)
	if current_drop_idx in [data.index, data.index + 1]:
		proposed_drop_idx = -1
		return false
	else:
		proposed_drop_idx = current_drop_idx
		return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is TabDropData:
		return
	set_process(false)
	move_tab(data.index, get_drop_index_at(at_position))

func move_tab(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= tabs.size() or to_index < 0 or to_index > tabs.size():
		return
	
	var tab_data = tabs[from_index]
	tabs.remove_at(from_index)
	
	if to_index > from_index:
		to_index -= 1
	
	tabs.insert(to_index, tab_data)
	
	# Update active tab index if needed
	if active_tab_index == from_index:
		active_tab_index = to_index
	elif active_tab_index > from_index and active_tab_index <= to_index:
		active_tab_index -= 1
	elif active_tab_index < from_index and active_tab_index >= to_index:
		active_tab_index += 1
	
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		set_process(false)
		proposed_drop_idx = -1