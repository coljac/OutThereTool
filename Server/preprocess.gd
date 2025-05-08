extends Node

## Pre-processor for FITS data
##
## This script handles the extraction and conversion of FITS data into
## optimized formats for faster loading and display in the application.

## Reference to the FitsHelper class
var fits_helper = null

## Log file for recording processing information
var log_file = null

## Metadata file for recording object information
var metadata_file = null

## Initialize the pre-processor
func _init():
	fits_helper = load("res://Scripts/fitshelper.gd").new()

## Process a single object
##
## @param object_id The ID of the object to process
## @param input_dir The directory containing the FITS files
## @param output_dir The directory to save processed data to
## @return The path to the generated manifest file
func preprocess_object(object_id: String, input_dir: String, output_dir: String) -> String:
	print("Processing object: " + object_id)
	
	# Create output directory if it doesn't exist
	var dir = DirAccess.open(output_dir)
	if not dir:
		DirAccess.make_dir_recursive_absolute(output_dir)
	
	# Create manifest
	var manifest = ObjectManifest.new()
	manifest.object_id = object_id
	manifest.object_name = object_id  # Default to ID, may be updated later
	manifest.spectrum_1d_paths = {}
	manifest.spectrum_2d_paths = {}
	manifest.direct_image_paths = {}
	
	# Ensure paths end with a slash
	if not input_dir.ends_with("/"):
		input_dir += "/"
	if not output_dir.ends_with("/"):
		output_dir += "/"
	
	# Process 1D spectra
	var spec_1d_path = input_dir + object_id + ".1D.fits"
	if FileAccess.file_exists(spec_1d_path):
		var spec_1d_result = preprocess_1d_spectra(object_id, spec_1d_path, output_dir)
		for filter_name in spec_1d_result:
			manifest.spectrum_1d_paths[filter_name] = spec_1d_result[filter_name]
	else:
		print("Warning: 1D spectrum file not found: " + spec_1d_path)
	
	# Process 2D spectra
	var spec_2d_path = input_dir + object_id + ".stack.fits"
	if FileAccess.file_exists(spec_2d_path):
		var spec_2d_result = preprocess_2d_spectra(object_id, spec_2d_path, output_dir)
		for filter_name in spec_2d_result:
			manifest.spectrum_2d_paths[filter_name] = spec_2d_result[filter_name]
	else:
		print("Warning: 2D spectrum file not found: " + spec_2d_path)
	
	# Process direct images
	var direct_path = input_dir + object_id + ".beams.fits"
	if FileAccess.file_exists(direct_path):
		var direct_result = preprocess_direct_images(object_id, direct_path, output_dir)
		for filter_name in direct_result:
			manifest.direct_image_paths[filter_name] = direct_result[filter_name]
	else:
		print("Warning: Direct image file not found: " + direct_path)
	
	# Process redshift data
	var redshift_path = input_dir + object_id + ".full.fits"
	if FileAccess.file_exists(redshift_path):
		manifest.redshift_path = preprocess_redshift(object_id, redshift_path, output_dir)
		
		# Extract redshift value for the manifest
		var redshift_resource = load(manifest.redshift_path) as RedshiftResource
		if redshift_resource:
			manifest.redshift = redshift_resource.best_redshift
	else:
		print("Warning: Redshift file not found: " + redshift_path)
	
	# Count bands
	manifest.band_count = manifest.get_available_filters().size()
	
	# Try to extract observation date from headers
	manifest.observation_date = extract_observation_date(object_id, input_dir)
	
	# Save manifest
	var manifest_path = output_dir + object_id + "_manifest.tres"
	var save_result = ResourceSaver.save(manifest, manifest_path)
	if save_result != OK:
		print("Error saving manifest: " + str(save_result))
		return ""
	
	# Write metadata to the metadata file
	write_object_metadata(manifest)
	
	print("Finished processing object: " + object_id)
	return manifest_path

