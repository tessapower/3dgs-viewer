# SplatLoader - A utility class for loading various 3D point cloud file formats
# Supports PLY (Stanford Polygon Library), SPLAT (3D Gaussian Splat), and XYZ formats
# Provides asynchronous loading to prevent UI freezing during large file operations
extends RefCounted
class_name SplatLoader

signal progress_updated(loaded: int, total: int)

# Container class for file loading results
# Carries packed vertex/color arrays directly to avoid per-point object overhead
class LoadResult:
	var success: bool
	var vertices: PackedVector3Array
	var colors: PackedColorArray
	var error: String

	func _init(is_success: bool = false, verts: PackedVector3Array = PackedVector3Array(), cols: PackedColorArray = PackedColorArray(), error_msg: String = ""):
		success = is_success
		vertices = verts
		colors = cols
		error = error_msg

	func point_count() -> int:
		return vertices.size()

# Main entry point for loading any supported point cloud file format
# Automatically detects file format from extension and routes to appropriate loader
# @param path: File system path to the point cloud file
# @return: LoadResult containing success status and point data or error message
func load_file(path: String) -> LoadResult:
	# Attempt to open the file for reading
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return LoadResult.new(false, PackedVector3Array(), PackedColorArray(), "Could not open file: " + path)

	# Determine file format from extension
	var extension = path.get_extension().to_lower()
	var result: LoadResult

	# Route to appropriate loader based on file extension
	match extension:
		"ply":
			# Stanford PLY format - commonly used for 3D meshes and point clouds
			result = await _load_ply(file)
		"splat":
			# Binary 3D Gaussian Splat format - contains full splat data
			result = await _load_splat(file)
		"xyz":
			# Simple XYZ coordinate format - plain text with position and optional color
			result = await _load_xyz(file)
		_:
			# Unsupported file format
			result = LoadResult.new(false, PackedVector3Array(), PackedColorArray(), "Unsupported file format: " + extension)

	# Clean up file handle
	file.close()
	return result

# Loads PLY (Stanford Polygon Library) format files
# Supports both ASCII and binary_little_endian formats
# @param file: Open file handle for reading
# @return: LoadResult with parsed point cloud data
func _load_ply(file: FileAccess) -> LoadResult:
	var vertex_count = 0
	var in_header = true
	var ply_format = "ascii"
	var current_element = ""
	# Only vertex properties, in declaration order
	var properties = []  # Array of {name: String, type: String}

	# Parse PLY header section (always ASCII)
	while in_header:
		var line = file.get_line().strip_edges()

		if line == "end_header":
			in_header = false
		elif line.begins_with("format"):
			if "binary_little_endian" in line:
				ply_format = "binary_little_endian"
			elif "binary_big_endian" in line:
				ply_format = "binary_big_endian"
		elif line.begins_with("element"):
			var parts = line.split(" ")
			current_element = parts[1] if parts.size() >= 2 else ""
			if current_element == "vertex" and parts.size() >= 3:
				vertex_count = parts[2].to_int()
		elif line.begins_with("property") and current_element == "vertex":
			var parts = line.split(" ")
			# Skip "property list" types (variable-length, used for face indices)
			if parts.size() >= 3 and parts[1] != "list":
				properties.append({"type": parts[1], "name": parts[2]})

	# Build property lookup: name -> {index, type, byte_offset}
	var prop_map = {}
	var byte_stride = 0
	for i in range(properties.size()):
		var prop = properties[i]
		prop_map[prop.name] = {"index": i, "type": prop.type, "byte_offset": byte_stride}
		byte_stride += _ply_type_size(prop.type)

	var has_position = prop_map.has("x") and prop_map.has("y") and prop_map.has("z")
	if not has_position:
		return LoadResult.new(false, PackedVector3Array(), PackedColorArray(), "PLY file missing x/y/z properties")

	# 3DGS PLY files use f_dc_0/f_dc_1/f_dc_2 (spherical harmonics) instead of red/green/blue
	var has_color = prop_map.has("red") and prop_map.has("green") and prop_map.has("blue")
	var has_sh_color = prop_map.has("f_dc_0") and prop_map.has("f_dc_1") and prop_map.has("f_dc_2")
	var color_is_uchar = has_color and prop_map["red"].type == "uchar"

	if ply_format == "binary_big_endian":
		return LoadResult.new(false, PackedVector3Array(), PackedColorArray(), "Binary big-endian PLY not yet supported")
	elif ply_format == "binary_little_endian":
		return await _load_ply_binary(file, vertex_count, prop_map, byte_stride, has_color, has_sh_color, color_is_uchar)
	else:
		return await _load_ply_ascii(file, vertex_count, prop_map, has_color, has_sh_color, color_is_uchar)

