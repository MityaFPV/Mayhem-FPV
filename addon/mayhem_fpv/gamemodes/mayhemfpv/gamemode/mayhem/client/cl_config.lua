local FPV = MayhemFPV

local C = {}
FPV.Config = C

local DIR = "fpv_drone"
local PATH = "fpv_drone/settings.json"

function C.Defaults()
    local cal = {}
    for i = 1, 8 do cal[i] = { min = -1, mid = 0, max = 1 } end
    return {
        version = 5,
        preset = "mayhem_x5",
        input = {
            backend = "auto",
            device = -1,
            map = {
                thr = { axis = 1, inv = false },
                roll = { axis = 2, inv = false },
                pitch = { axis = 3, inv = false },
                yaw = { axis = 4, inv = false },
            },
            cal = cal,
            arm = { kind = "axis", index = 5, inv = false, threshold = 0.3 },
            reset = { kind = "none", index = 6, inv = false, threshold = 0.3 },
            turtle = { kind = "none", index = 6, inv = false, threshold = 0.3 },
            camSw = { kind = "none", index = 4, inv = false, threshold = 0.3 },
            gamepad = {
                throttle = "up",
                expo = 0,
                layout = "xbox",
            },
            deadband = 0.0,
            calibrated = false,
            calibratedWith = "",
            deviceKey = "",
        },
        rates = FPV.Rates.defaults(),
        pids = FPV.Presets.defaultPids(),
        misc = FPV.Presets.defaultFcMisc(),
        camera = {
            uptilt = 30,
            fov = 120,
            mode = "fpv",
            chaseDist = 1.4,
            chaseHeight = 0.45,
        },
        osd = {
            enabled = true,
            craftName = "MAYHEM X5",
            video = "PAL",
            stickHUD = true,
            stickMode = 2,
            layout = {},
            craft = true, lq = true, voltage = true, cell = true, current = true,
            mah = true, timer = true, throttle = true, mode = true,
            crosshair = true, warnings = true, stats = true,
            gps_speed = false, altitude = false, rssi = false,
        },
        sound = {
            enabled = true,
            volume = 0.8,
            mode = "onboard",
        },
        video = {
            enabled = true,
            vtxPower = 600,
            rxPower = 250,
            noise = 1.0,
            fisheye = 0.0,
            scanlines = true,
            saturation = 0.85,
            shake = true,
            failsafe = true,
            model = "lit",
            modelBrightness = 1.0,
            props = "show",
            propColor = "smoke",
            actionCam = true,
        },
        music = {
            enabled = true,
            volume = 0.5,
            shuffle = true,
            notify = true,
            when = "always",
            folder = "",
        },
        game = {
            shield = true,
            hints = true,
            headBob = 1.0,
            cinematic = false,
        },
        sim = {
            rate = 2000,
            phys = 2,
            collideEvery = 2,
            propwash = 1.0,
            rotorDrag = 1.0,
            damage = 1.0,
            battery = 1400,
            cells = 6,
            charge = "full",
            packHealth = "new",
            ambient = 20,
            worldScale = 0.01905,
        },
    }
end

local function merge(dst, src)
    for k, v in pairs(src) do
        local d = dst[k]
        if type(v) == "table" and type(d) == "table" then
            merge(d, v)
        elseif d == nil or type(v) == type(d) then
            dst[k] = v
        end
    end
    return dst
end

function C.Load()
    local data = C.Defaults()
    local raw = file.Read(PATH, "DATA")
    if raw and raw ~= "" then
        local t = util.JSONToTable(raw)
        if istable(t) then merge(data, t) end
    end
    local cal = data.input.cal
    for i = 1, 8 do
        if not istable(cal[i]) then cal[i] = cal[tostring(i)] or { min = -1, mid = 0, max = 1 } end
        cal[tostring(i)] = nil
    end
    if not FPV.Presets[data.preset] then data.preset = "mayhem_x5" end
    if data.osd.craftName == "FREESTYLE 5" then data.osd.craftName = "MAYHEM X5" end
    if (data.version or 1) < 2 then
        if math.abs(data.sim.worldScale - 0.0254) < 1e-6 then data.sim.worldScale = 0.01905 end
        data.version = 2
    end
    if (data.version or 1) < 4 then
        local d = C.Defaults().input
        data.input.map, data.input.cal = d.map, d.cal
        data.input.arm, data.input.calibrated, data.input.calibratedWith = d.arm, false, ""
        data.input.needsRecal = true
    end
    if (data.version or 1) < 5 then
        if data.sim.rate == 1000 then data.sim.rate = 2000 end
    end
    data.version = 5
    C.data = data
    return data
end

C.SECTIONS = {
    ["Radio"] = { "input" },
    ["Rates"] = { "rates" },
    ["Video, Sound & OSD"] = { "camera", "osd", "video", "sound", "game" },
    ["Quad & Tuning"] = { "preset", "sim", "misc", "pids" },
    ["Music"] = { "music" },
}

local function assign(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end

function C.ResetSections(keys)
    local d = C.Defaults()
    for _, k in ipairs(keys) do
        if type(C.data[k]) == "table" and type(d[k]) == "table" then assign(C.data[k], d[k]) else C.data[k] = d[k] end
    end
    C.Save()
    if FPV.Render and FPV.Render.Invalidate then FPV.Render.Invalidate() end
end

function C.FactoryReset()
    local keys = {}
    for k in pairs(C.Defaults()) do keys[#keys + 1] = k end
    C.ResetSections(keys)
end

function C.Save()
    if not C.data then return end
    file.CreateDir(DIR)
    file.Write(PATH, util.TableToJSON(C.data, true))
end

function C.SaveSoon()
    timer.Create("mayhem_save", 0.6, 1, C.Save)
end

C.Load()
