import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
OUT.mkdir(parents=True, exist_ok=True)
FONT_BI = "/usr/share/fonts/truetype/google-fonts/Poppins-BoldItalic.ttf"
FONT_B = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
FONT_M = "/usr/share/fonts/truetype/google-fonts/Poppins-Medium.ttf"
ORANGE = (255, 92, 16)

def carbon(size=1024, cell=12):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    ci, cj = (x // cell).astype(int), (y // cell).astype(int)
    fx, fy = (x % cell) / cell, (y % cell) / cell
    horiz = ((ci + cj) % 4) < 2
    across = np.where(horiz, fy, fx)
    along = np.where(horiz, fx, fy)
    tow = np.sin(np.pi * across) ** 0.6
    sheen = np.where(horiz, 1.0, 0.82)
    edge = 1 - 0.35 * (np.abs(along - 0.5) * 2) ** 6
    rng = np.random.default_rng(7)
    noise = rng.normal(0, 0.02, (size, size)).astype(np.float32)
    v = 18 + 34 * tow * sheen * edge + 255 * noise * 0.4
    v = np.clip(v, 8, 70)
    img = np.stack([v * 0.97, v * 0.98, v * 1.04], axis=-1)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(OUT / "carbon.png")

def perimeter_fractions():
    by, bz0, bz1, r, cs = 0.0175, 0.0195, 0.0585, 0.0052, 6
    x0, y0, x1, y1 = -by, bz0, by, bz1
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -math.pi / 2), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, math.pi / 2), (x0 + r, y0 + r, math.pi)):
        for k in range(cs + 1):
            a = a0 + k / cs * math.pi / 2
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    pts.insert(0, (0.0, bz0))
    per = [0.0]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        per.append(per[-1] + math.dist(a, b))
    tot = per[-1]
    def frac_of(pred):
        idx = [i for i, p in enumerate(pts) if pred(p)]
        return per[min(idx)] / tot, per[max(idx)] / tot
    side_p = frac_of(lambda p: abs(p[0] - by) < 1e-9)
    top = frac_of(lambda p: abs(p[1] - bz1) < 1e-9)
    side_n = frac_of(lambda p: abs(p[0] + by) < 1e-9)
    return side_p, top, side_n

def text_img(text, font, fill, pad=4):
    bbox = font.getbbox(text)
    w, h = bbox[2] - bbox[0] + pad * 2, bbox[3] - bbox[1] + pad * 2
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad - bbox[0], pad - bbox[1]), text, font=font, fill=fill)
    return im

PX_PER_MM = 12
PACK_LEN_MM = 72.0
SIDE_MM = 29.0
STRAP_U = (0.653, 0.867)

def side_panel(front_on_right=True):
    w, h = int(PACK_LEN_MM * PX_PER_MM), int(SIDE_MM * PX_PER_MM)
    im = Image.new("RGBA", (w, h), (26, 26, 28, 255))
    d = ImageDraw.Draw(im)
    mm = PX_PER_MM
    def X(x):
        return x if front_on_right else w - x
    fx = int(w * ((STRAP_U[1] - 0.02) / 0.96)) + int(1 * mm)
    d.polygon([(X(fx + int(4 * mm)), 0), (X(w), 0), (X(w), h), (X(fx), h)], fill=ORANGE + (255,))
    a, b = X(int(2 * mm)), X(int(44 * mm))
    d.rectangle([min(a, b), int(19.2 * mm), max(a, b), int(19.9 * mm)], fill=ORANGE + (255,))
    big = ImageFont.truetype(FONT_BI, int(10.5 * mm))
    t = text_img("MAYHEM", big, (245, 245, 245, 255))
    scale = (42 * mm) / t.width
    t = t.resize((int(t.width * scale), int(t.height * scale)), Image.LANCZOS)
    tx = int(2 * mm) if front_on_right else w - int(2 * mm) - t.width
    im.alpha_composite(t, (tx, int(5 * mm)))
    small = ImageFont.truetype(FONT_M, int(3.0 * mm))
    s = text_img("6S  1400mAh  22.2V  120C", small, (200, 200, 205, 255))
    sx = int(2.3 * mm) if front_on_right else w - int(2.3 * mm) - s.width
    im.alpha_composite(s, (sx, int(21 * mm)))
    return im

def label(W=1024, H=1024):
    img = Image.new("RGBA", (W, H), (22, 22, 24, 255))
    (sp0, sp1), (t0, t1), (sn0, sn1) = perimeter_fractions()
    u0, u1 = int(0.02 * W), int(0.98 * W)
    y0, y1 = int(sn0 * H), int(sn1 * H)
    img.alpha_composite(side_panel(True).resize((u1 - u0, y1 - y0), Image.LANCZOS), (u0, y0))
    y0, y1 = int(sp0 * H), int(sp1 * H)
    img.alpha_composite(side_panel(False).rotate(180).resize((u1 - u0, y1 - y0), Image.LANCZOS), (u0, y0))
    y0, y1 = int(t0 * H), int(t1 * H)
    d = ImageDraw.Draw(img)
    mid = (y0 + y1) // 2
    tw, th = int(PACK_LEN_MM * PX_PER_MM), int(25 * PX_PER_MM)
    top = Image.new("RGBA", (tw, th), (22, 22, 24, 255))
    td = ImageDraw.Draw(top)
    c = th // 2
    mm = PX_PER_MM
    td.rectangle([0, c - int(2.5 * mm), tw, c + int(2.5 * mm)], fill=ORANGE + (255,))
    td.rectangle([0, c - int(4.2 * mm), tw, c - int(3.6 * mm)], fill=ORANGE + (255,))
    td.rectangle([0, c + int(3.6 * mm), tw, c + int(4.2 * mm)], fill=ORANGE + (255,))
    logo = text_img("X5", ImageFont.truetype(FONT_BI, int(12 * mm)), (245, 245, 245, 255))
    logo = logo.rotate(-90, expand=True)
    bx = int(tw * 0.10)
    td.rectangle([bx - int(1.5 * mm), 0, bx + logo.width + int(1.5 * mm), th], fill=(22, 22, 24, 255))
    top.alpha_composite(logo, (bx, c - logo.height // 2))
    img.alpha_composite(top.resize((u1 - u0, y1 - y0), Image.LANCZOS), (u0, y0))
    d.rectangle([0, 0, u0, H], fill=(18, 18, 19, 255))
    d.rectangle([u1, 0, W, H], fill=(18, 18, 19, 255))
    img.convert("RGB").save(OUT / "label.png")

def icon_bg(size=512):
    pass

if __name__ == "__main__":
    carbon()
    label()
    print("textures written to", OUT)
