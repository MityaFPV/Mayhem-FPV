local M = dofile("gmod_mock.lua")
CLIENT, SERVER = false, true

local fails = 0
local function check(name, ok, msg)
    if not ok then fails = fails + 1 end
    print(string.format("[%s] %-40s %s", ok and "PASS" or "FAIL", name, msg or ""))
end

local netNames = {}
function util.AddNetworkString(n) netNames[n] = true end
local sentTo = {}
net.Send = function(ply) sentTo[#sentTo + 1] = { name = M.lastNet.name, ply = ply, data = M.lastNet.data } end
net.ReadVector = function() return table.remove(M.readQueue, 1) end
net.ReadAngle = function() return table.remove(M.readQueue, 1) end
function AddOriginToPVS() end
local convars = {}
function GetConVar(n) return convars[n] end
function CreateConVar(n, def)
    local c = { v = def }
    function c:GetBool() return tonumber(self.v) ~= 0 end
    convars[n] = c
    return c
end
player_manager = { SetPlayerClass = function(ply, c) ply.class = c end }
FCVAR_ARCHIVE, FCVAR_NOTIFY = 128, 256

local created = {}
local function newEntity(class)
    local e = { class = class, pos = Vector(0, 0, 0), ang = Angle(0, 0, 0), nw = {}, removed = false, solid = true }
    local phys = { motion = true, vel = Vector(0, 0, 0) }
    function phys:EnableMotion(b) self.motion = b end
    function phys:Wake() end
    function phys:SetVelocity(v) self.vel = v end
    function phys:SetAngleVelocity() end
    function phys.IsValid() return true end
    function e:GetClass() return self.class end
    function e:SetPos(p) self.pos = p end
    function e:GetPos() return self.pos end
    function e:SetAngles(a) self.ang = a end
    function e:GetAngles() return self.ang end
    function e:Spawn() self.spawned = true end
    function e:Activate() end
    function e:Remove() self.removed = true; self.__invalid = true end
    function e:GetPhysicsObject() return phys end
    function e:SetNotSolid(b) self.solid = not b end
    function e:EntIndex() return 77 end
    function e:SetPilot(p) self.nw.Pilot = p end
    function e:GetPilot() return self.nw.Pilot or NULL end
    function e:SetOwnerPlayer(p) self.nw.Owner = p end
    function e:GetOwnerPlayer() return self.nw.Owner or NULL end
    e.phys = phys
    return e
end
ents.Create = function(class)
    local e = newEntity(class)
    created[#created + 1] = e
    return e
end

local function newPlayer()
    local p = { alive = true, pos = Vector(0, 0, 0), eye = Angle(0, 90, 0), weapons = { "weapon_pistol" }, cmds = {} }
    function p:Alive() return self.alive end
    function p:EyePos() return self.pos + Vector(0, 0, 64) end
    function p:GetPos() return self.pos end
    function p:EyeAngles() return self.eye end
    function p:GetAimVector() return self.eye:Forward() end
    function p:GetForward() local a = Angle(0, self.eye.y, 0) return a:Forward() end
    function p:GetEyeTrace()
        local s = self:EyePos()
        return util.TraceLine({ start = s, endpos = s + self:GetAimVector() * 4000 })
    end
    function p:StripWeapons() self.weapons = {} end
    function p:RemoveAllAmmo() end
    function p:ConCommand(c) self.cmds[#self.cmds + 1] = c end
    function p:SetWalkSpeed(v) self.walk = v end
    function p:SetRunSpeed(v) self.run = v end
    function p:SetSlowWalkSpeed(v) self.slow = v end
    function p:SetCrouchedWalkSpeed(v) self.crouch = v end
    function p:SetJumpPower(v) self.jump = v end
    function p.IsValid() return true end
    return p
end

local ok, err = pcall(function()
    include("init.lua")
    GAMEMODE = GM
end)
check("load gamemode (server)", ok, tostring(err))
local FPV = MayhemFPV
check("net messages registered", netNames.mayhem_begin and netNames.mayhem_state and netNames.mayhem_end and netNames.mayhem_stop, "")
check("server didn't load client files", FPV.Flight == nil and FPV.Menu == nil and FPV.Sim ~= nil, "")
check("no legacy addon", FPV.Legacy == false, "")

local ply = newPlayer()
ply.pos = Vector(100, 200, 0)
ply.eye = Angle(10, 90, 0)

GM:PlayerSpawn(ply, false)
M.runTimers()
GM:PlayerLoadout(ply)
local d = ply.MayhemDrone
check("player class set", ply.class == "player_default", tostring(ply.class))
check("no weapons", #ply.weapons == 0, "")
check("walking pace, not HL2 sprint", ply.walk == 85 and ply.run == 190 and ply.slow == 50, string.format("%s/%s/%s", tostring(ply.walk), tostring(ply.run), tostring(ply.slow)))
check("drone placed at spawn", d and d.class == "mayhem_x5" and d.spawned and d:GetOwnerPlayer() == ply, "")
check("drone in front, on the ground", d and d.pos.y > 220 and math.abs(d.pos.x - 100) < 2 and d.pos.z < 5,
    d and string.format("(%.0f %.0f %.0f)", d.pos.x, d.pos.y, d.pos.z) or "")
GM:PlayerSpawn(ply, false); M.runTimers()
check("one drone per pilot", #created == 1 and ply.MayhemDrone == d, tostring(#created))

ply.eye = Angle(30, 0, 0)
GM:ShowTeam(ply)
M.runTimers()
check("F2 moves the same drone", #created == 1 and d.pos.x > 150, string.format("x=%.0f", d.pos.x))
check("F2 starts piloting", ply.FPVDrone == d and d:GetPilot() == ply and not d.solid and d.phys.motion == false, "")
local last = sentTo[#sentTo]
check("client told to begin", last and last.name == "mayhem_begin" and last.ply == ply and last.data[1] == 77, "")

local px = d.pos.x
GM:ShowTeam(ply); GM:ShowSpare1(ply); M.runTimers()
check("F2/F3 ignored in flight", d.pos.x == px and #created == 1, "")

M.readQueue = { d, Vector(1, 2, 3), Angle(0, 45, 0) }
M.netRecv.mayhem_state(nil, ply)
check("pose mirrored", d.pos.x == 1 and d.pos.z == 3, "")
local other = newPlayer()
M.readQueue = { d, Vector(9, 9, 9), Angle(0, 0, 0) }
M.netRecv.mayhem_state(nil, other)
check("other players can't move it", d.pos.x == 1, "")

M.readQueue = { d, Vector(5, 5, 1), Angle(0, 0, 0), Vector(0, 0, -1) }
M.netRecv.mayhem_end(nil, ply)
check("exit hands the drone back to physics", ply.FPVDrone == nil and d:GetPilot() == NULL and d.solid and d.phys.motion, "")

ply.pos = Vector(-500, 0, 0)
ply.eye = Angle(0, 0, 0)
GM:ShowSpare1(ply)
check("F3 brings the drone", math.abs(d.pos.x - (-450)) < 2 and math.abs(d.pos.y) < 2, string.format("(%.0f %.0f %.0f)", d.pos.x, d.pos.y, d.pos.z))

GM:ShowHelp(ply)
check("F1 -> settings", ply.cmds[#ply.cmds] == "fpv_menu", "")
GM:ShowSpare2(ply)
check("F4 -> cinematic", ply.cmds[#ply.cmds] == "mayhem_cinematic", "")

check("no fall damage", GM:GetFallDamage(ply, 2000) == 0, "")
check("no damage", GM:PlayerShouldTakeDamage(ply, ply) == false, "")
check("noclip allowed by default", GM:PlayerNoClip(ply, true) == true, "")
convars.mayhem_noclip.v = "0"
check("noclip off by server setting", GM:PlayerNoClip(ply, true) == false and GM:PlayerNoClip(ply, false) == true, "")

ply.alive = false
GM:ShowTeam(ply); M.runTimers()
check("dead: no launch", ply.FPVDrone == nil, "")
ply.alive = true
GM:ShowTeam(ply); M.runTimers()
for _, fn in pairs(M.hooks.PlayerDeath) do fn(ply) end
check("death ends the flight", ply.FPVDrone == nil and d:GetPilot() == NULL and sentTo[#sentTo].name == "mayhem_stop", "")

for _, fn in pairs(M.hooks.PlayerDisconnected) do fn(ply) end
check("disconnect removes the drone", d.removed, "")

ENT = {}
local okE, errE = pcall(include, "mayhemfpv/entities/entities/mayhem_x5.lua")
check("entity loads (server)", okE and ENT.Initialize and ENT.Use and ENT.OnRemove and ENT.Spawnable == false, tostring(errE))
do
    local p2 = newPlayer()
    local e = newEntity("mayhem_x5")
    e:SetOwnerPlayer(p2); p2.MayhemDrone = e
    e:SetPilot(p2); p2.FPVDrone = e
    ENT.OnRemove(e)
    check("removing the drone clears owner + pilot", p2.MayhemDrone == nil and p2.FPVDrone == nil and sentTo[#sentTo].name == "mayhem_stop", "")
end

print(fails == 0 and "ALL SERVER TESTS PASSED" or (fails .. " FAILURE(S)"))
