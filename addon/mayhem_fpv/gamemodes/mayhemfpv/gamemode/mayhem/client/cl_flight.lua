local FPV = MayhemFPV

local F = {}
FPV.Flight = F

local sqrt, cos, sin, rad, deg, atan, tan, exp = math.sqrt, math.cos, math.sin, math.rad, math.deg, math.atan, math.tan, math.exp

F.active = false
F.view = {}
F.drawOpts = {}
F.env = { every = 2 }

local function angToQuat(ang)
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local m11, m12, m13 = f.x, -r.x, u.x
    local m21, m22, m23 = f.y, -r.y, u.y
    local m31, m32, m33 = f.z, -r.z, u.z
    local tr = m11 + m22 + m33
    if tr > 0 then
        local s = sqrt(tr + 1) * 2
        return 0.25 * s, (m32 - m23) / s, (m13 - m31) / s, (m21 - m12) / s
    elseif m11 > m22 and m11 > m33 then
        local s = sqrt(1 + m11 - m22 - m33) * 2
        return (m32 - m23) / s, 0.25 * s, (m12 + m21) / s, (m13 + m31) / s
    elseif m22 > m33 then
        local s = sqrt(1 + m22 - m11 - m33) * 2
        return (m13 - m31) / s, (m12 + m21) / s, 0.25 * s, (m23 + m32) / s
    end
    local s = sqrt(1 + m33 - m11 - m22) * 2
    return (m21 - m12) / s, (m13 + m31) / s, (m23 + m32) / s, 0.25 * s
end
F.angToQuat = angToQuat

local vF, vU = Vector(), Vector()
local function simAngle(s)
    local m11, _, m13, m21, _, m23, m31, _, m33 = FPV.Sim.quatToMat(s.qw, s.qx, s.qy, s.qz)
    vF:SetUnpacked(m11, m21, m31)
    vU:SetUnpacked(m13, m23, m33)
    return vF:AngleEx(vU)
end
F.simAngle = simAngle

local function sourceFov(hfov)
    local aspect = ScrW() / math.max(1, ScrH())
    local f = 2 * deg(atan(tan(rad(hfov) * 0.5) * (4 / 3) / aspect))
    if f < 10 then f = 10 elseif f > 170 then f = 170 end
    return f
end

local td = { start = Vector(), endpos = Vector(), mask = MASK_SOLID, output = {} }
local function trace(x0, y0, z0, x1, y1, z1)
    local k = F.invScale
    td.start:SetUnpacked(x0 * k, y0 * k, z0 * k)
    td.endpos:SetUnpacked(x1 * k, y1 * k, z1 * k)
    util.TraceLine(td)
    local tr = td.output
    if tr.StartSolid then return true, 0, 0, 0, 0, x0, y0, z0, true end
    if not tr.Hit then return false end
    local n, h, s = tr.HitNormal, tr.HitPos, F.scale
    return true, tr.Fraction, n.x, n.y, n.z, h.x * s, h.y * s, h.z * s, false
end
F.env.trace = trace

local bp = { start = Vector(), endpos = Vector(), mins = Vector(), maxs = Vector(), mask = MASK_SOLID, output = {} }
local function nearGeometry(sim, fdt)
    local k = F.invScale
    local spd = sqrt(sim.vx * sim.vx + sim.vy * sim.vy + sim.vz * sim.vz)
    local r = (0.24 + spd * fdt * 2.5 + 0.03) * k
    bp.mins:SetUnpacked(-r, -r, -r)
    bp.maxs:SetUnpacked(r, r, r)
    bp.start:SetUnpacked(sim.px * k, sim.py * k, sim.pz * k)
    bp.endpos:Set(bp.start)
    util.TraceHull(bp)
    local o = bp.output
    return o.Hit or o.StartSolid
end

local gd = { start = Vector(), endpos = Vector(), output = {} }
local function groundDistance(sim)
    local k = F.invScale
    gd.mask = bit.bor(MASK_SOLID, CONTENTS_WATER)
    gd.start:SetUnpacked(sim.px * k, sim.py * k, sim.pz * k)
    gd.endpos:SetUnpacked(sim.px * k, sim.py * k, (sim.pz - 1.2) * k)
    util.TraceLine(gd)
    local o = gd.output
    if o.Hit and not o.StartSolid then return o.Fraction * 1.2 end
    return 100
end

function F.IsLocalDrone(ent)
    return F.active and ent == F.ent
end

