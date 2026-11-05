local AT = {}

local abs, sqrt, max, min, floor = math.abs, math.sqrt, math.max, math.min, math.floor
local R2D = 180 / math.pi
local BASE = {
    roll  = { 45, 80, 35, 120 },
    pitch = { 47, 84, 39, 125 },
    yaw   = { 45, 80, 0, 120 },
}

AT.GOALS = {
    freestyle = { 1.0, 1.0, 1.0, 1.0, 1.0 },
    race      = { 1.6, 0.7, 0.8, 1.2, 0.6 },
    smooth    = { 0.7, 1.8, 1.4, 0.8, 1.6 },
}

local function round(x) return floor(x + 0.5) end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

function AT.pidsFor(p)
    local out = {}
    for ax, b in pairs(BASE) do
        local m = p.master
        out[ax] = {
            clamp(round(b[1] * m), 5, 220),
            clamp(round(b[2] * m), 5, 250),
            clamp(round(b[3] * m * p.d), 0, 160),
            clamp(round(b[4] * p.ff), 0, 600),
        }
    end
    return out
end

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end

local function yieldIfOver(job)
    if job.deadline and job.clock() > job.deadline then coroutine.yield() end
end

local function fly(job, pids, hoverThr)
    local M = job.spec.mods
    local Craft, Sim = M.Craft, M.Sim
    math.randomseed(4242)
    local quad = job.spec.makeQuad()
    local c = Craft.new(M, quad, job.spec.rates, pids, copy(job.spec.misc))
    Craft.setRate(c, job.spec.hz or 2000)
    Sim.reset(c.sim, 0, 0, 500, 1, 0, 0, 0)
    local FRAME = 1 / 144
    local t = 0
    local function run(sec, thr, roll, pitch, yaw, rec)
        local e = t + sec
        while t < e do
            Craft.setInput(c, thr, roll, pitch, yaw, true)
            Craft.advance(c, FRAME, nil)
            t = t + FRAME
            if rec then rec(c) end
            yieldIfOver(job)
        end
    end
    Craft.setInput(c, 0, 0, 0, 0, false)
    Craft.advance(c, FRAME, nil)
    Craft.setInput(c, 0, 0, 0, 0, true)
    run(0.5, hoverThr, 0, 0, 0)
    c.noiseAcc, c.noiseN = 0, 0
    run(0.6, hoverThr, 0, 0, 0)
    local nz, nzN = c.noiseAcc, c.noiseN

    local m = { track = 0, trackN = 0, over = 0, bounce = 0, bounceN = 0, punch = 0, punchN = 0, noise = 0, noiseN = 0, rise = 0, riseN = 0 }
    local function gyro(ax)
        local s = c.sim
        if ax == 1 then return s.wx * R2D elseif ax == 2 then return s.wy * R2D end
        return -s.wz * R2D
    end
    for ax = 1, 3 do
        for _, dir in ipairs({ 1, -1 }) do
            local st = 0.5 * dir
            local r, p, y = 0, 0, 0
            if ax == 1 then r = st elseif ax == 2 then p = st else y = st end
            local tStart, peak, risen = t, 0, nil
            run(0.22, hoverThr, r, p, y, function(cc)
                local sp = cc.fc.sp[ax]
                local g = gyro(ax)
                m.track = m.track + abs(sp - g)
                m.trackN = m.trackN + abs(sp)
                if g * dir > peak then peak = g * dir end
                if not risen and g * dir >= 0.9 * abs(sp) and abs(sp) > 1 then risen = t - tStart end
            end)
            local target = abs(c.fc.sp[ax])
            if target > 1 then m.over = max(m.over, (peak - target) / target) end
            m.rise = m.rise + (risen or 0.22)
            m.riseN = m.riseN + 1
            local tStop = t
            run(0.3, hoverThr, 0, 0, 0, function(cc)
                if t - tStop > 0.04 then
                    local g = gyro(ax)
                    m.bounce = m.bounce + g * g
                    m.bounceN = m.bounceN + 1
                end
            end)
        end
    end
    run(0.35, 0.85, 0, 0, 0, function(cc)
        local s = cc.sim
        m.punch = m.punch + (s.wx * s.wx + s.wy * s.wy) * R2D * R2D
        m.punchN = m.punchN + 1
    end)
    run(0.35, hoverThr, 0, 0, 0, function(cc)
        local s = cc.sim
        m.punch = m.punch + (s.wx * s.wx + s.wy * s.wy) * R2D * R2D
        m.punchN = m.punchN + 1
    end)
    return {
        track = m.track / max(m.trackN, 1e-6),
        overshoot = max(0, m.over),
        bounce = sqrt(m.bounce / max(m.bounceN, 1)),
        punch = sqrt(m.punch / max(m.punchN, 1)),
        noise = sqrt(nz / max(nzN, 1)),
        rise = m.rise / max(m.riseN, 1),
    }
