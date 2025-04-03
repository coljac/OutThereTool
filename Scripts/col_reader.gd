class_name CFITSReader
extends RefCounted

# FITS block size (bytes)
const FITS_BLOCK_SIZE = 2880

# Supported BITPIX values and their byte sizes
const BITPIX_TYPES = {
	8: 1,     # 8-bit unsigned byte
	16: 2,    # 16-bit signed integer  
	32: 4,    # 32-bit signed integer
	64: 8,    # 64-bit signed integer
	-32: 4,   # 32-bit IEEE floating point
	-64: 8    # 64-bit IEEE floating point
}

var _file_path: String
var _file: FileAccess
var _hdus = []
var _current_hdu_index = 0

# Initialize with a file path
func _init(file_path: String):
	_file_path = file_path
	_read_fits_file()

# Read the entire FITS file structure
func _read_fits_file() -> void:
	_file = FileAccess.open(_file_path, FileAccess.READ)
	if _file == null:
		push_error("Could not open FITS file: " + _file_path)
		return
	
	# First read the primary HDU
	var primary_hdu = _read_hdu(true)
	if primary_hdu:
		_hdus.append(primary_hdu)
	
	# Read any extension HDUs
	while not _file.eof_reached():
		var extension_hdu = _read_hdu(false)
		if extension_hdu:
			_hdus.append(extension_hdu)
	
	_file.close()

# Read a single HDU (header and data)
func _read_hdu(is_primary: bool) -> Dictionary:
	var header = _read_header()
	if header.is_empty():
		return {}
	
	var data = _read_data(header, is_primary)
	
	return {
		"header": header,
		"data": data,
		"is_primary": is_primary
	}

# Read the header of an HDU
func _read_header() -> Dictionary:
	var header = {}
	var end_found = false
	
	while not end_found and not _file.eof_reached():
		# Read a complete header block
		var block = _file.get_buffer(FITS_BLOCK_SIZE)
		if block.size() < FITS_BLOCK_SIZE:
			# We might still have a valid but incomplete header, so continue processing
			# what we have rather than just returning an empty dictionary
			if block.size() == 0:
				break  # Truly at EOF
			# Otherwise process the partial block
		
		# Process 80-byte header cards in this block
		for i in range(0, FITS_BLOCK_SIZE, 80):
			if i + 80 > block.size():
				break  # Don't go beyond the buffer
				
			var card = block.slice(i, i + 80).get_string_from_ascii()
			
			# Extract keyword name (first 8 characters)
			var keyword = card.substr(0, 8).strip_edges()
			
			# Check for END keyword
			if keyword == "END":
				end_found = true
				break
			
			if keyword.is_empty():
				# Skip blank keywords, but still record for COMMENT if needed
				header[" " + str(i)] = {
					"value": null,
					"comment": card.substr(8).strip_edges()
				}
				continue
			
			# Check if this is a value card
			if card.length() > 10 and card[8] == '=' and card[9] == ' ':
				var value_str = card.substr(10).strip_edges()
				var comment = ""
				
				# Split value and comment if there's a / that's not inside quotes
				var in_quotes = false
				var slash_pos = -1
				
				for j in range(0, value_str.length()):
					if value_str[j] == "'":
						in_quotes = !in_quotes
					elif value_str[j] == '/' and not in_quotes:
						slash_pos = j
						break
				
				if slash_pos != -1:
					comment = value_str.substr(slash_pos + 1).strip_edges()
					value_str = value_str.substr(0, slash_pos).strip_edges()
				
				# Parse the value based on its format
				var value = _parse_fits_value(value_str)
				
				header[keyword] = {
					"value": value,
					"comment": comment
				}
			else:
				# This is a comment-only keyword (HISTORY, COMMENT, etc.)
				header[keyword] = {
					"value": null,
					"comment": card.substr(8).strip_edges()
				}
		
		# If we found the END keyword, exit after processing this block
		if end_found:
			break
	
	# If we reached EOF without finding END, the header may still be valid
	return header
	
