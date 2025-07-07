extends Node

# Import the ObjectBundle class and dependencies
const ObjectBundle = preload("res://Server/object_bundle.gd")
const ObjectManifest = preload("res://Server/object_manifest.gd")

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
	log_message("Processing object: " + object_id)
	
	# Create output directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(output_dir):
		var dir_result = DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_result != OK:
			log_message("Error creating output directory: " + str(dir_result))
			return ""
	
	# Create manifest
	var manifest = ObjectManifest.new()
	manifest.object_id = object_id
	manifest.object_name = object_id # Default to ID, may be updated later
	manifest.spectrum_1d_paths = {}
	manifest.spectrum_2d_paths = {}
	manifest.direct_image_paths = {}
	manifest.spectrum_2d_paths_by_pa = {}
	
	# Ensure paths end with a slash
	if not input_dir.ends_with("/"):
		input_dir += "/"
	if not output_dir.ends_with("/"):
		output_dir += "/"
	
	# Create a bundled resource containing all data
	var bundle = ObjectBundle.new()
	bundle.manifest = manifest
	bundle.resources = {}
	
	# Process 1D spectra directly into bundle
	var spec_1d_path = input_dir + object_id + ".1D.fits"
	if FileAccess.file_exists(spec_1d_path):
		var spec_1d_resources = create_1d_spectra_resources(object_id, spec_1d_path)
		for filter_name in spec_1d_resources:
			bundle.resources["1d_" + filter_name] = spec_1d_resources[filter_name]
			# Update manifest to point to the resource that will be cached
			manifest.spectrum_1d_paths[filter_name] = object_id + "_1d_" + filter_name + ".res"
	else:
		log_message("Warning: 1D spectrum file not found: " + spec_1d_path)
	
	# Process 2D spectra directly into bundle
	var spec_2d_path = input_dir + object_id + ".stack.fits"
	if FileAccess.file_exists(spec_2d_path):
		var spec_2d_resources = create_2d_spectra_resources(object_id, spec_2d_path)
		
		# Store 2D spectra organized by PA
		var paths_by_pa = {}
		for key in spec_2d_resources:
			var resource = spec_2d_resources[key]
			var pa = resource.position_angle
			var filter_name = resource.filter_name
			
			if not pa in paths_by_pa:
				paths_by_pa[pa] = {}
			# Update manifest to point to the resource that will be cached
			paths_by_pa[pa][filter_name] = object_id + "_" + key + ".res"
			
			# Also maintain the old format for backward compatibility
			manifest.spectrum_2d_paths[filter_name + "_PA" + pa] = object_id + "_" + key + ".res"
			
			# Add to bundle
			bundle.resources[key] = resource
		
		manifest.spectrum_2d_paths_by_pa = paths_by_pa
	else:
		log_message("Warning: 2D spectrum file not found: " + spec_2d_path)
	
	# Process direct images directly into bundle
	var direct_path = input_dir + object_id + ".beams.fits"
	if FileAccess.file_exists(direct_path):
		var direct_resources = create_direct_image_resources(object_id, direct_path)
		for filter_name in direct_resources:
			bundle.resources["direct_" + filter_name] = direct_resources[filter_name]
			# Update manifest to point to the resource that will be cached
			manifest.direct_image_paths[filter_name] = object_id + "_direct_" + filter_name + ".res"
	else:
		log_message("Warning: Direct image file not found: " + direct_path)
	
	# Process redshift data directly into bundle
	var redshift_path = input_dir + object_id + ".full.fits"
	if FileAccess.file_exists(redshift_path):
		var redshift_resource = create_redshift_resource(object_id, redshift_path)
		if redshift_resource:
			bundle.resources["redshift"] = redshift_resource
			# Update manifest to point to the resource that will be cached
			manifest.redshift_path = object_id + "_redshift.res"
			manifest.redshift = redshift_resource.best_redshift
	else:
		log_message("Warning: Redshift file not found: " + redshift_path)
	
	# Count bands
	manifest.band_count = manifest.get_available_filters().size()
	
	# Try to extract observation date from headers
	manifest.observation_date = extract_observation_date(object_id, input_dir)
	
	# Add metadata
	manifest.metadata = {
		"processing_date": Time.get_datetime_string_from_system(),
		"input_directory": input_dir,
		"output_directory": output_dir
	}
	
	# Update the bundle's manifest
	bundle.manifest = manifest
	
	# Save as single .res file (binary format for better performance and type preservation)
	var bundle_path = output_dir + object_id + "_bundle.res"
	# Binary format preserves classes better and loads faster
	var save_result = ResourceSaver.save(bundle, bundle_path)
	if save_result != OK:
		log_message("Error saving bundle: " + str(save_result))
		return ""
	
	# Write metadata to the metadata file
	write_object_metadata(manifest)
	
	log_message("Finished processing object: " + object_id + " (single bundled file)")
	return bundle_path

