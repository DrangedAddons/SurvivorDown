-- Minimap button: click opens the settings, drag moves it around the minimap.
-- SurvivorsDragonUi's square minimap picks up any Minimap child button with drag
-- scripts and snaps it to the square's edge, so this only places it on a circle.
local SB = SurvivorBeacon
local RADIUS = 80

local button = CreateFrame("Button", "SurvivorBeaconMinimapButton", Minimap)
button:SetWidth(32)
button:SetHeight(32)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(Minimap:GetFrameLevel() + 20)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")
button:Hide()

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetWidth(20)
background:SetHeight(20)
background:SetPoint("CENTER", button, "CENTER", 0, 0)
-- The skull raid icon, the same one the pins and the beam use.
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
icon:SetTexCoord(0.75, 1, 0.25, 0.5)
icon:SetWidth(18)
icon:SetHeight(18)
icon:SetPoint("CENTER", button, "CENTER", 0, 0)
local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(54)
border:SetHeight(54)
border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function Place()
    local angle = math.rad(SB.Get("minimapAngle") or 200)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

local function Drag()
    local cx, cy = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local x, y = GetCursorPosition()
    if not cx or not x or not scale or scale <= 0 then return end
    x, y = x / scale - cx, y / scale - cy
    if x == 0 and y == 0 then return end
    SB.SetQuiet("minimapAngle", math.deg(math.atan2(y, x)))
    Place()
end

local dragging, ignoreClickUntil = false, 0
button:SetScript("OnDragStart", function()
    dragging = true
    GameTooltip:Hide()
    this:SetScript("OnUpdate", Drag)
end)
button:SetScript("OnDragStop", function()
    this:SetScript("OnUpdate", nil)
    Drag()
    dragging = false
    ignoreClickUntil = GetTime() + 0.15 -- the release after a drag isn't a click
end)
button:SetScript("OnClick", function()
    if dragging or GetTime() < ignoreClickUntil then return end
    SB.ToggleOptions()
end)
button:SetScript("OnEnter", function()
    if dragging then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("SurvivorBeacon")
    GameTooltip:AddLine("Click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
    GameTooltip:AddLine("/asb", 1, 0.82, 0)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

function SB.UpdateMinimapButton()
    if SB.Get("minimapButton") then
        button:Show()
        Place()
    else
        button:Hide()
    end
end
