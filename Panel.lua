-- Rallying Cry - Button Panel
-- A small draggable frame with one button per alert type. These are plain
-- (non-secure) buttons, so they keep working in combat.

local RC = RallyingCry

local Panel = {}
RC.Panel = Panel

local BUTTON_WIDTH = 130
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 4
local PADDING = 10
local TITLE_HEIGHT = 20

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    RC.db.panelPoint = { point, relativePoint, x, y }
end

local function RestorePosition(frame)
    frame:ClearAllPoints()
    local saved = RC.db.panelPoint
    if saved then
        frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80)
    end
end

function Panel:Create()
    if self.frame then
        return
    end

    local count = #RC.ALERT_ORDER
    local frame = CreateFrame("Frame", "RallyingCryPanel", UIParent, "BackdropTemplate")
    frame:SetSize(BUTTON_WIDTH + PADDING * 2,
        TITLE_HEIGHT + PADDING + count * BUTTON_HEIGHT + (count - 1) * BUTTON_GAP + PADDING)
    RC.Theme.SkinWindow(frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePosition(f)
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PADDING, -8)
    title:SetText("Rallying Cry")
    title:SetTextColor(RC.Theme.Color(RC.Theme.GOLD_LIGHT))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        Panel:Hide()
    end)

    local gear = CreateFrame("Button", nil, frame)
    gear:SetSize(14, 14)
    gear:SetPoint("RIGHT", close, "LEFT", 0, 0)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gear:SetScript("OnClick", function()
        RC.Options:Open()
    end)
    gear:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText("Settings")
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", GameTooltip_Hide)

    local previous
    for _, alertType in ipairs(RC.ALERT_ORDER) do
        local info = RC.ALERTS[alertType]
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
        RC.Theme.SkinButton(button)
        if previous then
            button:SetPoint("TOP", previous, "BOTTOM", 0, -BUTTON_GAP)
        else
            button:SetPoint("TOP", frame, "TOP", 0, -(TITLE_HEIGHT + PADDING))
        end
        button:SetText(info.color .. info.label .. "|r")
        button:SetScript("OnClick", function()
            RC:SendAlert(alertType)
        end)
        button:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            GameTooltip:SetText(info.label)
            GameTooltip:AddLine(info.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        previous = button
    end

    RestorePosition(frame)
    self.frame = frame
    frame:SetShown(RC.db.showPanel)
end

function Panel:Show()
    self:Create()
    self.frame:Show()
    RC.db.showPanel = true
end

function Panel:Hide(quiet)
    if self.frame then
        self.frame:Hide()
    end
    RC.db.showPanel = false
    if not quiet then
        RC:Print(RC.COLORS.INFO .. "Panel hidden. Type /rc panel to bring it back.|r")
    end
end

function Panel:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
