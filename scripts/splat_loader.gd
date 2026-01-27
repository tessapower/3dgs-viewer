# SplatLoader - A utility class for loading various 3D point cloud file formats
# Supports PLY (Stanford Polygon Library), SPLAT (3D Gaussian Splat), and XYZ formats
# Provides asynchronous loading to prevent UI freezing during large file operations
extends RefCounted
class_name SplatLoader

signal progress_updated(loaded: int, total: int)

# Represents a single point in a 3D point cloud with all associated properties
# This class stores comprehensive data for 3D Gaussian Splat rendering
class SplatPoint:
	var position: Vector3    # 3D world position of the point
	var color: Color        # RGB color with alpha channel
	var normal: Vector3     # Surface normal vector (used for lighting calculations)
	var scale: Vector3      # Scale factors for each axis (for ellipsoid splats)
	var rotation: Quaternion # Orientation of the splat in 3D space
	var opacity: float      # Transparency value (0.0 = transparent, 1.0 = opaque)

	# Constructor with default values for basic point cloud visualization
	# @param pos: Initial position (defaults to origin)
	# @param col: Initial color (defaults to white)
	func _init(pos: Vector3 = Vector3.ZERO, col: Color = Color.WHITE):
		position = pos
		color = col
		normal = Vector3.UP         # Default normal pointing up
		scale = Vector3.ONE         # Default uniform scale
		rotation = Quaternion.IDENTITY  # Default no rotation
		opacity = 1.0               # Default fully opaque

# Container class for file loading results
# Provides success/failure status with either point data or error information
class LoadResult:
	var success: bool                # True if loading was successful
	var points: Array[SplatPoint]    # Array of loaded points (empty if failed)
	var error: String                # Error message (empty if successful)

	# Constructor for creating load results
	# @param is_success: Whether the operation succeeded
	# @param point_data: Array of successfully loaded points
	# @param error_msg: Error message if loading failed
	func _init(is_success: bool = false, point_data: Array[SplatPoint] = [], error_msg: String = ""):
		success = is_success
		points = point_data
		error = error_msg

# Main entry point for loading any supported point cloud file format
# Automatically detects file format from extension and routes to appropriate loader
# @param path: File system path to the point cloud file
# @return: LoadResult containing success status and point data or error message
func load_file(path: String) -> LoadResult:
	# Attempt to open the file for reading
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return LoadResult.new(false, [], "Could not open file: " + path)

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
			result = LoadResult.new(false, [], "Unsupported file format: " + extension)

	# Clean up file handle
	file.close()
	return result

# Loads PLY (Stanford Polygon Library) format files
# PLY is a widely used format for 3D data with a self-describing header
# Format: ASCII text with header describing data structure, followed by vertex data
# @param file: Open file handle for reading
# @return: LoadResult with parsed point cloud data
func _load_ply(file: FileAccess) -> LoadResult:
	var points: Array[SplatPoint] = []
	var vertex_count = 0        # Number of vertices declared in header
	var in_header = true        # Flag to track if we're still parsing header
	var properties = []         # List of property definitions from header

	# Parse PLY header section
	# The header defines the structure and count of data that follows
	while in_header:
		var line = file.get_line().strip_edges()

		if line == "end_header":
			# Header parsing complete, data section begins next
			in_header = false
		elif line.begins_with("element vertex"):
			# Extract vertex count from "element vertex N" line
			var parts = line.split(" ")
			if parts.size() >= 3:
				vertex_count = parts[2].to_int()
		elif line.begins_with("property"):
			# Store property definitions (x, y, z, red, green, blue, etc.)
			properties.append(line)

	# Parse vertex data section
	# Each line contains space-separated values for one vertex
	for i in range(vertex_count):
		if file.eof_reached():
			break

		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue  # Skip empty lines

		var values = line.split(" ")
		if values.size() < 3:
			continue  # Need at least X, Y, Z coordinates

		# Create new point with position data
		var point = SplatPoint.new()
		point.position = Vector3(
			values[0].to_float(),  # X coordinate
			values[1].to_float(),  # Y coordinate
			values[2].to_float()   # Z coordinate
		)

		# Parse color data if available (typically RGB values 0-255)
		if values.size() >= 6:
			point.color = Color(
				values[3].to_float() / 255.0,  # Red component (normalized to 0-1)
				values[4].to_float() / 255.0,  # Green component (normalized to 0-1)
				values[5].to_float() / 255.0   # Blue component (normalized to 0-1)
			)

		points.append(point)

		# Yield control every 1000 points to prevent UI freezing
		if i % 1000 == 0:
			progress_updated.emit(i, vertex_count)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, points)

