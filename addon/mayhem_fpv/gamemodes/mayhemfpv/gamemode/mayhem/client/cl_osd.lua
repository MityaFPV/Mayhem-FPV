local FPV = MayhemFPV

local O = {}
FPV.OSD = O

local floor, min, max, abs, sqrt, deg, asin, atan2, tan, rad = math.floor, math.min, math.max, math.abs, math.sqrt,
    math.deg, math.asin, math.atan2, math.tan, math.rad
local FONT = FPV.OSDFont
local I = FONT.icon
local COLS = 30

local C = { x = 0, y = 0, cw = 10, ch = 18, rows = 16 }
local fontMat
local rec = nil

function O.Rows()
    return (FPV.Config.data.osd.video == "NTSC") and 13 or 16
end

function O.SetCanvas(x, y, w, h, rows)
    C.rows = rows or O.Rows()
    C.x, C.y, C.cw, C.ch = x, y, w / COLS, h / C.rows
end

function O.ScreenCanvas()
    local h = ScrH() * 0.90
    local w = h * 4 / 3
    if w > ScrW() then w = ScrW(); h = w * 3 / 4 end
    O.SetCanvas((ScrW() - w) * 0.5, (ScrH() - h) * 0.5, w, h)
end

local function bindFont()
    if not fontMat then fontMat = Material("mayhem_fpv/osd_font.png", "noclamp") end
    surface.SetMaterial(fontMat)
    surface.SetDrawColor(255, 255, 255, 255)
end

local AW, AH, GW, GH, CWc, CHc = FONT.atlasW, FONT.atlasH, FONT.glyphW, FONT.glyphH, FONT.cellW, FONT.cellH
local function glyph(code, col, row)
    if rec then
        if col < rec[1] then rec[1] = col end
        if row < rec[2] then rec[2] = row end
        if col > rec[3] then rec[3] = col end
        if row > rec[4] then rec[4] = row end
    end
    if col < 0 or col >= COLS or row < 0 or row >= C.rows then return end
    local gx, gy = code % 16, floor(code / 16)
    surface.DrawTexturedRectUV(C.x + col * C.cw, C.y + row * C.ch, C.cw + 0.5, C.ch + 0.5,
        gx * CWc / AW, gy * CHc / AH, (gx * CWc + GW) / AW, (gy * CHc + GH) / AH)
end
O.glyph = glyph

local function txt(col, row, s)
    for i = 1, #s do
        local b = string.byte(s, i)
        if b >= 97 and b <= 122 then b = b - 32 end
        if b ~= 32 and b < 127 then glyph(b, col + i - 1, row) end
    end
    return col + #s
end
local function ic(name, col, row) glyph(I[name], col, row) return col + 1 end

local function glyphAt(code, colf, rowf)
    if rec then
        local c, r = floor(colf + 0.5), floor(rowf + 0.5)
        if c < rec[1] then rec[1] = c end
        if r < rec[2] then rec[2] = r end
        if c > rec[3] then rec[3] = c end
        if r > rec[4] then rec[4] = r end
    end
    local gx, gy = code % 16, floor(code / 16)
    surface.DrawTexturedRectUV(floor(C.x + colf * C.cw + 0.5), floor(C.y + rowf * C.ch + 0.5), C.cw + 0.5, C.ch + 0.5,
        gx * CWc / AW, gy * CHc / AH, (gx * CWc + GW) / AW, (gy * CHc + GH) / AH)
end

local function fmtTime(t)
    t = max(0, floor(t))
    return string.format("%02d:%02d", floor(t / 60), t % 60)
end

local function blinkOn() return (RealTime() * 2.5) % 1 < 0.6 end

