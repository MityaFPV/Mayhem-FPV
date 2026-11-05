local FPV = MayhemFPV

local R = {}
FPV.Render = R

local matSolid = CreateMaterial("mayhem_solid_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = "1",
    ["$nocull"] = "1",
})
local matTrans = CreateMaterial("mayhem_trans_v1", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
    ["$translucent"] = "1",
    ["$nocull"] = "1",
})

local sqrt, sin, cos, pi, max, min = math.sqrt, math.sin, math.cos, math.pi, math.max, math.min

local Px, Py, Pz = 0, 0, 0
local r11, r12, r13, r21, r22, r23, r31, r32, r33 = 1, 0, 0, 0, 1, 0, 0, 0, 1
local K = 1 / 0.0254
local light = 1
local Lx, Ly, Lz = 0.35, 0.25, 0.9
do local n = sqrt(Lx * Lx + Ly * Ly + Lz * Lz); Lx, Ly, Lz = Lx / n, Ly / n, Lz / n end

local buf, nv = {}, 0
local function vert(x, y, z, r, g, b, a)
    local i = nv * 7
    buf[i + 1], buf[i + 2], buf[i + 3], buf[i + 4], buf[i + 5], buf[i + 6], buf[i + 7] = x, y, z, r, g, b, a
    nv = nv + 1
end

local vtmp = Vector()
local function flush(mat)
    if nv < 3 then nv = 0 return end
    local tris = math.floor(nv / 3)
    render.SetMaterial(mat)
    mesh.Begin(MATERIAL_TRIANGLES, tris)
    for t = 0, tris * 3 - 1 do
        local i = t * 7
        vtmp:SetUnpacked(buf[i + 1], buf[i + 2], buf[i + 3])
        mesh.Position(vtmp)
        mesh.Color(buf[i + 4], buf[i + 5], buf[i + 6], buf[i + 7])
        mesh.AdvanceVertex()
    end
    mesh.End()
    nv = 0
end

local function W(x, y, z)
    return Px + (r11 * x + r12 * y + r13 * z) * K,
           Py + (r21 * x + r22 * y + r23 * z) * K,
           Pz + (r31 * x + r32 * y + r33 * z) * K
end

local function shade(nx, ny, nz)
    local wx = r11 * nx + r12 * ny + r13 * nz
    local wy = r21 * nx + r22 * ny + r23 * nz
    local wz = r31 * nx + r32 * ny + r33 * nz
    local d = wx * Lx + wy * Ly + wz * Lz
    if d < 0 then d = 0 end
    return (0.42 + 0.58 * d) * light
end

local function quad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, nx, ny, nz, col, a)
    local s = shade(nx, ny, nz)
    local r, g, b = min(255, col[1] * s), min(255, col[2] * s), min(255, col[3] * s)
    a = a or 255
    local x1, y1, z1 = W(ax, ay, az)
    local x2, y2, z2 = W(bx, by, bz)
    local x3, y3, z3 = W(cx, cy, cz)
    local x4, y4, z4 = W(dx, dy, dz)
    vert(x1, y1, z1, r, g, b, a); vert(x2, y2, z2, r, g, b, a); vert(x3, y3, z3, r, g, b, a)
    vert(x1, y1, z1, r, g, b, a); vert(x3, y3, z3, r, g, b, a); vert(x4, y4, z4, r, g, b, a)
end