## Process 1D spectra from a FITS file
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Dictionary mapping filter names to resource paths
func preprocess_1d_spectra(object_id: String, fits_path: String, output_dir: String) -> Dictionary:
	print("  Processing 1D spectra from: " + fits_path)
	var result = {}
	
	# Get 1D spectrum data using FitsHelper
	var spectrum_data = fits_helper.get_1d_spectrum(fits_path, true)
	
	# Process each filter
	for filter_name in spectrum_data:
		var resource = Spectrum1DResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		
		# Extract wavelengths and fluxes from the Vector2 array
		var wavelengths = PackedFloat32Array()
		var fluxes = PackedFloat32Array()
		for point in spectrum_data[filter_name]["fluxes"]:
			wavelengths.append(point.x)
			fluxes.append(point.y)
		
		resource.wavelengths = wavelengths
		resource.fluxes = fluxes
		resource.errors = spectrum_data[filter_name]["err"]
		
		# Save resource
		var resource_path = output_dir + object_id + "_1d_" + filter_name + ".tres"
		var save_result = ResourceSaver.save(resource, resource_path)
		if save_result != OK:
			print("    Error saving 1D spectrum resource: " + str(save_result))
			continue
		
		result[filter_name] = resource_path
		print("    Saved 1D spectrum for filter: " + filter_name)
	
	return result

## Process 2D spectra from a FITS file
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Dictionary mapping filter names to resource paths
func preprocess_2d_spectra(object_id: String, fits_path: String, output_dir: String) -> Dictionary:
	print("  Processing 2D spectra from: " + fits_path)
	var result = {}
	
	# Get 2D spectrum data using FitsHelper
	var spectrum_indices = fits_helper.get_2d_spectrum(fits_path)
	
	# Create a FITS reader to access the data
	var fits_reader = FITSReader.new()
	fits_reader.load_fits(fits_path)
	
	# Process each filter
	for filter_name in spectrum_indices:
		var hdu_index = spectrum_indices[filter_name]
		var header = fits_reader.get_header_info(hdu_index)
		var image_data = fits_reader.get_image_data(hdu_index)
		
		# Get dimensions
		var width = int(header["NAXIS1"])
		var height = int(header["NAXIS2"])
		
		# Calculate wavelength scaling
		var crpix = float(header["CRPIX1"])
		var crval = float(header["CRVAL1"])
		var cdelt = float(header["CD1_1"])
		var scaling = {
			"left": -crpix * cdelt + crval,
			"right": (width - crpix) * cdelt + crval
		}
		
		# Save image data as EXR
		var exr_path = output_dir + object_id + "_2d_" + filter_name + ".exr"
		save_as_exr(image_data, width, height, exr_path)
		
		# Create resource
		var resource = Spectrum2DResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		resource.texture_path = exr_path
		resource.scaling = scaling
		resource.width = width
		resource.height = height
		resource.header_info = header
		
		# Save resource
		var resource_path = output_dir + object_id + "_2d_" + filter_name + ".tres"
		var save_result = ResourceSaver.save(resource, resource_path)
		if save_result != OK:
			print("    Error saving 2D spectrum resource: " + str(save_result))
			continue
		
		result[filter_name] = resource_path
		print("    Saved 2D spectrum for filter: " + filter_name)
	
	return result

## Process direct images from a FITS file
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Dictionary mapping filter names to resource paths
func preprocess_direct_images(object_id: String, fits_path: String, output_dir: String) -> Dictionary:
	print("  Processing direct images from: " + fits_path)
	var result = {}
	
	# Get direct image data using FitsHelper
	var direct_indices = fits_helper.get_directs(fits_path)
	
	# Create a FITS reader to access the data
	var fits_reader = FITSReader.new()
	fits_reader.load_fits(fits_path)
	
	# Process each filter
	for filter_name in direct_indices:
		var hdu_index = direct_indices[filter_name]
		var header = fits_reader.get_header_info(hdu_index)
		var image_data = fits_reader.get_image_data(hdu_index)
		
		# Get dimensions
		var width = int(header["NAXIS1"])
		var height = int(header["NAXIS2"])
		
		# Save image data as EXR
		var exr_path = output_dir + object_id + "_direct_" + filter_name + ".exr"
		save_as_exr(image_data, width, height, exr_path)
		
		# Create resource
		var resource = DirectImageResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		resource.texture_path = exr_path
		resource.width = width
		resource.height = height
		resource.header_info = header
		
		# Extract WCS information
		var wcs_info = {}
		for key in header:
			if key.begins_with("CD") or key.begins_with("CRPIX") or key.begins_with("CRVAL") or key.begins_with("CTYPE"):
				wcs_info[key] = header[key]
		resource.wcs_info = wcs_info
		
		# Check for segmentation map (for F200W)
		if filter_name == "F200W" and hdu_index + 1 < fits_reader.get_info()["hdus"].size():
			var segmap_data = fits_reader.get_image_data(hdu_index + 1)
			var segmap_path = output_dir + object_id + "_segmap.exr"
			save_as_exr(segmap_data, width, height, segmap_path)
			resource.segmap_path = segmap_path
			print("    Saved segmentation map for F200W")
		
		# Save resource
		var resource_path = output_dir + object_id + "_direct_" + filter_name + ".tres"
		var save_result = ResourceSaver.save(resource, resource_path)
		if save_result != OK:
			print("    Error saving direct image resource: " + str(save_result))
			continue
		
		result[filter_name] = resource_path
		print("    Saved direct image for filter: " + filter_name)
	
	return result

