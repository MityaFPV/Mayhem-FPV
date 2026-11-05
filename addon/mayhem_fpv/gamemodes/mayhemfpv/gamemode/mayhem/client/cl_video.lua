local FPV = MayhemFPV

local V = {}
FPV.Video = V

local log10 = math.log10
local random, min, max, sqrt, sin, floor = math.random, math.min, math.max, math.sqrt, math.sin, math.floor

V.quality = 1
V.rssiDbm = -40
V.lq = 100
V.wallLoss = 0
V.nextLink = 0

local tr = { mask = MASK_SOLID_BRUSHONLY, output = {} }
local vs, ve = Vector(), Vector()
local function trace(x0, y0, z0, x1, y1, z1)
    local k = FPV.Flight.invScale
    vs:SetUnpacked(x0 * k, y0 * k, z0 * k)
    ve:SetUnpacked(x1 * k, y1 * k, z1 * k)
    tr.start, tr.endpos = vs, ve
    util.TraceLine(tr)
    local o = tr.output
    return o.Hit, o.Fraction, o.StartSolid, o.FractionLeftSolid or 0, o.AllSolid
end

local linkParams = {}
local function updateLink(F)
    local cfg = FPV.Config.data.video
    local sim = F.craft.sim
    local s = F.scale
    local eye = LocalPlayer():EyePos()
    linkParams.vtxMw = cfg.vtxPower or 600
    linkParams.rxMw = cfg.rxPower or 250
    linkParams.sens = -108
    local r = FPV.Link.evaluate(trace, { eye.x * s, eye.y * s, eye.z * s }, { sim.px, sim.py, sim.pz }, linkParams, sim.groundDist)
    V.link = r
    V.rssiDbm = r.rx58
    V.quality = r.quality
    V.lq = math.floor(r.lq + 0.5)
    V.rxDbm = r.rx24
end

local noiseMats = {}
local fbMat = CreateMaterial("mayhem_video_fb_v1", "UnlitGeneric", {
    ["$basetexture"] = "_rt_FullFrameFB",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
    ["$ignorez"] = "1",
})

local function buildNoise()
    if #noiseMats > 0 then return end
    for i = 1, 4 do
        local rt = GetRenderTarget("mayhem_noise_v1_" .. i, 128, 128)
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 255)
        cam.Start2D()
        for y = 0, 127 do
            for x = 0, 127, 2 do
                local r = random()
                local v = r > 0.6 and floor(150 + r * 105) or floor(r * 70)
                surface.SetDrawColor(v, v, v, 255)
                surface.DrawRect(x, y, 2, 1)
            end
        end
        cam.End2D()
        render.PopRenderTarget()
        noiseMats[i] = CreateMaterial("mayhem_noise_mat_v1_" .. i, "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(),
            ["$vertexcolor"] = "1",
            ["$vertexalpha"] = "1",
            ["$translucent"] = "1",
        })
    end
end

function V.Update(F)
    local now = RealTime()
    if now >= V.nextLink then
        V.nextLink = now + 0.1
        updateLink(F)
    end
    local target = V.quality
    V.qSmooth = V.qSmooth or target
    local rate = (target < V.qSmooth) and 8 or 3
    V.qSmooth = V.qSmooth + (target - V.qSmooth) * min(1, FrameTime() * rate)
    V.q = max(0, min(1, V.qSmooth + (random() - 0.5) * 0.08 * (1 - V.qSmooth) * (1 - V.qSmooth)))
end

function V.Reset()
    V.qSmooth = nil
    V.quality = 1
    V.q = 1
    V.lq = 100
    V.nextLink = 0
end

