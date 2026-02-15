### main.gd: Main controller for the 3D Gaussian Splat Viewer. Handles the UI,
## file loading, and 3D visualization of point cloud data.
###
### Author: Tessa Power
extends Node3D

# UI Component References
@onready var file_dialog: FileDialog = $CanvasLayer/FileDialog
@onready var load_button: Button = $CanvasLayer/MarginContainer/UI/HBoxContainer/LoadButton
@onready var reset_camera_button: Button = $CanvasLayer/MarginContainer/UI/HBoxContainer/ResetCameraButton
@onready var example_dropdown: OptionButton = $CanvasLayer/MarginContainer/UI/HBoxContainer/ExampleDropdown
@onready var clear_button: Button = $CanvasLayer/MarginContainer/UI/HBoxContainer/ClearButton
@onready var info_label: Label = $CanvasLayer/MarginContainer/UI/BottomBar/InfoLabel
@onready var loading_spinner: CenterContainer = $CanvasLayer/LoadingSpinner
@onready var loading_label: Label = $CanvasLayer/LoadingSpinner/Label
@onready var camera: Camera3D = $Camera3D
@onready var point_cloud: Node3D = $PointCloud

# Core Components
var splat_loader: SplatLoader  # Handles loading of different point cloud file formats
const MAX_CACHE_SIZE = 5
var _model_cache: Dictionary = {}  # path -> {vertices, colors}
var _cache_order: Array = []  # LRU order, oldest first
const EXAMPLE_FILES = {
	"Goat Skull": "res://tests/goat-skull/goat-skull.ply",
	"Bonsai": "res://tests/bonsai-7k-mini.splat",
	"DNA": "res://tests/dna.splat",
}

# Loading spinner animation
const SPINNER_FRAMES = ["◜", "◝", "◞", "◟"]
var _spinner_frame: int = 0
var _spinner_time: float = 0.0
var _current_file: String = ""

# Camera Control State
var is_rotating: bool = false
var is_panning: bool = false
var last_mouse_position: Vector2
var pivot: Vector3 = Vector3.ZERO  # The point the camera orbits around

func _ready():
	# Initialize the splat loader component
	splat_loader = SplatLoader.new()

	# Populate examples dropdown with a placeholder first item
	example_dropdown.add_item("Select example")
	example_dropdown.set_item_disabled(0, true)
	for file_name in EXAMPLE_FILES:
		example_dropdown.add_item(file_name)

	# Connect UI signals to their respective handlers
	load_button.pressed.connect(_on_load_button_pressed)
	example_dropdown.item_selected.connect(_on_example_selected)
	reset_camera_button.pressed.connect(_reset_camera)
	clear_button.pressed.connect(_on_clear_pressed)
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

	# Create environment with dark background so both colored and white points are visible
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.15, 0.15)
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.3
	camera.environment = environment

	# Load the default example on the next frame (deferred so web VFS is ready)
	_on_example_selected.call_deferred(1)

func _process(delta):
	if loading_spinner.visible:
		_spinner_time += delta
		if _spinner_time >= 0.08:
			_spinner_time = 0.0
			_spinner_frame = (_spinner_frame + 1) % SPINNER_FRAMES.size()
			loading_label.text = SPINNER_FRAMES[_spinner_frame] + " Loading..."

# Event handler: Called when the load button is pressed
# Opens the file dialog for the user to select a point cloud file
func _on_load_button_pressed():
	file_dialog.popup_centered(Vector2i(800, 600))  # Show file dialog with 800x600 size

