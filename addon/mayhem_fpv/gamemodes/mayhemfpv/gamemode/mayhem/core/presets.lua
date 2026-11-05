local Presets = {}

local function buildContacts(a, propR, propZ)
    local pts = {}
    local function add(x, y, z, motor) pts[#pts + 1] = { x, y, z, motor } end
    local motors = { { -a, -a }, { a, -a }, { -a, a }, { a, a } }
    local diag = (a * math.sqrt(2) + propR) / (a * math.sqrt(2))
    for i, m in ipairs(motors) do
        local mx, my = m[1], m[2]
        add(mx, my, -0.016, nil)
        add(mx * diag, my * diag, propZ, i)
        add(mx + (mx > 0 and propR or -propR), my, propZ, i)
    end
    add(0.058, 0, -0.016)
    add(-0.066, 0, -0.016)
    add(0.060, 0, 0.012)
    add(0.028, 0, 0.060)
    add(-0.043, 0, 0.060)
    add(-0.008, 0.019, 0.045)
    add(-0.008, -0.019, 0.045)
    add(-0.083, 0.0105, 0.068)
    add(0, 0, 0.012)
    return pts
end

function Presets.mayhem_x5()
    local wheelbase = 0.245
    local a = wheelbase / 2 / math.sqrt(2)
    local propD = 5.1 * 0.0254
    local propR = propD / 2
    local p = {
        id = "mayhem_x5",
        name = "Mayhem X5",
        craftName = "MAYHEM X5",

        mass = 0.652,
        Ixx = 1.6e-3, Iyy = 1.7e-3, Izz = 2.8e-3,

        arm = a,
        propZ = 0.022,
        propD = propD,
        propPitch = 3.5 * 0.0254,
        propBlades = 3,
        motors = {
            { -a, -a, -1 },
            {  a, -a,  1 },
            { -a,  a,  1 },
            {  a,  a, -1 },
        },

        kT = 1.30e-6,
        kQ = 1.56e-8,
        zeroThrustFactor = 1.30,
        maxDescentGain = 1.35,

        kv = 1800,
        Rm = 0.12,
        I0 = 1.2,
        Jrot = 4.6e-6,
        iMax = 58,
        iMin = -45,
        idle = 0.055,

        cells = 6,
        capacity = 1400,
        R0 = 0.014,
        R1 = 0.009, tau1 = 4.0,
        auxCurrent = 0.5,
        packMass = 0.225,
        packHeatCap = 200,
        irHealth = 1.0,
        ambient = 20,

        CdA = { 0.0105, 0.0125, 0.034 },
        kH = 4.0e-5,
        angDrag = 1.5e-6,

        propwash = 1.0,
        phys = 2,
        cop = { -0.006, 0.0, 0.018 },
        imbalance = 1.0,
        gyroVib = 1.6,
        gyroNoise = 0.08,
        wakeGain = 1.6,
        propFragility = 1.0,
        vibTorque = 0.03,

        cam = { 0.057, 0.0, 0.010 },
        defaultUptilt = 30,

        contacts = buildContacts(a, propR, 0.019),
        restitution = 0.30,
        friction = 0.55,
    }
    return p
end

Presets.list = { "mayhem_x5" }

local REF_CELLS, REF_CAP, REF_MASS = 6, 1400, 0.225
Presets.PACK_HEALTH = { new = 1.0, used = 1.4, tired = 2.0 }

function Presets.applyBattery(q, cells, capacity, health)
    cells = cells or REF_CELLS
    capacity = capacity or REF_CAP
    local dry = q.mass - q.packMass
    local packMass = REF_MASS * (cells / REF_CELLS) * (capacity / REF_CAP)
    local base = q.baseInertia or { q.Ixx, q.Iyy, q.Izz, q.mass, q.packMass }
    q.baseInertia = base
    local dm = packMass - base[5]
    q.Ixx = base[1] + dm * 0.0016
    q.Iyy = base[2] + dm * 0.0020
    q.Izz = base[3] + dm * 0.0006
    q.mass = dry + packMass
    q.packMass = packMass
    q.cells = cells
    q.capacity = capacity
    local rScale = (cells / REF_CELLS) * (REF_CAP / capacity)
    q.R0 = 0.014 * rScale
    q.R1 = 0.009 * rScale
    q.packHeatCap = 900 * packMass
    q.irHealth = Presets.PACK_HEALTH[health or "new"] or 1.0
    return q
end

function Presets.get(id)
    local fn = Presets[id or "mayhem_x5"] or Presets.mayhem_x5
    return fn()
end

function Presets.defaultPids()
    return {
        roll  = { 45, 80, 35, 120 },
        pitch = { 47, 84, 39, 125 },
        yaw   = { 45, 80, 0, 120 },
    }
end

function Presets.defaultFcMisc()
    return {
        idle = 0.055,
        tpa_rate = 65,
        tpa_breakpoint = 1350,
        iterm_relax_cutoff = 15,
        pidsum_limit = 500,
        pidsum_limit_yaw = 400,
        gyro_lpf_hz = 250,
        dterm_lpf_hz = 110,
        gyro_lpf1_dyn_min_hz = 250,
        gyro_lpf1_dyn_max_hz = 500,
        gyro_lpf2_static_hz = 500,
        dterm_lpf1_dyn_min_hz = 75,
        dterm_lpf1_dyn_max_hz = 150,
        dterm_lpf2_static_hz = 150,
        anti_gravity_gain = 80,
        rpm_filter_harmonics = 3,
        output_delay_ms = 0.5,
        airmode_start = 0.25,
        crashflip_expo = 35,
        crash_recovery = "OFF",
        vbat_sag_compensation = 0,
        vbat_warning_cell_voltage = 350,
        vbat_min_cell_voltage = 330,
        vbat_full_cell_voltage = 410,
    }
end

return Presets
