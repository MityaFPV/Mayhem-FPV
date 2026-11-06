local FPV = MayhemFPV

local In = {}
FPV.Input = In

local NAXES = 8
In.NAXES = NAXES
local EDGETX_VID, EDGETX_PID = 0x1209, 0x4F54

In.state = {
    backend = "none",
    ok = false,
    raw = { 0, 0, 0, 0, 0, 0, 0, 0 },
    buttons = 0,
    buttonsHi = 0,
    thr = 0, roll = 0, pitch = 0, yaw = 0,
    arm = false, reset = false,
    deviceName = "",
}
In.devices = {}
In.moduleLoaded = false
In.moduleError = nil

local retryAt = 0
local kbArm, kbArmPrev, kbThr = false, false, 0
local kbTurtle, kbTurtlePrev = false, false

function In.LoadModule()
    if In.moduleLoaded then return true end
    if In.moduleTried then return false end
    In.moduleTried = true
    if util.IsBinaryModuleInstalled and not util.IsBinaryModuleInstalled("fpvjoy") then
        In.moduleError = "gmcl_fpvjoy_win64.dll not found in garrysmod/lua/bin"
        return false
    end
    local ok, err = pcall(require, "fpvjoy")
    if ok and fpvjoy and fpvjoy.Read then
        In.moduleLoaded = true
        In.moduleError = nil
        In.hid = fpvjoy.HidScan ~= nil
        if not In.hid then print("[Mayhem FPV] old fpvjoy module: only 6 axes. Install the new gmcl_fpvjoy_win64.dll.") end
        In.RefreshDevices()
    else
        In.moduleError = tostring(err or "module did not register")
    end
    return In.moduleLoaded
end

function In.RefreshDevices()
    In.devices = {}
    if not In.moduleLoaded then return In.devices end
    if In.hid then
        local n = fpvjoy.HidScan() or 0
        for id = 0, n - 1 do
            local ok, name, vid, pid, axes, buttons = fpvjoy.HidInfo(id)
            if ok then
                local edgetx = (vid == EDGETX_VID and pid == EDGETX_PID)
                In.devices[#In.devices + 1] = {
                    id = id, name = edgetx and ("EdgeTX radio (" .. name .. ")") or name,
                    vid = vid, pid = pid, axes = axes, buttons = buttons, edgetx = edgetx,
                    key = string.format("%04X:%04X:%s", vid, pid, name),
                }
            end
        end
        return In.devices
    end
    if fpvjoy.Refresh then fpvjoy.Refresh() end
    for id = 0, 15 do
        local ok, name, vid, pid, axes, buttons = fpvjoy.Info(id)
        if ok then
            local label = name
            if vid == EDGETX_VID and pid == EDGETX_PID then label = "EdgeTX radio (" .. name .. ")" end
            In.devices[#In.devices + 1] = {
                id = id, name = label, vid = vid, pid = pid, axes = axes, buttons = buttons,
                edgetx = (vid == EDGETX_VID and pid == EDGETX_PID),
                key = string.format("%04X:%04X:%s", vid, pid, name),
            }
        end
    end
    return In.devices
end

function In.ActiveDevice()
    local ic = FPV.Config.data.input
    local want = ic.deviceKey
    local pad = ic.backend == "gamepad"
    local first, edge, other
    for _, d in ipairs(In.devices) do
        if want and want ~= "" and d.key == want then return d.id end
        if d.edgetx and not edge then edge = d.id end
        if not d.edgetx and not other then other = d.id end
        if not first then first = d.id end
    end
    if pad then return other or first end
    return edge or first
end

local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

local function calAxis(cfg, i, centered)
    local v = In.state.raw[i] or 0
    local c = cfg.cal[i] or { min = -1, mid = 0, max = 1 }
    if not centered then
        local span = c.max - c.min
        if math.abs(span) < 1e-3 then return 0 end
        return clamp((v - c.min) / span * 2 - 1, -1, 1)
    end
    if v >= c.mid then
        local d = c.max - c.mid
        return d > 1e-3 and clamp((v - c.mid) / d, -1, 1) or 0
    end
    local d = c.mid - c.min
    return d > 1e-3 and clamp((v - c.mid) / d, -1, 1) or 0
