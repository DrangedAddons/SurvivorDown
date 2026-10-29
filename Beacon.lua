-- What SurvivorBeacon draws: the call-out, the minimap pins, the beam over a downed teammate's
-- nameplate, and the list with an arrow per row. Core.lua decides who's down and where.
local SB = SurvivorBeacon

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
-- Gold, black-edged, points up, and kept inside the circle it turns in. tools/make_arrow.py
-- draws it.
local ARROW = "Interface\\AddOns\\SurvivorBeacon\\Arrow"
-- The arrow reaches 27/64 of this from the centre at any angle (about 14 px), which keeps it
-- inside its 30 px column.
local ARROW_SIZE = 34
local FONT = "Fonts\\FRIZQT__.TTF"
local BEAM_DROP = 100 -- px from the nameplate down to about the feet, at the game's camera distance

local function SkullTexture(tex)
    tex:SetTexture(SKULL)
    tex:SetTexCoord(0.75, 1, 0.25, 0.5)
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 0.3, 0.3
end

local function Pulse(period)
    return math.mod(GetTime(), period) / period
end

-- Turns `tex` `a` radians counter-clockwise on screen. Each corner (x right, y up, from the
-- centre) shows the image at that corner turned back by `a`. Corners that land outside the
-- image show its transparent edge.
local function Rotate(tex, a)
    local c, s = math.cos(a), math.sin(a)
    local function At(x, y)
        return 0.5 + x * c + y * s, 0.5 + x * s - y * c
    end
    local ulx, uly = At(-0.5, 0.5)
    local llx, lly = At(-0.5, -0.5)
    local urx, ury = At(0.5, 0.5)
    local lrx, lry = At(0.5, -0.5)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

---------------------------------------------------------------------------------------------
-- Call-out

local alert = CreateFrame("Frame", nil, UIParent)
alert:SetFrameStrata("HIGH")
alert:SetWidth(700)
alert:SetHeight(50)
alert:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
alert:Hide()
local alertText = alert:CreateFontString(nil, "OVERLAY")
alertText:SetFont(FONT, 30, "THICKOUTLINE")
alertText:SetAllPoints(alert)
local alertShown, alertHold = 0, 0
alert:SetScript("OnUpdate", function()
    local t = GetTime() - alertShown
    if t > alertHold + 1 then
        this:Hide()
    elseif t > alertHold then
        this:SetAlpha(alertHold + 1 - t)
    end
end)

local function ShowAlert(text, r, g, b, hold)
    alertText:SetText(text)
    alertText:SetTextColor(r, g, b)
    alertShown, alertHold = GetTime(), hold
    alert:SetAlpha(1)
    alert:Show()
end

function SB.OnDown(d)
    if SB.Get("alert") then
        local r, g, b = ClassColor(d.class)
        ShowAlert(d.name .. " is down!", r, g, b, 3)
    end
    if SB.Get("sound") then PlaySound("RaidWarning") end
    SB.Tick()
end

function SB.OnUp(d)
    if SB.Get("alert") then ShowAlert(d.name .. " is back up", 0.3, 1, 0.3, 1.5) end
    SB.Tick()
end

---------------------------------------------------------------------------------------------
-- Minimap pins

local pins = {} -- name -> pin

local function GetPin(name)
    local p = pins[name]
    if p then return p end
    p = CreateFrame("Button", nil, Minimap)
    p:SetWidth(18)
    p:SetHeight(18)
    p:SetFrameLevel(Minimap:GetFrameLevel() + 30)
    p.glow = p:CreateTexture(nil, "BACKGROUND")
    p.glow:SetTexture(GLOW)
    p.glow:SetBlendMode("ADD")
    p.glow:SetVertexColor(1, 0.15, 0.1)
    p.glow:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    SkullTexture(p.icon)
    p.icon:SetAllPoints(p)
    p.name = name
    p:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText(this.name .. " is down")
        if this.info then GameTooltip:AddLine(this.info, 1, 1, 1) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[name] = p
    return p
end

