#!/usr/bin/env python3
"""Three app icon candidates, 1024x1024 RGB, drawn with Pillow in the app's own
language: the pint silhouette from DrinkGlass, the one amber accent, no text.
Usage: python3 tools/icon/candidates.py <out dir>
"""
import sys, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = sys.argv[1]
AMBER = (230, 138, 0)        # Theme.accent (light)
AMBER_DEEP = (168, 92, 0)
CREAM = (255, 246, 228)
INK = (41, 23, 0)
FOAM = (255, 253, 246)
BEER = (247, 178, 46)
BEER_DEEP = (214, 137, 20)

def gradient(top, bot, radial=False):
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(S):
            px[x, y] = c
    return img

def pint_path(cx, base_y, h, w_top, w_bot):
    """Pint silhouette: slight taper, rounded bottom corners via many points."""
    top_y = base_y - h
    r = w_bot * 0.12
    pts = [(cx - w_top / 2, top_y), (cx + w_top / 2, top_y), (cx + w_bot / 2, base_y - r)]
    import math
    for a in range(0, 91, 10):
        t = math.radians(a)
        pts.append((cx + w_bot / 2 - r + r * math.cos(t), base_y - r + r * math.sin(t)))
    for a in range(90, 181, 10):
        t = math.radians(a)
        pts.append((cx - w_bot / 2 + r + r * math.cos(t), base_y - r + r * math.sin(t)))
    pts.append((cx - w_bot / 2, top_y))
    return pts

def level_y(pts, level):
    ys = [p[1] for p in pts]
    top, bot = min(ys), max(ys)
    return bot - (bot - top) * level

def filled_pint(img, cx, base_y, h, w_top, w_bot, level=0.78, stroke=INK, stroke_w=22, glass_fill=CREAM, tilt=0):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = pint_path(cx, base_y, h, w_top, w_bot)
    d.polygon(pts, fill=glass_fill + (255,))
    # beer: clip a rectangle to the silhouette
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    beer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(beer)
    ly = level_y(pts, level)
    bd.rectangle([0, ly, S, S], fill=BEER + (255,))
    bd.rectangle([0, ly, S, ly + h * 0.07], fill=FOAM + (255,))          # foam band
    bd.rectangle([0, ly, S, ly + 6], fill=(255, 255, 255, 255))
    beer.putalpha(Image.composite(mask, Image.new("L", (S, S), 0), beer.getchannel("A")))
    layer = Image.alpha_composite(layer, beer)
    d = ImageDraw.Draw(layer)
    d.line(pts + [pts[0]], fill=stroke + (255,), width=stroke_w, joint="curve")
    if tilt:
        layer = layer.rotate(tilt, resample=Image.BICUBIC, center=(cx, base_y - h / 2))
    img.paste(layer, (0, 0), layer)
    return img

def outline_pint(img, cx, base_y, h, w_top, w_bot, level=0.62, stroke=FOAM, stroke_w=34):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = pint_path(cx, base_y, h, w_top, w_bot)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    fill = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fill)
    ly = level_y(pts, level)
    fd.rectangle([0, ly, S, S], fill=FOAM + (70,))
    fd.rectangle([0, ly, S, ly + h * 0.06], fill=FOAM + (255,))
    fill.putalpha(Image.composite(mask, Image.new("L", (S, S), 0), fill.getchannel("A")))
    layer = Image.alpha_composite(layer, fill)
    d = ImageDraw.Draw(layer)
    d.line(pts + [pts[0]], fill=stroke + (255,), width=stroke_w, joint="curve")
    img.paste(layer, (0, 0), layer)
    return img

# A. One pint, cream glass with ink outline, on the amber accent. The drink picker, as an icon.
a = gradient((236, 148, 8), (222, 128, 0))
filled_pint(a, S / 2, 830, 610, 380, 320, level=0.78)
a.save(os.path.join(OUT, "icon-A-pint.png"))

# B. Line-art pint, foam-white stroke on deep amber: the drawn glasses of the app, one colour.
b = gradient((196, 106, 0), (150, 78, 0))
outline_pint(b, S / 2, 840, 620, 390, 330, level=0.62)
b.save(os.path.join(OUT, "icon-B-lineart.png"))

# C. Cheers: two pints tilting into each other on amber.
c = gradient((240, 152, 10), (218, 124, 0))
filled_pint(c, 400, 850, 520, 300, 250, level=0.74, tilt=14)
filled_pint(c, 624, 850, 520, 300, 250, level=0.74, tilt=-14)
c.save(os.path.join(OUT, "icon-C-cheers.png"))

# Contact sheet with rounded masks at 180 px, the size it is judged at.
sheet = Image.new("RGB", (3 * 260 + 40, 300), (242, 242, 247))
for i, name in enumerate(["icon-A-pint.png", "icon-B-lineart.png", "icon-C-cheers.png"]):
    im = Image.open(os.path.join(OUT, name)).resize((180, 180), Image.LANCZOS)
    m = Image.new("L", (180, 180), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, 179, 179], radius=40, fill=255)
    sheet.paste(im, (40 + i * 260, 60), m)
sheet.save(os.path.join(OUT, "icon-candidates.png"))
print("ok")