function F.Begin(ent)
    if F.active then F.Stop() end
    local cfg = FPV.Config.data
    local quad = F.MakeQuad()
    F.quad = quad
    F.baseKH = quad.kH
    F.scale = cfg.sim.worldScale > 0 and cfg.sim.worldScale or FPV.DEFAULT_SCALE
    F.invScale = 1 / F.scale
    F.craft = FPV.Craft.new(F.Mods(), quad, cfg.rates, cfg.pids, cfg.misc)
    FPV.Craft.setRate(F.craft, cfg.sim.rate)

    F.launch = F.LaunchPose(ent)
    F.launchZ = F.launch[3]
    local qw, qx, qy, qz = F.launch[4], F.launch[5], F.launch[6], F.launch[7]
    FPV.Sim.reset(F.craft.sim, F.launch[1], F.launch[2], F.launch[3], qw, qx, qy, qz)
    FPV.Sim.resetBattery(F.craft.sim, F.StartCharge(), quad.ambient)

    F.ent = ent
    F.active = true
    F.camMode = "fpv"
    F.lockAngles = LocalPlayer():EyeAngles()
    F.lastFrame = SysTime()
    F.lastSend = 0
    F.chasePos = nil
    F.inWater = false
    F.prevReset = false
    F.prevCam = false
    td.filter = ent
    bp.filter = ent
    gd.filter = ent
    F.failsafe = false
    F.lqZeroTime = 0
    F.lastCrash = -1
    F.craft.sim.damageScale = (cfg.sim.damage or 1) * F.DAMAGE_BASE
    FPV.OSD.Reset()
    FPV.Video.Reset()
    FPV.Sound.Start()

    if FPV.Guard then FPV.Guard.Engage() end

    FPV.Input.ResetKeyboard()
    local st = FPV.Input.Poll(0)
    FPV.Craft.setInput(F.craft, st.thr, st.roll, st.pitch, st.yaw, st.arm, st.turtle)
end

F.DAMAGE_BASE = 0.75

F.SPAWN_CLEARANCE = 0.03
local lp = { start = Vector(), endpos = Vector(), mins = Vector(), maxs = Vector(), mask = MASK_SOLID, output = {} }
function F.LaunchPose(ent)
    local s, k = F.scale, F.invScale
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local lowest = 0.016
    local r = 0.05 * k
    lp.filter = { ent, LocalPlayer() }
    lp.mins:SetUnpacked(-r, -r, 0)
    lp.maxs:SetUnpacked(r, r, 0.01 * k)
    lp.start:SetUnpacked(pos.x, pos.y, pos.z + 0.25 * k)
    lp.endpos:SetUnpacked(pos.x, pos.y, pos.z - 1.5 * k)
    util.TraceHull(lp)
    local o = lp.output
    local ground
    if o.Hit and not o.StartSolid then
        ground = o.HitPos.z * s
    else
        ground = pos.z * s - lowest
    end
    local qw, qx, qy, qz = angToQuat(Angle(0, ang.y, 0))
    return { pos.x * s, pos.y * s, ground + lowest + F.SPAWN_CLEARANCE, qw, qx, qy, qz }
end

function F.Mods()
    return { Rates = FPV.Rates, FC = FPV.FC, Sim = FPV.Sim, Sensors = FPV.Sensors, Craft = FPV.Craft }
end

function F.MakeQuad(withDrag)
    local cfg = FPV.Config.data
    local quad = FPV.Presets.get(cfg.preset)
    FPV.Presets.applyBattery(quad, cfg.sim.cells, cfg.sim.battery, cfg.sim.packHealth)
    quad.ambient = cfg.sim.ambient or 20
    quad.propwash = cfg.sim.propwash
    quad.phys = cfg.sim.phys or 2
    if withDrag then quad.kH = quad.kH * (cfg.sim.rotorDrag or 1) end
    return quad
end

local CHARGE = { full = 4.20, ["4.10"] = 4.10, storage = 3.85 }
function F.StartCharge()
    local v = CHARGE[FPV.Config.data.sim.charge or "full"] or 4.20
    return FPV.Sim.socFromCell(v)
end

function F.Stop()
    if FPV.Guard then FPV.Guard.Release() end
    FPV.Sound.Stop()
    F.active = false
    F.ent = nil
    F.craft = nil
end

function F.RequestExit()
    if not F.active then return end
    if IsValid(F.ent) then
        local s, k = F.craft.sim, F.invScale
        net.Start("mayhem_end")
        net.WriteEntity(F.ent)
        net.WriteVector(Vector(s.px * k, s.py * k, s.pz * k))
        net.WriteAngle(simAngle(s))
        net.WriteVector(Vector(s.vx * k, s.vy * k, s.vz * k))
        net.SendToServer()
    end
    F.Stop()
