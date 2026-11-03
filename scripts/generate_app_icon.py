"""Generate the code-drawn SoNo ledger icon; no external artwork or fonts required."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "App/Assets.xcassets"


def artwork(size=1024):
    scale = 2
    canvas = Image.new("RGB", (size * scale, size * scale))
    drawing = ImageDraw.Draw(canvas)
    for y in range(size * scale):
        ratio = y / (size * scale - 1)
        color = tuple(round(a + (b - a) * ratio) for a, b in zip((20, 137, 131), (5, 69, 73)))
        drawing.line((0, y, size * scale, y), fill=color)

    def box(bounds, radius, color):
        drawing.rounded_rectangle(tuple(round(value * scale) for value in bounds), radius=radius * scale, fill=color)

    box((212, 166, 822, 874), 64, (4, 73, 77))
    box((194, 150, 804, 852), 64, (241, 250, 247))
    box((194, 150, 304, 852), 40, (191, 226, 214))
    drawing.rectangle((250 * scale, 150 * scale, 304 * scale, 852 * scale), fill=(191, 226, 214))
    box((358, 280, 680, 310), 15, (13, 107, 105))
    box((358, 380, 680, 410), 15, (13, 107, 105))
    box((358, 480, 570, 510), 15, (13, 107, 105))
    box((640, 150, 724, 278), 8, (239, 169, 83))
    drawing.ellipse((570 * scale, 602 * scale, 858 * scale, 890 * scale), fill=(239, 169, 83))
    drawing.line((643 * scale, 748 * scale, 693 * scale, 798 * scale, 791 * scale, 696 * scale), fill=(255, 255, 255), width=27 * scale, joint="curve")
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def generate():
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    output = CATALOG / "AppIcon.appiconset"
    output.mkdir(exist_ok=True)
    master = artwork()
    images = []
    for points in (20, 29, 40, 60):
        for scale in (2, 3):
            pixels = points * scale
            filename = f"AppIcon-{points}@{scale}x.png"
            master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(output / filename)
            images.append({"idiom": "iphone", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": filename})
    master.save(output / "AppIcon-1024.png")
    images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "AppIcon-1024.png"})
    (output / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    print("Generated 9 RGB app icons with no alpha channel.")


if __name__ == "__main__":
    generate()
