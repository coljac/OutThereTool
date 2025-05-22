extends Node
class_name AssetHelper

var c_log10 = log(10)

var manifest: Resource

func set_object(objid) -> bool:
	manifest = load("./processed/" + objid + "_manifest.tres")
	if manifest:
		print("2D spectra by filter: ", manifest['spectrum_2d_paths'])
		print("2D spectra by PA: ", manifest['spectrum_2d_paths_by_pa'])
		return true
	else:
		return false

func get_pz() -> Resource:
	if manifest:
		var pz = load(manifest.redshift_path)
		return pz
	return null


func get_1d_spectrum(microns: bool = false) -> Dictionary: # Array[Vector2]:
	if not manifest:
		return {}
	
	var oneds = manifest.spectrum_1d_paths
	var res = {}
	for filt in oneds:
		var spec = load(oneds[filt]) as Spectrum1DResource
		if not spec:
			continue
		var waves = spec.wavelengths
		var fluxes = spec.fluxes
		var errors = spec.errors
		var bestfit = spec.bestfit
		
		var max = Array(fluxes).max()
		# if microns:
			# waves = Array(waves).map(func d(x): return x / 10000)
			# waves = PackedFloat32Array(waves)

		res[filt] = {
			"fluxes": zip_p32([waves, fluxes]),
			"err": errors,
			"bestfit": zip_p32([waves, spec.bestfit]),
			"cont": zip_p32([waves, spec.continuum]),
			"contam": zip_p32([waves, spec.contam]),
			"flat": spec.flat,
			"max": max
		}
	
	return res

func get_directs() -> Dictionary:
	if not manifest:
		return {}
	var res = {}
	for filt in manifest.direct_image_paths:
		var direct = load(manifest.direct_image_paths[filt])
		res[filt] = direct
	return res


func get_2d_spectra() -> Dictionary:
	if not manifest:
		return {}
	var res = {}
	for pa in manifest.spectrum_2d_paths_by_pa:
		if pa not in res:
			res[pa] = {}
		for filt in manifest.spectrum_2d_paths_by_pa[pa]:
			res[pa][filt] = load(manifest.spectrum_2d_paths_by_pa[pa][filt])
	return res


func load_2ds():
	if manifest:
		print("2D spectra by filter: ", manifest['spectrum_2d_paths'])
		print("2D spectra by PA: ", manifest['spectrum_2d_paths_by_pa'])

		
func get_2d_spectra_by_pa(pa: String) -> Dictionary:
	if not manifest or not "spectrum_2d_paths_by_pa" in manifest:
		return {}
	
	if not pa in manifest.spectrum_2d_paths_by_pa:
		return {}
	
	return manifest.spectrum_2d_paths_by_pa[pa]

func get_available_position_angles() -> Array:
	if not manifest or not "spectrum_2d_paths_by_pa" in manifest:
		return []
	
	return manifest.spectrum_2d_paths_by_pa.keys()

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
