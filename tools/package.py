import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "addon" / "mayhem_fpv"
DLL = ROOT / "module" / "build" / "gmcl_fpvjoy_win64.dll"
DIST = ROOT / "dist"

version = re.search(r'FPV\.Version = "([^"]+)"', (ADDON / "gamemodes/mayhemfpv/gamemode/shared.lua").read_text()).group(1)
if not DLL.exists():
    sys.exit("module/build/gmcl_fpvjoy_win64.dll is missing: build the module first (module/build_cross.sh or CMake)")

if DIST.exists():
    shutil.rmtree(DIST)
DIST.mkdir()

def add_tree(z, src, arc):
    for f in sorted(src.rglob("*")):
        if f.is_file():
            z.write(f, f"{arc}/{f.relative_to(src).as_posix()}")

install = DIST / f"mayhem-fpv-v{version}.zip"
with zipfile.ZipFile(install, "w", zipfile.ZIP_DEFLATED) as z:
    add_tree(z, ADDON, "garrysmod/addons/mayhem_fpv")
    z.write(DLL, "garrysmod/lua/bin/gmcl_fpvjoy_win64.dll")
    z.writestr("garrysmod/sound/mayhem_music/PUT_MUSIC_HERE.txt",
               "Drop mp3 / ogg / wav files here, then Settings > Music > Rescan.\r\n")

shutil.copy(DLL, DIST / "gmcl_fpvjoy_win64.dll")

ws = DIST / "workshop" / "mayhem_fpv"
subprocess.run([sys.executable, str(ROOT / "tools" / "make_workshop.py"), str(ADDON), str(ws),
                str(ROOT / "branding" / "mayhem_fpv_icon.png")], check=True)

for f in sorted(DIST.iterdir()):
    print(f"{f.name}  {f.stat().st_size / 1e6:.1f} MB" if f.is_file() else f"{f.name}/")
