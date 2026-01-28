import struct
import math
import random
import colorsys

random.seed(42)

def hsv_to_rgb(h, s, v):
    """Convert HSV (0-1 range) to RGB (0-1 range)"""
    return colorsys.hsv_to_rgb(h % 1.0, s, v)

def make_splat(x, y, z, r, g, b, sx=0.1, sy=0.1, sz=0.1, opacity=1.0):
    """Helper to create a splat tuple with identity rotation"""
    return (x, y, z, sx, sy, sz, 0.0, 0.0, 0.0, 1.0, r, g, b, opacity)

def create_spiral_galaxy(num_points=8000):
    """Create a spiral galaxy with dense core and sweeping arms"""
    splats = []
    num_arms = 3
    arm_spread = 0.4

    for i in range(num_points):
        t = i / num_points

        if t < 0.2:
            # Dense galactic core (20% of points)
            r = random.gauss(0, 0.3)
            angle = random.uniform(0, 2 * math.pi)
            x = r * math.cos(angle)
            z = r * math.sin(angle)
            y = random.gauss(0, 0.05)  # Thin disk
            hue = 0.08 + random.gauss(0, 0.03)  # Warm yellow-white core
            sat = random.uniform(0.1, 0.4)
            val = random.uniform(0.85, 1.0)
        else:
            # Spiral arms
            arm = random.randint(0, num_arms - 1)
            arm_angle = (2 * math.pi / num_arms) * arm
            dist = random.uniform(0.3, 3.0)
            # Logarithmic spiral: angle increases with log of distance
            spiral_angle = arm_angle + 1.2 * math.log(1 + dist * 2)
            # Add spread that increases with distance
            spread = arm_spread * dist * 0.3
            x = dist * math.cos(spiral_angle) + random.gauss(0, spread)
            z = dist * math.sin(spiral_angle) + random.gauss(0, spread)
            y = random.gauss(0, 0.03 + 0.02 * dist)  # Slightly thicker at edges

            # Color: blue-white in arms, reddish at edges
            hue = 0.6 - dist * 0.08 + random.gauss(0, 0.03)  # Blue shifting to purple
            sat = 0.4 + dist * 0.1
            val = max(0.4, 1.0 - dist * 0.15)

        r, g, b = hsv_to_rgb(hue, min(sat, 1.0), val)
        splats.append(make_splat(x, y, z, r, g, b, opacity=random.uniform(0.7, 1.0)))

    return splats

def create_dna_helix(num_points=8000):
    """Create a DNA double helix with base pair connections"""
    splats = []
    helix_height = 6.0
    helix_radius = 1.0
    turns = 4

    for i in range(num_points):
        t = i / num_points

        if t < 0.35:
            # First strand
            progress = (t / 0.35)
            angle = progress * turns * 2 * math.pi
            y = progress * helix_height - helix_height / 2
            x = helix_radius * math.cos(angle) + random.gauss(0, 0.03)
            z = helix_radius * math.sin(angle) + random.gauss(0, 0.03)
            hue = 0.55  # Cyan
            sat, val = 0.8, 0.9
        elif t < 0.7:
            # Second strand (offset by pi)
            progress = ((t - 0.35) / 0.35)
            angle = progress * turns * 2 * math.pi + math.pi
            y = progress * helix_height - helix_height / 2
            x = helix_radius * math.cos(angle) + random.gauss(0, 0.03)
            z = helix_radius * math.sin(angle) + random.gauss(0, 0.03)
            hue = 0.75  # Purple
            sat, val = 0.7, 0.9
        else:
            # Base pairs connecting the two strands
            progress = ((t - 0.7) / 0.3)
            angle = progress * turns * 2 * math.pi
            y = progress * helix_height - helix_height / 2
            # Interpolate between the two strand positions
            lerp = random.uniform(0.0, 1.0)
            x1 = helix_radius * math.cos(angle)
            z1 = helix_radius * math.sin(angle)
            x2 = helix_radius * math.cos(angle + math.pi)
            z2 = helix_radius * math.sin(angle + math.pi)
            x = x1 * lerp + x2 * (1 - lerp) + random.gauss(0, 0.02)
            z = z1 * lerp + z2 * (1 - lerp) + random.gauss(0, 0.02)
            y += random.gauss(0, 0.02)
            # Color based on position between strands
            hue = 0.0 + lerp * 0.15  # Red to orange
            sat, val = 0.9, 0.95

        r, g, b = hsv_to_rgb(hue, sat, val)
        splats.append(make_splat(x, y, z, r, g, b))

    return splats

def create_torus_knot(num_points=8000):
    """Create a trefoil torus knot with flowing HSV colors"""
    splats = []
    # Torus knot parameters: p wraps around the hole, q wraps through the hole
    p, q = 2, 3
    R = 2.0   # Major radius
    r = 0.6   # Minor radius (tube thickness)

    for i in range(num_points):
        t = (i / num_points) * 2 * math.pi

        # Torus knot centerline
        cx = (R + r * math.cos(q * t)) * math.cos(p * t)
        cy = (R + r * math.cos(q * t)) * math.sin(p * t)
        cz = r * math.sin(q * t)

        # Add thickness around the centerline
        spread = 0.12
        cx += random.gauss(0, spread)
        cy += random.gauss(0, spread)
        cz += random.gauss(0, spread)

        # Smooth HSV gradient following the curve
        hue = (i / num_points) * 3  # Cycle through spectrum 3 times
        sat = 0.85
        val = 0.7 + 0.3 * math.sin(t * 5)  # Subtle brightness wave

        rv, gv, bv = hsv_to_rgb(hue, sat, val)
        splats.append(make_splat(cx, cz, cy, rv, gv, bv))  # Swap y/z so knot lies flat

    return splats

def write_splat_file(filename, splats):
    """Write splats to a binary SPLAT file"""
    with open(filename, 'wb') as f:
        for splat in splats:
            packed = struct.pack('14f', *splat)
            f.write(packed)

def write_ply_file(filename, splats):
    """Write splats as a PLY file"""
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
            f.write(f"{x} {y} {z} {int(r * 255)} {int(g * 255)} {int(b * 255)}\n")

def write_xyz_file(filename, splats):
    """Write splats as an XYZ file"""
    with open(filename, 'w') as f:
        for splat in splats:
            x, y, z = splat[0], splat[1], splat[2]
            r, g, b = splat[10], splat[11], splat[12]
            f.write(f"{x} {y} {z} {r} {g} {b}\n")

if __name__ == "__main__":
    generators = {
        "galaxy": ("Spiral Galaxy", create_spiral_galaxy),
        "dna": ("DNA Double Helix", create_dna_helix),
        "knot": ("Torus Knot", create_torus_knot),
    }

    for name, (label, gen_func) in generators.items():
        print(f"Generating {label}...")
        splats = gen_func()
        write_splat_file(f"{name}.splat", splats)
        write_ply_file(f"{name}.ply", splats)
        write_xyz_file(f"{name}.xyz", splats)
        print(f"  -> {len(splats)} points in .splat, .ply, .xyz")

    print("\nDone! Generated 3 shapes x 3 formats = 9 files.")
    print("Load them in the 3DGS Viewer to see the results.")
