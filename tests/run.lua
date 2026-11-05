local root = arg and arg[1]
if not root then
    local f = io.open("../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/sim.lua")
    root = f and "../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/" or "../addon/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/"
    if f then f:close() end
end
local Rates = dofile(root .. "rates.lua")
local Presets = dofile(root .. "presets.lua")
local FC = dofile(root .. "fc.lua")
local Sim = dofile(root .. "sim.lua")
local Craft = dofile(root .. "craft.lua")
local Prop = dofile(root .. "prop.lua")
local Sensors = dofile(root .. "sensors.lua")
Sim.setProp(Prop)
local mods = { Rates = Rates, FC = FC, Sim = Sim, Sensors = Sensors }
PHYS = tonumber(os.getenv("PHYS") or "2")

math.randomseed(1234)
local EPS = 0.0008
local WALL_X = nil

local function trace(x0, y0, z0, x1, y1, z1)
    local bestT, nx, ny, nz = nil, 0, 0, 0
    if z0 < -1e-9 then return true, 0, 0, 0, 1, x0, y0, z0, true end
    if z1 < EPS and z1 < z0 then
        local t = (z0 - EPS) / (z0 - z1)
        if t < 0 then t = 0 end
        bestT, nx, ny, nz = t, 0, 0, 1
    end
    if WALL_X then
        if x0 > WALL_X then return true, 0, -1, 0, 0, x0, y0, z0, true end
        if x1 > WALL_X - EPS and x1 > x0 then
            local t = (WALL_X - EPS - x0) / (x1 - x0)
            if t < 0 then t = 0 end
            if not bestT or t < bestT then bestT, nx, ny, nz = t, -1, 0, 0 end
        end
    end
    if bestT then
        return true, bestT, nx, ny, nz, x0 + (x1 - x0) * bestT, y0 + (y1 - y0) * bestT, z0 + (z1 - z0) * bestT, false
    end
    return false, 1, 0, 0, 0, x1, y1, z1, false
end
local env = { trace = trace }
local envAir = {}

local function newCraft()
    local q = Presets.get("mayhem_x5")
    q.phys = PHYS
    local c = Craft.new(mods, q, Rates.defaults(), Presets.defaultPids(), Presets.defaultFcMisc())
    return c
end

local function nan(x) return x ~= x end
local function report(name, ok, msg)
    print(string.format("[%s] %-34s %s", ok and "PASS" or "FAIL", name, msg or ""))
end
local D2R = math.pi / 180
local R2D = 180 / math.pi
local FRAME = 1 / 144

local function run(c, t, ctrl, e, onFrame)
    local time = 0
    while time < t do
        local thr, r, p, y, arm, turtle = ctrl(c, time)
        Craft.setInput(c, thr, r, p, y, arm, turtle)
        Craft.advance(c, FRAME, e)
        time = time + FRAME
        if onFrame then onFrame(c, time) end
    end
end

local function tiltDeg(s)
    local _, _, _, _, _, _, _, _, r33 = Sim.matrix(s)
    return math.acos(math.max(-1, math.min(1, r33))) * R2D
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 0.03, 1, 0, 0, 0)
    run(c, 3, function() return 0, 0, 0, 0, false end, env)
    local s = c.sim
    local ok = (not nan(s.pz)) and s.pz > 0.005 and s.pz < 0.03 and math.abs(s.vz) < 0.01 and tiltDeg(s) < 2
    report("rest on ground", ok, string.format("z=%.4f m tilt=%.2f deg sleeping=%s contacts=%d", s.pz, tiltDeg(s), tostring(s.sleeping), s.nContacts))
end

