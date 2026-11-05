local FPV = MayhemFPV

local S = {}
FPV.Sound = S

local pi, sin, log, abs, min, max, random, sqrt = math.pi, math.sin, math.log, math.abs, math.min, math.max, math.random, math.sqrt
local SR = 44100
local LAYERS = { 96, 240, 600, 1500 }
local SPREAD = log(2.5)
local BLADES = 3
local POLE_PAIRS = 7

S.ready = false
S.voices = nil
S.wind = nil
S.lastImpactTime = -1
S.lastBroke = -1

local function generate()
    if S.ready or S.failed then return S.ready end
    if not sound or not sound.Generate then S.failed = true return false end
    local ok = pcall(function()
        for li, f in ipairs(LAYERS) do
            local w0 = 2 * pi * f / SR
            local whine = POLE_PAIRS / BLADES
            local lp = 0
            sound.Generate("mayhem_motor_" .. li, SR, 1, function(t)
                local ph = w0 * t
                local v = sin(ph) * 0.62
                    + sin(2 * ph + 0.4) * 0.34
                    + sin(3 * ph + 1.3) * 0.22
                    + sin(4 * ph + 2.1) * 0.12
                    + sin(6 * ph + 0.7) * 0.06
                    + sin(whine * ph) * 0.10
                    + sin(2 * whine * ph + 1.0) * 0.05
                lp = lp + (random() * 2 - 1 - lp) * 0.35
                v = v + lp * 0.18
                return max(-1, min(1, v * 0.62))
            end, 0)
        end
        local lp1, lp2 = 0, 0
        sound.Generate("mayhem_wind", SR, 2, function()
            lp1 = lp1 + (random() * 2 - 1 - lp1) * 0.06
            lp2 = lp2 + (lp1 - lp2) * 0.12
            return max(-1, min(1, lp2 * 5))
        end, 0)
    end)
    S.ready = ok
    S.failed = not ok
    return ok
end

local function newPatch(name)
    local p = CreateSound(LocalPlayer(), name)
    if not p then return nil end
    p:SetSoundLevel(0)
    p:PlayEx(0, 100)
    return p
end

function S.Start()
    S.Stop()
    if not FPV.Config.data.sound.enabled then return end
    if not generate() then return end
    S.voices = {}
    for v = 1, 2 do
        local layers = {}
        for li = 1, #LAYERS do layers[li] = newPatch("mayhem_motor_" .. li) end
        S.voices[v] = layers
    end
    S.wind = newPatch("mayhem_wind")
end

function S.Stop()
    if S.voices then
        for _, layers in ipairs(S.voices) do
            for _, p in ipairs(layers) do if p then p:Stop() end end
        end
    end
    if S.wind then S.wind:Stop() end
    S.voices, S.wind = nil, nil
end

local function keepPlaying(p, vol, pitch)
    if not p then return end
    if vol > 0.002 and not p:IsPlaying() then p:PlayEx(vol, pitch) end
    p:ChangeVolume(vol, 0)
    p:ChangePitch(pitch, 0)
end

local function layerWeight(li, f)
    local d = abs(log(f / LAYERS[li])) / SPREAD
    if d >= 1 then return 0 end
    return 1 - d
end

local GROUPS = { { 1, 4 }, { 2, 3 } }

function S.Update(F, dt)
    if not S.voices then return end
    local cfg = FPV.Config.data.sound
    local sim = F.craft.sim
    local k = 1 / F.scale
    local master = cfg.volume or 0.8

    local att = 1
    if cfg.mode == "pilot" or F.camMode == "los" then
        local eye = LocalPlayer():EyePos()
        local dx, dy, dz = sim.px * k - eye.x, sim.py * k - eye.y, sim.pz * k - eye.z
        local d = sqrt(dx * dx + dy * dy + dz * dz) * F.scale
        att = 1 / (1 + d / 8)
    end
    master = master * att

    local wash = sim.wash or 0
    local vib = sim.vibration or 0
    local flutter = 1 + wash * 0.5 * (random() * 2 - 1) + vib * 0.6 * (random() * 2 - 1)

    for g = 1, 2 do
        local a, b = GROUPS[g][1], GROUPS[g][2]
        local w = (abs(sim.mw[a]) + abs(sim.mw[b])) * 0.5
        local layers = S.voices[g]
        local f = w / (2 * pi) * BLADES
        local load = (abs(sim.current[a]) + abs(sim.current[b])) * 0.5
        local vol = 0
        if w > 40 then
            local r = min(1, w / 3600)
            vol = (0.10 + 0.75 * r ^ 1.4 + 0.15 * min(1, load / 40)) * flutter
        end
        vol = max(0, min(1, vol * master * 0.55))
        for li = 1, #LAYERS do
            local wgt = (f > 1) and layerWeight(li, f) or 0
            local pitch = max(1, min(255, 100 * f / LAYERS[li]))
            keepPlaying(layers[li], vol * wgt, pitch)
        end
    end

    if S.wind then
        local spd = sqrt(sim.vx * sim.vx + sim.vy * sim.vy + sim.vz * sim.vz)
        local wv = min(1, (spd / 35) ^ 2) * 0.55 * master
        keepPlaying(S.wind, wv, max(40, min(200, 70 + spd * 2.5)))
    end

    local pos = Vector(sim.px * k, sim.py * k, sim.pz * k)
    if sim.impactTime ~= S.lastImpactTime and sim.impactTime >= 0 then
        S.lastImpactTime = sim.impactTime
        local spd = sim.lastImpact or 0
        if spd > 0.8 and cfg.enabled then
            local hard = spd > 3
            local snd = hard and ("physics/plastic/plastic_box_impact_hard" .. random(1, 4) .. ".wav")
                or ("physics/plastic/plastic_box_impact_soft" .. random(1, 4) .. ".wav")
            sound.Play(snd, pos, 75, 110 + random(0, 30), min(1, 0.3 + spd / 10) * (cfg.volume or 0.8))
        end
    end
    if sim.propBroke and sim.propBroke ~= S.lastBroke and sim.propBroke > 0 then
        S.lastBroke = sim.propBroke
        if cfg.enabled then
            sound.Play("physics/plastic/plastic_box_break" .. random(1, 2) .. ".wav", pos, 75, 140, cfg.volume or 0.8)
        end
    end
end
