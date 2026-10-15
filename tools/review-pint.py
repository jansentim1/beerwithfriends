#!/usr/bin/env python3
"""Draws functions/assets/review-pint.jpg, the review mate's drink photo.

A flat pint: amber body, white head band, on a dark bar-top background.
Re-run only if the picture should change: python3 tools/review-pint.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

W, H = 600, 800
img = Image.new("RGB", (W, H), (38, 28, 22))
d = ImageDraw.Draw(img)
glass = (150, 140, 450, 700)
d.rounded_rectangle(glass, radius=28, fill=(214, 140, 32))  # amber beer
d.rounded_rectangle((150, 140, 450, 250), radius=28, fill=(250, 246, 236))  # head
d.rectangle((150, 220, 450, 250), fill=(250, 246, 236))
for x, y in [(230, 400), (300, 520), (370, 450), (260, 610), (340, 330)]:
    d.ellipse((x - 6, y - 6, x + 6, y + 6), fill=(240, 180, 70))  # bubbles
d.rounded_rectangle(glass, radius=28, outline=(255, 255, 255), width=6)  # rim
out = Path(__file__).resolve().parent.parent / "functions" / "assets" / "review-pint.jpg"
out.parent.mkdir(exist_ok=True)
img.save(out, "JPEG", quality=80, optimize=True)
print(out, out.stat().st_size, "bytes")
