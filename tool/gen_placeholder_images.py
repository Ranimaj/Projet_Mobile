"""Generate placeholder onboarding images (abstract, orange palette).

Usage: python3 tool/gen_placeholder_images.py
Replace the output files with real campus photos when available
(1080 x 1350 px JPEG, <= 200 KB each).
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 1080, 1350
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "images", "onboarding")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(top, bottom):
    img = Image.new("RGB", (W, H))
    px = ImageDraw.Draw(img)
    for y in range(H):
        px.line([(0, y), (W, y)], fill=lerp(top, bottom, y / (H - 1)))
    return img


def circles(img, seed, count, colors):
    rnd = random.Random(seed)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        r = rnd.randint(120, 420)
        x, y = rnd.randint(-100, W + 100), rnd.randint(-100, H + 100)
        c = rnd.choice(colors) + (rnd.randint(40, 110),)
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(6))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


ORANGE, PEACH, DARK = (0xF9, 0x67, 0x1E), (0xFF, 0xB3, 0x80), (0x12, 0x12, 0x14)
WHITE = (255, 255, 255)

SPECS = [
    ("campus_1.jpg", ORANGE, PEACH, 1, [WHITE, ORANGE, PEACH]),
    ("campus_2.jpg", DARK, ORANGE, 2, [ORANGE, PEACH, WHITE]),
    ("campus_3.jpg", PEACH, DARK, 3, [WHITE, ORANGE, DARK]),
]

os.makedirs(OUT, exist_ok=True)
for name, top, bottom, seed, palette in SPECS:
    img = circles(gradient(top, bottom), seed, 7, palette)
    path = os.path.join(OUT, name)
    img.save(path, "JPEG", quality=80, optimize=True)
    print(name, os.path.getsize(path) // 1024, "KB")
