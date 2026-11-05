local M = {}
local GMROOT = os.getenv("MAYHEM_GM")
if not GMROOT then
    local f = io.open("../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/shared.lua")
    GMROOT = f and "../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/" or "../addon/mayhem_fpv/gamemodes/mayhemfpv/"
    if f then f:close() end
end
M.GMROOT = GMROOT

CLIENT, SERVER = true, false
local function noop() end

function math.Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function istable(t) return type(t) == "table" end
function isnumber(t) return type(t) == "number" end
function IsValid(x) return x ~= nil and x ~= NULL and (type(x) ~= "table" or not x.__invalid) end
NULL = { __invalid = true }
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function string.StartWith(s, p) return s:sub(1, #p) == p end

local VecMT = {}
VecMT.__index = VecMT
function Vector(x, y, z)
    if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, VecMT) end
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMT)
end
function VecMT:Normalize() local l = self:Length(); if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end end
function VecMT:SetUnpacked(x, y, z) self.x, self.y, self.z = x, y, z end
function VecMT:Set(v) self.x, self.y, self.z = v.x, v.y, v.z end
function VecMT:Unpack() return self.x, self.y, self.z end
function VecMT:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VecMT:Distance(o) return math.sqrt((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2) end
function VecMT:ToScreen() return { x = 960, y = 540, visible = true } end
VecMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VecMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VecMT.__mul = function(a, b)
    if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
    return Vector(a.x * b, a.y * b, a.z * b)
end
VecMT.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end

local AngMT = {}
AngMT.__index = AngMT
function Angle(p, y, r) return setmetatable({ p = p or 0, y = y or 0, r = r or 0 }, AngMT) end
local rad, deg, sin, cos, atan2, sqrt = math.rad, math.deg, math.sin, math.cos, math.atan2, math.sqrt
local function angleVectors(a)
    local sy, cy = sin(rad(a.y)), cos(rad(a.y))
    local sp, cp = sin(rad(a.p)), cos(rad(a.p))
    local sr, cr = sin(rad(a.r)), cos(rad(a.r))
    local f = Vector(cp * cy, cp * sy, -sp)
    local r = Vector(-1 * sr * sp * cy + -1 * cr * -sy, -1 * sr * sp * sy + -1 * cr * cy, -1 * sr * cp)
    local u = Vector(cr * sp * cy + -sr * -sy, cr * sp * sy + -sr * cy, cr * cp)
    return f, r, u
end
function AngMT:Forward() local f = angleVectors(self) return f end
function AngMT:Right() local _, r = angleVectors(self) return r end
function AngMT:Up() local _, _, u = angleVectors(self) return u end
function VecMT:AngleEx(up)
    local f = self
    local lx = up.y * f.z - up.z * f.y
    local ly = up.z * f.x - up.x * f.z
    local lz = up.x * f.y - up.y * f.x
    local ll = sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ll, ly / ll, lz / ll
    local xy = sqrt(f.x * f.x + f.y * f.y)
    if xy > 0.001 then
        local yaw = deg(atan2(f.y, f.x))
        local pitch = deg(atan2(-f.z, xy))
        local upz = ly * f.x - lx * f.y
        local roll = deg(atan2(lz, upz))
        return Angle(pitch, yaw, roll)
    end
    return Angle(deg(atan2(-f.z, xy)), deg(atan2(-lx, ly)), 0)
end
function VecMT:Angle()
    local xy = sqrt(self.x ^ 2 + self.y ^ 2)
    return Angle(deg(atan2(-self.z, xy)), deg(atan2(self.y, self.x)), 0)
end
function LerpVector(t, a, b) return a + (b - a) * t end

M.time = 0
function SysTime() return M.time end
M.frame = 0
function FrameNumber() return M.frame end
function RealTime() return M.time end
function CurTime() return M.time end
function FrameTime() return M.frameDt or 1 / 144 end
function ScrW() return 1920 end
function ScrH() return 1080 end
game = { SinglePlayer = function() return true end }
gui = { IsGameUIVisible = function() return false end }
M.keys = {}
input = {
    IsKeyDown = function(k) return M.keys[k] == true end,
    GetAnalogValue = function(c) return M.analog[c] or 0 end,
    IsButtonDown = function(c) return M.buttons[c] == true end,
    LookupBinding = function(b) return M.binds[b] end,
    GetKeyCode = function(k) return ({ w = KEY_W, s = KEY_S, a = KEY_A, d = KEY_D })[k] or 0 end,
}
M.binds = { ["+forward"] = "w", ["+back"] = "s", ["+moveleft"] = "a", ["+moveright"] = "d", ["+use"] = "e", gm_showteam = "F2", gm_showspare1 = "F3", gm_showhelp = "F1", ["+menu"] = "q", noclip = "v", gm_showspare2 = "F4" }
MOVETYPE_NOCLIP, MOVETYPE_WALK = 8, 2
KEY_W, KEY_S, KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_LSHIFT, KEY_T = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
MASK_SOLID_BRUSHONLY = 16395
MASK_SOLID, CONTENTS_WATER = 33570827, 32
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP = 0, 1, 2, 3
TOP, LEFT, FILL, BOTTOM, RIGHT = 4, 1, 5, 5, 2
MATERIAL_TRIANGLES = 0
MOUSE_LEFT = 107
RENDERGROUP_BOTH = 2

M.hooks = {}
hook = {
    GetTable = function() return M.hooks end,
    Add = function(ev, id, fn) M.hooks[ev] = M.hooks[ev] or {}; M.hooks[ev][id] = fn end,
    Remove = function(ev, id) if M.hooks[ev] then M.hooks[ev][id] = nil end end,
    Run = function(ev, ...)
        for _, fn in pairs(M.hooks[ev] or {}) do
            local a, b, c = fn(...)
            if a ~= nil then return a, b, c end
        end
    end,
}
M.concommands = {}
concommand = { Add = function(n, fn) M.concommands[n] = fn end }
M.cvars = { joystick = "0", joy_advanced = "0", joy_advaxisx = "4", joy_advaxisy = "2", joy_advaxisz = "0", joy_advaxisr = "0", joy_advaxisu = "0", joy_advaxisv = "0" }
M.cmds = {}
function RunConsoleCommand(n, v)
    M.cmds[#M.cmds + 1] = n .. (v and (" " .. v) or "")
    if v ~= nil and M.cvars[n] ~= nil then M.cvars[n] = tostring(v) end
end
function GetConVar(n)
    if M.cvars[n] == nil then return nil end
    return { GetString = function() return M.cvars[n] end, GetBool = function() return tonumber(M.cvars[n]) ~= 0 end }
end
ANALOG_JOY_X, ANALOG_JOY_Y, ANALOG_JOY_Z, ANALOG_JOY_R, ANALOG_JOY_U, ANALOG_JOY_V = 0, 1, 2, 3, 4, 5
JOYSTICK_FIRST_BUTTON = 114
M.analog = {}
M.buttons = {}
timer = { Create = function(_, _, _, fn) M.pendingTimers = M.pendingTimers or {}; table.insert(M.pendingTimers, fn) end,
    Simple = function(_, fn) M.pendingTimers = M.pendingTimers or {}; table.insert(M.pendingTimers, fn) end }
function M.runTimers() local t = M.pendingTimers or {}; M.pendingTimers = {}; for _, fn in ipairs(t) do fn() end end

M.files = {}
M.dirs = {}
file = {
    Find = function(pat)
        local dir = string.match(pat, "^(.*/)") or ""
        return M.dirs[dir] or {}, {}
    end,
    Exists = function(p) return M.files[p] ~= nil end,
    Read = function(p) return M.files[p] end,
    Write = function(p, s) M.files[p] = s end,
    CreateDir = noop,
}

local function toJSON(v)
    local t = type(v)
    if t == "table" then
        local isArr = #v > 0
        local parts = {}
        if isArr then
            for i = 1, #v do parts[#parts + 1] = toJSON(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, x in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. toJSON(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then return string.format("%q", v)
    elseif t == "boolean" or t == "number" then return tostring(v) end
    return "null"
end
local function fromJSON(s)
    local lua = s:gsub("%[", "{"):gsub("%]", "}"):gsub('"([^"]-)"%s*:', '["%1"]=')
    local f = loadstring("return " .. lua)
    local ok, t = pcall(f)
    if not ok then return nil end
    local function fix(x)
        if type(x) ~= "table" then return x end
        local o = {}
        for k, v in pairs(x) do o[tonumber(k) or k] = fix(v) end
        return o
    end
    return fix(t)
end
M.lastNet = {}
util = {
    TableToJSON = function(t) return toJSON(t) end,
    JSONToTable = fromJSON,
    IsBinaryModuleInstalled = function() return false end,
    PointContents = function() return 0 end,
}
M.groundZ = 0
local EPS = 0.03125
function util.TraceLine(t)
    local o = t.output or {}
    local s, e = t.start, t.endpos
    o.StartSolid = s.z < M.groundZ - 1e-6
    o.AllSolid = o.StartSolid and e.z < M.groundZ
    o.FractionLeftSolid = 0
    o.Hit, o.Fraction = false, 1
    o.HitPos = Vector(e.x, e.y, e.z)
    o.HitNormal = Vector(0, 0, 0)
    if o.StartSolid then o.Hit = true; o.Fraction = 0; return o end
    if e.z < M.groundZ + EPS and e.z < s.z then
        local f = (s.z - (M.groundZ + EPS)) / (s.z - e.z)
        if f < 0 then f = 0 end
        if f <= 1 then
            o.Hit, o.Fraction = true, f
            o.HitPos = Vector(s.x + (e.x - s.x) * f, s.y + (e.y - s.y) * f, s.z + (e.z - s.z) * f)
            o.HitNormal = Vector(0, 0, 1)
        end
    end
    M.traceCount = (M.traceCount or 0) + 1
    return o
end
function util.TraceHull(t)
    local o = t.output or {}
    if t.endpos.z < t.start.z - 1e-6 and t.start.z + t.mins.z >= M.groundZ then
        local b0, b1 = t.start.z + t.mins.z, t.endpos.z + t.mins.z
        if b1 < M.groundZ then
            local f = (b0 - M.groundZ) / (b0 - b1)
            o.Hit, o.StartSolid, o.Fraction = true, false, f
            o.HitPos = Vector(t.start.x, t.start.y, M.groundZ - t.mins.z)
            o.HitNormal = Vector(0, 0, 1)
        else
            o.Hit, o.StartSolid, o.Fraction = false, false, 1
            o.HitPos = Vector(t.endpos.x, t.endpos.y, t.endpos.z)
        end
        return o
    end
    local bottom = t.start.z + t.mins.z
    o.Hit = bottom < M.groundZ + 0.1
    o.StartSolid = o.Hit
    o.Fraction = o.Hit and 0 or 1
    o.HitPos = Vector(t.endpos.x, t.endpos.y, math.max(t.endpos.z, M.groundZ + t.maxs.z))
    return o
end

net = {
    Start = function(name) M.lastNet = { name = name, data = {} } end,
    WriteEntity = function(e) table.insert(M.lastNet.data, e) end,
    WriteVector = function(v) table.insert(M.lastNet.data, v) end,
    WriteAngle = function(a) table.insert(M.lastNet.data, a) end,
    WriteUInt = function(v) table.insert(M.lastNet.data, v) end,
    SendToServer = function() M.sent = M.sent or {}; table.insert(M.sent, M.lastNet) end,
    Receive = function(n, fn) M.netRecv = M.netRecv or {}; M.netRecv[n] = fn end,
    ReadUInt = function() return M.readQueue and table.remove(M.readQueue, 1) end,
    ReadEntity = function() return M.readQueue and table.remove(M.readQueue, 1) end,
}

M.counts = {}
local function counter(name) return function() M.counts[name] = (M.counts[name] or 0) + 1 end end
local meshState = {}
mesh = {
    Begin = function(_, n) meshState.n = n; meshState.v = 0 end,
    Position = function() meshState.v = meshState.v + 1 end,
    Color = noop, AdvanceVertex = noop,
    End = function()
        assert(meshState.v == meshState.n * 3, "mesh vertex count mismatch " .. meshState.v .. " vs " .. meshState.n * 3)
        M.counts.tris = (M.counts.tris or 0) + meshState.n
    end,
}
render = { SetMaterial = noop, GetLightColor = function() return Vector(0.5, 0.5, 0.5) end,
    UpdateScreenEffectTexture = function() M.counts.screenfx = (M.counts.screenfx or 0) + 1 end,
    PushRenderTarget = noop, PopRenderTarget = noop, Clear = noop }
cam = { Start2D = noop, End2D = noop,
    PushModelMatrix = function() M.matrixDepth = M.matrixDepth + 1 end,
    PopModelMatrix = function() M.matrixDepth = M.matrixDepth - 1; assert(M.matrixDepth >= 0) end }
render.SuppressEngineLighting = function(b) M.lightSuppressed = b end
render.SetModelLighting = function(i, r, g, b) assert(i >= 0 and i <= 5 and r >= 0 and g >= 0 and b >= 0) M.counts.modelLight = (M.counts.modelLight or 0) + 1 end
render.ComputeLighting = function() return Vector(0.6, 0.6, 0.55) end
function GetRenderTarget(name) return { GetName = function() return name end } end
function DrawColorModify(t) assert(t["$pp_colour_colour"]) M.counts.colormod = (M.counts.colormod or 0) + 1 end
M.generated = {}
M.patches = {}
sound = {
    Generate = function(name, sr, len, fn, loop)
        local n = math.floor(sr * len)
        local mx = 0
        for t = 0, n - 1, 7 do local v = fn(t); assert(v >= -1 and v <= 1, "sample out of range"); if math.abs(v) > mx then mx = math.abs(v) end end
        M.generated[name] = { samples = n, peak = mx, loop = loop }
    end,
    Play = function(name) M.played = M.played or {}; table.insert(M.played, name) end,
    PlayFile = function(path, flags, cb)
        M.audioOpened = M.audioOpened or {}
        table.insert(M.audioOpened, path)
        local len = M.audio and M.audio[path]
        if not len then cb(nil, 2, "BASS_ERROR_FILEOPEN") return end
        local ch = { path = path, state = 0, t = 0, len = len, vol = 1 }
        function ch:IsValid() return not self.dead end
        function ch:Play() self.state = 1 end
        function ch:Pause() self.state = 2 end
        function ch:Stop() self.state = 0; self.dead = true end
        function ch:GetState() return self.state end
        function ch:SetVolume(v) self.vol = v end
        function ch:GetTime() return self.t end
        function ch:SetTime(t) self.t = t end
        function ch:GetLength() return self.len end
        function ch:GetTagsID3() return M.id3 and M.id3[path] end
        M.lastChannel = ch
        cb(ch)
    end,
}
GMOD_CHANNEL_STOPPED, GMOD_CHANNEL_PLAYING, GMOD_CHANNEL_PAUSED, GMOD_CHANNEL_STALLED = 0, 1, 2, 3
function CreateSound(ent, name)
    assert(M.generated[name], "sound not generated: " .. name)
    local p = { name = name, vol = 0, pitch = 100, playing = false }
    function p:SetSoundLevel(l) self.level = l end
    function p:PlayEx(v, pt) self.playing = true; self.vol = v; self.pitch = pt end
    function p:ChangeVolume(v) assert(v >= 0 and v <= 1.0001, "volume " .. v); self.vol = v end
    function p:ChangePitch(pt) assert(pt >= 1 and pt <= 255, "pitch " .. pt); self.pitch = pt end
    function p:IsPlaying() return self.playing end
    function p:Stop() self.playing = false end
    table.insert(M.patches, p)
    return p
end
local MatMT = { __index = {
    SetTexture = function(self, k, v) self[k] = v end,
    SetVector = function(self, k, v) self[k] = v end,
    SetFloat = function(self, k, v) self[k] = v end,
    GetTexture = function(self) return { name = "tex:" .. (self.path or "?") } end,
    IsError = function(self) return self.err == true end,
} }
function CreateMaterial(name, shader, params) M.counts["mat:" .. shader] = (M.counts["mat:" .. shader] or 0) + 1; return setmetatable({ name = name, shader = shader }, MatMT) end
function Material(path, flags) return setmetatable({ path = path, err = not path:find("mayhem_fpv/") }, MatMT) end
M.meshVerts = 0
function Mesh()
    local m = {}
    function m:BuildFromTriangles(t)
        assert(#t % 3 == 0, "vertex count not a multiple of 3")
        assert(#t <= 65535, "too many vertices: " .. #t)
        for i = 1, #t do
            local v = t[i]
            assert(v.pos and v.normal and v.u and v.v and v.color, "bad vertex")
            assert(v.pos.x == v.pos.x and v.normal.z == v.normal.z, "NaN in mesh")
        end
        M.meshVerts = M.meshVerts + #t
        self.n = #t
    end
    function m:Draw() assert(M.matrixDepth > 0, "mesh drawn without model matrix"); M.counts.meshDraws = (M.counts.meshDraws or 0) + 1 end
    function m:Destroy() M.meshVerts = M.meshVerts - (self.n or 0) end
    return m
end
local MtxMT = { __index = { SetUnpacked = function(self, ...) local a = { ... }; assert(#a == 16); for i = 1, 16 do assert(a[i] == a[i], "NaN in matrix") end; self.e = a end } }
function Matrix() return setmetatable({}, MtxMT) end
M.matrixDepth = 0
M.lightSuppressed = false
M.rec = nil
M.drawColor = { 255, 255, 255, 255 }
M.currentMat = nil
local function R(t) if M.rec then M.rec[#M.rec + 1] = t end end
local surf = {
    GetTextSize = function(t) return #tostring(t) * 7, 14 end,
    SetDrawColor = function(r, g, b, a)
        if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
        M.drawColor = { r, g, b, a or 255 }
    end,
    SetMaterial = function(m) M.currentMat = m end,
    DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1)
        if M.currentMat and M.currentMat.path and M.currentMat.path:find("osd_font") then
            assert(u0 >= 0 and v0 >= 0 and u1 <= 1 and v1 <= 1 and u1 > u0 and v1 > v0, "bad UV")
        end
        M.counts.glyphs = (M.counts.glyphs or 0) + 1
        R({ "uv", M.currentMat and M.currentMat.path or "?", x, y, w, h, u0, v0, u1, v1 })
    end,
    DrawRect = function(x, y, w, h) R({ "rect", x, y, w, h, unpack(M.drawColor) }) end,
    DrawOutlinedRect = function(x, y, w, h, t) R({ "orect", x, y, w, h, t or 1, unpack(M.drawColor) }) end,
    DrawLine = function(x0, y0, x1, y1) R({ "line", x0, y0, x1, y1, unpack(M.drawColor) }) end,
}
surface = setmetatable(surf, { __index = function(_, k) return counter("surface." .. k) end })
local dr = {
    RoundedBox = function(r, x, y, w, h, c) R({ "rect", x, y, w, h, c.r, c.g, c.b, c.a }) end,
    SimpleText = function(t, font, x, y, c, ax, ay) R({ "text", tostring(t), x, y, c and c.r or 255, c and c.g or 255, c and c.b or 255, ax or 0, ay or 3 }) end,
    SimpleTextOutlined = function(t, font, x, y, c, ax, ay) R({ "text", tostring(t), x, y, c and c.r or 255, c and c.g or 255, c and c.b or 255, ax or 0, ay or 3 }) end,
}
draw = setmetatable(dr, { __index = function(_, k) return counter("draw." .. k) end })
bit = require("bit")

local PanelMT = {}
PanelMT.__index = function(self, k)
    local v = rawget(PanelMT, k)
    if v then return v end
    return function() return self end
end
function PanelMT.GetChildren(self) return self.__children or {} end
function PanelMT.CursorPos(self) return M.cursor and M.cursor[1] or 10, M.cursor and M.cursor[2] or 10 end
function PanelMT.GetWide(self) return rawget(self, "__w") or 800 end
function PanelMT.GetTall(self) return rawget(self, "__h") or 600 end
function PanelMT.SetSize(self, w, h) rawset(self, "__w", w); rawset(self, "__h", h) end
function PanelMT.GetValue(self) return self.__value or "" end
function PanelMT.SetValue(self, v) self.__value = v end
function PanelMT.Clear(self) self.__children = {} end
function PanelMT.AddSheet(self, name, pnl) local t = { Tab = M.newPanel(), Panel = pnl, Name = name } return t end
function PanelMT.GetActiveTab() return nil end
function M.newPanel(parent)
    local p = setmetatable({ __children = {} }, PanelMT)
    if parent then table.insert(parent.__children, p) end
    M.panels = (M.panels or 0) + 1
    return p
end
vgui = {
    Create = function(_, parent) return M.newPanel(parent) end,
    GetKeyboardFocus = function() return nil end,
}
spawnmenu = { AddToolMenuOption = noop }

local ply = { __alive = true }
function ply:Alive() return self.__alive end
function ply:EyeAngles() return Angle(0, 0, 0) end
M.eye = Vector(0, -100, 64)
function ply:EyePos() return M.eye end
function ply:IsTyping() return false end
function LocalPlayer() return ply end
M.ply = ply

function M.newEnt(pos, ang)
    local e = { pos = pos, ang = ang }
    function e:GetPos() return self.pos end
    function e:GetAngles() return self.ang end
    function e:EntIndex() return 42 end
    return e
end
function Entity(idx) return M.entities and M.entities[idx] end

function AddCSLuaFile() end
function include(path)
    local full
    if path:sub(1, 10) == "mayhemfpv/" then full = GMROOT .. path:sub(11)
    else full = GMROOT .. "gamemode/" .. path end
    local f = assert(loadfile(full))
    return f()
end
function isstring(x) return type(x) == "string" end
function MsgC(...) M.msgc = (M.msgc or "") .. table.concat({ select(2, ...) }) end
function DeriveGamemode(name) M.derived = name end
local baseGM = setmetatable({}, { __index = function() return function() end end })
baseclass = { Get = function() return baseGM end }
M.entsByClass = {}
ents = { FindByClass = function(c) return M.entsByClass[c] or {} end }
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM = 0, 1, 4
local function deepCopy(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and deepCopy(v) or v end return o end
table.Copy = table.Copy or deepCopy
M.skins = {}
derma = {
    GetDefaultSkin = function() return { Colours = { Label = {}, Button = {} }, PaintFrame = function() end } end,
    DefineSkin = function(name, desc, skin) M.skins[name] = skin end,
}
function ply:GetEyeTrace() return { Entity = NULL, HitPos = Vector(0, 0, 0) } end
GM = { FolderName = "mayhemfpv" }
function M.loadGamemode()
    include("cl_init.lua")
    GAMEMODE = GM
end
function require(name)
    if name == "bit" then return bit end
    error("module not found: " .. name)
end

return M
