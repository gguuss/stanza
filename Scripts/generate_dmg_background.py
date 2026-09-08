#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw, ImageFont

def generate_background():
    # 660 x 400 window
    width = 660
    height = 400
    
    img = Image.new('RGBA', (width, height), (22, 24, 29, 255))
    draw = ImageDraw.Draw(img)
    
    # Subtle top header / gradient feel
    for y in range(height):
        # subtle vertical gradient: slightly lighter at top, darker at bottom
        factor = 1.0 - (y / height) * 0.25
        r = int(28 * factor)
        g = int(31 * factor)
        b = int(38 * factor)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
    
    # Subtle border
    draw.rectangle([(0, 0), (width - 1, height - 1)], outline=(50, 55, 65, 255), width=1)
    
    # Try loading system font or fallback
    font_large = None
    font_small = None
    font_arrow = None
    
    font_paths = [
        "/System/Library/Fonts/SFPro-Bold.otf",
        "/System/Library/Fonts/SFCompact-Bold.otf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf"
    ]
    for p in font_paths:
        if os.path.exists(p):
            try:
                font_large = ImageFont.truetype(p, 20)
                font_small = ImageFont.truetype(p, 13)
                font_arrow = ImageFont.truetype(p, 28)
                break
            except Exception:
                continue
                
    if font_large is None:
        font_large = ImageFont.load_default()
        font_small = font_large
        font_arrow = font_large

    # Title text
    title = "Drag Stanza to Applications to install"
    bbox = draw.textbbox((0, 0), title, font=font_large)
    t_w = bbox[2] - bbox[0]
    draw.text(((width - t_w) // 2, 55), title, fill=(240, 240, 245, 255), font=font_large)
    
    subtitle = "Stanza • Minimalist Audio Player for macOS"
    s_bbox = draw.textbbox((0, 0), subtitle, font=font_small)
    s_w = s_bbox[2] - s_bbox[0]
    draw.text(((width - s_w) // 2, 85), subtitle, fill=(130, 135, 145, 255), font=font_small)

    # Modern arrow in the center between x=180 and x=480 (center is 330, y=190)
    # Draw a stylized pill with an arrow
    arrow_center_x = width // 2
    arrow_center_y = 190
    
    # Sleek arrow graphic
    # Shaft
    draw.rounded_rectangle(
        [(arrow_center_x - 30, arrow_center_y - 3), (arrow_center_x + 18, arrow_center_y + 3)],
        radius=3,
        fill=(255, 153, 51, 220) # Stanza vibrant orange
    )
    # Head
    draw.polygon(
        [
            (arrow_center_x + 14, arrow_center_y - 12),
            (arrow_center_x + 32, arrow_center_y),
            (arrow_center_x + 14, arrow_center_y + 12)
        ],
        fill=(255, 153, 51, 220)
    )

    output_path = os.path.join(os.path.dirname(__file__), "dmg_background.png")
    img.save(output_path, "PNG")
    print(f"Generated DMG background at {output_path}")

if __name__ == "__main__":
    generate_background()
