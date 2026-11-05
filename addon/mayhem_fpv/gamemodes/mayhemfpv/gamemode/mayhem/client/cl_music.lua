local FPV = MayhemFPV

local Mu = {}
FPV.Music = Mu

local ROOT = "sound/mayhem_music/"
local USER = ROOT .. "user/"
local EXTS = { mp3 = true, ogg = true, wav = true }

Mu.tracks = {}
Mu.order = {}
Mu.pos = 0
Mu.channel = nil
Mu.paused = false
Mu.current = nil
Mu.import = nil

local function cfg() return FPV.Config.data.music end

Mu.TITLES = {
    ["vixel_amps.mp3"] = "Vixel - Amps", ["vixel_antigrav.mp3"] = "Vixel - Antigrav",
    ["vixel_armed.mp3"] = "Vixel - Armed", ["vixel_febreze.mp3"] = "Vixel - Febreze",
    ["vixel_flick.mp3"] = "Vixel - Flick", ["vixel_flux.mp3"] = "Vixel - Flux",
    ["vixel_gaps.mp3"] = "Vixel - Gaps", ["vixel_gatekeeper.mp3"] = "Vixel - Gatekeeper",
    ["vixel_helix.mp3"] = "Vixel - Helix", ["vixel_rssi.mp3"] = "Vixel - RSSI",
    ["vixel_tilted.mp3"] = "Vixel - Tilted", ["vixel_weightless.mp3"] = "Vixel - Weightless",
}

local function niceName(file)
    local n = string.gsub(file, "%.[%w]+$", "")
    n = string.gsub(n, "_", " ")
    return n
end

