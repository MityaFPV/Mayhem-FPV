local core = arg[1]
local outPath = arg[2]
local Presets = dofile(core .. "presets.lua")
local Model = dofile(core .. "model.lua")
local quad = Presets.get("mayhem_x5")
local parts = Model.build(quad, { propColor = arg[8] })

local spinning = arg[4] == "1"
local health = tonumber(arg[5] or "1")
local st = {
    uptilt = tonumber(arg[3] or "30"),
    propAng = { 0.3, 1.4, 2.2, 0.9 },
    motorW = spinning and { 2000, 2000, 2000, 2000 } or { 0, 0, 0, 0 },
    health = { health, 1, 1, 1 },
    hideCamera = arg[6] == "1",
    hideProps = arg[7] == "1",
}
local inst, n = Model.instances(quad, st)

local f = assert(io.open(outPath, "w"))
local tris = 0
for pname, mats in pairs(parts) do
    for mname, list in pairs(mats) do
        f:write("group ", pname, " ", mname, "\n")
        for i = 1, #list do
            local v = list[i]
            f:write(string.format("v %.6f %.6f %.6f %.4f %.4f %.4f %.4f %.4f\n", v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]))
        end
        tris = tris + #list / 3
    end
end
for i = 1, n do
    local t = inst[i]
    f:write(string.format("inst %s %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f\n",
        t.part, t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t.tx, t.ty, t.tz, t.sx))
end
for name, m in pairs(Model.MATERIALS) do
    f:write(string.format("mat %s %d %d %d %s\n", name, m.color[1], m.color[2], m.color[3], m.tex or "-"))
end
f:close()
print(string.format("unique triangles: %d, instances: %d", tris, n))
