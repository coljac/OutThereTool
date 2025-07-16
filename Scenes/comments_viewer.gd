extends Control

@onready var comments_list: VBoxContainer = %CommentList
@onready var galaxy_label: Label = %GalaxyLabel
@onready var close_button: Button = %CloseButton
@onready var scroll_container: ScrollContainer = %ScrollContainer

var galaxy_id: String = ""
var comments_data: Array = []

signal closed

func _ready():
	if close_button and is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
	set_process_input(true)

func _input(event: InputEvent):
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("comments_view_toggle"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()

func show_comments(galaxy_id: String, comments: Array):
	"""Display comments for a specific galaxy"""
	print("DEBUG: comments_viewer.show_comments called for galaxy: ", galaxy_id, " with ", comments.size(), " comments")
	self.galaxy_id = galaxy_id
	self.comments_data = comments
	
	# Safely set galaxy label text if it exists
	if galaxy_label and is_instance_valid(galaxy_label):
		galaxy_label.text = "Comments for " + galaxy_id
	
	# Clear existing comments - use remove_child and queue_free to avoid issues
	if comments_list and is_instance_valid(comments_list):
		for child in comments_list.get_children():
			comments_list.remove_child(child)
			child.queue_free()
	
		if comments.size() == 0:
			var no_comments_label = Label.new()
			no_comments_label.text = "No comments from other users for this galaxy."
			no_comments_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			no_comments_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			comments_list.add_child(no_comments_label)
		else:
			# Sort comments by updated time (newest first)
			comments.sort_custom(func(a, b): return a.get("updated", "") > b.get("updated", ""))
			
			for comment in comments:
				_create_comment_item(comment)
	
	# Show the popup
	visible = true

func _create_comment_item(comment: Dictionary):
	"""Create a visual item for a single comment"""
	var comment_container = VBoxContainer.new()
	comment_container.add_theme_constant_override("separation", 8)
	
	# Create header with user and timestamp
	var header_container = HBoxContainer.new()
	
	var user_label = Label.new()
	user_label.text = comment.get("user_id", "Unknown User")
	user_label.add_theme_color_override("font_color", Color.CYAN)
	user_label.add_theme_font_size_override("font_size", 14)
	header_container.add_child(user_label)
	
	# Add spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(spacer)
	
	var timestamp_label = Label.new()
	var timestamp = comment.get("updated", "")
	if timestamp != "":
		# Format timestamp nicely
		timestamp_label.text = _format_timestamp(timestamp)
	else:
		timestamp_label.text = "Unknown time"
	timestamp_label.add_theme_color_override("font_color", Color.GRAY)
	timestamp_label.add_theme_font_size_override("font_size", 12)
	header_container.add_child(timestamp_label)
	
	comment_container.add_child(header_container)
	
	# Create content section
	var content_container = VBoxContainer.new()
	content_container.add_theme_constant_override("separation", 4)
	
	# Status and redshift info
	var info_container = HBoxContainer.new()
	
	var status_label = Label.new()
	var status = comment.get("status", -1)
	status_label.text = "Status: " + _format_status(status)
	info_container.add_child(status_label)
	
	if comment.has("redshift") and comment.redshift != null:
		var redshift_label = Label.new()
		redshift_label.text = "  |  Redshift: " + str(comment.redshift)
		info_container.add_child(redshift_label)
	
	content_container.add_child(info_container)
	
	# Comment text
	if comment.has("comment") and comment.comment != null and comment.comment != "":
		var comment_text = Label.new()
		comment_text.text = comment.comment
		comment_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		comment_text.add_theme_color_override("font_color", Color.WHITE)
		content_container.add_child(comment_text)
	
	comment_container.add_child(content_container)
	
	# Add separator
	var separator = HSeparator.new()
	separator.add_theme_color_override("color", Color.GRAY)
	comment_container.add_child(separator)
	
	# Add some padding
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 16)
	margin_container.add_theme_constant_override("margin_right", 16)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	margin_container.add_child(comment_container)
	
	# Safely add to comments list if it exists
	if comments_list and is_instance_valid(comments_list):
		comments_list.add_child(margin_container)

func _format_status(status: int) -> String:
	"""Convert status integer to readable string"""
	match status:
		-1:
			return "Unreviewed"
		0:
			return "Bad"
		1:
			return "Maybe"
		2:
			return "Good"
		3:
			return "Best"
		4:
			return "Definitely good"
		5:
			return "Perfect"
		_:
			return "Unknown (" + str(status) + ")"

func _format_timestamp(timestamp: String) -> String:
	"""Format timestamp string to be more readable"""
	# This is a simple formatting - could be enhanced with relative time
	if timestamp.length() > 19:
		return timestamp.substr(0, 19).replace("T", " ")
	return timestamp

func _on_close_pressed():
	"""Close the comments viewer"""
	visible = false
	closed.emit()
