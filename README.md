# Hello 3DGS - 3D Gaussian Splat Viewer

A simple Godot tool for loading and visualizing 3D Gaussian Splat point cloud data.

## Features

- Load multiple point cloud formats:
  - PLY files (Stanford Triangle Format)
  - SPLAT files (3D Gaussian Splat format)
  - XYZ files (simple point format)
- Interactive 3D visualization
- Mouse controls for camera navigation
- Color support for point clouds
- Asynchronous loading to prevent UI freezing

## How to Use

1. Open the project in Godot Engine 4.3+
2. Run the project
3. Click "Load Splat File" to open a file dialog
4. Select a supported point cloud file (.ply, .splat, or .xyz)
5. View the loaded point cloud in the 3D viewport

## Controls

### Mouse Controls
- **Left Mouse Button + Drag**: Rotate camera around the point cloud
- **Mouse Wheel Up/Down**: Zoom in/out

### Keyboard Controls
- **W** or **↑**: Zoom in
- **S** or **↓**: Zoom out
- **R**: Reset camera to default position

### Tips
- If mouse wheel doesn't work, use W/S keys for zooming
- Use R key to reset view if you get lost while navigating
- Camera has minimum zoom distance to prevent going inside the point cloud

## Supported File Formats

### PLY Files
Standard PLY format with vertex data. Supports position (x, y, z) and color (r, g, b) data.

### SPLAT Files
Binary format for 3D Gaussian Splats containing:
- Position (3 floats)
- Scale (3 floats)
- Rotation (4 floats - quaternion)
- Color (3 floats)
- Opacity (1 float)

### XYZ Files
Simple text format with space-separated values:
- Position only: `x y z`
- Position with color: `x y z r g b`
- Supports both normalized (0-1) and 0-255 color ranges

## Technical Details

- Built with Godot 4.3
- Uses ArrayMesh for efficient point cloud rendering
- Implements asynchronous file loading
- Supports large point clouds with progressive loading

## Project Structure

- `main.gd` - Main application controller
- `main.tscn` - Main scene with UI layout
- `splat_loader.gd` - Point cloud file loader class
- `project.godot` - Godot project configuration

## Requirements

- Godot Engine 4.3 or later
- Point cloud files in supported formats

## Example Files

The project includes example files for testing in the `tests`:

- `example.ply` - PLY format with 225 colored points
- `example.splat` - Binary splat format with position, scale, rotation, and color data
- `example.xyz` - Simple XYZ format with position and color data

These files contain a colorful 5×5×5 cube of points plus 100 randomly scattered points with various colors and properties.

### Generating New Examples

Run the included Python script found in the `tests` directory to generate fresh example files:

```bash
python generate_example_splat.py
```

This will create new example files in all three supported formats.

## Getting Started

1. Clone or download this project.
2. Open `project.godot` in Godot Engine.
3. Run the project.
4. Try loading the example files first to test the functionality.
5. Load your own point cloud files!