# Returns byte size for a PLY property type
func _ply_type_size(type: String) -> int:
	match type:
		"float", "float32", "int", "int32", "uint", "uint32":
			return 4
		"double", "float64", "int64", "uint64":
			return 8
		"short", "int16", "uint16", "ushort":
			return 2
		"char", "int8", "uchar", "uint8":
			return 1
		_:
			return 4  # Default assumption

# Sigmoid function for converting SH coefficients to color values
func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))

# Reads a value from a binary buffer based on PLY property type
func _ply_read_value(buffer: PackedByteArray, offset: int, type: String) -> float:
	match type:
		"float", "float32":
			return buffer.decode_float(offset)
		"double", "float64":
			return buffer.decode_double(offset)
		"uchar", "uint8":
			return float(buffer[offset])
		"char", "int8":
			return float(buffer.decode_s8(offset))
		"short", "int16":
			return float(buffer.decode_s16(offset))
		"ushort", "uint16":
			return float(buffer.decode_u16(offset))
		"int", "int32":
			return float(buffer.decode_s32(offset))
		"uint", "uint32":
			return float(buffer.decode_u32(offset))
		_:
			return buffer.decode_float(offset)

func _load_ply_binary(file: FileAccess, vertex_count: int, prop_map: Dictionary, byte_stride: int, has_color: bool, has_sh_color: bool, color_is_uchar: bool) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	vertices.resize(vertex_count)
	colors.resize(vertex_count)

	# Read all vertex data at once
	var buffer = file.get_buffer(vertex_count * byte_stride)
	var offset_x = prop_map["x"].byte_offset
	var type_x = prop_map["x"].type
	var offset_y = prop_map["y"].byte_offset
	var type_y = prop_map["y"].type
	var offset_z = prop_map["z"].byte_offset
	var type_z = prop_map["z"].type

	# Set up color property offsets
	var offset_red = 0
	var type_red = ""
	var offset_green = 0
	var type_green = ""
	var offset_blue = 0
	var type_blue = ""
	if has_color:
		offset_red = prop_map["red"].byte_offset
		type_red = prop_map["red"].type
		offset_green = prop_map["green"].byte_offset
		type_green = prop_map["green"].type
		offset_blue = prop_map["blue"].byte_offset
		type_blue = prop_map["blue"].type
	elif has_sh_color:
		# 3DGS PLY files store color as spherical harmonics DC coefficients
		offset_red = prop_map["f_dc_0"].byte_offset
		type_red = prop_map["f_dc_0"].type
		offset_green = prop_map["f_dc_1"].byte_offset
		type_green = prop_map["f_dc_1"].type
		offset_blue = prop_map["f_dc_2"].byte_offset
		type_blue = prop_map["f_dc_2"].type

	# SH DC to RGB conversion constant: 0.5 + SH_C0 * val, where SH_C0 = 0.28209479
	var sh_c0 = 0.28209479

	for i in range(vertex_count):
		var base = i * byte_stride

		vertices[i] = Vector3(
			_ply_read_value(buffer, base + offset_x, type_x),
			_ply_read_value(buffer, base + offset_y, type_y),
			_ply_read_value(buffer, base + offset_z, type_z)
		)

		if has_color:
			var red = _ply_read_value(buffer, base + offset_red, type_red)
			var green = _ply_read_value(buffer, base + offset_green, type_green)
			var blue = _ply_read_value(buffer, base + offset_blue, type_blue)
			if color_is_uchar:
				colors[i] = Color(red / 255.0, green / 255.0, blue / 255.0)
			else:
				colors[i] = Color(red, green, blue)
		elif has_sh_color:
			# Convert SH DC coefficients to RGB using sigmoid(SH_C0 * val + 0.5)
			var sh_r = _ply_read_value(buffer, base + offset_red, type_red)
			var sh_g = _ply_read_value(buffer, base + offset_green, type_green)
			var sh_b = _ply_read_value(buffer, base + offset_blue, type_blue)
			colors[i] = Color(
				_sigmoid(sh_c0 * sh_r + 0.5),
				_sigmoid(sh_c0 * sh_g + 0.5),
				_sigmoid(sh_c0 * sh_b + 0.5)
			)
		else:
			colors[i] = Color.WHITE

		# Yield every 10000 points to keep UI responsive
		if i % 10000 == 0 and i > 0:
			progress_updated.emit(i, vertex_count)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, vertices, colors)

