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

	# Configure the file dialog to support multiple point cloud formats
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.ply", "PLY Files")        # Stanford PLY format
	file_dialog.add_filter("*.splat", "Splat Files")    # Binary 3D Gaussian Splat format
	file_dialog.add_filter("*.xyz", "XYZ Point Files")  # Simple XYZ coordinate files

	# Set default directory to the tests folder where example files are located
	file_dialog.set_current_dir("res://tests/")

	# Set initial instruction text for the user
	info_label.text = "Click 'Load Splat File' to begin"

	# Initialize camera position and orientation
	# Position camera at a good viewing distance from the origin
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO, Vector3.UP)  # Look at origin with up vector pointing up

	# Create a bright environment with white background for better point visibility
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR   # Use solid color background
	environment.background_color = Color.WHITE           # White background for contrast
	environment.ambient_light_color = Color.WHITE        # White ambient lighting
	environment.ambient_light_energy = 0.3               # Moderate ambient light intensity
	camera.environment = environment                     # Apply environment to camera

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
		# Create 3D visualization from loaded points
		_create_point_cloud(result.points)
		# Update UI with success message and point count
		info_label.text = "Loaded %d points from %s" % [result.points.size(), path.get_file()]
	else:
		# Display error message if loading failed
		info_label.text = "Error loading file: " + result.error

# Creates a 3D mesh from point cloud data and adds it to the scene
# @param points: Array of SplatPoint objects containing position and color data
func _create_point_cloud(points: Array):
	# Create a new mesh instance to hold our point cloud
	var mesh_instance = MeshInstance3D.new()
	var array_mesh = ArrayMesh.new()

	# Prepare arrays to hold vertex data
	var vertices = PackedVector3Array()  # 3D positions of each point
	var colors = PackedColorArray()     # Color data for each point

	# Extract position and color data from each point
	for point in points:
		vertices.append(point.position)
		colors.append(point.color)

	# Create mesh array structure required by Godot
	# This array contains different types of vertex data (position, color, normals, etc.)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)           # Resize to accommodate all possible data types
	arrays[Mesh.ARRAY_VERTEX] = vertices   # Assign vertex positions
	arrays[Mesh.ARRAY_COLOR] = colors      # Assign vertex colors

	# Create the mesh surface using point primitives
	# PRIMITIVE_POINTS renders each vertex as an individual point
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	mesh_instance.mesh = array_mesh

	# Configure material properties for optimal point rendering
	var p_material = StandardMaterial3D.new()
	p_material.vertex_color_use_as_albedo = true  # Use vertex colors as the base color
	p_material.use_point_size = true              # Enable custom point sizing
	p_material.point_size = 2.0                   # Set point size in pixels
	p_material.no_depth_test = false              # Enable depth testing for proper occlusion
	mesh_instance.material_override = p_material  # Apply material to mesh

	# Add the completed mesh to the point cloud container in the scene
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
			offset = rot_y * rot_x * offset
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
	var direction = (camera.position - pivot).normalized()
	var new_position = camera.position + direction * amount
	if (new_position - pivot).length() > 0.5:
		camera.position = new_position

func _reset_camera():
	pivot = Vector3.ZERO
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO, Vector3.UP)