local function box(cx, cy, cz, hx, hy, hz, yaw, pitch, col, a)
    local cyw, syw = cos(yaw or 0), sin(yaw or 0)
    local cp, sp = cos(pitch or 0), sin(pitch or 0)
    local ex1, ex2, ex3 = cyw * cp, syw * cp, -sp
    local ey1, ey2, ey3 = -syw, cyw, 0
    local ez1, ez2, ez3 = cyw * sp, syw * sp, cp
    local function P(sx, sy, sz)
        return cx + ex1 * hx * sx + ey1 * hy * sy + ez1 * hz * sz,
               cy + ex2 * hx * sx + ey2 * hy * sy + ez2 * hz * sz,
               cz + ex3 * hx * sx + ey3 * hy * sy + ez3 * hz * sz
    end
    local ax, ay, az = P(-1, -1, -1); local bx, by, bz = P(1, -1, -1)
    local cx2, cy2, cz2 = P(1, 1, -1); local dx, dy, dz = P(-1, 1, -1)
    local ex, ey, ez = P(-1, -1, 1); local fx, fy, fz = P(1, -1, 1)
    local gx, gy, gz = P(1, 1, 1); local hx2, hy2, hz2 = P(-1, 1, 1)
    quad(ex, ey, ez, fx, fy, fz, gx, gy, gz, hx2, hy2, hz2, ez1, ez2, ez3, col, a)
    quad(ax, ay, az, dx, dy, dz, cx2, cy2, cz2, bx, by, bz, -ez1, -ez2, -ez3, col, a)
    quad(bx, by, bz, cx2, cy2, cz2, gx, gy, gz, fx, fy, fz, ex1, ex2, ex3, col, a)
    quad(ax, ay, az, ex, ey, ez, hx2, hy2, hz2, dx, dy, dz, -ex1, -ex2, -ex3, col, a)
    quad(dx, dy, dz, hx2, hy2, hz2, gx, gy, gz, cx2, cy2, cz2, ey1, ey2, ey3, col, a)
    quad(ax, ay, az, bx, by, bz, fx, fy, fz, ex, ey, ez, -ey1, -ey2, -ey3, col, a)
end

local function cylinder(cx, cy, z0, z1, rad, seg, col, rot)
    rot = rot or 0
    local s = shade(0, 0, 1)
    local r, g, b = min(255, col[1] * s), min(255, col[2] * s), min(255, col[3] * s)
    local tx, ty, tz = W(cx, cy, z1)
    for i = 0, seg - 1 do
        local a0 = rot + i / seg * 2 * pi
        local a1 = rot + (i + 1) / seg * 2 * pi
        local x0, y0 = cx + cos(a0) * rad, cy + sin(a0) * rad
        local x1, y1 = cx + cos(a1) * rad, cy + sin(a1) * rad
        local am = (a0 + a1) * 0.5
        quad(x0, y0, z0, x1, y1, z0, x1, y1, z1, x0, y0, z1, cos(am), sin(am), 0, col)
        local px0, py0, pz0 = W(x0, y0, z1)
        local px1, py1, pz1 = W(x1, y1, z1)
        vert(tx, ty, tz, r, g, b, 255); vert(px0, py0, pz0, r, g, b, 255); vert(px1, py1, pz1, r, g, b, 255)
    end
end

local function disc(cx, cy, z, rad, seg, col, aCenter, aEdge)
    local s = shade(0, 0, 1)
    local r, g, b = min(255, col[1] * s), min(255, col[2] * s), min(255, col[3] * s)
    local tx, ty, tz = W(cx, cy, z)
    for i = 0, seg - 1 do
        local a0 = i / seg * 2 * pi
        local a1 = (i + 1) / seg * 2 * pi
        local x0, y0, z0 = W(cx + cos(a0) * rad, cy + sin(a0) * rad, z)
        local x1, y1, z1 = W(cx + cos(a1) * rad, cy + sin(a1) * rad, z)
        vert(tx, ty, tz, r, g, b, aCenter); vert(x0, y0, z0, r, g, b, aEdge); vert(x1, y1, z1, r, g, b, aEdge)
    end
end

local CARBON = { 38, 38, 42 }
local CARBON_EDGE = { 55, 55, 60 }
local ALU = { 120, 70, 190 }
local MOTOR_BASE = { 30, 30, 32 }
local MOTOR_BELL = { 170, 30, 40 }
local MOTOR_TOP = { 60, 60, 65 }
local PROP = { 120, 60, 220 }
local CAM = { 18, 18, 20 }
local LENS = { 8, 10, 22 }
local BATT = { 30, 30, 34 }
local BATT_LABEL = { 225, 175, 20 }
local STRAP = { 15, 15, 15 }
local ANT = { 20, 20, 20 }
local ANT_TIP = { 200, 200, 205 }

