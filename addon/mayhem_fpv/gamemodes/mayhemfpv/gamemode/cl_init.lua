include("shared.lua")

local FPV = MayhemFPV
local BaseClass = baseclass.Get("gamemode_base")

local HINTS = {
    { { "+use" }, "on the drone: fly" },
    { { "gm_showteam" }, "launch where you look" },
    { { "gm_showspare1" }, "bring the drone" },
    { { "gm_showhelp", "+menu" }, "settings" },
    { { "gm_showspare2" }, "cinematic" },
    { { "noclip" }, "noclip" },
}

local function keyName(bind)
    local k = input.LookupBinding(bind, true)
    if not k or k == "" then return nil end
    return string.upper(k)
end

local function hintRows()
    local rows = {}
    for _, h in ipairs(HINTS) do
        local keys = {}
        for _, b in ipairs(h[1]) do
            local k = keyName(b)
            if k then keys[#keys + 1] = k end
        end
        if #keys > 0 then rows[#rows + 1] = { table.concat(keys, " / "), h[2] } end
    end
    return rows
end

local drone, nextFind = nil, 0
local function myDrone()
    local now = RealTime()
    if now > nextFind or not IsValid(drone) then
        nextFind = now + 0.5
        drone = nil
        local me = LocalPlayer()
        for _, e in ipairs(ents.FindByClass("mayhem_x5")) do
            if e:GetOwnerPlayer() == me then drone = e break end
        end
    end
    return drone
end

local function hints()
    local w, h = ScrW(), ScrH()
    surface.SetFont("DermaDefaultBold")
    local parts, total = {}, 0
    for _, hnt in ipairs(hintRows()) do
        local kw = surface.GetTextSize(hnt[1])
        surface.SetFont("DermaDefault")
        local tw = surface.GetTextSize(hnt[2])
        surface.SetFont("DermaDefaultBold")
        parts[#parts + 1] = { hnt[1], hnt[2], kw, tw }
        total = total + kw + 12 + tw + 22
    end
    if #parts == 0 then return end
    total = total - 22
    local x, y = math.floor((w - total) / 2), h - 38
    draw.RoundedBox(4, x - 12, y - 6, total + 24, 26, Color(0, 0, 0, 150))
    for _, p in ipairs(parts) do
        draw.RoundedBox(3, x - 4, y - 2, p[3] + 8, 18, Color(255, 255, 255, 30))
        draw.SimpleText(p[1], "DermaDefaultBold", x, y, Color(255, 255, 255, 230))
        x = x + p[3] + 12
        draw.SimpleText(p[2], "DermaDefault", x, y + 1, Color(210, 210, 215, 210))
        x = x + p[4] + 22
    end
end

local function marker(ent)
    local me = LocalPlayer()
    local pos = ent:GetPos() + Vector(0, 0, 8)
    local d = me:EyePos():Distance(pos)
    if d < 60 then return end
    local sp = pos:ToScreen()
    if not sp.visible then return end
    local m = d * 0.01905
    local a = math.Clamp(255 - (d - 60) * 0.08, 90, 220)
    draw.SimpleText("MAYHEM X5", "DermaDefaultBold", sp.x, sp.y - 14, Color(255, 255, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(string.format("%.0f m", m), "DermaDefault", sp.x, sp.y - 2, Color(220, 220, 225, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end

local KEEP = { CHudGMod = true, CHudChat = true, CHudCloseCaption = true, CHudMenu = true }
function GM:HUDShouldDraw(name) return KEEP[name] == true end
function GM:HUDDrawTargetID() end
function GM:HUDDrawPickupHistory() end
function GM:DrawDeathNotice() end
function GM:HUDItemPickedUp() end
function GM:HUDAmmoPickedUp() end
function GM:HUDWeaponPickedUp() end
function GM:ScoreboardShow() end
function GM:ScoreboardHide() end

local function usePrompt()
    local me = LocalPlayer()
    local tr = me:GetEyeTrace()
    local e = tr.Entity
    if not IsValid(e) or e:GetClass() ~= "mayhem_x5" or tr.HitPos:Distance(me:EyePos()) > 90 then return end
    local key = keyName("+use") or "E"
    local x, y = ScrW() / 2, ScrH() / 2
    draw.RoundedBox(2, x - 2, y - 2, 4, 4, Color(255, 255, 255, 200))
    draw.SimpleText(key .. "  fly", "DermaDefaultBold", x + 12, y, Color(255, 255, 255, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

function GM:HUDPaint()
    if FPV.Flight and FPV.Flight.active then return end
    local c = FPV.Config and FPV.Config.data
    if c and c.game.cinematic then return end
    usePrompt()
    local cfg = FPV.Config and FPV.Config.data
    local d = myDrone()
    if IsValid(d) then marker(d) end
    if not cfg or cfg.game.hints ~= false then hints() end
    if FPV.Legacy then
        draw.SimpleText("The old addon 'fpv_drone' is still installed - delete garrysmod/addons/fpv_drone (it is switched off for now).",
            "DermaDefaultBold", ScrW() / 2, 40, Color(255, 170, 60), TEXT_ALIGN_CENTER)
    end
end

function GM:PlayerBindPress(ply, bind, pressed)
    if pressed and bind == "+menu" and not (FPV.Flight and FPV.Flight.active) then
        RunConsoleCommand("fpv_menu")
        return true
    end
    if BaseClass.PlayerBindPress then return BaseClass.PlayerBindPress(self, ply, bind, pressed) end
    return false
end

local bob = { phase = 0, amp = 0, land = 0, landV = 0, vz = 0, ground = true }

function GM:CalcView(ply, origin, angles, fov, znear, zfar)
    local view = BaseClass.CalcView(self, ply, origin, angles, fov, znear, zfar) or { origin = origin, angles = angles, fov = fov }
    local cfg = FPV.Config and FPV.Config.data
    local k = cfg and cfg.game.headBob or 1
    if k <= 0 or not ply:Alive() or ply:GetMoveType() == MOVETYPE_NOCLIP or ply:InVehicle() or ply:ShouldDrawLocalPlayer() then
        bob.amp, bob.land, bob.landV = 0, 0, 0
        return view
    end
    local dt = math.min(FrameTime(), 0.05)
    local vel = ply:GetVelocity()
    local sp = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    local ground = ply:IsOnGround()

    if ground then bob.phase = bob.phase + sp * dt / FPV.StepLength(sp) end
    local target = ground and math.min(sp / FPV.WALK_SPEED, 2.2) or 0
    bob.amp = bob.amp + (target - bob.amp) * math.min(1, dt * 5)

    if ground and not bob.ground and bob.vz < -60 then
        bob.landV = bob.landV - math.min(-bob.vz, 700) * 0.02
    end
    bob.ground, bob.vz = ground, vel.z
    bob.landV = bob.landV + (-160 * bob.land - 22 * bob.landV) * dt
    bob.land = bob.land + bob.landV * dt

    local a = bob.amp * k
    local p = bob.phase * 2 * math.pi
    local strike = (1 + math.cos(p)) * 0.5
    local dz = -1.6 * a * strike * strike + bob.land
    local sway = math.sin(p * 0.5)
    local dy = 0.9 * a * sway
    local ang = Angle(view.angles.p, view.angles.y, view.angles.r)
    ang.r = ang.r + 0.55 * a * sway
    ang.p = ang.p + 0.35 * a * strike - bob.land * 0.4
    view.origin = view.origin + ang:Right() * dy + Vector(0, 0, dz)
    view.angles = ang
    return view
end
