extends SceneTree

## Test script to debug bundle loading issues

# Import required classes
const ObjectBundle = preload("res://Server/object_bundle.gd")
const ObjectManifest = preload("res://Server/object_manifest.gd")

func _init():
	print("=== Bundle Loading Debug Test ===")
	
	# Test with a specific bundle file
	var test_file = "processed/uma-03_05858_bundle.tres"
	print("Testing bundle file: " + test_file)
	
	if not FileAccess.file_exists(test_file):
		print("ERROR: Test file does not exist: " + test_file)
		return
	
	# Try different loading approaches
	test_loading_approaches(test_file)
	
	# Also test creating a new bundle
	test_simple_bundle_creation()

func test_loading_approaches(file_path: String):
	print("\n--- Approach 1: Direct ResourceLoader.load() ---")
	var resource1 = ResourceLoader.load(file_path)
	analyze_resource("Direct load", resource1)
	
	print("\n--- Approach 2: Load with ObjectBundle type hint ---")
	var resource2 = ResourceLoader.load(file_path, "ObjectBundle")
	analyze_resource("Type hint load", resource2)
	
	print("\n--- Approach 3: Load with cache mode ignore ---")
	var resource3 = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	analyze_resource("Cache ignore load", resource3)
	
	print("\n--- File Analysis ---")
	analyze_file_contents(file_path)

func analyze_resource(approach_name: String, resource: Resource):
	print(approach_name + " result:")
	if not resource:
		print("  Resource is null")
		return
	
	print("  Resource type: " + resource.get_class())
	print("  Resource script: " + str(resource.get_script()))
	
	# Check if it's an ObjectBundle
	var bundle = resource as ObjectBundle
	if bundle:
		print("  ✓ Successfully cast to ObjectBundle")
		print("  Manifest: " + str(bundle.manifest != null))
		print("  Resources count: " + str(bundle.resources.size() if bundle.resources else "null"))
		if bundle.manifest:
			print("  Object ID: " + str(bundle.manifest.object_id))
	else:
		print("  ✗ Failed to cast to ObjectBundle")
	
	# Check properties directly
	print("  Has 'manifest' property: " + str("manifest" in resource))
	print("  Has 'resources' property: " + str("resources" in resource))
	
	if resource.has_method("get"):
		var manifest_via_get = resource.get("manifest")
		var resources_via_get = resource.get("resources")
		print("  get('manifest'): " + str(manifest_via_get != null))
		print("  get('resources'): " + str(resources_via_get != null))
		
		if resources_via_get:
			print("  Resources via get() count: " + str(resources_via_get.size()))
	
	# Try to access properties directly
	if resource.has_method("get_property_list"):
		var props = resource.get_property_list()
		print("  Property list count: " + str(props.size()))
		for prop in props:
			if prop.name in ["manifest", "resources"]:
				print("    Found property: " + prop.name + " (type: " + str(prop.type) + ")")

func analyze_file_contents(file_path: String):
	print("File size: " + str(FileAccess.get_file_as_bytes(file_path).size()) + " bytes")
	
	# Read first few lines to see the file structure
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		print("First 10 lines of file:")
		for i in range(10):
			var line = file.get_line()
			if file.eof_reached():
				break
			print("  " + str(i + 1) + ": " + line)
		file.close()
	else:
		print("Could not open file for reading")

# Alternative test function to create a simple bundle and test it
func test_simple_bundle_creation():
	print("\n=== Testing Simple Bundle Creation ===")
	
	# Create a simple ObjectBundle
	var bundle = ObjectBundle.new()
	bundle.set_script(preload("res://Server/object_bundle.gd"))
	
	# Create a simple manifest
	var manifest = ObjectManifest.new()
	manifest.object_id = "test_object"
	manifest.object_name = "Test Object"
	
	bundle.manifest = manifest
	bundle.resources = {"test": "test_value"}
	
	# Save it
	var test_path = "user://test_bundle.tres"
	var save_result = ResourceSaver.save(bundle, test_path)
	print("Save result: " + str(save_result))
	
	if save_result == OK:
		print("Successfully saved test bundle")
		
		# Try to load it back
		var loaded = ResourceLoader.load(test_path)
		analyze_resource("Test bundle load", loaded)
	else:
		print("Failed to save test bundle")