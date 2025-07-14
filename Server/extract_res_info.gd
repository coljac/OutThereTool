#!/usr/bin/env -S uv run godot --headless --script
extends SceneTree

## Script to extract information from .res files or directories of .res files
## Outputs: field,object_id,redshift,num_filters

# Import required classes
const ObjectBundle = preload("res://Server/object_bundle.gd")
const ObjectManifest = preload("res://Server/object_manifest.gd")

func _init():
	var args = parse_args()
	
	if args.has("help") or not args.has("path"):
		print_usage()
		quit()
		return
	
	var path = args["path"]
	
	# Print CSV header
	print("field,object_id,redshift,num_filters")
	
	# Check if path is a file or directory
	if FileAccess.file_exists(path):
		if path.ends_with(".res"):
			process_res_file(path)
		else:
			print_rich("[color=red]Error: File must have .res extension[/color]")
	elif DirAccess.dir_exists_absolute(path):
		process_directory(path)
	else:
		print_rich("[color=red]Error: Path does not exist: " + path + "[/color]")
	
	quit()

## Parse command-line arguments
func parse_args() -> Dictionary:
	var args = {}
	
	for arg in OS.get_cmdline_args():
		if arg == "--help":
			args["help"] = true
		elif arg.begins_with("--path="):
			args["path"] = arg.substr(7)
		elif not arg.begins_with("--") and not arg.ends_with(".gd") and not arg.contains("godot"):
			# Treat non-option arguments as the path (for backward compatibility)
			args["path"] = arg
	
	return args

## Print usage information
func print_usage() -> void:
	print("FITS Resource Information Extractor")
	print("")
	print("Usage:")
	print("  godot --headless --script Server/extract_res_info.gd --path=<file_or_directory>")
	print("  godot --headless --script Server/extract_res_info.gd <file_or_directory>")
	print("")
	print("Options:")
	print("  --path=PATH            Path to .res file or directory containing .res files")
	print("  --help                 Show this help message")
	print("")
	print("Examples:")
	print("  # Process a single .res file")
	print("  godot --headless --script Server/extract_res_info.gd --path=processed/uma-03_05858_bundle.res")
	print("")
	print("  # Process all .res files in a directory")
	print("  godot --headless --script Server/extract_res_info.gd --path=processed/")
	print("")
	print("Output: CSV format with field,object_id,redshift,num_filters")

func process_directory(dir_path: String):
	var dir = DirAccess.open(dir_path)
	if not dir:
		print_rich("[color=red]Error: Cannot open directory: " + dir_path + "[/color]")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var res_files = []
	
	# Collect all .res files
	while file_name != "":
		if file_name.ends_with(".res"):
			res_files.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Sort files for consistent output
	res_files.sort()
	
	# Process each .res file
	for res_file in res_files:
		process_res_file(res_file)

func process_res_file(file_path: String):
	# Try to load the resource
	var resource = ResourceLoader.load(file_path)
	if not resource:
		print_rich("[color=yellow]Warning: Could not load resource: " + file_path + "[/color]")
		return
	
	# Try to cast to ObjectBundle
	var bundle = resource as ObjectBundle
	if not bundle:
		print_rich("[color=yellow]Warning: Resource is not an ObjectBundle: " + file_path + "[/color]")
		return
	
	if not bundle.manifest:
		print_rich("[color=yellow]Warning: Bundle has no manifest: " + file_path + "[/color]")
		return
	
	var manifest = bundle.manifest
	
	# Extract required information
	var object_id = manifest.object_id if "object_id" in manifest else "unknown"
	var redshift = manifest.redshift if "redshift" in manifest else 0.0
	var num_filters = 0
	var field = "unknown"
	
	# Get number of filters from available filters
	if manifest.has_method("get_available_filters"):
		var filters = manifest.get_available_filters()
		num_filters = filters.size()
	else:
		# Fallback: count from band_count if available
		if "band_count" in manifest:
			num_filters = manifest.band_count
	
	# Try to extract field from metadata
	if "metadata" in manifest and manifest.metadata:
		if "field" in manifest.metadata:
			field = manifest.metadata["field"]
		elif "field_name" in manifest.metadata:
			field = manifest.metadata["field_name"]
		elif "survey_field" in manifest.metadata:
			field = manifest.metadata["survey_field"]
	
	# If field is still unknown, try to extract from object_id
	if field == "unknown" and object_id != "unknown":
		# Many object IDs follow pattern like "field-name_objectnum"
		var parts = object_id.split("_")
		if parts.size() > 0:
			var potential_field = parts[0]
			# Remove common prefixes that aren't field names
			if potential_field.begins_with("obj-"):
				potential_field = potential_field.substr(4)
			field = potential_field
	
	# Output CSV line
	print("%s,%s,%.6f,%d" % [field, object_id, redshift, num_filters])

func print_rich(text: String):
	# For headless mode, just print without rich formatting
	var clean_text = text
	# Remove rich text tags
	var regex = RegEx.new()
	regex.compile("\\[/?[^\\]]*\\]")
	clean_text = regex.sub(clean_text, "", true)
	print(clean_text)