-- Distance text and minimap spot for a down; nil spot when there's no position to use.
local function Locate(d)
    local east, north, yards = SB.Offset(d)
    if not east then
        if d.mx and d.zone and d.zone ~= (GetRealZoneText() or "") then return "in " .. d.zone end
        -- Which link is missing: their SurvivorBeacon's message, or its ping.
        if d.comm then return "no ping yet" end
        return "nothing from their addon"
    end
    local dir = SB.Compass(east, north)
    if not yards then return dir, east, north, false end
    local dist = math.sqrt(east * east + north * north)
    if dist < 4 then return "here", east, north, true end
    return string.format("%d yd %s", dist, dir), east, north, true
end

local function PlacePin(p, east, north, yards)
    local radius = (Minimap:GetWidth() or 140) / 2
    local px, py
    if yards then
        local scale = radius / SB.MinimapRadiusYards()
        px, py = east * scale, north * scale
    else
        px, py = east * 1e6, north * 1e6 -- direction only: always on the rim
    end
    local dist = math.sqrt(px * px + py * py)
    local rim = radius - 8
    local onRim = dist > rim
    if onRim then px, py = px / dist * rim, py / dist * rim end
    p:ClearAllPoints()
    p:SetPoint("CENTER", Minimap, "CENTER", px, py)
    p:SetAlpha(onRim and 0.75 or 1)
end

---------------------------------------------------------------------------------------------
-- Nameplate beam

local beams = {} -- name -> beam

local function GetBeam(name)
    local b = beams[name]
    if b then return b end
    b = CreateFrame("Frame", nil, UIParent)
    b:SetFrameStrata("BACKGROUND")
    b:SetWidth(1)
    b:SetHeight(1)
    b.halo = b:CreateTexture(nil, "BACKGROUND")
    b.halo:SetTexture(1, 0.2, 0.1, 0.18)
    b.halo:SetWidth(22)
    b.halo:SetHeight(BEAM_DROP + 34)
    b.halo:SetPoint("TOP", b, "CENTER", 0, 34)
    b.core = b:CreateTexture(nil, "BORDER")
    b.core:SetTexture(1, 0.35, 0.2, 0.6)
    b.core:SetWidth(5)
    b.core:SetHeight(BEAM_DROP + 34)
    b.core:SetPoint("TOP", b, "CENTER", 0, 34)
    b.ring = b:CreateTexture(nil, "ARTWORK")
    b.ring:SetTexture(GLOW)
    b.ring:SetBlendMode("ADD")
    b.ring:SetVertexColor(1, 0.15, 0.1)
    b.ring:SetPoint("CENTER", b, "CENTER", 0, -BEAM_DROP)
    b.skull = b:CreateTexture(nil, "OVERLAY")
    SkullTexture(b.skull)
    b.skull:SetWidth(36)
    b.skull:SetHeight(36)
    b.skull:SetPoint("BOTTOM", b, "CENTER", 0, 34)
    b:Hide()
    beams[name] = b
    return b
end

-- The shown nameplate whose name text is `name`.
local function FindPlate(name)
    local kids = { WorldFrame:GetChildren() }
    for i = 1, table.getn(kids) do
        local f = kids[i]
        if f:IsShown() and f.GetRegions and not f:GetName() then
            local regions = { f:GetRegions() }
            for j = 1, table.getn(regions) do
                local r = regions[j]
                if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == name then
                    return f
                end
            end
        end
    end
end

SB.FindPlate = FindPlate

-- The game has no nameplateShowFriends CVar (GetCVar errors), so there's no telling whether
-- friendly plates were already on. nil when unknown.
local function FriendPlatesOn()
    local ok, v = pcall(GetCVar, "nameplateShowFriends")
    if ok then return v == "1" end
end
SB.FriendPlatesOn = FriendPlatesOn

-- Friendly nameplates are what the beam hangs on. Turned on while someone's down unless known
-- to be on already, and back off once nobody's down.
local friendsOn = false
local function FriendPlates(want)
    if want and not friendsOn then
        if not FriendPlatesOn() and ShowFriendNameplates then
            pcall(ShowFriendNameplates)
            friendsOn = true
        end
    elseif not want and friendsOn then
        if HideFriendNameplates then pcall(HideFriendNameplates) end
        friendsOn = false
    end
end

---------------------------------------------------------------------------------------------
-- List

