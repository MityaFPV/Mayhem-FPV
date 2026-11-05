local Model = {}

local sin, cos, pi, sqrt, abs, min, max, floor = math.sin, math.cos, math.pi, math.sqrt, math.abs, math.min, math.max, math.floor

Model.MATERIALS = {
    carbon   = { tex = "carbon", color = { 255, 255, 255 } },
    label    = { tex = "label", color = { 255, 255, 255 } },
    slot     = { color = { 12, 12, 13 } },
    black    = { color = { 24, 24, 26 } },
    gunmetal = { color = { 62, 62, 68 } },
    orange   = { color = { 255, 92, 16 } },
    prop     = { color = { 255, 112, 22 } },
    propSmoke = { color = { 44, 46, 54 } },
    braid    = { color = { 214, 104, 30 } },
    led      = { color = { 250, 252, 255 } },
    cam      = { color = { 30, 30, 33 } },
    screen   = { color = { 18, 26, 40 } },
    chip     = { color = { 16, 16, 18 } },
    magnet   = { color = { 70, 72, 78 } },
    capblue  = { color = { 30, 70, 150 } },
    strap    = { color = { 36, 36, 38 } },
    lens     = { color = { 60, 90, 150 } },
    ledgreen = { color = { 60, 255, 120 } },
    ledblue  = { color = { 70, 140, 255 } },
    silver   = { color = { 188, 188, 194 } },
    copper   = { color = { 128, 70, 36 } },
    pcb      = { color = { 20, 24, 28 } },
    pcbblue  = { color = { 22, 38, 78 } },
    yellow   = { color = { 238, 192, 28 } },
    red      = { color = { 196, 30, 30 } },
    white    = { color = { 222, 222, 222 } },
    glass    = { color = { 14, 20, 40 } },
    rubber   = { color = { 42, 42, 44 } },
}

Model.CAMERA_PIVOT = { 0.044, 0.0, 0.0025 }
Model.BLADE_Z = 0.0080

