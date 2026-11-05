local FPV = MayhemFPV

util.AddNetworkString("mayhem_begin")
util.AddNetworkString("mayhem_state")
util.AddNetworkString("mayhem_end")
util.AddNetworkString("mayhem_stop")

local CLASS = "mayhem_x5"

function FPV.StartPiloting(ply, ent)
    if not IsValid(ply) or not IsValid(ent) or not ply:Alive() then return end
    if IsValid(ent:GetPilot()) then return end
    if IsValid(ply.FPVDrone) then return end
    ent:SetPilot(ply)
    ply.FPVDrone = ent
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    ent:SetNotSolid(true)
    net.Start("mayhem_begin")
    net.WriteUInt(ent:EntIndex(), 16)
    net.Send(ply)
end

function FPV.StopPiloting(ply, ent, notifyClient, pos, ang, vel)
    if IsValid(ent) then
        ent:SetPilot(NULL)
        ent:SetNotSolid(false)
        if pos then ent:SetPos(pos) end
        if ang then ent:SetAngles(ang) end
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:Wake()
            if vel then phys:SetVelocity(vel) end
        end
    end
    if IsValid(ply) then
        ply.FPVDrone = nil
        if notifyClient then
            net.Start("mayhem_stop")
            net.Send(ply)
        end
    end
end

net.Receive("mayhem_state", function(_, ply)
    local ent = net.ReadEntity()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    if not IsValid(ent) or ent:GetClass() ~= CLASS or ent:GetPilot() ~= ply then return end
    ent:SetPos(pos)
    ent:SetAngles(ang)
end)

net.Receive("mayhem_end", function(_, ply)
    local ent = net.ReadEntity()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    local vel = net.ReadVector()
    if not IsValid(ent) or ent:GetClass() ~= CLASS or ent:GetPilot() ~= ply then
        ply.FPVDrone = nil
        return
    end
    FPV.StopPiloting(ply, ent, false, pos, ang, vel)
end)

hook.Add("SetupPlayerVisibility", "mayhem_pvs", function(ply)
    local d = ply.FPVDrone
    if IsValid(d) then AddOriginToPVS(d:GetPos()) end
end)

hook.Add("PlayerDeath", "mayhem_death", function(ply)
    if IsValid(ply.FPVDrone) then FPV.StopPiloting(ply, ply.FPVDrone, true) end
end)

hook.Add("PlayerDisconnected", "mayhem_disconnect", function(ply)
    if IsValid(ply.FPVDrone) then FPV.StopPiloting(ply, ply.FPVDrone, false) end
    if IsValid(ply.MayhemDrone) then ply.MayhemDrone:Remove() end
end)

local function groundSpot(ply, dist)
    local start = ply:EyePos()
    local fwd = ply:GetAimVector()
    local t = util.TraceLine({ start = start, endpos = start + fwd * dist, filter = { ply, ply.MayhemDrone } })
    local spot = t.HitPos - fwd * 12
    local down = util.TraceLine({ start = spot, endpos = spot - Vector(0, 0, 600), filter = { ply, ply.MayhemDrone } })
    return down.HitPos + Vector(0, 0, 2)
end

local function feetSpot(ply)
    local fwd = ply:GetForward()
    fwd.z = 0
    fwd:Normalize()
    local start = ply:GetPos() + Vector(0, 0, 30) + fwd * 50
    local tr = util.TraceHull({ start = ply:GetPos() + Vector(0, 0, 30), endpos = start, mins = Vector(-7, -7, -2), maxs = Vector(7, 7, 4), filter = { ply, ply.MayhemDrone } })
    local down = util.TraceLine({ start = tr.HitPos, endpos = tr.HitPos - Vector(0, 0, 200), filter = { ply, ply.MayhemDrone } })
    return down.HitPos + Vector(0, 0, 2)
end

function FPV.PlaceDrone(ply, pos, yaw)
    if not IsValid(ply) then return end
    local ent = ply.MayhemDrone
    if IsValid(ent) and IsValid(ent:GetPilot()) then return ent end
    if not IsValid(ent) then
        ent = ents.Create(CLASS)
        if not IsValid(ent) then return end
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, yaw, 0))
        ent:Spawn()
        ent:Activate()
        ent:SetOwnerPlayer(ply)
        ply.MayhemDrone = ent
    else
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, yaw, 0))
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(Vector(0, 0, 0))
            phys:SetAngleVelocity(Vector(0, 0, 0))
            phys:Wake()
        end
    end
    return ent
end

function FPV.LaunchHere(ply)
    if not IsValid(ply) or not ply:Alive() or IsValid(ply.FPVDrone) then return end
    local tr = ply:GetEyeTrace()
    local ent
    if IsValid(tr.Entity) and tr.Entity:GetClass() == CLASS and not IsValid(tr.Entity:GetPilot()) then
        ent = tr.Entity
    else
        ent = FPV.PlaceDrone(ply, groundSpot(ply, 150), ply:EyeAngles().y)
    end
    if not IsValid(ent) then return end
    timer.Simple(0.15, function()
        if IsValid(ent) and IsValid(ply) then FPV.StartPiloting(ply, ent) end
    end)
end

function FPV.BringDrone(ply)
    if not IsValid(ply) or not ply:Alive() or IsValid(ply.FPVDrone) then return end
    FPV.PlaceDrone(ply, feetSpot(ply), ply:EyeAngles().y)
end

concommand.Add("fpv_fly", function(ply) FPV.LaunchHere(ply) end)
concommand.Add("fpv_bring", function(ply) FPV.BringDrone(ply) end)
