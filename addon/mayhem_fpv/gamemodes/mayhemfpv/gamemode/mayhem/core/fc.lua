local FC = {}

local abs, max, min, pi, floor = math.abs, math.max, math.min, math.pi, math.floor

local PTERM_SCALE = 0.032029
local ITERM_SCALE = 0.244381
local DTERM_SCALE = 0.000529
local FEEDFORWARD_SCALE = 0.013754
local ITERM_LIMIT = 400
local ITERM_RELAX_SETPOINT_THRESHOLD = 40
local RAD2DEG = 180 / pi

local function pt1k(hz, dt)
    if hz <= 0 then return 1 end
    local rc = 1 / (2 * pi * hz)
    return dt / (rc + dt)
end

function FC.new(Rates, rates, pids, misc, quad)
    local fc = {
        Rates = Rates,
        rates = rates,
        pids = pids,
        misc = misc,
        armed = false,
        armBlock = nil,
        prevArm = nil,
        airmode = false,
        armTime = 0,
        iterm = { 0, 0, 0 },
        gyroF = { 0, 0, 0 },
        gyroF2 = { 0, 0, 0 },
        dF2 = { 0, 0, 0 },
        thrLpf = 0, agBoost = 1,
        outQ = {}, outHead = 0,
        prevGyro = { 0, 0, 0 },
        dF = { 0, 0, 0 },
        prevSp = { 0, 0, 0 },
        ffF = { 0, 0, 0 },
        spLpf = { 0, 0, 0 },
        sp = { 0, 0, 0 },
        pidSum = { 0, 0, 0 },
        throttle = 0,
        thrStick = 0,
        motor = { 0, 0, 0, 0 },
        mixv = { 0, 0, 0, 0 },
        mix = {},
        justArmed = false,
        justDisarmed = false,
        spin = { 1, 1, 1, 1 },
        turtleSw = false,
        flip = false,
    }
    local a = quad.arm
    for i, m in ipairs(quad.motors) do
        fc.mix[i] = { m[2] / a, -m[1] / a, m[3] }
    end
    return fc
end

local function resetState(fc)
    for ax = 1, 3 do
        fc.iterm[ax] = 0
        fc.dF[ax] = 0
        fc.ffF[ax] = 0
        fc.prevSp[ax] = 0
        fc.spLpf[ax] = 0
        fc.pidSum[ax] = 0
    end
    fc.airmode = false
end

function FC.arm(fc)
    resetState(fc)
    fc.flip = fc.turtleSw
    for i = 1, 4 do fc.spin[i] = fc.flip and -1 or 1 end
    fc.armed = true
    fc.armTime = 0
    fc.justArmed = true
end

function FC.disarm(fc)
    fc.armed = false
    fc.flip = false
    for i = 1, 4 do fc.spin[i] = 1 end
    fc.justDisarmed = true
    for i = 1, 4 do fc.motor[i] = 0 end
end

function FC.setArmSwitch(fc, on, thrStick)
    if fc.prevArm == nil then
        fc.prevArm = on
        if on then fc.armBlock = "ARMSWITCH" end
        return
    end
    if not on then
        if fc.armed then FC.disarm(fc) end
        fc.armBlock = nil
    elseif not fc.prevArm and not fc.armed then
        if fc.armBlock == nil then
            if thrStick < 0.05 then
                FC.arm(fc)
            else
                fc.armBlock = "THROTTLE"
            end
        end
    end
    fc.prevArm = on
end

function FC.setTurtleSwitch(fc, on)
    fc.turtleSw = on and true or false
end

function FC.forceDisarm(fc, reason)
    if fc.armed then FC.disarm(fc) end
    if fc.prevArm then fc.armBlock = reason or "ARMSWITCH" end
end