## Create 1D spectra resources in memory
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @return Dictionary mapping filter names to resources
func create_1d_spectra_resources(object_id: String, fits_path: String) -> Dictionary:
	log_message("  Creating 1D spectra resources from: " + fits_path)
	var result = {}
	
	# Get 1D spectrum data using FitsHelper
	var spectrum_data = fits_helper.get_1d_spectrum(fits_path, true)
	if spectrum_data.is_empty():
		log_message("    Error: Failed to extract 1D spectrum data from " + fits_path)
		return result
	
	# Process each filter
	for filter_name in spectrum_data:
		var resource = Spectrum1DResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		
		# Extract data from FITS table
		var data = spectrum_data[filter_name]
		var fluxes = data['fluxes']
		var waves = data['waves']
		var bestfit = data['bestfit']
		var cont = data['cont']
		var err = data['err']
		var N = Array(fluxes).size()
		var flat = PackedFloat32Array()
		flat.resize(N)
		for i in range(N):
			flat[i] = 1.0

		flat = data['flat'] if 'flat' in data else flat
		var contam = data['contam'] if 'contam' in data else PackedFloat32Array([0.0] * fluxes.size())
		
		resource.wavelengths = waves
		resource.fluxes = fluxes
		resource.bestfit = bestfit
		resource.continuum = cont
		resource.errors = err
		resource.flat = flat
		resource.contam = contam
	
		# Add metadata
		resource.metadata = {
			"source_file": fits_path,
			"processing_date": Time.get_datetime_string_from_system(),
			"filter": filter_name
		}
		
		result[filter_name] = resource
		log_message("    Created 1D spectrum resource for filter: " + filter_name)
	
	return result

