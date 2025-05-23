extends Node
var database: SQLite
signal updated_data(success: bool)

var current_field: String = "uma-03"


func _ready() -> void:
	database = SQLite.new()
	database.path = "./data/data.sqlite"
	database.open_db()

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
	return field_list

func set_current_field(field: String) -> void:
	current_field = field

func get_current_field() -> String:
	return current_field

func update_gal(id: String, status: int, comment: String) -> void:
	database.update_rows("galaxy", "id = '" + id + "'", {"status": status, "comments": comment})
	updated_data.emit(true)
