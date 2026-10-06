-- Rallying Cry - Ganker List Window
-- The guild's ganker list with bounties. Rows scroll with the mouse wheel.
-- Each row has Bounty, Claim, and Remove buttons, shown only when usable.

local RC = RallyingCry

local List = {}
RC.GankerList = List

local ROWS = 10
local ROW_HEIGHT = 24
local WIDTH = 560
local PADDING = 12
local HEADER_TOP = 40

-- Column x offsets inside a row
local COL_NAME, COL_REPORTS, COL_SEEN, COL_BOUNTY, COL_BUTTONS = 0, 150, 205, 330, 400

local ADD_POPUP = "RALLYINGCRY_ADD_GANKER"
local BOUNTY_POPUP = "RALLYINGCRY_POST_BOUNTY"
local CLAIM_POPUP = "RALLYINGCRY_CONFIRM_CLAIM"
local REMOVE_POPUP = "RALLYINGCRY_CONFIRM_REMOVE"

local function Me()
    return RC:PlayerFullName()
end

local function TimeAgo(stamp)
    if not stamp then
        return "never"
    end
    local seconds = math.max(0, GetServerTime() - stamp)
    if seconds < 3600 then
        return math.max(1, math.floor(seconds / 60)) .. "m ago"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. "h ago"
    end
    return math.floor(seconds / 86400) .. "d ago"
end

-- The popup edit box moved between client versions
local function PopupEditBox(dialog)
    return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

