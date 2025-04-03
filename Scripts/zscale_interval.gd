class_name ZScaleInterval

var n_samples: int = 1000
var contrast: float = 0.25
var max_reject: float = 0.5
var min_npixels: int = 5
var krej: float = 2.5
var max_iterations: int = 5

func get_limits(image: Image) -> Array:
	# Get image data as array of floats
	image.lock()
	var width = image.get_width()
	var height = image.get_height()
	
	# Sample the image
	var samples = []
	var total_pixels = width * height
	var step = max(1, total_pixels / n_samples)
	
	for i in range(0, total_pixels, step):
		var x = i % width
		var y = i / width
		var color = image.get_pixel(x, y)
		# Assuming we're working with grayscale or just the R channel
		var value = color.r
		if is_finite(value):
			samples.append(value)
	
	image.unlock()
	
	# Sort samples
	samples.sort()
	
	# Calculate minimum required pixels
	var npix = samples.size()
	var ngoodpix = npix
	var minpix = max(min_npixels, int(npix * (1.0 - max_reject)))
	
	# Iterative fitting process
	var last_ngoodpix = npix + 1
	var iteration = 0
	var xvalues = range(npix)
	
	var slope = 0.0
	var intercept = 0.0
	var good_indices = range(npix)
	
	while ngoodpix > minpix and ngoodpix != last_ngoodpix and iteration < max_iterations:
		var good_samples = []
		for idx in good_indices:
			good_samples.append(samples[idx])
		
		# Fit a line
		var result = fit_line(good_indices, good_samples)
		slope = result[0]
		intercept = result[1]
		
		# Calculate residuals
		var residuals = []
		for i in range(good_indices.size()):
			var idx = good_indices[i]
			var resid = samples[idx] - (intercept + slope * idx)
			residuals.append(resid)
		
		# Calculate standard deviation
		var mean_resid = 0.0
		for resid in residuals:
			mean_resid += resid
		mean_resid /= residuals.size()
		
		var std_resid = 0.0
		for resid in residuals:
			std_resid += (resid - mean_resid) * (resid - mean_resid)
		std_resid = sqrt(std_resid / residuals.size())
		
		# Reject outliers
		last_ngoodpix = ngoodpix
		var threshold = krej * std_resid
		var new_good_indices = []
		
		for i in range(good_indices.size()):
			var idx = good_indices[i]
			if abs(residuals[i]) <= threshold:
				new_good_indices.append(idx)
		
		good_indices = new_good_indices
		ngoodpix = good_indices.size()
		iteration += 1
	
	# Final scaling
	var vmin = 0.0
	var vmax = 1.0
	
	if ngoodpix >= minpix:
		# Adjust slope based on contrast
		if slope != 0.0:
			if contrast > 0:
				slope = slope / contrast
			else:
				slope = 0.0
		
		# Calculate center point
		var center_idx = good_indices[good_indices.size() / 2]
		var center_value = samples[center_idx]
		
		# Compute final limits
		vmin = max(center_value + slope * (0 - center_idx), samples[0])
		vmax = min(center_value + slope * (npix - 1 - center_idx), samples[npix - 1])
	else:
		# Use simple min/max
		vmin = samples[0]
		vmax = samples[npix - 1]
	
	return [vmin, vmax]

func fit_line(indices, values):
	# Simple linear regression
	var n = indices.size()
	var sum_x = 0.0
	var sum_y = 0.0
	var sum_xy = 0.0
	var sum_xx = 0.0
	
	for i in range(n):
		sum_x += indices[i]
		sum_y += values[i]
		sum_xy += indices[i] * values[i]
		sum_xx += indices[i] * indices[i]
	
	var slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
	var intercept = (sum_y - slope * sum_x) / n
	
	return [slope, intercept]

func is_finite(value):
	return not (is_inf(value) or is_nan(value))

func apply_scale(image: Image, limits: Array) -> Image:
	var vmin = limits[0]
	var vmax = limits[1]
	var result = Image.new()
	result.copy_from(image)
	
	result.lock()
	var width = result.get_width()
	var height = result.get_height()
	
	for y in range(height):
		for x in range(width):
			var color = result.get_pixel(x, y)
			# Scale each channel
			color.r = clamp((color.r - vmin) / (vmax - vmin), 0.0, 1.0)
			color.g = clamp((color.g - vmin) / (vmax - vmin), 0.0, 1.0)
			color.b = clamp((color.b - vmin) / (vmax - vmin), 0.0, 1.0)
			result.set_pixel(x, y, color)
	
	result.unlock()
	return result
