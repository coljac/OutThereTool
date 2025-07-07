extends SceneTree

## Test script to verify bundle loading with the fixes

func _init():
	print("=== Testing Bundle Loading Fix ===")
	
	# Create and save a test bundle
	test_bundle_creation()
	
	# Wait a frame then test loading
	await process_frame
	test_bundle_loading()
	
	quit()

func test_bundle_creation():
	print("\n--- Creating Test Bundle ---")
	
	# Create bundle using class_name reference
	var bundle = ObjectBundle.new()
	
	# Create manifest using class_name reference
	var manifest = ObjectManifest.new()
	manifest.object_id = "test_object_001"
	manifest.object_name = "Test Object"
	manifest.band_count = 3
	manifest.redshift = 2.5
	manifest.spectrum_1d_paths = {"F115W": "test_object_001_1d_F115W.tres"}
	manifest.spectrum_2d_paths = {"F115W_PA180": "test_object_001_2d_PA180_F115W.tres"}
	manifest.direct_image_paths = {"F115W": "test_object_001_direct_F115W.tres"}
	manifest.redshift_path = "test_object_001_redshift.tres"
	
	# Create a simple test resource to bundle
	var test_resource = Spectrum1DResource.new()
	test_resource.object_id = "test_object_001"
	test_resource.filter_name = "F115W"
	test_resource.wavelengths = PackedFloat32Array([1.0, 1.1, 1.2])
	test_resource.fluxes = PackedFloat32Array([0.5, 0.6, 0.7])
	test_resource.errors = PackedFloat32Array([0.05, 0.06, 0.07])
	
	# Add to bundle
	bundle.manifest = manifest
	bundle.resources = {
		"1d_F115W": test_resource
	}
	
	# Save the bundle
	var test_path = "user://test_bundle_fix.res"
	var save_result = ResourceSaver.save(bundle, test_path)
	print("Save result: " + str(save_result))
	
	if save_result == OK:
		print("Bundle saved successfully to: " + test_path)
		
		# Also save a copy to the processed directory if it exists
		if DirAccess.dir_exists_absolute("processed"):
			var processed_path = "processed/test_object_001_bundle.res"
			ResourceSaver.save(bundle, processed_path)
			print("Also saved to: " + processed_path)
	else:
		print("Failed to save bundle!")

func test_bundle_loading():
	print("\n--- Testing Bundle Loading ---")
	
	var test_path = "user://test_bundle_fix.res"
	
	# Test 1: Direct load
	print("\nTest 1: Direct ResourceLoader.load()")
	var loaded1 = ResourceLoader.load(test_path)
	analyze_loaded_resource("Direct load", loaded1)
	
	# Test 2: Load with type hint
	print("\nTest 2: Load with ObjectBundle type hint")
	var loaded2 = ResourceLoader.load(test_path, "ObjectBundle")
	analyze_loaded_resource("Type hint load", loaded2)
	
	# Test 3: Try casting
	print("\nTest 3: Casting test")
	if loaded1:
		var bundle = loaded1 as ObjectBundle
		if bundle:
			print("✓ Successfully cast to ObjectBundle!")
			print("  Object ID: " + str(bundle.manifest.object_id if bundle.manifest else "no manifest"))
			print("  Resources count: " + str(bundle.resources.size()))
			
			# Try to access bundled resources
			if bundle.resources.has("1d_F115W"):
				var spec = bundle.resources["1d_F115W"]
				print("  Found 1D spectrum resource!")
				if spec is Spectrum1DResource:
					print("    ✓ Resource is correctly typed as Spectrum1DResource")
					print("    Filter: " + spec.filter_name)
					print("    Wavelengths: " + str(spec.wavelengths))
		else:
			print("✗ Failed to cast to ObjectBundle")

func analyze_loaded_resource(test_name: String, resource: Resource):
	print(test_name + " result:")
	if not resource:
		print("  ✗ Resource is null")
		return
	
	print("  ✓ Resource loaded")
	print("  Class: " + resource.get_class())
	print("  Script: " + str(resource.get_script()))
	
	# Check properties
	if resource.has_method("get_property_list"):
		var props = resource.get_property_list()
		var relevant_props = []
		for prop in props:
			if prop.name in ["manifest", "resources"]:
				relevant_props.append(prop.name)
		print("  Found properties: " + str(relevant_props))
	
	# Try accessing as generic resource
	if "manifest" in resource and "resources" in resource:
		print("  ✓ Has manifest and resources properties")
		var manifest = resource.manifest
		var resources = resource.resources
		if manifest:
			print("    Manifest type: " + manifest.get_class())
			if "object_id" in manifest:
				print("    Object ID: " + manifest.object_id)
		if resources:
			print("    Resources count: " + str(resources.size()))