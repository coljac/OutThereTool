extends Node
class_name AssetLoader
var c_log10 = log(10)

var manifest: Resource

func set_object(objid):
	manifest = load("./processed/" + objid + "_manifest.tres")
	if manifest:
		print(manifest['spectrum_2d_paths'])

func load_2ds():
	if manifest:
		print(manifest['spectrum_2d_paths'])

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