local function setTransform(px, py, pz, m11, m12, m13, m21, m22, m23, m31, m32, m33, scale)
    Px, Py, Pz = px, py, pz
    r11, r12, r13, r21, r22, r23, r31, r32, r33 = m11, m12, m13, m21, m22, m23, m31, m32, m33
    K = 1 / scale
    local lc = render.GetLightColor(Vector(px, py, pz))
    local lum = (lc.x * 0.3 + lc.y * 0.59 + lc.z * 0.11)
    light = max(0.22, min(1.15, lum * 1.6 + 0.18))
end

local function drawBody(quad_, opts)
    local a = quad_.arm
    local pz = quad_.propZ
    for i = 1, 4 do
        local m = quad_.motors[i]
        local mx, my = m[1], m[2]
        local yaw = math.atan2(my, mx)
        local len = sqrt(mx * mx + my * my)
        box(mx * 0.5, my * 0.5, -0.003, len * 0.5 + 0.012, 0.0085, 0.0028, yaw, 0, CARBON)
    end
    box(0, 0, -0.008, 0.062, 0.024, 0.0018, 0, 0, CARBON_EDGE)
    box(-0.004, 0, 0.026, 0.052, 0.023, 0.0015, 0, 0, CARBON)
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            box(sx * 0.036, sy * 0.019, 0.009, 0.0025, 0.0025, 0.016, 0, 0, ALU)
        end
    end
    box(-0.008, 0, 0.008, 0.019, 0.019, 0.010, 0, 0, { 20, 70, 35 })
    if not opts.hideCamera then
        local t = math.rad(opts.uptilt or 30)
        box(0.045, 0, 0.010, 0.0105, 0.0095, 0.0095, 0, -t, CAM)
        box(0.045 + cos(t) * 0.013, 0, 0.010 + sin(t) * 0.013, 0.004, 0.0062, 0.0062, 0, -t, LENS)
        box(0.046, 0.0125, 0.010, 0.012, 0.0012, 0.011, 0, 0, ALU)
        box(0.046, -0.0125, 0.010, 0.012, 0.0012, 0.011, 0, 0, ALU)
    end
    box(-0.006, 0, 0.046, 0.040, 0.0175, 0.0175, 0, 0, BATT)
    box(-0.006, 0, 0.046, 0.0405, 0.0178, 0.0055, 0, 0, BATT_LABEL)
    box(-0.010, 0, 0.040, 0.008, 0.0182, 0.0245, 0, 0, STRAP)
    box(-0.072, 0, 0.040, 0.0018, 0.0018, 0.026, 0, math.rad(-35), ANT)
    box(-0.087, 0, 0.061, 0.004, 0.004, 0.007, 0, math.rad(-35), ANT_TIP)
    for i = 1, 4 do
        local m = quad_.motors[i]
        cylinder(m[1], m[2], 0.0, 0.006, 0.0125, 10, MOTOR_BASE)
        cylinder(m[1], m[2], 0.006, pz - 0.003, 0.0135, 12, MOTOR_BELL, opts.propAng and opts.propAng[i] or 0)
        cylinder(m[1], m[2], pz - 0.003, pz + 0.004, 0.004, 6, MOTOR_TOP)
    end
end

local function propsHidden(opts)
    local v = FPV.Config and FPV.Config.data and FPV.Config.data.video
    local p = v and v.props or "show"
    return p == "hide" or (p == "hidefpv" and opts and opts.fpv == true)
end
R.PropsHidden = propsHidden

local function drawBlades(quad_, opts, translucentPass)
    if propsHidden(opts) then return end
    local Rp = quad_.propD * 0.5
    local pz = quad_.propZ
    for i = 1, 4 do
        local m = quad_.motors[i]
        local w = opts.motorW and opts.motorW[i] or 0
        local ang = opts.propAng and opts.propAng[i] or (i * 0.7)
        local h = opts.health and opts.health[i] or 1
        if w < 0 then w = -w end
        local fast = w > 140
        if fast and translucentPass then
            local k = min(1, (w - 140) / 600)
            local hr = Rp * (0.35 + 0.65 * h)
            disc(m[1], m[2], pz, hr, 24, PROP, (30 + 30 * k) * (0.4 + 0.6 * h), (55 + 40 * k) * (0.4 + 0.6 * h))
        elseif not fast and not translucentPass then
            for b = 0, (quad_.propBlades or 3) - 1 do
                local yaw = ang + b * 2 * pi / (quad_.propBlades or 3)
                local len = Rp * 0.48 * (h >= 1 and 1 or (0.25 + 0.75 * h * (0.6 + 0.4 * ((b * 37 + i * 11) % 7) / 6)))
                local rr = 0.04 * Rp + len
                box(m[1] + cos(yaw) * rr, m[2] + sin(yaw) * rr, pz, len, 0.0062, 0.0011,
                    yaw, math.rad(m[3] * 12), PROP)
            end
        end
    end
