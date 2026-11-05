import fnmatch
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

src, out, icon = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])

ALLOW = [
    "lua/*.lua", "sound/*.wav", "sound/*.mp3", "sound/*.ogg",
    "materials/*.vmt", "materials/*.vtf", "materials/*.png", "materials/*.jpg", "materials/*.jpeg",
    "gamemodes/*/*.txt", "gamemodes/*/logo.png", "gamemodes/*/icon24.png",
    "gamemodes/*/gamemode/*.lua", "gamemodes/*/entities/effects/*.lua",
    "gamemodes/*/entities/weapons/*.lua", "gamemodes/*/entities/entities/*.lua",
    "gamemodes/*/backgrounds/*.png", "gamemodes/*/backgrounds/*.jpg",
]
DENY = ["gamemodes/*/*/*.txt"]

def allowed(rel):
    ok = any(fnmatch.fnmatchcase(rel, p) for p in ALLOW)
    if any(fnmatch.fnmatchcase(rel, p) for p in DENY):
        ok = False
    return ok

if out.exists():
    shutil.rmtree(out)
shutil.copytree(src, out)
meta = json.loads((out / "addon.json").read_text())
ignore = meta.get("ignore", [])
bad, total, size = [], 0, 0
for f in sorted(out.rglob("*")):
    if not f.is_file():
        continue
    rel = f.relative_to(out).as_posix()
    if rel == "addon.json" or any(fnmatch.fnmatchcase(rel, p) or fnmatch.fnmatchcase(f.name, p) for p in ignore):
        continue
    if rel != rel.lower():
        bad.append(rel + "  (upper case in path: GMod lowercases Workshop paths)")
    elif not allowed(rel):
        bad.append(rel)
    total += 1
    size += f.stat().st_size

im = Image.open(icon).convert("RGBA")
bg = Image.new("RGBA", im.size, (22, 23, 28, 255))
bg.alpha_composite(im)
bg.convert("RGB").resize((512, 512), Image.LANCZOS).save(out.parent / "workshop_icon.jpg", quality=92)

print(f"{total} files, {size / 1e6:.1f} MB")
if bad:
    print("NOT ALLOWED ON THE WORKSHOP:")
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("all files pass the Workshop whitelist")