local function EditBoxPopup(fields)
    local popup = {
        button1 = fields.button1,
        button2 = "Cancel",
        hasEditBox = true,
        maxLetters = fields.maxLetters,
        OnShow = function(dialog, data)
            local box = PopupEditBox(dialog)
            box:SetText(fields.initial and fields.initial(data) or "")
            box:SetFocus()
            box:HighlightText()
        end,
        OnAccept = function(dialog, data)
            fields.onAccept(PopupEditBox(dialog):GetText(), data)
        end,
        EditBoxOnEnterPressed = function(box)
            local dialog = box:GetParent()
            fields.onAccept(box:GetText(), dialog.data)
            dialog:Hide()
        end,
        EditBoxOnEscapePressed = function(box)
            box:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    popup.text = fields.text
    return popup
end

StaticPopupDialogs[ADD_POPUP] = EditBoxPopup({
    text = "Ganker's name, then an optional reason:",
    button1 = "Add",
    maxLetters = 100,
    initial = function()
        local target = RC:GetHostileTargetName()
        return target and (RC.DisplayName(target) .. " ") or ""
    end,
    onAccept = function(text)
        local name, reason = text:match("^%s*(%S*)%s*(.-)%s*$")
        RC.Gankers:Add(name, reason)
    end,
})

StaticPopupDialogs[BOUNTY_POPUP] = EditBoxPopup({
    text = "Gold to put on %s's head (0 withdraws yours):",
    button1 = "Post",
    maxLetters = 7,
    onAccept = function(text, name)
        RC.Gankers:PostBounty(name, text)
    end,
})

StaticPopupDialogs[CLAIM_POPUP] = {
    text = "Claim the bounty on %s?\n\nOnly claim it if you killed them. Each poster confirms before paying.",
    button1 = "Claim",
    button2 = "Cancel",
    OnAccept = function(_, name)
        RC.Gankers:Claim(name)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs[REMOVE_POPUP] = {
    text = "Remove %s from the guild ganker list?",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function(_, name)
        RC.Gankers:Remove(name)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function SmallButton(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 18)
    RC.Theme.SkinButton(button)
    button:SetText(label)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetScript("OnClick", onClick)
    return button
end

local function Column(row, x, width, font)
    local text = row:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    text:SetPoint("LEFT", x, 0)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function ShowRowTooltip(row)
    local ganker = row.ganker
    if not ganker then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(RC.DisplayName(ganker.name), 1, 0.2, 0.2)
    if ganker.reason then
        GameTooltip:AddLine(ganker.reason, 1, 1, 1, true)
    end
    GameTooltip:AddLine("Added by " .. RC.DisplayName(ganker.addedBy), 0.8, 0.8, 0.8)
    if ganker.zone then
        GameTooltip:AddLine("Last seen " .. TimeAgo(ganker.lastSeen) .. " in " .. ganker.zone, 0.8, 0.8, 0.8, true)
    end

    local bounties = RC.Gankers:ActiveBounties(ganker.name)
    if #bounties > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Bounties", 1, 0.82, 0)
        for _, bounty in ipairs(bounties) do
            local status = ""
            if bounty.status == "claimed" then
                status = " (claimed by " .. RC.DisplayName(bounty.claimant) .. ")"
            end
            GameTooltip:AddDoubleLine(RC.DisplayName(bounty.poster) .. status, RC.FormatGold(bounty.gold),
                1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

function List:CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH - PADDING * 2, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING, -(HEADER_TOP + 18 + (index - 1) * ROW_HEIGHT))

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(RC.Theme.Color(RC.Theme.BRONZE, index % 2 == 0 and 0.35 or 0.15))

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(RC.Theme.Color(RC.Theme.GOLD_LIGHT, 0.1))

    row.name = Column(row, COL_NAME + 4, COL_REPORTS - 8)
    row.name:SetTextColor(1, 0.35, 0.35)
    row.reports = Column(row, COL_REPORTS, COL_SEEN - COL_REPORTS - 4)
    row.seen = Column(row, COL_SEEN, COL_BOUNTY - COL_SEEN - 4, "GameFontHighlightSmall")
    row.bounty = Column(row, COL_BOUNTY, COL_BUTTONS - COL_BOUNTY - 4)

    row.bountyButton = SmallButton(row, "Bounty", 54, function()
        StaticPopup_Show(BOUNTY_POPUP, RC.DisplayName(row.ganker.name), nil, row.ganker.name)
    end)
    row.bountyButton:SetPoint("LEFT", COL_BUTTONS, 0)

    row.claimButton = SmallButton(row, "Claim", 48, function()
        StaticPopup_Show(CLAIM_POPUP, RC.DisplayName(row.ganker.name), nil, row.ganker.name)
    end)
    row.claimButton:SetPoint("LEFT", row.bountyButton, "RIGHT", 4, 0)

    row.removeButton = SmallButton(row, "X", 22, function()
        StaticPopup_Show(REMOVE_POPUP, RC.DisplayName(row.ganker.name), nil, row.ganker.name)
    end)
    row.removeButton:SetPoint("LEFT", row.claimButton, "RIGHT", 4, 0)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

function List:Create()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "RallyingCryGankerList", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEADER_TOP + 18 + ROWS * ROW_HEIGHT + 44)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    RC.Theme.SkinWindow(frame)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    -- Close with Escape
    table.insert(UISpecialFrames, "RallyingCryGankerList")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, -12)
    title:SetText("Guild Ganker List")
    title:SetTextColor(RC.Theme.Color(RC.Theme.GOLD_LIGHT))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local headers = {
        { COL_NAME + 4, "Name" },
        { COL_REPORTS, "Reports" },
        { COL_SEEN, "Last seen" },
        { COL_BOUNTY, "Bounty" },
    }
    for _, header in ipairs(headers) do
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", PADDING + header[1], -HEADER_TOP)
        text:SetText(header[2])
    end

    self.rows = {}
    for i = 1, ROWS do
        self.rows[i] = self:CreateRow(frame, i)
    end

    self.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("TOP", 0, -(HEADER_TOP + 60))
    self.empty:SetWidth(WIDTH - 80)
    self.empty:SetText("No gankers yet. They're added when a Ganked! or Hunt alert names one, or click Add Ganker.")

    local add = SmallButton(frame, "Add Ganker", 100, function()
        StaticPopup_Show(ADD_POPUP)
    end)
    add:SetHeight(22)
    add:SetPoint("BOTTOMLEFT", PADDING, 12)

    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("BOTTOMRIGHT", -PADDING, 18)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", add, "RIGHT", 12, 0)
    hint:SetText("Hover a row for details. Scroll for more.")

    self.offset = 0
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        List.offset = List.offset - delta
        List:Refresh()
    end)
    frame:SetScript("OnShow", function()
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
        end
        List:Refresh()
    end)

    self.frame = frame
end

function List:Refresh()
    if not (self.frame and self.frame:IsShown()) then
        return
    end

    local entries = RC.Gankers:Sorted()
    local maxOffset = math.max(0, #entries - ROWS)
    self.offset = math.min(math.max(self.offset, 0), maxOffset)

    local me = Me()
    for i, row in ipairs(self.rows) do
        local entry = entries[self.offset + i]
        if entry then
            local ganker = entry.ganker
            row.ganker = ganker
            row.name:SetText(RC.DisplayName(ganker.name))
            row.reports:SetText(ganker.reports)
            row.seen:SetText(TimeAgo(ganker.lastSeen))
            row.bounty:SetText(entry.bounty > 0 and RC.FormatGold(entry.bounty) or "|cff808080-|r")
            row.claimButton:SetShown(RC.Gankers:CanClaim(ganker.name))
            row.removeButton:SetShown(RC.Gankers:CanRemove(me, ganker))
            row:Show()
        else
            row.ganker = nil
            row:Hide()
        end
    end

    self.empty:SetShown(#entries == 0)
    if #entries > ROWS then
        self.pageText:SetText((self.offset + 1) .. "-" .. math.min(self.offset + ROWS, #entries) .. " of " .. #entries)
    else
        self.pageText:SetText(#entries == 1 and "1 ganker" or (#entries .. " gankers"))
    end
end

function List:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end