end

local function stick(cfg, m, centered)
    if not m or not m.axis or m.axis < 1 or m.axis > NAXES then return 0 end
    local v = calAxis(cfg, m.axis, centered)
    if m.inv then v = -v end
    if centered then
        local db = cfg.deadband or 0
        if db > 0 then
            local a = math.abs(v)
            if a < db then v = 0 else v = (v > 0 and 1 or -1) * (a - db) / (1 - db) end
        end
    end
    return v
end

local toggles = setmetatable({}, { __mode = "k" })

local function rawSwitch(sw)
    local st = In.state
    if sw.kind == "button" then
        local idx = sw.index or 1
        if idx < 1 or idx > 32 then return false end
        local on = bit.band(st.buttons, bit.lshift(1, idx - 1)) ~= 0
        if sw.inv then on = not on end
        return on
    end
    local v = st.raw[sw.index or 5] or 0
    if sw.inv then v = -v end
    return v > (sw.threshold or 0.3)
end

function In.SwitchActive(sw)
    if not sw or sw.kind == "none" then return false end
    local on = rawSwitch(sw)
    if not sw.toggle then return on end
    local t = toggles[sw]
    if not t then t = { prev = on, latched = false }; toggles[sw] = t end
    if on and not t.prev then t.latched = not t.latched end
    t.prev = on
    return t.latched
end

In.GAMEPADS = {
    xbox = {
        yaw = { axis = 1, inv = false }, roll = { axis = 4, inv = false }, pitch = { axis = 5, inv = true },
        stickThr = { axis = 2, inv = true }, trigThr = { axis = 3, inv = true, mode = "up" },
        arm = 1, turtle = 2, cam = 4, reset = 7,
    },
    playstation = {
        yaw = { axis = 1, inv = false }, roll = { axis = 3, inv = false }, pitch = { axis = 6, inv = true },
        stickThr = { axis = 2, inv = true }, trigThr = { axis = 5, inv = false, mode = "full" },
        arm = 2, turtle = 3, cam = 4, reset = 9,
    },
}

In.GAMEPADS_GMOD = {
    xbox = {
        yaw = { axis = 1, inv = false }, roll = { axis = 5, inv = false }, pitch = { axis = 4, inv = true },
        stickThr = { axis = 2, inv = true }, trigThr = { axis = 3, inv = true, mode = "up" },
        arm = 1, turtle = 2, cam = 4, reset = 7,
    },
}
In.GAMEPADS_GMOD.playstation = In.GAMEPADS_GMOD.xbox

local gmodPadOn = false
function In.EnableGamepad()
    if gmodPadOn then return end
    gmodPadOn = true
    local cv = GetConVar("joystick")
    In.padNeedsRestart = cv ~= nil and cv:GetString() == "0"
    RunConsoleCommand("joystick", "1")
end

local GMOD_AXES = { "ANALOG_JOY_X", "ANALOG_JOY_Y", "ANALOG_JOY_Z", "ANALOG_JOY_R", "ANALOG_JOY_U", "ANALOG_JOY_V" }
local function readGamepad(st)
    local raw = st.raw
    for i = 1, NAXES do
        local code = GMOD_AXES[i] and _G[GMOD_AXES[i]]
        raw[i] = code and clamp((input.GetAnalogValue(code) or 0) / 32767, -1, 1) or 0
    end
    local b = 0
    for i = 0, 15 do
        if input.IsButtonDown((JOYSTICK_FIRST_BUTTON or 114) + i) then b = bit.bor(b, bit.lshift(1, i)) end
    end
    st.buttons, st.buttonsHi = b, 0
end

