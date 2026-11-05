import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

src, texdir, out, view = sys.argv[1], Path(sys.argv[2]), sys.argv[3], sys.argv[4]
size = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5].isdigit() else 900
transparent = "--transparent" in sys.argv

groups, insts, mats = {}, [], {}
cur = None
for line in open(src):
    p = line.split()
    if p[0] == "group":
        cur = groups.setdefault(p[1], {}).setdefault(p[2], [])
    elif p[0] == "v":
        cur.append([float(x) for x in p[1:]])
    elif p[0] == "inst":
        insts.append((p[1], np.array([float(x) for x in p[2:11]]).reshape(3, 3),
                      np.array([float(x) for x in p[11:14]]), float(p[14])))
    elif p[0] == "mat":
        mats[p[1]] = (np.array([int(p[2]), int(p[3]), int(p[4])]) / 255.0, None if p[5] == "-" else p[5])

tex = {n: np.asarray(Image.open(texdir / f"{n}.png").convert("RGB")).astype(np.float32) / 255
       for n in ("carbon", "label")}

views = {
    "three_quarter": ((0.36, 0.27, 0.23), (0, 0, 0.0), 32),
    "front": ((0.32, 0.0, 0.05), (0, 0, 0.012), 30),
    "top": ((0.0001, 0.0, 0.45), (0, 0, 0), 32),
    "side": ((0.0, 0.33, 0.03), (0, 0, 0.015), 30),
    "rear": ((-0.25, -0.16, 0.14), (0, 0, 0.012), 30),
    "low": ((0.22, -0.22, -0.02), (0, 0, 0.01), 32),
    "detail": ((0.11, 0.10, 0.09), (-0.02, 0.0, 0.02), 32),
    "left": ((0.05, 0.30, 0.10), (-0.005, 0, 0.03), 26),
    "icon": ((0.29, 0.26, 0.20), (0.012, -0.012, 0.0), 37),
    "motor": ((0.175, -0.165, 0.040), (0.0636, -0.0636, -0.001), 24),
    "stack": ((0.03, -0.11, 0.06), (-0.02, 0.0, 0.01), 40),
}
if view == "fpv":
    t = math.radians(30)
    views["fpv"] = ((0.057, 0.0, 0.010), (0.057 + math.cos(t), 0.0, 0.010 + math.sin(t)), 104.8)
eye, target, fov = views[view]
eye, target = np.array(eye), np.array(target)
fwd = target - eye
fwd /= np.linalg.norm(fwd)
up0 = np.array([0, 0, 1.0]) if abs(fwd[2]) < 0.99 else np.array([1.0, 0, 0])
right = np.cross(fwd, up0); right /= np.linalg.norm(right)
up = np.cross(right, fwd)
SS = 2
H = size * SS
W = int(H * 16 / 9) if view == "fpv" else H
f = 1 / math.tan(math.radians(fov) / 2)

key = np.array([0.45, 0.35, 0.82]); key /= np.linalg.norm(key)
fill = np.array([-0.6, -0.5, 0.3]); fill /= np.linalg.norm(fill)

color = np.zeros((H, W, 3), np.float32)
alpha = np.zeros((H, W), np.float32)
zbuf = np.full((H, W), np.inf, np.float32)
if not transparent:
    gy = np.linspace(0, 1, H)[:, None]
    color[:] = (np.array([0.82, 0.84, 0.88]) * (1 - gy) + np.array([0.55, 0.57, 0.62]) * gy)[:, None, :].transpose(1, 0, 2).reshape(H, 1, 3) if False else 0
    base = np.array([0.80, 0.82, 0.86]) * (1 - gy[..., None]) + np.array([0.52, 0.54, 0.6]) * gy[..., None]
    color[:] = np.broadcast_to(base, (H, W, 3))
    alpha[:] = 1

ntri = 0
for part, R, T, sx in insts:
    S = np.diag([sx, 1, 1])
    M = R @ S
    for mname, verts in groups.get(part, {}).items():
        v = np.array(verts)
        P = v[:, :3] @ M.T + T
        N = v[:, 3:6] @ R.T
        UV = v[:, 6:8]
        base, texname = mats[mname]
        rel = P - eye
        cx, cy, cz = rel @ right, rel @ up, rel @ fwd
        sxp = (cx / cz * f) * (H / 2) + W / 2
        syp = H / 2 - (cy / cz * f) * (H / 2)
        for t in range(0, len(v), 3):
            ntri += 1
            xs, ys, zs = sxp[t:t + 3], syp[t:t + 3], cz[t:t + 3]
            if (zs <= 0.01).any():
                continue
            x0, x1 = int(max(0, math.floor(xs.min()))), int(min(W - 1, math.ceil(xs.max())))
            y0, y1 = int(max(0, math.floor(ys.min()))), int(min(H - 1, math.ceil(ys.max())))
            if x0 > x1 or y0 > y1:
                continue
            (ax, bx, cxx), (ay, by, cyy) = xs, ys
            den = (by - cyy) * (ax - cxx) + (cxx - bx) * (ay - cyy)
            if abs(den) < 1e-9:
                continue
            gx, gyy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            w0 = ((by - cyy) * (gx - cxx) + (cxx - bx) * (gyy - cyy)) / den
            w1 = ((cyy - ay) * (gx - cxx) + (ax - cxx) * (gyy - cyy)) / den
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
            if not inside.any():
                continue
            z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
            zb = zbuf[y0:y1 + 1, x0:x1 + 1]
            m = inside & (z < zb)
            if not m.any():
                continue
            n = (w0[..., None] * N[t] + w1[..., None] * N[t + 1] + w2[..., None] * N[t + 2])
            n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
            vdir = -(w0[..., None] * rel[t] + w1[..., None] * rel[t + 1] + w2[..., None] * rel[t + 2])
            flip = (n * vdir).sum(-1) < 0
            n[flip] *= -1
            lam = np.clip(n @ key, 0, 1) * 0.85 + np.clip(n @ fill, 0, 1) * 0.25 + 0.22
            if texname:
                uv = w0[..., None] * UV[t] + w1[..., None] * UV[t + 1] + w2[..., None] * UV[t + 2]
                img = tex[texname]
                ui = np.clip((uv[..., 0] % 1) * (img.shape[1] - 1), 0, img.shape[1] - 1).astype(int)
                vi = np.clip((uv[..., 1] % 1) * (img.shape[0] - 1), 0, img.shape[0] - 1).astype(int)
                col = img[vi, ui] * base
            else:
                col = np.broadcast_to(base, n.shape)
            h = key + vdir / (np.linalg.norm(vdir, axis=-1, keepdims=True) + 1e-9)
            h /= np.linalg.norm(h, axis=-1, keepdims=True) + 1e-9
            spec = np.clip((n * h).sum(-1), 0, 1) ** 40 * 0.25
            shaded = np.clip(col * lam[..., None] + spec[..., None], 0, 1)
            cblock = color[y0:y1 + 1, x0:x1 + 1]
            cblock[m] = shaded[m]
            zb[m] = z[m]
            alpha[y0:y1 + 1, x0:x1 + 1][m] = 1

img = np.concatenate([color, alpha[..., None]], -1)
img = img.reshape(H // SS, SS, W // SS, SS, 4).mean((1, 3))
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(out)
print(f"{out}: {ntri} triangles")
