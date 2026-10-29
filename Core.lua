-- SurvivorBeacon: marks where a party member went down so the others can find and revive them.
-- 1.12 has no call that turns a world position into a screen position, and the game gives
-- addons no world x/y/z for players, so the marker goes where the client does place things:
-- the minimap and the teammate's own nameplate. Beacon.lua draws those, plus a call-out and a
-- list with distance and direction.
--
-- Where someone went down comes from, best first:
--   1. a minimap ping: their SurvivorBeacon pings their own spot every few seconds while
--      they're down. The client keeps a ping fixed in the world and Minimap:GetPingPosition
--      gives it relative to you, so it needs no map coordinates (instances have none);
--   2. map coordinates their SurvivorBeacon sends to the party while it's down;
--   3. GetPlayerMapPosition on their party unit, if the game fills it in for party members.

SurvivorBeacon = {}
local SB = SurvivorBeacon
SB.version = GetAddOnMetadata and GetAddOnMetadata("SurvivorBeacon", "Version") or "?"

local PREFIX = "SBEACON"
local SEND_EVERY = 2 -- s between our own DOWN messages while we're down
local COMM_TIMEOUT = 8 -- s without a DOWN message before a teammate's own report counts as stale
local NO_ADDON_WAIT = 3 -- s after a teammate goes down before we skull them ourselves
local PING_EVERY = 3 -- s between our own minimap pings while we're down
local PING_STALE = 10 -- s after a down's last ping before it no longer counts
-- 1.12 outdoor minimap radius in yards for each zoom level.
local MINIMAP_YARDS = { 233.33, 200, 166.67, 133.33, 100, 66.67 }

SB.defaults = {
    alert = true, -- big "<name> is down" call-out
    sound = true, -- raid warning sound with the call-out
    minimap = true, -- pin on the minimap where they went down
    plate = true, -- beam over the downed teammate's nameplate
    friendPlates = true, -- turn friendly nameplates on while someone's down, so there's a plate to mark
    skull = true, -- skull raid icon on whoever is down
    list = true, -- the list of who's down, how far and which way
    arrow = true, -- an arrow beside each list row pointing at them
    listLocked = true,
    listX = nil, -- saved list position (offset from the bottom-left); nil = default
    listY = nil,
    -- Minimap button (Reset to defaults leaves these alone)
    minimapButton = true,
    minimapAngle = 200, -- degrees around the minimap, 0 = right
}
local KEEP_ON_RESET = { listX = true, listY = true, minimapButton = true, minimapAngle = true }

-- Who's down, by name: { name, class, unit, mx, my, zone, since, src, comm, heard, test }.
-- `src` says where mx/my came from ("addon", "party" or "test"); `comm` true once their own
-- SurvivorBeacon has reported, `heard` when it last did.
SB.downs = {}

local db
local selfDown, lastSent, lastPing = false, 0, 0
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

-- Saves without a refresh, for values nothing else depends on.
function SB.SetQuiet(key, value) db[key] = value end

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

function SB.MinimapRadiusYards()
    return MINIMAP_YARDS[(Minimap.GetZoom and Minimap:GetZoom() or 0) + 1] or MINIMAP_YARDS[1]
end

-- name -> GetTime() of their last minimap ping. SB.pinger is whoever pinged last: the client
-- keeps only one ping, so only theirs can be read live.
local pings = {}
SB.pinger = nil

-- The current ping in yards east and north of you. 1.12 gives GetPingPosition as a fraction of
-- the minimap's width; values far past that are taken as pixels, in case this client differs.
local function PingYards()
    if not Minimap.GetPingPosition then return nil end
    local x, y = Minimap:GetPingPosition()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if math.abs(x) > 1.5 or math.abs(y) > 1.5 then
        local width = Minimap:GetWidth() or 140
        x, y = x / width, y / width
    end
    local diameter = 2 * SB.MinimapRadiusYards()
    return x * diameter, y * diameter
end
SB.PingYards = PingYards

---------------------------------------------------------------------------------------------
-- Where you've walked and which way you face, for the list's arrows