local function tri(l, a, b, c) l[#l + 1] = a; l[#l + 1] = b; l[#l + 1] = c end
local function vtx(x, y, z, nx, ny, nz, u, v) return { x, y, z, nx, ny, nz, u or 0, v or 0 } end
local function norm(x, y, z)
    local n = sqrt(x * x + y * y + z * z)
    if n < 1e-12 then return 0, 0, 1 end
    return x / n, y / n, z / n
end
local function cross(ax, ay, az, bx, by, bz) return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx end

local CS = 1 / 0.34
local function uvCarbon(_, x, y, z, nx, ny, nz)
    local ax, ay, az = abs(nx), abs(ny), abs(nz)
    if az >= ax and az >= ay then return (x + 0.17) * CS, (y + 0.17) * CS end
    if ax >= ay then return (y + 0.17) * CS, (z + 0.17) * CS end
    return (x + 0.17) * CS, (z + 0.17) * CS
end
local function uvNone() return 0.5, 0.5 end

local function extrude(l, poly, B, w0, w1, uvf, smoothDeg)
    uvf = uvf or uvNone
    local o, e1, e2, e3 = B[1], B[2], B[3], B[4]
    local function P(a, b, w)
        return o[1] + e1[1] * a + e2[1] * b + e3[1] * w,
               o[2] + e1[2] * a + e2[2] * b + e3[2] * w,
               o[3] + e1[3] * a + e2[3] * b + e3[3] * w
    end
    local function N(a, b, w) return e1[1] * a + e2[1] * b + e3[1] * w, e1[2] * a + e2[2] * b + e3[2] * w, e1[3] * a + e2[3] * b + e3[3] * w end
    local n = #poly
    local ca, cb = 0, 0
    for i = 1, n do ca = ca + poly[i][1]; cb = cb + poly[i][2] end
    ca, cb = ca / n, cb / n
    local per, total = { 0 }, 0
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        total = total + sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        per[i + 1] = total
    end
    local function V(a, b, w, nx, ny, nz, kind, s)
        local x, y, z = P(a, b, w)
        local u, v = uvf(kind, x, y, z, nx, ny, nz, s, (w - w0) / (w1 - w0))
        return vtx(x, y, z, nx, ny, nz, u, v)
    end
    local tx, ty, tz = N(0, 0, 1)
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        tri(l, V(ca, cb, w1, tx, ty, tz, "top"), V(a[1], a[2], w1, tx, ty, tz, "top"), V(b[1], b[2], w1, tx, ty, tz, "top"))
        tri(l, V(ca, cb, w0, -tx, -ty, -tz, "bottom"), V(b[1], b[2], w0, -tx, -ty, -tz, "bottom"), V(a[1], a[2], w0, -tx, -ty, -tz, "bottom"))
    end
    local en = {}
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local da, db = b[1] - a[1], b[2] - a[2]
        local L = sqrt(da * da + db * db)
        en[i] = { db / L, -da / L }
    end
    local cosT = cos(math.rad(smoothDeg or 40))
    for i = 1, n do
        local j = i % n + 1
        local a, b = poly[i], poly[j]
        local ei = en[i]
        local prev, nxt = en[(i - 2) % n + 1], en[j]
        local na, nb = ei, ei
        if prev[1] * ei[1] + prev[2] * ei[2] > cosT then
            local x, y = prev[1] + ei[1], prev[2] + ei[2]
            local L = sqrt(x * x + y * y)
            na = { x / L, y / L }
        end
        if nxt[1] * ei[1] + nxt[2] * ei[2] > cosT then
            local x, y = nxt[1] + ei[1], nxt[2] + ei[2]
            local L = sqrt(x * x + y * y)
            nb = { x / L, y / L }
        end
        local ax, ay, az = N(na[1], na[2], 0)
        local bx, by, bz = N(nb[1], nb[2], 0)
        local sa, sb = per[i] / total, per[i + 1] / total
        local a0 = V(a[1], a[2], w0, ax, ay, az, "side", sa)
        local b0 = V(b[1], b[2], w0, bx, by, bz, "side", sb)
        local b1 = V(b[1], b[2], w1, bx, by, bz, "side", sb)
        local a1 = V(a[1], a[2], w1, ax, ay, az, "side", sa)
        tri(l, a0, b0, b1)
        tri(l, a0, b1, a1)
    end
end

local XY = function(z) return { { 0, 0, z or 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } end
local BZ = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
local BX = { { 0, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 0, 0 } }
local BY = { { 0, 0, 0 }, { 0, 0, 1 }, { 1, 0, 0 }, { 0, 1, 0 } }

local function circle(cx, cy, r, seg, rot)
    local p = {}
    rot = rot or 0
    for i = 0, seg - 1 do
        local a = rot + i / seg * 2 * pi
        p[#p + 1] = { cx + cos(a) * r, cy + sin(a) * r }
    end
    return p
end

local function roundedRect(x0, y0, x1, y1, r, cs)
    cs = cs or 5
    local p = {}
    local corners = { { x1 - r, y0 + r, -pi / 2 }, { x1 - r, y1 - r, 0 }, { x0 + r, y1 - r, pi / 2 }, { x0 + r, y0 + r, pi } }
    for _, c in ipairs(corners) do
        for k = 0, cs do
            local a = c[3] + k / cs * pi / 2
            p[#p + 1] = { c[1] + cos(a) * r, c[2] + sin(a) * r }
        end
    end
    return p
end

local function stadium(ax, ay, bx, by, r, cs)
    cs = cs or 8
    local dx, dy = bx - ax, by - ay
    local base = math.atan2(dy, dx)
    local p = {}
    for k = 0, cs do
        local a = base - pi / 2 + k / cs * pi
        p[#p + 1] = { bx + cos(a) * r, by + sin(a) * r }
    end
    for k = 0, cs do
        local a = base + pi / 2 + k / cs * pi
        p[#p + 1] = { ax + cos(a) * r, ay + sin(a) * r }
    end
    return p
end

local function flatPoly(l, poly, z, uvf)
    uvf = uvf or uvNone
    local n = #poly
    local ca, cb = 0, 0
    for i = 1, n do ca = ca + poly[i][1]; cb = cb + poly[i][2] end
    ca, cb = ca / n, cb / n
    local function V(x, y) local u, v = uvf("top", x, y, z, 0, 0, 1); return vtx(x, y, z, 0, 0, 1, u, v) end
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        tri(l, V(ca, cb), V(a[1], a[2]), V(b[1], b[2]))
    end
end

local function tube(l, ax, ay, az, bx, by, bz, r, seg, capA, capB, flat, rot)
    local dx, dy, dz = norm(bx - ax, by - ay, bz - az)
    local rx, ry, rz = 0, 0, 1
    if abs(dz) > 0.9 then rx, ry, rz = 1, 0, 0 end
    local p1x, p1y, p1z = norm(cross(dx, dy, dz, rx, ry, rz))
    local p2x, p2y, p2z = cross(dx, dy, dz, p1x, p1y, p1z)
    rot = rot or 0
    local function ring(k)
        local a = rot + k / seg * 2 * pi
        local c, s = cos(a), sin(a)
        return p1x * c + p2x * s, p1y * c + p2y * s, p1z * c + p2z * s
    end
    for k = 0, seg - 1 do
        local n0x, n0y, n0z = ring(k)
        local n1x, n1y, n1z = ring(k + 1)
        local fa0x, fa0y, fa0z, fa1x, fa1y, fa1z = n0x, n0y, n0z, n1x, n1y, n1z
        if flat then
            local mx, my, mz = norm(n0x + n1x, n0y + n1y, n0z + n1z)
            fa0x, fa0y, fa0z, fa1x, fa1y, fa1z = mx, my, mz, mx, my, mz
        end
        local a0 = vtx(ax + n0x * r, ay + n0y * r, az + n0z * r, fa0x, fa0y, fa0z, k / seg, 0)
        local a1 = vtx(ax + n1x * r, ay + n1y * r, az + n1z * r, fa1x, fa1y, fa1z, (k + 1) / seg, 0)
        local b0 = vtx(bx + n0x * r, by + n0y * r, bz + n0z * r, fa0x, fa0y, fa0z, k / seg, 1)
        local b1 = vtx(bx + n1x * r, by + n1y * r, bz + n1z * r, fa1x, fa1y, fa1z, (k + 1) / seg, 1)
        tri(l, a0, a1, b1)
        tri(l, a0, b1, b0)
        if capB then
            tri(l, vtx(bx, by, bz, dx, dy, dz), vtx(bx + n0x * r, by + n0y * r, bz + n0z * r, dx, dy, dz),
                vtx(bx + n1x * r, by + n1y * r, bz + n1z * r, dx, dy, dz))
        end
        if capA then
            tri(l, vtx(ax, ay, az, -dx, -dy, -dz), vtx(ax + n1x * r, ay + n1y * r, az + n1z * r, -dx, -dy, -dz),
                vtx(ax + n0x * r, ay + n0y * r, az + n0z * r, -dx, -dy, -dz))
        end
    end
end

local function annulus(l, cx, cy, z, r0, r1, seg, down)
    local nz = down and -1 or 1
    for k = 0, seg - 1 do
        local a0, a1 = k / seg * 2 * pi, (k + 1) / seg * 2 * pi
        local i0 = vtx(cx + cos(a0) * r0, cy + sin(a0) * r0, z, 0, 0, nz)
        local i1 = vtx(cx + cos(a1) * r0, cy + sin(a1) * r0, z, 0, 0, nz)
        local o0 = vtx(cx + cos(a0) * r1, cy + sin(a0) * r1, z, 0, 0, nz)
        local o1 = vtx(cx + cos(a1) * r1, cy + sin(a1) * r1, z, 0, 0, nz)
        tri(l, i0, o0, o1)
        tri(l, i0, o1, i1)
    end
end

local function box(l, c, h, e1, e2, e3, uvf)
    e1, e2, e3 = e1 or { 1, 0, 0 }, e2 or { 0, 1, 0 }, e3 or { 0, 0, 1 }
    local B = { { c[1] - e3[1] * h[3], c[2] - e3[2] * h[3], c[3] - e3[3] * h[3] }, e1, e2, e3 }
    extrude(l, { { -h[1], -h[2] }, { h[1], -h[2] }, { h[1], h[2] }, { -h[1], h[2] } }, B, 0, 2 * h[3], uvf, 1)
end

local function ellipsoid(l, c, a1, a2, a3, r1, r2, r3, su, sv)
    local function pt(th, ph)
        local x, y, z = cos(ph) * cos(th), cos(ph) * sin(th), sin(ph)
        local px = c[1] + a1[1] * x * r1 + a2[1] * y * r2 + a3[1] * z * r3
        local py = c[2] + a1[2] * x * r1 + a2[2] * y * r2 + a3[2] * z * r3
        local pz = c[3] + a1[3] * x * r1 + a2[3] * y * r2 + a3[3] * z * r3
        local nx, ny, nz = norm(a1[1] * x / r1 + a2[1] * y / r2 + a3[1] * z / r3,
            a1[2] * x / r1 + a2[2] * y / r2 + a3[2] * z / r3,
            a1[3] * x / r1 + a2[3] * y / r2 + a3[3] * z / r3)
        return vtx(px, py, pz, nx, ny, nz)
    end
    for i = 0, su - 1 do
        local t0, t1 = i / su * 2 * pi, (i + 1) / su * 2 * pi
        for j = 0, sv - 1 do
            local p0, p1 = -pi / 2 + j / sv * pi, -pi / 2 + (j + 1) / sv * pi
            local a, b, cc, d = pt(t0, p0), pt(t1, p0), pt(t1, p1), pt(t0, p1)
            tri(l, a, b, cc)
            tri(l, a, cc, d)
        end
    end
end

local function blade(l, quad, mirror)
    local R = quad.propD * 0.5
    local r0 = 0.0068
    local P = quad.propPitch or 0.0889
    local NS, NC = 26, 14
    local zb = Model.BLADE_Z
    local up, lo = {}, {}
    for i = 0, NS do
        local t = i / NS
        local r = r0 + (R - r0) * t
        local chord
        if t < 0.32 then
            local k = t / 0.32
            chord = 0.0095 + (0.0158 - 0.0095) * (k * k * (3 - 2 * k))
        else
            local k = (t - 0.32) / 0.68
            chord = 0.0158 - (0.0158 - 0.0072) * k
        end
        if t > 0.9 then chord = chord * sqrt(max(0.04, 1 - ((t - 0.9) / 0.1) ^ 2)) end
        local theta = math.atan(P / (2 * pi * r))
        if theta > math.rad(38) then theta = math.rad(38) end
        local th = 0.0022 * (1 - t) + 0.0008 * t
        local sweep = -0.0035 * t * t
        local cY, sZ = cos(theta), sin(theta)
        up[i], lo[i] = {}, {}
        for k = 0, NC do
            local s = k / NC
            local along = (0.5 - s) * chord
            local y = sweep + along * cY
            local z = zb + along * sZ
            local camber = 0.035 * chord * 4 * s * (1 - s)
            local f = 2.6 * sqrt(s) * (1 - s)
            local nY, nZ = -sZ, cY
            local ou = camber + th * 0.5 * f
            local ol = camber - th * 0.5 * f
            up[i][k] = { r, y + nY * ou, z + nZ * ou }
            lo[i][k] = { r, y + nY * ol, z + nZ * ol }
        end
    end
    local sgn = mirror and -1 or 1
    local function surface(grid, flip)
        local nrm = {}
        for i = 0, NS do nrm[i] = {} for k = 0, NC do nrm[i][k] = { 0, 0, 0 } end end
        for i = 0, NS - 1 do
            for k = 0, NC - 1 do
                local a, b, c = grid[i][k], grid[i + 1][k], grid[i][k + 1]
                local nx, ny, nz = cross(b[1] - a[1], b[2] - a[2], b[3] - a[3], c[1] - a[1], c[2] - a[2], c[3] - a[3])
                if flip then nx, ny, nz = -nx, -ny, -nz end
                for _, q in ipairs({ { i, k }, { i + 1, k }, { i, k + 1 }, { i + 1, k + 1 } }) do
                    local n = nrm[q[1]][q[2]]
                    n[1], n[2], n[3] = n[1] + nx, n[2] + ny, n[3] + nz
                end
            end
        end
        local function V(i, k)
            local p, n = grid[i][k], nrm[i][k]
            local nx, ny, nz = norm(n[1], n[2], n[3])
            return vtx(p[1], p[2] * sgn, p[3], nx, ny * sgn, nz, i / NS, k / NC)
        end
        for i = 0, NS - 1 do
            for k = 0, NC - 1 do
                tri(l, V(i, k), V(i + 1, k), V(i + 1, k + 1))
                tri(l, V(i, k), V(i + 1, k + 1), V(i, k + 1))
            end
        end
    end
    surface(up, true)
    surface(lo, false)
end

local function tiltBasis(o, t)
    local c, s = cos(t), sin(t)
    return { o, { 0, 1, 0 }, { -s, 0, c }, { c, 0, s } }
end
local function tp(o, t, x, y, z)
    local c, s = cos(t), sin(t)
    return o[1] + c * x - s * z, o[2] + y, o[3] + s * x + c * z
end

local function insetPoly(poly, d)
    local n = #poly
    local lines = {}
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local L = sqrt(dx * dx + dy * dy)
        if L > 1e-9 then
            dx, dy = dx / L, dy / L
            lines[#lines + 1] = { a[1] - dy * d, a[2] + dx * d, dx, dy }
        end
    end
    local out = {}
    local m = #lines
    for i = 1, m do
        local p, q = lines[(i - 2) % m + 1], lines[i]
        local den = p[3] * q[4] - p[4] * q[3]
        if abs(den) < 1e-6 then
            out[#out + 1] = { q[1], q[2] }
        else
            local t = ((q[1] - p[1]) * q[4] - (q[2] - p[2]) * q[3]) / den
            out[#out + 1] = { p[1] + p[3] * t, p[2] + p[4] * t }
        end
    end
    return out
end

local function chamferPlate(l, poly, z0, z1, c, uvf, smoothDeg)
    uvf = uvf or uvNone
    extrude(l, poly, BZ, z0, z1 - c, uvf, smoothDeg)
    local inner = insetPoly(poly, c)
    local n = #poly
    if #inner ~= n then
        extrude(l, poly, BZ, z1 - c, z1, uvf, smoothDeg)
        return
    end
    local en = {}
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local L = sqrt(dx * dx + dy * dy)
        en[i] = L > 1e-12 and { dy / L, -dx / L } or { 0, 0 }
    end
    local cosT = cos(math.rad(smoothDeg or 40))
    local function vn(i, e)
        local p = en[(i - 2) % n + 1]
        if p[1] * e[1] + p[2] * e[2] > cosT then
            local x, y = p[1] + e[1], p[2] + e[2]
            local L = sqrt(x * x + y * y)
            return x / L, y / L
        end
        return e[1], e[2]
    end
    local function V(x, y, z, nx, ny)
        local a, b, cc = norm(nx, ny, 1)
        local u, v = uvf("side", x, y, z, a, b, cc, 0, 0)
        return vtx(x, y, z, a, b, cc, u, v)
    end
    for i = 1, n do
        local j = i % n + 1
        local e = en[i]
        local ax, ay = vn(i, e)
        local nxt = en[j]
        local bx, by = e[1], e[2]
        if nxt[1] * e[1] + nxt[2] * e[2] > cosT then
            local x, y = nxt[1] + e[1], nxt[2] + e[2]
            local L = sqrt(x * x + y * y)
            bx, by = x / L, y / L
        end
        local o0, o1, i0, i1 = poly[i], poly[j], inner[i], inner[j]
        local A = V(o0[1], o0[2], z1 - c, ax, ay)
        local B = V(o1[1], o1[2], z1 - c, bx, by)
        local Bi = V(i1[1], i1[2], z1, bx, by)
        local Ai = V(i0[1], i0[2], z1, ax, ay)
        tri(l, A, B, Bi)
        tri(l, A, Bi, Ai)
    end
    flatPoly(l, inner, z1, uvf)
end

local function braid(la, lb, ax, ay, az, bx, by, bz, r, band)
    local L = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
    local n = math.max(2, floor(L / band))
    for k = 0, n - 1 do
        local t0, t1 = k / n, (k + 1) / n
        local l = (k % 2 == 0) and la or lb
        tube(l, ax + (bx - ax) * t0, ay + (by - ay) * t0, az + (bz - az) * t0,
            ax + (bx - ax) * t1, ay + (by - ay) * t1, az + (bz - az) * t1, r, 8, k == 0, k == n - 1, false, (k % 2) * pi / 8)
    end
end

local function wire(l, pts, r, seg)
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        tube(l, a[1], a[2], a[3], b[1], b[2], b[3], r, seg or 8, i == 1, i == #pts - 1)
        if i > 1 then ellipsoid(l, a, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, r, r, r, seg or 8, 4) end
    end
end

local function screwHead(lHead, lHex, x, y, z, r, down)
    local dz = down and -1 or 1
    tube(lHead, x, y, z, x, y, z + dz * r * 0.55, r, 14, false, false)
    ellipsoid(lHead, { x, y, z + dz * r * 0.55 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, dz }, r, r, r * 0.35, 14, 3)
    local hz = z + dz * (r * 0.9 + 0.00005)
    if down then
        local h = circle(x, y, r * 0.42, 6)
        local rev = {}
        for i = #h, 1, -1 do rev[#rev + 1] = h[i] end
        local n = #rev
        for i = 1, n do
            local a, b = rev[i], rev[i % n + 1]
            tri(lHex, vtx(x, y, hz, 0, 0, -1), vtx(a[1], a[2], hz, 0, 0, -1), vtx(b[1], b[2], hz, 0, 0, -1))
        end
    else
        flatPoly(lHex, circle(x, y, r * 0.42, 6), hz)
    end
end

function Model.build(quad, opts)
    opts = opts or {}
    local propMat = (opts.propColor == "orange") and "prop" or "propSmoke"
    local parts = { static = {}, camera = {}, gopro = {}, bell = {}, hub = {}, bladeCCW = {}, bladeCW = {} }
    local function L(part, mat)
        local p = parts[part]
        p[mat] = p[mat] or {}
        return p[mat]
    end

    local plateZ0, plateZ1 = -0.0165, -0.011
    local topZ0, topZ1 = 0.016, 0.018
    local carbon = L("static", "carbon")
    local CH = 0.0007

    chamferPlate(carbon, roundedRect(-0.068, -0.0225, 0.062, 0.0225, 0.008, 5), plateZ0, plateZ1, CH, uvCarbon)
    flatPoly(L("static", "slot"), stadium(0.018, -0.011, 0.018, 0.011, 0.0028, 6), plateZ1 + 0.0002)
    for i = 1, 4 do
        local m = quad.motors[i]
        local mx, my = m[1], m[2]
        local len = sqrt(mx * mx + my * my)
        local ux, uy = mx / len, my / len
        local nx, ny = -uy, ux
        local w0, w1 = 0.0092, 0.0068
        local p0x, p0y = ux * 0.010, uy * 0.010
        chamferPlate(carbon, {
            { p0x - nx * w0, p0y - ny * w0 }, { mx - nx * w1, my - ny * w1 },
            { mx + nx * w1, my + ny * w1 }, { p0x + nx * w0, p0y + ny * w0 },
        }, plateZ0, plateZ1, CH, uvCarbon, 1)
        chamferPlate(carbon, circle(mx, my, 0.0160, 36), plateZ0, plateZ1, CH, uvCarbon)
        flatPoly(L("static", "slot"), stadium(ux * 0.044, uy * 0.044, ux * 0.064, uy * 0.064, 0.0021, 6), plateZ1 + 0.0002)
        flatPoly(L("static", "slot"), stadium(ux * 0.072, uy * 0.072, ux * 0.088, uy * 0.088, 0.0018, 6), plateZ1 + 0.0002)
        for _, f in ipairs({ 0.018, 0.031 }) do
            screwHead(L("static", "silver"), L("static", "slot"), ux * f, uy * f, plateZ0, 0.0018, true)
        end
        for k = 0, 3 do
            local a = (k + 0.5) / 4 * 2 * pi + math.atan2(uy, ux)
            screwHead(L("static", "silver"), L("static", "slot"), mx + cos(a) * 0.0095, my + sin(a) * 0.0095, plateZ0, 0.0016, true)
        end
        local zb = plateZ1 + 0.0021
        local ax, ay = mx - ux * 0.0150, my - uy * 0.0150
        for w = -1, 1 do
            local ox, oy = nx * w * 0.0012, ny * w * 0.0012
            wire(L("static", "black"), {
                { mx - ux * 0.0110 + ox, my - uy * 0.0110 + oy, -0.0092 },
                { mx - ux * 0.0150 + ox, my - uy * 0.0150 + oy, zb - 0.0004 },
                { mx - ux * 0.0200 + ox * 0.5, my - uy * 0.0200 + oy * 0.5, zb },
            }, 0.00062, 6)
        end
        local bx0, by0 = mx - ux * 0.0195, my - uy * 0.0195
        local bx, by = ux * 0.026, uy * 0.026
        braid(L("static", "black"), L("static", "braid"), bx0, by0, zb, bx, by, zb, 0.0021, 0.0019)
        for _, f in ipairs({ 0.12, 0.70 }) do
            local cx, cy = bx0 + (bx - bx0) * f, by0 + (by - by0) * f
            tube(L("static", "rubber"), cx - ux * 0.0011, cy - uy * 0.0011, zb, cx + ux * 0.0011, cy + uy * 0.0011, zb, 0.0027, 12, true, true)
            box(L("static", "rubber"), { cx + nx * 0.0028, cy + ny * 0.0028, zb - 0.0010 }, { 0.0016, 0.0012, 0.0016 }, { ux, uy, 0 }, { nx, ny, 0 }, { 0, 0, 1 })
        end
    end

    chamferPlate(carbon, roundedRect(-0.062, -0.022, 0.054, 0.022, 0.007, 5), topZ0, topZ1, 0.0005, uvCarbon)
    for _, sgn in ipairs({ 1, -1 }) do
        flatPoly(L("static", "slot"), stadium(-0.040, sgn * 0.0185, -0.020, sgn * 0.0185, 0.0013, 5), topZ1 + 0.0002)
    end
    local stand = { { 0.028, 0.0175 }, { 0.028, -0.0175 }, { -0.050, 0.0175 }, { -0.050, -0.0175 }, { -0.011, 0.0185 }, { -0.011, -0.0185 } }
    for _, sd in ipairs(stand) do
        tube(L("static", "black"), sd[1], sd[2], plateZ1, sd[1], sd[2], topZ0, 0.0025, 6, false, false, true)
        screwHead(L("static", "silver"), L("static", "slot"), sd[1], sd[2], topZ1, 0.0023, false)
        screwHead(L("static", "silver"), L("static", "slot"), sd[1], sd[2], plateZ0, 0.0023, true)
    end

    local side = roundedRect(-0.011, 0.031, 0.015, 0.058, 0.006, 4)
    extrude(L("static", "black"), side, BY, 0.0112, 0.0142, nil, 50)
    extrude(L("static", "black"), side, BY, -0.0142, -0.0112, nil, 50)
    box(L("static", "orange"), { 0.0600, 0, -0.0125 }, { 0.0022, 0.0150, 0.0018 })
    local cp = Model.CAMERA_PIVOT
    for _, sgn in ipairs({ 1, -1 }) do
        local y = sgn * 0.0142
        tube(L("static", "silver"), cp[1], y, cp[3], cp[1], y + sgn * 0.0009, cp[3], 0.0017, 12, false, true)
        local hx = circle(cp[1], 0, 0.0007, 6)
        for i = 1, 6 do
            local q, r = hx[i], hx[i % 6 + 1]
            local yy = y + sgn * 0.00095
            tri(L("static", "slot"), vtx(cp[1], yy, cp[3], 0, sgn, 0), vtx(q[1], yy, cp[3] + q[2], 0, sgn, 0), vtx(r[1], yy, cp[3] + r[2], 0, sgn, 0))
        end
    end

    local sx = -0.011
    box(L("static", "pcb"), { sx, 0, -0.0083 }, { 0.0175, 0.0175, 0.0008 })
    for k = -2, 3 do
        for _, sg in ipairs({ 1, -1 }) do
            box(L("static", "chip"), { sx + (k - 0.5) * 0.0050, sg * 0.0105, -0.0071 }, { 0.0019, 0.0024, 0.0004 })
        end
    end
    box(L("static", "chip"), { sx, 0, -0.0071 }, { 0.0035, 0.0035, 0.0004 })
    for _, q in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
        tube(L("static", "orange"), sx + q[1] * 0.0150, q[2] * 0.0150, -0.0075, sx + q[1] * 0.0150, q[2] * 0.0150, 0.0006, 0.0021, 12, false, false)
        for k = -1, 1 do
            local px, py = sx + q[1] * 0.0125 + k * 0.0026 * q[2], q[2] * 0.0150 - q[2] * 0.0030
            box(L("static", "copper"), { px, py, -0.0074 }, { 0.0009, 0.0011, 0.0001 })
            ellipsoid(L("static", "silver"), { px, py, -0.0073 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, 0.0008, 0.0009, 0.0005, 8, 3)
        end
    end
    box(L("static", "pcbblue"), { sx, 0, 0.0013 }, { 0.0175, 0.0175, 0.0008 })
    box(L("static", "chip"), { sx, 0, 0.0025 }, { 0.0045, 0.0045, 0.0005 })
    box(L("static", "chip"), { sx - 0.0085, 0.0040, 0.0024 }, { 0.0016, 0.0016, 0.0004 })
    box(L("static", "silver"), { sx + 0.004, 0.0160, 0.0030 }, { 0.0045, 0.0019, 0.0014 })
    box(L("static", "ledgreen"), { sx + 0.010, -0.010, 0.0023 }, { 0.0007, 0.0004, 0.0003 })
    box(L("static", "ledblue"), { sx + 0.010, -0.0085, 0.0023 }, { 0.0007, 0.0004, 0.0003 })
    for _, c in ipairs({ { -0.0135, -0.0070 }, { -0.0135, 0.0070 }, { 0.0100, 0.0105 } }) do
        box(L("static", "white"), { sx + c[1], c[2], 0.0028 }, { 0.0015, 0.0030, 0.0007 })
    end
    tube(L("static", "capblue"), -0.030, 0, -0.0040, -0.054, 0, -0.0040, 0.0052, 18, false, true)
    tube(L("static", "gunmetal"), -0.054, 0, -0.0040, -0.0555, 0, -0.0040, 0.0047, 18, false, true)
    for _, sg in ipairs({ 1, -1 }) do
        wire(L("static", "silver"), { { -0.030, sg * 0.0015, -0.0040 }, { -0.027, sg * 0.0015, -0.0050 }, { -0.0260, sg * 0.0015, -0.0072 } }, 0.0003, 5)
    end
    box(L("static", "pcb"), { -0.033, 0, 0.0067 }, { 0.0105, 0.0105, 0.0007 })
    box(L("static", "gunmetal"), { -0.033, 0, 0.0093 }, { 0.0085, 0.0085, 0.0019 })
    for f = -3, 3 do
        box(L("static", "gunmetal"), { -0.033 + f * 0.0023, 0, 0.0121 }, { 0.0005, 0.0080, 0.0010 })
    end
    box(L("static", "capblue"), { -0.0565, -0.0090, -0.0080 }, { 0.0060, 0.0050, 0.0022 })

    box(L("static", "black"), { -0.0700, 0, -0.0130 }, { 0.0022, 0.0130, 0.0030 })
    for k = -2, 1 do
        box(L("static", "led"), { -0.0723, (k + 0.5) * 0.0055, -0.0130 }, { 0.0003, 0.0019, 0.0016 })
    end
    tube(L("static", "black"), -0.0605, 0.0110, -0.0110, -0.0605, 0.0110, -0.0060, 0.0042, 16, false, true)
    flatPoly(L("static", "slot"), circle(-0.0605, 0.0110, 0.0009, 10), -0.0059)

    for i = 1, 4 do
        local m = quad.motors[i]
        local mx, my = m[1], m[2]
        tube(L("static", "black"), mx, my, plateZ1, mx, my, -0.0092, 0.0137, 36, false, true)
        tube(L("static", "orange"), mx, my, -0.0092, mx, my, -0.0084, 0.01385, 36, false, true)
        tube(L("static", "magnet"), mx, my, -0.0084, mx, my, -0.0076, 0.0131, 36, false, false)
        tube(L("static", "copper"), mx, my, -0.0084, mx, my, 0.0008, 0.0113, 24, false, true)
        for k = 0, 11 do
            local a = k / 12 * 2 * pi
            box(L("static", "magnet"), { mx + cos(a) * 0.0113, my + sin(a) * 0.0113, -0.0038 }, { 0.0004, 0.0008, 0.0044 },
                { cos(a), sin(a), 0 }, { -sin(a), cos(a), 0 }, { 0, 0, 1 })
        end
        tube(L("static", "black"), mx, my, -0.0084, mx, my, 0.0010, 0.0050, 14, false, true)
    end
    local bell = L("bell", "black")
    tube(bell, 0, 0, -0.0074, 0, 0, -0.0052, 0.01395, 40, false, false)
    annulus(bell, 0, 0, -0.0074, 0.0130, 0.01395, 40, true)
    local NV, VA = 12, math.rad(28)
    for k = 0, NV - 1 do
        local a = (k + 0.5) / NV * 2 * pi
        local ex, ey = cos(a), sin(a)
        local tx, ty = -ey, ex
        box(bell, { ex * 0.0134, ey * 0.0134, -0.0021 }, { 0.0006, 0.0011, 0.0034 },
            { ex, ey, 0 }, { tx * cos(VA), ty * cos(VA), sin(VA) }, { -tx * sin(VA), -ty * sin(VA), cos(VA) })
    end
    tube(bell, 0, 0, 0.0010, 0, 0, 0.0036, 0.01395, 40, false, false)
    tube(L("bell", "gunmetal"), 0, 0, -0.0060, 0, 0, -0.0056, 0.01400, 40, false, false)
    tube(L("bell", "orange"), 0, 0, 0.0024, 0, 0, 0.0028, 0.01400, 40, false, false)
    local cap = L("bell", "gunmetal")
    annulus(cap, 0, 0, 0.0036, 0.0116, 0.01395, 40)
    for k = 0, 5 do
        local a = (k + 0.5) / 6 * 2 * pi
        local ex, ey = cos(a), sin(a)
        box(cap, { ex * 0.0083, ey * 0.0083, 0.0034 }, { 0.0034, 0.0012, 0.0003 }, { ex, ey, 0 }, { -ey, ex, 0 }, { 0, 0, 1 })
    end
    tube(cap, 0, 0, 0.0024, 0, 0, 0.0040, 0.0052, 20, false, true)
    tube(L("bell", "silver"), 0, 0, 0.0040, 0, 0, 0.0046, 0.0028, 12, false, true)

    local hubL = L("hub", propMat)
    tube(hubL, 0, 0, 0.0046, 0, 0, 0.0112, 0.0078, 28, true, false)
    ellipsoid(hubL, { 0, 0, 0.0112 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, 0.0078, 0.0078, 0.0012, 28, 3)
    annulus(L("hub", "slot"), 0, 0, 0.01225, 0.0060, 0.0065, 28)
    tube(L("hub", "silver"), 0, 0, 0.0122, 0, 0, 0.0128, 0.0060, 20, false, true)
    tube(L("hub", "silver"), 0, 0, 0.0128, 0, 0, 0.0158, 0.0052, 6, false, true, true)
    tube(L("hub", "orange"), 0, 0, 0.0158, 0, 0, 0.0168, 0.0046, 20, false, true)
    tube(L("hub", "silver"), 0, 0, 0.0168, 0, 0, 0.0178, 0.0024, 12, false, true)
    for k = 0, 2 do
        tube(L("hub", "gunmetal"), 0, 0, 0.0169 + k * 0.0003, 0, 0, 0.01705 + k * 0.0003, 0.00245, 12, false, false)
    end

    blade(L("bladeCCW", propMat), quad, false)
    blade(L("bladeCW", propMat), quad, true)

    local bx0, bx1 = -0.064, 0.010
    local by, bz0, bz1, br = 0.0175, 0.0195, 0.0585, 0.0052
    box(L("static", "rubber"), { (bx0 + bx1) / 2, 0, 0.0187 }, { (bx1 - bx0) / 2 - 0.002, 0.016, 0.0008 })
    local bp = roundedRect(-by, bz0, by, bz1, br, 6)
    local rotated, start = {}, nil
    local best = 1e9
    for i, q in ipairs(bp) do
        local d = abs(q[1]) + abs(q[2] - bz0)
        if q[2] < bz0 + 1e-6 and q[1] >= 0 and d < best then best, start = d, i end
    end
    start = start or 1
    for k = 0, #bp - 1 do rotated[#rotated + 1] = bp[(start - 1 + k) % #bp + 1] end
    if rotated[1][1] > 1e-6 then table.insert(rotated, 1, { 0, bz0 }) end
    extrude(L("static", "label"), rotated, BX, bx0, bx1, function(kind, x, y, z, nx, ny, nz, s, wf)
        if kind ~= "side" then return 0.004, 0.004 end
        return 0.02 + 0.96 * wf, s
    end, 50)
    for _, ex in ipairs({ bx0, bx1 }) do
        local sgn = ex < 0 and -1 or 1
        extrude(L("static", "black"), insetPoly(bp, 0.0012), BX, ex, ex + sgn * 0.0008, nil, 50)
    end
    local sp = roundedRect(-by - 0.0013, bz0 - 0.0012, by + 0.0013, bz1 + 0.0013, br + 0.0012, 6)
    for _, sx0 in ipairs({ -0.0175, 0.0026 }) do
        extrude(L("static", "strap"), sp, BX, sx0, sx0 + 0.0070, nil, 50)
        box(L("static", "black"), { sx0 + 0.0035, 0.0040, bz1 + 0.0022 }, { 0.0046, 0.0060, 0.0009 })
        box(L("static", "slot"), { sx0 + 0.0035, 0.0040, bz1 + 0.0032 }, { 0.0030, 0.0040, 0.0001 })
        box(L("static", "strap"), { sx0 + 0.0035, -0.0060, bz1 + 0.0019 }, { 0.0035, 0.0060, 0.0005 })
    end
    local xy = -0.0090
    for _, w in ipairs({ { 0.0038, "red" }, { -0.0038, "black" } }) do
        wire(L("static", w[2]), {
            { bx0 + 0.001, w[1] * 0.6, 0.050 }, { bx0 - 0.008, xy + w[1], 0.050 }, { -0.077, xy + w[1], 0.045 }, { -0.0805, xy + w[1], 0.0440 },
        }, 0.0019, 10)
        wire(L("static", w[2]), {
            { -0.0805, xy + w[1] * 0.8, 0.0280 }, { -0.074, xy + w[1] * 0.8, 0.018 }, { -0.066, xy + w[1] * 0.8, 0.008 },
            { -0.058, xy + w[1] * 0.8, -0.002 }, { -0.0275, w[1] * 2.6, -0.0074 },
        }, 0.0019, 10)
    end
    box(L("static", "yellow"), { -0.0805, xy, 0.0360 }, { 0.0042, 0.0082, 0.0080 })
    for k = -1, 1 do box(L("static", "yellow"), { -0.0805, xy + k * 0.0040, 0.0360 }, { 0.0046, 0.0006, 0.0060 }) end
    local bal = { "black", "red", "black", "black", "black", "black", "black" }
    for k = 1, 7 do
        local yy = 0.0100 + (k - 4) * 0.00055
        wire(L("static", bal[k] == "red" and "red" or "black"), {
            { bx0 + 0.0008, yy, 0.0560 }, { bx0 - 0.0040, yy, 0.0600 }, { bx0 + 0.0060, yy, 0.0612 }, { -0.0200, yy, 0.0602 },
        }, 0.00028, 4)
    end
    box(L("static", "white"), { -0.0195, 0.0100, 0.0603 }, { 0.0030, 0.0055, 0.0015 })

    local ay = 0.0115
    box(L("static", "orange"), { -0.0615, ay, plateZ1 + 0.0040 }, { 0.0050, 0.0060, 0.0040 })
    local ad = { -0.5, 0, 0.866 }
    local a0 = { -0.064, ay, plateZ1 + 0.007 }
    local a1 = { a0[1] + ad[1] * 0.052, ay, a0[3] + ad[3] * 0.052 }
    tube(L("static", "black"), a0[1], a0[2], a0[3], a1[1], a1[2], a1[3], 0.0017, 12, false, false)
    tube(L("static", "gunmetal"), a0[1], a0[2], a0[3], a0[1] + ad[1] * 0.006, ay, a0[3] + ad[3] * 0.006, 0.0024, 6, false, true, true)
    local hc = { a1[1] + ad[1] * 0.0060, ay, a1[3] + ad[3] * 0.0060 }
    local hn = { -0.866, 0, -0.5 }
    ellipsoid(L("static", "black"), hc, { 0, 1, 0 }, ad, hn, 0.0068, 0.0068, 0.0032, 18, 8)
    wire(L("static", "black"), { { -0.040, 0.0060, 0.0080 }, { -0.050, 0.0100, 0.0040 }, { -0.0605, ay, -0.0050 } }, 0.0006, 6)
    for _, sg in ipairs({ 1, -1 }) do
        local base = { -0.0505, sg * 0.0195, 0.000 }
        local tip = { -0.084, sg * 0.040, 0.026 }
        tube(L("static", "orange"), base[1], base[2], base[3], base[1] + (tip[1] - base[1]) * 0.45, base[2] + (tip[2] - base[2]) * 0.45, base[3] + (tip[3] - base[3]) * 0.45, 0.0014, 8, true, true)
        tube(L("static", "white"), base[1], base[2], base[3], tip[1], tip[2], tip[3], 0.0006, 6, false, true)
        tube(L("static", "rubber"), -0.0515, sg * 0.0175, -0.0005, -0.0495, sg * 0.0175, -0.0005, 0.0031, 10, true, true)
        wire(L("static", "black"), { { -0.0565, -0.0090, -0.0070 }, { -0.0530, sg * 0.0150, -0.0030 }, { base[1], base[2], base[3] } }, 0.0005, 5)
    end

    local cb = L("camera", "black")
    extrude(cb, roundedRect(-0.0095, -0.0095, 0.0095, 0.0095, 0.0022, 3), { { 0, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 0, 0 } }, -0.010, 0.006, nil, 50)
    tube(cb, -0.010, 0, -0.004, -0.014, 0, -0.004, 0.0018, 8, false, true)
    tube(cb, 0.006, 0, 0, 0.0080, 0, 0, 0.0074, 28, false, false)
    for k = 0, 3 do
        tube(L("camera", "gunmetal"), 0.0080 + k * 0.0010, 0, 0, 0.0085 + k * 0.0010, 0, 0, 0.0070, 28, false, false)
        tube(cb, 0.0085 + k * 0.0010, 0, 0, 0.0090 + k * 0.0010, 0, 0, 0.0068, 28, false, false)
    end
    tube(cb, 0.0120, 0, 0, 0.0128, 0, 0, 0.0070, 28, false, false)
    tube(L("camera", "orange"), 0.0128, 0, 0, 0.0142, 0, 0, 0.0073, 28, true, true)
    tube(L("camera", "glass"), 0.0142, 0, 0, 0.0146, 0, 0, 0.0052, 28, false, true)
    ellipsoid(L("camera", "lens"), { 0.0146, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 0, 0 }, 0.0040, 0.0040, 0.0012, 18, 4)

    local t = math.rad(20)
    local o = { 0.0335, 0, 0.0440 }
    local B = tiltBasis(o, t)
    local W2, H2, D2 = 0.0250, 0.0185, 0.0145
    local gp = L("gopro", "cam")
    extrude(gp, roundedRect(-W2, -H2, W2, H2, 0.0050, 6), B, -D2, D2, nil, 50)
    local function P(x, y, z) return { tp(o, t, x, y, z) } end
    local function seg(l, x0, y0, z0, x1, y1, z1, r, n, ca, cb2)
        local A, Bp = P(x0, y0, z0), P(x1, y1, z1)
        tube(l, A[1], A[2], A[3], Bp[1], Bp[2], Bp[3], r, n, ca, cb2)
    end
    local e2 = { -sin(t), 0, cos(t) }
    local e3 = { cos(t), 0, sin(t) }
    box(L("gopro", "black"), P(D2 + 0.0004, 0.0075, 0.0020), { 0.0118, 0.0118, 0.0004 }, { 0, 1, 0 }, e2, e3)
    seg(gp, D2 + 0.0008, 0.0075, 0.0020, D2 + 0.0040, 0.0075, 0.0020, 0.0095, 32, false, false)
    seg(L("gopro", "gunmetal"), D2 + 0.0040, 0.0075, 0.0020, D2 + 0.0046, 0.0075, 0.0020, 0.0090, 32, false, true)
    seg(L("gopro", "glass"), D2 + 0.0046, 0.0075, 0.0020, D2 + 0.0050, 0.0075, 0.0020, 0.0068, 32, false, true)
    local lc = P(D2 + 0.0050, 0.0075, 0.0020)
    ellipsoid(L("gopro", "lens"), lc, { 0, 1, 0 }, e2, e3, 0.0046, 0.0046, 0.0013, 20, 4)
    box(L("gopro", "screen"), P(D2 + 0.0002, -0.0135, 0.0030), { 0.0075, 0.0075, 0.0003 }, { 0, 1, 0 }, e2, e3)
    for k = 0, 2 do
        local q = P(D2 + 0.0002, -0.0135 + (k - 1) * 0.0016, -0.0110)
        ellipsoid(L("gopro", "slot"), q, { 0, 1, 0 }, e2, e3, 0.0004, 0.0004, 0.0002, 6, 2)
    end
    seg(L("gopro", "red"), 0.0040, -0.0110, H2, 0.0040, -0.0110, H2 + 0.0010, 0.0042, 20, false, true)
    seg(L("gopro", "black"), 0.0040, -0.0110, H2 + 0.0010, 0.0040, -0.0110, H2 + 0.0016, 0.0032, 20, false, true)
    box(L("gopro", "slot"), P(0.0000, -W2 - 0.0002, -0.0010), { 0.0105, 0.0002, 0.0140 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 })
    box(L("gopro", "cam"), P(0.0000, -W2 - 0.0003, -0.0010), { 0.0098, 0.0002, 0.0133 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 })
    seg(L("gopro", "black"), 0.0080, W2, 0.0100, 0.0080, W2 + 0.0008, 0.0100, 0.0030, 16, false, true)
    box(L("gopro", "black"), P(-D2 - 0.0002, 0, 0), { 0.0215, 0.0160, 0.0003 }, { 0, 1, 0 }, e2, e3)
    box(L("gopro", "screen"), P(-D2 - 0.0005, 0, 0), { 0.0195, 0.0145, 0.0003 }, { 0, 1, 0 }, e2, e3)
    local cr = L("gopro", "orange")
    box(cr, P(0, 0, -H2 - 0.0014), { D2 + 0.0016, W2 + 0.0016, 0.0014 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 })
    for _, sg in ipairs({ 1, -1 }) do
        box(cr, P(-0.0040, sg * (W2 + 0.0008), -0.0135), { D2 - 0.0040, 0.0008, 0.0055 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 })
    end
    box(cr, P(-D2 - 0.0010, 0, -0.0130), { 0.0010, W2 - 0.0020, 0.0060 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 })
    local wedge = { { -0.022, topZ1 }, { 0.022, topZ1 }, { 0.022, topZ1 + 0.0075 }, { -0.022, topZ1 + 0.0010 } }
    local wz = {}
    for _, q in ipairs(wedge) do wz[#wz + 1] = { q[2], q[1] + 0.033 } end
    extrude(L("gopro", "orange"), { wz[1], wz[4], wz[3], wz[2] }, BY, -0.016, 0.016, nil, 10)
    box(L("gopro", "strap"), { 0.033, 0, topZ1 + 0.0042 }, { 0.0060, 0.0225, 0.0006 })
    box(L("gopro", "black"), { 0.033, -0.0205, topZ1 + 0.0042 }, { 0.0068, 0.0030, 0.0012 })

    return parts
end

local function rz(a)
    local c, s = cos(a), sin(a)
    return c, -s, 0, s, c, 0, 0, 0, 1
end

local out = {}
function Model.instances(quad, st)
    local n = 0
    local function add(part, a, b, c, d, e, f, g, h, i, tx, ty, tz, sx)
        n = n + 1
        local t = out[n]
        if not t then t = {}; out[n] = t end
        t.part = part
        t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9] = a, b, c, d, e, f, g, h, i
        t.tx, t.ty, t.tz, t.sx = tx, ty, tz, sx or 1
    end
    add("static", 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
    if not st.hideCamera then
        local t = math.rad(st.uptilt or 30)
        local c, s = cos(t), sin(t)
        local p = Model.CAMERA_PIVOT
        add("camera", c, 0, -s, 0, 1, 0, s, 0, c, p[1], p[2], p[3])
    end
    if not st.hideActionCam then add("gopro", 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0) end
    local limit = st.spinLimit or 140
    for i = 1, 4 do
        local m = quad.motors[i]
        local ang = st.propAng and st.propAng[i] or (i * 0.7)
        local a1, a2, a3, a4, a5, a6, a7, a8, a9 = rz(ang)
        add("bell", a1, a2, a3, a4, a5, a6, a7, a8, a9, m[1], m[2], 0)
        if not st.hideProps then add("hub", a1, a2, a3, a4, a5, a6, a7, a8, a9, m[1], m[2], 0) end
        local w = st.motorW and abs(st.motorW[i]) or 0
        if w <= limit and not st.hideProps then
            local h = st.health and st.health[i] or 1
            local part = (m[3] > 0) and "bladeCCW" or "bladeCW"
            for b = 0, (quad.propBlades or 3) - 1 do
                local len = 1
                if h < 1 then len = 0.25 + 0.75 * h * (0.6 + 0.4 * ((b * 37 + i * 11) % 7) / 6) end
                local b1, b2, b3, b4, b5, b6, b7, b8, b9 = rz(ang + b * 2 * pi / (quad.propBlades or 3))
                add(part, b1, b2, b3, b4, b5, b6, b7, b8, b9, m[1], m[2], 0, len)
            end
        end
    end
    for k = n + 1, #out do out[k] = nil end
    return out, n
end

return Model
