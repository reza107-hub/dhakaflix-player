"""Generates the app icon for Android, Linux and Windows from one design.
Run: python3 packaging/make_icons.py   (needs Pillow)"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG, RED, RING = (20, 20, 20, 255), (229, 9, 20, 255), (60, 60, 60, 255)

def icon(size, round_corners=True, pad=0.0):
    s = size * 4  # Draw large, then downscale for smooth edges.
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    p = int(s * pad)
    box = (p, p, s - p - 1, s - p - 1)
    if round_corners:
        d.rounded_rectangle(box, radius=int((s - 2 * p) * 0.22), fill=BG)
    else:
        d.rectangle((0, 0, s, s), fill=BG)
    w = s - 2 * p
    # Thin ring like a film reel, then a red play triangle, optically centred.
    m = w * 0.18
    d.ellipse((p + m, p + m, s - p - m, s - p - m), outline=RING, width=int(w * 0.035))
    cx, cy, r = s / 2 + w * 0.035, s / 2, w * 0.2
    d.polygon([(cx - r * 0.8, cy - r), (cx - r * 0.8, cy + r), (cx + r, cy)], fill=RED)
    return im.resize((size, size), Image.LANCZOS)

# Android launcher icons (legacy square-ish icons; Android 8+ masks them).
for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    out = ROOT / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png"
    icon(px, pad=0.04).save(out)

# Linux (hicolor theme) and repository icon.
(ROOT / "packaging/linux").mkdir(parents=True, exist_ok=True)
icon(256).save(ROOT / "packaging/linux/dhakaflix-player.png")
icon(512).save(ROOT / "packaging/icon-512.png")

# Windows .ico with the usual sizes.
icon(256).save(ROOT / "windows/runner/resources/app_icon.ico",
               sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icons written")
