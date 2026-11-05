local Rates = {}

local abs = math.abs
local SETPOINT_RATE_LIMIT = 1998
local RC_RATE_INCREMENTAL = 14.54

Rates.TYPES = { "BETAFLIGHT", "RACEFLIGHT", "KISS", "ACTUAL", "QUICK" }
Rates.AXES = { "roll", "pitch", "yaw" }

local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

local function applyBetaflight(rc, sr, ex, cmd, absCmd)
    if ex ~= 0 then
        local e = ex / 100
        cmd = cmd * absCmd * absCmd * absCmd * e + cmd * (1 - e)
    end
    local rcRate = rc / 100
    if rcRate > 2 then
        rcRate = rcRate + RC_RATE_INCREMENTAL * (rcRate - 2)
    end
    local angleRate = 200 * rcRate * cmd
    if sr ~= 0 then
        angleRate = angleRate * (1 / clamp(1 - absCmd * (sr / 100), 0.01, 1))
    end
    return angleRate
end

local function applyRaceflight(rc, sr, ex, cmd, absCmd)
    cmd = (1 + 0.01 * ex * (cmd * cmd - 1)) * cmd
    local angleRate = 10 * rc * cmd
    return angleRate * (1 + absCmd * sr * 0.01)
end

local function applyKiss(rc, sr, ex, cmd, absCmd)
    local curve = ex / 100
    local useRates = 1 / clamp(1 - absCmd * (sr / 100), 0.01, 1)
    local kissCmd = (cmd * cmd * cmd * curve + cmd * (1 - curve)) * (rc / 1000)
    return clamp(2000 * useRates * kissCmd, -SETPOINT_RATE_LIMIT, SETPOINT_RATE_LIMIT)
end

local function applyActual(rc, sr, ex, cmd, absCmd)
    local e = ex / 100
    local c5 = cmd * cmd * cmd * cmd * cmd
    local expof = absCmd * (c5 * e + cmd * (1 - e))
    local center = rc * 10
    local stickMovement = sr * 10 - center
    if stickMovement < 0 then stickMovement = 0 end
    return cmd * center + stickMovement * expof
end

local function applyQuick(rc, sr, ex, cmd, absCmd)
    local rcRate = rc * 2
    local maxDPS = math.max(sr * 10, rcRate)
    if rcRate <= 0 then return 0 end
    local e = ex / 100
    local superFactorConfig = (maxDPS / rcRate - 1) / (maxDPS / rcRate)
    local curve = absCmd * absCmd * absCmd * e + absCmd * (1 - e)
    local superFactor = 1 / clamp(1 - curve * superFactorConfig, 0.01, 1)
    return clamp(cmd * rcRate * superFactor, -SETPOINT_RATE_LIMIT, SETPOINT_RATE_LIMIT)
end

local FN = {
    BETAFLIGHT = applyBetaflight,
    RACEFLIGHT = applyRaceflight,
    KISS = applyKiss,
    ACTUAL = applyActual,
    QUICK = applyQuick,
}

function Rates.setpoint(r, axis, stick)
    local fn = FN[r.type] or applyActual
    stick = clamp(stick, -1, 1)
    local a = fn(r.rc_rate[axis], r.srate[axis], r.expo[axis], stick, abs(stick))
    local lim = (r.rate_limit and r.rate_limit[axis]) or SETPOINT_RATE_LIMIT
    return clamp(a, -lim, lim)
end

function Rates.maxRate(r, axis)
    return abs(Rates.setpoint(r, axis, 1))
end

function Rates.throttle(r, x)
    local mid = (r.thr_mid or 50) / 100
    local expo = (r.thr_expo or 0) / 100
    x = clamp(x, 0, 1)
    if expo == 0 then return x end
    local t = x - mid
    local y = (t > 0) and (1 - mid) or mid
    if y <= 0 then return x end
    return clamp(mid + t * (1 - expo + expo * (t * t) / (y * y)), 0, 1)
end

function Rates.defaults()
    return {
        type = "ACTUAL",
        rc_rate = { 7, 7, 7 },
        srate = { 67, 67, 67 },
        expo = { 0, 0, 0 },
        thr_mid = 50,
        thr_expo = 0,
        rate_limit = { 1998, 1998, 1998 },
    }
end

local function pct(v) return v / 100 end
local function unpct(v) return math.floor(v * 100 + 0.5) end
local function x10(v) return v * 10 end
local function unx10(v) return math.floor(v / 10 + 0.5) end
local function x2(v) return v * 2 end
local function unx2(v) return math.floor(v / 2 + 0.5) end
local function x1(v) return v end
local function unx1(v) return math.floor(v + 0.5) end