func _read_headdesadfsdfr() -> Dictionary:
	var header = {}
	var header_block = ""
	var end_found = false
	
	while not end_found:
		# Read a complete header block
		var block = _file.get_buffer(FITS_BLOCK_SIZE)
		if block.size() < FITS_BLOCK_SIZE:
			push_error("Unexpected end of file while reading header")
			return header
		
		header_block += block.get_string_from_ascii()
		
		# Parse the header block for keywords
		for i in range(0, FITS_BLOCK_SIZE, 80):
			var card = header_block.substr(i, 80)
			if card.begins_with("END"):
				end_found = true
				break
			
			# Extract keyword name
			var keyword = card.substr(0, 8).strip_edges()
			if keyword.is_empty():
				continue  # Skip blank keywords
			
			# Check if this is a value card
			if card.length() > 10 and card[8] == '=' and card[9] == ' ':
				var value_str = card.substr(10).strip_edges()
				var comment = ""
				
				# Split value and comment if there's a / that's not inside quotes
				var in_quotes = false
				var slash_pos = -1
				
				for j in range(0, value_str.length()):
					if value_str[j] == "'":
						in_quotes = !in_quotes
					elif value_str[j] == '/' and not in_quotes:
						slash_pos = j
						break
				
				if slash_pos != -1:
					comment = value_str.substr(slash_pos + 1).strip_edges()
					value_str = value_str.substr(0, slash_pos).strip_edges()
				
				# Parse the value based on its format
				var value = _parse_fits_value(value_str)
				
				header[keyword] = {
					"value": value,
					"comment": comment
				}
			else:
				# This is a comment-only keyword (HISTORY, COMMENT, etc.)
				header[keyword] = {
					"value": null,
					"comment": card.substr(8).strip_edges()
				}
	
	return header

# Parse a FITS keyword value string to appropriate type
func _parse_fits_value(value_str: String):
	if value_str.is_empty():
		return null
	
	# String value (surrounded by single quotes)
	if value_str[0] == "'":
		var end_quote = value_str.rfind("'")
		if end_quote > 0:
			# Handle '' as escaping for ' within strings
			var str_value = value_str.substr(1, end_quote - 1)
			str_value = str_value.replace("''", "'")
			return str_value
		return value_str
	
	# Logical value (T/F)
	if value_str == "T":
		return true
	if value_str == "F":
		return false
	
	# Try numeric formats
	# Integer
	if value_str.is_valid_int():
		return value_str.to_int()
	
	# Float
	if value_str.is_valid_float():
		return value_str.to_float()
	
	# Default to string if no other format matches
	return value_str

# Read the data part of an HDU
func _read_data(header: Dictionary, is_primary: bool) -> Variant:
	# Check if there's data
	var naxis = 0
	if "NAXIS" in header:
		naxis = header["NAXIS"]["value"]
	
	if naxis == 0:
		return null  # No data array
	
	# Get data dimensions
	var dimensions = []
	for i in range(1, naxis + 1):
		var axis_key = "NAXIS" + str(i)
		if axis_key in header:
			dimensions.append(header[axis_key]["value"])
	
	# Get BITPIX
	var bitpix = header["BITPIX"]["value"]
	if not bitpix in BITPIX_TYPES:
		push_error("Unsupported BITPIX value: " + str(bitpix))
		return null
	
	# Calculate total data size
	var bytes_per_pixel = BITPIX_TYPES[bitpix]
	var total_pixels = 1
	for dim in dimensions:
		total_pixels *= dim
	
	var data_size = total_pixels * bytes_per_pixel
	
	# Read the data bytes
	var data_bytes = _file.get_buffer(data_size)
	
	# Handle padding to next FITS block boundary
	var padding = FITS_BLOCK_SIZE - (data_size % FITS_BLOCK_SIZE)
	if padding < FITS_BLOCK_SIZE:
		_file.get_buffer(padding)
	
	# Convert bytes to appropriate data type
	return _bytes_to_data(data_bytes, bitpix, dimensions)

# Convert raw bytes to appropriate data structure
func _bytes_to_data(data_bytes: PackedByteArray, bitpix: int, dimensions: Array) -> Variant:
	# For image data, let's convert to Texture2D if it's 2D
	if dimensions.size() == 2:
		return _create_texture_from_bytes(data_bytes, bitpix, dimensions[0], dimensions[1])
	
	# For other data, return a raw array
	var data_array = _bytes_to_array(data_bytes, bitpix)
	return data_array

