local M = dofile("gmod_mock.lua")
local fails = 0
local function check(name, ok, msg)
    if not ok then fails = fails + 1 end
    print(string.format("[%s] %-40s %s", ok and "PASS" or "FAIL", name, msg or ""))
end
FPV = { Version = "0.4.0", Flight = { active = false } }
local oldView = function() return { origin = Vector(1, 2, 3) } end
hook.Add("CalcView", "fpv_drone_view", oldView)
hook.Add("PreRender", "fpv_drone_frame", function() end)
hook.Add("Think", "fpv_detect_x", function() end)
hook.Add("CalcView", "SomeOtherAddon", function() end)
local ok, err = pcall(M.loadGamemode)
check("gamemode loads next to the old addon", ok, tostring(err))
check("old hooks removed", M.hooks.CalcView.fpv_drone_view == nil and M.hooks.PreRender.fpv_drone_frame == nil and M.hooks.Think.fpv_detect_x == nil, "")
check("other addons untouched", M.hooks.CalcView.SomeOtherAddon ~= nil, "")
check("ours present", M.hooks.CalcView.mayhem_view ~= nil and M.hooks.PreRender.mayhem_frame ~= nil, "")
check("flagged + console warning", MayhemFPV.Legacy == true and (M.msgc or ""):find("fpv_drone") ~= nil, "")
check("old global left alone", FPV.Version == "0.4.0" and MayhemFPV ~= FPV, "")
local hp = pcall(function() GM:HUDPaint() end)
check("HUD warning draws", hp, "")
print(fails == 0 and "ALL LEGACY TESTS PASSED" or (fails .. " FAILURE(S)"))