local hoverThr
do
    local lo, hi = 0.0, 0.6
    for _ = 1, 22 do
        local mid = (lo + hi) / 2
        local c = newCraft()
        Sim.reset(c.sim, 0, 0, 20, 1, 0, 0, 0)
        run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
        run(c, 1.5, function() return mid, 0, 0, 0, true end, envAir)
        if c.sim.vz > 0 then hi = mid else lo = mid end
    end
    hoverThr = (lo + hi) / 2
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 20, 1, 0, 0, 0)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 2, function() return hoverThr, 0, 0, 0, true end, envAir)
    local s = c.sim
    local rpm = s.mw[1] * 60 / (2 * math.pi)
    report("hover throttle 15-30%", hoverThr > 0.15 and hoverThr < 0.30,
        string.format("hover=%.1f%% rpm=%.0f Ibat=%.1fA V=%.2f", hoverThr * 100, rpm, s.ibat, s.vbat))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 50, 1, 0, 0, 0)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 1, function() return hoverThr, 0, 0, 0, true end, envAir)
    local s = c.sim
    local t90, peakI, minV = nil, 0, 99
    local w0 = s.mw[1]
    local wTarget
    local samples = {}
    run(c, 3, function() return 1, 0, 0, 0, true end, envAir, function(cc, t)
        samples[#samples + 1] = { t, cc.sim.mw[1], cc.sim.vz }
        if cc.sim.ibat > peakI then peakI = cc.sim.ibat end
        if cc.sim.vbat < minV then minV = cc.sim.vbat end
    end)
    local wPeak = 0
    for _, sm in ipairs(samples) do if sm[1] < 0.2 and sm[2] > wPeak then wPeak = sm[2] end end
    for _, sm in ipairs(samples) do
        if not t90 and sm[2] - w0 >= 0.9 * (wPeak - w0) then t90 = sm[1] end
    end
    local thrust = 0
    for i = 1, 4 do thrust = thrust + s.thrust[i] end
    report("punch: spin-up 15-80 ms", t90 and t90 > 0.012 and t90 < 0.08,
        string.format("t90=%.0f ms, peak rpm=%.0f", (t90 or 0) * 1000, wPeak * 60 / (2 * math.pi)))
    report("punch: battery sag", minV / 6 > 3.35 and minV / 6 < 3.95 and peakI > 100 and peakI < 240,
        string.format("peak I=%.0f A, min V=%.2f V (%.2f V/cell)", peakI, minV, minV / 6))
    report("punch: climb speed", s.vz > 15 and s.vz < 45, string.format("vz after 3 s = %.1f m/s (%.0f km/h)", s.vz, s.vz * 3.6))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 50, 1, 0, 0, 0)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 1.5, function() return hoverThr, 0, 0, 0, true end, envAir)
    local target = Rates.setpoint(c.fc.rates, 1, 0.6)
    local t90, peak = nil, 0
    local stepT = 0
    local function sampler(cc, t)
        local r = cc.sim.wx * R2D
        if r > peak then peak = r end
        if not t90 and r >= 0.9 * target then t90 = t end
    end
    run(c, 0.4, function() return hoverThr, 0.6, 0, 0, true end, envAir, sampler)
    local over = (peak - target) / target * 100
    report("roll step: rise < 80 ms", t90 and t90 < 0.08, string.format("target=%.0f deg/s t90=%.0f ms", target, (t90 or 1) * 1000))
    report("roll step: overshoot < 20%", over < 20, string.format("peak=%.0f deg/s overshoot=%.1f%%", peak, over))
    local settle, maxAbs = nil, 0
    run(c, 0.4, function() return hoverThr, 0, 0, 0, true end, envAir, function(cc, t)
        local r = cc.sim.wx * R2D
        if t > 0.1 and math.abs(r) > maxAbs then maxAbs = math.abs(r) end
    end)
    report("roll stop: residual < 15 deg/s", maxAbs < 15, string.format("residual after 100 ms = %.1f deg/s", maxAbs))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 80, 1, 0, 0, 0)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 1, function() return hoverThr, 0, 0, 0, true end, envAir)
    local peak = 0
    run(c, 0.6, function() return 0.25, 0, 1, 0, true end, envAir, function(cc)
        local r = cc.sim.wy * R2D
        if r > peak then peak = r end
    end)
    local pk2 = 0
    run(c, 0.6, function() return 0.25, 0, 0, 1, true end, envAir, function(cc)
        local r = -cc.sim.wz * R2D
        if r > pk2 then pk2 = r end
    end)
    report("full stick pitch ~670 deg/s", peak > 600 and peak < 760, string.format("pitch peak=%.0f deg/s", peak))
    report("full stick yaw reaches rate", pk2 > 500, string.format("yaw peak=%.0f deg/s", pk2))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 200, 1, 0, 0, 0)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 0.5, function() return hoverThr, 0, 0, 0, true end, envAir)
    local wantTilt = 65
    run(c, 8, function(cc)
        local _, _, r13, _, _, _, _, _, r33 = Sim.matrix(cc.sim)
        local pitchAng = math.atan2(r13, r33) * R2D
        local stick = (wantTilt - pitchAng) * 0.02 - cc.sim.wy * R2D * 0.0008
        stick = math.max(-1, math.min(1, stick))
        return 1, 0, stick, 0, true
    end, envAir)
    local s = c.sim
    local hs = math.sqrt(s.vx * s.vx + s.vy * s.vy)
    report("top speed 100-200 km/h", hs * 3.6 > 100 and hs * 3.6 < 200,
        string.format("horiz=%.0f km/h vz=%.1f m/s rpm=%.0f V=%.1f I=%.0f", hs * 3.6, s.vz, s.mw[1] * 60 / (2 * math.pi), s.vbat, s.ibat))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 500, 1, 0, 0, 0)
    run(c, 8, function() return 0, 0, 0, 0, false end, envAir)
    report("flat freefall 12-30 m/s", -c.sim.vz > 12 and -c.sim.vz < 30, string.format("v=%.1f m/s", -c.sim.vz))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 200, 1, 0, 0, 0)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 0.5, function() return hoverThr, 0, 0, 0, true end, envAir)
    run(c, 1.2, function() return 0.0, 0, 0, 0, true end, envAir)
    local wobble, washPeak = 0, 0
    run(c, 0.8, function() return hoverThr + 0.08, 0, 0, 0, true end, envAir, function(cc)
        local w = math.sqrt(cc.sim.wx ^ 2 + cc.sim.wy ^ 2) * R2D
        if w > wobble then wobble = w end
        if cc.sim.wash > washPeak then washPeak = cc.sim.wash end
    end)
    report("prop wash wobble present", wobble > 5 and wobble < 400, string.format("peak wobble=%.0f deg/s wash=%.2f", wobble, washPeak))