func _load_ply_ascii(file: FileAccess, vertex_count: int, prop_map: Dictionary, has_color: bool, has_sh_color: bool, color_is_uchar: bool) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	vertices.resize(vertex_count)
	colors.resize(vertex_count)

	var ix = prop_map["x"].index
	var iy = prop_map["y"].index
	var iz = prop_map["z"].index
	var ir = -1
	var ig = -1
	var ib = -1
	if has_color:
		ir = prop_map["red"].index
		ig = prop_map["green"].index
		ib = prop_map["blue"].index
	elif has_sh_color:
		ir = prop_map["f_dc_0"].index
		ig = prop_map["f_dc_1"].index
		ib = prop_map["f_dc_2"].index

	var sh_c0 = 0.28209479

	for i in range(vertex_count):
		if file.eof_reached():
			break

		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue

		var values = line.split(" ")

		vertices[i] = Vector3(
			values[ix].to_float(),
			values[iy].to_float(),
			values[iz].to_float()
		)

		if has_color:
			var red = values[ir].to_float()
			var green = values[ig].to_float()
			var blue = values[ib].to_float()
			if color_is_uchar:
				colors[i] = Color(red / 255.0, green / 255.0, blue / 255.0)
			else:
				colors[i] = Color(red, green, blue)
		elif has_sh_color:
			colors[i] = Color(
				_sigmoid(sh_c0 * values[ir].to_float() + 0.5),
				_sigmoid(sh_c0 * values[ig].to_float() + 0.5),
				_sigmoid(sh_c0 * values[ib].to_float() + 0.5)
			)
		else:
			colors[i] = Color.WHITE

		# Yield control every 1000 points to prevent UI freezing
		if i % 1000 == 0:
			progress_updated.emit(i, vertex_count)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, vertices, colors)

# Loads binary SPLAT format files (3D Gaussian Splat data)
# Supports two formats:
#   Standard (32 bytes): position(3xf32) + scale(3xf32) + color(4xu8 RGBA) + rotation(4xu8)
#   Extended (56 bytes): position(3xf32) + scale(3xf32) + rotation(4xf32) + color(3xf32) + opacity(f32)
# @param file: Open file handle for reading
# @return: LoadResult with parsed splat data
func _load_splat(file: FileAccess) -> LoadResult:
	# Read entire file into memory at once
	var buffer = file.get_buffer(file.get_length())
	var file_size = buffer.size()

	# Auto-detect format based on file size divisibility
	var use_standard = (file_size % 32 == 0)
	var use_extended = (file_size % 56 == 0)

	# If both divide evenly, peek at the data to decide:
	# In standard format, bytes 24-27 are uint8 RGBA color values.
	# In extended format, bytes 24-27 are the start of a rotation quaternion float.
	# A quaternion float read as 4 uint8s would rarely sum to a plausible RGBA.
	if use_standard and use_extended and file_size >= 56:
		# Read byte 27 (alpha in standard format) — real RGBA alpha is usually > 0
		# Read bytes 24-27 as a float — if it's in [-1, 1], likely a quaternion component
		var test_float = buffer.decode_float(24)
		if test_float >= -1.0 and test_float <= 1.0:
			use_standard = false  # Looks like a quaternion, use extended format
		else:
			use_extended = false

	if use_standard:
		return await _load_splat_standard(buffer)
	elif use_extended:
		return await _load_splat_extended(buffer)
	else:
		return LoadResult.new(false, PackedVector3Array(), PackedColorArray(), "Invalid .splat file: size not divisible by 32 or 56")

