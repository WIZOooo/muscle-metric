import os
from PIL import Image, ImageDraw, ImageFont, ImageColor

def create_icon():
    size = (1024, 1024)
    # Create a gradient background (Blue to Orange as requested)
    image = Image.new('RGB', size)
    draw = ImageDraw.Draw(image)
    
    top_color = (0, 122, 255) # System Blue
    bottom_color = (255, 149, 0) # System Orange
    
    for y in range(size[1]):
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * y / size[1])
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * y / size[1])
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * y / size[1])
        draw.line([(0, y), (1024, y)], fill=(r, g, b))
        
    # Draw "M" in the center
    # Try to load a font, fallback to default
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 600)
    except:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/SFCompactDisplay-Bold.otf", 600)
        except:
             font = ImageFont.load_default()

    text = "M"
    
    # Calculate text position to center it
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    x = (size[0] - text_width) / 2 - bbox[0]
    y = (size[1] - text_height) / 2 - bbox[1]
    
    draw.text((x+20, y+20), text, font=font, fill=(0,0,0,100))
    draw.text((x, y), text, font=font, fill=(255, 255, 255))
    
    # Corrected path
    output_path = "MuscleMetric/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    image.save(output_path)
    print(f"Icon saved to {output_path}")

if __name__ == "__main__":
    create_icon()
