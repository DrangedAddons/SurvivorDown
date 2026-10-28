-- SurvivorBeacon: marks where a party member went down so the others can find and revive them.
-- 1.12 has no call that turns a world position into a screen position, so the marker goes
-- where the client does give one: the minimap (from map coordinates) and the teammate's own
-- nameplate. Beacon.lua draws those, plus a call-out and a list with distance and direction.
--
-- Where someone went down comes from, best first:
--   1. their own SurvivorBeacon, which sends its map position to the party while it's down;
--   2. GetPlayerMapPosition on their party unit, if the game fills it in for party members.

SurvivorBeacon = {}
local SB = SurvivorBeacon
SB.version = GetAddOnMetadata and GetAddOnMetadata("SurvivorBeacon", "Version") or "?"

local PREFIX = "SBEACON"
local SEND_EVERY = 2 -- s between our own DOWN messages while we're down
local COMM_TIMEOUT = 8 -- s without a DOWN message before a teammate's own report counts as stale
local NO_ADDON_WAIT = 3 -- s after a teammate goes down before we skull them ourselves

SB.defaults = {
    alert = true, -- big "<name> is down" call-out
    sound = true, -- raid warning sound with the call-out
    minimap = true, -- pin on the minimap where they went down
    plate = true, -- beam over the downed teammate's nameplate
    friendPlates = true, -- turn friendly nameplates on while someone's down, so there's a plate to mark
    skull = true, -- skull raid icon on whoever is down
    list = true, -- the list of who's down, how far and which way
    listLocked = true,
    listX = nil, -- saved list position (offset from the bottom-left); nil = default
    listY = nil,
}
local KEEP_ON_RESET = { listX = true, listY = true }

-- Who's down, by name: { name, class, unit, mx, my, zone, since, src, comm, heard, test }.
-- `src` says where mx/my came from ("addon", "party" or "test"); `comm` true once their own
-- SurvivorBeacon has reported, `heard` when it last did.
SB.downs = {}

local db
local selfDown, lastSent = false, 0
local markedSelf = false
local marked = {} -- name -> true for teammates we put the skull on

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5050SurvivorBeacon:|r " .. msg)
end
SB.Print = Print

local function CharKey()
    local realm = GetRealmName and GetRealmName() or GetCVar("realmName") or "?"
    return (UnitName("player") or "?") .. " - " .. realm
end

local function LoadSettings()
    SurvivorBeaconDB = SurvivorBeaconDB or {}
    SurvivorBeaconDB.chars = SurvivorBeaconDB.chars or {}
    SurvivorBeaconDB.zones = SurvivorBeaconDB.zones or {}
    local key = CharKey()
    SurvivorBeaconDB.chars[key] = SurvivorBeaconDB.chars[key] or {}
    db = SurvivorBeaconDB.chars[key]
    for k, v in pairs(SB.defaults) do
        if db[k] == nil then db[k] = v end
    end
end

function SB.Get(key) return db and db[key] end

function SB.Set(key, value)
    db[key] = value
    if SB.Refresh then SB.Refresh() end
end

function SB.Reset()
    for k, v in pairs(SB.defaults) do
        if not KEEP_ON_RESET[k] then db[k] = v end
    end
    if SB.Refresh then SB.Refresh() end
end

---------------------------------------------------------------------------------------------
-- Map geometry

-- Zone sizes in yards (width east-west, height north-south) from the 1.12 world map data, for
-- when the run's lairs and chests can't be used to measure the zone.
local ZONE_YARDS = {
    ["Elwynn Forest"] = { 3470.83, 2314.58 },
    ["Westfall"] = { 3500, 2333.33 },
    ["Duskwood"] = { 2700, 1800 },
    ["Dun Morogh"] = { 4925, 3283.33 },
    ["Teldrassil"] = { 5091.67, 3393.75 },
    ["Durotar"] = { 5287.5, 3525 },
    ["Mulgore"] = { 5450, 3633.33 },
    ["Tirisfal Glades"] = { 4518.75, 3012.5 },
    ["The Barrens"] = { 10133.33, 6756.25 },
    ["Stranglethorn Vale"] = { 6381.25, 4254.17 },
}

