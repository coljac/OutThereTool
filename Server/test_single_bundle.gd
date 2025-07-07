extends Node

## Test script to verify the new single-bundle preprocessing

func _ready():
	print("Testing single bundle preprocessing...")
	
	# Create preprocessor
	var preprocessor = preload("res://Server/preprocess.gd").new()
	
	# Test parameters
	var test_object_id = "test_galaxy_001"
	var input_dir = "res://test_data/fits/"  # Adjust to your test data location
	var output_dir = "res://test_data/output/"
	
	# Ensure output directory exists
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	
	# Process a single object
	print("Processing object: " + test_object_id)
	var bundle_path = preprocessor.preprocess_object(test_object_id, input_dir, output_dir)
	
	if bundle_path.is_empty():
		print("ERROR: Failed to create bundle")
		return
	
	print("Bundle created at: " + bundle_path)
	print("Bundle format: " + (".res (binary)" if bundle_path.ends_with(".res") else ".tres (text)"))
	
	# Try to load the bundle
	var bundle = load(bundle_path) as ObjectBundle
	if not bundle:
		print("ERROR: Failed to load bundle as ObjectBundle")
		return
	
	print("Bundle loaded successfully!")
	print("Bundle stats:")
	var stats = bundle.get_bundle_stats()
	for key in stats:
		print("  " + key + ": " + str(stats[key]))
	
	# Check manifest
	if bundle.manifest:
		print("\nManifest info:")
		print("  Object ID: " + bundle.manifest.object_id)
		print("  Band count: " + str(bundle.manifest.band_count))
		print("  Redshift: " + str(bundle.manifest.redshift))
		print("  Available filters: " + str(bundle.manifest.get_available_filters()))
	
	# Check individual resources
	print("\nChecking bundled resources:")
	
	# Check redshift
	var redshift_resource = bundle.get_resource("redshift")
	if redshift_resource:
		print("  ✓ Redshift resource found")
	else:
		print("  ✗ Redshift resource missing")
	
	# Check 1D spectra
	var filters = ["F115W", "F150W", "F200W"]
	for filter_name in filters:
		var spec_1d = bundle.get_resource("1d", filter_name)
		if spec_1d:
			print("  ✓ 1D spectrum found for " + filter_name)
		else:
			print("  ✗ 1D spectrum missing for " + filter_name)
	
	# Check direct images
	for filter_name in filters:
		var direct = bundle.get_resource("direct", filter_name)
		if direct:
			print("  ✓ Direct image found for " + filter_name)
		else:
			print("  ✗ Direct image missing for " + filter_name)
	
	# Check 2D spectra (example for PA 0)
	var test_pa = "0"
	for filter_name in filters:
		var spec_2d = bundle.get_resource("2d", filter_name, test_pa)
		if spec_2d:
			print("  ✓ 2D spectrum found for " + filter_name + " PA" + test_pa)
		else:
			print("  ✗ 2D spectrum missing for " + filter_name + " PA" + test_pa)
	
	# Verify file size reduction
	print("\nFile system check:")
	var dir = DirAccess.open(output_dir)
	if dir:
		dir.list_dir_begin()
		var file_count = 0
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.begins_with(test_object_id):
				file_count += 1
				print("  Found file: " + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		
		print("Total files for object: " + str(file_count))
		if file_count == 1:
			print("SUCCESS: Only one bundle file created!")
		else:
			print("WARNING: Multiple files found, expected only bundle file")
	
	print("\nTest complete!")