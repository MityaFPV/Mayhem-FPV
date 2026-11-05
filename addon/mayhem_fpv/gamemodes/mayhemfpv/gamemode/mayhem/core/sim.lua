local Sim = {}
local Prop = Sim.Prop
function Sim.setProp(P) Prop = P end

local sqrt, abs, max, min, exp = math.sqrt, math.abs, math.max, math.min, math.exp
local sin, cos, pi, random, floor = math.sin, math.cos, math.pi, math.random, math.floor
local RHO = 1.225
local G = 9.81
local TWO_PI = 2 * pi

Sim.G = G

local OCV = {
    { 0.00, 3.27 }, { 0.05, 3.50 }, { 0.10, 3.61 }, { 0.20, 3.69 }, { 0.30, 3.74 },
    { 0.40, 3.78 }, { 0.50, 3.82 }, { 0.60, 3.87 }, { 0.70, 3.93 }, { 0.80, 4.01 },
    { 0.90, 4.09 }, { 1.00, 4.20 },
}
local function ocvCell(soc)
    if soc <= 0 then local x = -soc; return max(0.5, OCV[1][2] - 15 * x - 60 * x * x) end
    if soc >= 1 then return OCV[#OCV][2] end
    for i = 2, #OCV do
        local b = OCV[i]
        if soc <= b[1] then
            local a = OCV[i - 1]
            return a[2] + (b[2] - a[2]) * (soc - a[1]) / (b[1] - a[1])
        end
    end
    return OCV[#OCV][2]
end
Sim.ocvCell = ocvCell

function Sim.new(quad)
    local s = {
        quad = quad,
        Ke = 60 / (TWO_PI * quad.kv),
        diskArea = pi * (quad.propD / 2) ^ 2,
        zeroThrustK = quad.zeroThrustFactor * quad.propPitch / TWO_PI,
        px = 0, py = 0, pz = 0,
        vx = 0, vy = 0, vz = 0,
        qw = 1, qx = 0, qy = 0, qz = 0,
        wx = 0, wy = 0, wz = 0,
        ppx = 0, ppy = 0, ppz = 0,
        pqw = 1, pqx = 0, pqy = 0, pqz = 0,
        mw = { 0, 0, 0, 0 },
        duty = { 0, 0, 0, 0 },
        thrust = { 0, 0, 0, 0 },
        current = { 0, 0, 0, 0 },
        propAng = { 0, 1.1, 2.3, 0.4 },
        escOn = false,
        wnA = { 0, 0, 0, 0 }, wnB = { 0, 0, 0, 0 }, wnT = { 1, 1, 1, 1 }, wnF = { 25, 25, 25, 25 },
        wash = 0,
        washScale = 1,
        soc = 1, vrc = 0, ibat = 0, mah = 0, vbat = quad.cells * 4.2,
        ibatMax = 0, vbatMin = quad.cells * 4.2,
        packT = quad.ambient or 20, rMul = 1, startSoc = 1,
        solveS = { 0, 0, 0, 0 }, solveE = { 0, 0, 0, 0 }, solveC = { false, false, false, false },
        vi = { 0, 0, 0, 0 },
        wakeIn = { 0, 0, 0, 0 },
        propT = nil,
        groundDist = 100,
        windX = 0, windY = 0, windZ = 0,
        time = 0,
        contacts = {},
        nContacts = 0,
        lastImpact = 0,
        impactTime = -1,
        propStrike = { 0, 0, 0, 0 },
        propHealth = { 1, 1, 1, 1 },
        pendingGrind = { 0, 0, 0, 0 },
        spinCmd = { 1, 1, 1, 1 },
        vibration = 0,
        damageScale = 1,
        propBroke = 0,
        sleeping = false,
        sleepTimer = 0,
        ax = 0, ay = 0, az = 0,
    }
    for i = 1, 40 do s.contacts[i] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } end
    return s
end

function Sim.reset(s, px, py, pz, qw, qx, qy, qz)
    s.px, s.py, s.pz = px, py, pz
    s.ppx, s.ppy, s.ppz = px, py, pz
    local n = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
    s.qw, s.qx, s.qy, s.qz = qw / n, qx / n, qy / n, qz / n
    s.pqw, s.pqx, s.pqy, s.pqz = s.qw, s.qx, s.qy, s.qz
    s.vx, s.vy, s.vz = 0, 0, 0
    s.wx, s.wy, s.wz = 0, 0, 0
    for i = 1, 4 do s.mw[i] = 0; s.duty[i] = 0; s.thrust[i] = 0; s.current[i] = 0 end
    s.sleeping = false
    s.sleepTimer = 0
end

function Sim.repair(s)
    for i = 1, 4 do s.propHealth[i] = 1 end
    s.vibration = 0
end

function Sim.socFromCell(v)
    if v <= OCV[1][2] then return 0 end
    for i = 2, #OCV do
        local b = OCV[i]
        if v <= b[2] then
            local a = OCV[i - 1]
            return a[1] + (b[1] - a[1]) * (v - a[2]) / (b[2] - a[2])
        end
    end
    return 1
end

function Sim.resetBattery(s, soc, tempC)
    local q = s.quad
    s.soc = soc or 1
    s.startSoc = s.soc
    s.vrc, s.ibat, s.mah = 0, 0, 0
    s.vbat = ocvCell(s.soc) * q.cells
    s.ibatMax = 0
    s.vbatMin = s.vbat
    s.packT = tempC or q.ambient or 20
    s.rMul = 1
end

local function resistanceMul(q, soc, T)
    local e = 1 - soc
    if e < 0 then e = 0 end
    local e2 = e * e
    local fSoc = 1 + 0.5 * e2 * e2 * e2 * e2
    if soc < 0 then fSoc = fSoc + 4 * -soc end
    local fT = exp(0.022 * (25 - T))
    if fT < 0.75 then fT = 0.75 elseif fT > 2.5 then fT = 2.5 end
    return fSoc * fT * (q.irHealth or 1)
end
Sim.resistanceMul = resistanceMul

local function quatToMat(w, x, y, z)
    local xx, yy, zz = x * x, y * y, z * z
    local xy, xz, yz = x * y, x * z, y * z
    local wx, wy, wz = w * x, w * y, w * z
    return 1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy),
           2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx),
           2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)