-- The game's lair and chest lines carry each spot's world x/y and its map mx/my. Every pair of
-- spots gives d^2 = (W*dmx)^2 + (H*dmy)^2; least squares over all pairs solves W^2 and H^2.
-- Uses only distances, so it doesn't matter which way the world axes point.
local function Measure()
    local pts = {}
    local function Add(list)
        if type(list) ~= "table" then return end
        for i = 1, table.getn(list) do
            local p = list[i]
            if type(p.x) == "number" and type(p.y) == "number"
                and type(p.mx) == "number" and type(p.my) == "number" then
                local mx, my = p.mx, p.my
                if mx > 1.5 or my > 1.5 then mx, my = mx / 100, my / 100 end -- 0-100 scale
                table.insert(pts, { x = p.x, y = p.y, mx = mx, my = my })
            end
        end
    end
    Add(AZS_LAIRS)
    Add(AZS_CHESTS)
    local n = table.getn(pts)
    if n < 3 then return nil end
    local saa, sab, sbb, sad, sbd = 0, 0, 0, 0, 0
    for i = 1, n - 1 do
        for j = i + 1, n do
            local p, q = pts[i], pts[j]
            local a = (p.mx - q.mx) * (p.mx - q.mx)
            local b = (p.my - q.my) * (p.my - q.my)
            local d = (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)
            saa, sab, sbb = saa + a * a, sab + a * b, sbb + b * b
            sad, sbd = sad + a * d, sbd + b * d
        end
    end
    local det = saa * sbb - sab * sab
    if math.abs(det) < 1e-12 then return nil end
    local u = (sad * sbb - sab * sbd) / det
    local v = (saa * sbd - sab * sad) / det
    if u <= 0 or v <= 0 then return nil end
    local w, h = math.sqrt(u), math.sqrt(v)
    -- Every 1.12 zone map is 3:2. Far off that means the points don't fit the model.
    local ratio = w / h
    if ratio < 1.2 or ratio > 1.8 or w < 300 or w > 20000 then return nil end
    return w, h
end

local measuredZone, measuredAt = nil, 0

-- The current zone's size in yards and where it came from ("measured", "saved", "table"),
-- or nil.
function SB.ZoneSize()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local now = GetTime()
    if measuredZone ~= zone or now - measuredAt > 10 then
        measuredZone, measuredAt = zone, now
        local w, h = Measure()
        if w and zone ~= "" then SurvivorBeaconDB.zones[zone] = { w, h } end
    end
    local saved = SurvivorBeaconDB and SurvivorBeaconDB.zones[zone]
    if saved then return saved[1], saved[2], "measured" end
    local known = ZONE_YARDS[zone]
    if known then return known[1], known[2], "table" end
    return nil
end

function SB.PlayerPos()
    local x, y = GetPlayerMapPosition("player")
    if (not x or (x == 0 and y == 0)) and SetMapToCurrentZone then
        SetMapToCurrentZone()
        x, y = GetPlayerMapPosition("player")
    end
    if not x or (x == 0 and y == 0) then return nil end
    return x, y
end

-- Where a down is from here: yards east, yards north, and true if those are real yards. With
-- no zone size the result is only good for a direction (3:2 map, unit-less) and the third
-- value is false. nil when either position is unknown or they're in another zone.
function SB.Offset(d)
    if not d.mx then return nil end
    if d.zone and d.zone ~= "" and d.zone ~= (GetRealZoneText() or "") then return nil end
    local px, py = SB.PlayerPos()
    if not px then return nil end
    local dx, dy = d.mx - px, d.my - py
    local w, h = SB.ZoneSize()
    if w then return dx * w, -dy * h, true end
    return dx * 1.5, -dy, false
end

local COMPASS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
function SB.Compass(east, north)
    local deg = math.deg(math.atan2(north, east))
    local i = math.mod(math.floor((deg + 22.5) / 45) + 8, 8) + 1
    return COMPASS[i]
end

---------------------------------------------------------------------------------------------
-- Who's down

local function PartyUnit(name)
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitName(u) == name then return u end
    end
end