end

do
    local c = newCraft()
    WALL_X = 6
    Sim.reset(c.sim, 0, 0, 0.03, 1, 0, 0, 0)
    run(c, 0.5, function() return 0, 0, 0, 0, false end, env)
    run(c, 0.2, function() return 0, 0, 0, 0, true end, env)
    local bad = false
    local maxSpeed = 0
    run(c, 4, function(cc, t)
        local _, _, r13, _, _, _, _, _, r33 = Sim.matrix(cc.sim)
        local pitchAng = math.atan2(r13, r33) * R2D
        local want = (t < 0.6) and 0 or 40
        local stick = math.max(-1, math.min(1, (want - pitchAng) * 0.02 - cc.sim.wy * R2D * 0.0008))
        return (t < 0.6) and 0.5 or 0.45, 0, stick, 0, true
    end, env, function(cc)
        local s = cc.sim
        if nan(s.px) or nan(s.wx) or s.px > WALL_X + 0.01 then bad = true end
        local sp = math.sqrt(s.vx ^ 2 + s.vy ^ 2 + s.vz ^ 2)
        if sp > maxSpeed then maxSpeed = sp end
    end)
    local s = c.sim
    report("wall impact stable", not bad, string.format("max speed=%.1f m/s, last impact=%.1f m/s, x=%.2f", maxSpeed, s.lastImpact, s.px))
    run(c, 12, function() return 0, 0, 0, 0, false end, env, function(cc)
        if nan(cc.sim.pz) or cc.sim.pz < -0.05 then bad = true end
    end)
    report("crash + fall to ground", not bad and s.pz < 0.2, string.format("final z=%.3f tilt=%.0f", s.pz, tiltDeg(s)))
    WALL_X = nil
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 0.03, 1, 0, 0, 0)
    local e2 = { trace = trace, every = 2 }
    run(c, 0.5, function() return 0, 0, 0, 0, false end, e2)
    run(c, 3, function() return 0, 0, 0, 0, true end, e2)
    local s = c.sim
    local drift = math.sqrt(s.px ^ 2 + s.py ^ 2)
    report("armed idle on ground", drift < 0.05 and tiltDeg(s) < 2 and s.pz < 0.03,
        string.format("drift=%.3f m tilt=%.2f z=%.4f rpm=%.0f", drift, tiltDeg(s), s.pz, s.mw[1] * 60 / (2 * math.pi)))
    run(c, 1.0, function() return hoverThr + 0.1, 0, 0, 0, true end, e2)
    local zTop = s.pz
    local touch, vTouch, vPrev = false, 0, 0
    run(c, 8.0, function(cc)
        local sim = cc.sim
        if not touch and (sim.nContacts or 0) > 0 then touch, vTouch = true, vPrev end
        vPrev = sim.vz
        if touch then return 0, 0, 0, 0, true end
        local want = sim.pz > 0.6 and -1.0 or -0.5
        local thr = hoverThr + (want - sim.vz) * 0.08
        return math.max(0, math.min(1, thr)), 0, 0, 0, true
    end, e2)
    report("takeoff + land", zTop > 0.3 and touch and s.pz < 0.05 and tiltDeg(s) < 5,
        string.format("climbed to %.2f m, touchdown %.2f m/s, landed z=%.3f tilt=%.1f", zTop, vTouch, s.pz, tiltDeg(s)))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 0.03, 1, 0, 0, 0)
    Craft.setInput(c, 0, 0, 0, 0, true)
    Craft.advance(c, FRAME, env)
    local blocked1 = (not c.fc.armed) and c.fc.armBlock == "ARMSWITCH"
    Craft.setInput(c, 0, 0, 0, 0, false); Craft.setInput(c, 0.5, 0, 0, 0, true)
    local blocked2 = (not c.fc.armed) and c.fc.armBlock == "THROTTLE"
    Craft.setInput(c, 0, 0, 0, 0, false); Craft.setInput(c, 0, 0, 0, 0, true)
    report("arming safety", blocked1 and blocked2 and c.fc.armed, "")