end

function F.ResetCraft()
    if not F.active then return end
    local L = F.launch
    local c = F.craft
    FPV.Sim.reset(c.sim, L[1], L[2], L[3], L[4], L[5], L[6], L[7])
    local cfg = FPV.Config.data
    FPV.Presets.applyBattery(F.quad, cfg.sim.cells, cfg.sim.battery, cfg.sim.packHealth)
    F.quad.ambient = cfg.sim.ambient or 20
    FPV.Sim.resetBattery(c.sim, F.StartCharge(), F.quad.ambient)
    c.vSag, c.vDisplay = nil, nil
    FPV.Sim.repair(c.sim)
    FPV.FC.forceDisarm(c.fc, "ARMSWITCH")
    F.failsafe = false
    F.lqZeroTime = 0
    FPV.Video.Reset()
    FPV.Input.ResetKeyboard()
    c.flyTime, c.onTime = 0, 0
    F.inWater = false
    F.chasePos = nil
    FPV.OSD.Reset()
end

local MODES = { "fpv" }
function F.CycleCamera()
    for i, m in ipairs(MODES) do
        if m == F.camMode then F.camMode = MODES[i % #MODES + 1] break end
    end
    F.chasePos = nil
end

local function sendState(s)
    local k = F.invScale
    net.Start("mayhem_state", true)
    net.WriteEntity(F.ent)
    net.WriteVector(Vector(s.px * k, s.py * k, s.pz * k))
    net.WriteAngle(simAngle(s))
    net.SendToServer()
end

local function frame()
    if not F.active then return end
    local fn = FrameNumber()
    if F.steppedFrame == fn then return end
    F.steppedFrame = fn
    local now = SysTime()
    local fdt = now - F.lastFrame
    F.lastFrame = now
    if fdt <= 0 then return end
    if fdt > 0.1 then fdt = 0.1 end
    local ply = LocalPlayer()
    if not IsValid(F.ent) or not IsValid(ply) or not ply:Alive() then F.Stop() return end
    if game.SinglePlayer() and gui.IsGameUIVisible() then return end

    local cfg = FPV.Config.data
    local st = FPV.Input.Poll(fdt)
    if st.reset and not F.prevReset then F.ResetCraft() end
    F.prevReset = st.reset
    if st.cam and not F.prevCam then F.CycleCamera() end
    F.prevCam = st.cam

    local craft = F.craft
    local sim = craft.sim
    F.quad.propwash = cfg.sim.propwash
    F.quad.kH = F.baseKH * (cfg.sim.rotorDrag or 1)
    F.env.every = cfg.sim.collideEvery
    FPV.Craft.setRate(craft, cfg.sim.rate)
    sim.damageScale = (cfg.sim.damage or 1) * F.DAMAGE_BASE

    FPV.Video.Update(F)
    local lost = cfg.video.failsafe and FPV.Video.lq <= 0
    if lost then F.lqZeroTime = F.lqZeroTime + fdt else F.lqZeroTime = 0 end
    if F.lqZeroTime > 0.3 and not F.failsafe then
        F.failsafe = true
        FPV.FC.forceDisarm(craft.fc, "RXLOSS")
    elseif F.failsafe and not lost then
        F.failsafe = false
    end
    if F.failsafe or lost then
        FPV.Craft.setInput(craft, 0, 0, 0, 0, st.arm, false)
    else
        FPV.Craft.setInput(craft, st.thr, st.roll, st.pitch, st.yaw, st.arm, st.turtle)
    end

    local k = F.invScale
    local wp = Vector(sim.px * k, sim.py * k, sim.pz * k)
    local inWater = bit.band(util.PointContents(wp), CONTENTS_WATER) ~= 0
    if inWater and not F.inWater then FPV.FC.forceDisarm(craft.fc, "WATER") end
    F.inWater = inWater

    F.env.near = nearGeometry(sim, fdt)
    sim.groundDist = groundDistance(sim)
    FPV.Craft.advance(craft, fdt, F.env, 200)

    if inWater then
        local d = exp(-6 * fdt)
        sim.vx, sim.vy = sim.vx * d, sim.vy * d
        sim.vz = sim.vz * d + 9.2 * fdt
        sim.wx, sim.wy, sim.wz = sim.wx * d, sim.wy * d, sim.wz * d
    end

    if sim.impactTime ~= F.lastCrash then
        F.lastCrash = sim.impactTime
        if cfg.misc.crash_recovery == "DISARM" and craft.fc.armed and (sim.lastImpact or 0) > 4 then
            FPV.FC.forceDisarm(craft.fc, "CRASH")
        end
    end

    FPV.Sound.Update(F, fdt)
    FPV.OSD.Update(F)
    if now - F.lastSend > 1 / 30 then
        F.lastSend = now
        sendState(sim)
    end
end
hook.Add("PreRender", "mayhem_frame", frame)

local camF, camU = Vector(), Vector()
local chaseTr = { mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2), mask = MASK_SOLID }

