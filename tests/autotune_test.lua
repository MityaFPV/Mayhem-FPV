local root = arg and arg[1]
if not root then
    local f = io.open("../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/sim.lua")
    root = f and "../../garrysmod/addons/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/" or "../addon/mayhem_fpv/gamemodes/mayhemfpv/gamemode/mayhem/core/"
    if f then f:close() end
end
local Rates = dofile(root .. "rates.lua"); local Presets = dofile(root .. "presets.lua")
local FC = dofile(root .. "fc.lua"); local Sim = dofile(root .. "sim.lua"); local Craft = dofile(root .. "craft.lua")
local Prop = dofile(root .. "prop.lua"); local Sensors = dofile(root .. "sensors.lua"); Sim.setProp(Prop)
local AT = dofile(root .. "autotune.lua")
local mods = { Rates = Rates, FC = FC, Sim = Sim, Sensors = Sensors, Craft = Craft }
local fails = 0
local function check(name, ok, msg)
    if not ok then fails = fails + 1 end
    print(string.format("[%s] %-40s %s", ok and "PASS" or "FAIL", name, msg or ""))
end
local function fmt(r) return string.format("track %.3f, overshoot %.0f%%, rise %.0f ms, bounce %.1f, punch %.1f, noise %.4f", r.track, r.overshoot * 100, r.rise * 1000, r.bounce, r.punch, r.noise) end

local function tune(start, goal)
    local spec = {
        mods = mods, makeQuad = function() local q = Presets.get("mayhem_x5"); q.phys = 2; return q end,
        rates = Rates.defaults(), misc = Presets.defaultFcMisc(), pids = start, hz = 2000, goal = goal,
    }
    local job = AT.new(spec)
    local t0 = os.clock()
    local slices = 0
    repeat
        local done, p, err = AT.step(job, 0.01)
        slices = slices + 1
        if err then print("ERROR", err) end
    until done
    return job, os.clock() - t0, slices
end

local bad = { roll = { 20, 40, 12, 0 }, pitch = { 20, 40, 12, 0 }, yaw = { 25, 40, 0, 0 } }
local job, secs, slices = tune(bad, "freestyle")
local r = job.result
check("autotune finishes", r ~= nil and not job.error, string.format("%.1f s CPU in %d slices, %d test flights, hover %.0f%%", secs, slices, r and r.evals or 0, (r and r.hover or 0) * 100))
print("  before: " .. fmt(r.before))
print("  after:  " .. fmt(r.after))
print(string.format("  sliders: master %.2f, D %.2f, FF %.2f", r.sliders.master, r.sliders.d, r.sliders.ff))
print(string.format("  roll P%d I%d D%d F%d   pitch P%d I%d D%d F%d   yaw P%d I%d D%d F%d",
    r.pids.roll[1], r.pids.roll[2], r.pids.roll[3], r.pids.roll[4], r.pids.pitch[1], r.pids.pitch[2], r.pids.pitch[3], r.pids.pitch[4],
    r.pids.yaw[1], r.pids.yaw[2], r.pids.yaw[3], r.pids.yaw[4]))
check("much better than the sloppy tune", r.afterScore < r.beforeScore * 0.75, string.format("score %.2f -> %.2f", r.beforeScore, r.afterScore))
check("tracks the sticks better", r.after.track < r.before.track * 0.8, "")
check("sane PIDs", r.pids.roll[1] >= 25 and r.pids.roll[1] <= 110 and r.pids.roll[3] >= 15 and r.pids.roll[3] <= 90, "")
check("small overshoot", r.after.overshoot < 0.12, string.format("%.0f%%", r.after.overshoot * 100))
check("time-sliced (no long freezes)", slices > 20, tostring(slices))

local jr = tune(AT.pidsFor({ master = 1, d = 1, ff = 1 }), "race")
local js = tune(AT.pidsFor({ master = 1, d = 1, ff = 1 }), "smooth")
check("race goal is sharper than smooth", jr.result.after.track <= js.result.after.track + 1e-9 and js.result.after.noise <= jr.result.after.noise + 1e-9,
    string.format("race: track %.3f noise %.4f | smooth: track %.3f noise %.4f", jr.result.after.track, jr.result.after.noise, js.result.after.track, js.result.after.noise))
print(fails == 0 and "ALL AUTOTUNE TESTS PASSED" or (fails .. " FAILURE(S)"))
