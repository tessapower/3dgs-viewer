import struct
import math
import random

def create_example_splat():
    """Create an example SPLAT file with sample 3D Gaussian data"""
    
    # SPLAT file format (32 bytes per splat):
    # Position: 3 floats (x, y, z)
    # Scale: 3 floats (sx, sy, sz)
    # Rotation: 4 floats (quaternion: x, y, z, w)
    # Color: 3 floats (r, g, b)
    # Opacity: 1 float
    
    splats = []
    
    # Create a simple cube of splats
    for i in range(5):
        for j in range(5):
            for k in range(5):
                # Position
                x = (i - 2.0) * 0.5
                y = (j - 2.0) * 0.5
                z = (k - 2.0) * 0.5
                
                # Scale (small uniform splats)
                sx = sy = sz = 0.1
                
                # Rotation (identity quaternion)
                qx = qy = qz = 0.0
                qw = 1.0
                
                # Color (bright rainbow based on position)
                # Map positions to the entire color spectrum
                r = i / 4.0  # Red channel maps to i index
                g = j / 4.0  # Green channel maps to j index
                b = k / 4.0  # Blue channel maps to k index
                
                # Opacity
                opacity = 1.0
                
                splats.append((x, y, z, sx, sy, sz, qx, qy, qz, qw, r, g, b, opacity))
    
    # Add some random splats for variety
    for _ in range(875):
        # Random position in a sphere
        theta = random.uniform(0, 2 * math.pi)
        phi = random.uniform(0, math.pi)
        radius = random.uniform(0.5, 2.0)
        
        x = radius * math.sin(phi) * math.cos(theta)
        y = radius * math.sin(phi) * math.sin(theta)
        z = radius * math.cos(phi)
        
        # Random scale
        sx = random.uniform(0.05, 0.2)
        sy = random.uniform(0.05, 0.2)
        sz = random.uniform(0.05, 0.2)
        
        # Random rotation
        qx = random.uniform(-1, 1)
        qy = random.uniform(-1, 1)
        qz = random.uniform(-1, 1)
        qw = random.uniform(-1, 1)
        
        # Normalize quaternion
        q_len = math.sqrt(qx*qx + qy*qy + qz*qz + qw*qw)
        if q_len > 0:
            qx /= q_len
            qy /= q_len
            qz /= q_len
            qw /= q_len
        
        # Bright random color
        # Generate random colors for the spectrum
        r = random.uniform(0.0, 1.0)
        g = random.uniform(0.0, 1.0)
        b = random.uniform(0.0, 1.0)
        
        # Random opacity
        opacity = random.uniform(0.5, 1.0)
        
        splats.append((x, y, z, sx, sy, sz, qx, qy, qz, qw, r, g, b, opacity))
    
    return splats

def write_splat_file(filename, splats):
    """Write splats to a binary SPLAT file"""
    with open(filename, 'wb') as f:
        for splat in splats:
            # Pack each splat as 14 floats (32-bit each)
            packed = struct.pack('14f', *splat)
            f.write(packed)

def write_ply_file(filename, splats):
    """Write splats as a PLY file for comparison"""
    with open(filename, 'w') as f:
        f.write("ply\n")
        f.write("format ascii 1.0\n")
        f.write(f"element vertex {len(splats)}\n")
        f.write("property float x\n")
        f.write("property float y\n")
        f.write("property float z\n")
        f.write("property uchar red\n")
        f.write("property uchar green\n")
        f.write("property uchar blue\n")
        f.write("end_header\n")
        
        for splat in splats:
            x, y, z = splat[0], splat[1], splat[2]
            r, g, b = splat[10], splat[11], splat[12]
            
            # Convert colors to 0-255 range
            r_int = int(r * 255)
            g_int = int(g * 255)
            b_int = int(b * 255)
            
            f.write(f"{x} {y} {z} {r_int} {g_int} {b_int}\n")

def write_xyz_file(filename, splats):
    """Write splats as an XYZ file for comparison"""
    with open(filename, 'w') as f:
        for splat in splats:
            x, y, z = splat[0], splat[1], splat[2]
            r, g, b = splat[10], splat[11], splat[12]
            f.write(f"{x} {y} {z} {r} {g} {b}\n")

if __name__ == "__main__":
    print("Generating example point cloud data...")
    
    # Create sample splats
    splats = create_example_splat()
    
    # Write different formats to current directory (tests/)
    write_splat_file("example.splat", splats)
    write_ply_file("example.ply", splats)
    write_xyz_file("example.xyz", splats)
    
    print(f"Generated {len(splats)} splats in three formats:")
    print("- example.splat (binary 3D Gaussian splat format)")
    print("- example.ply (PLY format)")
    print("- example.xyz (XYZ format)")
    print("\nYou can now load these files in your Godot tool!")