function In.ApplyGamepad(ic, layout, throttle)
    local set = In.LoadModule() and In.GAMEPADS or In.GAMEPADS_GMOD
    local L = set[layout] or set.xbox
    local gp = ic.gamepad
    gp.layout = layout
    ic.backend = "gamepad"
    ic.map.yaw = { axis = L.yaw.axis, inv = L.yaw.inv }
    ic.map.roll = { axis = L.roll.axis, inv = L.roll.inv }
    ic.map.pitch = { axis = L.pitch.axis, inv = L.pitch.inv }
    if throttle == "trigger" then
        ic.map.thr = { axis = L.trigThr.axis, inv = L.trigThr.inv }
        gp.throttle = L.trigThr.mode
    else
        ic.map.thr = { axis = L.stickThr.axis, inv = L.stickThr.inv }
        gp.throttle = throttle == "full" and "full" or "up"
    end
    for i = 1, NAXES do ic.cal[i] = { min = -1, mid = 0, max = 1 } end
    ic.arm = { kind = "button", index = L.arm, inv = false, threshold = 0.3, toggle = true }
    ic.turtle = { kind = "button", index = L.turtle, inv = false, threshold = 0.3, toggle = true }
    ic.camSw = { kind = "button", index = L.cam, inv = false, threshold = 0.3 }
    ic.reset = { kind = "button", index = L.reset, inv = false, threshold = 0.3 }
    ic.deadband = math.max(ic.deadband or 0, 0.06)
    ic.calibrated, ic.needsRecal = true, false
end

local function pollKeyboard(dt)
    local st = In.state
    local typing = IsValid(LocalPlayer()) and LocalPlayer():IsTyping() or vgui.GetKeyboardFocus() ~= nil
    local function k(code) return (not typing) and input.IsKeyDown(code) end
    local function axis(pos, neg) return (k(pos) and 1 or 0) - (k(neg) and 1 or 0) end
    st.roll = axis(KEY_D, KEY_A) * 0.6
    st.pitch = axis(KEY_W, KEY_S) * 0.6
    st.yaw = axis(KEY_RIGHT, KEY_LEFT) * 0.5
    kbThr = clamp(kbThr + axis(KEY_UP, KEY_DOWN) * dt * 0.8, 0, 1)
    if k(KEY_LSHIFT) then kbThr = 0 end
    st.thr = kbThr
    local a = k(KEY_SPACE)
    if a and not kbArmPrev then kbArm = not kbArm end
    kbArmPrev = a
    st.arm = kbArm
    local t = k(KEY_T)
    if t and not kbTurtlePrev then kbTurtle = not kbTurtle end
    kbTurtlePrev = t
    st.turtle = kbTurtle
    st.reset = false
    st.ok = true
end

function In.ResetKeyboard()
    kbThr = 0
    kbArm, kbTurtle = false, false
    for _, t in pairs(toggles) do t.latched = false end
end

function In.Snapshot()
    local st = In.state
    local t = { buttons = st.buttons or 0 }
    for i = 1, NAXES do t[i] = st.raw[i] or 0 end
    return t
end

function In.DetectSwitch(a, b, ignoreAxes)
    local best, bestD = nil, 0
    for i = 1, NAXES do
        if not (ignoreAxes and ignoreAxes[i]) then
            local d = b[i] - a[i]
            if math.abs(d) > math.abs(bestD) then best, bestD = i, d end
        end
    end
    if best and math.abs(bestD) >= 0.4 then
        local inv = bestD < 0
        local v0 = inv and -a[best] or a[best]
        local v1 = inv and -b[best] or b[best]
        return { kind = "axis", index = best, inv = inv, threshold = (v0 + v1) * 0.5 }
    end
    local diff = bit.bxor(b.buttons, a.buttons)
    if diff ~= 0 then
        local idx = 1
        while bit.band(diff, bit.lshift(1, idx - 1)) == 0 and idx < 32 do idx = idx + 1 end
        local nowOn = bit.band(b.buttons, bit.lshift(1, idx - 1)) ~= 0
        return { kind = "button", index = idx, inv = not nowOn, threshold = 0.3 }
    end
    return nil