end
Sim.quatToMat = quatToMat

local function integrateQuat(qw, qx, qy, qz, wx, wy, wz, dt)
    local om = sqrt(wx * wx + wy * wy + wz * wz)
    if om < 1e-9 then return qw, qx, qy, qz end
    local half = om * dt * 0.5
    local sh = sin(half) / om
    local dw, dx, dy, dz = cos(half), wx * sh, wy * sh, wz * sh
    local nw = qw * dw - qx * dx - qy * dy - qz * dz
    local nx = qw * dx + qx * dw + qy * dz - qz * dy
    local ny = qw * dy - qx * dz + qy * dw + qz * dx
    local nz = qw * dz + qx * dy - qy * dx + qz * dw
    local n = 1 / sqrt(nw * nw + nx * nx + ny * ny + nz * nz)
    return nw * n, nx * n, ny * n, nz * n
end
Sim.integrateQuat = integrateQuat

function Sim.matrix(s)
    return quatToMat(s.qw, s.qx, s.qy, s.qz)
end

local function washNoise(s, i, dt)
    local t = s.wnT[i] + dt * s.wnF[i]
    if t >= 1 then
        t = t - floor(t)
        s.wnA[i] = s.wnB[i]
        s.wnB[i] = random() * 2 - 1
        s.wnF[i] = 14 + random() * 26
    end
    s.wnT[i] = t
    local k = t * t * (3 - 2 * t)
    return s.wnA[i] + (s.wnB[i] - s.wnA[i]) * k
end