## Create 2D spectra resources in memory
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @return Dictionary mapping resource keys to resources
func create_2d_spectra_resources(object_id: String, fits_path: String) -> Dictionary:
	log_message("  Creating 2D spectra resources from: " + fits_path)
	var result = {}
	
	# Get 2D spectrum data using FitsHelper
	var data_2d = fits_helper.get_2d_spectrum(fits_path)
	if data_2d.is_empty():
		log_message("    Error: Failed to extract 2D spectrum indices from " + fits_path)
		return result
	
	# Create a FITS reader to access the data
	var fits_reader = FITSReader.new()
	if not fits_reader.load_fits(fits_path):
		log_message("    Error: Failed to load FITS file: " + fits_path)
		return result
	
	# Process each PA and filter combination
	for pa in data_2d:
		for filter_name in data_2d[pa]:
			# Skip non-filter entries like CONTAM, MODEL, etc.
			if filter_name not in ['F115W', 'F150W', 'F200W']:
				continue
				
			var resource = Spectrum2DResource.new()
			
			# Get science data
			var sci_data = data_2d[pa][filter_name]['SCI']
			var sci_hdu_index = sci_data['index']
			var header = fits_reader.get_header_info(sci_hdu_index)
			var image_data = fits_reader.get_image_data_normalized(sci_hdu_index)
			
			# Check for contamination and model data
			if 'CONTAM' in data_2d[pa][filter_name] and 'MODEL' in data_2d[pa][filter_name]:
				var contam_data = data_2d[pa][filter_name]['CONTAM']
				var model_data = data_2d[pa][filter_name]['MODEL']
				
				var contam_header = fits_reader.get_header_info(contam_data['index'])
				var model_header = fits_reader.get_header_info(model_data['index'])
				
				resource.contam_data = fits_reader.get_image_data_normalized(contam_data['index'])
				var raw_model_data = fits_reader.get_image_data_normalized(model_data['index'])
				
				# Calculate SCI - MODEL (science minus model) for model_data
				# This shows the science data with the model subtracted
				var sci_minus_model = PackedFloat32Array()
				if image_data.size() == raw_model_data.size():
					sci_minus_model.resize(image_data.size())
					for i in range(image_data.size()):
						sci_minus_model[i] = image_data[i] - raw_model_data[i]
					resource.model_data = sci_minus_model
					log_message("    Calculated SCI - MODEL subtraction for PA " + pa + ", filter " + filter_name)
				else:
					# Fallback if dimensions don't match
					resource.model_data = raw_model_data
					log_message("    Warning: SCI and MODEL dimensions don't match, using raw MODEL data for PA " + pa + ", filter " + filter_name)
				
				# Store the actual dimensions of contam/model data
				resource.contam_width = int(contam_header.get("NAXIS1", 0))
				resource.contam_height = int(contam_header.get("NAXIS2", 0))
				resource.model_width = int(model_header.get("NAXIS1", 0))
				resource.model_height = int(model_header.get("NAXIS2", 0))
			
			if image_data.size() == 0:
				log_message("    Error: Failed to extract image data for PA " + pa + ", filter " + filter_name)
				continue
			
			# Get dimensions
			var width = int(header.get("NAXIS1", 0))
			var height = int(header.get("NAXIS2", 0))
			
			if width == 0 or height == 0:
				log_message("    Error: Invalid dimensions for PA " + pa + ", filter " + filter_name)
				continue
			
			# Calculate wavelength scaling
			var crpix = float(header.get("CRPIX1", 1.0))
			var crval = float(header.get("CRVAL1", 0.0))
			var cdelt = float(header.get("CD1_1", 0.0))
			if cdelt == 0.0 and header.has("CDELT1"):
				cdelt = float(header["CDELT1"])
			
			var scaling = {
				"left": - crpix * cdelt + crval,
				"right": (width - crpix) * cdelt + crval
			}
			
			# Create resource with raw image data
			resource.object_id = object_id
			resource.filter_name = filter_name
			resource.image_data = image_data
			resource.scaling = scaling
			resource.width = width
			resource.height = height
			resource.header_info = header
			
			# Add PA information to the resource
			resource.position_angle = pa
			
			# Add metadata
			resource.metadata = {
				"source_file": fits_path,
				"processing_date": Time.get_datetime_string_from_system(),
				"wavelength_unit": header.get("CUNIT1", "Angstrom"),
				"filter": filter_name,
				"position_angle": pa
			}
			
			# Store resource with key matching bundle format
			var key = "2d_PA" + pa + "_" + filter_name
			result[key] = resource
			log_message("    Created 2D spectrum resource for PA " + pa + " and filter: " + filter_name)
	
	return result

## Create redshift resource in memory
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @return The redshift resource or null if failed
func create_redshift_resource(object_id: String, fits_path: String) -> Resource:
	log_message("  Creating redshift resource from: " + fits_path)
	
	# Get redshift data using FitsHelper
	var pz_data = fits_helper.get_pz(fits_path)
	if pz_data.size() < 2 or pz_data[0].size() == 0 or pz_data[1].size() == 0:
		log_message("    Error: Failed to extract redshift data from " + fits_path)
		return null
	
	var z_grid = pz_data[0]
	var pdf = pz_data[1]
	
	# Calculate log10 of PDF
	var log_pdf = PackedFloat32Array()
	for p in pdf:
		if p <= 0: # Avoid log of zero or negative values
			log_pdf.append(-INF)
		else:
			log_pdf.append(fits_helper.log10(p))
	
	# Find peaks
	var peaks = fits_helper.peak_finding(log_pdf, 50)
	
	# Find best redshift (highest peak)
	var best_redshift = 0.0
	var max_pdf = - INF
	for peak in peaks:
		if peak["x"] < z_grid.size(): # Ensure index is valid
			var z = z_grid[peak["x"]]
			var p = peak["max"]
			if p > max_pdf:
				max_pdf = p
				best_redshift = z
	
	# Create a FITS reader to access header information
	var fits_reader = FITSReader.new()
	var header_info = {}
	if fits_reader.load_fits(fits_path):
		header_info = fits_reader.get_header_info(0)
	
	# Create resource
	var resource = RedshiftResource.new()
	resource.object_id = object_id
	resource.z_grid = z_grid
	resource.pdf = pdf
	resource.log_pdf = log_pdf
	resource.peaks.append(peaks) # [peaks[0]['max']]
	resource.best_redshift = best_redshift
	resource.header_info = header_info
	
	# Add metadata
	resource.metadata = {
		"source_file": fits_path,
		"processing_date": Time.get_datetime_string_from_system(),
		"peak_count": peaks.size()
	}
	
	log_message("    Created redshift resource with best z = " + str(best_redshift))
	return resource