function FC.update(fc, dt, rc, gR, gP, gY)
    local Rates, rates, misc = fc.Rates, fc.rates, fc.misc
    fc.thrStick = rc.thr
    local thr = Rates.throttle(rates, rc.thr)
    fc.throttle = thr

    local g1 = fc.gyroF
    local gF = fc.gyroF2
    local v2 = fc.v2
    if v2 and misc.gyro_lpf1_dyn_min_hz then
        local lo, hi = misc.gyro_lpf1_dyn_min_hz, misc.gyro_lpf1_dyn_max_hz or misc.gyro_lpf1_dyn_min_hz
        local cut = lo + (hi - lo) * math.sqrt(thr)
        local k1 = pt1k(cut, dt)
        local k2 = pt1k(misc.gyro_lpf2_static_hz or 500, dt)
        g1[1] = g1[1] + k1 * (gR - g1[1]); gF[1] = gF[1] + k2 * (g1[1] - gF[1])
        g1[2] = g1[2] + k1 * (gP - g1[2]); gF[2] = gF[2] + k2 * (g1[2] - gF[2])
        g1[3] = g1[3] + k1 * (gY - g1[3]); gF[3] = gF[3] + k2 * (g1[3] - gF[3])
    else
        local kg = pt1k(misc.gyro_lpf_hz or 250, dt)
        g1[1] = g1[1] + kg * (gR - g1[1])
        g1[2] = g1[2] + kg * (gP - g1[2])
        g1[3] = g1[3] + kg * (gY - g1[3])
        gF[1], gF[2], gF[3] = g1[1], g1[2], g1[3]
    end
    fc.gyroFiltered = gF

    if not fc.armed then
        local m = fc.motor
        m[1], m[2], m[3], m[4] = 0, 0, 0, 0
        fc.prevGyro[1], fc.prevGyro[2], fc.prevGyro[3] = gF[1], gF[2], gF[3]
        fc.outHead = 0
        return
    end
    fc.armTime = fc.armTime + dt

    if fc.flip then
        FC.crashflip(fc, rc)
        return
    end

    if not fc.airmode and thr > (misc.airmode_start or 0.25) then
        fc.airmode = true
    end

    local sp = fc.sp
    sp[1] = Rates.setpoint(rates, 1, rc.roll)
    sp[2] = Rates.setpoint(rates, 2, rc.pitch)
    sp[3] = Rates.setpoint(rates, 3, rc.yaw)

    local tpa = 1
    local bp = ((misc.tpa_breakpoint or 1350) - 1000) / 1000
    local tr = (misc.tpa_rate or 65) / 100
    if thr > bp and bp < 1 then
        tpa = 1 - tr * (thr - bp) / (1 - bp)
    end

    local kd, kd2
    if v2 and misc.dterm_lpf1_dyn_min_hz then
        local lo, hi = misc.dterm_lpf1_dyn_min_hz, misc.dterm_lpf1_dyn_max_hz or misc.dterm_lpf1_dyn_min_hz
        kd = pt1k(lo + (hi - lo) * math.sqrt(thr), dt)
        kd2 = pt1k(misc.dterm_lpf2_static_hz or 150, dt)
    else
        kd = pt1k(misc.dterm_lpf_hz or 110, dt)
    end
    local ag = v2 and (misc.anti_gravity_gain or 0) or 0
    fc.thrLpf = fc.thrLpf + pt1k(5, dt) * (thr - fc.thrLpf)
    local agB = 1
    if ag > 0 then
        local hp = abs(thr - fc.thrLpf)
        agB = 1 + (ag / 10) * min(1, hp * 8)
    end
    fc.agBoost = agB
    local kr = pt1k(misc.iterm_relax_cutoff or 15, dt)
    local kff = pt1k(40, dt)
    local invDt = 1 / dt
    local pids = fc.pids
    local pidTab = fc.pidTab
    if not pidTab or pidTab[1] ~= pids.roll or pidTab[2] ~= pids.pitch or pidTab[3] ~= pids.yaw then
        pidTab = { pids.roll, pids.pitch, pids.yaw }
        fc.pidTab = pidTab
    end
    local lim = misc.pidsum_limit or 500
    local limY = misc.pidsum_limit_yaw or 400

    for ax = 1, 3 do
        local pid = pidTab[ax]
        local g = gF[ax]
        local s = sp[ax]
        local err = s - g

        local P = PTERM_SCALE * pid[1] * err

        local errI = err
        local spl = fc.spLpf[ax] + kr * (s - fc.spLpf[ax])
        fc.spLpf[ax] = spl
        if ax < 3 then
            local hpf = abs(s - spl)
            local f = 1 - hpf / ITERM_RELAX_SETPOINT_THRESHOLD
            if f < 0 then f = 0 end
            errI = err * f
        end
        local I = fc.iterm[ax]
        if fc.airmode then
            I = I + ITERM_SCALE * pid[2] * errI * dt * agB
            if I > ITERM_LIMIT then I = ITERM_LIMIT elseif I < -ITERM_LIMIT then I = -ITERM_LIMIT end
        else
            I = 0
        end
        fc.iterm[ax] = I

        local dRaw = -(g - fc.prevGyro[ax]) * invDt
        fc.prevGyro[ax] = g
        local d = fc.dF[ax] + kd * (dRaw - fc.dF[ax])
        fc.dF[ax] = d
        if kd2 then
            d = fc.dF2[ax] + kd2 * (d - fc.dF2[ax])
            fc.dF2[ax] = d
        end
        local D = DTERM_SCALE * pid[3] * d * tpa

        local ffRaw = (s - fc.prevSp[ax]) * invDt
        fc.prevSp[ax] = s
        local ff = fc.ffF[ax] + kff * (ffRaw - fc.ffF[ax])
        fc.ffF[ax] = ff
        local F = FEEDFORWARD_SCALE * (pid[4] / 100) * ff

        local sum = P + I + D + F
        local l = (ax == 3) and limY or lim
        if sum > l then sum = l elseif sum < -l then sum = -l end
        fc.pidSum[ax] = sum
    end

    local sR, sP, sY = fc.pidSum[1] / 1000, fc.pidSum[2] / 1000, fc.pidSum[3] / 1000
    local mix, mixv = fc.mix, fc.mixv
    local mmin, mmax = 1e9, -1e9
    for i = 1, 4 do
        local m = mix[i]
        local v = sR * m[1] + sP * m[2] + sY * m[3]
        mixv[i] = v
        if v < mmin then mmin = v end
        if v > mmax then mmax = v end
    end
    local range = mmax - mmin
    local throttle = thr
    if range > 1 then
        for i = 1, 4 do mixv[i] = mixv[i] / range end
        mmin, mmax = mmin / range, mmax / range
    end
    if throttle < -mmin then throttle = -mmin end
    if throttle > 1 - mmax then throttle = 1 - mmax end

    local idle = misc.idle or 0.055
    local span = 1 - idle
    local motor = fc.motor
    local delay = (v2 and misc.output_delay_ms) and floor(misc.output_delay_ms / 1000 / dt + 0.5) or 0
    local Q = fc.outQ
    for i = 1, 4 do
        local o = idle + span * (mixv[i] + throttle)
        if o < idle then o = idle elseif o > 1 then o = 1 end
        if delay > 0 then
            local slot = (fc.outHead % delay) * 4 + i
            local old = Q[slot]
            Q[slot] = o
            o = (fc.outHead >= delay and old) or idle
        end
        motor[i] = o
    end
    fc.outHead = fc.outHead + 1