end

local function score(job, r)
    local w = AT.GOALS[job.spec.goal or "freestyle"] or AT.GOALS.freestyle
    return w[1] * r.track * 4
        + w[2] * max(0, r.overshoot - 0.02) * 6
        + w[3] * r.bounce / 25
        + w[4] * r.punch / 30
        + w[5] * r.noise / 0.0025
end
AT.score = score

local function findHover(job)
    local lo, hi = 0.05, 0.85
    local M = job.spec.mods
    for _ = 1, 9 do
        local mid = (lo + hi) / 2
        local quad = job.spec.makeQuad()
        local c = M.Craft.new(M, quad, job.spec.rates, AT.pidsFor({ master = 1, d = 1, ff = 1 }), copy(job.spec.misc))
        M.Craft.setRate(c, 1000)
        M.Sim.reset(c.sim, 0, 0, 500, 1, 0, 0, 0)
        M.Craft.setInput(c, 0, 0, 0, 0, false); M.Craft.advance(c, 1 / 144, nil)
        M.Craft.setInput(c, 0, 0, 0, 0, true)
        local t = 0
        while t < 1.2 do
            M.Craft.setInput(c, mid, 0, 0, 0, true)
            M.Craft.advance(c, 1 / 144, nil)
            t = t + 1 / 144
            yieldIfOver(job)
        end
        if c.sim.vz > 0 then hi = mid else lo = mid end
    end
    return (lo + hi) / 2
end

local function evaluate(job, p)
    local key = string.format("%.3f/%.3f/%.3f", p.master, p.d, p.ff)
    if job.cache[key] then return job.cache[key].score, job.cache[key].metrics end
    local r = fly(job, AT.pidsFor(p), job.hover)
    local s = score(job, r)
    job.cache[key] = { score = s, metrics = r }
    job.evals = job.evals + 1
    job.progress = min(0.97, 0.08 + job.evals / job.maxEvals * 0.9)
    return s, r
end

local function search(job)
    job.hover = findHover(job)
    job.progress = 0.08
    job.before = fly(job, job.spec.pids, job.hover)
    job.beforeScore = score(job, job.before)
    local x = { master = 1, d = 1, ff = 1 }
    local step = { master = 0.25, d = 0.25, ff = 0.4 }
    local bounds = { master = { 0.4, 2.0 }, d = { 0.3, 1.8 }, ff = { 0, 2.5 } }
    local best = evaluate(job, x)
    local order = { "master", "d", "ff" }
    for _ = 1, 8 do
        local improved = false
        for _, k in ipairs(order) do
            for _, sgn in ipairs({ 1, -1 }) do
                if job.evals >= job.maxEvals then break end
                local cand = { master = x.master, d = x.d, ff = x.ff }
                cand[k] = clamp(cand[k] + sgn * step[k], bounds[k][1], bounds[k][2])
                if cand[k] ~= x[k] then
                    local s = evaluate(job, cand)
                    if s < best - 1e-4 then
                        best, x, improved = s, cand, true
                        break
                    end
                end
            end
        end
        if not improved then
            step.master, step.d, step.ff = step.master / 2, step.d / 2, step.ff / 2
            if step.master < 0.04 then break end
        end
        if job.evals >= job.maxEvals then break end
    end
    local _, metrics = evaluate(job, x)
    job.result = {
        sliders = x,
        pids = AT.pidsFor(x),
        after = metrics,
        afterScore = best,
        before = job.before,
        beforeScore = job.beforeScore,
        hover = job.hover,
        evals = job.evals,
    }
    job.progress = 1
end

function AT.new(spec)
    local job = { spec = spec, cache = {}, evals = 0, maxEvals = spec.maxEvals or 34, progress = 0, clock = spec.clock or os.clock }
    job.co = coroutine.create(function() search(job) end)
    return job
end

function AT.step(job, budget)
    if job.done then return true, 1 end
    job.deadline = budget and (job.clock() + budget) or nil
    local ok, err = coroutine.resume(job.co)
    if not ok then
        job.done, job.error = true, tostring(err)
        return true, job.progress, job.error
    end
    if coroutine.status(job.co) == "dead" then job.done = true end
    return job.done, job.progress
end

return AT