function Sim.step(s, dt, env)
    local q = s.quad
    s.time = s.time + dt

    if s.sleeping then
        if s.escOn then
            s.sleeping = false
        else
            s.ibat = q.auxCurrent
            s.mah = s.mah + s.ibat * dt / 3.6
            s.soc = s.soc - s.ibat * dt / (q.capacity * 3.6)
            return
        end
    end

    local r11, r12, r13, r21, r22, r23, r31, r32, r33 = quatToMat(s.qw, s.qx, s.qy, s.qz)

    local vax, vay, vaz = s.vx - s.windX, s.vy - s.windY, s.vz - s.windZ
    local bvx = r11 * vax + r21 * vay + r31 * vaz
    local bvy = r12 * vax + r22 * vay + r32 * vaz
    local bvz = r13 * vax + r23 * vay + r33 * vaz
    local wx, wy, wz = s.wx, s.wy, s.wz

    local rMul = resistanceMul(q, s.soc, s.packT)
    s.rMul = rMul
    local Rb = q.R0 * rMul
    local Voc = ocvCell(s.soc) * q.cells - s.vrc
    local vbat
    if s.escOn then
        local Rm, Ke_ = q.Rm, s.Ke
        local fixed = q.auxCurrent
        local A, B = 0, 0
        local sv, ev, clamped = s.solveS, s.solveE, s.solveC
        for i = 1, 4 do
            local si = s.spinCmd[i] * s.duty[i]
            local w = s.mw[i]
            sv[i], ev[i], clamped[i] = si, Ke_ * w, false
            if (w > 1 or w < -1) then fixed = fixed + s.duty[i] * q.I0 * 0.5 end
            A = A + si * si / Rm
            B = B + si * ev[i] / Rm
        end
        vbat = (Voc - Rb * fixed + Rb * B) / (1 + Rb * A)
        local again = false
        for i = 1, 4 do
            local si = sv[i]
            local I = (si * vbat - ev[i]) / Rm
            local hi, lo = q.iMax, q.iMin
            if s.spinCmd[i] < 0 then hi, lo = -q.iMin, -q.iMax end
            if I > hi or I < lo then
                local Ic = (I > hi) and hi or lo
                clamped[i] = true
                again = true
                A = A - si * si / Rm
                B = B - si * ev[i] / Rm
                fixed = fixed + si * Ic
            end
        end
        if again then vbat = (Voc - Rb * fixed + Rb * B) / (1 + Rb * A) end
    else
        vbat = Voc - Rb * q.auxCurrent
    end
    if vbat < 0 then vbat = 0 end
    s.vbat = vbat

    local ge = 1
    if r33 > 0.5 then
        local R = q.propD * 0.5
        local h = s.groundDist + q.propZ
        if h < 3 * R then
            if h < 0.6 * R then h = 0.6 * R end
            local k = R / (4 * h)
            ge = 1 / (1 - k * k)
            if ge > 1.35 then ge = 1.35 end
        end
    end

    local Ke = s.Ke
    local Kt = Ke
    local rz = q.propZ
    local kH = q.kH
    local Jr = q.Jrot
    local escOn = s.escOn
    local washK = q.propwash * s.washScale
    local diskK = 1 / (2 * RHO * s.diskArea)

    local phys2 = (q.phys or 1) >= 2 and Prop ~= nil
    local PT, Rp, rhoA = nil, 0, 0
    local wakeIn = s.wakeIn
    if phys2 then
        PT = s.propT
        if not PT then PT = Prop.get(q); s.propT = PT end
        Rp = PT.R
        rhoA = RHO * PT.A
        local fx, fy = -bvx, -bvy
        local vh = sqrt(fx * fx + fy * fy)
        for j = 1, 4 do wakeIn[j] = 0 end
        if vh > 2 then
            local ux, uy = fx / vh, fy / vh
            local gain = q.wakeGain or 1.6
            for i = 1, 4 do
                local vi = s.vi[i]
                if vi > 0.2 then
                    local mi = q.motors[i]
                    local down = bvz + vi
                    for j = 1, 4 do
                        if j ~= i then
                            local mj = q.motors[j]
                            local dx, dy = mj[1] - mi[1], mj[2] - mi[2]
                            local sd = dx * ux + dy * uy
                            if sd > 0.02 then
                                local lx, ly = dx - sd * ux, dy - sd * uy
                                local lat = sqrt(lx * lx + ly * ly)
                                local cover = 1 - lat / (1.85 * Rp)
                                local drop = abs(sd * down / vh)
                                local vert = 1 - drop / (1.5 * Rp)
                                if cover > 0 and vert > 0 then
                                    wakeIn[j] = wakeIn[j] + gain * vi * cover * vert
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local Fx, Fy, Fz = 0, 0, 0
    local Tx, Ty, Tz = 0, 0, 0
    local Hz = 0
    local ibat = q.auxCurrent
    local washMax = 0
    local lossT = Kt * q.I0
    local vibMax = 0
    local health = s.propHealth
    local spinCmd = s.spinCmd

    for i = 1, 4 do
        local m = q.motors[i]
        local mx, my, dir = m[1], m[2], m[3]
        local w = s.mw[i]
        local aw = w < 0 and -w or w
        local sg = w < 0 and -1 or 1

        local pvx = bvx + (wy * rz - wz * my)
        local pvy = bvy + (wz * mx - wx * rz)
        local pvz = bvz + (wx * my - wy * mx)

        local tauNet, I = 0, 0
        if escOn then
            local d = s.duty[i]
            local sc = spinCmd[i]
            I = (sc * d * vbat - Ke * w) / q.Rm
            if sc > 0 then
                if I > q.iMax then I = q.iMax elseif I < q.iMin then I = q.iMin end
            else
                if I < -q.iMax then I = -q.iMax elseif I > -q.iMin then I = -q.iMin end
            end
            tauNet = Kt * I - (aw > 1 and sg * lossT or 0)
            ibat = ibat + sc * d * I + (aw > 1 and d * q.I0 * 0.5 or 0)
        elseif aw > 1 then
            tauNet = -sg * 3e-4
        end

        local h = health[i]
        local eff = h >= 1 and 1 or (0.02 + 0.98 * h ^ 0.7)
        local qeff = h >= 1 and 1 or (0.01 + 0.99 * eff ^ 1.3)
        local w2 = w * w
        local T, Q
        local hx, hy = nil, nil
        local Mx, My = 0, 0
        if phys2 and w > 0 then
            local gei = 1
            if r33 > 0.3 then
                local h = s.groundDist + (r31 * mx + r32 * my + r33 * rz)
                local Rr = Rp
                if h < 3 * Rr then
                    if h < 0.6 * Rr then h = 0.6 * Rr end
                    local kk = Rr / (4 * h)
                    gei = 1 / (1 - kk * kk)
                    if gei > 1.35 then gei = 1.35 end
                end
            end
            local VR = w * Rp
            if VR > 2 then
                local ve = sqrt(pvx * pvx + pvy * pvy)
                local ct, cq, chx, chy, cmx, cmy, li = Prop.lookup(PT, ve / VR, (pvz + wakeIn[i]) / VR)
                local dyn = rhoA * VR * VR
                T = ct * dyn * gei * eff
                Q = cq * dyn * Rp * qeff
                s.vi[i] = li * VR
                local ex, ey = 1, 0
                if ve > 1e-3 then ex, ey = pvx / ve, pvy / ve end
                local yx, yy = -ey, ex
                if dir < 0 then chy, cmx = -chy, -cmx end
                hx = (chx * ex + chy * yx) * dyn * eff
                hy = (chx * ey + chy * yy) * dyn * eff
                local mr = Rp * dyn * eff
                Mx = (cmx * ex + cmy * yx) * mr
                My = (cmx * ey + cmy * yy) * mr
            else
                T, Q = 0, 0
                s.vi[i] = 0
                hx, hy = 0, 0
            end
            local desc = -pvz
            if desc > 0.3 and T > 0 then
                local vh = sqrt(T * diskK)
                if vh < 1 then vh = 1 end
                local x = (desc / vh - 1.0) / 0.45
                local wsh = exp(-x * x) * washK
                if wsh > 0.002 then
                    local nz = washNoise(s, i, dt)
                    T = T * (1 - 0.28 * wsh + 0.75 * wsh * nz)
                    if wsh > washMax then washMax = wsh end
                end
            end
        elseif w >= 0 then
            local vzero = s.zeroThrustK * w
            if vzero < 0.5 then vzero = 0.5 end
            local f = 1 - pvz / vzero
            if f > q.maxDescentGain then f = q.maxDescentGain elseif f < -0.25 then f = -0.25 end
            T = q.kT * w2 * f * ge * eff

            local desc = -pvz
            if desc > 0.3 and T > 0 then
                local vh = sqrt(T * diskK)
                if vh < 1 then vh = 1 end
                local x = (desc / vh - 1.0) / 0.45
                local wsh = exp(-x * x) * washK
                if wsh > 0.002 then
                    local n = washNoise(s, i, dt)
                    T = T * (1 - 0.28 * wsh + 0.75 * wsh * n)
                    if wsh > washMax then washMax = wsh end
                end
            end
            local fq = 0.3 + 0.7 * f
            if fq < 0.12 then fq = 0.12 end
            Q = q.kQ * w2 * fq * qeff
        else
            T = -0.5 * q.kT * w2 * eff
            Q = -0.85 * q.kQ * w2 * qeff
        end

        local nw = w + (tauNet - Q) / Jr * dt
        if not escOn and (nw > 0) ~= (w > 0) then nw = 0 end
        w = nw
        if s.propStrike[i] > 0 then
            w = w * (1 - s.propStrike[i])
            s.propStrike[i] = 0
        end
        aw = w < 0 and -w or w
        s.mw[i] = w
        s.thrust[i] = T
        s.current[i] = I
        local ang = s.propAng[i] + dir * w * dt
        if ang > TWO_PI then ang = ang - TWO_PI elseif ang < 0 then ang = ang + TWO_PI end
        s.propAng[i] = ang

        if not hx then
            hx = -kH * aw * pvx
            hy = -kH * aw * pvy
        end
        Fx = Fx + hx
        Fy = Fy + hy
        Fz = Fz + T
        Tx = Tx + (my * T - rz * hy)
        Ty = Ty + (rz * hx - mx * T)
        Tz = Tz + (mx * hy - my * hx)
        Tx = Tx + Mx
        Ty = Ty + My
        Tz = Tz - dir * tauNet
        Hz = Hz + dir * Jr * w

        if h < 1 then
            local r = aw / 2500
            local vib = (1 - h) * r * r
            if vib > vibMax then vibMax = vib end
            if vib > 0.001 then
                Tx = Tx + q.vibTorque * vib * (random() * 2 - 1)
                Ty = Ty + q.vibTorque * vib * (random() * 2 - 1)
                Fz = Fz + q.vibTorque * 20 * vib * (random() * 2 - 1)
            end
        end
    end
    s.vibration = vibMax
    s.wash = washMax

    local spd = sqrt(bvx * bvx + bvy * bvy + bvz * bvz)
    local cd = q.CdA
    local hr = 0.5 * RHO * spd
    local dx_, dy_, dz_ = -hr * cd[1] * bvx, -hr * cd[2] * bvy, -hr * cd[3] * bvz
    Fx = Fx + dx_
    Fy = Fy + dy_
    Fz = Fz + dz_
    if phys2 and q.cop then
        local cx, cy, cz = q.cop[1], q.cop[2], q.cop[3]
        Tx = Tx + (cy * dz_ - cz * dy_)
        Ty = Ty + (cz * dx_ - cx * dz_)
        Tz = Tz + (cx * dy_ - cy * dx_)
    end

    local ad = q.angDrag
    Tx = Tx - ad * wx * abs(wx)
    Ty = Ty - ad * wy * abs(wy)
    Tz = Tz - ad * wz * abs(wz)

    Tx = Tx - wy * Hz
    Ty = Ty + wx * Hz

    local Ixx, Iyy, Izz = q.Ixx, q.Iyy, q.Izz
    local cx = wy * (Izz * wz) - wz * (Iyy * wy)
    local cy = wz * (Ixx * wx) - wx * (Izz * wz)
    local cz = wx * (Iyy * wy) - wy * (Ixx * wx)
    wx = wx + (Tx - cx) / Ixx * dt
    wy = wy + (Ty - cy) / Iyy * dt
    wz = wz + (Tz - cz) / Izz * dt
    s.wx, s.wy, s.wz = wx, wy, wz

    local im = 1 / q.mass
    local ax = (r11 * Fx + r12 * Fy + r13 * Fz) * im
    local ay = (r21 * Fx + r22 * Fy + r23 * Fz) * im
    local az = (r31 * Fx + r32 * Fy + r33 * Fz) * im - G
    s.vx = s.vx + ax * dt
    s.vy = s.vy + ay * dt
    s.vz = s.vz + az * dt
    s.ax, s.ay, s.az = ax, ay, az + G

    if ibat < -10 then ibat = -10 end
    s.ibat = ibat
    if ibat > s.ibatMax then s.ibatMax = ibat end
    s.vrc = s.vrc + (ibat * q.R1 * rMul - s.vrc) * dt / q.tau1
    s.soc = s.soc - ibat * dt / (q.capacity * 3.6)
    s.mah = s.mah + ibat * dt / 3.6
    local heat = ibat * ibat * (q.R0 + q.R1) * rMul
    local spd = sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz)
    local cool = (0.35 + 0.09 * spd) * (s.packT - (q.ambient or 20))
    s.packT = s.packT + (heat - cool) * dt / (q.packHeatCap or 200)
    if escOn and vbat < s.vbatMin then s.vbatMin = vbat end

    local active = env and env.trace and env.near ~= false
    local didCollide = false
    if active then
        s.collideCounter = (s.collideCounter or 0) + 1
        if s.collideCounter >= (env.every or 1) then
            s.collideCounter = 0
            local nqw, nqx, nqy, nqz = integrateQuat(s.qw, s.qx, s.qy, s.qz, s.wx, s.wy, s.wz, dt)
            Sim.collide(s, dt, env, s.px + s.vx * dt, s.py + s.vy * dt, s.pz + s.vz * dt, nqw, nqx, nqy, nqz)
            didCollide = true
        end
    else
        s.nContacts = 0
    end

    s.px = s.px + s.vx * dt
    s.py = s.py + s.vy * dt
    s.pz = s.pz + s.vz * dt
    s.qw, s.qx, s.qy, s.qz = integrateQuat(s.qw, s.qx, s.qy, s.qz, s.wx, s.wy, s.wz, dt)

    if didCollide then
        if s.nContacts > 0 then Sim.correctPositions(s) end
        s.ppx, s.ppy, s.ppz = s.px, s.py, s.pz
        s.pqw, s.pqx, s.pqy, s.pqz = s.qw, s.qx, s.qy, s.qz
    elseif not active then
        s.ppx, s.ppy, s.ppz = s.px, s.py, s.pz
        s.pqw, s.pqx, s.pqy, s.pqz = s.qw, s.qx, s.qy, s.qz
    end

    if not escOn and s.nContacts > 0 then
        local v2 = s.vx * s.vx + s.vy * s.vy + s.vz * s.vz
        local w2 = s.wx * s.wx + s.wy * s.wy + s.wz * s.wz
        local spin = abs(s.mw[1]) + abs(s.mw[2]) + abs(s.mw[3]) + abs(s.mw[4])
        if v2 < 0.0004 and w2 < 0.0025 and spin < 4 then
            s.sleepTimer = s.sleepTimer + dt
            if s.sleepTimer > 0.4 then
                s.sleeping = true
                s.vx, s.vy, s.vz, s.wx, s.wy, s.wz = 0, 0, 0, 0, 0, 0
                for i = 1, 4 do s.mw[i] = 0 end
            end
        else
            s.sleepTimer = 0
        end
    else
        s.sleepTimer = 0
    end
