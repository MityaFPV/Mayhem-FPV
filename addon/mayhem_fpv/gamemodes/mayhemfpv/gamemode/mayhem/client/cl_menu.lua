local FPV = MayhemFPV

local M = {}
FPV.Menu = M

local function cfg() return FPV.Config.data end
local function changed() FPV.Config.SaveSoon() end

local DARK = Color(24, 24, 28)
local GRID = Color(60, 60, 68)
local TEXT = Color(230, 230, 235)
local DIM = Color(150, 150, 160)
local OK = Color(90, 220, 120)
local BAD = Color(240, 90, 80)
local AXCOL = { Color(255, 110, 110), Color(120, 220, 120), Color(110, 160, 255) }

local SK = FPV.Skin
local UI = SK.C

local function T(s)
    if M.plain and type(s) == "string" then s = string.gsub(string.gsub(s, "%s*%b()", ""), "%s+$", "") end
    return s
end
M.T = T

local function header(parent, text)
    local l = vgui.Create("DLabel", parent)
    l:SetText(string.upper(T(text)))
    l:SetFont("MayhemHeader")
    l:SetTextColor(Color(255, 150, 90))
    l:SetTall(18)
    l:Dock(TOP)
    l:DockMargin(8, 18, 8, 4)
    l.PaintOver = function(self, w, h)
        surface.SetFont(self:GetFont() or "MayhemHeader")
        local tw = surface.GetTextSize(self:GetText() or "")
        if tw + 12 < w then
            surface.SetDrawColor(UI.line)
            surface.DrawRect(tw + 12, math.floor(h / 2), w - tw - 12, 1)
        end
    end
    return l
end

local function note(parent, text)
    local l = vgui.Create("DLabel", parent)
    if M.noNotes then l:SetVisible(false) end
    l:SetText(T(text))
    l:SetFont("MayhemUISmall")
    l:SetTextColor(UI.dim)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:Dock(TOP)
    l:DockMargin(10, 2, 10, 4)
    return l
end

local function slider(parent, text, min, max, dec, value, onChange)
    local s = vgui.Create("DNumSlider", parent)
    s:SetText(T(text))
    s:SetMin(min)
    s:SetMax(max)
    s:SetDecimals(dec)
    s:SetValue(value)
    s:SetDark(true)
    s:SetTall(28)
    s:Dock(TOP)
    s:DockMargin(10, 0, 10, 0)
    local lbl, te = SK.child(s, "Label"), SK.child(s, "TextArea")
    if lbl then lbl:SetFont("MayhemUI") end
    if te then te:SetFont("MayhemUI"); te:SetTextColor(UI.text) end
    s.OnValueChanged = function(_, v) onChange(v); changed() end
    return s
end

local function check(parent, text, value, onChange)
    local c = vgui.Create("DCheckBoxLabel", parent)
    c:SetText(T(text))
    c:SetValue(value and true or false)
    c:SetDark(true)
    c:SetFont("MayhemUI")
    c:Dock(TOP)
    c:DockMargin(10, 6, 10, 2)
    c.OnChange = function(_, v) onChange(v and true or false); changed() end
    return c
end

local function row(parent, tall)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(tall or 26)
    p:Dock(TOP)
    p:DockMargin(10, 3, 10, 3)
    p:SetPaintBackground(false)
    return p
end

local function rowLabel(p, text, w)
    local l = vgui.Create("DLabel", p)
    l:SetText(T(text))
    l:SetDark(true)
    l:SetFont("MayhemUI")
    l:SetWide(w or 110)
    l:Dock(LEFT)
    return l
end

local function combo(p, choices, current, onSelect, w)
    local c = vgui.Create("DComboBox", p)
    c:SetWide(w or 180)
    c:Dock(LEFT)
    c:DockMargin(0, 0, 8, 0)
    c:SetSortItems(false)
    c:SetFont("MayhemUI")
    c:SetTextColor(UI.text)
    for _, ch in ipairs(choices) do
        c:AddChoice(T(ch[1]), ch[2], ch[2] == current)
    end
    c.OnMenuOpened = function(_, menu) if IsValid(menu) then menu:SetSkin(SK.NAME) end end
    c.OnSelect = function(_, _, _, data) onSelect(data); changed() end
    return c
end

local function button(p, text, fn, w, dock)
    local b = vgui.Create("DButton", p)
    b:SetText((string.gsub(T(text), "%.%.%.$", "")))
    b:SetFont("MayhemUI")
    b:SetWide(w or 140)
    b:Dock(dock or LEFT)
    b:DockMargin(0, 0, 8, 0)
    b.DoClick = fn
    return b
end

local function scroll(parent)
    local s = vgui.Create("DScrollPanel", parent)
    s:Dock(FILL)
    local vb = SK.child(s, "VBar")
    if vb then
        vb:SetWide(10)
        if vb.SetHideButtons then vb:SetHideButtons(true) end
    end
    M.lastScroll = s
    return s
end