# Event handler: Called when a file is selected from the file dialog
# Loads and displays the selected point cloud file
func _on_file_selected(path: String):
	_current_file = path

	# Reset dropdown to placeholder if loading an external file
	if path not in EXAMPLE_FILES.values():
		example_dropdown.select(0)

	# Clear any existing point cloud data from the scene
	for child in point_cloud.get_children():
		child.queue_free()

	# Check cache first
	if path in _model_cache:
		var cached = _model_cache[path]
		_create_point_cloud(cached.vertices, cached.colors)
		_auto_frame_camera(cached.vertices)
		info_label.text = "Loaded %d points from %s" % [cached.vertices.size(), path.get_file()]
		info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		# Move to end of LRU order
		_cache_order.erase(path)
		_cache_order.append(path)
		return

	# Update UI to show loading status
	info_label.text = "Loading file: " + path.get_file()
	loading_spinner.visible = true

	# Asynchronously load the selected file using the splat loader
	var result = await splat_loader.load_file(path)

	loading_spinner.visible = false

	# Handle the loading result
	if result.success:
		var centered_verts = _center_vertices(result.vertices)
		_create_point_cloud(centered_verts, result.colors)
		_auto_frame_camera(centered_verts)
		info_label.text = "Loaded %d points from %s" % [result.point_count(), path.get_file()]
		info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		# Cache the centered result
		_cache_model(path, centered_verts, result.colors)
	else:
		info_label.text = "Error loading file: " + result.error
		info_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

func _cache_model(path: String, vertices: PackedVector3Array, colors: PackedColorArray):
	_model_cache[path] = {vertices = vertices, colors = colors}
	_cache_order.append(path)
	# Evict oldest entry if cache is full
	while _cache_order.size() > MAX_CACHE_SIZE:
		var evicted = _cache_order.pop_front()
		_model_cache.erase(evicted)

func _on_files_dropped(files: PackedStringArray):
	if files.size() == 0:
		return
	var path = files[0]
	var ext = path.get_extension().to_lower()
	if ext in ["ply", "splat", "xyz"]:
		_on_file_selected(path)
	else:
		info_label.text = "Unsupported file type: ." + ext
		info_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

func _on_example_selected(index: int):
	if index == 0:
		return
	var file_name = example_dropdown.get_item_text(index)
	var path = EXAMPLE_FILES[file_name]
	if path == _current_file:
		return
	example_dropdown.select(index)
	_on_file_selected(path)

func _on_load_progress(loaded: int, total: int):
	if total > 0:
		info_label.text = "Loading... %d / %d points" % [loaded, total]
	else:
		info_label.text = "Loading... %d points" % loaded

func _on_clear_pressed():
	for child in point_cloud.get_children():
		child.queue_free()
	_current_file = ""
	example_dropdown.select(0)
	_reset_camera()
	info_label.text = "Load a file or drag and drop to begin"

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

	# Custom shader: distance-based point sizing with Gaussian falloff
	var shader = Shader.new()
	shader.code = "
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;

uniform float base_point_size : hint_range(1.0, 50.0) = 20.0;
uniform float min_point_size : hint_range(1.0, 10.0) = 1.0;
uniform float max_point_size : hint_range(10.0, 200.0) = 80.0;

void vertex() {
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	POINT_SIZE = clamp(base_point_size / dist, min_point_size, max_point_size);
}

void fragment() {
	// Convert square point to soft circular splat with Gaussian falloff
	vec2 center = POINT_COORD * 2.0 - 1.0;
	float r2 = dot(center, center);

	// Discard pixels outside the circle
	if (r2 > 1.0) discard;

	// Gaussian falloff: exp(-r^2 * sigma), sigma controls softness
	float alpha = exp(-r2 * 3.0) * COLOR.a;

	ALBEDO = COLOR.rgb;
	ALPHA = alpha;
}
"
	var p_material = ShaderMaterial.new()
	p_material.shader = shader
	mesh_instance.material_override = p_material

	point_cloud.add_child(mesh_instance)

# Input handler for camera controls (only fires for events not consumed by UI)
func _unhandled_input(event):
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

	# If a point cloud is loaded, reframe the camera to fit it
	if point_cloud.get_child_count() > 0:
		var mesh_instance = point_cloud.get_child(0) as MeshInstance3D
		if mesh_instance and mesh_instance.mesh:
			var vertices = mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			_auto_frame_camera(vertices)
			return

	# Default camera position when no model is loaded
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