end

function Sim.collide(s, dt, env, px, py, pz, nqw, nqx, nqy, nqz)
    local q = s.quad
    local pts = q.contacts
    local trace = env.trace
    local r11, r12, r13, r21, r22, r23, r31, r32, r33 = quatToMat(nqw, nqx, nqy, nqz)
    local o11, o12, o13, o21, o22, o23, o31, o32, o33 = quatToMat(s.pqw, s.pqx, s.pqy, s.pqz)
    local ppx, ppy, ppz = s.ppx, s.ppy, s.ppz
    local C = s.contacts
    local n = 0

    for i = 1, #pts do
        local pt = pts[i]
        local bx, by, bz = pt[1], pt[2], pt[3]
        local ox = r11 * bx + r12 * by + r13 * bz
        local oy = r21 * bx + r22 * by + r23 * bz
        local oz = r31 * bx + r32 * by + r33 * bz
        local x1, y1, z1 = px + ox, py + oy, pz + oz
        local x0 = ppx + o11 * bx + o12 * by + o13 * bz
        local y0 = ppy + o21 * bx + o22 * by + o23 * bz
        local z0 = ppz + o31 * bx + o32 * by + o33 * bz
        local hit, frac, nx, ny, nz, hx, hy, hz, ss = trace(x0, y0, z0, x1, y1, z1)
        if ss then
            hit, frac, nx, ny, nz, hx, hy, hz, ss = trace(px, py, pz, x1, y1, z1)
            if ss then hit = false end
        end
        if hit and (nx ~= 0 or ny ~= 0 or nz ~= 0) then
            local depth = (hx - x1) * nx + (hy - y1) * ny + (hz - z1) * nz
            if depth < 0 then depth = 0 end
            n = n + 1
            local c = C[n]
            c[1], c[2], c[3] = ox, oy, oz
            c[4], c[5], c[6] = nx, ny, nz
            c[7] = depth
            c[8] = 0
            c[9] = 0
            c[10], c[11], c[12] = 0, 0, 0
            c[13] = pt[4] or 0
            c[14], c[15], c[16] = bx, by, bz
            c[17], c[18], c[19] = hx, hy, hz
        end
    end
    s.nContacts = n
    if n == 0 then return end

    local m = q.mass
    local im = 1 / m
    local iIxx, iIyy, iIzz = 1 / q.Ixx, 1 / q.Iyy, 1 / q.Izz
    local mu = q.friction
    local e = q.restitution

    local vx, vy, vz = s.vx, s.vy, s.vz
    local bwx, bwy, bwz = s.wx, s.wy, s.wz
    local wx = r11 * bwx + r12 * bwy + r13 * bwz
    local wy = r21 * bwx + r22 * bwy + r23 * bwz
    local wz = r31 * bwx + r32 * bwy + r33 * bwz

    local function invI(ax, ay, az)
        local bx = (r11 * ax + r21 * ay + r31 * az) * iIxx
        local by = (r12 * ax + r22 * ay + r32 * az) * iIyy
        local bz = (r13 * ax + r23 * ay + r33 * az) * iIzz
        return r11 * bx + r12 * by + r13 * bz,
               r21 * bx + r22 * by + r23 * bz,
               r31 * bx + r32 * by + r33 * bz
    end

    local function applyImpulse(rx, ry, rz, jx, jy, jz)
        vx = vx + jx * im
        vy = vy + jy * im
        vz = vz + jz * im
        local tx = ry * jz - rz * jy
        local ty = rz * jx - rx * jz
        local tz = rx * jy - ry * jx
        local dx, dy, dz = invI(tx, ty, tz)
        wx = wx + dx
        wy = wy + dy
        wz = wz + dz
    end

    local function effMass(rx, ry, rz, nx, ny, nz)
        local cx = ry * nz - rz * ny
        local cy = rz * nx - rx * nz
        local cz = rx * ny - ry * nx
        local ix, iy, iz = invI(cx, cy, cz)
        local kx = iy * rz - iz * ry
        local ky = iz * rx - ix * rz
        local kz = ix * ry - iy * rx
        return im + kx * nx + ky * ny + kz * nz
    end

    local maxImpact = 0
    for k = 1, n do
        local c = C[k]
        local rx, ry, rz = c[1], c[2], c[3]
        local pvx = vx + (wy * rz - wz * ry)
        local pvy = vy + (wz * rx - wx * rz)
        local pvz = vz + (wx * ry - wy * rx)
        local vn = pvx * c[4] + pvy * c[5] + pvz * c[6]
        if vn < -1.2 then c[9] = -e * vn end
        if -vn > maxImpact then maxImpact = -vn end
        local mi = c[13]
        if mi > 0 and abs(s.mw[mi]) > 150 then
            local tv = sqrt(pvx * pvx + pvy * pvy + pvz * pvz)
            s.propStrike[mi] = min(0.6, 0.08 + tv * 0.04)
            local spinF = min(1, abs(s.mw[mi]) / 2000)
            s.pendingGrind[mi] = s.pendingGrind[mi] + spinF * dt * (env.every or 1)
        end
    end
    if maxImpact > 0.5 then
        s.lastImpact = maxImpact
        s.impactTime = s.time
    end

    for iter = 1, 6 do
        for k = 1, n do
            local c = C[k]
            local rx, ry, rz = c[1], c[2], c[3]
            local nx, ny, nz = c[4], c[5], c[6]
            local pvx = vx + (wy * rz - wz * ry)
            local pvy = vy + (wz * rx - wx * rz)
            local pvz = vz + (wx * ry - wy * rx)
            local vn = pvx * nx + pvy * ny + pvz * nz
            local kn = effMass(rx, ry, rz, nx, ny, nz)
            local dj = (c[9] - vn) / kn
            local acc = c[8] + dj
            if acc < 0 then acc = 0 end
            dj = acc - c[8]
            c[8] = acc
            if dj ~= 0 then applyImpulse(rx, ry, rz, nx * dj, ny * dj, nz * dj) end

            pvx = vx + (wy * rz - wz * ry)
            pvy = vy + (wz * rx - wx * rz)
            pvz = vz + (wx * ry - wy * rx)
            vn = pvx * nx + pvy * ny + pvz * nz
            local tx, ty, tz = pvx - vn * nx, pvy - vn * ny, pvz - vn * nz
            local vt = sqrt(tx * tx + ty * ty + tz * tz)
            if vt > 1e-6 then
                tx, ty, tz = tx / vt, ty / vt, tz / vt
                local kt = effMass(rx, ry, rz, tx, ty, tz)
                local jt = -vt / kt
                local fx, fy, fz = c[10] + tx * jt, c[11] + ty * jt, c[12] + tz * jt
                local fm = sqrt(fx * fx + fy * fy + fz * fz)
                local lim = mu * c[8]
                if fm > lim then
                    local sc = (fm > 0) and lim / fm or 0
                    fx, fy, fz = fx * sc, fy * sc, fz * sc
                end
                local djx, djy, djz = fx - c[10], fy - c[11], fz - c[12]
                c[10], c[11], c[12] = fx, fy, fz
                applyImpulse(rx, ry, rz, djx, djy, djz)
            end
        end
    end

    local ds = s.damageScale * (q.propFragility or 1)
    if ds > 0 then
        for k = 1, n do
            local c = C[k]
            local mi = c[13]
            if mi > 0 then
                local dmg = (c[8] * 0.35 + s.pendingGrind[mi] * 3.0) * ds
                if dmg > 0.002 then
                    local before = s.propHealth[mi]
                    local h = before - dmg
                    if h < 0 then h = 0 end
                    s.propHealth[mi] = h
                    if before > 0 and h <= 0 then s.propBroke = s.time end
                end
                s.pendingGrind[mi] = 0
            end
        end
    end

    s.vx, s.vy, s.vz = vx, vy, vz
    s.wx = r11 * wx + r21 * wy + r31 * wz
    s.wy = r12 * wx + r22 * wy + r32 * wz
    s.wz = r13 * wx + r23 * wy + r33 * wz

end

function Sim.correctPositions(s)
    local C = s.contacts
    local r11, r12, r13, r21, r22, r23, r31, r32, r33 = quatToMat(s.qw, s.qx, s.qy, s.qz)
    local px, py, pz = s.px, s.py, s.pz
    local cx, cy, cz = 0, 0, 0
    for k = 1, s.nContacts do
        local c = C[k]
        local bx, by, bz = c[14], c[15], c[16]
        local x = px + r11 * bx + r12 * by + r13 * bz
        local y = py + r21 * bx + r22 * by + r23 * bz
        local z = pz + r31 * bx + r32 * by + r33 * bz
        local nx, ny, nz = c[4], c[5], c[6]
        local depth = (c[17] - x) * nx + (c[18] - y) * ny + (c[19] - z) * nz
        local need = depth - (cx * nx + cy * ny + cz * nz)
        if need > 0 then
            cx, cy, cz = cx + nx * need, cy + ny * need, cz + nz * need
        end
    end
    s.px, s.py, s.pz = px + cx, py + cy, pz + cz
end

return Sim
