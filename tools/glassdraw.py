"""Draw DrinkGlass bowl paths locally, same unit box (0..1, y down) as the Swift."""
from PIL import Image, ImageDraw, ImageFont
import sys, math

class P:
    def __init__(s, w, h, ox, oy): s.w, s.h, s.ox, s.oy = w, h, ox, oy; s.pts=[]; s.cur=None
    def p(s, x, y): return (s.ox + x*s.w, s.oy + y*s.h)
    def move(s, x, y): s.cur = s.p(x,y); s.pts.append(s.cur)
    def line(s, x, y): s.cur = s.p(x,y); s.pts.append(s.cur)
    def quad(s, x, y, cx, cy):
        p0, c, p1 = s.cur, s.p(cx,cy), s.p(x,y)
        for i in range(1, 17):
            t=i/16; mt=1-t
            s.pts.append((mt*mt*p0[0]+2*mt*t*c[0]+t*t*p1[0], mt*mt*p0[1]+2*mt*t*c[1]+t*t*p1[1]))
        s.cur = p1
    def curve(s, x, y, c1x, c1y, c2x, c2y):
        p0, a, b, p1 = s.cur, s.p(c1x,c1y), s.p(c2x,c2y), s.p(x,y)
        for i in range(1, 25):
            t=i/24; mt=1-t
            s.pts.append((mt**3*p0[0]+3*mt*mt*t*a[0]+3*mt*t*t*b[0]+t**3*p1[0],
                          mt**3*p0[1]+3*mt*mt*t*a[1]+3*mt*t*t*b[1]+t**3*p1[1]))
        s.cur = p1

def pils(g):
    g.move(0.07,0.02); g.line(0.93,0.02); g.line(0.80,0.92)
    g.quad(0.72,0.97, 0.79,0.97); g.line(0.28,0.97); g.quad(0.20,0.92, 0.21,0.97)

def pint(g):
    # gentle nonic ledge: 5% out, then straight down
    g.move(0.13,0.03); g.line(0.87,0.03); g.line(0.88,0.24); g.line(0.94,0.30)
    g.line(0.87,0.36); g.line(0.82,0.90)
    g.quad(0.74,0.96, 0.81,0.96); g.line(0.26,0.96); g.quad(0.18,0.90, 0.19,0.96)
    g.line(0.13,0.36); g.line(0.06,0.30); g.line(0.12,0.24)

def stein(g):
    g.move(0.08,0.05); g.line(0.64,0.05); g.line(0.64,0.88)
    g.quad(0.56,0.95, 0.64,0.95); g.line(0.16,0.95); g.quad(0.08,0.88, 0.08,0.95)

def stein_handle(g):
    g.move(0.64,0.24); g.line(0.86,0.30); g.quad(0.92,0.46, 0.93,0.36)
    g.quad(0.84,0.62, 0.91,0.58); g.line(0.64,0.70)

def stout(g):
    # tulip pint: wide rim easing to a shallow waist, then straight to the base
    g.move(0.06,0.03); g.line(0.94,0.03)
    g.curve(0.82,0.52, 0.92,0.22, 0.83,0.36)
    g.line(0.80,0.90); g.quad(0.72,0.96, 0.79,0.96); g.line(0.28,0.96)
    g.quad(0.20,0.90, 0.21,0.96); g.line(0.18,0.52)
    g.curve(0.06,0.03, 0.17,0.36, 0.08,0.22)

SHAPES = {"pils":(pils,0.56), "pint":(pint,0.62), "stein":(stein,0.78), "stout":(stout,0.62)}

def render(names, out, variants=None):
    H=260; pad=46; cellw=200
    img=Image.new("RGB",(cellw*len(names), H+50),(242,242,247)); d=ImageDraw.Draw(img)
    for i,n in enumerate(names):
        fn, ratio = (variants or SHAPES)[n]
        h=H-2*pad; w=h*ratio
        g=P(w,h, i*cellw+(cellw-w)/2, pad)
        fn(g)
        d.polygon(g.pts, fill=(232,232,236), outline=(90,90,95))
        d.line(g.pts+[g.pts[0]], fill=(90,90,95), width=3)
        if n == "stein":
            hg=P(w,h, i*cellw+(cellw-w)/2, pad); stein_handle(hg)
            d.line(hg.pts, fill=(90,90,95), width=3, joint="curve")
        d.text((i*cellw+cellw/2-20, H+4), n, fill=(60,60,67))
    img.save(out)
render(["pils","pint","stein","stout"], sys.argv[1] if len(sys.argv)>1 else "/tmp/g.png")
