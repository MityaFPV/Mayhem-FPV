AddCSLuaFile()
local FPV = MayhemFPV

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Mayhem X5"
ENT.Author = "Mayhem FPV"
ENT.Category = "Mayhem FPV"
ENT.Purpose = "Press E (Use) to fly. E again to land/exit, R to reset."
ENT.Spawnable = false
ENT.AdminOnly = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Pilot")
    self:NetworkVar("Entity", 1, "OwnerPlayer")
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, className)
        if not tr.Hit then return end
        local ent = ents.Create(className)
        ent:SetPos(tr.HitPos + tr.HitNormal * 2)
        ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
        ent:Spawn()
        ent:Activate()
        return ent
    end

    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate025x025.mdl")
        self:PhysicsInitBox(FPV.BoxMins, FPV.BoxMaxs)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:EnableCustomCollisions(true)
        self:SetCollisionBounds(FPV.BoxMins, FPV.BoxMaxs)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetMass(0.65)
            phys:SetMaterial("plastic")
            phys:Wake()
        end
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        FPV.StartPiloting(activator, self)
    end

    function ENT:Think()
        local pilot = self:GetPilot()
        if IsValid(pilot) then
            if not pilot:Alive() or pilot.FPVDrone ~= self then
                FPV.StopPiloting(pilot, self, true)
            end
        end
        self:NextThink(CurTime() + 0.25)
        return true
    end

    function ENT:OnRemove()
        local owner = self:GetOwnerPlayer()
        if IsValid(owner) and owner.MayhemDrone == self then owner.MayhemDrone = nil end
        local pilot = self:GetPilot()
        if IsValid(pilot) and pilot.FPVDrone == self then
            pilot.FPVDrone = nil
            net.Start("mayhem_stop")
            net.Send(pilot)
        end
    end
else
    function ENT:Initialize()
        self:SetRenderBounds(Vector(-12, -12, -6), Vector(12, 12, 8))
    end

    local function isLocal(self)
        return FPV.Flight and FPV.Flight.IsLocalDrone(self)
    end

    function ENT:Draw()
        if isLocal(self) or not FPV.Render then return end
        FPV.Render.DrawEntity(self, false)
    end

    function ENT:DrawTranslucent()
        if isLocal(self) or not FPV.Render then return end
        FPV.Render.DrawEntity(self, true)
    end
end
