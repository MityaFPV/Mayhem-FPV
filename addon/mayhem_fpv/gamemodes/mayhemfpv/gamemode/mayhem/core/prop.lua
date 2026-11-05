local Prop = {}

local sin, cos, atan2, sqrt, pi, exp, acos, abs, min, max, floor =
    math.sin, math.cos, math.atan2, math.sqrt, math.pi, math.exp, math.acos, math.abs, math.min, math.max, math.floor

local RHO = 1.225
Prop.MU_MAX, Prop.NMU = 1.2, 25
Prop.LC_MIN, Prop.LC_MAX, Prop.NLC = -0.5, 0.5, 41

local CL0, CLA, ASTALL, CD0, KD = 0.30, 5.0, math.rad(17), 0.022, 0.028
local function airfoil(a)
    if a > pi then a = a - 2 * pi elseif a < -pi then a = a + 2 * pi end
    local s2 = sin(2 * a)
    local clFp = 1.05 * s2
    local sa = sin(a)
    local cdFp = CD0 + 1.9 * sa * sa
    local aa = abs(a)
    if aa < ASTALL + 0.25 then
        local cl = CL0 + CLA * a
        local cd = CD0 + KD * (cl - 0.25) * (cl - 0.25)
        local w = 1 / (1 + exp(-(aa - ASTALL) / 0.05))
        return (1 - w) * cl + w * clFp, (1 - w) * cd + w * cdFp
    end
    return clFp, cdFp
end
Prop.airfoil = airfoil

function Prop.geometry(quad, nr)
    local R = quad.propD * 0.5
    local r0 = 0.0068
    local P = quad.propPitch or 0.0889
    nr = nr or 10
    local st = {}
    local dr = (R - r0) / nr
    for i = 1, nr do
        local r = r0 + (i - 0.5) * dr
        local t = (r - r0) / (R - r0)
        local chord
        if t < 0.32 then
            local k = t / 0.32
            chord = 0.0095 + (0.0158 - 0.0095) * (k * k * (3 - 2 * k))
        else
            local k = (t - 0.32) / 0.68
            chord = 0.0158 - (0.0158 - 0.0072) * k
        end
        if t > 0.9 then chord = chord * sqrt(max(0.04, 1 - ((t - 0.9) / 0.1) ^ 2)) end
        local theta = math.atan(P / (2 * pi * r))
        if theta > math.rad(38) then theta = math.rad(38) end
        st[i] = { r = r, x = r / R, c = chord, theta = theta, dr = dr }
    end
    return { R = R, B = quad.propBlades or 3, st = st }
end

local NPSI = 16
local SPSI, CPSI = {}, {}
for k = 1, NPSI do
    local psi = (k - 0.5) / NPSI * 2 * pi
    SPSI[k], CPSI[k] = sin(psi), cos(psi)
end

local function sweep(G, mu, lc, li0)
    local R, B = G.R, G.B
    local piR2 = pi * R * R
    local kx, ky = 0, 0
    local lam = lc + li0
    if mu > 0.002 then
        local chi = atan2(mu, abs(lam) + 1e-6)
        local sc = sin(chi)
        if sc > 1e-3 then kx = 4 / 3 * (1 - cos(chi) - 1.8 * mu * mu) / sc end
        ky = -2 * mu
    end
    local npsi = (mu > 0.002) and NPSI or 1
    local CT, CQ, CHx, CHy, CMx, CMy = 0, 0, 0, 0, 0, 0
    for k = 1, npsi do
        local sp, cp = SPSI[k], CPSI[k]
        if npsi == 1 then sp, cp = 0, 0 end
        for i = 1, #G.st do
            local e = G.st[i]
            local x = e.x
            local ut = x + mu * sp
            local up = lc + li0 * (1 + kx * x * cp + ky * x * sp)
            local u2 = ut * ut + up * up
            local phi = atan2(up, ut)
            local cl, cd = airfoil(e.theta - phi)
            local F = 1
            local sphi = abs(sin(phi))
            if sphi > 1e-4 then
                local f = B / 2 * (1 - x) / (x * sphi)
                F = 2 / pi * acos(min(1, exp(-f)))
            end
            local cphi, sphi2 = cos(phi), sin(phi)
            local q = 0.5 * u2 * e.c * e.dr / piR2
            local dT = q * (cl * cphi - cd * sphi2) * F
            local dF = q * (cl * sphi2 + cd * cphi)
            CT = CT + dT
            CQ = CQ + dF * x
            CHx = CHx - dF * sp
            CHy = CHy + dF * cp
            CMx = CMx - x * sp * dT
            CMy = CMy + x * cp * dT
        end
    end
    local s = B / npsi
    return CT * s, CQ * s, CHx * s, CHy * s, CMx * s, CMy * s
end
Prop.sweep = sweep

local function axialInduced(lh, lc)
    local x = lc / lh
    if x >= 0 then return lh * (-x / 2 + sqrt(x * x / 4 + 1)) end
    if x >= -2 then
        return lh * (1 - 1.125 * x - 1.372 * x * x - 1.718 * x * x * x - 0.655 * x * x * x * x)
    end
    return lh * (-x / 2 - sqrt(x * x / 4 - 1))
