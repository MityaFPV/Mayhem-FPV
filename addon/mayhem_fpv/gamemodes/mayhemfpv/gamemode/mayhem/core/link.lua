local Link = {}

local sqrt, log10, min, max, abs = math.sqrt, math.log10, math.min, math.max, math.abs

local C = 299792458
local LAMBDA58 = C / 5.8e9
local LAMBDA24 = C / 2.4e9

local BAND = {
    v = { lambda = LAMBDA58, fsplK = 47.7, penBase = 10, penPerM = 40, floor = 22, floorEnclosed = 14 },
    c = { lambda = LAMBDA24, fsplK = 40.05, penBase = 6, penPerM = 25, floor = 15, floorEnclosed = 10 },
}
Link.BAND = BAND

local PEN_THICK_CAP = 0.4
local MERGE_GAP = 1.0

function Link.knifeEdge(v)
    if v <= -0.78 then return 0 end
    local a = v - 0.1
    return 6.9 + 20 * log10(sqrt(a * a + 1) + a)
end

function Link.solids(trace, ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-3 then return {}, len end
    local ux, uy, uz = dx / len, dy / len, dz / len
    local segs = {}
    local t = 0
    local eps = 0.03
    for _ = 1, 32 do
        if t >= len then break end
        local sx, sy, sz = ax + ux * t, ay + uy * t, az + uz * t
        local remain = len - t
        local hit, frac, ss, left, all = trace(sx, sy, sz, bx, by, bz)
        if ss then
            local exitT
            if all then exitT = len else exitT = t + (left or 0) * remain end
            if exitT < t + eps then exitT = t + eps end
            local last = segs[#segs]
            if last and t - last[2] < MERGE_GAP then
                if exitT > last[2] then last[2] = exitT end
            else
                segs[#segs + 1] = { t, exitT }
            end
            t = exitT + eps
        elseif hit then
            local enter = t + frac * remain
            local last = segs[#segs]
            if last and enter - last[2] < MERGE_GAP then
                if enter + eps > last[2] then last[2] = enter + eps end
            else
                segs[#segs + 1] = { enter, enter + eps }
            end
            t = enter + eps
        else
            break
        end
    end
    return segs, len
end

local function clear(trace, ax, ay, az, bx, by, bz)
    local hit, _, ss = trace(ax, ay, az, bx, by, bz)
    return not hit and not ss
end

local PROBE = {
    { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 },
    { 0.707, 0.707, 0 }, { -0.707, 0.707, 0 }, { 0.707, -0.707, 0 }, { -0.707, -0.707, 0 },
    { 0, 0, 1 }, { 0.6, 0, 0.8 }, { -0.6, 0, 0.8 }, { 0, 0.6, 0.8 }, { 0, -0.6, 0.8 },
}
function Link.enclosure(trace, x, y, z, range)
    range = range or 20
    local blocked = 0
    for i = 1, #PROBE do
        local p = PROBE[i]
        local hit, _, ss = trace(x, y, z, x + p[1] * range, y + p[2] * range, z + p[3] * range)
        if hit or ss then blocked = blocked + 1 end
    end
    return blocked / #PROBE
end

local UP = { 1.5, 4, 10, 25 }
local SIDE = { 2, 6, 15 }
function Link.bestDetour(trace, ax, ay, az, bx, by, bz, d)
    local best = nil
    local hx, hy = bx - ax, by - ay
    local hl = sqrt(hx * hx + hy * hy)
    local px, py = 0, 1
    if hl > 1e-3 then px, py = -hy / hl, hx / hl end
    local function try(x, y, z)
        local l1 = sqrt((x - ax) ^ 2 + (y - ay) ^ 2 + (z - az) ^ 2)
        local l2 = sqrt((x - bx) ^ 2 + (y - by) ^ 2 + (z - bz) ^ 2)
        local delta = l1 + l2 - d
        if best and delta >= best then return end
        if clear(trace, ax, ay, az, x, y, z) and clear(trace, x, y, z, bx, by, bz) then
            best = delta
        end
    end
    for _, end_ in ipairs({ { bx, by, bz }, { ax, ay, az } }) do
        local ex, ey, ez = end_[1], end_[2], end_[3]
        for _, h in ipairs(UP) do try(ex, ey, ez + h) end
        for _, s in ipairs(SIDE) do
            try(ex + px * s, ey + py * s, ez + 1)
            try(ex - px * s, ey - py * s, ez + 1)
        end
    end
    return best
end

function Link.evaluate(trace, pilot, drone, p, groundDist)
    local ax, ay, az = pilot[1], pilot[2], pilot[3]
    local bx, by, bz = drone[1], drone[2], drone[3]
    local d = max(1, sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2))
    local r = { dist = d, obstacles = 0, obsV = 0, obsC = 0, via = "clear" }

    local segs = Link.solids(trace, ax, ay, az, bx, by, bz)
    if #segs > 0 then
        r.obstacles = #segs
        local penV, penC = 0, 0
        for _, sg in ipairs(segs) do
            local th = min(PEN_THICK_CAP, max(0.05, sg[2] - sg[1]))
            penV = penV + BAND.v.penBase + BAND.v.penPerM * th
            penC = penC + BAND.c.penBase + BAND.c.penPerM * th
        end
        local delta = Link.bestDetour(trace, ax, ay, az, bx, by, bz, d)
        local difV, difC = 1e9, 1e9
        if delta then
            difV = Link.knifeEdge(2 * sqrt(delta / BAND.v.lambda))
            difC = Link.knifeEdge(2 * sqrt(delta / BAND.c.lambda))
        end
        local enc = Link.enclosure(trace, bx, by, bz, 20)
        local flV = BAND.v.floor + BAND.v.floorEnclosed * enc
        local flC = BAND.c.floor + BAND.c.floorEnclosed * enc
        r.obsV = min(penV, difV, flV)
        r.obsC = min(penC, difC, flC)
        r.enclosure = enc
        r.via = (r.obsV == penV) and "through" or ((r.obsV == difV) and "around" or "reflected")
    end

    local fres = 0
    local h = min(groundDist or 100, 10)
    if d > 60 and h < 1.5 then fres = (1.5 - h) / 1.5 * min(6, (d - 60) / 40) end

    local txV = 10 * log10(max(1, p.vtxMw or 600))
    r.rx58 = txV + 5 - (20 * log10(d) + BAND.v.fsplK) - r.obsV - fres
    local txC = 10 * log10(max(1, p.rxMw or 250))
    r.rx24 = txC + 4 - (20 * log10(d) + BAND.c.fsplK) - r.obsC - fres * 0.5

    r.quality = max(0, min(1, (r.rx58 + 92) / 20))
    local margin = r.rx24 - (p.sens or -108)
    r.margin = margin
    r.lq = max(0, min(100, (margin + 3) / 11 * 100))
    return r
end

return Link
