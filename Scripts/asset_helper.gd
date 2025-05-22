extends Node
class_name AssetLoader
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

func get_pz() -> Array[PackedFloat32Array]:
	if manifest:
		var pz = load(manifest.redshift_path)
		return pz
	return PackedFloat32Array([])


func get_1d_spectrum(microns: bool = false) -> Dictionary: # Array[Vector2]:
	if not manifest:
		return {}
	
	var oneds = load(manifest.spectrum_1d_paths)
	var res = {}
	for filt in oneds:
		var spec = load(oneds[filt]) as Spectrum1DResource
		if not spec:
			continue
		var waves = spec.wavelengths
		var fluxes = spec.fluxes
		var errors = spec.errors
		var bestfit = spec.line

		# var bestfit = data['data']['line']
		# var cont = data['data']['cont']
		# var err = data['data']['err']
		# var flat = data['data']['flat'] if 'flat' in data['data'] else PackedFloat32Array([1.0] * fluxes.size())
		# var contam = data['data']['contam'] if 'contam' in data['data'] else PackedFloat32Array([0.0] * fluxes.size())
		
		# Check if pscale exists in the data columns
		var pscale = 1.0
		if 'pscale' in data['data']:
			pscale = data['data']['pscale']
		
		# Normalize the data
		# Convert to Array for processing
		var flux_arr = Array(fluxes)
		var err_arr = Array(err)
		var cont_arr = Array(cont)
		var bestfit_arr = Array(bestfit)
		var contam_arr = Array(contam)
		var flat_arr = Array(flat)
		
		# Apply normalization: (value/flat)/(1.0e-19)/pscale
		for i in range(flux_arr.size()):
			var ps = pscale
			# Avoid division by zero
			var flat_val = flat_arr[i] if flat_arr[i] != 0 else 1.0
		
			if not ps is float:
				ps = pscale[i]

			# Normalize flux and err with pscale
			flux_arr[i] = (flux_arr[i] / flat_val) / (1.0e-19) / ps
			err_arr[i] = (err_arr[i] / flat_val) / (1.0e-19) / ps
			
			# Normalize cont and bestfit (line)
			cont_arr[i] = (cont_arr[i] / flat_val) / (1.0e-19)
			bestfit_arr[i] = (bestfit_arr[i] / flat_val) / (1.0e-19)
			
			# Normalize contam with pscale
			contam_arr[i] = (contam_arr[i] / flat_val) / (1.0e-19) / ps
		
		# Convert back to PackedFloat32Array
		fluxes = PackedFloat32Array(flux_arr)
		err = PackedFloat32Array(err_arr)
		cont = PackedFloat32Array(cont_arr)
		bestfit = PackedFloat32Array(bestfit_arr)
		contam = PackedFloat32Array(contam_arr)
		var max = Array(fluxes).max()
		if microns:
			waves = Array(waves).map(func d(x): return x / 10000)
			waves = PackedFloat32Array(waves)
			
		res[filt] = {
			"fluxes": zip_p32([waves, fluxes]),
			"err": err,
			"bestfit": zip_p32([waves, bestfit]),
			"cont": zip_p32([waves, cont]),
			"contam": zip_p32([waves, contam]),
			"max": max
		}
	
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