local list = CreateFrame("Frame", "SurvivorBeaconList", UIParent)
list:SetWidth(230)
list:SetHeight(30)
list:SetFrameStrata("MEDIUM")
list:SetMovable(true)
list:SetClampedToScreen(true)
list:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
list:SetBackdropColor(0, 0, 0, 0.7)
list:SetBackdropBorderColor(0.8, 0.2, 0.15, 1)
list:Hide()
list.title = list:CreateFontString(nil, "OVERLAY")
list.title:SetFont(FONT, 11, "OUTLINE")
list.title:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -6)
list.title:SetTextColor(1, 0.35, 0.3)
list.title:SetText("Down")
list:RegisterForDrag("LeftButton")
list:SetScript("OnDragStart", function()
    if not SB.Get("listLocked") then this:StartMoving() end
end)
list:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    SB.Set("listX", this:GetLeft())
    SB.Set("listY", this:GetTop())
end)

local rows = {}
local ROW_H = 26
local ROW_GAP = 3
local LIST_PAD = 8 -- inside the border, left and right of the rows and below the last
local LIST_TOP = 22 -- title height
local ARROW_COL = 30 -- the arrow's column at the right of each row

local function ListHeight(n)
    return LIST_TOP + n * (ROW_H + ROW_GAP) - ROW_GAP + LIST_PAD
end

local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    local y = -LIST_TOP - (i - 1) * (ROW_H + ROW_GAP)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_PAD, y)
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_PAD, y)
    -- Each row is its own band with a stripe in their class colour, so rows don't run together.
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetTexture(0.55, 0.1, 0.08, 0.35)
    r.bg:SetAllPoints(r)
    r.stripe = r:CreateTexture(nil, "BORDER")
    r.stripe:SetTexture(1, 1, 1, 1)
    r.stripe:SetWidth(3)
    r.stripe:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.stripe:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    SkullTexture(r.icon)
    r.icon:SetWidth(16)
    r.icon:SetHeight(16)
    r.icon:SetPoint("LEFT", r, "LEFT", 7, 0)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(FONT, 13, "OUTLINE")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.info = r:CreateFontString(nil, "OVERLAY")
    r.info:SetFont(FONT, 13, "OUTLINE")
    -- Centred in its own column at the row's right end, so it never reaches the border; the
    -- distance moves left of the column while arrows are on.
    r.arrow = r:CreateTexture(nil, "OVERLAY")
    r.arrow:SetTexture(ARROW)
    r.arrow:SetWidth(ARROW_SIZE)
    r.arrow:SetHeight(ARROW_SIZE)
    r.arrow:SetPoint("CENTER", r, "RIGHT", -ARROW_COL / 2, 0)
    r.arrow:Hide()
    r:SetScript("OnClick", function()
        if this.unit and UnitExists(this.unit) then
            TargetUnit(this.unit)
        elseif this.down then
            TargetByName(this.down, true)
        end
    end)
    rows[i] = r
    return r
end

local function PlaceList()
    list:ClearAllPoints()
    local x, y = SB.Get("listX"), SB.Get("listY")
    if x and y then
        list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        list:SetPoint("TOP", UIParent, "CENTER", 0, -120)
    end
    list:EnableMouse(not SB.Get("listLocked"))
end

---------------------------------------------------------------------------------------------
-- Update

-- Downs in the order they went down.
local function Sorted()
    local out = {}
    for _, d in pairs(SB.downs) do table.insert(out, d) end
    table.sort(out, function(a, b) return a.since < b.since end)
    return out
end

-- The row's arrow, turned toward its down. Hidden with no direction, no facing, or once
-- you're on top of them.
local function PointArrow(r)
    local d = r.down and SB.downs[r.down]
    local east, north
    if d and SB.Get("arrow") then east, north = SB.Offset(d) end
    local facing = east and SB.Facing()
    if not facing or east * east + north * north < 16 then
        r.arrow:Hide()
        return
    end
    -- Same convention as facing: 0 = north, counter-clockwise.
    Rotate(r.arrow, math.atan2(-east, north) - facing)
    r.arrow:Show()
end