Rates.UI = {
    BETAFLIGHT = {
        { "RC Rate",    pct, unpct, 0.01, 2.55, 2 },
        { "Super Rate", pct, unpct, 0.00, 1.00, 2 },
        { "RC Expo",    pct, unpct, 0.00, 1.00, 2 },
    },
    RACEFLIGHT = {
        { "Rate",  x10, unx10, 10, 2550, 0 },
        { "Acro+", x1,  unx1,  0, 255, 0 },
        { "Expo",  x1,  unx1,  0, 100, 0 },
    },
    KISS = {
        { "RC Rate",  pct, unpct, 0.01, 2.55, 2 },
        { "Rate",     pct, unpct, 0.00, 0.99, 2 },
        { "RC Curve", pct, unpct, 0.00, 1.00, 2 },
    },
    ACTUAL = {
        { "Center Sensitivity", x10, unx10, 10, 2000, 0 },
        { "Max Rate",           x10, unx10, 10, 2000, 0 },
        { "Expo",               pct, unpct, 0.00, 1.00, 2 },
    },
    QUICK = {
        { "Center Sensitivity", x2,  unx2,  2, 510, 0 },
        { "Max Rate",           x10, unx10, 10, 2000, 0 },
        { "Expo",               pct, unpct, 0.00, 1.00, 2 },
    },
}

local AXIS_NAMES = { "roll", "pitch", "yaw" }

function Rates.parseCLI(text, r, pids, misc)
    local n = 0
    local typeMap = { BETAFLIGHT = true, RACEFLIGHT = true, KISS = true, ACTUAL = true, QUICK = true }
    for line in string.gmatch(text .. "\n", "([^\r\n]*)\r?\n") do
        local key, val = string.match(line, "^%s*set%s+([%w_]+)%s*=%s*(%S+)")
        if key then
            key = string.lower(key)
            local num = tonumber(val)
            local done = false
            if key == "rates_type" then
                local t = string.upper(val)
                if typeMap[t] then r.type = t; done = true end
            elseif key == "thr_mid" and num then r.thr_mid = num; done = true
            elseif key == "thr_expo" and num then r.thr_expo = num; done = true
            elseif key == "rc_rate" and num then r.rc_rate[1] = num; r.rc_rate[2] = num; done = true
            elseif key == "rc_rate_yaw" and num then r.rc_rate[3] = num; done = true
            elseif key == "rc_expo" and num then r.expo[1] = num; r.expo[2] = num; done = true
            elseif key == "rc_expo_yaw" and num then r.expo[3] = num; done = true
            elseif num then
                for ai = 1, 3 do
                    local an = AXIS_NAMES[ai]
                    if key == an .. "_rc_rate" then r.rc_rate[ai] = num; done = true
                    elseif key == an .. "_srate" then r.srate[ai] = num; done = true
                    elseif key == an .. "_expo" then r.expo[ai] = num; done = true
                    elseif key == an .. "_rate_limit" then
                        r.rate_limit = r.rate_limit or { 1998, 1998, 1998 }
                        r.rate_limit[ai] = num; done = true
                    elseif pids and key == "p_" .. an then pids[an][1] = num; done = true
                    elseif pids and key == "i_" .. an then pids[an][2] = num; done = true
                    elseif pids and key == "d_" .. an then pids[an][3] = num; done = true
                    elseif pids and key == "f_" .. an then pids[an][4] = num; done = true
                    end
                end
                if not done and misc then
                    if key == "dshot_idle_value" then misc.idle = num / 100; done = true
                    elseif key == "tpa_rate" then misc.tpa_rate = num; done = true
                    elseif key == "tpa_breakpoint" then misc.tpa_breakpoint = num; done = true
                    elseif key == "iterm_relax_cutoff" then misc.iterm_relax_cutoff = num; done = true
                    elseif key == "pidsum_limit" then misc.pidsum_limit = num; done = true
                    elseif key == "pidsum_limit_yaw" then misc.pidsum_limit_yaw = num; done = true
                    elseif key == "vbat_sag_compensation" then misc.vbat_sag_compensation = num; done = true
                    elseif key == "gyro_lpf1_dyn_min_hz" then misc.gyro_lpf1_dyn_min_hz = num; done = true
                    elseif key == "gyro_lpf1_dyn_max_hz" then misc.gyro_lpf1_dyn_max_hz = num; done = true
                    elseif key == "gyro_lpf2_static_hz" then misc.gyro_lpf2_static_hz = num; done = true
                    elseif key == "dterm_lpf1_dyn_min_hz" then misc.dterm_lpf1_dyn_min_hz = num; done = true
                    elseif key == "dterm_lpf1_dyn_max_hz" then misc.dterm_lpf1_dyn_max_hz = num; done = true
                    elseif key == "dterm_lpf2_static_hz" then misc.dterm_lpf2_static_hz = num; done = true
                    elseif key == "anti_gravity_gain" then misc.anti_gravity_gain = num; done = true
                    elseif key == "rpm_filter_harmonics" then misc.rpm_filter_harmonics = num; done = true
                    elseif key == "vbat_warning_cell_voltage" then misc.vbat_warning_cell_voltage = num; done = true
                    elseif key == "vbat_min_cell_voltage" then misc.vbat_min_cell_voltage = num; done = true
                    elseif key == "vbat_full_cell_voltage" then misc.vbat_full_cell_voltage = num; done = true
                    end
                end
            end
            if done then n = n + 1 end
        end
    end
    return n
end

return Rates