end

do
    local r = Rates.defaults()
    local a = Rates.maxRate(r, 1)
    r.type = "BETAFLIGHT"; r.rc_rate = { 100, 100, 100 }; r.srate = { 70, 70, 70 }; r.expo = { 0, 0, 0 }
    local b = Rates.maxRate(r, 1)
    r.type = "KISS"; r.rc_rate = { 100, 100, 100 }; r.srate = { 70, 70, 70 }
    local k = Rates.maxRate(r, 1)
    local cli = "set rates_type = BETAFLIGHT\nset roll_rc_rate = 120\nset roll_srate = 75\nset p_roll = 50\n"
    local pids = Presets.defaultPids()
    local n = Rates.parseCLI(cli, r, pids, {})
    report("rates math", math.abs(a - 670) < 0.5 and math.abs(b - 666.7) < 1 and math.abs(k - 666.7) < 1 and n == 4 and pids.roll[1] == 50,
        string.format("actual=%.1f bf=%.1f kiss=%.1f parsed=%d", a, b, k, n))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 0.07, 0, 1, 0, 0)
    run(c, 1.0, function() return 0, 0, 0, 0, false end, env)
    local _, _, _, _, _, _, _, _, r33a = Sim.matrix(c.sim)
    local maxTilt = 0
    run(c, 0.1, function() return 0, 0, 0, 0, false, true end, env)
    local function ctl(thr, roll, pitch, yaw, arm, turtle)
        return function() return thr, roll, pitch, yaw, arm, turtle end
    end
    local flipped = false
    local t = 0
    while t < 3 and not flipped do
        Craft.setInput(c, 0, (t > 0.1) and 0.55 or 0, 0, 0, true, true)
        Craft.advance(c, FRAME, env)
        t = t + FRAME
        local _, _, _, _, _, _, _, _, r33 = Sim.matrix(c.sim)
        if r33 > -0.2 then flipped = true end
    end
    local revOk = c.fc.flip and c.sim.spinCmd[1] == -1
    run(c, 1.5, function() return 0, 0, 0, 0, false, false end, env)
    local _, _, _, _, _, _, _, _, r33b = Sim.matrix(c.sim)
    report("turtle mode flips quad over", r33a < -0.9 and revOk and flipped and r33b > 0.9,
        string.format("start r33=%.2f, flipped in %.2f s, final up=%.2f", r33a, t, r33b))
end

