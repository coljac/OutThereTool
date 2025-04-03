extends Node
var c_log10 = log(10)

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
	fits_table.load_fits(object)
	var data = fits_table.get_table_data(2)
	var zs = data['data']['zgrid']
	var pzs = data['data']['pdf']
	return [zs, pzs]
	
func get_1d_spectrum(object: String, microns: bool = false) -> Array[Vector2]: 
	var fits_table = FITSReader.new()
	fits_table.load_fits(object)
	var data = fits_table.get_table_data(2)
	var waves = data['data']['wave']
	var fluxes = data['data']['flux']
	if microns:
		waves = Array(waves).map(func d(x): return x/10000)
		waves = PackedFloat32Array(waves)
	return zip_p32([waves, fluxes])

# How to get directs:
# For every header called REF
#   Filters += header['PUPIL']
#   keep the hdu index in a dictionary
# Might need PIXSCALE
# Image is in .data. Easy!
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

	return filter_dict

func get_hdu_by_name_ver(fits_file: FITSReader, name: String, ver: String = ""):
	for hdu in fits_file.get_info()['hdus']:
		if "name" in hdu and hdu['name']==name:
			var hdr = fits_file.get_header_info(hdu['index'])
			if ver != "":
				if "EXTVER" in hdr and hdr['EXTVER']==ver:
					return hdu
			else:
				return hdu

func get_2d_spectrum(object: String) -> int: 
	var fits_file = FITSReader.new()
	fits_file.load_fits(object)

	var f200w = get_hdu_by_name_ver(fits_file, "SCI", "F200W")

	return f200w['index']
	
func log10(f: float):
	return log(f)/c_log10
		
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