# Standard 32-byte .splat format (antimatter15/splat and most 3DGS tools)
func _load_splat_standard(buffer: PackedByteArray) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var bytes_per_splat = 32

	var total_points: int = buffer.size() / bytes_per_splat
	vertices.resize(total_points)
	colors.resize(total_points)

	for i in range(total_points):
		var offset = i * bytes_per_splat

		# Position: 3 x float32 (bytes 0-11)
		# Negate Y to convert from Y-down (3DGS/COLMAP convention) to Y-up (Godot)
		vertices[i] = Vector3(
			buffer.decode_float(offset),
			-buffer.decode_float(offset + 4),
			buffer.decode_float(offset + 8)
		)

		# Color: 4 x uint8 RGBA (bytes 24-27)
		colors[i] = Color(
			buffer[offset + 24] / 255.0,
			buffer[offset + 25] / 255.0,
			buffer[offset + 26] / 255.0,
			buffer[offset + 27] / 255.0
		)

		# Yield every 10000 points to keep UI responsive
		if i % 10000 == 0 and i > 0:
			progress_updated.emit(i, total_points)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, vertices, colors)

# Extended 56-byte .splat format (all floats, used by this project's generator)
func _load_splat_extended(buffer: PackedByteArray) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var bytes_per_splat = 56

	var total_points: int = buffer.size() / bytes_per_splat
	vertices.resize(total_points)
	colors.resize(total_points)

	for i in range(total_points):
		var offset = i * bytes_per_splat

		# Negate Y to convert from Y-down (3DGS/COLMAP convention) to Y-up (Godot)
		vertices[i] = Vector3(
			buffer.decode_float(offset),
			-buffer.decode_float(offset + 4),
			buffer.decode_float(offset + 8)
		)

		var opacity = buffer.decode_float(offset + 52)
		colors[i] = Color(
			buffer.decode_float(offset + 40),
			buffer.decode_float(offset + 44),
			buffer.decode_float(offset + 48),
			opacity
		)

		# Yield every 10000 points to keep UI responsive
		if i % 10000 == 0 and i > 0:
			progress_updated.emit(i, total_points)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, vertices, colors)

# Loads simple XYZ format files (plain text coordinate data)
# XYZ format is a simple ASCII format with space-separated values per line
# Format: "x y z [r g b]" where coordinates are required and colors are optional
# @param file: Open file handle for reading
# @return: LoadResult with parsed point cloud data
func _load_xyz(file: FileAccess) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()

	# Read file line by line until end
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue

		var values = line.split(" ")
		if values.size() < 3:
			continue

		vertices.append(Vector3(
			values[0].to_float(),
			values[1].to_float(),
			values[2].to_float()
		))

		# Parse optional color data (supports both 0-1 and 0-255 ranges)
		if values.size() >= 6:
			var r = values[3].to_float()
			var g = values[4].to_float()
			var b = values[5].to_float()

			# Auto-detect color format and normalize to 0-1 range
			if r > 1.0 or g > 1.0 or b > 1.0:
				colors.append(Color(r / 255.0, g / 255.0, b / 255.0))
			else:
				colors.append(Color(r, g, b))
		else:
			colors.append(Color.WHITE)

		# Yield control every 1000 points to prevent UI freezing
		if vertices.size() % 1000 == 0:
			progress_updated.emit(vertices.size(), 0)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, vertices, colors)