do
    local c = newCraft()
    WALL_X = 8
    Sim.reset(c.sim, 0, 0, 1.5, 1, 0, 0, 0)
    run(c, 0.1, function() return 0, 0, 0, 0, false end, env)
    run(c, 0.05, function() return 0, 0, 0, 0, true end, env)
    run(c, 2.5, function(cc, t)
        local _, _, r13, _, _, _, _, _, r33 = Sim.matrix(cc.sim)
        local p = math.atan2(r13, r33) * R2D
        return 0.55, 0, math.max(-1, math.min(1, (45 - p) * 0.02 - cc.sim.wy * R2D * 0.0008)), 0, true
    end, env)
    WALL_X = nil
    local h = c.sim.propHealth
    local minH = math.min(h[1], h[2], h[3], h[4])
    report("wall crash damages props", minH < 0.9, string.format("prop health %.2f %.2f %.2f %.2f, impact %.1f m/s", h[1], h[2], h[3], h[4], c.sim.lastImpact))

    local c2 = newCraft()
    Sim.reset(c2.sim, 0, 0, 50, 1, 0, 0, 0)
    c2.sim.propHealth[2] = 0
    run(c2, 0.05, function() return 0, 0, 0, 0, false end, envAir)
    run(c2, 0.05, function() return 0, 0, 0, 0, true end, envAir)
    local maxRate = 0
    run(c2, 1.5, function() return hoverThr + 0.1, 0, 0, 0, true end, envAir, function(cc)
        local r = math.sqrt(cc.sim.wx ^ 2 + cc.sim.wy ^ 2 + cc.sim.wz ^ 2) * R2D
        if r > maxRate then maxRate = r end
    end)
    report("broken prop -> can't fly", maxRate > 300 or c2.sim.vz < -4,
        string.format("peak rotation %.0f deg/s, vz %.1f m/s", maxRate, c2.sim.vz))

    local c3 = newCraft()
    Sim.reset(c3.sim, 0, 0, 50, 1, 0, 0, 0)
    c3.sim.propHealth[1] = 0.6
    run(c3, 0.05, function() return 0, 0, 0, 0, false end, envAir)
    run(c3, 0.05, function() return 0, 0, 0, 0, true end, envAir)
    local jitter = 0
    run(c3, 1.0, function() return hoverThr + 0.03, 0, 0, 0, true end, envAir, function(cc)
        if cc.sim.vibration > jitter then jitter = cc.sim.vibration end
    end)
    local _, _, _, _, _, _, _, _, r33 = Sim.matrix(c3.sim)
    report("bent prop -> flyable but vibrates", r33 > 0.9 and jitter > 0.005, string.format("vibration %.3f, upright %.2f", jitter, r33))
end

