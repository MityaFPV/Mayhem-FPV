import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PNG_OUT, LUA_OUT = sys.argv[1], sys.argv[2]
PREVIEW = sys.argv[3] if len(sys.argv) > 3 else None

GW, GH = 12, 18
CW, CH = 16, 32
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

MICRO = {
    "M": ["X.X", "XXX", "X.X", "X.X", "X.X"], "A": [".X.", "X.X", "XXX", "X.X", "X.X"],
    "H": ["X.X", "X.X", "XXX", "X.X", "X.X"], "K": ["X.X", "X.X", "XX.", "X.X", "X.X"],
    "W": ["X.X", "X.X", "X.X", "XXX", "X.X"], "L": ["X..", "X..", "X..", "X..", "XXX"],
    "Q": ["XXX", "X.X", "X.X", "XX.", ".XX"], "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
    "R": ["XX.", "X.X", "XX.", "X.X", "X.X"], "F": ["XXX", "X..", "XX.", "X..", "X.."],
    "Y": ["X.X", "X.X", ".X.", ".X.", ".X."], "O": ["XXX", "X.X", "X.X", "X.X", "XXX"],
    "N": ["XX.", "X.X", "X.X", "X.X", "X.X"], "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
    "B": ["XX.", "X.X", "XX.", "X.X", "XX."], "C": ["XXX", "X..", "X..", "X..", "XXX"],
    "V": ["X.X", "X.X", "X.X", "X.X", ".X."], "/": ["..X", "..X", ".X.", "X..", "X.."],
    "P": ["XX.", "X.X", "XX.", "X..", "X.."], "G": ["XXX", "X..", "X.X", "X.X", "XXX"],
    "S": ["XXX", "X..", "XXX", "..X", "XXX"], "E": ["XXX", "X..", "XX.", "X..", "XXX"],
    "X": ["X.X", "X.X", ".X.", "X.X", "X.X"],
}

def blank():
    return np.zeros((GH, GW), bool)

def micro(mask, text, x, y):
    for ch in text:
        pat = MICRO[ch]
        for r, line in enumerate(pat):
            for c, v in enumerate(line):
                if v == "X" and 0 <= y + r < GH and 0 <= x + c < GW:
                    mask[y + r, x + c] = True
        x += 4

def rect(mask, x0, y0, x1, y1):
    mask[max(0, y0):min(GH, y1 + 1), max(0, x0):min(GW, x1 + 1)] = True