end

function In.Poll(dt)
    local cfg = FPV.Config.data.input
    local st = In.state
    if cfg.gamepad and cfg.gamepad.enabled and cfg.backend ~= "keyboard" then
        cfg.backend = "gamepad"
        cfg.gamepad.enabled = nil
    end
    local backend = cfg.backend
    if backend == "gamepad" then
        backend = In.LoadModule() and "fpvjoy" or "gamepad"
    elseif backend ~= "keyboard" then
        backend = In.LoadModule() and "fpvjoy" or "keyboard"
    end
    st.backend = backend

    if backend == "keyboard" then
        pollKeyboard(dt or 0)
        return st
    end

    local raw = st.raw
    st.path = (backend == "fpvjoy") and (In.hid and "hid" or "winmm") or backend
    if backend == "gamepad" then
        In.EnableGamepad()
        readGamepad(st)
        st.ok = true
    elseif backend == "fpvjoy" then
        local now = SysTime()
        local id = In.ActiveDevice()
        if id == nil then
            st.ok = false
            if now > retryAt then retryAt = now + 2; In.RefreshDevices() end
        elseif st.ok or now > retryAt then
            local ok
            if In.hid then
                local lo, hi, reps, a1, a2, a3, a4, a5, a6, a7, a8
                ok, lo, hi, reps, a1, a2, a3, a4, a5, a6, a7, a8 = fpvjoy.HidRead(id)
                if ok then
                    raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7], raw[8] = a1, a2, a3, a4, a5, a6, a7, a8
                    st.buttons, st.buttonsHi = lo or 0, hi or 0
                    st.reports = reps
                end
            else
                local a1, a2, a3, a4, a5, a6, buttons
                ok, a1, a2, a3, a4, a5, a6, buttons = fpvjoy.Read(id)
                if ok then
                    raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7], raw[8] = a1, a2, a3, a4, a5, a6, 0, 0
                    st.buttons, st.buttonsHi = buttons or 0, 0
                end
            end
            if ok then
                st.ok = true
                st.deviceId = id
            else
                st.ok = false
                retryAt = now + 2
                In.RefreshDevices()
            end
        end
    else
        st.ok = false
    end

    local m = cfg.map
    local gp = cfg.gamepad
    if gp and cfg.backend == "gamepad" then
        local t = stick(cfg, m.thr, true)
        if gp.throttle == "full" then st.thr = (t + 1) * 0.5 else st.thr = math.max(0, t) end
        local e = gp.expo or 0
        local function ex(v) return v * (1 - e) + v * v * v * e end
        st.roll = ex(stick(cfg, m.roll, true))
        st.pitch = ex(stick(cfg, m.pitch, true))
        st.yaw = ex(stick(cfg, m.yaw, true))
    else
        st.thr = (stick(cfg, m.thr, false) + 1) * 0.5
        st.roll = stick(cfg, m.roll, true)
        st.pitch = stick(cfg, m.pitch, true)
        st.yaw = stick(cfg, m.yaw, true)
    end
    st.arm = In.SwitchActive(cfg.arm)
    st.reset = In.SwitchActive(cfg.reset)
    st.turtle = In.SwitchActive(cfg.turtle)
    st.cam = In.SwitchActive(cfg.camSw)
    if not st.ok then
        st.thr, st.roll, st.pitch, st.yaw, st.arm, st.turtle, st.cam = 0, 0, 0, 0, false, false, false
    end
    return st
end

concommand.Add("fpv_joy_list", function()
    if not In.LoadModule() then
        print("[FPV] joystick module not loaded: " .. tostring(In.moduleError))
        return
    end
    In.RefreshDevices()
    if #In.devices == 0 then print("[FPV] no joysticks found") end
    for _, d in ipairs(In.devices) do
        print(string.format("[FPV] id %d: %s  VID %04X PID %04X  %d axes, %d buttons", d.id, d.name, d.vid, d.pid, d.axes, d.buttons))
    end
end)
