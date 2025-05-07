extends Node
var database: SQLite
signal updated_data(success: bool)


func _ready() -> void:
    database = SQLite.new()
    database.path = "res://data/data.sqlite"
    database.open_db()

func get_gals():
    var gals = database.select_rows("galaxy", "status > -1", ["*"])
    return gals

func update_gal(id: String, status: int, comment: String) -> void:
    database.update_rows("galaxy", "id = '" + id + "'", {"status": status, "comments": comment})
    updated_data.emit(true)