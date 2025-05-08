extends Node
var c_log10 = log(10)

## Check if pre-processed data exists for an object
##
## @param object_id The ID of the object to check
## @param processed_data_path The path to the processed data directory
## @return True if pre-processed data exists, false otherwise
func check_preprocessed_data_exists(object_id: String, processed_data_path: String) -> bool:
	if not processed_data_path.ends_with("/"):
		processed_data_path += "/"
	
	var manifest_path = processed_data_path + object_id + "_manifest.tres"
	return FileAccess.file_exists(manifest_path)


func zip_p32(inputs: Array[PackedFloat32Array]) -> Array[Vector2]:
	var output = [] as Array[Vector2]
	for i in range(inputs[0].size()):
		output.append(Vector2(inputs[0][i], inputs[1][i]))
	return output
		

func zip_arr(inputs: Array[Array]) -> Array[Vector2]:
	var output = [] as Array[Vector2]
	for i in range(inputs[0].size()):
		output.append(Vector2(inputs[0][i], inputs[1][i]))
	return output


func get_pz(object: String) -> Array[PackedFloat32Array]:
	var fits_table = FITSReader.new()
	print_debug("Loading ", object)
	fits_table.load_fits(object)
	var data = fits_table.get_table_data(2)
	var zs = data['data']['zgrid']
	var pzs = data['data']['pdf']
	return [zs, pzs]


func _2d_to_1d(object: String, microns: bool = false) -> Dictionary: # Array[Vector2]: )
	var fits_data = FITSReader.new()
	fits_data.load_fits(object)
	var data = fits_data.get_image_data(0)
	print(data)
	print(fits_data.world_to_pixel(0, 0))
	if microns:
		return {}
	return {}


func get_segmap(object: String, filter: String):
	pass


func get_1d_spectrum(object: String, microns: bool = false) -> Dictionary: # Array[Vector2]:
	var fits_table = FITSReader.new()
	fits_table.load_fits(object)
	var res = {}
	for filt in ["F115W", "F150W", "F200W"]:
		var h = get_hdu_by_name_ver(fits_table, filt)
		if not h:
			continue
	
		var data = fits_table.get_table_data(h['index'])
		var waves = data['data']['wave']
		var fluxes = data['data']['flux']
		var err = data['data']['err']


		if microns:
			waves = Array(waves).map(func d(x): return x / 10000)
			waves = PackedFloat32Array(waves)
		res[filt] = {"fluxes": zip_p32([waves, fluxes]), "err": err} # zip_p32([waves, err])}
	# errors
	
	return res

# How to get directs:
# For every header called REF
#   Filters += header['PUPIL']
#   keep the hdu index in a dictionary
# Might need PIXSCALE
# Image is in .data. Easy!
#     if ref_filters_list[i]=='F200W': # show segmentation map for F200W band 
		# seg_im=  beam_hdul[hdul_ind+1].data
		# segmap_cmap=get_cmap(seg_im)
		# axs[i+1].imshow(seg_im,origin='lower',cmap=segmap_cmap)

func get_directs(object: String) -> Dictionary:
	var fits_file = FITSReader.new()
	var filter_dict = {}
	fits_file.load_fits(object)
	var hdus = fits_file.get_info()
	var filters: Array[String] = [] as Array[String]
	for h in hdus['hdus']:
		if "name" in h and h['name'] == "REF":
			var filt = fits_file.get_header_info(h['index'])['PUPIL']
			if filt not in filter_dict:
				filter_dict[filt] = h['index'] # fits_file.get_image_data(h['index'])
			if filt == "F200W":
				print(h['index'], " +1! ")

	return filter_dict

func get_hdu_by_name_ver(fits_file: FITSReader, name: String, ver: String = ""):
	for hdu in fits_file.get_info()['hdus']:
		if "name" in hdu and hdu['name'] == name:
			var hdr = fits_file.get_header_info(hdu['index'])
			if ver != "":
				if "EXTVER" in hdr and hdr['EXTVER'] == ver:
					return hdu
			else:
				return hdu

func get_2d_spectrum(object: String) -> Dictionary:
	var fits_file = FITSReader.new()
	fits_file.load_fits(object)
	var res = {}
	var f200w = get_hdu_by_name_ver(fits_file, "SCI", "F200W")
	if f200w:
		res['F200W'] = f200w['index']
	var f150w = get_hdu_by_name_ver(fits_file, "SCI", "F150W")
	if f150w:
		res['F150W'] = f150w['index']
	var f115w = get_hdu_by_name_ver(fits_file, "SCI", "F115W")
	if f115w:
		res['F115W'] = f115w['index']
	return res
	#return f200w['index']
	
func log10(f: float):
	return log(f) / c_log10
		
func peak_finding(data, window_size):
	"""
	Find values and positions of peaks in a given time series data.
	Return an array of dictionaries [{x=x1, max=max1}, {x=x2, max=max2},...,{x=xn, max=maxn}]

	data:        An array containing time series data
	window_size: Look for peaks in a box of "window_size" size
	"""
	# Create extended array with zeros at beginning and end
	var data_extended = []
	
	# Add leading zeros
	for i in range(window_size):
		data_extended.append(0)
	
	# Add original data
	for value in data:
		data_extended.append(value)
	
	# Add trailing zeros  
	for i in range(window_size):
		data_extended.append(0)
	
	var max_list = []
	
	for i in range(len(data_extended)):
		if i >= window_size and i < len(data_extended) - window_size:
			# Find max value in left window
			var max_left = 0
			for j in range(i - window_size, i + 1):
				max_left = max(max_left, data_extended[j])
			
			# Find max value in right window
			var max_right = 0
			for j in range(i, i + window_size + 1):
				max_right = max(max_right, data_extended[j])
			
			var check_value = data_extended[i] - ((max_left + max_right) / 2)
			
			if check_value >= 0:
				# In GDScript, let's return a dictionary instead of a tuple
				max_list.append({"x": i - window_size, "max": data[i - window_size]})
	
	return max_list