hook.Add("CalcView", "mayhem_view", function(ply, origin, angles, fov)
    if not F.active then return end
    frame()
    if not F.active or not F.craft then return end
    local cfg = FPV.Config.data.camera
    local s = F.craft.sim
    local k = F.invScale
    local m11, m12, m13, m21, m22, m23, m31, m32, m33 = FPV.Sim.quatToMat(s.qw, s.qx, s.qy, s.qz)
    local px, py, pz = s.px * k, s.py * k, s.pz * k
    local view = F.view
    view.drawviewer = true
    view.zfar = nil

    if F.camMode == "fpv" then
        local c = F.quad.cam
        local cx = px + (m11 * c[1] + m12 * c[2] + m13 * c[3]) * k
        local cy = py + (m21 * c[1] + m22 * c[2] + m23 * c[3]) * k
        local cz = pz + (m31 * c[1] + m32 * c[2] + m33 * c[3]) * k
        local t = rad(cfg.uptilt or 30)
        local ct, st = cos(t), sin(t)
        camF:SetUnpacked(m11 * ct + m13 * st, m21 * ct + m23 * st, m31 * ct + m33 * st)
        camU:SetUnpacked(-m11 * st + m13 * ct, -m21 * st + m23 * ct, -m31 * st + m33 * ct)
        view.origin = Vector(cx, cy, cz)
        view.angles = camF:AngleEx(camU)
        local vib = s.vibration or 0
        if vib > 0.003 and FPV.Config.data.video.shake then
            local j = math.min(4, vib * 3)
            local a = view.angles
            a.p = a.p + (math.random() - 0.5) * j
            a.y = a.y + (math.random() - 0.5) * j
            a.r = a.r + (math.random() - 0.5) * j * 0.6
        end
        view.fov = sourceFov(cfg.fov or 120)
        view.znear = 0.35
        return view
    end

    local dronePos = Vector(px, py, pz)
    if F.camMode == "chase" then
        local hx, hy = m11, m21
        local hl = sqrt(hx * hx + hy * hy)
        if hl > 0.25 then
            F.chaseHx, F.chaseHy = hx / hl, hy / hl
        end
        hx, hy = F.chaseHx or 1, F.chaseHy or 0
        local want = Vector(px - hx * cfg.chaseDist * k, py - hy * cfg.chaseDist * k, pz + cfg.chaseHeight * k)
        chaseTr.start = dronePos
        chaseTr.endpos = want
        chaseTr.filter = F.ent
        local tr = util.TraceHull(chaseTr)
        want = tr.HitPos
        local dt = FrameTime()
        if not F.chasePos then F.chasePos = want end
        F.chasePos = LerpVector(1 - exp(-9 * dt), F.chasePos, want)
        view.origin = F.chasePos
        view.angles = (dronePos - F.chasePos):Angle()
        view.fov = sourceFov(95)
        view.znear = 1
        return view
    end

    local eye = ply:EyePos()
    view.origin = eye
    view.angles = (dronePos - eye):Angle()
    view.fov = fov
    view.znear = 2
    return view
end)

local function drawLocal(translucent)
    local cfg = FPV.Config.data.camera
    local o = F.drawOpts
    o.hideCamera = (F.camMode == "fpv")
    o.fpv = (F.camMode == "fpv")
    o.uptilt = cfg.uptilt
    FPV.Render.DrawCraft(F.craft.sim, F.quad, F.scale, translucent, o)
end

hook.Add("PostDrawOpaqueRenderables", "mayhem_draw", function(depth, sky)
    if not F.active or not F.craft or depth or sky then return end
    drawLocal(false)
end)

hook.Add("PostDrawTranslucentRenderables", "mayhem_draw_t", function(depth, sky)
    if not F.active or not F.craft or depth or sky then return end
    drawLocal(true)
end)

