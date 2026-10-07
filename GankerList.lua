-- Rallying Cry - Ganker List Window
-- Two lists in one window: gankers (with bounties) and KOS guilds. Rows
-- scroll with the mouse wheel. Row buttons only show when usable.

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

local BOUNTY_POPUP = "RALLYINGCRY_POST_BOUNTY"
local CLAIM_POPUP = "RALLYINGCRY_CONFIRM_CLAIM"
local REMOVE_POPUP = "RALLYINGCRY_CONFIRM_REMOVE"
local REMOVE_GUILD_POPUP = "RALLYINGCRY_CONFIRM_REMOVE_GUILD"

-- Per-mode labels. Guild rows reuse the ganker columns: name, then "Added by"
-- in the wide last-seen column.
local MODES = {
    gankers = {
        headers = { "Name", "Reports", "Last seen", "Bounty" },
        add = "Add Ganker",
        empty = "No gankers yet. They're added when a Ganked! or Hunt alert names one, or click Add Ganker.",
        one = "1 ganker",
        many = " gankers",
    },
    guilds = {
        headers = { "Guild", "", "Added by", "" },
        add = "Add Guild",
        empty = "No KOS guilds yet. Every member of a guild on this list counts as a ganker. Officers can add one with Add Guild.",
        one = "1 guild",
        many = " guilds",
    },
}

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