-- Your position in yards from wherever tracking started. From map coordinates when there are
-- some, else from the live minimap ping: a ping stays put in the world, so however its offset
-- changes is how you moved. walkEpoch goes up whenever neither is available, since positions
-- remembered before that no longer line up.
local walkE, walkN, walkEpoch = 0, 0, 0
local walkRef, refE, refN -- what the last sample came from ("map" or a pinger's name) and where
local headE, headN = 0, 0 -- walk position at the last heading update
local HEADING_STEP = 1.5 -- yd you have to move before the heading updates
local MAP_JUMP = 30 -- yd in one frame on the map means a zone change or a teleport, not a step
SB.heading = nil -- radians, 0 = north, counter-clockwise: which way you last moved

local function PingRef()
    local name = SB.pinger
    local d = name and SB.downs[name]
    if not d or not pings[name] then return nil end
    if not d.test and GetTime() - pings[name] >= PING_STALE then return nil end
    local e, n = PingYards()
    if e then return name, -e, -n end
end

-- Every frame while someone's down.
local function TrackWalk()
    local ref, e, n
    -- Not SB.PlayerPos: that calls SetMapToCurrentZone, too much for every frame.
    local x, y = GetPlayerMapPosition("player")
    local w, h = SB.ZoneSize()
    if x and not (x == 0 and y == 0) and w then
        ref, e, n = "map", x * w, -y * h
    else
        ref, e, n = PingRef()
    end
    if not ref then
        if walkRef then walkEpoch = walkEpoch + 1 end
        walkRef = nil
        return
    end
    if ref == walkRef then
        local dE, dN = e - refE, n - refN
        if ref == "map" and dE * dE + dN * dN > MAP_JUMP * MAP_JUMP then
            walkEpoch = walkEpoch + 1
            headE, headN = walkE, walkN
        else
            walkE, walkN = walkE + dE, walkN + dN
        end
    end
    -- A new reference costs one frame of movement; positions still line up.
    walkRef, refE, refN = ref, e, n
    local mE, mN = walkE - headE, walkN - headN
    if mE * mE + mN * mN >= HEADING_STEP * HEADING_STEP then
        SB.heading = math.atan2(-mE, mN)
        headE, headN = walkE, walkN
    end
end

-- The minimap's player arrow, if this client gives it to addons as a Model. Only trusted once
-- its facing has changed, since a model nobody turns reports 0 forever.
local arrowModel, modelSearched, modelFirst, modelLive

local function ArrowModel()
    if modelSearched then return arrowModel end
    modelSearched = true
    local kids = { Minimap:GetChildren() }
    for i = 1, table.getn(kids) do
        local f = kids[i]
        if f.GetObjectType and f:GetObjectType() == "Model" and f.GetFacing and f.GetModel then
            local ok, m = pcall(f.GetModel, f)
            if ok and string.find(string.lower(tostring(m)), "minimaparrow", 1, true) then
                arrowModel = f
            end
        end
    end
    return arrowModel
end

-- Which way you face: radians, 0 = north, counter-clockwise, and where that came from. nil
-- until there's a source.
function SB.Facing()
    local m = ArrowModel()
    if m then
        local ok, f = pcall(m.GetFacing, m)
        if ok and type(f) == "number" then
            if modelFirst == nil then
                modelFirst = f
            elseif f ~= modelFirst then
                modelLive = true
            end
            if modelLive then return f, "minimap arrow" end
        end
    end
    if SB.heading then return SB.heading, "movement" end
end

function SB.FacingInfo()
    return ArrowModel() and (modelLive and "live" or "found, not turning yet") or "none", walkRef
end

-- Where a down is from here: yards east, yards north, and true if those are real yards. With
-- no zone size the result is only good for a direction (3:2 map, unit-less) and the third
-- value is false. nil when either position is unknown or they're in another zone.
function SB.Offset(d)
    if d.testOf then
        -- An extra pretend down from /asb test N: a fixed step from the first one.
        local base = SB.downs[d.testOf]
        local e, n, yards = nil, nil, nil
        if base then e, n, yards = SB.Offset(base) end
        if not e then return nil end
        return e + d.testE, n + d.testN, yards
    end
    local pinged = pings[d.name]
    if pinged and (d.test or GetTime() - pinged < PING_STALE) then
        if d.name == SB.pinger then
            -- Theirs is the last ping, so it can be read live.
            local e, n = PingYards()
            if e then
                d.pe, d.pn, d.src = e, n, "ping"
                d.wE, d.wN, d.wEpoch = walkE + e, walkN + n, walkEpoch
            end
        elseif d.wE and d.wEpoch == walkEpoch then
            -- Someone else has pinged since: follow how far you've walked from that spot.
            d.pe, d.pn = d.wE - walkE, d.wN - walkN
        end
        if d.pe then return d.pe, d.pn, true end
    end
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

-- /asb debug: every step of a down, a ping and a message, in chat. Not saved.
SB.debug = false
local function Debug(msg)
    if SB.debug then Print("|cff88ccff[debug]|r " .. msg) end
end

local function Send(msg)
    if GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
        local channel = GetNumRaidMembers() > 0 and "RAID" or "PARTY"
        local ok, err = pcall(SendAddonMessage, PREFIX, msg, channel)
        Debug("sent " .. msg .. " to " .. channel .. (ok and "" or (" - failed: " .. tostring(err))))
    else
        Debug("not in a party, so " .. msg .. " wasn't sent")
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
            selfDown, lastSent, lastPing = true, 0, 0
            if db.skull then markedSelf = SetSkull("player", true) and true or false end
            local r = type(AZS_REVIVE) == "table" and AZS_REVIVE or {}
            Debug(string.format("you're down: dead %s, health %s/%s, revive line down=%s",
                tostring(UnitIsDeadOrGhost("player")), tostring(UnitHealth("player")),
                tostring(UnitHealthMax("player")), tostring(r.down)))
        end
        if now - lastPing >= PING_EVERY then
            lastPing = now
            if Minimap.PingLocation then
                local ok, err = pcall(Minimap.PingLocation, Minimap, 0, 0) -- our own spot, for the party
                Debug("pinged your spot" .. (ok and "" or (" - failed: " .. tostring(err))))
            else
                Debug("can't ping: no Minimap:PingLocation")
            end
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
        Debug("you're up")
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

-- MINIMAP_PING: in 1.12 arg1 is the unit that pinged; this client may give a name or nothing.
-- Our own pings are ignored; Test sets its own.
local function OnPing(who, a2, a3)
    local px, py
    if Minimap.GetPingPosition then px, py = Minimap:GetPingPosition() end
    Debug(string.format("MINIMAP_PING arg1=%s arg2=%s arg3=%s, ping at %s, %s", tostring(who),
        tostring(a2), tostring(a3), tostring(px), tostring(py)))
    local name
    if who and UnitExists(who) then
        if UnitIsUnit(who, "player") then return end
        name = UnitName(who)
    elseif who and who ~= UnitName("player") and PartyUnit(who) then
        name = who
    end
    if not name then
        -- No usable sender: if exactly one teammate's SurvivorBeacon says they're down, it's theirs.
        local only, count = nil, 0
        for n, d in pairs(SB.downs) do
            if d.comm then only, count = n, count + 1 end
        end
        if count == 1 then name = only end
    end
    if not name then
        Debug("  couldn't tell whose ping that was")
        return
    end
    Debug("  ping is " .. name .. "'s")
    SB.pinger = name
    pings[name] = GetTime()
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

-- A pretend teammate down where you stand, for 30 s, placed with a minimap ping the same way a
-- real one is: walk away and the list and minimap pin should stay on that spot. With a target,
-- it takes the target's name, so the nameplate beam shows on the target's plate. The ping
-- shows on your party's minimaps too.
--
-- With a count (up to 4 more, a full party of 5 being you and 4 down), the extra ones lie at
-- fixed spots around the first, so the list fills up and each arrow points its own way.
local TEST_SECS = 30
local TEST_EXTRA = {
    { "MAGE", 25, 0 }, { "PRIEST", 0, -30 }, { "ROGUE", -20, 20 }, { "HUNTER", 40, 40 },
}
function SB.Test(count)
    local name = UnitExists("target") and UnitName("target") or "Test Hero"
    local _, class = UnitClass("player")
    RemoveDown(name)
    local fields = { class = class, zone = GetRealZoneText(), src = "test", test = true,
        testEnds = GetTime() + TEST_SECS }
    count = math.min(math.max(count or 1, 1), table.getn(TEST_EXTRA) + 1)
    for i = 1, table.getn(TEST_EXTRA) do RemoveDown("Test Hero " .. (i + 1)) end
    local pinged = Minimap.PingLocation and pcall(Minimap.PingLocation, Minimap, 0, 0)
    if pinged then
        SB.pinger = name
        pings[name] = GetTime()
    else
        local x, y = SB.PlayerPos()
        fields.mx, fields.my = x, y
        if not x then
            Print("no minimap ping or map position here, so the test can't be placed. The call-out and list still show.")
        end
    end
    AddDown(name, fields)
    for i = 1, count - 1 do
        local x = TEST_EXTRA[i]
        -- `since` a hair apart so they list in this order.
        AddDown("Test Hero " .. (i + 1), { class = x[1], src = "test", test = true,
            testOf = name, testE = x[2], testN = x[3], since = GetTime() + i * 0.001,
            testEnds = GetTime() + TEST_SECS })
    end
    Print("test: " .. name .. (count > 1 and (" and " .. (count - 1) .. " more") or "")
        .. " down for " .. TEST_SECS .. " s. Walk away and the list and minimap pin should stay put.")
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
            local plate = SB.FindPlate and SB.FindPlate(UnitName(u) or "")
            Print(string.format("%s: %s, down %s, health %s/%s, map %s, nameplate %s", u,
                UnitName(u) or "?", tostring(UnitDown(u)), Fmt(UnitHealth(u)), Fmt(UnitHealthMax(u)),
                (px and not (px == 0 and py == 0)) and string.format("%.4f, %.4f", px, py) or "none",
                plate and "found" or "none"))
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
    if Minimap.GetPingPosition then
        local px, py = Minimap:GetPingPosition()
        local e, n = PingYards()
        Print(string.format("minimap ping: raw %s, %s = %s yd east, %s yd north; last from %s",
            Fmt(px), Fmt(py), Fmt(e), Fmt(n), Fmt(SB.pinger)))
    else
        Print("minimap ping: no GetPingPosition")
    end
    local facing, fsrc = SB.Facing()
    local model, ref = SB.FacingInfo()
    Print(string.format("facing: %s (%s); minimap arrow model %s; tracking movement by %s",
        facing and string.format("%.0f deg", math.deg(facing)) or "unknown", Fmt(fsrc), model,
        Fmt(ref)))
    local on = SB.FriendPlatesOn and SB.FriendPlatesOn()
    Print("friendly nameplates: " .. (on == nil and "unknown (no CVar)" or (on and "on" or "off")))
    local rx, ry = GetPlayerMapPosition("player")
    Print("raw map position: " .. Fmt(rx) .. ", " .. Fmt(ry))
    -- Looking for any other place the game puts where we are.
    local function Keys(label, t)
        if type(t) ~= "table" then return end
        local s = ""
        for k, v in pairs(t) do
            if type(v) ~= "table" then s = s .. " " .. tostring(k) .. "=" .. Fmt(v) end
        end
        Print(label .. ":" .. (s ~= "" and s or " empty"))
    end
    Keys("run line", AZS_RUN)
    Keys("zone line", AZS_ZONE)
    for _, l in ipairs({ { "lairs", AZS_LAIRS }, { "chests", AZS_CHESTS } }) do
        local t = l[2]
        if type(t) == "table" then
            Print(l[1] .. ": " .. table.getn(t))
            if t[1] then Keys("  first", t[1]) end
        end
    end
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
    arrow = "arrow beside the list pointing at each",
    button = "minimap button",
}
local TOGGLE_KEY = { friendplates = "friendPlates", button = "minimapButton" }