local cm = {
    ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.01,
    ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1.1, ["$pp_colour_colour"] = 0.85,
    ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

local GX, GY = 32, 36
local poly = { {}, {}, {}, {} }
for i = 1, 4 do poly[i] = { x = 0, y = 0, u = 0, v = 0 } end

local function srcUV(x, y, k)
    local aspect = ScrW() / ScrH()
    local ax = x * aspect
    local r2 = (ax * ax + y * y) / (aspect * aspect)
    local rc2 = (aspect * aspect + 1) / (aspect * aspect)
    local s = (1 + k * r2) / (1 + k * rc2)
    return (x * s + 1) * 0.5, (y * s + 1) * 0.5
end

local rowShift = {}
local function wrapV(v) if v > 1 then return v - 1 end return v end

function V.DrawScreen(F)
    local cfg = FPV.Config.data.video
    if not cfg.enabled then return end
    local q = V.q or 1
    local bad = 1 - q
    local W, H = ScrW(), ScrH()

    if DrawColorModify then
        cm["$pp_colour_colour"] = (cfg.saturation or 0.85) * (1 - max(0, bad - 0.6) * 2.2)
        cm["$pp_colour_contrast"] = 1.08 + bad * bad * 0.25
        cm["$pp_colour_brightness"] = -0.01 - bad * bad * 0.05
        cm["$pp_colour_addb"] = 0.012
        DrawColorModify(cm)
    end

    local fish = cfg.fisheye or 0
    local tearAmt = max(0, bad - 0.5) * 2
    if fish <= 0.001 and tearAmt <= 0.01 then return end

    render.UpdateScreenEffectTexture()
    local slip = (bad > 0.75 and random() < (bad - 0.75) * 0.4) and (random() - 0.5) * 0.25 or 0
    for r = 0, GY do
        local j = 0
        if tearAmt > 0 then
            j = (random() - 0.5) * 0.02 * tearAmt
            if random() < tearAmt * 0.15 then j = j + (random() - 0.5) * 0.08 * tearAmt end
        end
        rowShift[r] = j + slip
    end
    local roll = (bad > 0.85 and random() < 0.1) and random() * 0.15 or 0

    cam.Start2D()
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, W, H)
    surface.SetMaterial(fbMat)
    surface.SetDrawColor(255, 255, 255, 255)
    local k = fish * 0.55
    for gy = 0, GY - 1 do
        local y0, y1 = gy / GY * 2 - 1, (gy + 1) / GY * 2 - 1
        local sh0, sh1 = rowShift[gy], rowShift[gy + 1]
        for gx = 0, GX - 1 do
            local x0, x1 = gx / GX * 2 - 1, (gx + 1) / GX * 2 - 1
            local u00, v00 = srcUV(x0, y0, k)
            local u10, v10 = srcUV(x1, y0, k)
            local u11, v11 = srcUV(x1, y1, k)
            local u01, v01 = srcUV(x0, y1, k)
            local p = poly
            p[1].x, p[1].y, p[1].u, p[1].v = (x0 + 1) * 0.5 * W, (y0 + 1) * 0.5 * H, u00 + sh0, wrapV(v00 + roll)
            p[2].x, p[2].y, p[2].u, p[2].v = (x1 + 1) * 0.5 * W, (y0 + 1) * 0.5 * H, u10 + sh0, wrapV(v10 + roll)
            p[3].x, p[3].y, p[3].u, p[3].v = (x1 + 1) * 0.5 * W, (y1 + 1) * 0.5 * H, u11 + sh1, wrapV(v11 + roll)
            p[4].x, p[4].y, p[4].u, p[4].v = (x0 + 1) * 0.5 * W, (y1 + 1) * 0.5 * H, u01 + sh1, wrapV(v01 + roll)
            surface.DrawPoly(p)
        end
    end
    cam.End2D()
end

function V.DrawOverlay(F)
    local cfg = FPV.Config.data.video
    if not cfg.enabled then return end
    buildNoise()
    local W, H = ScrW(), ScrH()
    local q = V.q or 1
    local bad = 1 - q
    local base = cfg.noise or 1

    local a = (0.03 + bad ^ 2.2 * 0.9) * base
    if a > 0.004 and #noiseMats > 0 then
        surface.SetMaterial(noiseMats[random(1, #noiseMats)])
        surface.SetDrawColor(255, 255, 255, min(255, a * 255))
        local u, v = random(), random()
        local sx = W / 256
        local sy = H / 256 * 0.6
        surface.DrawTexturedRectUV(0, 0, W, H, u, v, u + sx, v + sy)
    end

    if bad > 0.4 then
        local n = floor((bad - 0.4) * 22 * base)
        for _ = 1, n do
            local y = random() * H
            local h = 1 + random() * 3 * bad
            local c = random() < 0.5 and 255 or 0
            surface.SetDrawColor(c, c, c, 60 + 120 * bad)
            surface.DrawRect(0, y, W, h)
        end
    end

    if cfg.scanlines then
        surface.SetDrawColor(0, 0, 0, 28)
        for y = 0, H, 3 do surface.DrawRect(0, y, W, 1) end
    end

    if q < 0.12 then
        local drop = (0.12 - q) / 0.12
        if random() < drop * 0.9 then
            surface.SetDrawColor(10, 10, 12, 200 + 55 * drop)
            surface.DrawRect(0, 0, W, H)
            if #noiseMats > 0 then
                surface.SetMaterial(noiseMats[random(1, #noiseMats)])
                surface.SetDrawColor(255, 255, 255, 220 * base)
                local u, v = random(), random()
                surface.DrawTexturedRectUV(0, 0, W, H, u, v, u + W / 200, v + H / 260)
            end
        end
    end
end

return V