local HIDE = {
    CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true,
    CHudCrosshair = true, CHudWeaponSelection = true, CHudDamageIndicator = true,
    CHudZoom = true, CHudSuitPower = true, CHudPoisonDamageIndicator = true,
    CHudSquadStatus = true, CHudGeiger = true, CHudHistoryResource = true,
}
hook.Add("RenderScreenspaceEffects", "mayhem_video", function()
    if F.active and F.craft and F.camMode == "fpv" then FPV.Video.DrawScreen(F) end
end)

hook.Add("HUDShouldDraw", "mayhem_hidehud", function(name)
    if F.active and HIDE[name] then return false end
end)

hook.Add("HUDPaint", "mayhem_hud", function()
    if not F.active or not F.craft then return end
    local cine = FPV.Config.data.game.cinematic
    if cine then
        if F.camMode == "fpv" then FPV.Video.DrawOverlay(F) end
        return
    end
    if F.camMode == "fpv" then
        FPV.OSD.Draw(F)
        FPV.Video.DrawOverlay(F)
        FPV.OSD.DrawStickHUD(F)
    else
        FPV.OSD.DrawMini(F)
        FPV.OSD.DrawStickHUD(F)
    end
end)

hook.Add("PreDrawViewModel", "mayhem_novm", function()
    if F.active then return true end
end)
hook.Add("PreDrawPlayerHands", "mayhem_nohands", function()
    if F.active then return true end
end)

hook.Add("CreateMove", "mayhem_block", function(cmd)
    if not F.active then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if F.lockAngles then cmd:SetViewAngles(F.lockAngles) end
end)

hook.Add("InputMouseApply", "mayhem_mouse", function(cmd)
    if not F.active then return end
    if F.lockAngles then cmd:SetViewAngles(F.lockAngles) end
    return true
end)

local BLOCK = {
    "+attack", "+jump", "+duck", "+speed", "+walk", "+forward", "+back", "+moveleft", "+moveright",
    "invnext", "invprev", "slot", "lastinv", "impulse", "+zoom", "noclip", "phys_swap", "+left", "+right",
}
hook.Add("PlayerBindPress", "mayhem_binds", function(_, bind, pressed)
    if not F.active then return end
    if pressed then
        if string.find(bind, "+use", 1, true) then F.RequestExit() return true end
        if string.find(bind, "+reload", 1, true) then F.ResetCraft() return true end
        if string.find(bind, "+attack2", 1, true) then F.CycleCamera() return true end
    end
    for _, b in ipairs(BLOCK) do
        if string.find(bind, b, 1, true) then return true end
    end
end)

net.Receive("mayhem_begin", function()
    local idx = net.ReadUInt(16)
    local tries = 0
    local function attempt()
        local ent = Entity(idx)
        if IsValid(ent) then
            F.Begin(ent)
        elseif tries < 40 then
            tries = tries + 1
            timer.Simple(0.05, attempt)
        end
    end
    attempt()
end)

net.Receive("mayhem_stop", function()
    F.Stop()
end)

concommand.Add("fpv_exit", function() F.RequestExit() end)
concommand.Add("fpv_reset", function() F.ResetCraft() end)
concommand.Add("fpv_camera", function(_, _, args)
    local m = args[1]
    if m == "fpv" then
        F.camMode = m
        F.chasePos = nil
    else
        F.CycleCamera()
    end
end)

local toast = { text = nil, t = 0 }
function F.Toast(text) toast.text, toast.t = text, RealTime() end

function F.SetCinematic(on)
    local g = FPV.Config.data.game
    if on == nil then on = not g.cinematic end
    g.cinematic = on and true or false
    FPV.Config.SaveSoon()
    F.Toast(g.cinematic and "Cinematic mode" or "HUD on")
end
concommand.Add("mayhem_cinematic", function() F.SetCinematic() end)

hook.Add("HUDPaint", "mayhem_toast", function()
    if not toast.text then return end
    local age = RealTime() - toast.t
    if age > 1.6 then toast.text = nil return end
    local a = age < 1.1 and 1 or (1.6 - age) / 0.5
    surface.SetFont("DermaDefaultBold")
    local tw = surface.GetTextSize(toast.text)
    local x, y = ScrW() / 2, 60
    draw.RoundedBox(6, x - tw / 2 - 14, y - 13, tw + 28, 26, Color(16, 17, 21, 200 * a))
    draw.SimpleText(toast.text, "DermaDefaultBold", x, y, Color(255, 255, 255, 235 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