local frame = CreateFrame("Frame", "SurvivorBeaconFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("MINIMAP_PING")
frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == "SurvivorBeacon" then
            LoadSettings()
            if SB.Refresh then SB.Refresh() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if SetMapToCurrentZone then SetMapToCurrentZone() end
    elseif event == "MINIMAP_PING" then
        OnPing(arg1, arg2, arg3)
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == PREFIX and db then
            Debug("heard " .. tostring(arg2) .. " from " .. tostring(arg4) .. " on " .. tostring(arg3))
            OnAddonMessage(arg2 or "", arg4)
        end
    end
end)

local elapsed = 0
frame:SetScript("OnUpdate", function()
    if db and next(SB.downs) then
        TrackWalk()
    elseif walkRef then
        walkRef, walkEpoch = nil, walkEpoch + 1
    end
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
    if cmd == "" then
        SB.ToggleOptions()
    elseif string.find(cmd, "^test") then
        local _, _, count = string.find(cmd, "^test%s+(%d)$")
        SB.Test(tonumber(count))
    elseif cmd == "status" then
        SB.Status()
    elseif cmd == "unlock" or cmd == "lock" then
        SB.Set("listLocked", cmd == "lock")
        Print(cmd == "lock" and "list locked." or "list unlocked: drag it by its title. /asb lock when done.")
    elseif cmd == "debug" then
        SB.debug = not SB.debug
        Print("debug " .. (SB.debug and "on: downs, pings and messages show in chat." or "off."))
    elseif cmd == "reset" then
        SB.Reset()
        Print("settings back to defaults.")
    elseif TOGGLES[cmd] then
        local key = TOGGLE_KEY[cmd] or cmd
        SB.Set(key, not db[key])
        Print(TOGGLES[cmd] .. ": " .. (db[key] and "on" or "off"))
    else
        Print("commands:")
        Print("  /asb - open or close the settings")
        for k, text in pairs(TOGGLES) do
            local key = TOGGLE_KEY[k] or k
            Print(string.format("  /asb %s - %s (%s)", k, text, (db and db[key]) and "on" or "off"))
        end
        Print("  /asb unlock | lock - move the list")
        Print("  /asb test [2-5] - a pretend teammate down where you stand for 30 s (or that many)")
        Print("  /asb status - what the addon can see: party, positions, zone size")
        Print("  /asb debug - show every down, ping and message in chat")
        Print("  /asb reset - settings back to defaults")
    end
end
