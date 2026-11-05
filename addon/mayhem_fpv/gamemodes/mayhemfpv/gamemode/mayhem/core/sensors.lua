local Sensors = {}

local sin, cos, sqrt, pi, random, abs, min, max = math.sin, math.cos, math.sqrt, math.pi, math.random, math.abs, math.min, math.max
local R2D = 180 / pi

function Sensors.new()
    return { vib = 0, noiseRms = 0, sat = false, g1 = 0, g2 = 0, g3 = 0 }
end

local function aaf(f, fc)
    return 1 / sqrt(1 + (f / fc) ^ 2)
end

local function gauss()
    return (random() + random() + random() - 1.5) * 2
end

function Sensors.gyro(st, sim, misc)
    local q = sim.quad
    local harm = misc.rpm_filter_harmonics or 3
    local att1 = (harm >= 1) and 0.06 or 1
    local att3 = (harm >= 3) and 0.08 or 1
    local kv = q.gyroVib or 1.6
    local vx, vy, vz = 0, 0, 0
    local health = sim.propHealth
    local total = 0
    for m = 1, 4 do
        local w = abs(sim.mw[m])
        if w > 30 then
            local wk = w / 1000
            local imb = (q.imbalance or 1) + (1 - health[m]) * 9
            local f1 = w / (2 * pi)
            local a1 = kv * wk * wk * imb * aaf(f1, 260) * att1
            local a3 = kv * 0.55 * wk * wk * aaf(3 * f1, 260) * att3
            local ang = sim.propAng[m]
            local s1, c1 = sin(ang), cos(ang)
            local s3, c3 = sin(3 * ang + m), cos(3 * ang + m)
            vx = vx + a1 * c1 + a3 * c3
            vy = vy + a1 * s1 + a3 * s3
            vz = vz + 0.3 * a1 * c1 + 0.2 * a3 * s3
            total = total + a1 + a3
        end
    end
    st.vib = total
    local n = q.gyroNoise or 0.08
    local gr = sim.wx * R2D + vx + gauss() * n
    local gp = sim.wy * R2D + vy + gauss() * n
    local gy = -sim.wz * R2D + vz + gauss() * n
    local lim = 2000
    st.sat = false
    if gr > lim then gr = lim; st.sat = true elseif gr < -lim then gr = -lim; st.sat = true end
    if gp > lim then gp = lim; st.sat = true elseif gp < -lim then gp = -lim; st.sat = true end
    if gy > lim then gy = lim; st.sat = true elseif gy < -lim then gy = -lim; st.sat = true end
    return gr, gp, gy
end

return Sensors