end

local function legacyDrawCraft(sim, quad_, scale, translucent, opts)
    local m11, m12, m13, m21, m22, m23, m31, m32, m33 = FPV.Sim.quatToMat(sim.qw, sim.qx, sim.qy, sim.qz)
    setTransform(sim.px / scale, sim.py / scale, sim.pz / scale, m11, m12, m13, m21, m22, m23, m31, m32, m33, scale)
    opts.propAng = sim.propAng
    opts.motorW = sim.mw
    opts.health = sim.propHealth
    if translucent then
        drawBlades(quad_, opts, true)
        flush(matTrans)
    else
        drawBody(quad_, opts)
        drawBlades(quad_, opts, false)
        flush(matSolid)
    end
end

local entQuad
local entOpts = { uptilt = 30 }
local function legacyDrawEntity(ent, translucent)
    if translucent then return end
    entQuad = entQuad or FPV.Presets.get("mayhem_x5")
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local scale = (FPV.Config and FPV.Config.data and FPV.Config.data.sim.worldScale) or FPV.DEFAULT_SCALE
    setTransform(pos.x, pos.y, pos.z, f.x, -r.x, u.x, f.y, -r.y, u.y, f.z, -r.z, u.z, scale)
    entOpts.uptilt = FPV.Config and FPV.Config.data.camera.uptilt or 30
    entOpts.propAng = nil
    entOpts.motorW = nil
    entOpts.health = nil
    drawBody(entQuad, entOpts)
    drawBlades(entQuad, entOpts, false)
    flush(matSolid)
end

local Model = FPV.Model
local DEFS = Model.MATERIALS
local WHITE = Color(255, 255, 255)
local meshes, builtKey
local matCache, textures = {}, {}
R.failed = false

local function shadingMode()
    if R.failed then return "legacy" end
    local v = FPV.Config and FPV.Config.data and FPV.Config.data.video
    return (v and v.model) or "lit"
end

local function pngTexture(name)
    if textures[name] ~= nil then return textures[name] or nil end
    local m = Material("mayhem_fpv/" .. name .. ".png", "mips smooth")
    local tex = (m and not m:IsError()) and m:GetTexture("$basetexture") or false
    textures[name] = tex
    return tex or nil
end

local function material(shading, name)
    local key = shading .. "/" .. name
    local m = matCache[key]
    if m then return m end
    local def = DEFS[name]
    local c = def.color
    if shading == "lit" then
        m = CreateMaterial("mayhem_x5_lit_v1_" .. name, "VertexLitGeneric", {
            ["$basetexture"] = "vgui/white",
            ["$color2"] = string.format("[%.3f %.3f %.3f]", c[1] / 255, c[2] / 255, c[3] / 255),
            ["$nocull"] = "1",
        })
    else
        m = CreateMaterial("mayhem_x5_simple_v1_" .. name, "UnlitGeneric", {
            ["$basetexture"] = "vgui/white",
            ["$vertexcolor"] = "1",
            ["$nocull"] = "1",
        })
    end
    if def.tex then
        local t = pngTexture(def.tex)
        if t then m:SetTexture("$basetexture", t) end
    end
    matCache[key] = m
    return m
end

local BLX, BLY, BLZ = 0.35, 0.25, 0.9
do local n = sqrt(BLX * BLX + BLY * BLY + BLZ * BLZ); BLX, BLY, BLZ = BLX / n, BLY / n, BLZ / n end

