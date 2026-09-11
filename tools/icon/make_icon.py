#!/usr/bin/env python3
"""LEGACY placeholder generator; the shipped icon is candidate A from tools/icon/candidates.js.
Two clinking pints on a warm amber gradient. Pure Pillow, no fonts needed.
Usage: python3 tools/icon/make_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import sys, math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S))
px = img.load()
# Vertical gradient: deep amber -> warm orange
top, bot = (196, 92, 16), (247, 165, 46)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(S):
        px[x, y] = c

d = ImageDraw.Draw(img)

def pint(cx, base_y, h, w_top, w_bot, tilt_deg, beer=(255, 194, 41), glass=(255, 248, 230), foam=(255, 255, 255)):
    """Draw a tilted pint glass as a layer, then composite."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    top_y = base_y - h
    # glass body (trapezoid)
    body = [(cx - w_top / 2, top_y), (cx + w_top / 2, top_y), (cx + w_bot / 2, base_y), (cx - w_bot / 2, base_y)]
    ld.polygon(body, fill=glass + (255,))
    # beer fill (lower ~72%)
    fill_top = top_y + h * 0.28
    k = (fill_top - top_y) / h
    wl = w_top + (w_bot - w_top) * k
    ld.polygon([(cx - wl / 2 + 14, fill_top), (cx + wl / 2 - 14, fill_top), (cx + w_bot / 2 - 14, base_y - 14), (cx - w_bot / 2 + 14, base_y - 14)], fill=beer + (255,))
    # foam head: overlapping circles above the fill line
    r = w_top * 0.16
    for i in range(-2, 3):
        ox = cx + i * r * 1.35
        oy = fill_top - r * 0.45 + (r * 0.25 if i % 2 else 0)
        ld.ellipse([ox - r, oy - r, ox + r, oy + r], fill=foam + (255,))
    ld.rectangle([cx - wl / 2 + 14, fill_top - r * 0.2, cx + wl / 2 - 14, fill_top + 6], fill=foam + (255,))
    # highlight stripe
    ld.polygon([(cx - w_top / 2 + 36, top_y + 40), (cx - w_top / 2 + 76, top_y + 40), (cx - w_bot / 2 + 66, base_y - 40), (cx - w_bot / 2 + 30, base_y - 40)], fill=(255, 255, 255, 90))
    # soft shadow
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(18))
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(shadow.point(lambda a: int(a * 0.35)))
    sh = sh.rotate(tilt_deg, center=(cx, base_y), resample=Image.BICUBIC)
    layer = layer.rotate(tilt_deg, center=(cx, base_y), resample=Image.BICUBIC)
    img.paste(sh, (12, 22), sh)
    img.paste(layer, (0, 0), layer)

pint(cx=392, base_y=800, h=470, w_top=300, w_bot=230, tilt_deg=14)
pint(cx=632, base_y=800, h=470, w_top=300, w_bot=230, tilt_deg=-14)

# a few sparkle dots where the glasses meet
d = ImageDraw.Draw(img)
for (x, y, r) in [(512, 300, 14), (470, 250, 9), (556, 262, 9), (512, 222, 6)]:
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255))

img.save(sys.argv[1], "PNG", optimize=True)
print("wrote", sys.argv[1], img.size, img.mode)