# Loads binary SPLAT format files (3D Gaussian Splat data)
# SPLAT format stores complete 3D Gaussian information in binary form
# Each splat contains: position, scale, rotation, color, and opacity
# Format: Binary data with 56 bytes per splat (14 floats x 4 bytes each)
# @param file: Open file handle for reading
# @return: LoadResult with parsed splat data
func _load_splat(file: FileAccess) -> LoadResult:
	var points: Array[SplatPoint] = []
	var bytes_per_splat = 56  # 14 floats * 4 bytes each

	# Read entire file into memory at once instead of 14 individual get_float() calls per point
	var buffer = file.get_buffer(file.get_length())
	var total_points = buffer.size() / bytes_per_splat
	points.resize(total_points)

	for i in range(total_points):
		var offset = i * bytes_per_splat
		var point = SplatPoint.new()

		point.position = Vector3(
			buffer.decode_float(offset),
			buffer.decode_float(offset + 4),
			buffer.decode_float(offset + 8)
		)
		point.scale = Vector3(
			buffer.decode_float(offset + 12),
			buffer.decode_float(offset + 16),
			buffer.decode_float(offset + 20)
		)
		point.rotation = Quaternion(
			buffer.decode_float(offset + 24),
			buffer.decode_float(offset + 28),
			buffer.decode_float(offset + 32),
			buffer.decode_float(offset + 36)
		)
		point.color = Color(
			buffer.decode_float(offset + 40),
			buffer.decode_float(offset + 44),
			buffer.decode_float(offset + 48)
		)
		point.opacity = buffer.decode_float(offset + 52)

		points[i] = point

		# Yield every 10000 points to keep UI responsive
		if i % 10000 == 0 and i > 0:
			progress_updated.emit(i, total_points)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, points)

# Loads simple XYZ format files (plain text coordinate data)
# XYZ format is a simple ASCII format with space-separated values per line
# Format: "x y z [r g b]" where coordinates are required and colors are optional
# @param file: Open file handle for reading
# @return: LoadResult with parsed point cloud data
func _load_xyz(file: FileAccess) -> LoadResult:
	var points: Array[SplatPoint] = []

	# Read file line by line until end
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue  # Skip empty lines

		# Split line into space-separated values
		var values = line.split(" ")
		if values.size() < 3:
			continue  # Need at least X, Y, Z coordinates

		# Create point with 3D position
		var point = SplatPoint.new()
		point.position = Vector3(
			values[0].to_float(),  # X coordinate
			values[1].to_float(),  # Y coordinate
			values[2].to_float()   # Z coordinate
		)

		# Parse optional color data if present (supports both 0-1 and 0-255 ranges)
		if values.size() >= 6:
			var r = values[3].to_float()
			var g = values[4].to_float()
			var b = values[5].to_float()

			# Auto-detect color format and normalize to 0-1 range
			# If any value > 1.0, assume 0-255 range and convert
			if r > 1.0 or g > 1.0 or b > 1.0:
				point.color = Color(r / 255.0, g / 255.0, b / 255.0)
			else:
				# Values already in 0-1 range
				point.color = Color(r, g, b)

		points.append(point)

		# Yield control every 1000 points to prevent UI freezing
		if points.size() % 1000 == 0:
			progress_updated.emit(points.size(), 0)
			await Engine.get_main_loop().process_frame

	return LoadResult.new(true, points)
