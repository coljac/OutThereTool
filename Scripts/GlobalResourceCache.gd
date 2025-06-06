extends Node

var loader: ThreadedCachedResourceLoader

func _ready():
	loader = ThreadedCachedResourceLoader.new()
	add_child(loader)
	print("Global threaded resource cache initialized")
	NetworkConfig.print_config()

func get_loader() -> ThreadedCachedResourceLoader:
	return loader