do
    local function punch(setup, secs)
        local c = newCraft()
        if setup then setup(c) end
        Sim.reset(c.sim, 0, 0, 200, 1, 0, 0, 0)
        run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
        run(c, 0.6, function() return hoverThr, 0, 0, 0, true end, envAir)
        local minV = 99
        run(c, secs or 1.5, function() return 1, 0, 0, 0, true end, envAir, function(cc)
            if cc.sim.vbat < minV then minV = cc.sim.vbat end
        end)
        return minV / c.quad.cells, c.sim.vz, c
    end
    local cold = punch(function(c) c.quad.ambient = 0; Sim.resetBattery(c.sim, 1, 0) end)
    local warm = punch(function(c) c.quad.ambient = 35; Sim.resetBattery(c.sim, 1, 35) end)
    report("cold pack sags more than warm", cold < warm - 0.08, string.format("0 C: %.2f V/cell, 35 C: %.2f V/cell", cold, warm))

    local _, _, hot = punch(nil, 6)
    report("pack heats up when punching", hot.sim.packT > 25 and hot.sim.packT < 60, string.format("after 6 s full throttle: %.1f C", hot.sim.packT))

    local low, lowVz = punch(function(c) Sim.resetBattery(c.sim, 0.06, 25) end)
    local full, fullVz = punch(function(c) Sim.resetBattery(c.sim, 1, 25) end)
    report("near-empty pack: deep sag, weak punch", low < 3.35 and lowVz < fullVz * 0.8,
        string.format("6%%: %.2f V/cell, climb %.1f m/s  vs full: %.2f V/cell, %.1f m/s", low, lowVz, full, fullVz))

    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 200, 1, 0, 0, 0)
    Sim.resetBattery(c.sim, -0.10, 25)
    run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
    run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
    run(c, 3, function() return 1, 0, 0, 0, true end, envAir)
    report("over-discharged pack forces a landing", c.sim.vz < 1, string.format("full throttle: vz %.1f m/s, %.2f V/cell", c.sim.vz, c.sim.vbat / 6))

    local function hoverOf(setup)
        local lo, hi = 0.0, 0.9
        for _ = 1, 20 do
            local mid = (lo + hi) / 2
            local cc = newCraft()
            setup(cc)
            Sim.reset(cc.sim, 0, 0, 50, 1, 0, 0, 0)
            run(cc, 0.05, function() return 0, 0, 0, 0, false end, envAir)
            run(cc, 0.02, function() return 0, 0, 0, 0, true end, envAir)
            run(cc, 1.5, function() return mid, 0, 0, 0, true end, envAir)
            if cc.sim.vz > 0 then hi = mid else lo = mid end
        end
        return (lo + hi) / 2
    end
    local function to4S(cc)
        Presets.applyBattery(cc.quad, 4, 1500, "new")
        cc.sim = Sim.new(cc.quad)
        Sim.resetBattery(cc.sim, 1, 25)
    end
    local h4 = hoverOf(to4S)
    local _, vz4 = punch(to4S)
    report("4S on 1800KV: higher hover, weaker punch", h4 > hoverThr + 0.08 and vz4 < fullVz * 0.75,
        string.format("4S hover %.0f%% (6S %.0f%%), climb %.1f vs %.1f m/s", h4 * 100, hoverThr * 100, vz4, fullVz))

    local hFull = hoverOf(function(cc) Sim.resetBattery(cc.sim, 1, 25) end)
    local hLow = hoverOf(function(cc) Sim.resetBattery(cc.sim, 0.25, 25) end)
    local hComp = hoverOf(function(cc) Sim.resetBattery(cc.sim, 0.25, 25); cc.fc.misc.vbat_sag_compensation = 100 end)
    report("sag compensation steadies hover throttle", hLow > hFull + 0.01 and math.abs(hComp - hFull) < math.abs(hLow - hFull) * 0.5,
        string.format("full %.1f%%, 25%% pack %.1f%%, 25%% + comp %.1f%%", hFull * 100, hLow * 100, hComp * 100))

    local cs = newCraft()
    Sim.resetBattery(cs.sim, Sim.socFromCell(3.85), 20)
    report("storage charge start voltage", math.abs(cs.sim.vbat / 6 - 3.85) < 0.01, string.format("%.3f V/cell", cs.sim.vbat / 6))
    local q6 = Presets.get("mayhem_x5")
    Presets.applyBattery(q6, 6, 1400, "new")
    report("reference pack unchanged", math.abs(q6.mass - 0.652) < 1e-9 and math.abs(q6.R0 - 0.014) < 1e-12, string.format("mass %.3f", q6.mass))
end

