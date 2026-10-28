-- SurvivorBeacon settings window: /asb or the minimap button. Every change applies at once.
local SB = SurvivorBeacon

local frame
local widgets = {}

local function Font(label, size)
    local T = DFRL and DFRL.tools
    if T and T.SetFont then
        T.SetFont(label, size, "OUTLINE")
    else
        label:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
end

local function Text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Font(fs, size)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function Heading(parent, text, x, y)
    local fs = Text(parent, 14, 1, 0.82, 0)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
end

local function Check(parent, key, label, x, y)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetWidth(24)
    c:SetHeight(24)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 4, y)
    c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local fs = Text(c, 11)
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    c:SetScript("OnClick", function() SB.Set(key, this:GetChecked() and true or false) end)
    c.Refresh = function() c:SetChecked(SB.Get(key) and 1 or nil) end
    table.insert(widgets, c)
    return c
end

local function PlainButton(parent, text, width)
    local T = DFRL and DFRL.tools
    if T and T.CreateButton then return T.CreateButton(parent, text, width, 26) end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(24)
    b:SetText(text)
    return b
end

local function Build()
    frame = CreateFrame("Frame", "SurvivorBeaconOptions", UIParent)
    frame:SetWidth(320)
    frame:SetHeight(410)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    frame:Hide()
    table.insert(UISpecialFrames, "SurvivorBeaconOptions") -- Escape closes it

    local title = Text(frame, 18, 1, 0.82, 0)
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("SurvivorBeacon")
    local version = Text(frame, 10, 0.6, 0.6, 0.6)
    version:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    version:SetText("v" .. SB.version)

    local L = 20
    Heading(frame, "When a teammate goes down", L, -44)
    Check(frame, "alert", "Call out who went down", L, -66)
    Check(frame, "sound", "Play a sound with the call-out", L, -90)
    Check(frame, "minimap", "Pin on the minimap", L, -114)
    Check(frame, "plate", "Beam under their nameplate", L, -138)
    Check(frame, "friendPlates", "Turn friendly nameplates on for the beam", L, -162)
    Check(frame, "skull", "Skull raid icon on them", L, -186)
    Check(frame, "list", "List of who's down, how far and which way", L, -210)
    local unlock = PlainButton(frame, "Unlock list", 120)
    unlock:SetPoint("TOPLEFT", frame, "TOPLEFT", L, -238)
    unlock:SetScript("OnClick", function() SB.Set("listLocked", not SB.Get("listLocked")) end)
    unlock.Refresh = function()
        unlock:SetText(SB.Get("listLocked") and "Unlock list" or "Lock list")
    end
    table.insert(widgets, unlock)
    local unlockHint = Text(frame, 10, 0.6, 0.6, 0.6)
    unlockHint:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
    unlockHint:SetText("then drag it by its title")

    Heading(frame, "Other", L, -276)
    Check(frame, "minimapButton", "Show minimap button", L, -298)

    local test = PlainButton(frame, "Test", 90)
    test:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    test:SetScript("OnClick", function() SB.Test() end)
    local status = PlainButton(frame, "Status", 90)
    status:SetPoint("LEFT", test, "RIGHT", 6, 0)
    status:SetScript("OnClick", function() SB.Status() end)
    local close = PlainButton(frame, "Close", 90)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    close:SetScript("OnClick", function() frame:Hide() end)

    local hint = Text(frame, 10, 0.6, 0.6, 0.6)
    hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 48)
    hint:SetText("Test: a pretend teammate down where you stand, on your target's plate if you have one. Walk away to check it stays put.")
    hint:SetWidth(290)
end

function SB.RefreshOptions()
    if not frame or not frame:IsShown() then return end
    for i = 1, table.getn(widgets) do widgets[i].Refresh() end
end

function SB.ToggleOptions()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        SB.RefreshOptions()
    end
end
