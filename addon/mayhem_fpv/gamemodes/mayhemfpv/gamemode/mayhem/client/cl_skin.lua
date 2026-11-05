local FPV = MayhemFPV

local S = {}
FPV.Skin = S
S.NAME = "MayhemFPV"

local C = {
    bg = Color(16, 17, 21, 248),
    panel = Color(23, 25, 30),
    field = Color(32, 34, 41),
    fieldHi = Color(43, 46, 55),
    line = Color(255, 255, 255, 16),
    text = Color(234, 235, 240),
    dim = Color(146, 150, 162),
    faint = Color(86, 90, 100),
    accent = Color(255, 122, 40),
    accentSoft = Color(255, 122, 40, 44),
    white = Color(255, 255, 255),
}
S.C = C

surface.CreateFont("MayhemUI", { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("MayhemUIBold", { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("MayhemUISmall", { font = "Roboto", size = 13, weight = 400, extended = true })
surface.CreateFont("MayhemHeader", { font = "Roboto", size = 12, weight = 800, extended = true })
surface.CreateFont("MayhemTitle", { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("MayhemBig", { font = "Roboto", size = 30, weight = 800, extended = true })

local function mix(a, b, t)
    return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
end
S.mix = mix

local function ease(p, key, on, speed)
    local v = p[key]
    if type(v) ~= "number" then v = on and 1 or 0 end
    v = v + ((on and 1 or 0) - v) * math.min(1, FrameTime() * (speed or 14))
    p[key] = v
    return v
end
S.ease = ease

local function hovered(p) return p:IsHovered() or (p.Hovered == true) end

function S.child(p, k)
    local c = p[k]
    if c ~= nil and type(c) ~= "function" and IsValid(c) then return c end
end

local SKIN = table.Copy(derma.GetDefaultSkin() or {})
SKIN.PrintName = "Mayhem FPV"
SKIN.Author = "MityaFPV & Claude"

SKIN.Colours = table.Copy(SKIN.Colours or {})
local cl = SKIN.Colours
cl.Label = { Default = C.text, Bright = C.text, Dark = C.text, Highlight = C.accent }
cl.Button = { Normal = C.text, Hover = C.white, Down = C.white, Disabled = C.faint }
cl.Tab = {
    Active = { Normal = C.text, Hover = C.white, Down = C.white, Disabled = C.faint },
    Inactive = { Normal = C.dim, Hover = C.text, Down = C.text, Disabled = C.faint },
}
cl.Window = { TitleActive = C.text, TitleInactive = C.dim }

SKIN.colTextEntryText = C.text
SKIN.colTextEntryTextHighlight = Color(255, 122, 40, 120)
SKIN.colTextEntryTextCursor = C.white
SKIN.colTextEntryTextPlaceholder = C.faint

function SKIN:PaintPanel(panel, w, h)
    if not panel.m_bBackground then return end
    local bg = panel.m_bgColor
    draw.RoundedBox(6, 0, 0, w, h, istable(bg) and bg or C.panel)
end
function SKIN:PaintShadow() end

function SKIN:PaintFrame(panel, w, h)
    draw.RoundedBox(10, 0, 0, w, h, C.bg)
end

function SKIN:PaintButton(panel, w, h)
    if not panel.m_bBackground then return end
    local dis = panel.GetDisabled and panel:GetDisabled()
    local hv = ease(panel, "mHov", hovered(panel) and not dis)
    local col = mix(C.field, C.fieldHi, hv)
    if panel.Depressed or (panel.IsDown and panel:IsDown()) then col = mix(col, C.accent, 0.35) end
    if dis then col = mix(C.field, C.bg, 0.5) end
    draw.RoundedBox(5, 0, 0, w, h, col)
end

function SKIN:PaintWindowCloseButton(panel, w, h)
    local hv = ease(panel, "mHov", hovered(panel))
    if hv > 0.01 then draw.RoundedBox(5, 0, 0, w, h, Color(255, 255, 255, 18 * hv)) end
    local c = mix(C.dim, C.white, hv)
    surface.SetDrawColor(c)
    local m = math.floor(w * 0.34)
    for o = 0, 1 do
        surface.DrawLine(m + o, m, w - m + o, h - m)
        surface.DrawLine(w - m + o, m, m + o, h - m)
    end
end
function SKIN:PaintWindowMinimizeButton() end
function SKIN:PaintWindowMaximizeButton() end

function SKIN:PaintTextEntry(panel, w, h)
    if panel.m_bBackground ~= false then
        local focus = panel:HasFocus()
        local f = ease(panel, "mFocus", focus)
        draw.RoundedBox(5, 0, 0, w, h, mix(C.field, C.accent, 0.55 * f))
        draw.RoundedBox(5, 1, 1, w - 2, h - 2, mix(C.field, C.panel, f))
    end
    panel:DrawTextEntryText(panel:GetTextColor() or C.text, panel:GetHighlightColor() or SKIN.colTextEntryTextHighlight,
        panel:GetCursorColor() or C.white)
end
function SKIN:SchemeTextEntry(panel)
    panel:SetTextColor(C.text)
    panel:SetHighlightColor(SKIN.colTextEntryTextHighlight)
    panel:SetCursorColor(C.white)
end

function SKIN:PaintCheckBox(panel, w, h)
    local on = panel:GetChecked()
    local t = ease(panel, "mChk", on, 16)
    local hv = ease(panel, "mHov", hovered(panel))
    draw.RoundedBox(4, 0, 0, w, h, mix(mix(C.fieldHi, Color(64, 68, 80), hv), C.accent, t))
    if t < 0.98 then draw.RoundedBox(4, 2, 2, w - 4, h - 4, Color(C.field.r, C.field.g, C.field.b, 255 * (1 - t))) end
    if t > 0.02 then
        surface.SetDrawColor(255, 255, 255, 255 * t)
        local x, y = w * 0.24, h * 0.52
        for o = 0, 1 do
            surface.DrawLine(x, y + o, w * 0.43, h * 0.72 + o)
            surface.DrawLine(w * 0.43, h * 0.72 + o, w * 0.78, h * 0.3 + o)
        end
    end
end

function SKIN:PaintComboBox(panel, w, h)
    local dis = panel.GetDisabled and panel:GetDisabled()
    local open = panel.IsMenuOpen and panel:IsMenuOpen()
    local hv = ease(panel, "mHov", (hovered(panel) or open) and not dis)
    draw.RoundedBox(5, 0, 0, w, h, mix(C.field, C.fieldHi, hv))
end
function SKIN:PaintComboDownArrow(panel, w, h)
    local cb = panel.ComboBox
    local open = cb and cb.IsMenuOpen and cb:IsMenuOpen()
    surface.SetDrawColor(open and C.accent or C.dim)
    local cx, cy = math.floor(w / 2), math.floor(h / 2)
    for o = 0, 1 do
        surface.DrawLine(cx - 4, cy - 2 + o, cx, cy + 2 + o)
        surface.DrawLine(cx, cy + 2 + o, cx + 4, cy - 2 + o)
    end
end

function SKIN:PaintMenu(panel, w, h)
    draw.RoundedBox(6, 0, 0, w, h, Color(52, 55, 64))
    draw.RoundedBox(6, 1, 1, w - 2, h - 2, C.field)
end
function SKIN:PaintMenuSpacer(panel, w, h)
    surface.SetDrawColor(C.line)
    surface.DrawRect(6, 0, w - 12, h)
end
function SKIN:PaintMenuOption(panel, w, h)
    local hv = ease(panel, "mHov", panel.Hovered or panel.Highlight)
    if hv > 0.01 then draw.RoundedBox(4, 3, 1, w - 6, h - 2, Color(255, 122, 40, 60 * hv)) end
    if panel.m_bChecked then draw.RoundedBox(3, 7, h / 2 - 3, 6, 6, C.accent) end
end
function SKIN:PaintMenuRightArrow() end

function SKIN:PaintPropertySheet(panel, w, h)
    local tab = panel:GetActiveTab()
    local off = tab and (tab:GetTall() - 8) or 20
    surface.SetDrawColor(C.line)
    surface.DrawRect(0, off, w, 1)
end
function SKIN:PaintTab(panel, w, h)
    local active = panel:IsActive()
    local hv = ease(panel, "mHov", hovered(panel) and not active)
    local a = ease(panel, "mAct", active, 12)
    local barY = active and (h - 10) or (h - 2)
    if a > 0.01 then
        local bw = (w - 16) * a
        draw.RoundedBox(1, (w - bw) / 2, barY, bw, 2, C.accent)
    elseif hv > 0.01 then
        draw.RoundedBox(1, 8, barY, w - 16, 2, Color(255, 255, 255, 40 * hv))
    end
end

function SKIN:PaintNumSlider(panel, w, h)
    local y = math.floor(h / 2)
    local x = math.floor((panel:GetSlideX() or 0) * w)
    draw.RoundedBox(1, 0, y - 1, w, 3, C.fieldHi)
    draw.RoundedBox(1, 0, y - 1, x, 3, C.accent)
end
function SKIN:PaintSliderKnob(panel, w, h)
    local hv = ease(panel, "mHov", hovered(panel) or panel.Depressed)
    local cx, cy = math.floor(w / 2), math.floor(h / 2)
    local halo = 7
    if hv > 0.01 then draw.RoundedBox(halo, cx - halo, cy - halo, halo * 2, halo * 2, Color(255, 122, 40, 70 * hv)) end
    local r = 5
    draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, C.white)
end

function SKIN:PaintVScrollBar() end
function SKIN:PaintScrollBarGrip(panel, w, h)
    local hv = ease(panel, "mHov", hovered(panel) or panel.Depressed)
    local bw = math.floor(4 + 2 * hv)
    draw.RoundedBox(bw / 2, w - bw - 2, 0, bw, h, mix(Color(255, 255, 255, 40), Color(255, 255, 255, 110), hv))
end
function SKIN:PaintButtonUp() end
function SKIN:PaintButtonDown() end
function SKIN:PaintButtonLeft() end
function SKIN:PaintButtonRight() end

function SKIN:PaintProgress(panel, w, h)
    draw.RoundedBox(3, 0, 0, w, h, C.field)
    local f = math.Clamp(panel:GetFraction() or 0, 0, 1)
    local shown = type(panel.mShown) == "number" and panel.mShown or f
    panel.mShown = shown + (f - shown) * math.min(1, FrameTime() * 10)
    if panel.mShown > 0.002 then draw.RoundedBox(3, 0, 0, math.max(6, w * panel.mShown), h, C.accent) end
end

function SKIN:PaintTooltip(panel, w, h)
    draw.RoundedBox(5, 0, 0, w, h, C.fieldHi)
end

function SKIN:PaintCollapsibleCategory(panel, w, h)
    draw.RoundedBox(6, 0, 0, w, h, C.panel)
end
function SKIN:PaintCategoryList(panel, w, h) end

derma.DefineSkin(S.NAME, "Mayhem FPV: dark, flat, one accent", SKIN)
S.SKIN = SKIN

function S.Window(f, title, subtitle)
    f:SetSkin(S.NAME)
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:DockPadding(14, 50, 14, 12)
    f.Paint = function(s, w, h)
        draw.RoundedBox(10, 0, 0, w, h, C.bg)
        draw.SimpleText(title, "MayhemTitle", 18, 14, C.text)
        if subtitle then
            surface.SetFont("MayhemTitle")
            local tw = surface.GetTextSize(title)
            draw.SimpleText(subtitle, "MayhemUISmall", 18 + tw + 10, 20, C.faint)
        end
        surface.SetDrawColor(C.accent)
        surface.DrawRect(18, 40, 22, 2)
    end
    local cb = vgui.Create("DButton", f)
    cb:SetText("")
    cb:SetSize(30, 30)
    cb.Paint = function(s, w, h) SKIN.PaintWindowCloseButton(SKIN, s, w, h) end
    cb.DoClick = function() S.Close(f) end
    f.mClose = cb
    local pl = f.PerformLayout
    f.PerformLayout = function(s, w, h)
        if pl then pl(s, w, h) end
        if IsValid(cb) then cb:SetPos(w - 40, 10) end
    end
    f:SetAlpha(0)
    f:AlphaTo(255, 0.16, 0)
    return f
end

function S.Close(f)
    if not IsValid(f) or f.mClosing then return end
    f.mClosing = true
    f:AlphaTo(0, 0.12, 0, function()
        if IsValid(f) then f:Close() end
    end)
end

function S.Confirm(title, text, yesLabel, onYes)
    local f = vgui.Create("DFrame")
    f:SetSize(440, 190)
    f:Center()
    f:MakePopup()
    f:DoModal()
    S.Window(f, title)
    local l = vgui.Create("DLabel", f)
    l:SetText(text)
    l:SetFont("MayhemUI")
    l:SetTextColor(C.dim)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:Dock(TOP)
    l:DockMargin(4, 4, 4, 0)
    local r = vgui.Create("DPanel", f)
    r:SetPaintBackground(false)
    r:SetTall(32)
    r:Dock(BOTTOM)
    local yes = vgui.Create("DButton", r)
    yes:SetText(yesLabel or "OK")
    yes:SetFont("MayhemUIBold")
    yes:SetWide(150)
    yes:Dock(RIGHT)
    yes:SetTextColor(C.white)
    yes.Paint = function(self, w, h)
        local hv = S.ease(self, "mHov", self:IsHovered())
        draw.RoundedBox(5, 0, 0, w, h, S.mix(Color(214, 92, 22), C.accent, hv))
    end
    yes.DoClick = function()
        S.Close(f)
        if onYes then onYes() end
    end
    local no = vgui.Create("DButton", r)
    no:SetText("Cancel")
    no:SetFont("MayhemUI")
    no:SetWide(110)
    no:Dock(RIGHT)
    no:DockMargin(0, 0, 8, 0)
    no.DoClick = function() S.Close(f) end
    return f
end

return S