## Process 1D spectra from a FITS file (legacy function for compatibility)
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Dictionary mapping filter names to resource paths
func preprocess_1d_spectra(object_id: String, fits_path: String, output_dir: String) -> Dictionary:
	log_message("  Processing 1D spectra from: " + fits_path)
	var result = {}
	
	# Get 1D spectrum data using FitsHelper
	var spectrum_data = fits_helper.get_1d_spectrum(fits_path, true)
	if spectrum_data.is_empty():
		log_message("    Error: Failed to extract 1D spectrum data from " + fits_path)
		return result
	
	# Process each filter
	for filter_name in spectrum_data:
		var resource = Spectrum1DResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		
		# Extract data from FITS table
		var data = spectrum_data[filter_name]
		# var data = fits_helper.get_table_data(h['index'])
		var fluxes = data['fluxes']
		var waves = data['waves']
		var bestfit = data['bestfit']
		var cont = data['cont']
		var err = data['err']
		var N = Array(fluxes).size()
		var flat = PackedFloat32Array()
		flat.resize(N)
		for i in range(N):
			flat[i] = 1.0

		flat = data['flat'] if 'flat' in data else flat
		var contam = data['contam'] if 'contam' in data else PackedFloat32Array([0.0] * fluxes.size())
		
		resource.wavelengths = waves
		resource.fluxes = fluxes
		resource.bestfit = bestfit
		resource.continuum = cont
		resource.errors = err
		resource.flat = flat
		resource.contam = contam
	
		# Add metadata
		resource.metadata = {
			"source_file": fits_path,
			"processing_date": Time.get_datetime_string_from_system(),
			"filter": filter_name
		}
		
		# Save resource
		var resource_path = output_dir + object_id + "_1d_" + filter_name + ".res"
		var save_result = ResourceSaver.save(resource, resource_path)
		if save_result != OK:
			log_message("    Error saving 1D spectrum resource: " + str(save_result))
			continue
		
		result[filter_name] = resource_path
		log_message("    Saved 1D spectrum for filter: " + filter_name)
	
	return result