def ascii_glyph(ch, font):
    big = Image.new("L", (GW * 4, GH * 4), 0)
    d = ImageDraw.Draw(big)
    bbox = d.textbbox((0, 0), ch, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    hb = d.textbbox((0, 0), "H", font=font)
    x = (GW * 4 - (bbox[2] - bbox[0])) / 2 - bbox[0]
    y = (GH * 4 - (hb[3] - hb[1])) / 2 - hb[1]
    d.text((x, y), ch, font=font, fill=255)
    small = np.asarray(big.resize((GW, GH), Image.BOX)).astype(np.float32) / 255
    return small > 0.42

glyphs = {}
font = ImageFont.truetype(FONT, 66)
for code in range(32, 127):
    ch = chr(code)
    glyphs[code] = blank() if ch == " " else ascii_glyph(ch.upper() if ch.isalpha() else ch, font)

icons = {}
nxt = [128]

def icon(name, mask):
    icons[name] = nxt[0]
    glyphs[nxt[0]] = mask
    nxt[0] += 1

raw = {}

def icon_raw(name, rows):
    rows = ["." * GW] * ((GH - len(rows)) // 2) + rows
    rows = rows + ["." * GW] * (GH - len(rows))
    white, black = blank(), blank()
    for y, line in enumerate(rows):
        for x, ch in enumerate(line):
            white[y, x] = ch == "O"
            black[y, x] = ch == "#"
    icon(name, white)
    raw[icons[name]] = black

for level in range(7):
    m = blank()
    rect(m, 4, 1, 7, 2)
    rect(m, 2, 3, 9, 3); rect(m, 2, 16, 9, 16)
    rect(m, 2, 3, 2, 16); rect(m, 9, 3, 9, 16)
    fill = round(level / 6 * 11)
    if fill > 0:
        rect(m, 4, 15 - fill + 1, 7, 14)
    icon(f"BATT{level}", m)

def unit(name, text, y=11):
    m = blank()
    micro(m, text, (GW - (len(text) * 4 - 1)) // 2, y)
    icon(name, m)

unit("VOLT", "V")
unit("AMP", "A")
m = blank(); micro(m, "MA", 2, 4); micro(m, "H", 4, 11); icon("MAH", m)
unit("WATT", "W")
m = blank(); rect(m, 1, 4, 3, 4); rect(m, 1, 6, 3, 6); rect(m, 1, 4, 1, 6); rect(m, 3, 4, 3, 6); micro(m, "C", 6, 9); icon("TEMPC", m)
m = blank(); micro(m, "KM", 2, 3); micro(m, "/H", 2, 11); icon("KPH", m)
unit("METER", "M")

def clock(m):
    yy, xx = np.mgrid[0:GH, 0:GW]
    r = np.sqrt((xx - 5.5) ** 2 + (yy - 9) ** 2)
    m |= (r > 3.6) & (r < 5.0)
    rect(m, 5, 6, 6, 9); rect(m, 6, 9, 8, 9)
    return m

icon("FLY", clock(blank()))
m = blank(); micro(m, "ON", 2, 1); icon("ON", m)
m = blank(); micro(m, "THR", 0, 7); icon("THR", m)
m = blank(); micro(m, "LQ", 2, 7); icon("LQ", m)
m = blank()
rect(m, 5, 6, 6, 15)
for k in range(4):
    rect(m, 1 + k, 2 + k, 1 + k, 2 + k); rect(m, 10 - k, 2 + k, 10 - k, 2 + k)
icon("RSSI", m)
m = blank(); micro(m, "DBM", 0, 7); icon("DBM", m)
m = blank()
rect(m, 5, 4, 6, 14); rect(m, 2, 15, 9, 15)
for k in range(3):
    rect(m, 5 - k - 1, 5 + k, 5 - k - 1, 5 + k); rect(m, 6 + k + 1, 5 + k, 6 + k + 1, 5 + k)
icon("ALT", m)
m = blank()
for k in range(4):
    rect(m, 2 + k, 5 + k, 3 + k, 5 + k); rect(m, 2 + k, 13 - k, 3 + k, 13 - k)
    rect(m, 6 + k, 5 + k, 7 + k, 5 + k); rect(m, 6 + k, 13 - k, 7 + k, 13 - k)
icon("SPEED", m)
m = blank(); micro(m, "G", 4, 7); icon("GFORCE", m)
E = "............"
icon_raw("CROSS_L", [E, E, E, E, E, E, "........#O.#", "........#O.#", E, E, E, E, E, E])
icon_raw("CROSS_C", [
    ".....##.....",
    ".....OO.....",
    "............",
    ".....##.....",
    "....#OO#....",
    "...#O##O#...",
    "O.#O#..#O#.O",
    "O.#O#..#O#.O",
    "...#O##O#...",
    "....#OO#....",
    ".....##.....",
    "............",
    ".....OO.....",
    ".....##.....",
])
icon_raw("CROSS_R", [E, E, E, E, E, E, "#.O#........", "#.O#........", E, E, E, E, E, E])
for k in range(9):
    m = blank(); y = 1 + k * 2; rect(m, 0, y, 11, y); icon(f"AH{k}", m)
m = blank(); rect(m, 4, 9, 7, 9); icon("AH_DECOR", m)
m = blank()
for k in range(4): rect(m, 7 - k, 9 - k, 7 - k, 9 + k)
icon("AH_LEFT", m)
m = blank()
for k in range(4): rect(m, 4 + k, 9 - k, 4 + k, 9 + k)
icon("AH_RIGHT", m)
m = blank(); rect(m, 5, 9, 6, 9); rect(m, 3, 9, 8, 9); rect(m, 5, 7, 6, 11); icon("STICK_CENTER", m)
m = blank(); rect(m, 5, 0, 6, 17); icon("STICK_VERT", m)
m = blank(); rect(m, 0, 8, 11, 9); icon("STICK_HORIZ", m)
for name, y in (("STICK_HIGH", 2), ("STICK_MID", 7), ("STICK_LOW", 12)):
    m = blank(); rect(m, 3, y, 8, y + 4); icon(name, m)
m = blank(); rect(m, 4, 4, 5, 14); rect(m, 4, 4, 11, 4); rect(m, 4, 14, 11, 14); rect(m, 7, 7, 11, 11); icon("PB_START", m)
m = blank(); rect(m, 0, 4, 11, 4); rect(m, 0, 14, 11, 14); rect(m, 0, 7, 11, 11); icon("PB_FULL", m)
m = blank(); rect(m, 0, 4, 11, 4); rect(m, 0, 14, 11, 14); icon("PB_EMPTY", m)
m = blank(); rect(m, 6, 4, 7, 14); rect(m, 0, 4, 7, 4); rect(m, 0, 14, 7, 14); icon("PB_END", m)
m = blank(); micro(m, "VTX", 0, 7); icon("VTX", m)

atlas = np.zeros((16 * CH, 16 * CW, 4), np.uint8)
for code, mask in glyphs.items():
    pad = np.pad(mask, 1)
    dil = np.zeros_like(pad)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            dil |= np.roll(np.roll(pad, dy, 0), dx, 1)
    dil = dil[1:-1, 1:-1]
    if code in raw:
        dil = raw[code]
    cell = np.zeros((GH, GW, 4), np.uint8)
    cell[dil] = (0, 0, 0, 255)
    cell[mask] = (255, 255, 255, 255)
    r, c = divmod(code, 16)
    atlas[r * CH:r * CH + GH, c * CW:c * CW + GW] = cell
Image.fromarray(atlas, "RGBA").save(PNG_OUT)

with open(LUA_OUT, "w") as f:
    f.write("local FPV = MayhemFPV\n")
    f.write(f"FPV.OSDFont = {{\n    glyphW = {GW}, glyphH = {GH}, cellW = {CW}, cellH = {CH}, atlasW = {16 * CW}, atlasH = {16 * CH},\n")
    f.write("    icon = {\n")
    for name, code in icons.items():
        f.write(f"        {name} = {code},\n")
    f.write("    },\n}\n")

if PREVIEW:
    sel = list(range(48, 58)) + list(range(65, 91)) + list(icons.values())
    cols = 20
    rows = (len(sel) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (GW + 2) * 4, rows * (GH + 2) * 4), (90, 120, 150, 255))
    src = Image.fromarray(atlas, "RGBA")
    for i, code in enumerate(sel):
        r, c = divmod(code, 16)
        g = src.crop((c * CW, r * CH, c * CW + GW, r * CH + GH)).resize((GW * 4, GH * 4), Image.NEAREST)
        rr, cc = divmod(i, cols)
        sheet.alpha_composite(g, (cc * (GW + 2) * 4, rr * (GH + 2) * 4))
    sheet.save(PREVIEW)
print(f"{len(glyphs)} glyphs, {len(icons)} icons")