local function UnitDown(unit)
    if not UnitExists(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return true end
    local max = UnitHealthMax(unit)
    return max and max > 0 and UnitHealth(unit) <= 0 and UnitIsConnected(unit) and true or false
end

local function SelfIsDown()
    if UnitIsDeadOrGhost("player") then return true end
    -- Health reads 0 for a moment during loading screens, so only with a real maximum.
    local max = UnitHealthMax("player")
    if max and max > 0 and UnitHealth("player") <= 0 then return true end
    -- The game's revive line, while it's fresh: { down = 1 } while we wait for a revive.
    local r = AZS_REVIVE
    return type(r) == "table" and r.down == 1 and AZS_REVIVE_UPDATED
        and GetTime() - AZS_REVIVE_UPDATED < 10 or false
end

local function SetSkull(unit, on)
    if not SetRaidTarget or not GetRaidTargetIndex then return false end
    local have = GetRaidTargetIndex(unit)
    if on and have ~= 8 then
        return pcall(SetRaidTarget, unit, 8)
    elseif not on and have == 8 then
        return pcall(SetRaidTarget, unit, 0)
    end
    return false
end

local function Send(msg)
    if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
        local channel = GetNumRaidMembers() > 0 and "RAID" or "PARTY"
        pcall(SendAddonMessage, PREFIX, msg, channel)
    end
end

local function AddDown(name, fields)
    local d = SB.downs[name]
    local fresh = not d
    if fresh then
        d = { name = name, since = GetTime() }
        SB.downs[name] = d
    end
    for k, v in pairs(fields) do d[k] = v end
    if fresh and SB.OnDown then SB.OnDown(d) end
    return d
end

local function RemoveDown(name)
    local d = SB.downs[name]
    if not d then return end
    SB.downs[name] = nil
    if marked[name] then
        local u = PartyUnit(name)
        if u then SetSkull(u, false) end
        marked[name] = nil
    end
    if SB.OnUp and not d.test then SB.OnUp(d) end
end

local function UpdateSelf(now)
    local down = SelfIsDown()
    if down then
        if not selfDown then
            selfDown, lastSent = true, 0
            if db.skull then markedSelf = SetSkull("player", true) and true or false end
        end
        if now - lastSent >= SEND_EVERY then
            lastSent = now
            local x, y = SB.PlayerPos()
            if x then
                Send(string.format("DOWN:%.5f:%.5f:%s", x, y, GetRealZoneText() or ""))
            else
                Send("DOWN")
            end
        end
    elseif selfDown then
        selfDown = false
        Send("UP")
        if markedSelf then SetSkull("player", false) end
        markedSelf = false
    end
end

local function UpdateParty(now)
    local seen = {}
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local name = UnitName(u)
            seen[name] = true
            local d = SB.downs[name]
            if UnitDown(u) then
                local _, class = UnitClass(u)
                d = AddDown(name, { unit = u, class = class })
                if not d.comm then
                    local x, y = GetPlayerMapPosition(u)
                    if x and not (x == 0 and y == 0) then
                        d.mx, d.my, d.zone, d.src = x, y, GetRealZoneText(), "party"
                    end
                    if db.skull and not marked[name] and now - d.since >= NO_ADDON_WAIT then
                        marked[name] = SetSkull(u, true) and true or nil
                    end
                end
            elseif d and not d.test and (not d.comm or now - (d.heard or 0) > 1) then
                -- Their unit says they're up. Trust that over a DOWN message more than a
                -- second old, since UP can be lost.
                RemoveDown(name)
            end
        end
    end
    for name, d in pairs(SB.downs) do
        if d.test then
            if now > d.testEnds then RemoveDown(name) end
        elseif not seen[name] and (not d.comm or now - (d.heard or 0) > COMM_TIMEOUT) then
            RemoveDown(name)
        end
    end
end

local function OnAddonMessage(msg, sender)
    if sender == UnitName("player") then return end
    local _, _, cmd, rest = string.find(msg, "^(%u+):?(.*)$")
    if cmd == "DOWN" then
        local u = PartyUnit(sender)
        local class
        if u then _, class = UnitClass(u) end
        local fields = { unit = u, class = class, comm = true, heard = GetTime() }
        local _, _, x, y, zone = string.find(rest or "", "^([%d%.]+):([%d%.]+):?(.*)$")
        if x then
            fields.mx, fields.my, fields.zone, fields.src = tonumber(x), tonumber(y), zone, "addon"
        end
        AddDown(sender, fields)
        -- They skull themselves and clear it when they're up, so forget ours.
        marked[sender] = nil
    elseif cmd == "UP" then
        RemoveDown(sender)
    end
end

---------------------------------------------------------------------------------------------
-- Test

-- A pretend teammate down 40 yards north-east of you for 20 s. With a target, it takes the
-- target's name, so the nameplate beam shows on the target's plate.
function SB.Test()
    local x, y = SB.PlayerPos()
    if not x then
        Print("no map position for you here, so the minimap pin can't be placed. The call-out and list still show.")
    end
    local name = UnitExists("target") and UnitName("target") or "Test Hero"
    local w, h = SB.ZoneSize()
    local mx, my
    if x then
        if w then
            mx, my = x + 28 / w, y - 28 / h
        else
            mx, my = x + 0.006, y - 0.006
        end
    end
    local _, class = UnitClass("player")
    RemoveDown(name)
    AddDown(name, { class = class, mx = mx, my = my, zone = GetRealZoneText(), src = "test",
        test = true, testEnds = GetTime() + 20 })
    Print("test beacon on " .. name .. " for 20 s.")
end

---------------------------------------------------------------------------------------------
-- Status

local function Fmt(v)
    if v == nil then return "nil" end
    if type(v) == "number" then return string.format("%.4g", v) end
    return tostring(v)
end

function SB.Status()
    Print("version " .. SB.version)
    local zone = GetRealZoneText() or "?"
    local x, y = SB.PlayerPos()
    Print("zone: " .. zone .. ", you at " .. (x and string.format("%.4f, %.4f", x, y) or "no map position"))
    local w, h, src = SB.ZoneSize()
    if w then
        Print(string.format("zone size: %.0f x %.0f yd (%s)", w, h, src))
    else
        Print("zone size: unknown, so distances can't be shown and the minimap pin sits on the rim")
    end
    Print("minimap zoom: " .. Fmt(Minimap.GetZoom and Minimap:GetZoom()) .. ", "
        .. string.format("%.0f px across", Minimap:GetWidth() or 0))
    local n = 0
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            n = n + 1
            local px, py = GetPlayerMapPosition(u)
            Print(string.format("%s: %s, down %s, health %s/%s, map %s", u, UnitName(u) or "?",
                tostring(UnitDown(u)), Fmt(UnitHealth(u)), Fmt(UnitHealthMax(u)),
                (px and not (px == 0 and py == 0)) and string.format("%.4f, %.4f", px, py) or "none"))
        end
    end
    if n == 0 then Print("WoW party: none. Teammates must be in your party for SurvivorBeacon to see them.") end
    if type(AZS_PARTY) == "table" and table.getn(AZS_PARTY) > 0 then
        local names = ""
        for i = 1, table.getn(AZS_PARTY) do names = names .. " " .. Fmt(AZS_PARTY[i].name) end
        Print("game's coop list:" .. names)
    end
    if type(AZS_REVIVE) == "table" then
        local r = AZS_REVIVE
        Print(string.format("revive line: down=%s share=%s by=%s reviving=%s rshare=%s",
            Fmt(r.down), Fmt(r.share), Fmt(r.by), Fmt(r.reviving), Fmt(r.rshare)))
    end
    Print("friendly nameplates CVar: " .. Fmt(GetCVar("nameplateShowFriends")))
    local any = false
    for name, d in pairs(SB.downs) do
        any = true
        Print(string.format("down: %s via %s, map %s", name, Fmt(d.src),
            d.mx and string.format("%.4f, %.4f", d.mx, d.my) or "unknown"))
    end
    if not any then Print("nobody down") end
end

---------------------------------------------------------------------------------------------
-- Events and slash command

local TOGGLES = {
    alert = "call-out when someone goes down",
    sound = "sound with the call-out",
    minimap = "minimap pin",
    plate = "beam over the nameplate",
    friendplates = "turn friendly nameplates on while someone's down",
    skull = "skull icon on whoever is down",
    list = "list of who's down",
}
local TOGGLE_KEY = { friendplates = "friendPlates" }

local frame = CreateFrame("Frame", "SurvivorBeaconFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == "SurvivorBeacon" then
            LoadSettings()
            if SB.Refresh then SB.Refresh() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if SetMapToCurrentZone then SetMapToCurrentZone() end
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == PREFIX and db then OnAddonMessage(arg2 or "", arg4) end
    end
end)

local elapsed = 0
frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < 0.2 or not db then return end
    elapsed = 0
    local now = GetTime()
    UpdateSelf(now)
    UpdateParty(now)
    if SB.Tick then SB.Tick() end
end)

