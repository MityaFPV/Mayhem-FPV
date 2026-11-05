local FPV = MayhemFPV

local G = {}
FPV.Guard = G

G.EVENTS = {
    "CalcView", "CalcViewModelView", "ShouldDrawLocalPlayer", "RenderScene", "PreRender",
    "PreDrawViewModel", "PostDrawViewModel", "PreDrawPlayerHands", "PostDrawPlayerHands",
    "CreateMove", "InputMouseApply", "AdjustMouseSensitivity", "PlayerBindPress",
    "PlayerButtonDown", "PlayerButtonUp", "StartCommand",
    "HUDShouldDraw", "HUDPaint", "HUDPaintBackground", "PreDrawHUD", "PostDrawHUD",
    "HUDDrawTargetID", "HUDDrawPickupHistory", "DrawDeathNotice", "HUDAmmoPickedUp", "HUDItemPickedUp", "HUDWeaponPickedUp",
    "RenderScreenspaceEffects", "PreDrawHalos", "GetMotionBlurValues", "NeedsDepthPass", "PostProcessPermitted",
    "PreDrawEffects", "PostDrawEffects",
}

local OURS = "mayhem_"
local parked = nil
local lastSweep = 0

local function ours(id)
    return isstring(id) and string.sub(id, 1, #OURS) == OURS
end

local function sweep()
    local tab = hook.GetTable()
    local found = {}
    for _, ev in ipairs(G.EVENTS) do
        local t = tab[ev]
        if t then
            for id, fn in pairs(t) do
                if not ours(id) then found[#found + 1] = { ev, id, fn } end
            end
        end
    end
    for _, h in ipairs(found) do
        hook.Remove(h[1], h[2])
        parked[#parked + 1] = h
    end
    return #found
end

function G.Active() return parked ~= nil end
function G.Count() return parked and #parked or 0 end

function G.Engage()
    local cfg = FPV.Config and FPV.Config.data
    if cfg and cfg.game and cfg.game.shield == false then return end
    if parked then return end
    parked = {}
    sweep()
    lastSweep = RealTime()
end

function G.Release()
    if not parked then return end
    local list = parked
    parked = nil
    for i = #list, 1, -1 do
        local h = list[i]
        local ev, id, fn = h[1], h[2], h[3]
        if isstring(id) or IsValid(id) then
            local cur = hook.GetTable()[ev]
            if not (cur and cur[id]) then hook.Add(ev, id, fn) end
        end
    end
end

hook.Add("Think", "mayhem_guard", function()
    if not parked then return end
    local now = RealTime()
    if now - lastSweep < 1 then return end
    lastSweep = now
    sweep()
end)

concommand.Add("mayhem_shield_status", function()
    print(string.format("[Mayhem FPV] flight shield %s, %d foreign hooks parked", parked and "ON" or "off", G.Count()))
    if parked then
        for _, h in ipairs(parked) do print("  " .. h[1] .. "  " .. tostring(h[2])) end
    end
end)

return G
