### main.gd: Main controller for the 3D Gaussian Splat Viewer. Handles the UI,
## file loading, and 3D visualization of point cloud data.
###
### Author: Tessa Power
extends Control

# UI Component References
# These are automatically assigned when the scene is ready
@onready var file_dialog: FileDialog = $FileDialog
@onready var load_button: Button = $VBoxContainer/HBoxContainer/LoadButton
@onready var info_label: Label = $VBoxContainer/HBoxContainer/InfoLabel
@onready var viewport: SubViewport = $VBoxContainer/ViewportContainer/SubViewport
@onready var camera: Camera3D = $VBoxContainer/ViewportContainer/SubViewport/Camera3D
@onready var point_cloud: Node3D = $VBoxContainer/ViewportContainer/SubViewport/PointCloud

# Core Components
var splat_loader: SplatLoader  # Handles loading of different point cloud file formats

# Camera Control State
var is_rotating: bool = false
var is_panning: bool = false
var last_mouse_position: Vector2
var pivot: Vector3 = Vector3.ZERO  # The point the camera orbits around

func _ready():
	# Initialize the splat loader component
	splat_loader = SplatLoader.new()

	# Connect UI signals to their respective handlers
	load_button.pressed.connect(_on_load_button_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	get_tree().root.files_dropped.connect(_on_files_dropped)
	splat_loader.progress_updated.connect(_on_load_progress)

	# Configure the file dialog to support multiple point cloud formats
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.ply", "PLY Files")        # Stanford PLY format
	file_dialog.add_filter("*.splat", "Splat Files")    # Binary 3D Gaussian Splat format
	file_dialog.add_filter("*.xyz", "XYZ Point Files")  # Simple XYZ coordinate files

	# Set default directory to the tests folder where example files are located
	file_dialog.set_current_dir("res://tests/")

	# Set initial instruction text for the user
	info_label.text = "Load a file or drag and drop to begin"

	# Initialize camera position and orientation
	# Position camera at a good viewing distance from the origin
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO, Vector3.UP)  # Look at origin with up vector pointing up

	# Create environment with dark background so both colored and white points are visible
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.15, 0.15)
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.3
	camera.environment = environment

# Event handler: Called when the load button is pressed
# Opens the file dialog for the user to select a point cloud file
func _on_load_button_pressed():
	file_dialog.popup_centered(Vector2i(800, 600))  # Show file dialog with 800x600 size

# Event handler: Called when a file is selected from the file dialog
# Loads and displays the selected point cloud file
func _on_file_selected(path: String):
	# Update UI to show loading status
	info_label.text = "Loading file: " + path.get_file()

	# Clear any existing point cloud data from the scene
	# This prevents memory leaks and visual artifacts from previous loads
	for child in point_cloud.get_children():
		child.queue_free()  # Queue nodes for deletion at end of frame

	# Asynchronously load the selected file using the splat loader
	# This prevents UI freezing during large file loads
	var result = await splat_loader.load_file(path)

	# Handle the loading result
	if result.success:
		var centered_verts = _center_vertices(result.vertices)
		_create_point_cloud(centered_verts, result.colors)
		_auto_frame_camera(centered_verts)
		info_label.text = "Loaded %d points from %s" % [result.point_count(), path.get_file()]
	else:
		info_label.text = "Error loading file: " + result.error

func _on_files_dropped(files: PackedStringArray):
	if files.size() == 0:
		return
	var path = files[0]
	var ext = path.get_extension().to_lower()
	if ext in ["ply", "splat", "xyz"]:
		_on_file_selected(path)
	else:
		info_label.text = "Unsupported file type: ." + ext

func _on_load_progress(loaded: int, total: int):
	if total > 0:
		info_label.text = "Loading... %d / %d points" % [loaded, total]
	else:
		info_label.text = "Loading... %d points" % loaded

