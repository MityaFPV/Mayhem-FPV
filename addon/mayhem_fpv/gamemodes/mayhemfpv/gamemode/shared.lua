GM.Name = "Mayhem FPV"
GM.Author = "MityaFPV & Claude"
GM.Email = ""
GM.Website = ""
GM.TeamBased = false

DeriveGamemode("base")

MayhemFPV = MayhemFPV or {}
local FPV = MayhemFPV
FPV.Version = "0.7.4"

FPV.MODULE_URL = "https://github.com/MityaFPV/Mayhem-FPV/releases/latest"
FPV.Gamemode = true

FPV.DEFAULT_SCALE = 0.0254

FPV.BoxMins = Vector(-6.1, -6.1, -0.9)
FPV.BoxMaxs = Vector(6.1, 6.1, 3.7)

FPV.WALK_SPEED, FPV.RUN_SPEED, FPV.SLOW_SPEED = 85, 190, 50
function FPV.StepLength(speed) return 30 + 0.16 * math.min(speed, 260) end

function GM:PlayerStepSoundTime(ply, stepType, walking)
    local v = ply:GetVelocity()
    local sp = math.max(math.sqrt(v.x * v.x + v.y * v.y), 20)
    local t = FPV.StepLength(sp) / sp * 1000
    if ply:Crouching() then t = t * 1.2 end
    return math.Clamp(t, 220, 900)
end

FPV.ROOT = GM.FolderName .. "/gamemode/mayhem/"
local ROOT = FPV.ROOT

local CORE_FILES = { "rates", "presets", "fc", "prop", "sensors", "sim", "craft", "link", "model", "autotune" }
local CLIENT_FILES = { "cl_config", "cl_input", "cl_render", "cl_osdfont", "cl_osd", "cl_sound", "cl_video",
    "cl_guard", "cl_flight", "cl_tune", "cl_music", "cl_skin", "cl_menu" }

do
    local legacy = (istable(_G.FPV) and _G.FPV.Version ~= nil) or file.Exists("autorun/fpv_drone_init.lua", "LUA")
    FPV.Legacy = legacy and true or false
    if legacy then
        local dead = {}
        for ev, t in pairs(hook.GetTable()) do
            for id in pairs(t) do
                if isstring(id) and (string.sub(id, 1, 10) == "fpv_drone_" or string.sub(id, 1, 11) == "fpv_detect_") then
                    dead[#dead + 1] = { ev, id }
                end
            end
        end
        for _, d in ipairs(dead) do hook.Remove(d[1], d[2]) end
        MsgC(Color(255, 160, 60), "[Mayhem FPV] The old addon 'fpv_drone' is still installed. It has been switched off for this session; "
            .. "delete garrysmod/addons/fpv_drone - the gamemode replaces it.\n")
    end
end

if SERVER then
    for _, f in ipairs(CORE_FILES) do AddCSLuaFile(ROOT .. "core/" .. f .. ".lua") end
    for _, f in ipairs(CLIENT_FILES) do AddCSLuaFile(ROOT .. "client/" .. f .. ".lua") end
end

FPV.Rates = include(ROOT .. "core/rates.lua")
FPV.Presets = include(ROOT .. "core/presets.lua")
FPV.FC = include(ROOT .. "core/fc.lua")
FPV.Sim = include(ROOT .. "core/sim.lua")
FPV.Craft = include(ROOT .. "core/craft.lua")
FPV.Prop = include(ROOT .. "core/prop.lua")
FPV.Sensors = include(ROOT .. "core/sensors.lua")
FPV.Sim.setProp(FPV.Prop)
FPV.Link = include(ROOT .. "core/link.lua")
FPV.Model = include(ROOT .. "core/model.lua")
FPV.Autotune = include(ROOT .. "core/autotune.lua")

if CLIENT then
    for _, f in ipairs(CLIENT_FILES) do include(ROOT .. "client/" .. f .. ".lua") end
end