-- The row's text: just the yards while its arrow shows the way, else Locate's distance and
-- compass direction (or why there's no position).
local function RowInfo(d, r, info)
    if not r.arrow:IsShown() then return info end
    local east, north, yards = SB.Offset(d)
    if not east then return info end
    if not yards then return "" end
    return string.format("%d", math.sqrt(east * east + north * north))
end

-- Per frame: pins, beams and arrows follow you, and pins and beams pulse.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    for i = 1, table.getn(rows) do
        if rows[i]:IsShown() then PointArrow(rows[i]) end
    end
    local phase = Pulse(1)
    for name, p in pairs(pins) do
        if p:IsShown() then
            local d = SB.downs[name]
            if d then
                local info, east, north, yards = Locate(d)
                p.info = info
                if east then PlacePin(p, east, north, yards) end
            end
            p.glow:SetWidth(20 + 34 * phase)
            p.glow:SetHeight(20 + 34 * phase)
            p.glow:SetAlpha(1 - phase)
        end
    end
    for _, b in pairs(beams) do
        if b:IsShown() then
            b.ring:SetWidth(50 + 70 * phase)
            b.ring:SetHeight((50 + 70 * phase) * 0.4) -- flattened: a ring on the ground
            b.ring:SetAlpha(1 - phase)
            b.halo:SetAlpha(0.6 + 0.4 * (1 - phase))
        end
    end
end)

-- Every 0.2 s from Core.lua, and when someone goes down or comes up.
function SB.Tick()
    local downs = Sorted()
    local n = table.getn(downs)
    local live = {}
    local anyReal = false
    local revive = type(AZS_REVIVE) == "table" and AZS_REVIVE or {}

    for i = 1, n do
        local d = downs[i]
        live[d.name] = true
        if not d.test then anyReal = true end
        local info, east = Locate(d)

        local p = pins[d.name]
        if SB.Get("minimap") and east then
            GetPin(d.name):Show()
        elseif p then
            p:Hide()
        end

        local b = beams[d.name]
        local plate = SB.Get("plate") and FindPlate(d.name)
        if plate then
            b = GetBeam(d.name)
            b:ClearAllPoints()
            b:SetPoint("CENTER", plate, "CENTER", 0, 0)
            b:Show()
        elseif b then
            b:Hide()
        end

        if SB.Get("list") then
            local r = GetRow(i)
            r.down, r.unit = d.name, d.unit
            local cr, cg, cb = ClassColor(d.class)
            r.name:SetText(d.name)
            r.name:SetTextColor(cr, cg, cb)
            r.stripe:SetVertexColor(cr, cg, cb)
            r.info:ClearAllPoints()
            r.info:SetPoint("RIGHT", r, "RIGHT", SB.Get("arrow") and -(ARROW_COL + 2) or -6, 0)
            if revive.reviving == d.name and type(revive.rshare) == "number" then
                r.info:SetText(string.format("reviving %d%%", revive.rshare * 100))
                r.info:SetTextColor(0.3, 1, 0.3)
            else
                r.info:SetText(RowInfo(d, r, info) .. (d.test and " (test)" or ""))
                r.info:SetTextColor(1, 1, 1)
            end
            r:Show()
        end
    end

    for name, p in pairs(pins) do
        if not live[name] then p:Hide() end
    end
    for name, b in pairs(beams) do
        if not live[name] then b:Hide() end
    end
    local shownRows = SB.Get("list") and n or 0
    for i = shownRows + 1, table.getn(rows) do rows[i]:Hide() end
    if shownRows > 0 then
        list:SetHeight(ListHeight(shownRows))
        list:Show()
    elseif SB.Get("listLocked") then
        list:Hide()
    end

    FriendPlates(anyReal and SB.Get("plate") and SB.Get("friendPlates"))
    if n > 0 then driver:Show() else driver:Hide() end
end

-- Settings changed (or loaded).
function SB.Refresh()
    PlaceList()
    if SB.UpdateMinimapButton then SB.UpdateMinimapButton() end
    if SB.RefreshOptions then SB.RefreshOptions() end
    if not SB.Get("listLocked") then
        -- Unlocked: show the list even when empty so there's something to drag.
        list:SetHeight(ListHeight(1))
        list:Show()
    end
    SB.Tick()
end
