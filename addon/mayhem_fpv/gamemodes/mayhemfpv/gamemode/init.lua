AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local FPV = MayhemFPV
include(FPV.ROOT .. "sv_drone.lua")

local BaseClass = baseclass.Get("gamemode_base")
local noclip = GetConVar("mayhem_noclip") or CreateConVar("mayhem_noclip", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Allow noclip (V) on foot")

function GM:PlayerSpawn(ply, transition)
    player_manager.SetPlayerClass(ply, "player_default")
    BaseClass.PlayerSpawn(self, ply, transition)
    ply:SetWalkSpeed(FPV.WALK_SPEED)
    ply:SetRunSpeed(FPV.RUN_SPEED)
    ply:SetSlowWalkSpeed(FPV.SLOW_SPEED)
    ply:SetCrouchedWalkSpeed(0.45)
    ply:SetJumpPower(165)
    timer.Simple(0.4, function()
        if IsValid(ply) and ply:Alive() and not IsValid(ply.MayhemDrone) then FPV.BringDrone(ply) end
    end)
end

function GM:PlayerLoadout(ply)
    ply:StripWeapons()
    ply:RemoveAllAmmo()
    return true
end

function GM:PlayerNoClip(ply, desired)
    return (not desired) or noclip:GetBool()
end

function GM:GetFallDamage() return 0 end
function GM:PlayerShouldTakeDamage() return false end
function GM:CanPlayerSuicide() return true end

function GM:ShowHelp(ply) ply:ConCommand("fpv_menu") end
function GM:ShowTeam(ply) FPV.LaunchHere(ply) end
function GM:ShowSpare1(ply) FPV.BringDrone(ply) end
function GM:ShowSpare2(ply) ply:ConCommand("mayhem_cinematic") end