## Process redshift data from a FITS file
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Path to the saved redshift resource
func preprocess_redshift(object_id: String, fits_path: String, output_dir: String) -> String:
	print("  Processing redshift data from: " + fits_path)
	
	# Get redshift data using FitsHelper
	var pz_data = fits_helper.get_pz(fits_path)
	var z_grid = pz_data[0]
	var pdf = pz_data[1]
	
	# Calculate log10 of PDF
	var log_pdf = PackedFloat32Array()
	for p in pdf:
		log_pdf.append(fits_helper.log10(p))
	
	# Find peaks
	var peaks = fits_helper.peak_finding(log_pdf, 50)
	
	# Find best redshift (highest peak)
	var best_redshift = 0.0
	var max_pdf = -INF
	for peak in peaks:
		var z = z_grid[peak["x"]]
		var p = peak["max"]
		if p > max_pdf:
			max_pdf = p
			best_redshift = z
	
	# Create resource
	var resource = RedshiftResource.new()
	resource.object_id = object_id
	resource.z_grid = z_grid
	resource.pdf = pdf
	resource.log_pdf = log_pdf
	resource.peaks = peaks
	resource.best_redshift = best_redshift
	
	# Save resource
	var resource_path = output_dir + object_id + "_redshift.tres"
	var save_result = ResourceSaver.save(resource, resource_path)
	if save_result != OK:
		print("    Error saving redshift resource: " + str(save_result))
		return ""
	
	print("    Saved redshift data with best z = " + str(best_redshift))
	return resource_path

## Save image data as an EXR file
##
## @param data The image data as a PackedFloat32Array
## @param width The width of the image
## @param height The height of the image
## @param path The path to save the EXR file to
func save_as_exr(data: PackedFloat32Array, width: int, height: int, path: String) -> void:
	var img = Image.create(width, height, false, Image.FORMAT_RF)
	
	for y in range(height):
		for x in range(width):
			var idx = y * width + x
			if idx < data.size():
				img.set_pixel(x, y, Color(data[idx], 0, 0, 0))
	
	var save_result = img.save_exr(path)
	if save_result != OK:
		print("    Error saving EXR file: " + str(save_result))

## Extract observation date from FITS headers
##
## @param object_id The ID of the object
## @param input_dir The directory containing the FITS files
## @return The observation date as a string
func extract_observation_date(object_id: String, input_dir: String) -> String:
	var date = ""
	
	# Try to get date from direct image file first
	var direct_path = input_dir + object_id + ".beams.fits"
	if FileAccess.file_exists(direct_path):
		var fits_reader = FITSReader.new()
		fits_reader.load_fits(direct_path)
		var header = fits_reader.get_header_info(0)
		
		if "DATE-OBS" in header:
			date = header["DATE-OBS"]
		elif "DATE" in header:
			date = header["DATE"]
	
	# If not found, try other files
	if date.is_empty():
		var files = [
			input_dir + object_id + ".1D.fits",
			input_dir + object_id + ".stack.fits",
			input_dir + object_id + ".full.fits"
		]
		
		for file_path in files:
			if FileAccess.file_exists(file_path):
				var fits_reader = FITSReader.new()
				fits_reader.load_fits(file_path)
				var header = fits_reader.get_header_info(0)
				
				if "DATE-OBS" in header:
					date = header["DATE-OBS"]
					break
				elif "DATE" in header:
					date = header["DATE"]
					break
	
	return date

## Initialize the metadata file
##
## @param output_dir The directory to save the metadata file to
func init_metadata_file(output_dir: String) -> void:
	if not output_dir.ends_with("/"):
		output_dir += "/"
	
	var file_path = output_dir + "object_metadata.txt"
	metadata_file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if metadata_file:
		metadata_file.store_line("object_id\tobject_name\tband_count\tobservation_date\tredshift")
	else:
		print("Error: Could not create metadata file at " + file_path)