StaticPopupDialogs[REMOVE_GUILD_POPUP] = {
    text = "Remove <%s> from the KOS guild list?",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function(_, name)
        RC.Gankers:RemoveGuild(name)
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

local function ShowGuildTooltip(row)
    local guild = row.guild
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText("<" .. guild.name .. ">", 1, 0.2, 0.2)
    if guild.name:sub(-1) == "*" then
        GameTooltip:AddLine("Matches every guild starting with " .. guild.name:sub(1, -2), 1, 0.82, 0, true)
    elseif guild.numbered then
        GameTooltip:AddLine("Also matches " .. guild.name .. " 2, " .. guild.name .. " II, and so on", 1, 0.82, 0, true)
    end
    if guild.realm then
        GameTooltip:AddLine(guild.realm, 0.8, 0.8, 0.8)
    end
    if guild.reason then
        GameTooltip:AddLine(guild.reason, 1, 1, 1, true)
    end
    GameTooltip:AddLine("Added by " .. RC.DisplayName(guild.addedBy), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Every member counts as a ganker.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function ShowRowTooltip(row)
    if row.guild then
        ShowGuildTooltip(row)
        return
    end
    local ganker = row.ganker
    if not ganker then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(RC.DisplayName(ganker.name), 1, 0.2, 0.2)
    if ganker.guild then
        local kos = RC.Gankers:MatchGuild(ganker.guild) and " |cffff3333(KOS guild)|r" or ""
        GameTooltip:AddLine("<" .. ganker.guild .. ">" .. kos, 1, 1, 1)
    end
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
        if row.guild then
            StaticPopup_Show(REMOVE_GUILD_POPUP, row.guild.name, nil, row.guild.name)
        else
            StaticPopup_Show(REMOVE_POPUP, RC.DisplayName(row.ganker.name), nil, row.ganker.name)
        end
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
    title:SetText("Ganker List")
    title:SetTextColor(RC.Theme.Color(RC.Theme.GOLD_LIGHT))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    -- Gankers | Guilds toggle
    self.tabs = {}
    self.tabs.guilds = SmallButton(frame, "Guilds", 70, function()
        List:SetMode("guilds")
    end)
    self.tabs.guilds:SetHeight(20)
    self.tabs.guilds:SetPoint("TOPRIGHT", -36, -10)
    self.tabs.gankers = SmallButton(frame, "Gankers", 70, function()
        List:SetMode("gankers")
    end)
    self.tabs.gankers:SetHeight(20)
    self.tabs.gankers:SetPoint("RIGHT", self.tabs.guilds, "LEFT", -4, 0)

    self.headers = {}
    for i, x in ipairs({ COL_NAME + 4, COL_REPORTS, COL_SEEN, COL_BOUNTY }) do
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", PADDING + x, -HEADER_TOP)
        self.headers[i] = text
    end

    self.rows = {}
    for i = 1, ROWS do
        self.rows[i] = self:CreateRow(frame, i)
    end

    self.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("TOP", 0, -(HEADER_TOP + 60))
    self.empty:SetWidth(WIDTH - 80)

    local add = SmallButton(frame, "Add Ganker", 100, function()
        List:ShowAddForm()
    end)
    self.addButton = add
    add:SetHeight(22)
    add:SetPoint("BOTTOMLEFT", PADDING, 12)

    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.pageText:SetPoint("BOTTOMRIGHT", -PADDING, 18)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", add, "RIGHT", 12, 0)
    hint:SetText("Hover a row for details. Scroll for more.")

    self.offset = 0
    self.mode = self.mode or "gankers"
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

function List:SetMode(mode)
    self.mode = mode
    self.offset = 0
    if self.addForm then
        self.addForm:Hide()
    end
    self:Refresh()
end

local function FillGankerRow(row, entry, me)
    local ganker = entry.ganker
    row.ganker, row.guild = ganker, nil
    row.name:SetText(RC.DisplayName(ganker.name))
    row.reports:SetText(ganker.reports)
    row.seen:SetText(TimeAgo(ganker.lastSeen))
    row.bounty:SetText(entry.bounty > 0 and RC.FormatGold(entry.bounty) or "|cff808080-|r")
    row.bountyButton:Show()
    row.claimButton:SetShown(RC.Gankers:CanClaim(ganker.name))
    row.removeButton:SetShown(RC.Gankers:CanRemove(me, ganker))
end

local function FillGuildRow(row, guild, me)
    row.ganker, row.guild = nil, guild
    row.name:SetText(RC.GuildLabel(guild))
    row.reports:SetText("")
    row.seen:SetText(RC.DisplayName(guild.addedBy))
    row.bounty:SetText("")
    row.bountyButton:Hide()
    row.claimButton:Hide()
    row.removeButton:SetShown(RC.Gankers:IsOfficer(me))
end

function List:Refresh()
    if not (self.frame and self.frame:IsShown()) then
        return
    end

    local mode = MODES[self.mode]
    for i, header in ipairs(self.headers) do
        header:SetText(mode.headers[i])
    end
    self.addButton:SetText(mode.add)
    -- Only officers manage KOS guilds
    self.addButton:SetShown(self.mode ~= "guilds" or RC.Gankers:IsOfficer(Me()))
    self.empty:SetText(mode.empty)
    for key, tab in pairs(self.tabs) do
        if key == self.mode then
            tab:SetText("|cffffd100" .. (key == "gankers" and "Gankers" or "Guilds") .. "|r")
            tab:LockHighlight()
        else
            tab:SetText("|cff808080" .. (key == "gankers" and "Gankers" or "Guilds") .. "|r")
            tab:UnlockHighlight()
        end
    end

    local guildMode = self.mode == "guilds"
    local entries = guildMode and RC.Gankers:SortedGuilds() or RC.Gankers:Sorted()
    local maxOffset = math.max(0, #entries - ROWS)
    self.offset = math.min(math.max(self.offset, 0), maxOffset)

    local me = Me()
    for i, row in ipairs(self.rows) do
        local entry = entries[self.offset + i]
        if entry then
            if guildMode then
                FillGuildRow(row, entry, me)
            else
                FillGankerRow(row, entry, me)
            end
            row:Show()
        else
            row.ganker, row.guild = nil, nil
            row:Hide()
        end
    end

    self.empty:SetShown(#entries == 0)
    if #entries > ROWS then
        self.pageText:SetText((self.offset + 1) .. "-" .. math.min(self.offset + ROWS, #entries) .. " of " .. #entries)
    else
        self.pageText:SetText(#entries == 1 and mode.one or (#entries .. mode.many))
    end
end

----------------------------------------------------------------------
-- Add Ganker form
----------------------------------------------------------------------

local FORM_WIDTH = 320
local FORM_PADDING = 16

local function FormLabel(form, text, anchor, gap)
    local label = form:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 12))
    label:SetText(text)
    return label
end

local function FormInput(form, label, width, maxLetters)
    local box = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    return box
end

function List:CreateAddForm()
    local form = CreateFrame("Frame", "RallyingCryAddGanker", self.frame, "BackdropTemplate")
    form:SetSize(FORM_WIDTH, 250)
    form:SetPoint("CENTER", self.frame, "CENTER")
    form:SetFrameStrata("FULLSCREEN_DIALOG")
    RC.Theme.SkinWindow(form)
    form:EnableMouse(true)
    form:Hide()

    form.title = form:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    form.title:SetPoint("TOPLEFT", FORM_PADDING, -14)
    form.title:SetTextColor(RC.Theme.Color(RC.Theme.GOLD_LIGHT))

    form.nameLabel = FormLabel(form, "Name", form.title, 14)
    local nameLabel = form.nameLabel
    form.name = FormInput(form, nameLabel, 180, 40)

    form.targetButton = SmallButton(form, "Use Target", 90, function()
        if form.mode == "guilds" then
            local guild, realm = RC:GetUnitGuild("target")
            if guild and RC:GetHostileTargetName() then
                form:SetGuildName(guild)
                form.realm = realm
                form.error:SetText("")
            else
                form.error:SetText("Target an enemy player who's in a guild first.")
            end
            return
        end
        local target = RC:GetHostileTargetName()
        if target then
            form.name:SetText(RC.DisplayName(target))
            form.error:SetText("")
        else
            form.error:SetText("Target an enemy player first.")
        end
    end)
    form.targetButton:SetHeight(22)
    form.targetButton:SetPoint("LEFT", form.name, "RIGHT", 8, 0)

    local reasonLabel = FormLabel(form, "Reason |cff808080(optional)|r", nameLabel, 34)
    form.reason = FormInput(form, reasonLabel, FORM_WIDTH - FORM_PADDING * 2 - 6, 60)

    local bountyLabel = FormLabel(form, "Bounty in gold |cff808080(optional)|r", reasonLabel, 34)
    form.bountyLabel = bountyLabel

    -- Guild mode only, in the bounty field's spot
    form.numbered = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
    form.numbered:SetSize(24, 24)
    form.numbered:SetPoint("TOPLEFT", reasonLabel, "BOTTOMLEFT", -2, -30)
    local numberedText = form.numbered.Text or form.numbered.text or form.numbered:CreateFontString(nil, "OVERLAY")
    numberedText:SetFontObject("GameFontHighlightSmall")
    numberedText:ClearAllPoints()
    numberedText:SetPoint("LEFT", form.numbered, "RIGHT", 2, 0)
    form.numberedText = numberedText
    form.bounty = FormInput(form, bountyLabel, 90, 7)
    form.bounty:SetNumeric(true)

    form.error = form:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    form.error:SetPoint("TOPLEFT", bountyLabel, "BOTTOMLEFT", 0, -34)
    form.error:SetWidth(FORM_WIDTH - FORM_PADDING * 2)
    form.error:SetJustifyH("LEFT")

    local cancel = SmallButton(form, "Cancel", 90, function()
        form:Hide()
    end)
    cancel:SetHeight(22)
    cancel:SetPoint("BOTTOMRIGHT", -FORM_PADDING, 14)

    local add = SmallButton(form, "Add", 90, function()
        List:SubmitAddForm()
    end)
    add:SetHeight(22)
    add:SetPoint("RIGHT", cancel, "LEFT", -8, 0)

    -- Tab moves between fields, Enter adds, Escape closes
    local allFields = { form.name, form.reason, form.bounty }
    for _, box in ipairs(allFields) do
        box:SetScript("OnTabPressed", function()
            local fields = form.mode == "guilds" and { form.name, form.reason } or allFields
            local index = 1
            for i, field in ipairs(fields) do
                if field == box then
                    index = i
                end
            end
            local step = IsShiftKeyDown() and -1 or 1
            fields[(index - 1 + step) % #fields + 1]:SetFocus()
        end)
        box:SetScript("OnEnterPressed", function()
            List:SubmitAddForm()
        end)
        box:SetScript("OnEscapePressed", function()
            form:Hide()
        end)
    end

    -- "Olympus 2" fills in "Olympus" so the whole numbered family is covered
    function form:SetGuildName(guild)
        local base = guild and RC.GuildBaseName(guild)
        self.name:SetText(base or guild or "")
        self.numberedText:SetText("Also match numbered guilds (" .. (base or guild or "Olympus") ..
            " 2, " .. (base or guild or "Olympus") .. " II...)")
        self.numbered:SetChecked(true)
    end

    self.addForm = form
end

function List:ShowAddForm()
    if not self.addForm then
        self:CreateAddForm()
    end
    local form = self.addForm
    local guildMode = self.mode == "guilds"
    form.mode = self.mode
    form.realm = nil
    form.title:SetText(guildMode and "Add KOS Guild" or "Add Ganker")
    form.nameLabel:SetText(guildMode and "Guild name |cff808080(end with * to match all that start with it)|r" or "Name")
    form.bountyLabel:SetShown(not guildMode)
    form.bounty:SetShown(not guildMode)
    form.numbered:SetShown(guildMode)
    form.numbered:SetChecked(true)

    local target = RC:GetHostileTargetName()
    if guildMode then
        local guild, realm
        if target then
            guild, realm = RC:GetUnitGuild("target")
        end
        target = guild
        form.realm = realm
        form:SetGuildName(guild)
    else
        form.name:SetText(target and RC.DisplayName(target) or "")
    end
    form.reason:SetText("")
    form.bounty:SetText("")
    form.error:SetText("")
    form:Show()
    if target then
        form.reason:SetFocus()
    else
        form.name:SetFocus()
    end
end

function List:SubmitAddForm()
    local form = self.addForm
    if form.mode == "guilds" then
        local guild = RC.CleanText(form.name:GetText(), 30)
        if guild == "" then
            form.error:SetText("Enter the guild's name.")
            form.name:SetFocus()
            return
        end
        if not IsInGuild() then
            form.error:SetText("You need to be in a guild to use the ganker list.")
            return
        end
        RC.Gankers:AddGuild(guild, form.realm, form.reason:GetText(), form.numbered:GetChecked() and true or false)
        form:Hide()
        return
    end
    local name = RC.NormalizeName(form.name:GetText())
    if not name then
        form.error:SetText("Enter the ganker's name.")
        form.name:SetFocus()
        return
    end
    if not IsInGuild() then
        form.error:SetText("You need to be in a guild to use the ganker list.")
        return
    end
    local gold = tonumber(form.bounty:GetText())

    RC.Gankers:Add(name, form.reason:GetText())
    if gold and gold > 0 then
        RC.Gankers:PostBounty(name, gold)
    end
    form:Hide()
end

function List:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end
