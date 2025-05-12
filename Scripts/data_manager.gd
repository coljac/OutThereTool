extends Node
var database: SQLite
signal updated_data(success: bool)


func _ready() -> void:
    database = SQLite.new()
    database.path = "./data/data.sqlite"
    database.open_db()

func get_gals(redshift_min: float = 0.0, redshift_max: float = 10.0, bands: int = 0) -> Array:
    print(
    "status > -1 and redshift >= %.2f and redshift <= %.2f and filters >= %d" % [redshift_min, redshift_max, bands]

    )
    var gals = database.select_rows("galaxy", "status > -1 and redshift >= %.2f and redshift <= %.2f and filters >= %d" % [redshift_min, redshift_max, bands], ["*"])
    return gals

func update_gal(id: String, status: int, comment: String) -> void:
    database.update_rows("galaxy", "id = '" + id + "'", {"status": status, "comments": comment})
    updated_data.emit(true)