## Process 2D spectra from a FITS file
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Dictionary mapping PA and filter combinations to resource paths
func preprocess_2d_spectra(object_id: String, fits_path: String, output_dir: String) -> Dictionary:
	log_message("  Processing 2D spectra from: " + fits_path)
	var result = {}
	
	# Get 2D spectrum data using FitsHelper
	var data_2d = fits_helper.get_2d_spectrum(fits_path)
	if data_2d.is_empty():
		log_message("    Error: Failed to extract 2D spectrum indices from " + fits_path)
		return result
	
	# Create a FITS reader to access the data
	var fits_reader = FITSReader.new()
	if not fits_reader.load_fits(fits_path):
		log_message("    Error: Failed to load FITS file: " + fits_path)
		return result
	
	# Process each PA and filter combination
	for pa in data_2d:
		# Initialize PA entry in result dictionary if it doesn't exist
		if not pa in result:
			result[pa] = {}
			
		for filter_name in data_2d[pa]:
			# Skip non-filter entries like CONTAM, MODEL, etc.
			if filter_name not in ['F115W', 'F150W', 'F200W']:
				continue
				
			var resource = Spectrum2DResource.new()
			
			# Get science data
			var sci_data = data_2d[pa][filter_name]['SCI']
			var sci_hdu_index = sci_data['index']
			var header = fits_reader.get_header_info(sci_hdu_index)
			var image_data = fits_reader.get_image_data_normalized(sci_hdu_index)
			# Check for contamination and model data
			if 'CONTAM' in data_2d[pa][filter_name] and 'MODEL' in data_2d[pa][filter_name]:
				var contam_data = data_2d[pa][filter_name]['CONTAM']
				var model_data = data_2d[pa][filter_name]['MODEL']
				
				var contam_header = fits_reader.get_header_info(contam_data['index'])
				var model_header = fits_reader.get_header_info(model_data['index'])
				
				resource.contam_data = fits_reader.get_image_data_normalized(contam_data['index'])
				var raw_model_data = fits_reader.get_image_data_normalized(model_data['index'])
				
				# Calculate SCI - MODEL (science minus model) for model_data
				# This shows the science data with the model subtracted
				var sci_minus_model = PackedFloat32Array()
				if image_data.size() == raw_model_data.size():
					sci_minus_model.resize(image_data.size())
					for i in range(image_data.size()):
						sci_minus_model[i] = image_data[i] - raw_model_data[i]
					resource.model_data = sci_minus_model
					log_message("    Calculated SCI - MODEL subtraction for PA " + pa + ", filter " + filter_name)
				else:
					# Fallback if dimensions don't match
					resource.model_data = raw_model_data
					log_message("    Warning: SCI and MODEL dimensions don't match, using raw MODEL data for PA " + pa + ", filter " + filter_name)
				
				# Store the actual dimensions of contam/model data
				resource.contam_width = int(contam_header.get("NAXIS1", 0))
				resource.contam_height = int(contam_header.get("NAXIS2", 0))
				resource.model_width = int(model_header.get("NAXIS1", 0))
				resource.model_height = int(model_header.get("NAXIS2", 0))
			
			if image_data.size() == 0:
				log_message("    Error: Failed to extract image data for PA " + pa + ", filter " + filter_name)
				continue
			
			# Get dimensions
			var width = int(header.get("NAXIS1", 0))
			var height = int(header.get("NAXIS2", 0))
			
			if width == 0 or height == 0:
				log_message("    Error: Invalid dimensions for PA " + pa + ", filter " + filter_name)
				continue
			
			# Calculate wavelength scaling
			var crpix = float(header.get("CRPIX1", 1.0))
			var crval = float(header.get("CRVAL1", 0.0))
			var cdelt = float(header.get("CD1_1", 0.0))
			if cdelt == 0.0 and header.has("CDELT1"):
				cdelt = float(header["CDELT1"])
			
			var scaling = {
				"left": - crpix * cdelt + crval,
				"right": (width - crpix) * cdelt + crval
			}
			
			# Create resource with raw image data
			resource.object_id = object_id
			resource.filter_name = filter_name
			resource.image_data = image_data
			resource.scaling = scaling
			resource.width = width
			resource.height = height
			resource.header_info = header
			
			# Add PA information to the resource
			resource.position_angle = pa
			
			# Add metadata
			resource.metadata = {
				"source_file": fits_path,
				"processing_date": Time.get_datetime_string_from_system(),
				"wavelength_unit": header.get("CUNIT1", "Angstrom"),
				"filter": filter_name,
				"position_angle": pa
			}
			
			# Save resource with PA in the filename
			var resource_path = output_dir + object_id + "_2d_PA" + pa + "_" + filter_name + ".res"
			var save_result = ResourceSaver.save(resource, resource_path)
			if save_result != OK:
				log_message("    Error saving 2D spectrum resource: " + str(save_result))
				continue
			
			# Store the resource path in the nested dictionary
			result[pa][filter_name] = resource_path
			log_message("    Saved 2D spectrum for PA " + pa + " and filter: " + filter_name)
	
	return result

## Create direct image resources in memory
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @return Dictionary mapping filter names to resources
func create_direct_image_resources(object_id: String, fits_path: String) -> Dictionary:
	log_message("  Creating direct image resources from: " + fits_path)
	var result = {}
	
	# Get direct image data using FitsHelper
	var direct_indices = fits_helper.get_directs(fits_path)
	if direct_indices.is_empty():
		log_message("    Error: Failed to extract direct image indices from " + fits_path)
		return result
	
	# Create a FITS reader to access the data
	var fits_reader = FITSReader.new()
	if not fits_reader.load_fits(fits_path):
		log_message("    Error: Failed to load FITS file: " + fits_path)
		return result
	
	# Process each filter
	for filter_name in direct_indices:
		var hdu_index = direct_indices[filter_name]['index']
		var header = fits_reader.get_header_info(hdu_index)
		var image_data = fits_reader.get_image_data_normalized(hdu_index)
		
		if image_data.size() == 0:
			log_message("    Error: Failed to extract image data for filter " + filter_name)
			continue
		
		# Get dimensions
		var width = int(header.get("NAXIS1", 0))
		var height = int(header.get("NAXIS2", 0))
		
		if width == 0 or height == 0:
			log_message("    Error: Invalid dimensions for filter " + filter_name)
			continue
		
		# Create resource with raw image data
		var resource = DirectImageResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		resource.image_data = image_data
		resource.width = width
		resource.height = height
		resource.header_info = header
		
		# Extract WCS information
		var wcs_info = {}
		for key in header:
			if key.begins_with("CD") or key.begins_with("CRPIX") or key.begins_with("CRVAL") or key.begins_with("CTYPE"):
				wcs_info[key] = header[key]
		resource.wcs_info = wcs_info
		
		# Add metadata
		resource.metadata = {
			"source_file": fits_path,
			"processing_date": Time.get_datetime_string_from_system(),
			"filter": filter_name
		}
		
		# Check for segmentation map (for all filters, not just F200W)
		if hdu_index + 1 < fits_reader.get_info()["hdus"].size():
			# Try to determine if the next HDU is a segmentation map
			var next_header = fits_reader.get_header_info(hdu_index + 1)
			var is_segmap = false
			
			# Check if it's a segmentation map based on header info
			if next_header.has("EXTNAME") and next_header["EXTNAME"] == "SEG":
				is_segmap = true
			elif filter_name == "F200W": # Keep original behavior for F200W
				is_segmap = true
			
			if is_segmap:
				var segmap_data_array = fits_reader.get_image_data(hdu_index + 1)
				if segmap_data_array.size() > 0:
					resource.segmap_data = segmap_data_array
					log_message("    Created segmentation map data for " + filter_name)
		
		result[filter_name] = resource
		log_message("    Created direct image resource for filter: " + filter_name)
	
	return result