local function propColor()
    local v = FPV.Config and FPV.Config.data and FPV.Config.data.video
    return (v and v.propColor == "orange") and "orange" or "smoke"
end

local function buildMeshes(quad_, scale, shading)
    if meshes then
        for _, ms in pairs(meshes) do for _, m in pairs(ms) do m:Destroy() end end
    end
    meshes = {}
    local K = 1 / scale
    local parts = Model.build(quad_, { propColor = propColor() })
    local count = 0
    for part, ms in pairs(parts) do
        meshes[part] = {}
        for mname, list in pairs(ms) do
            local c = DEFS[mname].color
            local verts = {}
            for i = 1, #list do
                local v = list[i]
                local col = WHITE
                if shading == "simple" then
                    local d = v[4] * BLX + v[5] * BLY + v[6] * BLZ
                    local sh = 0.42 + 0.58 * (d > 0 and d or 0)
                    col = Color(min(255, c[1] * sh), min(255, c[2] * sh), min(255, c[3] * sh))
                end
                verts[i] = { pos = Vector(v[1] * K, v[2] * K, v[3] * K), normal = Vector(v[4], v[5], v[6]), u = v[7], v = v[8], color = col }
            end
            local m = Mesh()
            m:BuildFromTriangles(verts)
            meshes[part][mname] = m
            count = count + #list / 3
        end
    end
    R.triangles = count
end

local function ensureMeshes(quad_, scale, shading)
    local key = shading .. "@" .. scale .. "@" .. propColor()
    if builtKey == key and meshes then return true end
    local ok, err = pcall(buildMeshes, quad_, scale, shading)
    if not ok then
        R.failed = true
        print("[Mayhem FPV] model build failed, using low-poly model: " .. tostring(err))
        return false
    end
    builtKey = key
    return true
end

local DIRS = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1) }
local lightPos = Vector()
local colVec = Vector()
local function beginLighting(shading, x, y, z)
    local bright = (FPV.Config.data.video.modelBrightness or 1)
    lightPos:SetUnpacked(x, y, z)
    local amb = render.GetLightColor(lightPos)
    if shading == "lit" then
        render.SuppressEngineLighting(true)
        for i = 1, 6 do
            local c = render.ComputeLighting and render.ComputeLighting(lightPos, DIRS[i]) or amb
            render.SetModelLighting(i - 1,
                max(c.x, amb.x * 0.5, 0.03) * bright,
                max(c.y, amb.y * 0.5, 0.03) * bright,
                max(c.z, amb.z * 0.5, 0.03) * bright)
        end
    else
        local lum = amb.x * 0.3 + amb.y * 0.59 + amb.z * 0.11
        local l = max(0.25, min(1.2, lum * 1.6 + 0.2)) * bright
        colVec:SetUnpacked(l, l, l)
        for key, m in pairs(matCache) do
            if string.sub(key, 1, 7) == "simple/" then m:SetVector("$color", colVec) end
        end
    end
end

local vm = Matrix()
local function drawInstances(px, py, pz, b11, b12, b13, b21, b22, b23, b31, b32, b33, K, inst, n, shading)
    for k = 1, n do
        local t = inst[k]
        local ms = meshes[t.part]
        if ms then
            local i11, i12, i13, i21, i22, i23, i31, i32, i33 = t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9]
            local sx = t.sx
            local c11 = (b11 * i11 + b12 * i21 + b13 * i31) * sx
            local c21 = (b21 * i11 + b22 * i21 + b23 * i31) * sx
            local c31 = (b31 * i11 + b32 * i21 + b33 * i31) * sx
            local c12 = b11 * i12 + b12 * i22 + b13 * i32
            local c22 = b21 * i12 + b22 * i22 + b23 * i32
            local c32 = b31 * i12 + b32 * i22 + b33 * i32
            local c13 = b11 * i13 + b12 * i23 + b13 * i33
            local c23 = b21 * i13 + b22 * i23 + b23 * i33
            local c33 = b31 * i13 + b32 * i23 + b33 * i33
            local tx = px + (b11 * t.tx + b12 * t.ty + b13 * t.tz) * K
            local ty = py + (b21 * t.tx + b22 * t.ty + b23 * t.tz) * K
            local tz = pz + (b31 * t.tx + b32 * t.ty + b33 * t.tz) * K
            vm:SetUnpacked(c11, c12, c13, tx, c21, c22, c23, ty, c31, c32, c33, tz, 0, 0, 0, 1)
            cam.PushModelMatrix(vm)
            for mname, m in pairs(ms) do
                render.SetMaterial(material(shading, mname))
                m:Draw()
            end
            cam.PopModelMatrix()
        end
    end