local E = {}
O.ELEMENTS = E
local function el(id, label, x, y, on, draw) E[#E + 1] = { id = id, label = label, x = x, y = y, on = on, draw = draw } end

el("link_quality", "Link quality", 1, 1, true, function(c, x, y)
    ic("LQ", x, y)
    txt(x + 1, y, string.format("%3d", floor(c.lq + 0.5)))
end)
el("rssi_dbm", "RSSI dBm", 1, 2, false, function(c, x, y)
    ic("RSSI", x, y)
    local nx = txt(x + 1, y, string.format("%4d", floor(c.rssiDbm + 0.5)))
    ic("DBM", nx, y)
end)
el("craft_name", "Craft name", 11, 1, true, function(c, x, y)
    txt(x, y, string.sub(string.upper(c.craftName or ""), 1, 15))
end)
el("flymode", "Flight mode", 25, 1, true, function(c, x, y)
    if c.failsafe then
        if blinkOn() then txt(x, y, "!FS!") end
    else
        txt(x, y, c.airmode and "AIR" or "ACRO")
    end
end)
el("vtx_channel", "VTX channel", 23, 2, false, function(c, x, y)
    txt(x, y, c.vtx or "R:1:600")
end)
el("crosshairs", "Crosshairs", 13, 7, true, function(c, x, y)
    local cx, cy = COLS / 2 - 1.5, C.rows / 2 - 0.5
    glyphAt(I.CROSS_L, cx, cy); glyphAt(I.CROSS_C, cx + 1, cy); glyphAt(I.CROSS_R, cx + 2, cy)
end)
el("artificial_horizon", "Artificial horizon", 14, 7, false, function(c, x, y)
    local slope = tan(rad(max(-60, min(60, c.roll)))) * 9 * C.cw / C.ch
    local p = max(-20, min(20, c.pitch)) * 2
    for i = -4, 4 do
        local sub = floor(40 + p - i * slope + 0.5)
        if sub >= 0 and sub <= 80 then glyph(I["AH" .. (sub % 9)], x + i, y - 4 + floor(sub / 9)) end
    end
    if rec then glyph(I.AH4, x - 4, y - 4); glyph(I.AH4, x + 4, y + 4) end
end)
el("horizon_sidebars", "Horizon sidebars", 14, 7, false, function(c, x, y)
    for r = -3, 3 do
        if r == 0 then
            ic("AH_LEFT", x - 7, y); ic("AH_RIGHT", x + 7, y)
        else
            ic("AH_DECOR", x - 7, y + r); ic("AH_DECOR", x + 7, y + r)
        end
    end
end)
el("altitude", "Altitude", 23, 4, false, function(c, x, y)
    ic("ALT", x, y)
    local nx = txt(x + 1, y, string.format("%5.1f", c.alt))
    ic("METER", nx, y)
end)
el("gps_speed", "Speed", 1, 4, false, function(c, x, y)
    ic("SPEED", x, y)
    local nx = txt(x + 1, y, string.format("%3d", floor(c.speed + 0.5)))
    ic("KPH", nx, y)
end)
el("g_force", "G-force", 1, 5, false, function(c, x, y)
    local nx = txt(x, y, string.format("%3.1f", c.gforce))
    ic("GFORCE", nx, y)
end)
el("disarmed", "Disarmed", 11, 5, true, function(c, x, y)
    if not c.armed then txt(x, y, "DISARMED")
    elseif c.showArmed then txt(x + 1, y, "ARMED") end
    if rec then rec[3] = max(rec[3], x + 7) end
end)
el("warnings", "Warnings", 9, 10, true, function(c, x, y)
    local w = c.warning
    if w and (not c.warningBlink or blinkOn()) then
        txt(x + 6 - floor(#w / 2), y, w)
    end
    if rec then rec[1] = min(rec[1], x); rec[2] = min(rec[2], y); rec[3] = max(rec[3], x + 11); rec[4] = max(rec[4], y) end
end)
el("stick_overlay_left", "Stick overlay left", 2, 6, false, function(c, x, y)
    O.StickOverlay(x, y, c.sticks.lx, c.sticks.ly)
end)
el("stick_overlay_right", "Stick overlay right", 21, 6, false, function(c, x, y)
    O.StickOverlay(x, y, c.sticks.rx, c.sticks.ry)
end)
el("main_batt_usage", "Battery usage bar", 10, 12, false, function(c, x, y)
    local rem = max(0, 1 - c.mah / max(1, c.capacity))
    ic("PB_START", x, y)
    for i = 1, 8 do ic((i - 0.5) / 8 <= rem and "PB_FULL" or "PB_EMPTY", x + i, y) end
    ic("PB_END", x + 9, y)
end)
el("avg_cell_voltage", "Average cell voltage", 1, 13, true, function(c, x, y)
    ic("BATT" .. c.battLevel, x, y)
    local nx = txt(x + 1, y, string.format("%4.2f", c.cellV))
    ic("VOLT", nx, y)
end)
el("throttle_pos", "Throttle", 13, 13, true, function(c, x, y)
    ic("THR", x, y)
    txt(x + 1, y, string.format("%3d", floor(c.thr * 100 + 0.5)))
end)
el("flytime", "Fly time", 23, 13, true, function(c, x, y)
    ic("FLY", x, y)
    txt(x + 1, y, fmtTime(c.flyTime))
end)
el("on_time", "On time", 23, 12, false, function(c, x, y)
    ic("ON", x, y)
    txt(x + 1, y, fmtTime(c.onTime))
end)
el("main_batt_voltage", "Battery voltage", 1, 14, true, function(c, x, y)
    ic("BATT" .. c.battLevel, x, y)
    local nx = txt(x + 1, y, string.format("%4.1f", c.vbat))
    ic("VOLT", nx, y)
end)
el("current_draw", "Current draw", 9, 14, true, function(c, x, y)
    local nx = txt(x, y, string.format("%5.1f", max(0, c.ibat)))
    ic("AMP", nx, y)
end)
el("power", "Power", 9, 13, false, function(c, x, y)
    local nx = txt(x, y, string.format("%4d", floor(max(0, c.power) + 0.5)))
    ic("WATT", nx, y)
end)
el("mah_drawn", "mAh drawn", 22, 14, true, function(c, x, y)
    local nx = txt(x, y, string.format("%5d", floor(c.mah + 0.5)))
    ic("MAH", nx, y)
end)

local BYID = {}
for i, e in ipairs(E) do BYID[e.id] = e; e.order = i end

function O.StickOverlay(x, y, sx, sy)
    for r = 0, 4 do if r ~= 2 then ic("STICK_VERT", x + 3, y + r) end end
    for k = 0, 6 do if k ~= 3 then ic("STICK_HORIZ", x + k, y + 2) end end
    ic("STICK_CENTER", x + 3, y + 2)
    local cx = x + floor((max(-1, min(1, sx)) + 1) * 3 + 0.5)
    local pos = floor((1 - max(-1, min(1, sy))) / 2 * 14 + 0.5)
    local r, sub = floor(pos / 3), pos % 3
    ic(sub == 0 and "STICK_HIGH" or (sub == 1 and "STICK_MID" or "STICK_LOW"), cx, y + r)
end

function O.Layout()
    local cfg = FPV.Config.data.osd
    cfg.layout = cfg.layout or {}
    local L = cfg.layout
    for _, e in ipairs(E) do
        local p = L[e.id]
        if type(p) ~= "table" then
            L[e.id] = { x = e.x, y = e.y, on = e.on }
        else
            if p.x == nil then p.x = e.x end
            if p.y == nil then p.y = e.y end
            if p.on == nil then p.on = e.on end
        end
    end
    return L
end

function O.ResetLayout()
    FPV.Config.data.osd.layout = {}
    O.Layout()
    FPV.Config.Save()
end

local function gridY(y)
    if C.rows == 13 and y >= 8 then return y - 3 end
    return y
end
O.gridY = gridY

local S = { vFilt = nil, armedShowUntil = 0, stats = nil, wasArmed = false, lowT = 0, landT = 0 }
local ctx = { sticks = {} }

local function battLevel(cellV, minCell)
    return max(0, min(6, floor((cellV - minCell) / (4.2 - minCell) * 6 + 0.5)))
end

function O.Update(F)
    local craft = F.craft
    local fc, sim = craft.fc, craft.sim
    local cfg = FPV.Config.data
    local misc = cfg.misc
    local dt = FrameTime()
    local cells = F.quad.cells
    local now = RealTime()
    local vDisp = craft.vDisplay or sim.vbat
    local cellV = vDisp / cells
    local warnCell = (misc.vbat_warning_cell_voltage or 350) / 100
    local minCell = (misc.vbat_min_cell_voltage or 330) / 100
    local fullCell = (misc.vbat_full_cell_voltage or 410) / 100

    local m11, m12, m13, m21, m22, m23, m31, m32, m33 = FPV.Sim.quatToMat(sim.qw, sim.qx, sim.qy, sim.qz)
    local spd = sqrt(sim.vx * sim.vx + sim.vy * sim.vy + sim.vz * sim.vz)
    local gf = sqrt(sim.ax * sim.ax + sim.ay * sim.ay + sim.az * sim.az) / 9.81

    if cellV < warnCell then S.lowT = S.lowT + dt else S.lowT = 0 end
    if cellV < minCell then S.landT = S.landT + dt else S.landT = 0 end

    if fc.armed and not S.wasArmed then
        S.armedShowUntil = now + 1.5
        S.stats = nil
        S.armFly = craft.flyTime
        S.maxCurrent, S.minV, S.maxAlt, S.maxSpd, S.maxG = 0, vDisp, 0, 0, 1
        S.minLq, S.minRssi, S.maxTemp = 100, 0, sim.packT or 20
        S.minRssi = FPV.Video.rxDbm or -50
    end
    if fc.armed then
        S.maxCurrent = max(S.maxCurrent, sim.ibat)
        S.minV = min(S.minV, vDisp)
        S.maxAlt = max(S.maxAlt, sim.pz - (F.launchZ or 0))
        S.maxSpd = max(S.maxSpd, spd * 3.6)
        S.maxG = max(S.maxG, gf)
        S.minLq = min(S.minLq, FPV.Video.lq or 100)
        S.minRssi = min(S.minRssi, FPV.Video.rxDbm or -50)
        S.maxTemp = max(S.maxTemp, sim.packT or 20)
    end
    if not fc.armed and S.wasArmed and (craft.flyTime - (S.armFly or 0)) > 2 then
        S.stats = {
            { "FLY TIME", fmtTime(craft.flyTime) },
            { "MAX ALTITUDE", string.format("%.1fM", S.maxAlt) },
            { "MAX SPEED", string.format("%dKM/H", floor(S.maxSpd + 0.5)) },
            { "MIN BATTERY", string.format("%.2fV", S.minV) },
            { "END BATTERY", string.format("%.2fV", vDisp) },
            { "MIN LQ", string.format("%d", floor(S.minLq)) },
            { "MIN RSSI DBM", string.format("%d", floor(S.minRssi + 0.5)) },
            { "MAX CURRENT", string.format("%dA", floor(S.maxCurrent + 0.5)) },
            { "USED MAH", string.format("%d", floor(sim.mah + 0.5)) },
            { "MAX G-FORCE", string.format("%.1fG", S.maxG) },
            { "MAX BATT TEMP", string.format("%dC", floor(S.maxTemp + 0.5)) },
        }
        S.statsAt = now
    end
    S.wasArmed = fc.armed
    local st = FPV.Input.state
    if S.stats and (now - (S.statsAt or 0) > 1) and (abs(st.roll) > 0.7 or abs(st.pitch) > 0.7 or fc.armed) then
        S.stats = nil
    end

    local warn, blink = nil, true
    local lq = FPV.Video.lq or 100
    if F.inWater then warn = "WATER"
    elseif F.failsafe or (not st.ok and st.backend ~= "keyboard") then warn = "RXLOSS"
    elseif fc.flip then warn = "CRASH FLIP"; blink = false
    elseif not fc.armed and fc.armBlock then warn = fc.armBlock
    elseif not fc.armed and st.thr > 0.05 then warn = "THROTTLE"
    elseif fc.armed and S.landT > 2 then warn = "LAND NOW"
    elseif fc.armed and S.lowT > 2 then warn = "LOW BATTERY"
    elseif lq < 30 then warn = "LQ LOW"
    elseif not fc.armed and cellV < fullCell then warn = "BATT < FULL"; blink = false
    end

    local mode = cfg.osd.stickMode or 2
    local thrY = st.thr * 2 - 1
    local sk = ctx.sticks
    if mode == 1 then
        sk.lx, sk.ly, sk.rx, sk.ry = st.yaw, st.pitch, st.roll, thrY
    else
        sk.lx, sk.ly, sk.rx, sk.ry = st.yaw, thrY, st.roll, st.pitch
    end

    ctx.armed, ctx.airmode, ctx.failsafe = fc.armed, true, F.failsafe
    ctx.showArmed = fc.armed and now < S.armedShowUntil
    ctx.warning, ctx.warningBlink = warn, blink
    ctx.lq, ctx.rssiDbm = lq, FPV.Video.rxDbm or -50
    ctx.craftName = cfg.osd.craftName or F.quad.craftName
    ctx.cellV, ctx.vbat, ctx.battLevel = cellV, vDisp, battLevel(cellV, minCell)
    ctx.ibat, ctx.mah, ctx.capacity, ctx.power = sim.ibat, sim.mah, F.quad.capacity, vDisp * sim.ibat
    ctx.thr = fc.throttle
    ctx.flyTime, ctx.onTime = craft.flyTime, craft.onTime
    ctx.alt, ctx.speed, ctx.gforce = sim.pz - (F.launchZ or 0), spd * 3.6, gf
    ctx.pitch = deg(asin(max(-1, min(1, m31))))
    ctx.roll = deg(atan2(m32, m33))
    ctx.vtx = string.format("R:1:%d", cfg.video.vtxPower or 600)
    ctx.stats = S.stats
    ctx.turtle, ctx.armSwitch = st.turtle, st.arm
    O.ctx = ctx
end

function O.Reset()
    S.vFilt = nil
    S.stats = nil
    S.wasArmed = false
    S.lowT, S.landT = 0, 0
end

function O.SampleContext()
    return {
        armed = true, airmode = true, failsafe = false, showArmed = false,
        warning = "LOW BATTERY", warningBlink = false,
        lq = 100, rssiDbm = -64, craftName = FPV.Config.data.osd.craftName or "MAYHEM X5",
        cellV = 3.92, vbat = 23.5, battLevel = 4, ibat = 23.4, mah = 412, capacity = 1400, power = 550,
        thr = 0.34, flyTime = 83, onTime = 140, alt = 12.4, speed = 87, gforce = 1.8,
        pitch = 6, roll = -12, vtx = "R:1:600",
        sticks = { lx = -0.2, ly = -0.3, rx = 0.45, ry = 0.6 },
    }
end

local function drawStats(stats)
    local top = C.rows == 13 and 1 or 2
    txt(9, top, "--- STATS ---")
    for i, line in ipairs(stats) do
        local r = top + 1 + i
        if r < C.rows then
            txt(3, r, line[1])
            txt(20, r, line[2])
        end
    end
end

function O.Render(c, boxes, showAll)
    bindFont()
    local L = O.Layout()
    if c.stats and not boxes and FPV.Config.data.osd.stats ~= false then
        drawStats(c.stats)
        return
    end
    for _, e in ipairs(E) do
        local p = L[e.id]
        if p.on or showAll then
            local x, y = p.x, gridY(p.y)
            if boxes then rec = { 99, 99, -99, -99 } end
            e.draw(c, x, y)
            if boxes then
                bindFont()
                boxes[#boxes + 1] = { id = e.id, x0 = rec[1], y0 = rec[2], x1 = rec[3], y1 = rec[4], on = p.on }
                rec = nil
            end
        end
    end
end

function O.Draw(F)
    local cfg = FPV.Config.data.osd
    if not cfg.enabled or not O.ctx then return end
    O.ScreenCanvas()
    O.Render(O.ctx)
end

local function gimbal(x, y, s, sx, sy)
    local a = 70
    surface.SetDrawColor(255, 255, 255, a)
    surface.DrawOutlinedRect(x, y, s, s, 1)
    surface.SetDrawColor(255, 255, 255, a * 0.5)
    surface.DrawLine(x + s / 2, y + 3, x + s / 2, y + s - 3)
    surface.DrawLine(x + 3, y + s / 2, x + s - 3, y + s / 2)
    local px = x + s / 2 + max(-1, min(1, sx)) * (s / 2 - 4)
    local py = y + s / 2 - max(-1, min(1, sy)) * (s / 2 - 4)
    local d = math.max(4, math.floor(s * 0.07))
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(px - d / 2 - 1, py - d / 2 - 1, d + 2, d + 2)
    surface.SetDrawColor(255, 255, 255, 230)
    surface.DrawRect(px - d / 2, py - d / 2, d, d)
end

function O.DrawStickHUD(F)
    local cfg = FPV.Config.data.osd
    if not cfg.stickHUD or not O.ctx then return end
    local sk = O.ctx.sticks
    local W, H = ScrW(), ScrH()
    local s = math.floor(H * 0.075)
    local side = (W - H * 0.9 * 4 / 3) / 2
    local y = H - s - math.floor(H * 0.06)
    local lx, rx
    if side >= s + 16 then
        lx = math.floor((side - s) / 2)
        rx = math.floor(W - side + (side - s) / 2)
    else
        lx, rx = math.floor(W / 2 - s - 6), math.floor(W / 2 + 6)
        y = math.floor(H * 0.02)
    end
    gimbal(lx, y, s, sk.lx, sk.ly)
    gimbal(rx, y, s, sk.rx, sk.ry)
end

function O.DrawMini(F)
    local fc, sim = F.craft.fc, F.craft.sim
    local s = string.format("%s  %.1fV  THR %d%%  [%s]   E: exit   R: reset   RMB: camera",
        fc.armed and "ARMED" or "DISARMED", F.craft.vDisplay or sim.vbat, math.floor(fc.throttle * 100), string.upper(F.camMode))
    draw.SimpleTextOutlined(s, "DermaDefaultBold", ScrW() * 0.5, ScrH() - 14, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0))
end
