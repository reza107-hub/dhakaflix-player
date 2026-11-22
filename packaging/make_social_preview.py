"""Social preview image for GitHub (1280x640). Run: python3 packaging/make_social_preview.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
W, H = 1280, 640
im = Image.new("RGB", (W, H), (18, 18, 18))
d = ImageDraw.Draw(im)
font = str(ROOT / "assets/fonts/NotoSans-Regular.ttf")
icon = Image.open(ROOT / "packaging/icon-512.png").resize((300, 300), Image.LANCZOS)
im.paste(icon, (110, (H - 300) // 2), icon)
x = 470
d.text((x, 190), "DhakaFlix Player", font=ImageFont.truetype(font, 78), fill=(255, 255, 255))
d.text((x, 300), "Unofficial lightweight player for", font=ImageFont.truetype(font, 34), fill=(200, 200, 200))
d.text((x, 345), "DhakaFlix (h5ai) servers", font=ImageFont.truetype(font, 34), fill=(200, 200, 200))
d.text((x, 420), "Android  ·  Windows  ·  Linux", font=ImageFont.truetype(font, 30), fill=(229, 9, 20))
d.rectangle((0, H - 8, W, H), fill=(229, 9, 20))
out = ROOT / "docs/social-preview.png"
out.parent.mkdir(exist_ok=True)
im.save(out, optimize=True)
print(out)