local function addFolder(dir, titles)
    local files = file.Find(dir .. "*", "GAME") or {}
    table.sort(files, function(a, b) return string.lower(a) < string.lower(b) end)
    for _, f in ipairs(files) do
        local ext = string.lower(string.match(f, "%.(%w+)$") or "")
        if EXTS[ext] then
            Mu.tracks[#Mu.tracks + 1] = { path = dir .. f, title = (titles and titles[f]) or niceName(f) }
        end
    end
end

local function shuffleOrder()
    local n = #Mu.tracks
    Mu.order = {}
    for i = 1, n do Mu.order[i] = i end
    if cfg().shuffle then
        for i = n, 2, -1 do
            local j = math.random(i)
            Mu.order[i], Mu.order[j] = Mu.order[j], Mu.order[i]
        end
    end
end

function Mu.Scan()
    local playing = Mu.current and Mu.current.path
    Mu.tracks = {}
    addFolder(ROOT, Mu.TITLES)
    local titles = {}
    local idx = file.Read(USER .. "index.txt", "GAME")
    if idx then
        for line in string.gmatch(idx, "[^\r\n]+") do
            local f, t = string.match(line, "^([^\t]+)\t(.+)$")
            if f then titles[f] = t end
        end
    end
    addFolder(USER, titles)
    shuffleOrder()
    Mu.pos = 0
    if playing then
        for p, i in ipairs(Mu.order) do
            if Mu.tracks[i].path == playing then Mu.pos = p end
        end
    end
    return #Mu.tracks
end

local note = { title = nil, t = -100 }
local function notify(title)
    if not cfg().notify then return end
    note.title, note.t = title, RealTime()
end

surface.CreateFont("MayhemMusicSmall", { font = "Roboto", size = 12, weight = 800, extended = true })
surface.CreateFont("MayhemMusicTitle", { font = "Roboto", size = 17, weight = 600, extended = true })

hook.Add("HUDPaint", "mayhem_music", function()
    if not note.title then return end
    local g = FPV.Config.data.game
    if g and g.cinematic then return end
    local age = RealTime() - note.t
    local HOLD, IN, OUT = 4.5, 0.35, 0.35
    if age > IN + HOLD + OUT then note.title = nil return end
    local k
    if age < IN then k = age / IN
    elseif age < IN + HOLD then k = 1
    else k = 1 - (age - IN - HOLD) / OUT end
    k = 1 - (1 - k) * (1 - k)

    surface.SetFont("MayhemMusicTitle")
    local tw = surface.GetTextSize(note.title)
    local w = math.Clamp(tw + 52, 220, math.floor(ScrW() * 0.4))
    local h = 52
    local x = ScrW() - (w + 18) * k
    local y = 22
    local a = 255 * k
    draw.RoundedBox(8, x, y, w, h, Color(16, 17, 21, 225 * k))
    draw.RoundedBox(1, x, y + 10, 3, h - 20, Color(255, 122, 40, a))
    local t = RealTime()
    for i = 0, 2 do
        local bh = 5 + 7 * math.abs(math.sin(t * (5 + i * 1.7) + i))
        draw.RoundedBox(1, x + 16 + i * 5, y + 30 - bh / 2 + 6, 3, bh, Color(255, 122, 40, a))
    end
    draw.SimpleText("NOW PLAYING", "MayhemMusicSmall", x + 38, y + 10, Color(150, 154, 165, a))
    local title = note.title
    if tw > w - 52 then
        while #title > 4 and surface.GetTextSize(title .. "...") > w - 52 do title = string.sub(title, 1, -2) end
        title = title .. "..."
    end
    draw.SimpleText(title, "MayhemMusicTitle", x + 38, y + 25, Color(236, 237, 242, a))
end)

local function stopChannel()
    if IsValid(Mu.channel) then Mu.channel:Stop() end
    Mu.channel = nil
end

local token = 0
local function playIndex(i)
    local tr = Mu.tracks[i]
    if not tr then return end
    stopChannel()
    token = token + 1
    local my = token
    Mu.current = tr
    Mu.paused = false
    Mu.loading = true
    sound.PlayFile(tr.path, "noplay", function(ch, errId, errName)
        if my ~= token then
            if IsValid(ch) then ch:Stop() end
            return
        end
        Mu.loading = false
        if not IsValid(ch) then
            Mu.failed = (Mu.failed or 0) + 1
            print("[Mayhem FPV] music: can't play " .. tr.path .. " (" .. tostring(errName or errId) .. ")")
            if Mu.failed < #Mu.tracks then Mu.Next(true) else Mu.userStopped = true end
            return
        end
        Mu.failed = 0
        Mu.channel = ch
        ch:SetVolume(cfg().volume or 0.5)
        ch:Play()
        local tags = ch.GetTagsID3 and ch:GetTagsID3()
        local title = tr.title
        if istable(tags) and tags.title and tags.title ~= "" and tags.artist and tags.artist ~= "" then
            title = tags.artist .. " - " .. tags.title
        end
        tr.shown = title
        notify(title)
    end)
end

function Mu.Next(auto)
    if #Mu.tracks == 0 then return end
    if #Mu.order ~= #Mu.tracks then shuffleOrder() end
    Mu.pos = Mu.pos + 1
    if Mu.pos > #Mu.order then
        if cfg().shuffle then shuffleOrder() end
        Mu.pos = 1
    end
    playIndex(Mu.order[Mu.pos])
end

function Mu.Prev()
    if #Mu.tracks == 0 then return end
    if IsValid(Mu.channel) and Mu.channel:GetTime() > 4 then
        Mu.channel:SetTime(0)
        return
    end
    Mu.pos = Mu.pos - 1
    if Mu.pos < 1 then Mu.pos = #Mu.order end
    playIndex(Mu.order[Mu.pos])
end

function Mu.PlayTrack(i)
    for p, idx in ipairs(Mu.order) do
        if idx == i then Mu.pos = p end
    end
    playIndex(i)
end

function Mu.Toggle()
    if not IsValid(Mu.channel) then
        if Mu.loading then return end
        Mu.Next()
        return
    end
    Mu.paused = not Mu.paused
    if Mu.paused then Mu.channel:Pause() else Mu.channel:Play() end
end

function Mu.Stop()
    token = token + 1
    stopChannel()
    Mu.current = nil
    Mu.loading = false
end

function Mu.Playing() return IsValid(Mu.channel) and not Mu.paused and Mu.channel:GetState() == GMOD_CHANNEL_PLAYING end

function Mu.SetVolume(v)
    cfg().volume = v
    if IsValid(Mu.channel) then Mu.channel:SetVolume(v) end
end

function Mu.Seek(frac)
    if not IsValid(Mu.channel) then return end
    local len = Mu.channel:GetLength()
    if len and len > 0 then Mu.channel:SetTime(math.Clamp(frac, 0, 0.999) * len) end
end

function Mu.Times()
    if not IsValid(Mu.channel) then return nil end
    return Mu.channel:GetTime() or 0, Mu.channel:GetLength() or 0
end

local function wanted()
    local c = cfg()
    if not c.enabled then return false end
    local flying = FPV.Flight and FPV.Flight.active
    if c.when == "flying" then return flying and true or false end
    if c.when == "foot" then return not flying end
    return true
end

local started = false
local startAt = nil
hook.Add("Think", "mayhem_music", function()
    if not FPV.Config or not FPV.Config.data then return end
    if not startAt then startAt = RealTime() + 2 end
    if RealTime() < startAt then return end
    if not started then
        started = true
        Mu.Scan()
    end
    local want = wanted()
    local ch = Mu.channel
    if not want then
        if IsValid(ch) and ch:GetState() == GMOD_CHANNEL_PLAYING then ch:Pause(); Mu.held = true end
        return
    end
    if IsValid(ch) then
        local st = ch:GetState()
        if Mu.held and st == GMOD_CHANNEL_PAUSED and not Mu.paused then ch:Play() end
        Mu.held = false
        if st == GMOD_CHANNEL_STOPPED and not Mu.paused then Mu.Next(true) end
    elseif not Mu.loading and not Mu.paused and #Mu.tracks > 0 and not Mu.userStopped then
        Mu.Next(true)
    end
end)

function Mu.CanImport()
    return FPV.Input.LoadModule() and fpvjoy and fpvjoy.MusicImport ~= nil
end

local function pollImport()
    if not fpvjoy or not fpvjoy.MusicStatus then return end
    local st, done, total, msg = fpvjoy.MusicStatus()
    Mu.import = { state = st, done = done, total = total, message = msg }
    if st == 1 then
        timer.Simple(0.25, pollImport)
        return
    end
    Mu.userStopped = false
    if st == 2 then
        Mu.Stop()
        Mu.userStopped = false
        Mu.Scan()
        if cfg().enabled then Mu.Next() end
    end
    if FPV.Menu and FPV.Menu.OnMusicChanged then FPV.Menu.OnMusicChanged() end
end

function Mu.ImportFolder(path)
    if not Mu.CanImport() or not path or path == "" then return false end
    cfg().folder = path
    FPV.Config.Save()
    Mu.Stop()
    Mu.userStopped = true
    local ok = fpvjoy.MusicImport(path)
    pollImport()
    return ok
end

function Mu.ChooseFolder()
    if not Mu.CanImport() or not fpvjoy.MusicPickFolder then return nil end
    local p = fpvjoy.MusicPickFolder()
    if p then Mu.ImportFolder(p) end
    return p
end

function Mu.ClearImported()
    if not Mu.CanImport() then return end
    Mu.Stop()
    fpvjoy.MusicClear()
    cfg().folder = ""
    FPV.Config.Save()
    Mu.Scan()
end

concommand.Add("mayhem_music_next", function() Mu.userStopped = false; Mu.Next() end)
concommand.Add("mayhem_music_prev", function() Mu.Prev() end)
concommand.Add("mayhem_music_toggle", function() Mu.userStopped = false; Mu.Toggle() end)
concommand.Add("mayhem_music_rescan", function() print("[Mayhem FPV] music: " .. Mu.Scan() .. " tracks") end)

return Mu