# Creates a 3D mesh from packed vertex/color arrays and adds it to the scene
func _create_point_cloud(vertices: PackedVector3Array, colors: PackedColorArray):
	var mesh_instance = MeshInstance3D.new()
	var array_mesh = ArrayMesh.new()

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors

	# PRIMITIVE_POINTS renders each vertex as an individual point
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	mesh_instance.mesh = array_mesh

	# Configure material for point rendering
	var p_material = StandardMaterial3D.new()
	p_material.vertex_color_use_as_albedo = true
	p_material.use_point_size = true
	p_material.point_size = 2.0
	p_material.no_depth_test = false
	mesh_instance.material_override = p_material

	point_cloud.add_child(mesh_instance)

# Global input handler for camera controls
# Handles mouse and keyboard input for camera manipulation
func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.shift_pressed:
				# Shift+left-click: start panning
				is_panning = true
				is_rotating = false
			elif event.pressed:
				# Left-click: start rotating
				is_rotating = true
				is_panning = false
			else:
				is_rotating = false
				is_panning = false
			last_mouse_position = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			is_rotating = false
			last_mouse_position = event.position
		elif event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(-0.5)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(0.5)

	elif event is InputEventMouseMotion:
		var delta = event.position - last_mouse_position
		last_mouse_position = event.position

		if is_rotating:
			var sensitivity = 0.005
			# Orbit around the pivot point
			var offset = camera.position - pivot
			var rot_y = Basis(Vector3.UP, -delta.x * sensitivity)
			var local_x = camera.global_transform.basis.x
			var rot_x = Basis(local_x, -delta.y * sensitivity)
			var new_offset = rot_y * rot_x * offset

			# Clamp pitch to avoid gimbal lock at the poles
			# The angle between the offset and the horizontal plane must stay within ~85°
			var pitch_angle = asin(clamp(new_offset.normalized().y, -1.0, 1.0))
			var max_pitch = deg_to_rad(85.0)
			if abs(pitch_angle) < max_pitch:
				offset = new_offset
			else:
				# Only apply the horizontal (yaw) rotation
				offset = rot_y * offset

			camera.position = pivot + offset
			camera.look_at(pivot, Vector3.UP)
		elif is_panning:
			var sensitivity = 0.005
			var dist = (camera.position - pivot).length()
			var pan_speed = dist * sensitivity
			# Pan in the camera's local XY plane
			var right = camera.global_transform.basis.x
			var up = camera.global_transform.basis.y
			var pan_offset = (-right * delta.x + up * delta.y) * pan_speed
			camera.position += pan_offset
			pivot += pan_offset

	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_W or event.keycode == KEY_UP:
			_zoom_camera(-0.5)
		elif event.keycode == KEY_S or event.keycode == KEY_DOWN:
			_zoom_camera(0.5)
		elif event.keycode == KEY_R:
			_reset_camera()

func _zoom_camera(amount: float):
	var dist = (camera.position - pivot).length()
	# Zoom speed proportional to distance — feels consistent at any scale
	var step = dist * 0.15 * amount
	var direction = (camera.position - pivot).normalized()
	var new_position = camera.position + direction * step
	if (new_position - pivot).length() > 0.01:
		camera.position = new_position

func _reset_camera():
	pivot = Vector3.ZERO
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO, Vector3.UP)

# Translate all vertices so their centroid is at the origin
func _center_vertices(vertices: PackedVector3Array) -> PackedVector3Array:
	if vertices.is_empty():
		return vertices

	var centroid = Vector3.ZERO
	for v in vertices:
		centroid += v
	centroid /= vertices.size()

	var centered = PackedVector3Array()
	centered.resize(vertices.size())
	for i in range(vertices.size()):
		centered[i] = vertices[i] - centroid
	return centered

# Position the camera to see the entire (already centered) point cloud
func _auto_frame_camera(vertices: PackedVector3Array):
	if vertices.is_empty():
		return

	# Find maximum distance from origin to determine cloud radius
	var max_dist = 0.0
	for v in vertices:
		var d = v.length()
		if d > max_dist:
			max_dist = d

	var dist = max(max_dist * 2.0, 0.5)
	pivot = Vector3.ZERO
	camera.position = Vector3(0, dist * 0.3, dist)
	camera.look_at(Vector3.ZERO, Vector3.UP)