if PHYS >= 2 then
    local function cruise(tiltDeg, secs, setup)
        local c = newCraft()
        if setup then setup(c) end
        Sim.reset(c.sim, 0, 0, 300, 1, 0, 0, 0)
        run(c, 0.05, function() return 0, 0, 0, 0, false end, envAir)
        run(c, 0.02, function() return 0, 0, 0, 0, true end, envAir)
        local thr, iz = hoverThr, 0
        local acc = { n = 0, cur = 0, front = 0, rear = 0, wakeRear = 0, wakeFront = 0, noise = 0, spd = 0 }
        run(c, secs, function(cc, t)
            local s = cc.sim
            local _, _, r13, _, _, _, _, _, r33 = Sim.matrix(s)
            local p = math.atan2(r13, r33) * R2D
            local ps = math.max(-1, math.min(1, (tiltDeg - p) * 0.02 - s.wy * R2D * 0.0008))
            iz = iz + (-s.vz) * 0.0025
            thr = math.max(0.05, math.min(1, hoverThr + iz - s.vz * 0.04))
            if t > secs - 2 then
                acc.n = acc.n + 1
                acc.cur = acc.cur + s.ibat
                acc.front = acc.front + (cc.fc.motor[2] + cc.fc.motor[4]) / 2
                acc.rear = acc.rear + (cc.fc.motor[1] + cc.fc.motor[3]) / 2
                acc.wakeRear = acc.wakeRear + (s.wakeIn[1] + s.wakeIn[3]) / 2
                acc.wakeFront = acc.wakeFront + (s.wakeIn[2] + s.wakeIn[4]) / 2
                acc.noise = acc.noise + cc.motorNoise
                acc.spd = acc.spd + math.sqrt(s.vx ^ 2 + s.vy ^ 2)
            end
            return thr, 0, ps, 0, true
        end, envAir)
        for k, v in pairs(acc) do if k ~= "n" then acc[k] = v / acc.n end end
        return acc
    end

    local hov = cruise(0, 5)
    local best, bestSpd, curve, lastCur = 1e9, 0, {}, 0
    for _, tilt in ipairs({ 8, 14, 20, 26 }) do
        local r = cruise(tilt, 7)
        curve[#curve + 1] = string.format("%d km/h %.2f A", r.spd * 3.6, r.cur)
        if r.cur < best then best, bestSpd = r.cur, r.spd end
        lastCur = r.cur
    end
    report("power curve: dips below hover, then rises", best < hov.cur and lastCur > hov.cur * 1.05,
        string.format("hover %.2f A; %s", hov.cur, table.concat(curve, ", ")))

    local function wakeAt(tiltDeg, speed)
        local c = newCraft()
        local t = math.rad(tiltDeg)
        Sim.reset(c.sim, 0, 0, 300, math.cos(t / 2), 0, math.sin(t / 2), 0)
        c.sim.vx = speed
        c.sim.escOn = true
        for i = 1, 4 do c.sim.duty[i] = 0.35; c.sim.mw[i] = 1800 end
        for _ = 1, 400 do
            Sim.step(c.sim, 0.0005, envAir)
            c.sim.vx, c.sim.vy, c.sim.vz = speed, 0, 0
            c.sim.wx, c.sim.wy, c.sim.wz = 0, 0, 0
            c.sim.qw, c.sim.qx, c.sim.qy, c.sim.qz = math.cos(t / 2), 0, math.sin(t / 2), 0
        end
        local s = c.sim
        return (s.wakeIn[1] + s.wakeIn[3]) / 2, (s.wakeIn[2] + s.wakeIn[4]) / 2, (s.thrust[1] + s.thrust[3]) / (s.thrust[2] + s.thrust[4])
    end
    local wr, wf, ratio = wakeAt(8, 22)
    report("front wake hits the rear props (fast, flat)", wr > 0.5 and wf < 0.05 and ratio < 0.97,
        string.format("80 km/h at 8 deg: wake into rear %.2f m/s, front %.2f, rear/front thrust %.2f", wr, wf, ratio))
    local wr2 = wakeAt(50, 22)
    report("steep tilt: wake passes below the rear props", wr2 < wr * 0.3, string.format("at 50 deg: %.2f m/s", wr2))
    local mid = cruise(20, 5)
    local fast = cruise(45, 7)
    local noRpm = cruise(0, 3, function(c) c.fc.misc.rpm_filter_harmonics = 0 end)
    report("RPM filter cuts motor noise", hov.noise < noRpm.noise * 0.5,
        string.format("motor noise rms %.4f with RPM filter, %.4f without", math.sqrt(hov.noise), math.sqrt(noRpm.noise)))
    local bent = cruise(0, 3, function(c) c.sim.propHealth[3] = 0.5 end)
    report("bent prop makes motors noisier", bent.noise > hov.noise * 2,
        string.format("motor noise rms %.4f bent vs %.4f healthy", math.sqrt(bent.noise), math.sqrt(hov.noise)))
end

do
    local c = newCraft()
    Sim.reset(c.sim, 0, 0, 0.5, 1, 0, 0, 0)
    Craft.setInput(c, 0, 0, 0, 0, false)
    Craft.setInput(c, 0, 0, 0, 0, true)
    local t0 = os.clock()
    local N = 0
    for _ = 1, 400 do
        Craft.setInput(c, hoverThr, 0.1, 0, 0, true)
        N = N + Craft.advance(c, 0.025, env)
    end
    local dt = os.clock() - t0
    report("perf (1 kHz w/ contacts)", true, string.format("%.1f us per step -> %.1f%% of a core at 1 kHz", dt / N * 1e6, dt / N * 1e6 / 10))
end
