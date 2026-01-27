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
# PLY is a widely used format for 3D data with a self-describing header
# Format: ASCII text with header describing data structure, followed by vertex data
# @param file: Open file handle for reading
# @return: LoadResult with parsed point cloud data
func _load_ply(file: FileAccess) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var vertex_count = 0
	var in_header = true
	# Maps property names to their column index in the data
	var prop_index = {}
	var prop_types = {}
	var prop_count = 0

	# Parse PLY header section
	while in_header:
		var line = file.get_line().strip_edges()

		if line == "end_header":
			in_header = false
		elif line.begins_with("element vertex"):
			var parts = line.split(" ")
			if parts.size() >= 3:
				vertex_count = parts[2].to_int()
		elif line.begins_with("property"):
			# Format: "property <type> <name>"
			var parts = line.split(" ")
			if parts.size() >= 3:
				var prop_type = parts[1]  # e.g. "float", "uchar"
				var prop_name = parts[2]  # e.g. "x", "red"
				prop_index[prop_name] = prop_count
				prop_types[prop_name] = prop_type
				prop_count += 1

	# Resolve column indices for position and color properties
	var ix = prop_index.get("x", -1)
	var iy = prop_index.get("y", -1)
	var iz = prop_index.get("z", -1)
	var ir = prop_index.get("red", -1)
	var ig = prop_index.get("green", -1)
	var ib = prop_index.get("blue", -1)
	var has_position = ix >= 0 and iy >= 0 and iz >= 0
	var has_color = ir >= 0 and ig >= 0 and ib >= 0
	# Determine if colors need normalization (uchar 0-255 vs float 0-1)
	var color_is_uchar = has_color and prop_types.get("red", "") == "uchar"

	vertices.resize(vertex_count)
	colors.resize(vertex_count)

	# Parse vertex data section
	for i in range(vertex_count):
		if file.eof_reached():
			break

		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue

		var values = line.split(" ")
		if not has_position or values.size() <= ix or values.size() <= iy or values.size() <= iz:
			continue

		vertices[i] = Vector3(
			values[ix].to_float(),
			values[iy].to_float(),
			values[iz].to_float()
		)

		if has_color and values.size() > ir and values.size() > ig and values.size() > ib:
			var r = values[ir].to_float()
			var g = values[ig].to_float()
			var b = values[ib].to_float()
			if color_is_uchar:
				colors[i] = Color(r / 255.0, g / 255.0, b / 255.0)
			else:
				colors[i] = Color(r, g, b)
		else:
			colors[i] = Color.WHITE

		# Yield control every 1000 points to prevent UI freezing
		if i % 1000 == 0:
			progress_updated.emit(i, vertex_count)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, vertices, colors)

# Loads binary SPLAT format files (3D Gaussian Splat data)
# SPLAT format stores complete 3D Gaussian information in binary form
# Each splat contains: position, scale, rotation, color, and opacity
# Format: Binary data with 56 bytes per splat (14 floats x 4 bytes each)
# @param file: Open file handle for reading
# @return: LoadResult with parsed splat data
func _load_splat(file: FileAccess) -> LoadResult:
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	var bytes_per_splat = 56  # 14 floats * 4 bytes each

	# Read entire file into memory at once instead of 14 individual get_float() calls per point
	var buffer = file.get_buffer(file.get_length())
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
