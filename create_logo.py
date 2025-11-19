#!/usr/bin/env python3
"""
Generate TenX app logo
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_tenx_logo(size):
    """Create a modern TenX logo"""
    # Create image with gradient background
    img = Image.new('RGB', (size, size), color='#000000')
    draw = ImageDraw.Draw(img)
    
    # Create gradient background (dark blue to purple)
    for y in range(size):
        # Gradient from dark blue (#0A1929) to purple (#1A0A29)
        r = int(10 + (26 - 10) * (y / size))
        g = int(25 - 15 * (y / size))
        b = int(41)
        draw.rectangle([(0, y), (size, y+1)], fill=(r, g, b))
    
    # Add subtle grid pattern
    grid_color = (255, 255, 255, 20)
    grid_spacing = size // 10
    for i in range(0, size, grid_spacing):
        draw.line([(i, 0), (i, size)], fill=grid_color, width=1)
        draw.line([(0, i), (size, i)], fill=grid_color, width=1)
    
    # Draw "10X" text
    font_size = int(size * 0.35)
    try:
        # Try to use a bold system font
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/SFNSDisplay.ttf", font_size)
        except:
            # Fallback to default with size
            font = ImageFont.load_default()
            font_size = int(size * 0.2)  # Adjust for default font
    
    # Draw text with glow effect
    text = "10X"
    
    # Get text bounding box
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    # Center position
    x = (size - text_width) // 2
    y = (size - text_height) // 2 - int(size * 0.05)
    
    # Draw glow effect (multiple layers)
    glow_colors = [
        (0, 255, 255, 30),   # Cyan glow
        (0, 200, 255, 50),
        (0, 150, 255, 70),
    ]
    
    for i, glow_color in enumerate(glow_colors):
        offset = (len(glow_colors) - i) * 3
        for dx in range(-offset, offset+1):
            for dy in range(-offset, offset+1):
                if dx*dx + dy*dy <= offset*offset:
                    draw.text((x + dx, y + dy), text, font=font, fill=glow_color)
    
    # Draw main text (white with slight blue tint)
    draw.text((x, y), text, font=font, fill=(255, 255, 255))
    
    # Add accent line below text
    line_y = y + text_height + int(size * 0.05)
    line_width = int(text_width * 0.8)
    line_x = x + (text_width - line_width) // 2
    
    # Gradient line (cyan to blue)
    for i in range(line_width):
        progress = i / line_width
        r = int(0 + (100 - 0) * progress)
        g = int(255 - 100 * progress)
        b = 255
        draw.rectangle(
            [(line_x + i, line_y), (line_x + i + 1, line_y + int(size * 0.015))],
            fill=(r, g, b)
        )
    
    return img

def main():
    # Create logo in multiple sizes for iOS
    sizes = [1024, 512, 256, 180, 120, 87, 80, 60, 58, 40, 29, 20]
    
    output_dir = "/Volumes/pookiepants/POOKIEPANTS/AI Code/CascadeProjects/windsurf-project/personal-journal/TenX/AppIcon"
    os.makedirs(output_dir, exist_ok=True)
    
    for size in sizes:
        print(f"Creating {size}x{size} logo...")
        img = create_tenx_logo(size)
        
        # Save with appropriate naming
        if size == 1024:
            filename = f"AppIcon-{size}.png"
        else:
            filename = f"AppIcon-{size}x{size}.png"
        
        img.save(os.path.join(output_dir, filename), 'PNG')
    
    # Create the main 1024x1024 for the asset catalog
    main_logo = create_tenx_logo(1024)
    main_logo.save(os.path.join(output_dir, "AppIcon-1024x1024.png"), 'PNG')
    
    print(f"✅ Created TenX logos in: {output_dir}")
    print("\nTo use in Xcode:")
    print("1. Open Assets.xcassets")
    print("2. Click on AppIcon")
    print("3. Drag AppIcon-1024x1024.png to the 1024x1024 slot")

if __name__ == "__main__":
    main()
