# Hello 3DGS - 3D Gaussian Splat Viewer

[![pages-build-deployment](https://github.com/tessapower/3dgs-viewer/actions/workflows/pages/pages-build-deployment/badge.svg)](https://github.com/tessapower/3dgs-viewer/actions/workflows/pages/pages-build-deployment)

A simple Godot tool for loading and visualizing 3D Gaussian Splat point cloud data.

![Goat skull model](assets/goat-skull.gif)

## Features

- Load multiple point cloud formats:
  - PLY files (ASCII and binary, including 3DGS spherical harmonics)
  - SPLAT files (standard 32-byte and extended 56-byte formats)
  - XYZ files (simple point format)
- Drag-and-drop file loading
- Interactive orbit camera with pan, rotate, and zoom
- Distance-based point sizing with Gaussian falloff rendering
- Auto-centering and camera framing for any model size
- Asynchronous loading with progress reporting

## How to Use

1. Open the project in Godot Engine 4.6+
2. Run the project
3. Click "Load Splat File" or drag and drop a file onto the window
4. View the loaded point cloud in the 3D viewport

## Controls

### Mouse Controls

- **Left Click + Drag**: Rotate camera around the point cloud
- **Shift + Left Click + Drag** or **Middle Mouse + Drag**: Pan camera
- **Mouse Wheel Up/Down**: Zoom in/out

### Keyboard Controls

- **W** or **Up Arrow**: Zoom in
- **S** or **Down Arrow**: Zoom out
- **R**: Reset camera

### UI Buttons

- **Load Splat File**: Open file dialog to select a point cloud file
- **Reset Camera**: Reset camera to frame the loaded model (or default position)
- **Clear**: Remove the current point cloud from the scene

## Supported File Formats

### PLY Files

Standard PLY format with vertex data. Supports both ASCII and binary (little-endian) formats. Reads position (x, y, z) and color from either RGB properties or spherical harmonics DC coefficients (f_dc_0, f_dc_1, f_dc_2).

### SPLAT Files

Binary format for 3D Gaussian Splats. Supports two variants:

- **Standard (32 bytes)**: 3×f32 position, 3×f32 scale, 4×u8 RGBA color, 4×u8 rotation
- **Extended (56 bytes)**: 14×f32 for position, scale, rotation, color, and opacity

### XYZ Files

Simple text format with space-separated values:

- Position only: `x y z`
- Position with color: `x y z r g b`
- Supports both normalized (0-1) and 0-255 color ranges

## Technical Details

- Built with Godot 4.6
- Uses ArrayMesh with packed arrays for efficient point cloud rendering
- Custom spatial shader with distance-based point sizing and Gaussian falloff
- Bulk buffer reads for fast file loading
- Asynchronous loading with progress callbacks

## Project Structure

- `scripts/main.gd` - Main application controller (UI, camera, rendering)
- `scripts/splat_loader.gd` - Point cloud file loader (PLY, SPLAT, XYZ)
- `scenes/main.tscn` - Main scene with UI layout
- `tests/` - Example point cloud files and generator script

## Requirements

- Godot Engine 4.6 or later

## Example Files

The `tests/` directory includes example files in all three formats:

- **Spiral Galaxy** (`galaxy.splat`, `.ply`, `.xyz`) - A spiral galaxy with dense core and sweeping arms
- **DNA Double Helix** (`dna.splat`, `.ply`, `.xyz`) - A DNA double helix with base pair connections
- **Torus Knot** (`knot.splat`, `.ply`, `.xyz`) - A trefoil torus knot with flowing HSV colors

Each contains 8,000 points with HSV color gradients.

### Generating New Examples

Run the included Python script from the `tests/` directory:

```bash
cd tests
python generate_example_splat.py
```

This generates all 9 example files (3 shapes × 3 formats).

## Getting Started

1. Clone or download this project
2. Open `project.godot` in Godot Engine 4.6+
3. Run the project
4. Try loading the example files to test, or load your own point cloud files