end

local st = {}
local function drawModel(quad_, scale, px, py, pz, b11, b12, b13, b21, b22, b23, b31, b32, b33, o)
    local shading = shadingMode()
    if not ensureMeshes(quad_, scale, shading) then return false end
    st.propAng, st.motorW, st.health = o.propAng, o.motorW, o.health
    st.uptilt, st.hideCamera, st.spinLimit = o.uptilt, o.hideCamera, 140
    st.hideProps = propsHidden(o)
    local v = FPV.Config.data.video
    st.hideActionCam = v.actionCam == false
    local inst, n = Model.instances(quad_, st)
    beginLighting(shading, px, py, pz)
    local ok, err = pcall(drawInstances, px, py, pz, b11, b12, b13, b21, b22, b23, b31, b32, b33, 1 / scale, inst, n, shading)
    if shading == "lit" then render.SuppressEngineLighting(false) end
    if not ok then
        R.failed = true
        print("[Mayhem FPV] model draw failed, using low-poly model: " .. tostring(err))
    end
    return ok
end

local function drawDiscs(quad_, o)
    if propsHidden(o) then return end
    local col = (propColor() == "orange") and Model.MATERIALS.prop.color or Model.MATERIALS.propSmoke.color
    local Rp = quad_.propD * 0.5
    local z = Model.BLADE_Z
    for i = 1, 4 do
        local w = o.motorW and math.abs(o.motorW[i]) or 0
        if w > 140 then
            local m = quad_.motors[i]
            local h = o.health and o.health[i] or 1
            local k = min(1, (w - 140) / 600)
            disc(m[1], m[2], z, Rp * (0.35 + 0.65 * h), 28, col,
                (26 + 26 * k) * (0.4 + 0.6 * h), (48 + 36 * k) * (0.4 + 0.6 * h))
        end
    end
    flush(matTrans)
end

function R.DrawCraft(sim, quad_, scale, translucent, opts)
    if shadingMode() == "legacy" then return legacyDrawCraft(sim, quad_, scale, translucent, opts) end
    local m11, m12, m13, m21, m22, m23, m31, m32, m33 = FPV.Sim.quatToMat(sim.qw, sim.qx, sim.qy, sim.qz)
    local px, py, pz = sim.px / scale, sim.py / scale, sim.pz / scale
    opts.propAng, opts.motorW, opts.health = sim.propAng, sim.mw, sim.propHealth
    if translucent then
        setTransform(px, py, pz, m11, m12, m13, m21, m22, m23, m31, m32, m33, scale)
        drawDiscs(quad_, opts)
        return
    end
    if not drawModel(quad_, scale, px, py, pz, m11, m12, m13, m21, m22, m23, m31, m32, m33, opts) then
        legacyDrawCraft(sim, quad_, scale, false, opts)
    end
end

local idleOpts = { uptilt = 30 }
function R.DrawEntity(ent, translucent)
    if translucent then return end
    if shadingMode() == "legacy" then return legacyDrawEntity(ent, translucent) end
    entQuad = entQuad or FPV.Presets.get("mayhem_x5")
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local scale = (FPV.Config and FPV.Config.data and FPV.Config.data.sim.worldScale) or FPV.DEFAULT_SCALE
    idleOpts.uptilt = FPV.Config and FPV.Config.data.camera.uptilt or 30
    if not drawModel(entQuad, scale, pos.x, pos.y, pos.z, f.x, -r.x, u.x, f.y, -r.y, u.y, f.z, -r.z, u.z, idleOpts) then
        legacyDrawEntity(ent, translucent)
    end
end

function R.Invalidate()
    builtKey = nil
    R.failed = false
end