# Convert bytes to a simple array based on BITPIX
func _bytes_to_array(data_bytes: PackedByteArray, bitpix: int) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(data_bytes.size() / BITPIX_TYPES[bitpix])
	
	var idx = 0
	var byte_size = BITPIX_TYPES[bitpix]
	
	# Loop through all elements
	for i in range(0, data_bytes.size(), byte_size):
		var value = 0.0
		
		# Handle different bit depths
		if bitpix == 8:
			value = data_bytes[i]
		elif bitpix == 16:
			value = _bytes_to_int16(data_bytes, i)
		elif bitpix == 32:
			value = _bytes_to_int32(data_bytes, i)
		elif bitpix == 64:
			value = _bytes_to_int64(data_bytes, i)
		elif bitpix == -32:
			value = _bytes_to_float32(data_bytes, i)
		elif bitpix == -64:
			value = _bytes_to_float64(data_bytes, i)
		
		result[idx] = value
		idx += 1
	
	return result

# Create a Texture2D from image data
func _create_texture_from_bytes(data_bytes: PackedByteArray, bitpix: int, width: int, height: int) -> Texture2D:
	var image = Image.create(width, height, false, Image.FORMAT_RF)
	
	# Convert the data to a format suitable for Image
	var data_array = _bytes_to_array(data_bytes, bitpix)
	
	# Find data range to normalize values
	var min_val = data_array[0]
	var max_val = data_array[0]
	
	for val in data_array:
		min_val = min(min_val, val)
		max_val = max(max_val, val)
	
	# Normalize and set pixels
	var range_val = max_val - min_val
	if range_val == 0:
		range_val = 1  # Avoid division by zero
	
	for y in range(height):
		for x in range(width):
			var idx = y * width + x
			var normalized = (data_array[idx] - min_val) / range_val
			image.set_pixel(x, y, Color(normalized, normalized, normalized, 1.0))
	
	var texture = ImageTexture.create_from_image(image)
	return texture

# Byte conversion helpers for big-endian data
func _bytes_to_int16(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 8) | bytes[offset + 1]

func _bytes_to_int32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | bytes[offset+3]

func _bytes_to_int64(bytes: PackedByteArray, offset: int) -> int:
	var high = _bytes_to_int32(bytes, offset)
	var low = _bytes_to_int32(bytes, offset + 4)
	return (high << 32) | low

func _bytes_to_float32(bytes: PackedByteArray, offset: int) -> float:
	# This is a simplistic implementation
	# A full implementation would need to decode IEEE 754 format
	var bits = _bytes_to_int32(bytes, offset)
	var f = 0.0
	var sign = 1
	if (bits & 0x80000000) != 0:
		sign = -1
	var exponent = ((bits >> 23) & 0xFF) - 127
	var mantissa = bits & 0x7FFFFF
	if exponent == -127:
		if mantissa == 0:
			return 0.0 * sign
		exponent = -126
		mantissa /= 0x800000
	else:
		mantissa = 1.0 + mantissa / 0x800000
	return sign * mantissa * pow(2, exponent)

func _bytes_to_float64(bytes: PackedByteArray, offset: int) -> float:
	# A simplistic implementation - actual IEEE 754 double format is complex
	# For complete accuracy, you'd need a full IEEE 754 decoder
	# This is a rough approximation
	var bits_high = _bytes_to_int32(bytes, offset)
	var bits_low = _bytes_to_int32(bytes, offset + 4)
	
	var sign = 1
	if (bits_high & 0x80000000) != 0:
		sign = -1
	
	var exponent = ((bits_high >> 20) & 0x7FF) - 1023
	var mantissa = (bits_high & 0xFFFFF) * 4294967296.0 + bits_low
	
	if exponent == -1023:
		if mantissa == 0:
			return 0.0 * sign
		exponent = -1022
	else:
		mantissa += 4503599627370496.0  # 2^52
	
	mantissa /= 4503599627370496.0
	return sign * mantissa * pow(2, exponent)

# Public methods to access FITS data
func get_num_hdus() -> int:
	return _hdus.size()

func get_header(hdu_index: int = 0) -> Dictionary:
	if hdu_index >= 0 and hdu_index < _hdus.size():
		return _hdus[hdu_index]["header"]
	return {}

func get_data(hdu_index: int = 0) -> Variant:
	if hdu_index >= 0 and hdu_index < _hdus.size():
		return _hdus[hdu_index]["data"]
	return null

func get_data_as_texture(hdu_index: int = 0) -> Texture2D:
	var data = get_data(hdu_index)
	if data is Texture2D:
		return data
	return null