end

local CRASH_FLIP_STICK_MINF = 0.15
local CRASH_FLIP_DEADBAND = 20 / 2000
function FC.crashflip(fc, rc)
    local misc = fc.misc
    local expoF = 1 - (misc.crashflip_expo or 35) / 100
    local pA, rA, yA = abs(rc.pitch), abs(rc.roll), abs(rc.yaw)
    local function ex(x) return expoF * x + x * x * x * (1 - expoF) end
    local pE, rE, yE = ex(pA), ex(rA), ex(yA)
    local signPitch = rc.pitch < 0 and 1 or -1
    local signRoll = rc.roll < 0 and 1 or -1
    local signYaw = (rc.yaw < 0 and 1 or -1) * -1
    local len = math.sqrt(pA * pA + rA * rA)
    local lenE = math.sqrt(pE * pE + rE * rE)
    if yA > max(pA, rA) then
        len, lenE = yA, yE
        signRoll, signPitch = 0, 0
    else
        signYaw = 0
    end
    local cosPhi = (len > 0) and (pA + rA) / (math.sqrt(2) * len) or 0
    if cosPhi < math.sqrt(3) / 2 then
        if rA > pA then signPitch = 0 else signRoll = 0 end
    end
    local minE = ex(CRASH_FLIP_STICK_MINF)
    local power = max(0, lenE - minE) / (1 - minE)
    local idle = misc.idle or 0.055
    for i = 1, 4 do
        local m = fc.mix[i]
        local o = signPitch * m[2] + signRoll * m[1] + signYaw * m[3]
        if o < 0 then o = 0 end
        o = min(1, power * o)
        local out = idle + o * (1 - idle)
        if out < idle + CRASH_FLIP_DEADBAND then out = 0 else out = out - CRASH_FLIP_DEADBAND end
        fc.motor[i] = out
        fc.spin[i] = -1
    end
end

FC.RAD2DEG = RAD2DEG

return FC
