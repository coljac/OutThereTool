extends Node

var loader: CachedResourceLoader

func _ready():
	loader = CachedResourceLoader.new()
	add_child(loader)
	print("Global resource cache initialized")

func get_loader() -> CachedResourceLoader:
	return loader