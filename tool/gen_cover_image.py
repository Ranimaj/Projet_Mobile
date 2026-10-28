"""Generate the placeholder profile cover (abstract, orange palette).

Usage: python3 tool/gen_cover_image.py
Replace assets/images/cover_campus.jpg with a real campus photo when available
(1080 x 600 px JPEG, <= 200 KB).
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 1080, 600
ORANGE, PEACH, DARK = (0xF9, 0x67, 0x1E), (0xFF, 0xB3, 0x80), (0x12, 0x12, 0x14)
WHITE = (255, 255, 255)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "cover_campus.jpg")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGB", (W, H))
px = ImageDraw.Draw(img)
for y in range(H):
    px.line([(0, y), (W, y)], fill=lerp(ORANGE, DARK, y / (H - 1)))

rnd = random.Random(7)
layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
for _ in range(8):
    r = rnd.randint(100, 320)
    x, y = rnd.randint(-100, W + 100), rnd.randint(-100, H + 100)
    c = rnd.choice([PEACH, ORANGE, WHITE]) + (rnd.randint(40, 110),)
    d.ellipse([x - r, y - r, x + r, y + r], fill=c)
layer = layer.filter(ImageFilter.GaussianBlur(6))
out = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
out.save(OUT, "JPEG", quality=80, optimize=True)
print("cover_campus.jpg", os.path.getsize(OUT) // 1024, "KB")
