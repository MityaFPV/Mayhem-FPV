local root = arg and arg[1]
if not root then
    local f = io.open("../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/link.lua")
    root = f and "../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/" or "../addon/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/"
    if f then f:close() end
end
local Link = dofile(root .. "link.lua")

local boxes = {}
local function box(x0, y0, z0, x1, y1, z1) boxes[#boxes + 1] = { x0, y0, z0, x1, y1, z1 } end
local function hollow(x0, y0, x1, y1, h, door)
    local t = 0.3
    box(x0, y0, 0, x1, y0 + t, h)
    if door then
        boxes[#boxes] = nil
        local mx = (x0 + x1) / 2
        box(x0, y0, 0, mx - 1.5, y0 + t, h)
        box(mx + 1.5, y0, 0, x1, y0 + t, h)
        box(mx - 1.5, y0, 3, mx + 1.5, y0 + t, h)
    end
    box(x0, y1 - t, 0, x1, y1, h)
    box(x0, y0, 0, x0 + t, y1, h)
    box(x1 - t, y0, 0, x1, y1, h)
    box(x0, y0, h - t, x1, y1, h)
end

local function trace(x0, y0, z0, x1, y1, z1)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local bestEnter, startSolid, leave = 2, false, 0
    local all = false
    local function slab(p, d, lo, hi, tmin, tmax)
        if math.abs(d) < 1e-12 then
            if p < lo or p > hi then return nil end
            return tmin, tmax
        end
        local a, b = (lo - p) / d, (hi - p) / d
        if a > b then a, b = b, a end
        return math.max(tmin, a), math.min(tmax, b)
    end
    for _, b in ipairs(boxes) do
        local tmin, tmax = -1e9, 1e9
        tmin, tmax = slab(x0, dx, b[1], b[4], tmin, tmax)
        if tmin then tmin, tmax = slab(y0, dy, b[2], b[5], tmin, tmax) end
        if tmin then tmin, tmax = slab(z0, dz, b[3], b[6], tmin, tmax) end
        if tmin and tmin <= tmax then
            local inside = x0 > b[1] and x0 < b[4] and y0 > b[2] and y0 < b[5] and z0 > b[3] and z0 < b[6]
            if inside then
                startSolid = true
                if tmax >= 1 then all = true else leave = math.max(leave, tmax) end
            elseif tmin >= 0 and tmin <= 1 and tmin < bestEnter then
                bestEnter = tmin
            end
        end
    end
    if dz < 0 and z0 >= 0 and z1 < 0 then
        local t = z0 / -dz
        if t < bestEnter then bestEnter = t end
    end
    local hit = bestEnter <= 1
    return hit, hit and bestEnter or 1, startSolid, leave, all
end

local fails = 0
local function check(name, ok, msg)
    if not ok then fails = fails + 1 end
    print(string.format("[%s] %-44s %s", ok and "PASS" or "FAIL", name, msg or ""))
end
local P = { vtxMw = 600, rxMw = 250, sens = -108 }
local function eval(pilot, drone, p, gd)
    return Link.evaluate(trace, pilot, drone, p or P, gd or 5)
end
local function fmt(r)
    return string.format("d=%.0fm obs=%d lossV=%.1fdB (%s) rx58=%.1f q=%.2f rx24=%.1f LQ=%d",
        r.dist, r.obstacles, r.obsV, r.via, r.rx58, r.quality, r.rx24, math.floor(r.lq + 0.5))
end

local pilot = { 0, 0, 1.7 }

do
    boxes = {}
    local r = eval(pilot, { 100, 0, 5 })
    check("open 100 m: clean, LQ 100", r.quality > 0.99 and r.lq >= 100, fmt(r))
    r = eval(pilot, { 1000, 0, 20 })
    check("open 1 km 600 mW: mostly clean", r.quality > 0.7 and r.lq >= 100, fmt(r))
    r = eval(pilot, { 1000, 0, 20 }, { vtxMw = 25, rxMw = 250, sens = -108 })
    check("open 1 km 25 mW: noisy", r.quality < 0.6, fmt(r))
end

do
    boxes = {}
    box(40, -10, 0, 60, 10, 30)
    local r = eval(pilot, { 75, 0, 3 })
    check("behind solid building 75 m: usable video", r.quality > 0.55 and r.lq >= 100, fmt(r))
    boxes = {}
    for i = 0, 9 do box(40 + i * 2, -10, 0, 42 + i * 2, 10, 30) end
    local r2 = eval(pilot, { 75, 0, 3 })
    check("10 adjacent brushes = 1 obstacle", r2.obstacles == 1 and math.abs(r2.obsV - r.obsV) < 0.01, fmt(r2))
end

do
    boxes = {}
    hollow(30, 20, 60, 50, 12, true)
    local r = eval(pilot, { 45, 30, 2 })
    check("inside building 50 m away: light noise only", r.quality > 0.6 and r.lq >= 100, fmt(r))
    local r2 = eval(pilot, { 45, 45, 2 })
    check("deep inside, far wall: still flyable", r2.quality > 0.35 and r2.lq >= 100, fmt(r2))
end

do
    boxes = {}
    box(100, -15, 0, 130, 15, 40)
    box(180, -20, 0, 210, 20, 60)
    box(260, -15, 0, 290, 15, 45)
    local r = eval(pilot, { 320, 0, 3 })
    check("behind 3 blocks at 320 m: heavy noise", r.quality < 0.45, fmt(r))
    check("... control link still solid", r.lq >= 90, fmt(r))
    local r25 = eval(pilot, { 320, 0, 3 }, { vtxMw = 25, rxMw = 250, sens = -108 })
    check("... 25 mW video gone", r25.quality < 0.05, fmt(r25))
end

do
    boxes = {}
    local r = eval(pilot, { 20000, 0, 50 })
    check("20 km open: control still OK", r.lq > 80, fmt(r))
    r = eval(pilot, { 200000, 0, 50 })
    check("200 km: control lost", r.lq <= 0, fmt(r))
end

do
    local a, b, c = Link.knifeEdge(0), Link.knifeEdge(1), Link.knifeEdge(2.4)
    check("knife-edge formula", math.abs(a - 6.0) < 0.3 and math.abs(b - 13.9) < 0.6 and math.abs(c - 20.6) < 0.8,
        string.format("%.1f %.1f %.1f dB", a, b, c))
end

print(fails == 0 and "ALL LINK TESTS PASSED" or (fails .. " FAILURE(S)"))
