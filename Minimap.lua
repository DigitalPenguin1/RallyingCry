-- Rallying Cry - Minimap Button
-- Left-click toggles the button panel, Shift-click the ganker list,
-- right-click opens settings, drag to move it around the minimap. The addon compartment entry shares the same
-- click and tooltip handlers.

local RC = RallyingCry

local MinimapButton = {}
RC.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\Ability_Warrior_BattleShout"
local DEFAULT_ANGLE = 200

local function PlaceAtAngle(button, degrees)
    local angle = math.rad(degrees)
    local radius = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor(button)
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    local degrees = math.deg(math.atan2(my / scale - cy, mx / scale - cx))
    RC.db.minimapAngle = degrees
    PlaceAtAngle(button, degrees)
end

function MinimapButton:Create()
    if self.button then
        return
    end

    local button = CreateFrame("Button", "RallyingCryMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(RC.Theme.Color(RC.Theme.BRONZE_DARK))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouseButton)
        MinimapButton:OnClick(mouseButton)
    end)
    button:SetScript("OnDragStart", function(b)
        b:LockHighlight()
        b:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(b)
        b:UnlockHighlight()
        b:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(b)
        MinimapButton:ShowTooltip(b, true)
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    PlaceAtAngle(button, RC.db.minimapAngle or DEFAULT_ANGLE)
    self.button = button
    button:SetShown(RC.db.showMinimap)
end

function MinimapButton:SetShown(shown)
    RC.db.showMinimap = shown
    self:Create()
    self.button:SetShown(shown)
end

function MinimapButton:Toggle()
    self:SetShown(not RC.db.showMinimap)
    if RC.db.showMinimap then
        RC:Print("Minimap button shown.")
    else
        RC:Print(RC.COLORS.INFO .. "Minimap button hidden. Type /rc minimap to bring it back.|r")
    end
end

function MinimapButton:OnClick(mouseButton)
    if mouseButton == "RightButton" then
        RC.Options:Open()
    elseif IsShiftKeyDown() then
        RC.GankerList:Toggle()
    else
        RC.Panel:Toggle()
    end
end

function MinimapButton:ShowTooltip(owner, draggable)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Rallying Cry", RC.Theme.Color(RC.Theme.GOLD_LIGHT))
    GameTooltip:AddLine("Left-click: toggle alert panel", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-click: ganker list", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
    if draggable then
        GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
    end

    local last = RC.db.log[1]
    if last then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Last alert (" .. date("%H:%M", last.time) .. ")", 1, 0.82, 0)
        GameTooltip:AddLine(RC.FormatAlert(last), 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- Addon compartment (the addon list by the minimap). The TOC points
-- AddonCompartmentFunc/OnEnter/OnLeave at these globals.
function RallyingCry_OnAddonCompartmentClick(_, mouseButton)
    MinimapButton:OnClick(mouseButton)
end

function RallyingCry_OnAddonCompartmentEnter(_, menuButtonFrame)
    MinimapButton:ShowTooltip(menuButtonFrame, false)
end

function RallyingCry_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