## Write object metadata to the metadata file
##
## @param manifest The object manifest containing metadata
func write_object_metadata(manifest: ObjectManifest) -> void:
	if not metadata_file:
		print("Error: Metadata file not initialized")
		return
	
	var line = manifest.object_id + "\t" + \
			   manifest.object_name + "\t" + \
			   str(manifest.band_count) + "\t" + \
			   manifest.observation_date + "\t" + \
			   str(manifest.redshift)
	
	metadata_file.store_line(line)

## Initialize the log file
##
## @param output_dir The directory to save the log file to
func init_log_file(output_dir: String) -> void:
	if not output_dir.ends_with("/"):
		output_dir += "/"
	
	var file_path = output_dir + "preprocess_log.txt"
	log_file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if log_file:
		var datetime = Time.get_datetime_dict_from_system()
		var date_str = "%04d-%02d-%02d %02d:%02d:%02d" % [
			datetime["year"], datetime["month"], datetime["day"],
			datetime["hour"], datetime["minute"], datetime["second"]
		]
		log_file.store_line("Pre-processing started at " + date_str)
	else:
		print("Error: Could not create log file at " + file_path)

## Write a message to the log file
##
## @param message The message to write
func log_message(message: String) -> void:
	if log_file:
		log_file.store_line(message)
	print(message)

## Close the log and metadata files
func close_files() -> void:
	if log_file:
		var datetime = Time.get_datetime_dict_from_system()
		var date_str = "%04d-%02d-%02d %02d:%02d:%02d" % [
			datetime["year"], datetime["month"], datetime["day"],
			datetime["hour"], datetime["minute"], datetime["second"]
		]
		log_file.store_line("Pre-processing completed at " + date_str)
		log_file.close()
		log_file = null
	
	if metadata_file:
		metadata_file.close()
		metadata_file = null

## Batch process multiple objects
##
## @param object_ids Array of object IDs to process
## @param input_dir The directory containing the FITS files
## @param output_dir The directory to save processed data to
func batch_process(object_ids: Array, input_dir: String, output_dir: String) -> void:
	# Initialize log and metadata files
	init_log_file(output_dir)
	init_metadata_file(output_dir)
	
	log_message("Starting batch processing of " + str(object_ids.size()) + " objects")
	
	# Process each object
	var success_count = 0
	var error_count = 0
	
	for object_id in object_ids:
		log_message("Processing object " + str(success_count + error_count + 1) + "/" + str(object_ids.size()) + ": " + object_id)
		
		var manifest_path = preprocess_object(object_id, input_dir, output_dir)
		if not manifest_path.is_empty():
			success_count += 1
		else:
			error_count += 1
			log_message("Error processing object: " + object_id)
	
	log_message("Batch processing completed")
	log_message("Successful: " + str(success_count) + ", Errors: " + str(error_count))
	
	# Close log and metadata files
	close_files()

## Process all FITS files in a directory
##
## @param input_dir The directory containing the FITS files
## @param output_dir The directory to save processed data to
## @param pattern The pattern to match object IDs (default: "*.full.fits")
func process_directory(input_dir: String, output_dir: String, pattern: String = "*.full.fits") -> void:
	# Initialize log and metadata files
	init_log_file(output_dir)
	init_metadata_file(output_dir)
	
	log_message("Scanning directory: " + input_dir)
	
	# Scan directory for FITS files
	var dir = DirAccess.open(input_dir)
	if not dir:
		log_message("Error: Could not open directory " + input_dir)
		close_files()
		return
	
	var object_ids = []
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.match(pattern):
			var object_id = file_name.replace(".full.fits", "")
			object_ids.append(object_id)
		file_name = dir.get_next()
	
	log_message("Found " + str(object_ids.size()) + " objects to process")
	
	# Process each object
	var success_count = 0
	var error_count = 0
	
	for object_id in object_ids:
		log_message("Processing object " + str(success_count + error_count + 1) + "/" + str(object_ids.size()) + ": " + object_id)
		
		var manifest_path = preprocess_object(object_id, input_dir, output_dir)
		if not manifest_path.is_empty():
			success_count += 1
		else:
			error_count += 1
			log_message("Error processing object: " + object_id)
	
	log_message("Directory processing completed")
	log_message("Successful: " + str(success_count) + ", Errors: " + str(error_count))
	
	# Close log and metadata files
	close_files()
