local FPV = MayhemFPV

local T = {}
FPV.Tune = T

T.state = "idle"
T.progress = 0
T.goal = "freestyle"
T.result = nil
T.backup = nil
T.message = nil

local BUDGET = 0.006

local function copyPids(p)
    return {
        roll = { p.roll[1], p.roll[2], p.roll[3], p.roll[4] },
        pitch = { p.pitch[1], p.pitch[2], p.pitch[3], p.pitch[4] },
        yaw = { p.yaw[1], p.yaw[2], p.yaw[3], p.yaw[4] },
    }
end

local function setPids(dst, src)
    for _, ax in ipairs({ "roll", "pitch", "yaw" }) do
        for i = 1, 4 do dst[ax][i] = src[ax][i] end
    end
end

function T.Running() return T.state == "running" end

function T.Start(goal)
    if T.state == "running" then return end
    local cfg = FPV.Config.data
    T.goal = goal or T.goal
    T.backup = copyPids(cfg.pids)
    T.result, T.message = nil, nil
    T.job = FPV.Autotune.new({
        mods = FPV.Flight.Mods(),
        makeQuad = function() return FPV.Flight.MakeQuad(true) end,
        rates = cfg.rates,
        misc = cfg.misc,
        pids = copyPids(cfg.pids),
        hz = cfg.sim.rate or 2000,
        goal = T.goal,
        clock = SysTime,
    })
    T.state, T.progress = "running", 0
    T.started = SysTime()
end

function T.Cancel()
    if T.state ~= "running" then return end
    T.job = nil
    T.state, T.progress, T.message = "idle", 0, "Autotune cancelled."
end

function T.Revert()
    if not T.backup then return end
    setPids(FPV.Config.data.pids, T.backup)
    FPV.Config.Save()
    T.message = "Previous PIDs restored."
    T.reverted = true
end

hook.Add("Think", "mayhem_autotune", function()
    if T.state ~= "running" or not T.job then return end
    local done, prog, err = FPV.Autotune.step(T.job, BUDGET)
    T.progress = prog or T.progress
    if not done then return end
    local job = T.job
    T.job = nil
    if err or not job.result then
        T.state = "error"
        T.message = "Autotune failed: " .. tostring(err)
        ErrorNoHalt("[Mayhem FPV] autotune: " .. tostring(err) .. "\n")
        return
    end
    T.result = job.result
    T.state = "done"
    T.reverted = false
    T.seconds = SysTime() - (T.started or SysTime())
    setPids(FPV.Config.data.pids, job.result.pids)
    FPV.Config.Save()
    surface.PlaySound("buttons/button9.wav")
    if FPV.Menu and FPV.Menu.OnTuneDone then FPV.Menu.OnTuneDone() end
end)

function T.Describe(r)
    return string.format("tracking error %.0f%%, overshoot %.0f%%, response %.0f ms, bounce-back %.0f deg/s, motor noise %.2f%%",
        r.track * 100, r.overshoot * 100, r.rise * 1000, r.bounce, r.noise * 100)
end

return T