## Process direct images from a FITS file (legacy function for compatibility)
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Dictionary mapping filter names to resource paths
func preprocess_direct_images(object_id: String, fits_path: String, output_dir: String) -> Dictionary:
	log_message("  Processing direct images from: " + fits_path)
	var result = {}
	
	# Get direct image data using FitsHelper
	var direct_indices = fits_helper.get_directs(fits_path)
	if direct_indices.is_empty():
		log_message("    Error: Failed to extract direct image indices from " + fits_path)
		return result
	
	# Create a FITS reader to access the data
	var fits_reader = FITSReader.new()
	if not fits_reader.load_fits(fits_path):
		log_message("    Error: Failed to load FITS file: " + fits_path)
		return result
	
	# Process each filter
	for filter_name in direct_indices:
		var hdu_index = direct_indices[filter_name]['index']
		var header = fits_reader.get_header_info(hdu_index)
		var image_data = fits_reader.get_image_data_normalized(hdu_index)
		
		if image_data.size() == 0:
			log_message("    Error: Failed to extract image data for filter " + filter_name)
			continue
		
		# Get dimensions
		var width = int(header.get("NAXIS1", 0))
		var height = int(header.get("NAXIS2", 0))
		
		if width == 0 or height == 0:
			log_message("    Error: Invalid dimensions for filter " + filter_name)
			continue
		
		# Create resource with raw image data
		var resource = DirectImageResource.new()
		resource.object_id = object_id
		resource.filter_name = filter_name
		resource.image_data = image_data
		resource.width = width
		resource.height = height
		resource.header_info = header
		
		# Extract WCS information
		var wcs_info = {}
		for key in header:
			if key.begins_with("CD") or key.begins_with("CRPIX") or key.begins_with("CRVAL") or key.begins_with("CTYPE"):
				wcs_info[key] = header[key]
		resource.wcs_info = wcs_info
		
		# Add metadata
		resource.metadata = {
			"source_file": fits_path,
			"processing_date": Time.get_datetime_string_from_system(),
			"filter": filter_name
		}
		
		# Check for segmentation map (for all filters, not just F200W)
		if hdu_index + 1 < fits_reader.get_info()["hdus"].size():
			# Try to determine if the next HDU is a segmentation map
			var next_header = fits_reader.get_header_info(hdu_index + 1)
			var is_segmap = false
			
			# Check if it's a segmentation map based on header info
			if next_header.has("EXTNAME") and next_header["EXTNAME"] == "SEG":
				is_segmap = true
			elif filter_name == "F200W": # Keep original behavior for F200W
				is_segmap = true
			
			if is_segmap:
				var segmap_data_array = fits_reader.get_image_data(hdu_index + 1)
				if segmap_data_array.size() > 0:
					resource.segmap_data = segmap_data_array
					log_message("    Saved segmentation map data for " + filter_name)
		
		# Save resource
		var resource_path = output_dir + object_id + "_direct_" + filter_name + ".res"
		var save_result = ResourceSaver.save(resource, resource_path)
		if save_result != OK:
			log_message("    Error saving direct image resource: " + str(save_result))
			continue
		
		result[filter_name] = resource_path
		log_message("    Saved direct image for filter: " + filter_name)
	
	return result