SLASH_SURVIVORBEACON1 = "/asb"
SLASH_SURVIVORBEACON2 = "/survivorbeacon"
SlashCmdList["SURVIVORBEACON"] = function(msg)
    local cmd = string.lower(msg or "")
    cmd = string.gsub(cmd, "^%s+", "")
    cmd = string.gsub(cmd, "%s+$", "")
    if cmd == "test" then
        SB.Test()
    elseif cmd == "status" then
        SB.Status()
    elseif cmd == "unlock" or cmd == "lock" then
        SB.Set("listLocked", cmd == "lock")
        Print(cmd == "lock" and "list locked." or "list unlocked: drag it by its title. /asb lock when done.")
    elseif cmd == "reset" then
        SB.Reset()
        Print("settings back to defaults.")
    elseif TOGGLES[cmd] then
        local key = TOGGLE_KEY[cmd] or cmd
        SB.Set(key, not db[key])
        Print(TOGGLES[cmd] .. ": " .. (db[key] and "on" or "off"))
    else
        Print("commands:")
        for k, text in pairs(TOGGLES) do
            local key = TOGGLE_KEY[k] or k
            Print(string.format("  /asb %s - %s (%s)", k, text, (db and db[key]) and "on" or "off"))
        end
        Print("  /asb unlock | lock - move the list")
        Print("  /asb test - a pretend teammate down 40 yd north-east for 20 s")
        Print("  /asb status - what the addon can see: party, positions, zone size")
        Print("  /asb reset - settings back to defaults")
    end
end
