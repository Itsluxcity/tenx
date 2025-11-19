#!/usr/bin/env python3
"""
Generate simple TenX app logo without text rendering issues
"""

from PIL import Image, ImageDraw
import os

def create_tenx_logo(size):
    """Create a modern TenX logo with geometric design"""
    # Create image with gradient background
    img = Image.new('RGB', (size, size), color='#000000')
    draw = ImageDraw.Draw(img)
    
    # Create gradient background (dark blue to purple)
    for y in range(size):
        r = int(10 + (26 - 10) * (y / size))
        g = int(25 - 15 * (y / size))
        b = int(41)
        draw.rectangle([(0, y), (size, y+1)], fill=(r, g, b))
    
    # Draw "TenX" text using simple geometric representation
    center_x = size // 2
    center_y = size // 2
    
    # Scale factor for elements
    scale = size / 1024
    
    # Draw "T" - horizontal top bar and vertical stem
    t_width = int(250 * scale)
    t_height = int(400 * scale)
    t_stem_width = int(80 * scale)
    t_x = center_x - int(350 * scale)
    t_y = center_y - t_height // 2
    
    # Top horizontal bar of "T"
    draw.rectangle(
        [(t_x, t_y), (t_x + t_width, t_y + int(80 * scale))],
        fill=(0, 220, 255)
    )
    
    # Vertical stem of "T"
    stem_x = t_x + (t_width - t_stem_width) // 2
    draw.rectangle(
        [(stem_x, t_y), (stem_x + t_stem_width, t_y + t_height)],
        fill=(0, 220, 255)
    )
    
    # Draw "e" - circle with horizontal line
    e_radius = int(120 * scale)
    e_thickness = int(60 * scale)
    e_x = center_x - int(100 * scale)
    e_y = center_y + int(50 * scale)
    
    # Outer circle
    draw.ellipse(
        [(e_x - e_radius, e_y - e_radius),
         (e_x + e_radius, e_y + e_radius)],
        fill=(100, 200, 255)
    )
    
    # Inner circle (hole)
    inner_radius = e_radius - e_thickness
    draw.ellipse(
        [(e_x - inner_radius, e_y - inner_radius),
         (e_x + inner_radius, e_y + inner_radius)],
        fill=(10, 20, 41)  # Match background
    )
    
    # Horizontal line through "e"
    draw.rectangle(
        [(e_x - e_radius, e_y - int(30 * scale)),
         (e_x + e_radius, e_y + int(10 * scale))],
        fill=(10, 20, 41)
    )
    
    # Draw "n" - vertical bar and arch
    n_height = int(250 * scale)
    n_width = int(200 * scale)
    n_thickness = int(70 * scale)
    n_x = center_x + int(80 * scale)
    n_y = center_y + int(50 * scale)
    
    # Left vertical bar
    draw.rectangle(
        [(n_x, n_y - n_height//2), (n_x + n_thickness, n_y + n_height//2)],
        fill=(150, 100, 255)
    )
    
    # Right vertical bar
    draw.rectangle(
        [(n_x + n_width - n_thickness, n_y - n_height//2),
         (n_x + n_width, n_y + n_height//2)],
        fill=(150, 100, 255)
    )
    
    # Top arch
    draw.ellipse(
        [(n_x, n_y - n_height//2 - int(50 * scale)),
         (n_x + n_width, n_y + int(50 * scale))],
        fill=(150, 100, 255)
    )
    
    # Cut out inner arch
    draw.ellipse(
        [(n_x + n_thickness, n_y - n_height//2),
         (n_x + n_width - n_thickness, n_y)],
        fill=(10, 20, 41)
    )
    
    # Draw "X" - two diagonal bars
    x_size = int(300 * scale)
    x_thickness = int(80 * scale)
    x_x = center_x + int(350 * scale)
    x_y = center_y
    
    # Top-left to bottom-right diagonal
    points1 = [
        (x_x - x_size//2, x_y - x_size//2),
        (x_x - x_size//2 + x_thickness, x_y - x_size//2),
        (x_x + x_size//2, x_y + x_size//2),
        (x_x + x_size//2 - x_thickness, x_y + x_size//2)
    ]
    draw.polygon(points1, fill=(255, 100, 200))
    
    # Top-right to bottom-left diagonal
    points2 = [
        (x_x + x_size//2, x_y - x_size//2),
        (x_x + x_size//2 - x_thickness, x_y - x_size//2),
        (x_x - x_size//2, x_y + x_size//2),
        (x_x - x_size//2 + x_thickness, x_y + x_size//2)
    ]
    draw.polygon(points2, fill=(255, 100, 200))
    
    return img

def main():
    # Create logo in multiple sizes for iOS
    sizes = [1024]
    
    output_dir = "/Volumes/pookiepants/POOKIEPANTS/AI Code/CascadeProjects/windsurf-project/personal-journal/TenX/AppIcon"
    os.makedirs(output_dir, exist_ok=True)
    
    for size in sizes:
        print(f"Creating {size}x{size} logo...")
        img = create_tenx_logo(size)
        img.save(os.path.join(output_dir, f"AppIcon-{size}x{size}.png"), 'PNG')
    
    print(f"✅ Created TenX logo in: {output_dir}")
    print("\nTo use in Xcode:")
    print("1. Open Assets.xcassets in Xcode")
    print("2. Click on AppIcon")
    print("3. Drag AppIcon-1024x1024.png to the 1024x1024 slot")
    print("4. Xcode will automatically generate all other sizes")

if __name__ == "__main__":
    main()