local function drawGimbal(x, y, size, sx, sy, label)
    draw.RoundedBox(4, x, y, size, size, Color(40, 40, 46))
    surface.SetDrawColor(GRID)
    surface.DrawLine(x + size / 2, y + 4, x + size / 2, y + size - 4)
    surface.DrawLine(x + 4, y + size / 2, x + size - 4, y + size / 2)
    local px = x + size / 2 + math.Clamp(sx, -1, 1) * (size / 2 - 8)
    local py = y + size / 2 - math.Clamp(sy, -1, 1) * (size / 2 - 8)
    draw.RoundedBox(6, px - 6, py - 6, 12, 12, Color(255, 200, 60))
    draw.SimpleText(label, "DermaDefault", x + size / 2, y + size + 4, DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

local function drawBar(x, y, w, h, v, label, centered)
    draw.RoundedBox(3, x, y, w, h, Color(40, 40, 46))
    v = math.Clamp(v, -1, 1)
    if centered then
        local mid = x + w / 2
        local len = v * (w / 2 - 2)
        surface.SetDrawColor(80, 170, 255)
        if len >= 0 then surface.DrawRect(mid, y + 2, len, h - 4) else surface.DrawRect(mid + len, y + 2, -len, h - 4) end
        surface.SetDrawColor(GRID)
        surface.DrawLine(mid, y, mid, y + h)
    else
        surface.SetDrawColor(80, 170, 255)
        surface.DrawRect(x + 2, y + 2, (w - 4) * (v + 1) / 2, h - 4)
    end
    draw.SimpleText(label, "DermaDefault", x - 6, y + h / 2, TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%+.2f", v), "DermaDefault", x + w + 6, y + h / 2, DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function buildLive(parent)
    local live = vgui.Create("DPanel", parent)
    live:SetTall(300)
    live:Dock(TOP)
    live:DockMargin(6, 6, 6, 6)
    live.Paint = function(_, w, h)
        local st = FPV.Input.state
        draw.RoundedBox(6, 0, 0, w, h, DARK)
        local size = 150
        drawGimbal(16, 34, size, st.yaw, st.thr * 2 - 1, "Yaw / Throttle")
        drawGimbal(32 + size, 34, size, st.roll, st.pitch, "Roll / Pitch")
        local bx = 2 * size + 110
        local bw = math.max(80, w - bx - 70)
        for i = 1, 8 do
            drawBar(bx, 30 + (i - 1) * 22, bw, 16, st.raw[i] or 0, "CH" .. i .. " / Axis " .. i, true)
        end
        local by = 30 + 8 * 22 + 6
        draw.SimpleText("Buttons:", "DermaDefault", bx - 6, by + 6, TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        for i = 1, 32 do
            local on = bit.band(st.buttons or 0, bit.lshift(1, i - 1)) ~= 0
            local cx = bx + ((i - 1) % 16) * 16
            local cy = by + math.floor((i - 1) / 16) * 16
            draw.RoundedBox(3, cx, cy, 13, 13, on and OK or Color(50, 50, 56))
        end
        local status
        if st.backend == "keyboard" then
            status = "Keyboard: W/S pitch, A/D roll, Left/Right yaw, Up/Down throttle, Space arm, Shift cut"
        elseif st.ok then
            status = st.path == "winmm" and "Radio OK - old module, 6 channels only: install the new gmcl_fpvjoy_win64.dll" or "Radio OK"
        else
            status = "No radio data"
        end
        draw.SimpleText(status, "DermaDefaultBold", 16, 10, st.ok and OK or BAD)
        draw.SimpleText(st.arm and "ARM SWITCH: ON" or "ARM SWITCH: OFF", "DermaDefaultBold", w - 16, 10,
            st.arm and OK or DIM, TEXT_ALIGN_RIGHT)
        draw.SimpleText(string.format("THR %3d%%", math.floor(st.thr * 100 + 0.5)), "DermaDefault", 16 + size / 2, h - 18, TEXT, TEXT_ALIGN_CENTER)
    end
    return live
end

local AXIS_CHOICES = {}
for i = 1, 8 do AXIS_CHOICES[i] = { "CH" .. i, i } end

function M.BuildGamepad(root, ic)
    local gp = ic.gamepad
    header(root, "Gamepad")
    check(root, "I'm using a gamepad (self-centring sticks)", gp.enabled, function(v) gp.enabled = v end)
    local r1 = row(root)
    rowLabel(r1, "Layout", 140)
    combo(r1, { { "Xbox / XInput", "xbox" }, { "PlayStation", "playstation" } }, gp.layout or "xbox", function(v) gp.layout = v end, 200)
    local r2 = row(root)
    rowLabel(r2, "Throttle", 140)
    local thrChoice = (gp.throttle == "full") and "full" or "up"
    M.gpThrottle = M.gpThrottle or thrChoice
    combo(r2, {
        { "Left stick up (let go = idle)", "up" },
        { "Left stick, full travel (centre = 50%)", "full" },
        { "Right trigger", "trigger" },
    }, M.gpThrottle, function(v) M.gpThrottle = v end, 300)
    local r3 = row(root, 30)
    button(r3, "Set up gamepad", function()
        FPV.Input.ApplyGamepad(ic, gp.layout or "xbox", M.gpThrottle or "up")
        FPV.Config.Save()
        M.Reopen("Radio")
    end, 160)
    slider(root, "Stick expo (gamepad)", 0, 0.9, 2, gp.expo or 0.35, function(v) gp.expo = v end)
    note(root, "Left stick: throttle + yaw, right stick: roll + pitch. A / Cross arms (press to toggle), B / Circle turtle mode, "
        .. "Back / Share resets. Other pads: use the calibration wizard and Detect.")
end

function M.BuildRadio(parent)
    M.plain = true
    local root = scroll(parent)
    local ic = cfg().input

    local r1 = row(root)
    rowLabel(r1, "Input source")
    combo(r1, {
        { "Radio / gamepad", "auto" },
        { "Keyboard", "keyboard" },
    }, (ic.backend == "keyboard") and "keyboard" or "auto", function(v)
        ic.backend = v
    end, 230)
    local modLbl = vgui.Create("DLabel", r1)
    modLbl:Dock(FILL)
    modLbl:SetDark(true)
    FPV.Input.LoadModule()
    if FPV.Input.moduleLoaded then
        modLbl:SetText("fpvjoy module loaded")
    else
        modLbl:SetText("Radio module not installed: keyboard only")
    end

    local r2 = row(root)
    rowLabel(r2, "Device")
    local devCombo = vgui.Create("DComboBox", r2)
    devCombo:SetWide(330)
    devCombo:Dock(LEFT)
    devCombo:DockMargin(0, 0, 8, 0)
    local function fillDevices()
        devCombo:Clear()
        devCombo:AddChoice("Auto", "", (ic.deviceKey or "") == "")
        for _, d in ipairs(FPV.Input.devices) do
            devCombo:AddChoice(d.name, d.key, ic.deviceKey == d.key)
        end
    end
    fillDevices()
    devCombo.OnSelect = function(_, _, _, data) ic.deviceKey = data; changed() end
    button(r2, "Refresh", function() FPV.Input.RefreshDevices(); fillDevices() end, 90)

    if not FPV.Input.moduleLoaded then
        local mr = row(root, 30)
        local url = FPV.MODULE_URL or ""
        local b = button(mr, "Get the radio module", function() if url ~= "" then gui.OpenURL(url) end end, 200)
        b:SetEnabled(url ~= "")
        local ml = vgui.Create("DLabel", mr)
        ml:SetFont("MayhemUISmall")
        ml:SetTextColor(SK.C.dim)
        ml:SetText("Needed for radios and gamepads. Put gmcl_fpvjoy_win64.dll in garrysmod/lua/bin and restart.")
        ml:Dock(FILL)
    end

    buildLive(root)

    local wr = row(root, 30)
    button(wr, "Calibration wizard...", function() M.OpenWizard() end, 200)
    local wl = vgui.Create("DLabel", wr)
    wl:SetDark(true)
    wl:Dock(FILL)
    if ic.needsRecal then
        wl:SetTextColor(BAD)
        wl:SetText("v0.5 reads all 8 channels in a new order: please run the wizard again.")
    else
        wl:SetText(ic.calibrated and "Calibrated." or "Not calibrated yet - run the wizard once.")
    end

    header(root, "Channel mapping (wizard fills this in)")
    local names = { { "thr", "Throttle" }, { "roll", "Roll" }, { "pitch", "Pitch" }, { "yaw", "Yaw" } }
    for _, n in ipairs(names) do
        local m = ic.map[n[1]]
        local r = row(root)
        rowLabel(r, n[2])
        combo(r, AXIS_CHOICES, m.axis, function(v) m.axis = v end, 100)
        local c = vgui.Create("DCheckBoxLabel", r)
        c:SetText("Invert")
        c:SetDark(true)
        c:SetValue(m.inv)
        c:Dock(LEFT)
        c:DockMargin(4, 5, 0, 0)
        c.OnChange = function(_, v) m.inv = v; changed() end
    end

    local function switchRow(title, sw, allowNone)
        header(root, title)
        local r = row(root)
        rowLabel(r, "Source")
        local kinds = { { "Axis", "axis" }, { "Button", "button" } }
        if allowNone then table.insert(kinds, 1, { "None", "none" }) end
        combo(r, kinds, sw.kind, function(v) sw.kind = v end, 100)
        local wang = vgui.Create("DNumberWang", r)
        wang:SetMin(1)
        wang:SetMax(32)
        wang:SetValue(sw.index or 1)
        wang:SetWide(60)
        wang:Dock(LEFT)
        wang:DockMargin(0, 0, 8, 0)
        wang.OnValueChanged = function(_, v) sw.index = math.floor(tonumber(v) or 1); changed() end
        local c = vgui.Create("DCheckBoxLabel", r)
        c:SetText("Invert")
        c:SetDark(true)
        c:SetValue(sw.inv)
        c:Dock(LEFT)
        c:DockMargin(4, 5, 0, 0)
        c.OnChange = function(_, v) sw.inv = v; changed() end
        local detect = vgui.Create("DButton", r)
        detect:SetText("Detect")
        detect:SetWide(90)
        detect:Dock(LEFT)
        detect:DockMargin(12, 0, 0, 0)
        detect.DoClick = function(self)
            local before = FPV.Input.Snapshot()
            local ignore = {}
            for _, m in pairs(ic.map) do ignore[m.axis] = true end
            local t0 = RealTime()
            self:SetText("Flip it now...")
            local id = "mayhem_detect_" .. tostring(sw)
            hook.Add("Think", id, function()
                if not IsValid(self) then hook.Remove("Think", id) return end
                local found = FPV.Input.DetectSwitch(before, FPV.Input.Snapshot(), ignore)
                if found or RealTime() - t0 > 5 then
                    hook.Remove("Think", id)
                    if found then
                        sw.kind, sw.index, sw.inv, sw.threshold = found.kind, found.index, found.inv, found.threshold
                        FPV.Config.Save()
                        M.Reopen("Radio")
                    else
                        self:SetText("Nothing - retry")
                    end
                end
            end)
        end
        slider(root, "Axis threshold", -1, 1, 2, sw.threshold or 0.3, function(v) sw.threshold = v end)
        check(root, "Button toggles (press once = on, again = off), for gamepads", sw.toggle, function(v) sw.toggle = v end)
    end
    switchRow("Arm switch (Betaflight-style: throttle must be low; cycle switch if blocked)", ic.arm, false)
    switchRow("Turtle mode / crash flip (optional): turn on while disarmed, then arm", ic.turtle, true)
    switchRow("Reset to launch point (optional switch)", ic.reset, true)

    header(root, "Sticks")
    slider(root, "Deadband (roll/pitch/yaw)", 0, 0.2, 3, ic.deadband or 0, function(v) ic.deadband = v end)

    M.BuildGamepad(root, ic)
    M.plain = false
    return root
end

function M.OpenWizard()
    local ic = cfg().input
    local w = vgui.Create("DFrame")
    w:SetSize(620, 466)
    w:Center()
    w:MakePopup()
    SK.Window(w, "Radio calibration")
    w:DoModal()

    local snap = function()
        local st = FPV.Input.state
        local t = { buttons = st.buttons or 0 }
        for i = 1, 8 do t[i] = st.raw[i] or 0 end
        return t
    end
    local mins, maxs = {}, {}
    for i = 1, 8 do mins[i], maxs[i] = 99, -99 end
    local base
    local result = { map = {}, used = {} }

    local steps = {
        { text = "1/7  Center the roll, pitch and yaw stick, put THROTTLE fully DOWN and the ARM switch OFF.\nThen click Next." },
        { text = "2/7  Move BOTH sticks slowly through their FULL range: all four corners and full circles, 2-3 times.\nThen click Next." },
        { text = "3/7  Hold THROTTLE fully UP, then click Next.", key = "thr" },
        { text = "4/7  Center throttle back down. Hold ROLL stick fully RIGHT, click Next.", key = "roll" },
        { text = "5/7  Hold PITCH stick fully FORWARD (up), click Next.", key = "pitch" },
        { text = "6/7  Hold YAW stick fully RIGHT, click Next.", key = "yaw" },
        { text = "7/7  Release sticks. Flip your ARM switch ON, click Next.", key = "arm" },
        { text = "All set. Click Finish to save, then switch ARM off before flying." },
    }
    local idx = 1

    local lbl = vgui.Create("DLabel", w)
    lbl:Dock(TOP)
    lbl:DockMargin(10, 8, 10, 4)
    lbl:SetTall(70)
    lbl:SetWrap(true)
    lbl:SetFont("DermaDefaultBold")
    lbl:SetText(steps[1].text)

    local err = vgui.Create("DLabel", w)
    err:Dock(TOP)
    err:DockMargin(10, 0, 10, 4)
    err:SetTextColor(BAD)
    err:SetText("")

    local live = vgui.Create("DPanel", w)
    live:Dock(FILL)
    live:DockMargin(10, 4, 10, 4)
    live.Paint = function(_, pw, ph)
        local st = FPV.Input.state
        draw.RoundedBox(6, 0, 0, pw, ph, DARK)
        for i = 1, 8 do
            drawBar(70, 10 + (i - 1) * 22, pw - 140, 16, st.raw[i] or 0, "CH" .. i, true)
        end
        draw.SimpleText(st.ok and "radio OK" or "NO RADIO DATA", "DermaDefaultBold", 10, ph - 20, st.ok and OK or BAD)
    end
    local baseThinkW = w.Think
    w.Think = function(self)
        if baseThinkW then baseThinkW(self) end
        if not FPV.Flight.active then FPV.Input.Poll(FrameTime()) end
        local st = FPV.Input.state
        if idx >= 2 then
            for i = 1, 8 do
                local v = st.raw[i] or 0
                if v < mins[i] then mins[i] = v end
                if v > maxs[i] then maxs[i] = v end
            end
        end
    end

    local function detectAxis(cur)
        local best, bestD = nil, 0
        for i = 1, 8 do
            if not result.used[i] then
                local d = cur[i] - base[i]
                if math.abs(d) > math.abs(bestD) then best, bestD = i, d end
            end
        end
        if not best or math.abs(bestD) < 0.3 then return nil end
        return best, bestD
    end

    local nextBtn = vgui.Create("DButton", w)
    nextBtn:Dock(BOTTOM)
    nextBtn:DockMargin(10, 4, 10, 8)
    nextBtn:SetTall(30)
    nextBtn:SetText("Next")
    nextBtn.DoClick = function()
        err:SetText("")
        local step = steps[idx]
        local cur = snap()
        if idx == 1 then
            if not FPV.Input.state.ok then err:SetText("No radio data. Check the device in the Radio tab.") return end
            base = cur
            for i = 1, 8 do mins[i], maxs[i] = cur[i], cur[i] end
        elseif step.key == "arm" then
            local ax, d = detectAxis(cur)
            if ax and math.abs(d) >= 0.4 then
                local inv = d < 0
                local b0 = inv and -base[ax] or base[ax]
                local b1 = inv and -cur[ax] or cur[ax]
                result.arm = { kind = "axis", index = ax, inv = inv, threshold = (b0 + b1) * 0.5 }
            else
                local diff = bit.bxor(cur.buttons, base.buttons)
                if diff == 0 then err:SetText("No switch change detected. Flip ARM on (or off and on) and try again.") return end
                local bitIdx = 1
                while bit.band(diff, bit.lshift(1, bitIdx - 1)) == 0 and bitIdx < 32 do bitIdx = bitIdx + 1 end
                local pressedNow = bit.band(cur.buttons, bit.lshift(1, bitIdx - 1)) ~= 0
                result.arm = { kind = "button", index = bitIdx, inv = not pressedNow, threshold = 0.3 }
            end
        elseif step.key then
            local ax, d = detectAxis(cur)
            if not ax then err:SetText("No stick movement detected - hold the stick at full deflection and click Next.") return end
            result.used[ax] = true
            result.map[step.key] = { axis = ax, inv = d < 0 }
        elseif idx == #steps then
            for k, v in pairs(result.map) do ic.map[k] = v end
            if result.arm then
                ic.arm.kind, ic.arm.index, ic.arm.inv, ic.arm.threshold =
                    result.arm.kind, result.arm.index, result.arm.inv, result.arm.threshold
            end
            for i = 1, 8 do
                local c = ic.cal[i]
                if maxs[i] - mins[i] > 0.2 then
                    c.min, c.max = mins[i], maxs[i]
                    c.mid = math.Clamp(base[i], mins[i], maxs[i])
                end
            end
            ic.calibrated = true
            ic.calibratedWith = FPV.Input.state.path or ""
            ic.needsRecal = false
            FPV.Config.Save()
            w:Close()
            M.Reopen()
            return
        end
        idx = idx + 1
        lbl:SetText(steps[idx].text)
        if idx == #steps then nextBtn:SetText("Finish") end
    end
end

function M.BuildRates(parent)
    local root = scroll(parent)
    local Rates = FPV.Rates
    local r = cfg().rates

    local graph = vgui.Create("DPanel", root)
    graph:SetTall(230)
    graph:Dock(TOP)
    graph:DockMargin(6, 6, 6, 6)
    graph.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, DARK)
        local maxR = 200
        for a = 1, 3 do maxR = math.max(maxR, Rates.maxRate(r, a)) end
        maxR = math.ceil(maxR / 200) * 200
        local gx, gy, gw, gh = 50, 14, w - 230, h - 40
        surface.SetDrawColor(GRID)
        for i = 0, maxR, 200 do
            local y = gy + gh - i / maxR * gh
            surface.DrawLine(gx, y, gx + gw, y)
            draw.SimpleText(tostring(i), "DermaDefault", gx - 6, y, DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        surface.DrawLine(gx, gy, gx, gy + gh)
        draw.SimpleText("stick ->", "DermaDefault", gx + gw, gy + gh + 6, DIM, TEXT_ALIGN_RIGHT)
        draw.SimpleText("deg/s", "DermaDefault", gx, gy + gh + 6, DIM)
        local names = { "Roll", "Pitch", "Yaw" }
        for a = 3, 1, -1 do
            surface.SetDrawColor(AXCOL[a])
            local px, py
            for i = 0, 60 do
                local s = i / 60
                local v = Rates.setpoint(r, a, s)
                local x = gx + s * gw
                local y = gy + gh - v / maxR * gh
                if px then surface.DrawLine(px, py, x, y) end
                px, py = x, y
            end
            local cs = Rates.setpoint(r, a, 0.05) / 0.05
            draw.SimpleText(string.format("%s  max %d deg/s  center %d", names[a], math.floor(Rates.maxRate(r, a) + 0.5), math.floor(cs + 0.5)),
                "DermaDefaultBold", w - 170, 30 + (a - 1) * 22, AXCOL[a], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local typeRow = row(root)
    rowLabel(typeRow, "Rates type")
    local choices = {}
    for _, t in ipairs(Rates.TYPES) do choices[#choices + 1] = { t, t } end

    local area = vgui.Create("DPanel", root)
    area:Dock(TOP)
    area:SetPaintBackground(false)
    area:DockMargin(0, 0, 0, 0)

    local function buildArea()
        area:Clear()
        local ui = Rates.UI[r.type] or Rates.UI.ACTUAL
        local axisNames = { "Roll", "Pitch", "Yaw" }
        local fields = { "rc_rate", "srate", "expo" }
        local total = 0
        for a = 1, 3 do
            local h = header(area, axisNames[a])
            h:SetTextColor(AXCOL[a])
            total = total + 18 + 14
            for fi = 1, 3 do
                local spec = ui[fi]
                local field = fields[fi]
                local toD, fromD = spec[2], spec[3]
                slider(area, spec[1], spec[4], spec[5], spec[6], toD(r[field][a]), function(v)
                    r[field][a] = fromD(v)
                end)
                total = total + 30
            end
        end
        area:SetTall(total + 10)
    end
    combo(typeRow, choices, r.type, function(v) r.type = v; buildArea() end, 160)
    buildArea()

    header(root, "Throttle curve")
    slider(root, "Throttle mid", 0, 100, 0, r.thr_mid or 50, function(v) r.thr_mid = math.floor(v + 0.5) end)
    slider(root, "Throttle expo", 0, 100, 0, r.thr_expo or 0, function(v) r.thr_expo = math.floor(v + 0.5) end)

    header(root, "Paste from Betaflight CLI (diff all / dump) - rates, PIDs, idle, TPA")
    local te = vgui.Create("DTextEntry", root)
    te:SetMultiline(true)
    te:SetTall(110)
    te:Dock(TOP)
    te:DockMargin(8, 2, 8, 2)
    te:SetPlaceholderText("set rates_type = ACTUAL\nset roll_rc_rate = 7\nset roll_srate = 67\n...")
    local pr = row(root, 30)
    local res = vgui.Create("DLabel", pr)
    button(pr, "Apply CLI text", function()
        local c = cfg()
        local n = Rates.parseCLI(te:GetValue() or "", c.rates, c.pids, c.misc)
        FPV.Config.Save()
        res:SetText(n .. " setting(s) applied")
        timer.Simple(0.8, function() M.Reopen("Rates") end)
    end, 140)
    button(pr, "Betaflight defaults", function()
        local d = Rates.defaults()
        r.type = d.type
        for a = 1, 3 do r.rc_rate[a], r.srate[a], r.expo[a] = d.rc_rate[a], d.srate[a], d.expo[a] end
        r.thr_mid, r.thr_expo = d.thr_mid, d.thr_expo
        FPV.Config.Save()
        M.Reopen("Rates")
    end, 150)
    res:Dock(FILL)
    res:SetDark(true)
    res:SetText("")
    return root
end

function M.BuildCamera(parent)
    M.plain, M.noNotes = true, true
    local root = scroll(parent)
    local c = cfg().camera
    local o = cfg().osd
    local g = cfg().game
    header(root, "Game")
    check(root, "Shield the flight from other addons (their cameras, HUDs, keybinds and screen effects pause while you fly)", g.shield,
        function(v) g.shield = v end)
    check(root, "Cinematic mode", g.cinematic, function(v) g.cinematic = v end)
    check(root, "Show key hints on foot", g.hints, function(v) g.hints = v end)
    slider(root, "Head bob when walking (0 = off)", 0, 2, 2, g.headBob or 1, function(v) g.headBob = v end)

    header(root, "FPV camera")
    slider(root, "Camera uptilt (deg)", 0, 60, 0, c.uptilt, function(v) c.uptilt = v end)
    slider(root, "Horizontal FOV (deg)", 60, 170, 0, c.fov, function(v) c.fov = v end)

    local vid = cfg().video
    header(root, "Drone model")
    local mr = row(root)
    rowLabel(mr, "Shading", 140)
    combo(mr, {
        { "Map lighting (default)", "lit" },
        { "Simple (use if the model looks black)", "simple" },
        { "Old low-poly model", "legacy" },
    }, vid.model or "lit", function(v) vid.model = v; FPV.Render.Invalidate() end, 300)
    slider(root, "Model brightness", 0.3, 3, 2, vid.modelBrightness or 1, function(v) vid.modelBrightness = v end)
    local pr = row(root)
    rowLabel(pr, "Propellers", 140)
    combo(pr, { { "Show", "show" }, { "Hide in the FPV view", "hidefpv" }, { "Hide everywhere", "hide" } }, vid.props or "show",
        function(v) vid.props = v end, 220)
    local pc = row(root)
    rowLabel(pc, "Prop colour", 140)
    combo(pc, { { "Smoke black", "smoke" }, { "Orange", "orange" } }, vid.propColor or "smoke",
        function(v) vid.propColor = v; FPV.Render.Invalidate() end, 220)
    check(root, "Action camera on top", vid.actionCam ~= false, function(v) vid.actionCam = v end)

    header(root, "Analog video")
    check(root, "Analog look + signal breakup", vid.enabled, function(v) vid.enabled = v end)
    local vr = row(root)
    rowLabel(vr, "VTX power", 140)
    combo(vr, { { "25 mW", 25 }, { "200 mW", 200 }, { "400 mW", 400 }, { "600 mW", 600 }, { "1000 mW", 1000 }, { "1600 mW", 1600 } },
        vid.vtxPower, function(v) vid.vtxPower = v end, 140)
    local rr = row(root)
    rowLabel(rr, "Radio TX power", 140)
    combo(rr, { { "25 mW", 25 }, { "100 mW", 100 }, { "250 mW", 250 }, { "500 mW", 500 }, { "1000 mW", 1000 } },
        vid.rxPower or 250, function(v) vid.rxPower = v end, 140)
    slider(root, "Noise strength", 0, 2, 2, vid.noise, function(v) vid.noise = v end)
    slider(root, "Fisheye (lens distortion)", 0, 1, 2, vid.fisheye, function(v) vid.fisheye = v end)
    slider(root, "Colour saturation", 0, 1.5, 2, vid.saturation, function(v) vid.saturation = v end)
    check(root, "Scanlines", vid.scanlines, function(v) vid.scanlines = v end)
    check(root, "Camera shake from damaged props", vid.shake, function(v) vid.shake = v end)
    check(root, "Failsafe on control link loss (range / walls)", vid.failsafe, function(v) vid.failsafe = v end)
    note(root, "Signal is computed from you (your player) to the quad: distance, plus buildings in between. Like the real thing, the signal also bends around edges and bounces off walls, so a building costs you some snow, not the picture. Going far behind several blocks is where analog breaks up.")

    local snd = cfg().sound
    header(root, "Sound")
    check(root, "Motor sound", snd.enabled, function(v) snd.enabled = v; if FPV.Flight.active then if v then FPV.Sound.Start() else FPV.Sound.Stop() end end end)
    slider(root, "Volume", 0, 1, 2, snd.volume, function(v) snd.volume = v end)
    local sr = row(root)
    rowLabel(sr, "Hear the quad", 140)
    combo(sr, { { "Onboard (like other sims)", "onboard" }, { "From where you stand (realistic)", "pilot" } },
        snd.mode, function(v) snd.mode = v end, 260)

    header(root, "OSD (Betaflight analog style)")
    check(root, "Show OSD", o.enabled, function(v) o.enabled = v end)
    local nr = row(root)
    rowLabel(nr, "Craft name", 140)
    local ne = vgui.Create("DTextEntry", nr)
    ne:SetWide(200)
    ne:Dock(LEFT)
    ne:SetValue(o.craftName or "")
    ne.OnChange = function(self)
        o.craftName = string.upper(string.sub(self:GetValue() or "", 1, 16))
        changed()
    end
    local er = row(root, 30)
    button(er, "Edit OSD layout", function() M.OpenOSDEditor() end, 200)
    local vr2 = row(root)
    rowLabel(vr2, "Video system", 140)
    combo(vr2, { { "PAL (30 x 16)", "PAL" }, { "NTSC (30 x 13)", "NTSC" } }, o.video or "PAL", function(v) o.video = v end, 160)
    check(root, "Post-flight stats", o.stats ~= false, function(v) o.stats = v end)

    header(root, "Stick overlay")
    check(root, "Stick display beside the goggle frame (all cameras)", o.stickHUD, function(v) o.stickHUD = v end)
    note(root, "Betaflight's own OSD stick overlays (left/right) are in the OSD layout editor.")
    local sm = row(root)
    rowLabel(sm, "Radio mode", 140)
    combo(sm, { { "Mode 2 (throttle left)", 2 }, { "Mode 1 (throttle right)", 1 } }, o.stickMode or 2, function(v) o.stickMode = v end, 200)
    M.plain, M.noNotes = false, false
    return root
end

function M.OpenOSDEditor()
    local O = FPV.OSD
    O.Layout()
    local L = FPV.Config.data.osd.layout
    local f = vgui.Create("DFrame")
    f:SetSize(math.min(ScrW() - 40, 1180), math.min(ScrH() - 40, 720))
    f:Center()
    f:MakePopup()
    SK.Window(f, "OSD layout", "drag elements, tick to enable")
    f.OnClose = function() FPV.Config.Save() end

    local side = vgui.Create("DScrollPanel", f)
    side:Dock(RIGHT)
    side:SetWide(250)
    side:DockMargin(6, 0, 0, 0)

    local holder = vgui.Create("DPanel", f)
    holder:Dock(FILL)
    holder:SetPaintBackground(false)

    local canvas = vgui.Create("DPanel", holder)
    local sample = O.SampleContext()
    local boxes, selected, hover, drag = {}, nil, nil, nil
    holder.PerformLayout = function(self, w, h)
        local cw = math.min(w, h * 4 / 3)
        canvas:SetSize(cw, cw * 3 / 4)
        canvas:SetPos((w - cw) / 2, (h - cw * 3 / 4) / 2)
    end

    local function cellAt(px, py, w, h)
        local rows = O.Rows()
        return math.floor(px / (w / 30)), math.floor(py / (h / rows))
    end
    local function storedY(gridRow)
        if O.Rows() == 13 and gridRow >= 5 then return gridRow + 3 end
        return gridRow
    end
    local function boxAt(col, row)
        local best, area = nil, 1e9
        for _, b in ipairs(boxes) do
            if b.on and col >= b.x0 and col <= b.x1 and row >= b.y0 and row <= b.y1 then
                local a = (b.x1 - b.x0 + 1) * (b.y1 - b.y0 + 1)
                if a < area then best, area = b, a end
            end
        end
        return best
    end

    canvas.Paint = function(self, w, h)
        surface.SetDrawColor(92, 110, 128); surface.DrawRect(0, 0, w, h * 0.55)
        surface.SetDrawColor(58, 66, 54); surface.DrawRect(0, h * 0.55, w, h * 0.45)
        local rows = O.Rows()
        surface.SetDrawColor(255, 255, 255, 18)
        for c = 0, 30 do surface.DrawLine(c * w / 30, 0, c * w / 30, h) end
        for r = 0, rows do surface.DrawLine(0, r * h / rows, w, r * h / rows) end
        O.SetCanvas(0, 0, w, h, rows)
        boxes = {}
        O.Render(sample, boxes)
        local cw, ch = w / 30, h / rows
        for _, b in ipairs(boxes) do
            local sel = selected == b.id
            if sel or hover == b.id then
                surface.SetDrawColor(sel and 255 or 255, sel and 96 or 255, sel and 18 or 255, sel and 255 or 120)
                surface.DrawOutlinedRect(b.x0 * cw - 2, b.y0 * ch - 2, (b.x1 - b.x0 + 1) * cw + 4, (b.y1 - b.y0 + 1) * ch + 4, 2)
            end
        end
        if selected then
            local e
            for _, el in ipairs(O.ELEMENTS) do if el.id == selected then e = el end end
            if e then draw.SimpleTextOutlined(e.label, "DermaDefaultBold", 6, h - 6, Color(255, 150, 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0)) end
        end
    end
    canvas.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        local mx, my = self:CursorPos()
        local col, row = cellAt(mx, my, self:GetWide(), self:GetTall())
        local b = boxAt(col, row)
        if b then
            selected = b.id
            local p = L[b.id]
            drag = { id = b.id, dx = col - p.x, dy = row - O.gridY(p.y) }
            self:MouseCapture(true)
        else
            selected = nil
        end
    end
    canvas.OnMouseReleased = function(self)
        drag = nil
        self:MouseCapture(false)
        FPV.Config.SaveSoon()
    end
    canvas.Think = function(self)
        local mx, my = self:CursorPos()
        local col, row = cellAt(mx, my, self:GetWide(), self:GetTall())
        if drag then
            local p = L[drag.id]
            p.x = math.Clamp(col - drag.dx, 0, 29)
            p.y = math.Clamp(storedY(row - drag.dy), 0, 15)
        else
            local b = boxAt(col, row)
            hover = b and b.id or nil
        end
    end

    local function build()
        side:Clear()
        local t = vgui.Create("DLabel", side)
        t:SetText("Elements")
        t:SetFont("DermaDefaultBold")
        t:SetDark(true)
        t:Dock(TOP)
        t:DockMargin(4, 4, 4, 4)
        for _, e in ipairs(O.ELEMENTS) do
            local c = vgui.Create("DCheckBoxLabel", side)
            c:SetText(e.label)
            c:SetDark(true)
            c:SetValue(L[e.id].on and true or false)
            c:Dock(TOP)
            c:DockMargin(6, 3, 4, 0)
            c.OnChange = function(_, v) L[e.id].on = v and true or false; selected = e.id; FPV.Config.SaveSoon() end
        end
        local r = vgui.Create("DButton", side)
        r:SetText("Reset to defaults")
        r:Dock(TOP)
        r:DockMargin(6, 12, 6, 0)
        r.DoClick = function()
            O.ResetLayout()
            L = FPV.Config.data.osd.layout
            build()
        end
    end
    build()
end

local GOALS = {
    { "Freestyle (balanced)", "freestyle" },
    { "Race (sharpest tracking)", "race" },
    { "Smooth / cinematic (cool motors, no bounce)", "smooth" },
}

function M.BuildAutotune(root)
    local T = FPV.Tune
    header(root, "Autotune (Auto-PID)")
    note(root, "Flies quick test flights of this exact setup in the background (battery, props, physics model, filters, rates): "
        .. "hover, stick snaps on every axis, a throttle punch. It then sets the PIDs with Betaflight's master / D / feedforward sliders, "
        .. "so a custom PID ratio from a CLI paste is replaced. Takes a few seconds and you can keep flying. Undo restores your previous PIDs.")
    local r = row(root, 26)
    rowLabel(r, "Goal", 140)
    combo(r, GOALS, T.goal, function(v) T.goal = v end, 300)
    local run = button(r, "Run autotune", function()
        if T.Running() then T.Cancel() else T.Start(T.goal) end
    end, 130)
    local undo = button(r, "Undo", function()
        T.Revert()
        M.Reopen()
    end, 70)

    local pr = row(root, 18)
    local bar = vgui.Create("DProgress", pr)
    bar:Dock(FILL)
    bar:DockMargin(0, 2, 8, 2)
    local status = note(root, "")
    local res1 = note(root, "")
    local res2 = note(root, "")

    local function refresh()
        local running = T.Running()
        run:SetText(running and "Cancel" or "Run autotune")
        undo:SetEnabled(T.backup ~= nil and T.state == "done" and not T.reverted)
        bar:SetFraction(running and T.progress or (T.state == "done" and 1 or 0))
        local msg
        if running then
            msg = string.format("Test flying... %d%%", math.floor(T.progress * 100 + 0.5))
        elseif T.state == "done" and T.result then
            local x = T.result.sliders
            msg = string.format("Done: %d test flights in %.1f s. Sliders: master %.2f, D %.2f, FF %.2f (hover %d%% throttle). PIDs applied.",
                T.result.evals, T.seconds or 0, x.master, x.d, x.ff, math.floor(T.result.hover * 100 + 0.5))
            if T.reverted then msg = msg .. " (undone)" end
        else
            msg = T.message or "Not run yet."
        end
        if status:GetText() ~= msg then status:SetText(msg) end
        local a, b = "", ""
        if T.state == "done" and T.result then
            a = "Before: " .. T.Describe(T.result.before)
            b = "After:  " .. T.Describe(T.result.after)
        end
        if res1:GetText() ~= a then res1:SetText(a) end
        if res2:GetText() ~= b then res2:SetText(b) end
    end
    refresh()
    pr.Think = refresh
end

function M.OnTuneDone()
    if IsValid(M.frame) then M.Reopen() end
end

function M.BuildQuad(parent)
    local root = scroll(parent)
    local c = cfg()
    local sim, misc, pids = c.sim, c.misc, c.pids

    header(root, "Quad: Mayhem X5, 5\" 6S freestyle")
    header(root, "Battery")
    local br1 = row(root)
    rowLabel(br1, "Cells", 140)
    combo(br1, { { "6S (22.2 V)", 6 }, { "4S (14.8 V)", 4 } }, sim.cells or 6, function(v) sim.cells = v end, 160)
    slider(root, "Capacity (mAh)", 650, 2200, 0, sim.battery, function(v) sim.battery = math.floor(v / 50 + 0.5) * 50 end)
    local br2 = row(root)
    rowLabel(br2, "Charge at takeoff", 140)
    combo(br2, { { "Full (4.20 V/cell)", "full" }, { "Rested (4.10 V/cell)", "4.10" }, { "Storage (3.85 V/cell)", "storage" } },
        sim.charge or "full", function(v) sim.charge = v end, 200)
    local br3 = row(root)
    rowLabel(br3, "Pack condition", 140)
    combo(br3, { { "New", "new" }, { "Used (40% more sag)", "used" }, { "Tired / puffy (2x sag)", "tired" } },
        sim.packHealth or "new", function(v) sim.packHealth = v end, 220)
    slider(root, "Air / pack temperature (C)", -10, 40, 0, sim.ambient or 20, function(v) sim.ambient = math.floor(v + 0.5) end)
    note(root, "Cold packs sag much more. Packs warm up as you fly. Heavier packs change the weight and inertia. Past the rated capacity the voltage collapses.")
    slider(root, "vbat_sag_compensation (%)", 0, 150, 0, misc.vbat_sag_compensation or 0, function(v) misc.vbat_sag_compensation = math.floor(v + 0.5) end)
    slider(root, "Low battery warning (V/cell)", 3.0, 3.9, 2, (misc.vbat_warning_cell_voltage or 350) / 100, function(v) misc.vbat_warning_cell_voltage = math.floor(v * 100 + 0.5) end)
    slider(root, "Land now (V/cell)", 2.8, 3.6, 2, (misc.vbat_min_cell_voltage or 330) / 100, function(v) misc.vbat_min_cell_voltage = math.floor(v * 100 + 0.5) end)

    header(root, "Physics")
    local pv = row(root)
    rowLabel(pv, "Physics model", 140)
    combo(pv, {
        { "MayhemPhys 2.0", 2 },
        { "MayhemPhys 1.0", 1 },
    }, sim.phys or 2, function(v) sim.phys = v end, 330)
    slider(root, "Prop wash strength", 0, 2, 2, sim.propwash, function(v) sim.propwash = v end)
    slider(root, "Rotor drag / turn grip (1 = measured)", 0, 3, 2, sim.rotorDrag or 1, function(v) sim.rotorDrag = v end)

    local r1 = row(root)
    rowLabel(r1, "Physics rate", 140)
    combo(r1, { { "1000 Hz", 1000 }, { "2000 Hz (default)", 2000 }, { "4000 Hz", 4000 } }, sim.rate, function(v) sim.rate = v end, 230)
    local r2 = row(root)
    rowLabel(r2, "Collision checks", 140)
    combo(r2, { { "Every step (most precise)", 1 }, { "Every 2nd step (default)", 2 }, { "Every 4th step (fastest)", 4 } }, sim.collideEvery, function(v) sim.collideEvery = v end, 230)
    local r3 = row(root)
    rowLabel(r3, "World scale", 140)
    combo(r3, {
        { "1 unit = 0.75 inch (matches map size, default)", 0.01905 },
        { "1 unit = 1 inch (Source physics scale)", 0.0254 },
    }, sim.worldScale, function(v) sim.worldScale = v; FPV.Render.Invalidate() end, 300)

    header(root, "Crashes")
    slider(root, "Prop fragility (0 = indestructible)", 0, 3, 2, sim.damage or 1, function(v) sim.damage = v end)
    local cr = row(root)
    rowLabel(cr, "Crash recovery", 140)
    combo(cr, { { "OFF (Betaflight default)", "OFF" }, { "DISARM on hard hit", "DISARM" } }, misc.crash_recovery or "OFF",
        function(v) misc.crash_recovery = v end, 230)
    slider(root, "Crash flip expo", 0, 100, 0, misc.crashflip_expo or 35, function(v) misc.crashflip_expo = math.floor(v + 0.5) end)

    M.BuildAutotune(root)

    header(root, "PIDs (Betaflight scale)")
    local axes = { { "roll", "Roll" }, { "pitch", "Pitch" }, { "yaw", "Yaw" } }
    local terms = { { "P", 0, 250 }, { "I", 0, 250 }, { "D", 0, 250 }, { "F", 0, 1000 } }
    for _, ax in ipairs(axes) do
        local h = header(root, ax[2])
        h:DockMargin(14, 6, 6, 0)
        for ti, t in ipairs(terms) do
            slider(root, ax[2] .. " " .. t[1], t[2], t[3], 0, pids[ax[1]][ti], function(v)
                pids[ax[1]][ti] = math.floor(v + 0.5)
            end)
        end
    end
    header(root, "Filters / mixer")
    slider(root, "Motor idle (dshot_idle_value %)", 2, 10, 1, misc.idle * 100, function(v) misc.idle = v / 100 end)
    slider(root, "TPA rate (%)", 0, 100, 0, misc.tpa_rate, function(v) misc.tpa_rate = v end)
    slider(root, "TPA breakpoint", 1000, 2000, 0, misc.tpa_breakpoint, function(v) misc.tpa_breakpoint = v end)
    slider(root, "gyro_lpf1_dyn_min_hz", 50, 1000, 0, misc.gyro_lpf1_dyn_min_hz or 250, function(v) misc.gyro_lpf1_dyn_min_hz = math.floor(v + 0.5) end)
    slider(root, "gyro_lpf1_dyn_max_hz", 50, 1000, 0, misc.gyro_lpf1_dyn_max_hz or 500, function(v) misc.gyro_lpf1_dyn_max_hz = math.floor(v + 0.5) end)
    slider(root, "gyro_lpf2_static_hz", 50, 1000, 0, misc.gyro_lpf2_static_hz or 500, function(v) misc.gyro_lpf2_static_hz = math.floor(v + 0.5) end)
    slider(root, "dterm_lpf1_dyn_min_hz", 30, 300, 0, misc.dterm_lpf1_dyn_min_hz or 75, function(v) misc.dterm_lpf1_dyn_min_hz = math.floor(v + 0.5) end)
    slider(root, "dterm_lpf1_dyn_max_hz", 30, 300, 0, misc.dterm_lpf1_dyn_max_hz or 150, function(v) misc.dterm_lpf1_dyn_max_hz = math.floor(v + 0.5) end)
    slider(root, "dterm_lpf2_static_hz", 30, 300, 0, misc.dterm_lpf2_static_hz or 150, function(v) misc.dterm_lpf2_static_hz = math.floor(v + 0.5) end)
    local rf = row(root)
    rowLabel(rf, "rpm_filter_harmonics", 140)
    combo(rf, { { "3 (default)", 3 }, { "2", 2 }, { "1", 1 }, { "0 (RPM filter off)", 0 } }, misc.rpm_filter_harmonics or 3, function(v) misc.rpm_filter_harmonics = v end, 200)
    slider(root, "anti_gravity_gain", 0, 250, 0, misc.anti_gravity_gain or 80, function(v) misc.anti_gravity_gain = math.floor(v + 0.5) end)

    local br = row(root, 30)
    button(br, "Reset PIDs + filters to defaults", function()
        local dp = FPV.Presets.defaultPids()
        for _, ax in ipairs(axes) do
            for i = 1, 4 do pids[ax[1]][i] = dp[ax[1]][i] end
        end
        local dm = FPV.Presets.defaultFcMisc()
        for k, v in pairs(dm) do misc[k] = v end
        FPV.Config.Save()
        M.Reopen("Quad & Tuning")
    end, 240)
    return root
end

local function fmtTime(t)
    t = math.max(0, math.floor(t or 0))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function M.BuildMusic(parent)
    local Mu = FPV.Music
    local mc = cfg().music
    local root = scroll(parent)

    local np = vgui.Create("DPanel", root)
    np:Dock(TOP)
    np:SetTall(92)
    np:DockMargin(10, 6, 10, 4)
    local barX, barY, barW = 18, 62, 0
    np.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, UI.panel)
        local cur = Mu.current
        local title = cur and (cur.shown or cur.title) or (#Mu.tracks > 0 and "Not playing" or "No music yet")
        draw.SimpleText("NOW PLAYING", "MayhemHeader", 18, 14, Color(255, 150, 90))
        draw.SimpleText(title, "MayhemTitle", 18, 30, UI.text)
        local t, len = Mu.Times()
        barW = w - 36 - 90
        draw.RoundedBox(2, barX, barY + 8, barW, 4, UI.fieldHi)
        if t and len and len > 0 then
            draw.RoundedBox(2, barX, barY + 8, barW * math.Clamp(t / len, 0, 1), 4, UI.accent)
            draw.SimpleText(fmtTime(t) .. " / " .. fmtTime(len), "MayhemUISmall", w - 18, barY + 10, UI.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    np.OnMousePressed = function(self)
        local x, y = self:CursorPos()
        if y >= barY and y <= barY + 20 and x >= barX and x <= barX + barW then Mu.Seek((x - barX) / barW) end
    end

    local br = row(root, 30)
    button(br, "Previous", function() Mu.Prev() end, 100)
    local play = button(br, "Play", function() Mu.userStopped = false; Mu.Toggle() end, 100)
    button(br, "Next", function() Mu.userStopped = false; Mu.Next() end, 100)
    button(br, "Stop", function() Mu.userStopped = true; Mu.Stop() end, 80)
    br.Think = function()
        local txt = Mu.Playing() and "Pause" or "Play"
        if play:GetText() ~= txt then play:SetText(txt) end
    end

    header(root, "Player")
    check(root, "Music on", mc.enabled, function(v) mc.enabled = v end)
    slider(root, "Volume", 0, 1, 2, mc.volume or 0.5, function(v) Mu.SetVolume(v) end)
    check(root, "Shuffle", mc.shuffle, function(v) mc.shuffle = v; Mu.Scan() end)
    check(root, "Show the track name when a new track starts", mc.notify, function(v) mc.notify = v end)
    local wr = row(root)
    rowLabel(wr, "Play", 140)
    combo(wr, { { "Always", "always" }, { "Only while flying", "flying" }, { "Only on foot", "foot" } }, mc.when or "always",
        function(v) mc.when = v end, 220)

    header(root, "Your music")
    local fr = row(root, 30)
    local can = Mu.CanImport()
    local choose = button(fr, "Choose folder", function() Mu.ChooseFolder(); M.Reopen("Music") end, 170)
    local te = vgui.Create("DTextEntry", fr)
    te:Dock(FILL)
    te:DockMargin(0, 0, 8, 0)
    te:SetFont("MayhemUI")
    te:SetValue(mc.folder or "")
    if te.SetPlaceholderText then te:SetPlaceholderText("or paste a folder path, e.g. C:\\Users\\you\\Music\\FPV") end
    local imp = button(fr, "Import", function() Mu.ImportFolder(te:GetValue()) end, 90, RIGHT)
    local st = note(root, "")
    local function refresh()
        local msg
        local im = Mu.import
        if not can then
            msg = "Folder import needs the new gmcl_fpvjoy_win64.dll"
        elseif im and im.state == 1 then
            msg = string.format("Copying %d / %d", im.done, im.total)
        elseif im and im.state == 3 then
            msg = "Import failed: " .. tostring(im.message)
        else
            msg = ""
        end
        if st:GetText() ~= msg then st:SetText(msg) end
        local show = msg ~= ""
        if st:IsVisible() ~= show then st:SetVisible(show); root:InvalidateLayout() end
    end
    refresh()
    fr.Think = refresh
    choose:SetEnabled(can)
    imp:SetEnabled(can)
    local cr = row(root, 30)
    button(cr, "Rescan", function() Mu.Scan(); M.Reopen("Music") end, 100)
    local clr = button(cr, "Remove imported music", function()
        SK.Confirm("Remove music", "Delete the copies in garrysmod/sound/mayhem_music/user? Your original folder is not touched.", "Remove", function()
            Mu.ClearImported()
            M.Reopen("Music")
        end)
    end, 210)
    clr:SetEnabled(can)

    header(root, "Playlist")
    if #Mu.tracks == 0 then note(root, "Empty. Choose a folder above, or drop music into garrysmod/sound/mayhem_music/ and press Rescan.") end
    for i, tr in ipairs(Mu.tracks) do
        local r = vgui.Create("DButton", root)
        r:SetText("")
        r:Dock(TOP)
        r:SetTall(28)
        r:DockMargin(10, 1, 10, 1)
        r.Paint = function(self, w, h)
            local on = Mu.current == tr
            local hv = SK.ease(self, "mHov", self:IsHovered())
            if on or hv > 0.01 then draw.RoundedBox(5, 0, 0, w, h, on and Color(255, 122, 40, 40) or Color(255, 255, 255, 12 * hv)) end
            draw.SimpleText(string.format("%2d", i), "MayhemUISmall", 12, h / 2, on and UI.accent or UI.faint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tr.shown or tr.title, "MayhemUI", 40, h / 2, on and UI.white or UI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        r.DoClick = function() Mu.userStopped = false; Mu.PlayTrack(i) end
    end
    return root
end

function M.OnMusicChanged()
    if IsValid(M.frame) and IsValid(M.sheet) and IsValid(M.sheet:GetActiveTab()) and M.sheet:GetActiveTab():GetText() == "Music" then
        M.Reopen("Music")
    end
end

function M.BuildAbout(parent)
    local root = scroll(parent)
    local logo = Material("mayhem_fpv/logo.png", "smooth")
    local top = vgui.Create("DPanel", root)
    top:Dock(TOP)
    top:SetTall(150)
    top.Paint = function(_, w, h)
        if logo and not logo:IsError() then
            surface.SetDrawColor(255, 255, 255)
            surface.SetMaterial(logo)
            surface.DrawTexturedRect(math.floor(w / 2 - 144), 8, 288, 128)
        else
            draw.SimpleText("MAYHEM FPV", "MayhemBig", w / 2, 60, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local v = vgui.Create("DLabel", root)
    v:SetText("v" .. FPV.Version .. "  ·  open beta")
    v:SetFont("MayhemUI")
    v:SetTextColor(UI.dim)
    v:SetContentAlignment(5)
    v:SetTall(22)
    v:Dock(TOP)

    header(root, "Credits")
    local function credit(name, role)
        local r = vgui.Create("DPanel", root)
        r:Dock(TOP)
        r:SetTall(46)
        r:DockMargin(10, 4, 10, 4)
        r.Paint = function(self, w, h)
            local hv = SK.ease(self, "mHov", self:IsHovered())
            draw.RoundedBox(8, 0, 0, w, h, SK.mix(UI.panel, UI.field, hv))
            draw.RoundedBox(1, 0, 10, 3, h - 20, UI.accent)
            draw.SimpleText(name, "MayhemUIBold", 18, h / 2 - 8, UI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(role, "MayhemUISmall", 18, h / 2 + 9, UI.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    credit("MityaFPV", "Code, design, menu, MayhemPhys, models")
    credit("Claude (Anthropic)", "Code helper, troubleshooting, fpvjoy module, radio controller, rates and Betaflight firmware connection")

    header(root, "Thanks")
    note(root, "Open-source Betaflight firmware")

    header(root, "Factory reset")
    note(root, "Every setting back to first launch: radio mapping and calibration, rates, PIDs, video, OSD layout, quad and game settings.")
    local fr = row(root, 30)
    button(fr, "Factory reset...", function()
        SK.Confirm("Factory reset", "Reset every Mayhem FPV setting to its default? Your radio will need calibrating again.", "Reset everything", function()
            FPV.Config.FactoryReset()
            M.Reopen("About")
        end)
    end, 180)
    return root
end

local TABS = { "Radio", "Rates", "Video, Sound & OSD", "Quad & Tuning", "Music", "About" }

function M.Open(tab, keep)
    if IsValid(M.frame) then M.frame:Close() end
    local f = vgui.Create("DFrame")
    if keep then
        f:SetPos(keep.x, keep.y)
        f:SetSize(keep.w, keep.h)
    else
        f:SetSize(math.min(ScrW() - 40, 1000), math.min(ScrH() - 40, 760))
        f:Center()
    end
    f:SetSizable(true)
    f:SetMinWidth(640)
    f:SetMinHeight(420)
    f:MakePopup()
    SK.Window(f, "Mayhem FPV", "v" .. FPV.Version)
    if keep then f:SetAlpha(255); f:Stop() end
    f.OnClose = function() FPV.Config.Save() end
    local baseThink = f.Think
    f.Think = function(self)
        if baseThink then baseThink(self) end
        if not FPV.Flight.active then FPV.Input.Poll(FrameTime()) end
    end
    M.frame = f

    local sheet = vgui.Create("DPropertySheet", f)
    sheet:Dock(FILL)
    sheet:SetPadding(0)
    if sheet.SetFadeTime then sheet:SetFadeTime(0.12) end
    M.sheet = sheet
    M.scrolls = {}
    local builders = { M.BuildRadio, M.BuildRates, M.BuildCamera, M.BuildQuad, M.BuildMusic, M.BuildAbout }
    for i, name in ipairs(TABS) do
        local pnl = vgui.Create("DPanel", sheet)
        pnl:SetPaintBackground(false)
        pnl:DockPadding(0, 6, 0, 0)
        M.lastScroll = nil
        local root = builders[i](pnl)
        M.plain, M.noNotes = false, false
        M.scrolls[name] = M.lastScroll
        local keys = FPV.Config.SECTIONS[name]
        if keys and root then
            header(root, "Reset")
            local rr = row(root, 30)
            button(rr, "Reset " .. name .. " to defaults...", function()
                local extra = name == "Radio" and " The radio will need calibrating again." or ""
                SK.Confirm("Reset " .. name, "Put every setting on this tab back to its default?" .. extra, "Reset tab", function()
                    FPV.Config.ResetSections(keys)
                    M.Reopen(name)
                end)
            end, 340)
        end
        local s = sheet:AddSheet(name, pnl)
        if s and s.Tab and s.Tab.SetFont then s.Tab:SetFont("MayhemUIBold") end
        if tab == name then sheet:SetActiveTab(s.Tab) end
    end
end

function M.Reopen(tab)
    local active, keep, y = tab, nil, nil
    local f = M.frame
    if IsValid(f) then
        local x, yy = f:GetPos()
        keep = { x = x, y = yy, w = f:GetWide(), h = f:GetTall() }
        if not active and IsValid(M.sheet) and IsValid(M.sheet:GetActiveTab()) then active = M.sheet:GetActiveTab():GetText() end
        local sp = M.scrolls and M.scrolls[active]
        local vb = sp and SK.child(sp, "VBar")
        if vb and (tab == nil or tab == active) then y = vb:GetScroll() end
    end
    M.Open(active or "Radio", keep)
    if y then
        timer.Simple(0, function()
            local sp = M.scrolls and M.scrolls[active]
            local vb = sp and SK.child(sp, "VBar")
            if vb then vb:SetScroll(y) end
        end)
    end
end

concommand.Add("fpv_menu", function() M.Open() end)
concommand.Add("mayhem_menu", function() M.Open() end)