end
Prop.axialInduced = axialInduced

local function momentumInduced(ct, mu, lc, guess)
    local li = guess
    for _ = 1, 30 do
        local l = lc + li
        local sq = sqrt(mu * mu + l * l)
        local f = li - ct / (2 * sq)
        local df = 1 + ct * l / (2 * sq * sq * sq)
        local nl = li - f / df
        if nl < 0 then nl = li * 0.5 end
        if abs(nl - li) < 1e-7 then li = nl break end
        li = nl
    end
    return li
end

function Prop.solve(G, mu, lc)
    local li = 0.05
    local CT, CQ, CHx, CHy, CMx, CMy
    for it = 1, 40 do
        CT, CQ, CHx, CHy, CMx, CMy = sweep(G, mu, lc, li)
        local ct = max(CT, 1e-6)
        local lh = sqrt(ct / 2)
        local axial = axialInduced(lh, lc)
        local mom = momentumInduced(ct, mu, lc, max(li, 1e-4))
        local w = min(1, mu / (1.5 * lh))
        local target = (1 - w) * axial + w * mom
        if lc >= 0 then target = mom end
        local nl = li + 0.45 * (target - li)
        if abs(nl - li) < 1e-6 then li = nl break end
        li = nl
    end
    CT, CQ, CHx, CHy, CMx, CMy = sweep(G, mu, lc, li)
    return CT, CQ, CHx, CHy, CMx, CMy, li
end

function Prop.build(quad)
    local G = Prop.geometry(quad, 10)
    local R = G.R
    local A = pi * R * R
    local T = {
        R = R, A = A,
        nmu = Prop.NMU, nlc = Prop.NLC,
        dmu = Prop.MU_MAX / (Prop.NMU - 1),
        dlc = (Prop.LC_MAX - Prop.LC_MIN) / (Prop.NLC - 1),
        ct = {}, cq = {}, chx = {}, chy = {}, cmx = {}, cmy = {}, li = {},
    }
    for i = 0, T.nmu - 1 do
        local mu = i * T.dmu
        local guessRow = {}
        for j = 0, T.nlc - 1 do
            local lc = Prop.LC_MIN + j * T.dlc
            local CT, CQ, CHx, CHy, CMx, CMy, li = Prop.solve(G, mu, lc)
            local k = i * T.nlc + j + 1
            T.ct[k], T.cq[k], T.chx[k], T.chy[k], T.cmx[k], T.cmy[k], T.li[k] = CT, CQ, CHx, CHy, CMx, CMy, li
        end
    end
    local j0 = floor((0 - Prop.LC_MIN) / T.dlc + 0.5)
    local k0 = j0 + 1
    local ctTarget = quad.kT / (RHO * A * R * R)
    local cqTarget = quad.kQ / (RHO * A * R * R * R)
    T.sT = ctTarget / T.ct[k0]
    T.sQ = cqTarget / T.cq[k0]
    local k1 = T.nlc + j0 + 1
    local slope = -T.chx[k1] / T.dmu
    local slopeTarget = (quad.kH or 4e-5) / (RHO * A * R)
    T.sH = (slope > 1e-9) and (slopeTarget / slope) or 1
    T.static = { ct = T.ct[k0], cq = T.cq[k0], li = T.li[k0] }
    return T
end

function Prop.lookup(T, mu, lc)
    local fi = mu / T.dmu
    if fi < 0 then fi = 0 elseif fi > T.nmu - 1.0001 then fi = T.nmu - 1.0001 end
    local fj = (lc - Prop.LC_MIN) / T.dlc
    if fj < 0 then fj = 0 elseif fj > T.nlc - 1.0001 then fj = T.nlc - 1.0001 end
    local i, j = floor(fi), floor(fj)
    local a, b = fi - i, fj - j
    local n = T.nlc
    local k00 = i * n + j + 1
    local k01, k10, k11 = k00 + 1, k00 + n, k00 + n + 1
    local w00, w01, w10, w11 = (1 - a) * (1 - b), (1 - a) * b, a * (1 - b), a * b
    local function L(t) return t[k00] * w00 + t[k01] * w01 + t[k10] * w10 + t[k11] * w11 end
    local sT, sH = T.sT, T.sH
    return L(T.ct) * sT, L(T.cq) * T.sQ, L(T.chx) * sH, L(T.chy) * sH, L(T.cmx) * sT, L(T.cmy) * sT, L(T.li)
end

local cache = {}
function Prop.get(quad)
    local key = string.format("%.5f/%.5f/%d/%.3e/%.3e/%.3e", quad.propD, quad.propPitch or 0, quad.propBlades or 3, quad.kT, quad.kQ, quad.kH or 0)
    local t = cache[key]
    if not t then
        t = Prop.build(quad)
        cache[key] = t
    end
    return t
end

return Prop
