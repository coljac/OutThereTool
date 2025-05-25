extends EditorImportPlugin

func get_importer_name() -> String:
	return "fits_importer"

func get_visible_name() -> String:
	return "FITS Importer"

func get_recognized_extensions() -> PackedStringArray:
	return ["fits"]

func get_save_extension() -> String:
	return "res"

func get_resource_type() -> String:
	# A custom Resource we define (see below)
	return "FitsResource"

func import(
	source_file: String,
	save_path: String,
	options: Dictionary,
	platform_variants: Array,
	gen_files: Array
) -> int:
	# (Pseudo-code) Load the FITS data from your extension
	#var fits_data = load_fits_data_from_cpp_extension(source_file)

	print("GOOO")
	#var resource = FitsResource.new()
	#resource.data = fits_data
	var resource = FITSReader.new()
	# Save the custom resource
	ResourceSaver.save(resource, save_path + ".res")
	return OK
