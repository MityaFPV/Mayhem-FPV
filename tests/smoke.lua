local M = dofile("gmod_mock.lua")
local allPanels = {}
local create = vgui.Create
vgui.Create = function(cls, parent)
    local p = create(cls, parent)
    allPanels[#allPanels + 1] = p
    return p
end

local fails = 0
local function check(name, ok, msg)
    if not ok then fails = fails + 1 end
    print(string.format("[%s] %-36s %s", ok and "PASS" or "FAIL", name, msg or ""))
end
local function try(name, fn)
    local ok, err = pcall(fn)
    check(name, ok, ok and "" or tostring(err))
    return ok
end

try("load gamemode (client)", function() M.loadGamemode() end)
local noGlobal = rawget(_G, "FPV") == nil
FPV = MayhemFPV
check("modules present", FPV and FPV.Flight and FPV.Menu and FPV.OSD and FPV.Render and FPV.Input and FPV.Config and FPV.Guard and FPV.Tune, "")
check("derives from base, no FPV global", M.derived == "base" and noGlobal and GM.Name == "Mayhem FPV", "")

ENT = {}
try("load entity", function() include("mayhemfpv/entities/entities/mayhem_x5.lua") end)

do
    local worst = 0
    math.randomseed(7)
    for _ = 1, 200 do
        local a = Angle(math.random() * 170 - 85, math.random() * 360 - 180, math.random() * 360 - 180)
        local qw, qx, qy, qz = FPV.Flight.angToQuat(a)
        local m11, m12, m13, m21, m22, m23, m31, m32, m33 = FPV.Sim.quatToMat(qw, qx, qy, qz)
        local f, r, u = a:Forward(), a:Right(), a:Up()
        local e = math.abs(m11 - f.x) + math.abs(m21 - f.y) + math.abs(m31 - f.z)
            + math.abs(m12 + r.x) + math.abs(m22 + r.y) + math.abs(m32 + r.z)
            + math.abs(m13 - u.x) + math.abs(m23 - u.y) + math.abs(m33 - u.z)
        local s = { qw = qw, qx = qx, qy = qy, qz = qz }
        local back = FPV.Flight.simAngle(s)
        local f2, u2 = back:Forward(), back:Up()
        e = e + math.abs(f2.x - f.x) + math.abs(f2.y - f.y) + math.abs(f2.z - f.z) + math.abs(u2.x - u.x) + math.abs(u2.y - u.y) + math.abs(u2.z - u.z)
        if e > worst then worst = e end
    end
    check("angle/quat round trip", worst < 1e-6, string.format("max error %.2e", worst))
end

local ent = M.newEnt(Vector(0, 0, 0.68), Angle(0, 90, 0))
M.entities = { [42] = ent }
M.readQueue = { 42 }
try("net mayhem_begin -> Begin", function() M.netRecv["mayhem_begin"]() end)
check("flight active", FPV.Flight.active and FPV.Flight.IsLocalDrone(ent), "")

local F = FPV.Flight
local function frames(sec, fn)
    local dt = 1 / 144
    local t = 0
    while t < sec do
        M.time = M.time + dt
        M.frameDt = dt
        if fn then fn(t) end
        M.frame = M.frame + 1
        hook.Run("PreRender")
        t = t + dt
    end
end

frames(0.6)
local s = F.craft.sim
check("rests on ground", s.pz > 0 and s.pz < 0.03 and not F.craft.fc.armed, string.format("z=%.4f m", s.pz))

do
    local m11, _, _, m21 = FPV.Sim.quatToMat(s.qw, s.qx, s.qy, s.qz)
    check("spawn heading", math.abs(m11) < 1e-3 and math.abs(m21 - 1) < 1e-3, string.format("fwd=(%.3f, %.3f)", m11, m21))
end

M.keys[KEY_SPACE] = true
frames(0.05)
M.keys[KEY_SPACE] = false
frames(0.3)
check("armed via keyboard", F.craft.fc.armed, F.craft.fc.armBlock or "")
M.keys[KEY_UP] = true
frames(1.0)
M.keys[KEY_UP] = false
frames(1.0)
check("climbs", s.pz > 1.0, string.format("z=%.2f m thr=%.2f I=%.1fA", s.pz, F.craft.fc.throttle, s.ibat))
check("server mirror sent", M.sent and #M.sent > 10 and M.sent[#M.sent].name == "mayhem_state", tostring(M.sent and #M.sent))

for _, mode in ipairs({ "fpv", "chase", "los" }) do
    F.camMode = mode
    try("CalcView " .. mode, function()
        local v = hook.Run("CalcView", M.ply, Vector(), Angle(), 90)
        assert(v and v.origin and v.angles and type(v.fov) == "number", "bad view")
        assert(v.fov > 9 and v.fov < 171, "fov out of range " .. v.fov)
    end)
    try("draw opaque " .. mode, function() hook.Run("PostDrawOpaqueRenderables", false, false) end)
    try("draw translucent " .. mode, function() hook.Run("PostDrawTranslucentRenderables", false, false) end)
    try("HUDPaint " .. mode, function() hook.Run("HUDPaint") end)
end
F.camMode = "fpv"
check("model meshes rendered", (M.counts.meshDraws or 0) > 60, tostring(M.counts.meshDraws))
check("hud hidden", hook.Run("HUDShouldDraw", "CHudHealth") == false, "")
check("binds: reload resets", hook.Run("PlayerBindPress", M.ply, "+reload", true) == true, "")
check("reset spawns lifted above the ground", math.abs(s.pz - (0.016 + F.SPAWN_CLEARANCE)) < 0.002, string.format("z=%.3f", s.pz))
frames(0.6)
check("after reset: settles, disarmed", not F.craft.fc.armed and s.pz > 0.005 and s.pz < 0.03, string.format("z=%.3f block=%s", s.pz, tostring(F.craft.fc.armBlock)))

frames(0.1)
M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false; frames(0.2)
check("re-arm after reset", F.craft.fc.armed, tostring(F.craft.fc.armBlock))

M.keys[KEY_UP] = true; frames(0.8); M.keys[KEY_UP] = false; frames(3)
M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false; frames(0.2)
try("OSD stats screen", function() hook.Run("HUDPaint") end)

check("FPV view only: RMB keeps FPV", hook.Run("PlayerBindPress", M.ply, "+attack2", true) == true and F.camMode == "fpv", F.camMode)
check("prop fragility 1.00 = 0.75 damage", math.abs(F.craft.sim.damageScale - 0.75) < 1e-9, tostring(F.craft.sim.damageScale))
M.sent = {}
check("binds: use exits", hook.Run("PlayerBindPress", M.ply, "+use", true) == true and not F.active, "")
check("mayhem_end sent", M.sent[1] and M.sent[1].name == "mayhem_end" and #M.sent[1].data == 4, "")

do
    M.ply.__alive = true
    FPV.Config.data.input.backend = "keyboard"
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    local F = FPV.Flight
    check("sound layers generated", M.generated["mayhem_motor_1"] and M.generated["mayhem_motor_4"] and M.generated["mayhem_wind"]
        and M.generated["mayhem_motor_1"].peak > 0.3, "")
    M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false; frames(0.1)
    M.keys[KEY_UP] = true; frames(0.7); M.keys[KEY_UP] = false; frames(0.3)
    local audible = 0
    for _, p in ipairs(M.patches) do if p.playing and p.vol > 0.02 then audible = audible + 1 end end
    check("motor sound follows rpm", audible >= 2, audible .. " audible layers")
    FPV.Config.data.video.fisheye = 0.6
    try("screen effects (fisheye)", function() hook.Run("RenderScreenspaceEffects") end)
    check("colour + warp ran", (M.counts.colormod or 0) > 0 and (M.counts.screenfx or 0) > 0, "")
    try("video overlay", function() hook.Run("HUDPaint") end)
    check("LQ near pilot", FPV.Video.lq == 100, tostring(FPV.Video.lq))
    M.eye = Vector(0, -200000, 64)
    frames(0.5)
    check("5 km: heavy noise, control ok", (FPV.Video.q or 1) < 0.5 and FPV.Video.lq > 50 and not F.failsafe, string.format("lq=%s q=%.2f", FPV.Video.lq, FPV.Video.q or -1))
    M.eye = Vector(0, -12000000, 64)
    frames(0.8)
    check("range failsafe", F.failsafe and not F.craft.fc.armed and FPV.Video.lq == 0, string.format("lq=%s q=%.2f", FPV.Video.lq, FPV.Video.q or -1))
    try("HUDPaint in failsafe", function() hook.Run("HUDPaint") end)
    M.eye = Vector(0, -100, 64)
    frames(0.3)
    check("link back, still disarmed", not F.failsafe and not F.craft.fc.armed, tostring(F.craft.fc.armBlock))
    hook.Run("PlayerBindPress", M.ply, "+reload", true)
    frames(0.5)
    M.keys[KEY_T] = true; frames(0.05); M.keys[KEY_T] = false; frames(0.1)
    M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false; frames(0.1)
    check("turtle armed via T", F.craft.fc.armed and F.craft.fc.flip, tostring(F.craft.fc.armBlock))
    try("OSD crash flip", function() hook.Run("HUDPaint") end)
    hook.Run("PlayerBindPress", M.ply, "+use", true)
    check("sound stopped on exit", (function() for _, p in ipairs(M.patches) do if p.playing then return false end end return true end)(), "")
end

do
    M.ply.__alive = true
    FPV.Config.data.input.backend = "keyboard"
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    local F = FPV.Flight
    for _, mode in ipairs({ "lit", "simple", "legacy", "lit" }) do
        FPV.Config.data.video.model = mode
        FPV.Render.Invalidate()
        M.counts.meshDraws = 0
        M.counts.tris = 0
        for _, cm in ipairs({ "fpv", "chase" }) do
            F.camMode = cm
            frames(0.05)
            try("model " .. mode .. " " .. cm, function()
                hook.Run("PostDrawOpaqueRenderables", false, false)
                hook.Run("PostDrawTranslucentRenderables", false, false)
            end)
        end
        local e2 = setmetatable(M.newEnt(Vector(10, 10, 1), Angle(0, 30, 0)), { __index = ENT })
        try("idle entity " .. mode, function() ENT.Draw(e2) end)
        check("model " .. mode .. ": drew, lighting restored", not M.lightSuppressed and M.matrixDepth == 0 and not FPV.Render.failed
            and ((mode == "legacy" and M.counts.tris > 0) or (mode ~= "legacy" and M.counts.meshDraws > 40)),
            string.format("mesh draws %d, legacy tris %d, triangles %s", M.counts.meshDraws, M.counts.tris or 0, tostring(FPV.Render.triangles)))
    end
    M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false; frames(0.1)
    M.keys[KEY_UP] = true; frames(0.4); M.keys[KEY_UP] = false
    M.counts.meshDraws, M.counts.tris = 0, 0
    try("spinning draw", function()
        hook.Run("PostDrawOpaqueRenderables", false, false)
        hook.Run("PostDrawTranslucentRenderables", false, false)
    end)
    local spinDraws = M.counts.meshDraws
    local inst, ni = FPV.Model.instances(FPV.Flight.quad, { motorW = FPV.Flight.craft.sim.mw, spinLimit = 140 })
    local blades = 0
    for k = 1, ni do if string.find(inst[k].part, "blade", 1, true) then blades = blades + 1 end end
    check("spinning: blur discs, no blades", M.counts.tris > 0 and blades == 0, string.format("draws %d disc tris %d blades %d", M.counts.meshDraws, M.counts.tris, blades))
    local vid = FPV.Config.data.video
    vid.props = "hide"
    M.counts.meshDraws, M.counts.tris = 0, 0
    hook.Run("PostDrawOpaqueRenderables", false, false)
    hook.Run("PostDrawTranslucentRenderables", false, false)
    check("props hidden: no hubs, no discs", M.counts.tris == 0 and M.counts.meshDraws < spinDraws, string.format("draws %d disc tris %d", M.counts.meshDraws, M.counts.tris))
    vid.props = "hidefpv"
    local camMode = FPV.Flight.camMode
    FPV.Flight.camMode = "fpv"
    M.counts.tris = 0
    hook.Run("PostDrawTranslucentRenderables", false, false)
    local fpvT = M.counts.tris
    FPV.Flight.camMode = "chase"
    M.counts.tris = 0
    hook.Run("PostDrawTranslucentRenderables", false, false)
    check("props hidden only in the FPV view", fpvT == 0 and M.counts.tris > 0, string.format("fpv %d chase %d", fpvT, M.counts.tris))
    FPV.Flight.camMode = camMode
    vid.props = "show"
    vid.actionCam = false
    M.counts.meshDraws = 0
    hook.Run("PostDrawOpaqueRenderables", false, false)
    check("action camera can be hidden", M.counts.meshDraws < spinDraws, string.format("%d < %d", M.counts.meshDraws, spinDraws))
    vid.actionCam = true
    vid.propColor = "orange"; FPV.Render.Invalidate()
    local okc = pcall(function() hook.Run("PostDrawOpaqueRenderables", false, false) end)
    check("orange props rebuild", okc and not FPV.Render.failed, "")
    vid.propColor = "smoke"; FPV.Render.Invalidate()
    hook.Run("PlayerBindPress", M.ply, "+use", true)
end

do
    local O = FPV.OSD
    local layout = O.Layout()
    local n = 0
    for _, e in ipairs(O.ELEMENTS) do n = n + 1; check("layout default " .. e.id, layout[e.id] and layout[e.id].x ~= nil, "") end
    for _, vs in ipairs({ "PAL", "NTSC" }) do
        FPV.Config.data.osd.video = vs
        M.counts.glyphs = 0
        try("all elements " .. vs, function()
            O.ScreenCanvas()
            local boxes = {}
            O.Render(O.SampleContext(), boxes, true)
            assert(#boxes == #O.ELEMENTS, "boxes " .. #boxes)
            for _, b in ipairs(boxes) do
                assert(b.x0 >= 0 and b.x1 <= 29 and b.y0 >= 0 and b.y1 < O.Rows(), b.id .. " outside the grid")
            end
        end)
        check("glyphs drawn " .. vs, M.counts.glyphs > 100, tostring(M.counts.glyphs))
    end
    FPV.Config.data.osd.video = "PAL"

    M.ply.__alive = true
    FPV.Config.data.input.backend = "keyboard"
    FPV.Config.data.sim.charge = "storage"
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    local F = FPV.Flight
    frames(0.3)
    check("BATT < FULL on a storage-charged pack", O.ctx.warning == "BATT < FULL", tostring(O.ctx.warning))
    FPV.Sim.resetBattery(F.craft.sim, 0.02, 20)
    F.craft.vDisplay = nil
    M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false
    M.keys[KEY_UP] = true; frames(0.6); M.keys[KEY_UP] = false
    frames(2.6)
    check("LOW BATTERY / LAND NOW when flat", O.ctx.warning == "LAND NOW" or O.ctx.warning == "LOW BATTERY",
        string.format("%s at %.2f V/cell", tostring(O.ctx.warning), O.ctx.cellV))
    M.counts.glyphs = 0
    try("live OSD + stick HUD", function() hook.Run("HUDPaint") end)
    check("live OSD drew", M.counts.glyphs > 40, tostring(M.counts.glyphs))
    M.keys[KEY_SPACE] = true; frames(0.05); M.keys[KEY_SPACE] = false; frames(0.2)
    check("post-flight stats", O.ctx.stats and #O.ctx.stats >= 10, "")
    try("stats screen", function() hook.Run("HUDPaint") end)
    hook.Run("PlayerBindPress", M.ply, "+use", true)
    FPV.Config.data.sim.charge = "full"

    allPanels = {}
    try("OSD editor opens", function() FPV.Menu.OpenOSDEditor() end)
    local canvas
    for _, p in ipairs(allPanels) do if rawget(p, "OnMousePressed") then canvas = p end end
    local before = FPV.Config.data.osd.layout.flytime.x
    try("OSD editor drag", function()
        canvas:SetSize(900, 675)
        rawget(canvas, "Paint")(canvas, 900, 675)
        local cw, ch = 900 / 30, 675 / 16
        local L = FPV.Config.data.osd.layout.flytime
        M.cursor = { (L.x + 1.5) * cw, (L.y + 0.5) * ch }
        rawget(canvas, "OnMousePressed")(canvas, MOUSE_LEFT)
        M.cursor = { (L.x - 0.5) * cw, (L.y + 0.5) * ch }
        rawget(canvas, "Think")(canvas)
        rawget(canvas, "OnMouseReleased")(canvas, MOUSE_LEFT)
        M.cursor = nil
    end)
    check("editor moved element", FPV.Config.data.osd.layout.flytime.x == before - 2,
        string.format("%d -> %d", before, FPV.Config.data.osd.layout.flytime.x))
    FPV.OSD.ResetLayout()
end

try("ENT:Draw (idle)", function()
    local e2 = M.newEnt(Vector(10, 10, 1), Angle(0, 30, 0))
    setmetatable(e2, { __index = ENT })
    ENT.Draw(e2)
end)

try("menu builds", function() FPV.Menu.Open() end)
try("wizard builds", function() FPV.Menu.OpenWizard() end)
local calls = 0
try("panel callbacks", function()
    for _, p in ipairs(allPanels) do
        local paint = rawget(p, "Paint")
        if paint then paint(p, 900, 260); calls = calls + 1 end
        local th = rawget(p, "Think")
        if th then th(p); calls = calls + 1 end
        local ov = rawget(p, "OnValueChanged")
        if ov then ov(p, 1); calls = calls + 1 end
        local oc = rawget(p, "OnChange")
        if oc then oc(p, true); calls = calls + 1 end
    end
end)
check("callbacks exercised", calls > 50, tostring(calls))

do
    FPV.Config.data = FPV.Config.Defaults()
    FPV.Config.data.input.backend = "fpvjoy"
    local raw = { -1, 0, 0, 0, -1, 0 }
    fpvjoy = {
        Read = function() return true, raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], 0 end,
        Info = function(id) if id == 0 then return true, "EdgeTX", 0x1209, 0x4F54, 6, 32 end return false end,
        Refresh = function() end,
        Version = function() return "mock" end,
    }
    FPV.Input.moduleLoaded = true
    FPV.Input.RefreshDevices()
    allPanels = {}
    FPV.Menu.OpenWizard()
    local frame = allPanels[1]
    local nextBtn
    for _, p in ipairs(allPanels) do if rawget(p, "DoClick") then nextBtn = p end end
    local function tick() FPV.Input.Poll(1 / 60); rawget(frame, "Think")(frame) end
    local seq = {
        function() raw = { -1, 0, 0, 0, -1, 0 } end,
        function() for _, v in ipairs({ -1, 1 }) do raw = { v, v, v, v, -1, 0 }; tick() end raw = { -1, 0, 0, 0, -1, 0 } end,
        function() raw = { 1, 0, 0, 0, -1, 0 } end,
        function() raw = { -1, 0.9, 0, 0, -1, 0 } end,
        function() raw = { -1, 0, -0.95, 0, -1, 0 } end,
        function() raw = { -1, 0, 0, 1, -1, 0 } end,
        function() raw = { -1, 0, 0, 0, 1, 0 } end,
        function() raw = { -1, 0, 0, 0, -1, 0 } end,
    }
    local ok = pcall(function()
        for _, step in ipairs(seq) do step(); tick(); rawget(nextBtn, "DoClick")(nextBtn) end
    end)
    local ic = FPV.Config.data.input
    check("wizard mapping", ok and ic.map.thr.axis == 1 and ic.map.roll.axis == 2 and ic.map.pitch.axis == 3
        and ic.map.pitch.inv == true and ic.map.yaw.axis == 4 and ic.arm.kind == "axis" and ic.arm.index == 5 and ic.calibrated,
        string.format("thr=%s roll=%s pitch=%s(inv=%s) yaw=%s arm=%s%s", ic.map.thr.axis, ic.map.roll.axis, ic.map.pitch.axis,
            tostring(ic.map.pitch.inv), ic.map.yaw.axis, ic.arm.kind, ic.arm.index))
    raw = { 1, 0.9, -0.95, 0, 1, 0 }
    local st = FPV.Input.Poll(1 / 60)
    check("radio mapping applied", st.thr > 0.99 and st.roll > 0.89 and st.pitch > 0.89 and st.arm,
        string.format("thr=%.2f roll=%.2f pitch=%.2f arm=%s", st.thr, st.roll, st.pitch, tostring(st.arm)))
end

do
    FPV.Config.data = FPV.Config.Defaults()
    local ic = FPV.Config.data.input
    ic.backend = "gamepad"
    local raw, btn = { 0, 0, 0, 0, 0, 0 }, 0
    fpvjoy = {
        Read = function() return true, raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], btn end,
        Info = function(id) if id == 0 then return true, "Controller", 0x045E, 0x02FF, 6, 16 end return false end,
        Refresh = function() end,
        Version = function() return "mock" end,
    }
    FPV.Input.moduleLoaded, FPV.Input.hid = true, false
    FPV.Input.RefreshDevices()
    allPanels = {}
    FPV.Menu.OpenWizard()
    local frame = allPanels[1]
    local nextBtn
    for _, p in ipairs(allPanels) do if rawget(p, "DoClick") then nextBtn = p end end
    local function tick() FPV.Input.Poll(1 / 60); rawget(frame, "Think")(frame) end
    local seq = {
        function() raw = { 0, 0, 0, 0, 0, 0 } end,
        function() for _, v in ipairs({ -0.7, 0.7 }) do raw = { v, v, v, v, 0, 0 }; tick() end raw = { 0, 0, 0, 0, 0, 0 } end,
        function() raw = { 0, -0.7, 0, 0, 0, 0 } end,
        function() raw = { 0, 0, 0, 0.7, 0, 0 } end,
        function() raw = { 0, 0, 0, 0, -0.7, 0 } end,
        function() raw = { 0.7, 0, 0, 0, 0, 0 } end,
        function() raw = { 0, 0, 0, 0, 0, 0 }; tick(); btn = 1; tick(); btn = 0 end,
        function() end,
    }
    local ok, e = pcall(function()
        for _, step in ipairs(seq) do step(); tick(); rawget(nextBtn, "DoClick")(nextBtn) end
    end)
    check("wizard: gamepad arm button is a press, not a hold", ok and ic.arm.kind == "button" and ic.arm.index == 1
        and ic.arm.toggle == true and ic.arm.inv == false,
        string.format("%s %s %s toggle=%s", tostring(e or ""), ic.arm.kind, tostring(ic.arm.index), tostring(ic.arm.toggle)))
    local st = FPV.Input.Poll(1 / 60)
    btn = 1; st = FPV.Input.Poll(1 / 60); btn = 0; st = FPV.Input.Poll(1 / 60)
    check("wizard: gamepad arms after one press", st.arm == true, tostring(st.arm))
    raw = { 0, -0.7, 0, 0.7, 0, 0 }
    st = FPV.Input.Poll(1 / 60)
    check("wizard: gamepad stick extremes = full", st.thr > 0.99 and st.roll > 0.99, string.format("thr %.2f roll %.2f", st.thr, st.roll))
    fpvjoy = nil
    FPV.Input.moduleLoaded = false
    FPV.Config.data = FPV.Config.Defaults()
end

do
    local In = FPV.Input
    FPV.Config.data = FPV.Config.Defaults()
    local ic = FPV.Config.data.input
    In.moduleLoaded, In.moduleTried, In.hid = false, true, false
    fpvjoy = nil
    ic.backend = "gamepad"
    local st = In.Poll(1 / 60)
    check("pad without module: Garry's Mod path, preset applied on its own", st.backend == "gamepad" and ic.gamepad.path == "gmod"
        and ic.map.roll.axis == 5 and ic.arm.kind == "button" and ic.arm.toggle == true,
        string.format("%s path %s roll %s", st.backend, tostring(ic.gamepad.path), tostring(ic.map.roll.axis)))

    local devs = { { "EdgeTX", 0x1209, 0x4F54 } }
    local ax, btn = { 0, 0, 0, 0, 0, 0, 0, 0 }, 0
    fpvjoy = {
        Read = function() return false end,
        HidScan = function() return #devs end,
        HidInfo = function(i) local d = devs[i + 1]; if d then return true, d[1], d[2], d[3], 8, 16, 5 end return false end,
        HidRead = function(i)
            if devs[i + 1] and devs[i + 1][1] == "EdgeTX" then return true, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1 end
            return true, btn, 0, 1, ax[1], ax[2], ax[3], ax[4], ax[5], ax[6], ax[7], ax[8]
        end,
    }
    In.moduleLoaded, In.hid = true, true
    In.RefreshDevices()
    M.time = M.time + 10
    st = In.Poll(1 / 60)
    check("module + only the radio plugged in: Gamepad source does not read the radio", st.backend == "gamepad" and st.padPath == "gmod",
        string.format("%s %s", st.backend, tostring(st.padPath)))

    devs[2] = { "Wireless Controller", 0x054C, 0x09CC }
    st = In.Poll(1 / 60)
    M.time = M.time + 4
    st = In.Poll(1 / 60)
    check("module: gamepad plugged in mid-game is picked up, no restart", st.backend == "fpvjoy" and st.padPath == "hid"
        and st.deviceId == 1 and st.padName == "Wireless Controller", string.format("%s %s %s", st.backend, tostring(st.padPath), tostring(st.deviceId)))
    check("module: setup switches to the direct-read layout, PlayStation detected", ic.gamepad.path == "hid"
        and ic.gamepad.layout == "playstation" and ic.map.roll.axis == 3 and ic.map.pitch.axis == 6 and ic.arm.index == 2,
        string.format("layout %s roll %s pitch %s arm %s", tostring(ic.gamepad.layout), ic.map.roll.axis, ic.map.pitch.axis, tostring(ic.arm.index)))
    ax[3], ax[6] = 0.71, -0.71
    st = In.Poll(1 / 60)
    btn = 2; st = In.Poll(1 / 60); btn = 0; st = In.Poll(1 / 60)
    check("module: PlayStation pad flies (right stick corner, Cross arms)", st.roll > 0.99 and st.pitch > 0.99 and st.arm == true,
        string.format("roll %.2f pitch %.2f arm %s", st.roll, st.pitch, tostring(st.arm)))
    ic.gamepad.thrChoice = "trigger"; ic.gamepad.applied = nil
    ax = { 0, 0, 0, 0, -1, 0, 0, 0 }
    st = In.Poll(1 / 60)
    local t0 = st.thr
    ax[5] = 1
    st = In.Poll(1 / 60)
    check("module: throttle choice re-applies on its own (R2)", t0 == 0 and st.thr > 0.99, string.format("%.2f -> %.2f", t0, st.thr))
    local xa, xb = { 0, 0, 0, 0, 0, 0, -1, 0 }, 0
    fpvjoy.XInputRead = function(slot)
        if slot ~= 0 then return false end
        return true, xb, 0, 1, xa[1], xa[2], xa[3], xa[4], xa[5], xa[6], xa[7], xa[8]
    end
    In.RefreshDevices()
    ic.gamepad.thrChoice = "up"
    st = In.Poll(1 / 60)
    check("module: XInput pad preferred (Xbox / Steam Input), no Garry's Mod dead zone", st.padPath == "xinput"
        and ic.gamepad.layout == "xbox" and ic.map.roll.axis == 4, string.format("%s %s roll %s", tostring(st.padPath), tostring(ic.gamepad.layout), ic.map.roll.axis))
    xa[4], xa[5], xa[2] = 0.03, -0.05, -0.04
    st = In.Poll(1 / 60)
    check("module: XInput tiny stick movement reaches the quad", math.abs(st.roll - 0.05) < 0.02 and st.pitch > 0.04 and st.thr > 0.03,
        string.format("roll %.3f pitch %.3f thr %.3f", st.roll, st.pitch, st.thr))
    xb = 1; st = In.Poll(1 / 60); xb = 0; st = In.Poll(1 / 60)
    check("module: XInput A arms", st.arm == true, tostring(st.arm))
    fpvjoy = nil
    In.moduleLoaded, In.hid = false, false
    FPV.Config.data = FPV.Config.Defaults()
end

do
    local In = FPV.Input
    local hraw = { -1, 0, 0, 0, -1, -1, -1, -1 }
    local hbtn = 0
    fpvjoy = {
        Read = function() return false end, Info = function() return false end, Refresh = function() end,
        Version = function() return "mock hid" end,
        HidScan = function() return 2 end,
        HidInfo = function(i)
            if i == 0 then return true, "Some Gamepad", 0x045E, 0x028E, 6, 10, 5 end
            if i == 1 then return true, "TX12", 0x1209, 0x4F54, 8, 24, 5 end
            return false
        end,
        HidRead = function(i)
            if i ~= 1 then return true, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 end
            return true, hbtn, 0, 5, hraw[1], hraw[2], hraw[3], hraw[4], hraw[5], hraw[6], hraw[7], hraw[8]
        end,
    }
    In.moduleLoaded, In.moduleTried = false, false
    util.IsBinaryModuleInstalled = function() return true end
    local realRequire = require
    require = function(n) if n == "fpvjoy" then return true end return realRequire(n) end
    FPV.Config.data = FPV.Config.Defaults()
    FPV.Config.data.input.backend = "auto"
    In.LoadModule()
    check("HID module detected", In.hid == true and #In.devices == 2, tostring(#In.devices))
    local st = In.Poll(1 / 60)
    check("auto-picks the EdgeTX radio over a gamepad", st.ok and st.deviceId == 1 and st.path == "hid", tostring(st.deviceId))
    FPV.Config.data.input.backend = "gamepad"
    check("Gamepad input source picks the gamepad, not the radio", In.ActiveDevice() == 0, tostring(In.ActiveDevice()))
    FPV.Config.data.input.backend = "auto"
    FPV.Config.data.input.deviceKey = In.devices[1].key
    st = In.Poll(1 / 60)
    check("device chosen by key", st.deviceId == 0, tostring(st.deviceId))
    FPV.Config.data.input.deviceKey = ""
    In.Poll(1 / 60)
    local before = In.Snapshot()
    hraw[8] = 1
    In.Poll(1 / 60)
    local sw = In.DetectSwitch(before, In.Snapshot(), { [1] = true, [2] = true, [3] = true, [4] = true })
    check("switch on CH8 detected", sw and sw.kind == "axis" and sw.index == 8, sw and (sw.kind .. sw.index) or "none")
    FPV.Config.data.input.arm = sw
    st = In.Poll(1 / 60)
    check("CH8 switch arms", st.arm == true and st.raw[8] == 1, tostring(st.arm))
    hraw[8] = -1
    st = In.Poll(1 / 60)
    check("CH8 switch off", st.arm == false, tostring(st.arm))
    hbtn = 2 ^ 31
    st = In.Poll(1 / 60)
    check("button 32 readable", In.SwitchActive({ kind = "button", index = 32, inv = false }), "")
    require = realRequire
    fpvjoy = nil
    In.moduleLoaded, In.hid = false, false
    FPV.Config.data = FPV.Config.Defaults()
end

do
    local F = FPV.Flight
    if F.active then F.Stop() end
    local e = M.newEnt(Vector(0, 0, -0.4), Angle(25, 70, 170))
    M.entities = { [42] = e }
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    local s = F.craft.sim
    local _, _, _, _, _, _, _, _, r33 = FPV.Sim.quatToMat(s.qw, s.qx, s.qy, s.qz)
    local m11, _, _, m21 = FPV.Sim.quatToMat(s.qw, s.qx, s.qy, s.qz)
    local yaw = math.deg(math.atan2(m21, m11))
    check("spawn: upright, same heading", r33 > 0.9999 and math.abs(yaw - 70) < 0.5, string.format("up %.4f yaw %.1f", r33, yaw))
    check("spawn: lifted above the ground", s.pz > 0.03 and s.pz < 0.06, string.format("z=%.3f", s.pz))
    local function frames2(sec) local t = 0 while t < sec do M.time = M.time + 1 / 144; M.frameDt = 1 / 144; M.frame = M.frame + 1; hook.Run("PreRender"); t = t + 1 / 144 end end
    frames2(1)
    check("spawn: settles on the ground", s.pz > 0.005 and s.pz < 0.03 and math.abs(s.vz) < 0.05, string.format("z=%.3f vz=%.3f", s.pz, s.vz))
    F.Stop()
end

do
    local O = FPV.OSD
    local osd = FPV.Config.data.osd
    local res = {}
    for _, vs in ipairs({ "PAL", "NTSC" }) do
        osd.video = vs
        O.ScreenCanvas()
        local rects = {}
        local orig = surface.DrawTexturedRectUV
        surface.DrawTexturedRectUV = function(x, y, w, h) rects[#rects + 1] = { x, y, w, h } end
        for _, e in ipairs(O.ELEMENTS) do
            if e.id == "crosshairs" then e.draw(O.ctx or {}, 13, 7) end
        end
        surface.DrawTexturedRectUV = orig
        local m = rects[2]
        res[vs] = m and { m[1] + (m[3] - 0.5) / 2 - ScrW() / 2, m[2] + (m[4] - 0.5) / 2 - ScrH() / 2 } or { 99, 99 }
    end
    osd.video = "PAL"
    check("crosshairs on the screen centre", math.abs(res.PAL[1]) <= 1 and math.abs(res.PAL[2]) <= 1 and math.abs(res.NTSC[1]) <= 1 and math.abs(res.NTSC[2]) <= 1,
        string.format("PAL %.1f,%.1f  NTSC %.1f,%.1f px", res.PAL[1], res.PAL[2], res.NTSC[1], res.NTSC[2]))
end

do
    local In = FPV.Input
    In.moduleLoaded, In.moduleTried, In.hid = false, true, false
    fpvjoy = nil
    FPV.Config.data = FPV.Config.Defaults()
    local st = In.Poll(1 / 60)
    check("no module: keyboard", st.backend == "keyboard" and st.ok, st.backend)
    FPV.Config.data.input.backend = "fpvjoy"
    st = In.Poll(1 / 60)
    check("no module, old 'radio module' setting: keyboard", st.backend == "keyboard", st.backend)
    local ic = FPV.Config.data.input
    In.ApplyGamepad(ic, "xbox", "up")
    In.padSeen = nil
    st = In.Poll(1 / 60)
    check("no module: no gamepad data until it moves", st.ok == false and st.path == "gamepad", tostring(st.ok))
    M.analog[ANALOG_JOY_Y] = -32767
    M.analog[ANALOG_JOY_U] = 32767
    M.analog[ANALOG_JOY_R] = -16000
    st = In.Poll(1 / 60)
    check("no module: gamepad through GMod", ic.backend == "gamepad" and st.backend == "gamepad" and st.ok and st.thr > 0.99 and st.roll > 0.99 and st.pitch > 0.1,
        string.format("%s thr %.2f roll %.2f pitch %.2f", st.backend, st.thr, st.roll, st.pitch))
    check("no module: GMod joystick switched on, restart hint", M.cvars.joystick == "1" and In.padNeedsRestart == true, "")
    In.ApplyGamepad(ic, "xbox", "up")
    M.analog[ANALOG_JOY_Y], M.analog[ANALOG_JOY_U], M.analog[ANALOG_JOY_R] = 0, 0, 0
    In.Poll(1 / 60)
    M.analog[ANALOG_JOY_U] = math.floor(0.71 * 32767)
    M.analog[ANALOG_JOY_R] = -math.floor(0.71 * 32767)
    M.analog[ANALOG_JOY_X] = math.floor(0.54 * 32767)
    M.analog[ANALOG_JOY_Y] = -math.floor(0.83 * 32767)
    st = In.Poll(1 / 60)
    check("no module: gamepad stick in the corner (round gate) = full on both axes",
        st.roll > 0.99 and st.pitch > 0.99 and st.yaw > 0.6 and st.thr > 0.99,
        string.format("roll %.2f pitch %.2f yaw %.2f thr %.2f", st.roll, st.pitch, st.yaw, st.thr))
    M.analog[ANALOG_JOY_X], M.analog[ANALOG_JOY_Y] = 0, 0
    M.analog[ANALOG_JOY_U], M.analog[ANALOG_JOY_R] = math.floor(0.5 * 32767), 0
    st = In.Poll(1 / 60)
    check("no module: half stick straight = half", math.abs(st.roll - 0.5) < 0.01 and st.pitch == 0,
        string.format("roll %.2f pitch %.2f", st.roll, st.pitch))
    M.analog[ANALOG_JOY_R], M.analog[ANALOG_JOY_U] = 0, 0
    M.buttons[JOYSTICK_FIRST_BUTTON] = true
    st = In.Poll(1 / 60)
    M.buttons[JOYSTICK_FIRST_BUTTON] = nil
    st = In.Poll(1 / 60)
    check("no module: A arms (toggle)", st.arm == true, tostring(st.arm))
    ic.backend = "auto"
    st = In.Poll(1 / 60)
    check("no module, RC radio selected: no radio read (keyboard)", st.backend == "keyboard", st.backend)
    local legacy = FPV.Config.Defaults().input
    legacy.gamepad.enabled = true
    FPV.Config.data.input = legacy
    st = In.Poll(1 / 60)
    check("old 'I'm using a gamepad' setting becomes the Gamepad input source", legacy.backend == "gamepad" and st.backend == "gamepad", legacy.backend)
    local old = FPV.Config.Defaults().input
    old.backend = "gamepad"
    old.gamepad.expo, old.deadband = 0.35, 0.06
    FPV.Config.data.input = old
    st = In.Poll(1 / 60)
    check("v0.7.2 gamepad settings: old deadband/expo defaults cleared, range relearned",
        old.deadband == 0 and old.gamepad.expo == 0 and old.cal[1].max == 1 and old.gamepad.rangeVer == 2,
        string.format("db %s expo %s max %.2f", tostring(old.deadband), tostring(old.gamepad.expo), old.cal[1].max))
    M.analog, M.buttons = {}, {}
    FPV.Config.data = FPV.Config.Defaults()
end

do
    local F = FPV.Flight
    if F.active then F.Stop() end
    local foreignView = function() return { origin = Vector(0, 0, 0) } end
    hook.Add("CalcView", "SomeThirdPersonAddon", foreignView)
    hook.Add("HUDPaint", "SomeHudAddon", function() end)
    hook.Add("Think", "SomeThinker", function() end)
    local objId = { IsValid = function() return true end }
    hook.Add("CreateMove", objId, function() end)
    M.entities = { [42] = M.newEnt(Vector(0, 0, 0.68), Angle(0, 0, 0)) }
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    local parked = M.hooks.CalcView.SomeThirdPersonAddon == nil and M.hooks.HUDPaint.SomeHudAddon == nil and M.hooks.CreateMove[objId] == nil
    check("shield parks foreign hooks in flight", F.active and parked and FPV.Guard.Count() == 3, tostring(FPV.Guard.Count()))
    check("shield keeps our hooks + others", M.hooks.CalcView.mayhem_view ~= nil and M.hooks.Think.SomeThinker ~= nil, "")
    hook.Add("RenderScreenspaceEffects", "LateBloom", function() end)
    M.time = M.time + 1.5
    hook.Run("Think")
    check("shield sweeps late hooks", M.hooks.RenderScreenspaceEffects.LateBloom == nil, "")
    F.Stop()
    check("shield restores after flight", M.hooks.CalcView.SomeThirdPersonAddon == foreignView and M.hooks.HUDPaint.SomeHudAddon
        and M.hooks.CreateMove[objId] and M.hooks.RenderScreenspaceEffects.LateBloom and not FPV.Guard.Active(), "")
    FPV.Config.data.game.shield = false
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    check("shield off = nothing parked", M.hooks.CalcView.SomeThirdPersonAddon ~= nil and not FPV.Guard.Active(), "")
    F.Stop()
    FPV.Config.data.game.shield = true
    hook.Remove("CalcView", "SomeThirdPersonAddon"); hook.Remove("HUDPaint", "SomeHudAddon"); hook.Remove("Think", "SomeThinker")
    hook.Remove("CreateMove", objId); hook.Remove("RenderScreenspaceEffects", "LateBloom")
end

do
    local me = LocalPlayer()
    local d = M.newEnt(Vector(0, 300, 0), Angle(0, 0, 0))
    function d:GetOwnerPlayer() return me end
    M.entsByClass.mayhem_x5 = { d }
    local ok, err = pcall(function() GM:HUDPaint() end)
    check("on-foot HUD (hints + drone marker)", ok, tostring(err))
    local ran
    local rcc = RunConsoleCommand
    RunConsoleCommand = function(c) ran = c end
    local r = GM:PlayerBindPress(me, "+menu", true)
    RunConsoleCommand = rcc
    check("Q opens settings", r == true and ran == "fpv_menu", tostring(ran))
end

do
    local drawn = {}
    local st = draw.SimpleText
    draw.SimpleText = function(t) drawn[#drawn + 1] = t end
    M.binds["+menu"] = "tab"; M.binds.gm_showspare1 = nil
    GM:HUDPaint()
    draw.SimpleText = st
    local all = table.concat(drawn, "|")
    check("hints use rebound keys", all:find("F1 / TAB", 1, true) and not all:find("Q", 1, true) and not all:find("bring the drone", 1, true), all)
    M.binds["+menu"] = "q"; M.binds.gm_showspare1 = "F3"

    local me = LocalPlayer()
    local vel = Vector(85, 0, 0)
    me.GetVelocity = function() return vel end
    me.IsOnGround = function() return true end
    me.GetMoveType = function() return MOVETYPE_WALK end
    me.InVehicle = function() return false end
    me.ShouldDrawLocalPlayer = function() return false end
    local base = Vector(0, 0, 64)
    local zmin, zmax, rmax = 1e9, -1e9, 0
    for i = 1, 400 do
        M.frameDt = 1 / 144
        local v = GM:CalcView(me, base, Angle(0, 0, 0), 90)
        if i > 150 then
            zmin, zmax = math.min(zmin, v.origin.z), math.max(zmax, v.origin.z)
            rmax = math.max(rmax, math.abs(v.angles.r))
        end
    end
    check("head bobs while walking", zmax - zmin > 1 and zmax - zmin < 3 and rmax > 0.2, string.format("dz %.2f roll %.2f", zmax - zmin, rmax))
    vel = Vector(0, 0, 0)
    local last
    for _ = 1, 400 do last = GM:CalcView(me, base, Angle(0, 0, 0), 90) end
    check("head settles when standing", math.abs(last.origin.z - 64) < 0.05 and math.abs(last.angles.r) < 0.05, string.format("z %.3f", last.origin.z))
    local t = GM:PlayerStepSoundTime({ GetVelocity = function() return Vector(85, 0, 0) end, Crouching = function() return false end })
    check("footsteps match the bob cadence", t > 450 and t < 560, string.format("%.0f ms", t))
end

do
    local SKIN = M.skins[FPV.Skin.NAME]
    check("skin defined", SKIN ~= nil and SKIN.Colours.Label.Dark.r > 200, "")
    local n, bad = 0, nil
    for _, hov in ipairs({ false, true }) do
        for _, on in ipairs({ false, true }) do
            local p = M.newPanel()
            p.m_bBackground = true
            p.IsHovered = function() return hov end
            p.GetChecked = function() return on end
            p.GetDisabled = function() return false end
            p.IsActive = function() return on end
            p.HasFocus = function() return on end
            p.GetSlideX = function() return 0.4 end
            p.GetFraction = function() return 0.5 end
            p.GetTall = function() return 28 end
            p.GetActiveTab = function() return p end
            p.IsMenuOpen = function() return on end
            p.ComboBox = p
            for k, fn in pairs(SKIN) do
                if type(fn) == "function" and k:sub(1, 5) == "Paint" then
                    local ok, err = pcall(fn, SKIN, p, 120, 24)
                    n = n + 1
                    if not ok then bad = k .. ": " .. tostring(err) end
                end
            end
        end
    end
    check("skin paints run", bad == nil and n > 60, bad or tostring(n))
    check("stock HUD hidden", GM:HUDShouldDraw("CHudHealth") == false and GM:HUDShouldDraw("CHudCrosshair") == false
        and GM:HUDShouldDraw("CHudGMod") == true and GM:HUDShouldDraw("CHudChat") == true, "")
    local ok = pcall(function() FPV.Menu.Open("About"); FPV.Menu.Reopen() end)
    check("about tab + in-place reopen", ok, "")
end

do
    local In = FPV.Input
    local ax = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local btn = 0
    fpvjoy = {
        Read = function() return false end, Info = function() return false end, Refresh = function() end,
        HidScan = function() return 1 end,
        HidInfo = function(i) if i == 0 then return true, "Controller (Xbox One For Windows)", 0x045E, 0x02FF, 5, 16, 5 end return false end,
        HidRead = function() return true, btn, 0, 1, ax[1], ax[2], ax[3], ax[4], ax[5], ax[6], ax[7], ax[8] end,
    }
    In.moduleLoaded, In.moduleTried = false, false
    util.IsBinaryModuleInstalled = function() return true end
    local realRequire = require
    require = function(n) if n == "fpvjoy" then return true end return realRequire(n) end
    FPV.Config.data = FPV.Config.Defaults()
    local ic = FPV.Config.data.input
    In.LoadModule()
    In.ApplyGamepad(ic, "xbox", "up")
    local st = In.Poll(1 / 60)
    check("gamepad: sticks centred = idle", st.ok and st.thr == 0 and st.roll == 0 and not st.arm, string.format("thr %.2f", st.thr))
    ax[2] = -1; ax[4] = 1; ax[5] = -0.5
    st = In.Poll(1 / 60)
    check("gamepad: left up = throttle, right stick = roll/pitch", st.thr > 0.99 and st.roll > 0.99 and math.abs(st.pitch - 0.5 * math.sqrt(1.25)) < 0.01,
        string.format("thr %.2f roll %.2f pitch %.2f", st.thr, st.roll, st.pitch))
    check("gamepad: no deadband and no expo by default", (ic.deadband or 0) == 0 and (ic.gamepad.expo or 0) == 0,
        string.format("db %s expo %s", tostring(ic.deadband), tostring(ic.gamepad.expo)))
    btn = 1; st = In.Poll(1 / 60); local a1 = st.arm
    btn = 0; st = In.Poll(1 / 60); local a2 = st.arm
    btn = 1; st = In.Poll(1 / 60); btn = 0; st = In.Poll(1 / 60); local a3 = st.arm
    check("gamepad: A toggles arm", a1 and a2 and not a3, string.format("%s %s %s", tostring(a1), tostring(a2), tostring(a3)))
    btn = 8; st = In.Poll(1 / 60)
    check("gamepad: Y = camera button", st.cam == true, "")
    btn = 0
    In.ApplyGamepad(ic, "xbox", "trigger")
    ax[2] = 0; ax[3] = -1
    st = In.Poll(1 / 60)
    check("gamepad: right trigger throttle", st.thr > 0.99, string.format("%.2f", st.thr))
    ax[3] = 0
    st = In.Poll(1 / 60)
    check("gamepad: trigger released = idle", st.thr == 0, string.format("%.2f", st.thr))
    In.ApplyGamepad(ic, "playstation", "trigger")
    ax = { 0, 0, 0, 0, -1, 0, 0, 0 }
    st = In.Poll(1 / 60)
    local t0 = st.thr
    ax[5] = 1
    st = In.Poll(1 / 60)
    check("gamepad: PlayStation R2 throttle", t0 == 0 and st.thr > 0.99, string.format("%.2f -> %.2f", t0, st.thr))
    require = realRequire
    fpvjoy = nil
    In.moduleLoaded, In.hid = false, false
    FPV.Config.data = FPV.Config.Defaults()
end

do
    local F = FPV.Flight
    if F.active then F.Stop() end
    local osdCalls = 0
    local od = FPV.OSD.Draw
    FPV.OSD.Draw = function(...) osdCalls = osdCalls + 1 return od(...) end
    M.entities = { [42] = M.newEnt(Vector(0, 0, 0.68), Angle(0, 0, 0)) }
    M.readQueue = { 42 }
    M.netRecv["mayhem_begin"]()
    hook.Run("HUDPaint")
    local normal = osdCalls
    M.concommands.mayhem_cinematic()
    osdCalls = 0
    hook.Run("HUDPaint")
    check("cinematic hides the OSD in flight", normal > 0 and osdCalls == 0 and FPV.Config.data.game.cinematic, string.format("%d -> %d", normal, osdCalls))
    F.Stop()
    FPV.OSD.Draw = od
    local drawn = 0
    local st = draw.SimpleText
    draw.SimpleText = function() drawn = drawn + 1 end
    GM:HUDPaint()
    local cine = drawn
    M.concommands.mayhem_cinematic()
    drawn = 0
    GM:HUDPaint()
    draw.SimpleText = st
    check("cinematic hides the on-foot HUD", cine == 0 and drawn > 0 and not FPV.Config.data.game.cinematic, string.format("%d / %d", cine, drawn))
end

do
    local C = FPV.Config
    local rates = C.data.rates
    rates.rc_rate[1] = 33
    C.data.pids.roll[1] = 99
    C.ResetSections(C.SECTIONS["Rates"])
    check("tab reset restores defaults in place", C.data.rates == rates and rates.rc_rate[1] == 7 and C.data.pids.roll[1] == 99, "")
    C.data.input.calibrated = true
    C.data.game.headBob = 0.2
    C.FactoryReset()
    check("factory reset", C.data.pids.roll[1] == 45 and not C.data.input.calibrated and C.data.game.headBob == 1, "")
    local ok, err = pcall(function() FPV.Skin.Confirm("Reset", "Sure?", "Reset", function() end) end)
    check("confirm dialog builds", ok, tostring(err))
end

do
    local Mu = FPV.Music
    local mc = FPV.Config.data.music
    mc.shuffle = false
    M.dirs["sound/mayhem_music/"] = { "Zebra_Run.mp3", "cover.jpg", "alpha.ogg", "user" }
    M.dirs["sound/mayhem_music/user/"] = { "track_001.mp3", "track_002.wav", "index.txt" }
    M.files["sound/mayhem_music/user/index.txt"] = "track_001.mp3\tМоя пісня\ntrack_002.wav\tSecond one\n"
    M.audio = { ["sound/mayhem_music/alpha.ogg"] = 120, ["sound/mayhem_music/Zebra_Run.mp3"] = 90,
        ["sound/mayhem_music/user/track_001.mp3"] = 200 }
    M.id3 = { ["sound/mayhem_music/alpha.ogg"] = { title = "Alpha", artist = "Some Band" } }
    local n = Mu.Scan()
    local names = {}
    for _, t in ipairs(Mu.tracks) do names[#names + 1] = t.title end
    check("music: playlist from both folders", n == 4 and names[1] == "alpha" and names[2] == "Zebra Run" and names[3] == "Моя пісня",
        table.concat(names, " | "))
    for _ = 1, 400 do M.time = M.time + 0.01; hook.Run("Think") end
    check("music: starts by itself", Mu.current and Mu.current.title == "alpha" and Mu.Playing(), Mu.current and Mu.current.title or "none")
    local drawn = {}
    local st = draw.SimpleText
    draw.SimpleText = function(t) drawn[#drawn + 1] = t end
    hook.Run("HUDPaint")
    draw.SimpleText = st
    local all = table.concat(drawn, "|")
    check("music: now-playing card with ID3 name", all:find("NOW PLAYING", 1, true) and all:find("Some Band - Alpha", 1, true), all)
    M.lastChannel.state = 0
    hook.Run("Think")
    check("music: next track on end", Mu.current.title == "Zebra Run", Mu.current.title)
    Mu.Next()
    Mu.Next()
    check("music: broken file skipped", Mu.current.title == "alpha" or Mu.current.title == "Моя пісня", Mu.current.title)
    M.lastChannel.t = 30
    local before = Mu.current
    Mu.Prev()
    check("music: previous restarts a track that's playing", Mu.current == before and M.lastChannel.t == 0, "")
    mc.when = "flying"
    hook.Run("Think")
    check("music: paused on foot when set to 'only while flying'", M.lastChannel.state == 2, tostring(M.lastChannel.state))
    mc.when = "always"
    hook.Run("Think")
    check("music: resumes", M.lastChannel.state == 1, tostring(M.lastChannel.state))
    Mu.SetVolume(0.2)
    check("music: volume", M.lastChannel.vol == 0.2, "")
    FPV.Config.data.game.cinematic = true
    drawn = {}
    draw.SimpleText = function(t) drawn[#drawn + 1] = t end
    Mu.Next()
    hook.Run("HUDPaint")
    draw.SimpleText = st
    FPV.Config.data.game.cinematic = false
    check("music: no card in cinematic mode", not table.concat(drawn, "|"):find("NOW PLAYING", 1, true), "")

    local imported
    local stState = 1
    fpvjoy = {
        Read = function() return false end, Info = function() return false end,
        MusicImport = function(p) imported = p return true end,
        MusicStatus = function() return stState, stState == 2 and 3 or 1, 3, stState == 2 and "ok" or "copying" end,
        MusicPickFolder = function() return "C:\\Music\\FPV" end,
        MusicClear = function() return true end,
    }
    FPV.Input.moduleLoaded = true
    check("music: import available with the module", Mu.CanImport(), "")
    Mu.ChooseFolder()
    check("music: folder dialog -> import", imported == "C:\\Music\\FPV" and mc.folder == imported and Mu.import.state == 1, tostring(imported))
    M.dirs["sound/mayhem_music/user/"] = { "track_001.mp3", "track_002.mp3", "track_003.mp3", "index.txt" }
    M.files["sound/mayhem_music/user/index.txt"] = "track_001.mp3\tA\ntrack_002.mp3\tB\ntrack_003.mp3\tC\n"
    stState = 2
    M.runTimers()
    check("music: rescanned after import", #Mu.tracks == 5 and Mu.import.state == 2, tostring(#Mu.tracks))
    local ok, err = pcall(function() FPV.Menu.Open("Music") end)
    check("music tab builds", ok, tostring(err))
    fpvjoy = nil
    FPV.Input.moduleLoaded = false
    Mu.Stop()
    mc.enabled = false
end

do
    local texts = {}
    local create = vgui.Create
    vgui.Create = function(cls, parent)
        local p = create(cls, parent)
        local st, ac = p.SetText, p.AddChoice
        p.SetText = function(self, t) texts[#texts + 1] = t; return self end
        p.AddChoice = function(self, t) texts[#texts + 1] = t; return self end
        p.SetVisible = function(self, v) if v == false then self.__hidden = true end return self end
        return p
    end
    FPV.Menu.Open("Radio")
    vgui.Create = create
    local paren = {}
    for _, t in ipairs(texts) do
        if type(t) == "string" and t:find("%b()") and not t:find("^%d/%d") then paren[#paren + 1] = t end
    end
    local all = table.concat(texts, "|")
    check("radio tab: no (...) asides", not all:find("Auto (radio module", 1, true) and not all:find("(axis 1)", 1, true)
        and not all:find("press to toggle", 1, true) and all:find("CH1", 1, true) ~= nil, "")
    check("video tab: asides + notes gone", not all:find("Camera uptilt (deg)", 1, true) and all:find("Camera uptilt", 1, true) ~= nil, "")
    check("quad tab: trimmed", not all:find("652 g", 1, true) and not all:find("applies on R", 1, true) and not all:find("blade-element props", 1, true)
        and not all:find("crashflip_expo)", 1, true) and not all:find("R (reset) replaces", 1, true) and all:find("Crash flip expo", 1, true) ~= nil, "")
    check("about: open alpha", all:find("open alpha", 1, true) ~= nil, "")
end

do
    local T = FPV.Tune
    local pids = FPV.Config.data.pids
    local before = { pids.roll[1], pids.roll[3], pids.roll[4] }
    pids.roll[1], pids.roll[3], pids.roll[4] = 20, 10, 0
    local st = SysTime
    SysTime = os.clock
    T.Start("freestyle")
    local n = 0
    while T.Running() and n < 20000 do
        M.time = M.time + 0.01
        hook.Run("Think")
        n = n + 1
    end
    SysTime = st
    local r = T.result
    check("autotune ran in slices", T.state == "done" and n > 20, string.format("%s after %d frames %s", T.state, n, tostring(T.message)))
    check("autotune applied PIDs", r and pids.roll[1] == r.pids.roll[1] and pids.roll[3] == r.pids.roll[3] and pids.roll[1] > 30, r and tostring(pids.roll[1]) or "")
    check("autotune result readable", r and #T.Describe(r.after) > 20, r and T.Describe(r.after) or "")
    T.Revert()
    check("autotune undo", pids.roll[1] == 20 and pids.roll[3] == 10 and pids.roll[4] == 0, string.format("P%d D%d F%d", pids.roll[1], pids.roll[3], pids.roll[4]))
    pids.roll[1], pids.roll[3], pids.roll[4] = before[1], before[2], before[3]
end

try("config save/load", function()
    FPV.Config.data.rates.rc_rate[1] = 9
    FPV.Config.Save()
    local d = FPV.Config.Load()
    assert(d.rates.rc_rate[1] == 9, "rc_rate not persisted")
    assert(d.input.cal[1] and d.input.cal[1].min, "cal lost")
end)

print(fails == 0 and "ALL SMOKE TESTS PASSED" or (fails .. " FAILURE(S)"))
