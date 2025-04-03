extends Control

signal tab_added(tab_index)
signal tab_closed(tab_index)
signal tab_selected(tab_index)

# References to child nodes
var tab_bar: Control
var content_container: Control

# Tab scene to instantiate for new tabs
var tab_scene = null

# Tab data
var tabs = []

func _ready():
	# Get references to child nodes
	tab_bar = $TabBar
	content_container = $ContentContainer
	
	# Connect signals from tab bar
	tab_bar.tab_added.connect(_on_tab_bar_tab_added)
	tab_bar.tab_closed.connect(_on_tab_bar_tab_closed)
	tab_bar.tab_selected.connect(_on_tab_bar_tab_selected)

# Set the scene to use for new tabs
func set_tab_scene(scene_path: String):
	tab_scene = load(scene_path)

# Create a new tab with the given title
func create_tab(title: String) -> int:
	if not tab_scene:
		push_error("Tab scene not set. Call set_tab_scene() first.")
		return -1
	
	# Create a new tab in the tab bar
	var tab_index = tab_bar.add_tab(title)
	
	# Create a new instance of the tab scene
	var tab_instance = tab_scene.instantiate()
	tab_instance.name = "Tab" + str(tab_index)
	content_container.add_child(tab_instance)
	
	# Store tab data
	tabs.append({
		"title": title,
		"content": tab_instance
	})
	
	# Hide all tabs except the active one
	_update_tab_visibility()
	
	emit_signal("tab_added", tab_index)
	return tab_index

# Close a tab at the given index
func close_tab(tab_index: int):
	if tab_index < 0 or tab_index >= tabs.size():
		return
	
	# Remove the tab from the tab bar
	tab_bar.close_tab(tab_index)
	
	# Remove the tab content
	var tab_content = tabs[tab_index].content
	content_container.remove_child(tab_content)
	tab_content.queue_free()
	
	# Remove the tab data
	tabs.remove_at(tab_index)
	
	# Update tab visibility
	_update_tab_visibility()
	
	emit_signal("tab_closed", tab_index)

# Set the active tab
func set_active_tab(tab_index: int):
	if tab_index < 0 or tab_index >= tabs.size():
		return
	
	tab_bar.set_active_tab(tab_index)
	_update_tab_visibility()
	
	emit_signal("tab_selected", tab_index)

# Get the active tab index
func get_active_tab_index() -> int:
	return tab_bar.get_active_tab_index()

# Get the number of tabs
func get_tab_count() -> int:
	return tabs.size()

# Get the tab content at the given index
func get_tab_content(tab_index: int) -> Control:
	if tab_index < 0 or tab_index >= tabs.size():
		return null
	
	return tabs[tab_index].content

# Update the visibility of tab content based on the active tab
func _update_tab_visibility():
	var active_index = tab_bar.get_active_tab_index()
	
	for i in range(tabs.size()):
		var tab_content = tabs[i].content
		tab_content.visible = (i == active_index)

# Signal handlers
func _on_tab_bar_tab_added():
	# This is handled by create_tab()
	pass

func _on_tab_bar_tab_closed(tab_index: int):
	close_tab(tab_index)

func _on_tab_bar_tab_selected(tab_index: int):
	_update_tab_visibility()
	emit_signal("tab_selected", tab_index)