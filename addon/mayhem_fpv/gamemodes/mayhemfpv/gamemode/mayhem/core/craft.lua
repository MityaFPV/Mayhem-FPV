local Craft = {}

function Craft.new(mods, quad, rates, pids, misc)
    local c = {
        Sim = mods.Sim, FC = mods.FC,
        quad = quad,
        sim = mods.Sim.new(quad),
        Sensors = mods.Sensors,
        sens = mods.Sensors and mods.Sensors.new() or nil,
        motorLp = { 0, 0, 0, 0 },
        motorNoise = 0,
        noiseAcc = 0, noiseN = 0,
        noiseArmed = false,
        fc = mods.FC.new(mods.Rates, rates, pids, misc, quad),
        dt = 1 / 1000,
        acc = 0,
        rcPrev = { thr = 0, roll = 0, pitch = 0, yaw = 0 },
        rcNext = { thr = 0, roll = 0, pitch = 0, yaw = 0 },
        rc = { thr = 0, roll = 0, pitch = 0, yaw = 0 },
        flyTime = 0,
        onTime = 0,
        steps = 0,
    }
    return c
end

function Craft.setRate(c, hz)
    if hz < 200 then hz = 200 elseif hz > 4000 then hz = 4000 end
    c.dt = 1 / hz
end

function Craft.setInput(c, thr, roll, pitch, yaw, armSwitch, turtleSwitch)
    local p, nx = c.rcPrev, c.rcNext
    p.thr, p.roll, p.pitch, p.yaw = nx.thr, nx.roll, nx.pitch, nx.yaw
    nx.thr, nx.roll, nx.pitch, nx.yaw = thr, roll, pitch, yaw
    if turtleSwitch ~= nil then c.FC.setTurtleSwitch(c.fc, turtleSwitch) end
    c.FC.setArmSwitch(c.fc, armSwitch, thr)
end

function Craft.advance(c, frameDt, env, maxSteps)
    local dt = c.dt
    c.acc = c.acc + frameDt
    local steps = math.floor(c.acc / dt)
    maxSteps = maxSteps or 120
    if steps > maxSteps then
        steps = maxSteps
        c.acc = 0
    else
        c.acc = c.acc - steps * dt
    end
    local Sim, FC = c.Sim, c.FC
    local sim, fc = c.sim, c.fc
    local p, nx, rc = c.rcPrev, c.rcNext, c.rc
    local R2D = FC.RAD2DEG
    local sagComp = (fc.misc.vbat_sag_compensation or 0) / 100
    local kSag = dt / (0.2 / (2 * math.pi) + dt)
    c.vSag = c.vSag or sim.vbat
    local Sensors = c.Sensors
    local phys2 = Sensors and (sim.quad.phys or 1) >= 2
    fc.v2 = phys2 and true or false
    local kMl = dt / (1 / (2 * math.pi * 30) + dt)
    local kMn = dt / (0.25 + dt)
    for k = 1, steps do
        local t = k / steps
        rc.thr = p.thr + (nx.thr - p.thr) * t
        rc.roll = p.roll + (nx.roll - p.roll) * t
        rc.pitch = p.pitch + (nx.pitch - p.pitch) * t
        rc.yaw = p.yaw + (nx.yaw - p.yaw) * t
        if phys2 then
            local gR, gP, gY = Sensors.gyro(c.sens, sim, fc.misc)
            FC.update(fc, dt, rc, gR, gP, gY)
        else
            local gn = sim.vibration * 12
            local nR, nP, nY = 0, 0, 0
            if gn > 0.002 then
                local rnd = math.random
                nR, nP, nY = (rnd() * 2 - 1) * gn, (rnd() * 2 - 1) * gn, (rnd() * 2 - 1) * gn * 0.5
            end
            FC.update(fc, dt, rc, (sim.wx + nR) * R2D, (sim.wy + nP) * R2D, -(sim.wz + nY) * R2D)
        end
        if fc.armed and not c.noiseArmed then
            for i = 1, 4 do c.motorLp[i] = fc.motor[i] end
            c.motorNoise = 0
        end
        c.noiseArmed = fc.armed
        if fc.armed then
            local ml, acc = c.motorLp, 0
            for i = 1, 4 do
                local m = fc.motor[i]
                ml[i] = ml[i] + kMl * (m - ml[i])
                local hp = m - ml[i]
                acc = acc + hp * hp
            end
            c.motorNoise = c.motorNoise + kMn * (acc * 0.25 - c.motorNoise)
            c.noiseAcc = c.noiseAcc + acc * 0.25
            c.noiseN = c.noiseN + 1
        end
        sim.escOn = fc.armed
        c.vSag = c.vSag + (sim.vbat - c.vSag) * kSag
        local d, m, sp, fs = sim.duty, fc.motor, sim.spinCmd, fc.spin
        local comp = sagComp
        if comp > 0 and fc.armed then
            local full = sim.quad.cells * 4.2
            local r = full / math.max(c.vSag, 1)
            if r > 1.33 then r = 1.33 end
            local scale = 1 + comp * (r - 1)
            for i = 1, 4 do
                local o = m[i] * scale
                d[i] = o > 1 and 1 or o
            end
        else
            d[1], d[2], d[3], d[4] = m[1], m[2], m[3], m[4]
        end
        sp[1], sp[2], sp[3], sp[4] = fs[1], fs[2], fs[3], fs[4]
        Sim.step(sim, dt, env)
    end
    c.vDisplay = c.vDisplay and (c.vDisplay + (sim.vbat - c.vDisplay) * math.min(1, frameDt * 3)) or sim.vbat
    c.onTime = c.onTime + frameDt
    if fc.armed and fc.airmode then c.flyTime = c.flyTime + frameDt end
    c.steps = steps
    return steps
end

return Craft
