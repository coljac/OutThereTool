extends Node
var database: SQLite
signal updated_data(success: bool)

var current_field: String = "uma-03"


func _ready() -> void:
	database = SQLite.new()
	database.path = OS.get_environment("OUTTHERE_DB")
	if database.path == "":
		database.path = "user://data.sqlite"
		if not FileAccess.file_exists(database.path):
			print("Copy initial database to user directory: ")
			# Copy from res://data.sqlite if it exists to user://data.sqlite
			if FileAccess.file_exists("res://data.sqlite"):
				copy_file_from_res_to_user("data.sqlite")
		else:
			print("Using default database path: ", database.path)
	database.open_db()

func copy_file_from_res_to_user(file_path: String) -> bool:
	var source_file = FileAccess.open("res://" + file_path, FileAccess.READ)
	if source_file == null:
		return false
	
	var content = source_file.get_buffer(source_file.get_length())
	source_file.close()
	
	var dir = DirAccess.open("user://")
	if dir == null:
		return false
	
	# Create directories if needed
	var directory_path = file_path.get_base_dir()
	if directory_path != "":
		dir.make_dir_recursive(directory_path)
	
	var dest_file = FileAccess.open("user://" + file_path, FileAccess.WRITE)
	if dest_file == null:
		return false
	
	dest_file.store_buffer(content)
	dest_file.close()
	
	return true

func get_gals(redshift_min: float = 0.0, redshift_max: float = 10.0, bands: int = 0, field: String = "") -> Array:
	var field_condition = ""
	if field != "" and field != "No fields":
		field_condition = " and field = '%s'" % field
	
	var condition = "status > -1 and redshift >= %.2f and redshift <= %.2f and filters >= %d%s" % [redshift_min, redshift_max, bands, field_condition]
	print(condition)
	
	var gals = database.select_rows("galaxy", condition, ["*"])
	return gals

func get_unique_fields() -> Array:
	var fields = database.select_rows("galaxy", "field IS NOT NULL", ["DISTINCT field"])
	var field_list = []
	for field_row in fields:
		field_list.append(field_row["FIELD"])
	field_list.sort()
	return field_list

func set_current_field(field: String) -> void:
	current_field = field

func get_current_field() -> String:
	return current_field

func get_gals_by_ids(object_ids: Array) -> Array:
	if object_ids.size() == 0:
		return []
	
	# Create condition for multiple IDs
	var id_conditions = []
	for id in object_ids:
		id_conditions.append("id = '" + str(id) + "'")
	var condition = "(" + " OR ".join(id_conditions) + ")"
	
	var gals = database.select_rows("galaxy", condition, ["*"])
	
	# Create a dictionary to preserve order of input IDs
	var id_to_gal = {}
	for gal in gals:
		id_to_gal[gal["id"]] = gal
	
	# Return objects in the same order as input IDs, skip missing ones
	var ordered_gals = []
	for id in object_ids:
		if id_to_gal.has(str(id)):
			ordered_gals.append(id_to_gal[str(id)])
	
	return ordered_gals

func update_gal(id: String, status: int, comment: String) -> void:
	database.update_rows("galaxy", "id = '" + id + "'", {"status": status, "comments": comment})
	updated_data.emit(true)

func set_user_data(item: String, value: String) -> void:
	var existing = database.select_rows("userdata", "item = '" + item + "'", ["*"])
	if existing.size() > 0:
		database.update_rows("userdata", "item = '" + item + "'", {"item_value": value})
	else:
		database.insert_row("userdata", {"item": item, "item_value": value})

func get_user_data(item: String) -> String:
	var result = database.select_rows("userdata", "item = '" + item + "'", ["item_value"])
	if result.size() > 0:
		return result[0]["item_value"]
	return ""

func get_user_credentials() -> Dictionary:
	var username = get_user_data("user.name")
	var password = get_user_data("user.password")
	return {"username": username, "password": password}