## Process redshift data from a FITS file
##
## @param object_id The ID of the object
## @param fits_path The path to the FITS file
## @param output_dir The directory to save processed data to
## @return Path to the saved redshift resource
func preprocess_redshift(object_id: String, fits_path: String, output_dir: String) -> String:
	log_message("  Processing redshift data from: " + fits_path)
	
	# Get redshift data using FitsHelper
	var pz_data = fits_helper.get_pz(fits_path)
	if pz_data.size() < 2 or pz_data[0].size() == 0 or pz_data[1].size() == 0:
		log_message("    Error: Failed to extract redshift data from " + fits_path)
		return ""
	
	var z_grid = pz_data[0]
	var pdf = pz_data[1]
	
	# Calculate log10 of PDF
	var log_pdf = PackedFloat32Array()
	for p in pdf:
		if p <= 0: # Avoid log of zero or negative values
			log_pdf.append(-INF)
		else:
			log_pdf.append(fits_helper.log10(p))
	
	# Find peaks
	var peaks = fits_helper.peak_finding(log_pdf, 50)
	
	# Find best redshift (highest peak)
	var best_redshift = 0.0
	var max_pdf = - INF
	for peak in peaks:
		if peak["x"] < z_grid.size(): # Ensure index is valid
			var z = z_grid[peak["x"]]
			var p = peak["max"]
			if p > max_pdf:
				max_pdf = p
				best_redshift = z
	
	# Create a FITS reader to access header information
	var fits_reader = FITSReader.new()
	var header_info = {}
	if fits_reader.load_fits(fits_path):
		header_info = fits_reader.get_header_info(0)
	
	# Create resource
	var resource = RedshiftResource.new()
	resource.object_id = object_id
	resource.z_grid = z_grid
	resource.pdf = pdf
	resource.log_pdf = log_pdf
	resource.peaks.append(peaks) # [peaks[0]['max']]
	resource.best_redshift = best_redshift
	resource.header_info = header_info
	
	# Add metadata
	resource.metadata = {
		"source_file": fits_path,
		"processing_date": Time.get_datetime_string_from_system(),
		"peak_count": peaks.size()
	}
	
	# Save resource
	var resource_path = output_dir + object_id + "_redshift.res"
	var save_result = ResourceSaver.save(resource, resource_path)
	if save_result != OK:
		log_message("    Error saving redshift resource: " + str(save_result))
		return ""
	
	log_message("    Saved redshift data with best z = " + str(best_redshift))
	return resource_path

# This function has been removed as we now store raw data directly in resources

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
		if fits_reader.load_fits(direct_path):
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
				if fits_reader.load_fits(file_path):
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
	
	# Ensure the directory exists
	if not DirAccess.dir_exists_absolute(output_dir):
		var dir_result = DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_result != OK:
			log_message("Error creating directory for metadata file: " + str(dir_result))
			return
	
	var file_path = output_dir + "object_metadata.txt"
	metadata_file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if metadata_file:
		metadata_file.store_line("object_id\tobject_name\tband_count\tobservation_date\tredshift")
		log_message("Initialized metadata file at " + file_path)
	else:
		log_message("Error: Could not create metadata file at " + file_path)

## Write object metadata to the metadata file
##
## @param manifest The object manifest containing metadata
func write_object_metadata(manifest: ObjectManifest) -> void:
	if not metadata_file:
		log_message("Error: Metadata file not initialized")
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
	
	# Ensure the directory exists
	if not DirAccess.dir_exists_absolute(output_dir):
		var dir_result = DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_result != OK:
			print("Error creating directory for log file: " + str(dir_result))
			return
	
	var file_path = output_dir + "preprocess_log.txt"
	log_file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if log_file:
		var datetime = Time.get_datetime_dict_from_system()
		var date_str = "%04d-%02d-%02d %02d:%02d:%02d" % [
			datetime["year"], datetime["month"], datetime["day"],
			datetime["hour"], datetime["minute"], datetime["second"]
		]
		log_file.store_line("Pre-processing started at " + date_str)
		print("Initialized log file at " + file_path)
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

# These functions are no longer needed since we create resources directly in memory
