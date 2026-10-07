-- Rallying Cry - Sync Log
-- A record of ganker list syncing for the Sync page in settings: what was
-- asked for, sent, received, and ignored. Incoming records arrive one
-- message at a time, so they're grouped per guildmate into one line.

local RC = RallyingCry

local SyncLog = {}
RC.SyncLog = SyncLog

local MAX_ENTRIES = 100

-- A batch is written to the log once a guildmate goes quiet for this long
local BATCH_QUIET = 3

local KIND_NAMES = {
    KOS = { "ganker", "gankers" },
    BNTY = { "bounty", "bounties" },
    KOSG = { "KOS guild", "KOS guilds" },
}
local KIND_ORDER = { "KOS", "BNTY", "KOSG" }

local batches = {}

local function FormatEntry(entry)
    return RC.COLORS.INFO .. date("%m/%d %H:%M", entry.time) .. "|r  " .. entry.text
end

function SyncLog:Add(text)
    local log = RC.guild.syncLog
    table.insert(log, { time = time(), text = text })
    while #log > MAX_ENTRIES do
        table.remove(log, 1)
    end
    RC:Debug("sync: " .. text)
    if self.messages then
        self.messages:AddMessage(FormatEntry(log[#log]))
    end
    self:UpdateSummary()
end

local function CountsText(counts)
    local parts = {}
    for _, kind in ipairs(KIND_ORDER) do
        local n = counts[kind]
        if n > 0 then
            table.insert(parts, n .. " " .. KIND_NAMES[kind][n == 1 and 1 or 2])
        end
    end
    return table.concat(parts, ", ")
end

-- Up to three of the names in a batch, so you can see what was sent
local MAX_NAMES = 3

local function NamesText(names)
    if #names == 0 then
        return ""
    end
    local shown = {}
    for i = 1, math.min(#names, MAX_NAMES) do
        shown[i] = names[i]
    end
    local text = table.concat(shown, ", ")
    if #names > MAX_NAMES then
        text = text .. " +" .. (#names - MAX_NAMES) .. " more"
    end
    return ": " .. text
end

local function Flush(key)
    local batch = batches[key]
    batches[key] = nil
    local who = "|cffffffff" .. RC.DisplayName(batch.sender) .. "|r"
    local text
    if batch.relay then
        text = "Received " .. batch.total .. (batch.total == 1 and " update" or " updates") ..
            " from " .. who .. " (" .. CountsText(batch.counts) .. ")"
        text = text .. (batch.applied > 0 and (", " .. batch.applied .. " new") or ", already up to date")
    else
        text = who .. " changed " .. CountsText(batch.counts)
    end
    text = text .. NamesText(batch.names)
    if batch.applied > 0 then
        RC.guild.lastSyncReceived = time()
    end
    SyncLog:Add(text)
end

-- Called for every ganker, bounty, or KOS guild record a guildmate sends.
-- applied is false when we already had that version or newer.
function SyncLog:CountRecord(sender, relay, kind, applied, label)
    -- An import writes its own summary line
    if self.muted then
        return
    end
    local key = sender .. (relay and ":sync" or ":live")
    local batch = batches[key]
    if not batch then
        batch = { sender = sender, relay = relay, counts = { KOS = 0, BNTY = 0, KOSG = 0 }, total = 0, applied = 0, names = {} }
        batches[key] = batch
    end
    batch.counts[kind] = batch.counts[kind] + 1
    batch.total = batch.total + 1
    if applied then
        batch.applied = batch.applied + 1
        -- Only list what actually changed for you
        if label and not tContains(batch.names, label) then
            table.insert(batch.names, label)
        end
    end
    if batch.timer then
        batch.timer:Cancel()
    end
    batch.timer = C_Timer.NewTimer(BATCH_QUIET, function()
        Flush(key)
    end)
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------

local function TimeAgo(stamp)
    if not stamp then
        return "never"
    end
    local seconds = math.max(0, time() - stamp)
    if seconds < 60 then
        return "just now"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m ago"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. "h ago"
    end
    return math.floor(seconds / 86400) .. "d ago"
end

function SyncLog:UpdateSummary()
    if not self.summary then
        return
    end
    local gankers, guilds, bounties = 0, 0, 0
    for _, ganker in pairs(RC.guild.gankers) do
        if not ganker.removedBy then
            gankers = gankers + 1
        end
    end
    for _, guild in pairs(RC.guild.kosGuilds) do
        if not guild.removedBy then
            guilds = guilds + 1
        end
    end
    for _, bounty in pairs(RC.guild.bounties) do
        if bounty.status == "open" or bounty.status == "claimed" or bounty.status == "denied" then
            bounties = bounties + 1
        end
    end
    self.summary:SetText(
        "Gankers: |cffffffff" .. gankers .. "|r     KOS guilds: |cffffffff" .. guilds ..
        "|r     Open bounties: |cffffffff" .. bounties .. "|r\n" ..
        "Last update from a guildmate: |cffffffff" .. TimeAgo(RC.guild.lastSyncReceived) .. "|r")
end

local function Button(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    RC.Theme.SkinButton(button)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

function SyncLog:CreatePage()
    local frame = CreateFrame("Frame")
    local Theme = RC.Theme

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Sync")
    title:SetTextColor(Theme.Color(Theme.GOLD_LIGHT))

    local about = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    about:SetWidth(560)
    about:SetJustifyH("LEFT")
    about:SetText("The ganker list, KOS guilds, and bounties are shared with every guildmate running " ..
        "Rallying Cry. When you log in, you ask the guild for anything you missed.")

    self.summary = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.summary:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
    self.summary:SetJustifyH("LEFT")
    self.summary:SetSpacing(4)

    local syncNow = Button(frame, "Sync Now", 110, function()
        SyncLog:SyncNow()
    end)
    syncNow:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -14)

    local clear = Button(frame, "Clear Log", 110, function()
        wipe(RC.guild.syncLog)
        SyncLog.messages:Clear()
    end)
    clear:SetPoint("LEFT", syncNow, "RIGHT", 8, 0)

    local export = Button(frame, "Export Backup", 120, function()
        SyncLog:ShowBackup("export")
    end)
    export:SetPoint("LEFT", clear, "RIGHT", 24, 0)

    local import = Button(frame, "Import Backup", 120, function()
        SyncLog:ShowBackup("import")
    end)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", syncNow, "BOTTOMLEFT", 0, -12)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    Theme.SkinWindow(box)

    local messages = CreateFrame("ScrollingMessageFrame", nil, box)
    messages:SetPoint("TOPLEFT", 10, -10)
    -- Extra room at the bottom so the newest line clears the border
    messages:SetPoint("BOTTOMRIGHT", -10, 16)
    messages:SetFontObject("GameFontHighlightSmall")
    messages:SetJustifyH("LEFT")
    messages:SetFading(false)
    messages:SetMaxLines(MAX_ENTRIES)
    messages:SetInsertMode("BOTTOM")
    messages:EnableMouseWheel(true)
    messages:SetScript("OnMouseWheel", function(f, delta)
        if delta > 0 then
            f:ScrollUp()
        else
            f:ScrollDown()
        end
    end)
    self.messages = messages

    frame:SetScript("OnShow", function()
        messages:Clear()
        for _, entry in ipairs(RC.guild.syncLog) do
            messages:AddMessage(FormatEntry(entry))
        end
        SyncLog:UpdateSummary()
    end)

    return frame
end

-- Manual sync, at most once every 30 seconds
function SyncLog:SyncNow()
    if not IsInGuild() then
        self:Add("Not in a guild, nothing to sync.")
        return
    end
    local now = GetTime()
    if self.lastManual and now - self.lastManual < 30 then
        self:Add("Already asked a moment ago. Give guildmates a few seconds to answer.")
        return
    end
    self.lastManual = now
    RC.Gankers:RequestSync()
end

----------------------------------------------------------------------
-- Backup window
----------------------------------------------------------------------

local IMPORT_POPUP = "RALLYINGCRY_CONFIRM_IMPORT"

StaticPopupDialogs[IMPORT_POPUP] = {
    text = "%s",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function(_, backup)
        local count = RC.Gankers:Import(backup)
        if count == 0 then
            RC:Print("Nothing in that backup is newer than your list, so nothing changed.")
        elseif count then
            RC:Print("Restored " .. Plural(count, "entry", "entries") .. " from the backup. " ..
                "They're being shared with your guild.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

local function Plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

local function Summary(counts)
    return Plural(counts.KOS, "ganker", "gankers") .. ", " .. Plural(counts.KOSG, "KOS guild", "KOS guilds") ..
        ", " .. Plural(counts.BNTY, "bounty", "bounties")
end

function SyncLog:CreateBackupWindow()
    local frame = CreateFrame("Frame", "RallyingCryBackup", UIParent, "BackdropTemplate")
    frame:SetSize(520, 340)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    RC.Theme.SkinWindow(frame)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    table.insert(UISpecialFrames, "RallyingCryBackup")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 16, -14)
    frame.title:SetTextColor(RC.Theme.Color(RC.Theme.GOLD_LIGHT))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.help:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.help:SetWidth(488)
    frame.help:SetJustifyH("LEFT")

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -70)
    box:SetPoint("BOTTOMRIGHT", -16, 50)
    box:SetBackdrop(RC.Theme.WINDOW_BACKDROP)
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(RC.Theme.Color(RC.Theme.GOLD, 0.6))

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(440)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    edit:SetScript("OnTextChanged", function(e, userInput)
        -- The export text can't be edited by accident
        if userInput and frame.mode == "export" then
            e:SetText(frame.exportText)
            e:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    -- Clicking anywhere in the box focuses the text
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
    end)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 16, 20)
    frame.status:SetWidth(300)
    frame.status:SetJustifyH("LEFT")

    frame.action = Button(frame, "", 110, function()
        SyncLog:BackupAction()
    end)
    frame.action:SetPoint("BOTTOMRIGHT", -16, 14)

    self.backupWindow = frame
end

function SyncLog:ShowBackup(mode)
    if not self.backupWindow then
        self:CreateBackupWindow()
    end
    local frame = self.backupWindow
    frame.mode = mode
    frame.status:SetText("")
    frame.status:SetTextColor(1, 1, 1)

    if mode == "export" then
        local text, counts = RC.Gankers:ExportString()
        if not text then
            RC:Print(RC.COLORS.ERROR .. "Couldn't create a backup.|r")
            return
        end
        frame.exportText = text
        frame.title:SetText("Export Backup")
        frame.help:SetText("Copy this text with Ctrl+C and keep it somewhere safe, like a Discord channel " ..
            "or a text file. An officer can import it later to restore the guild's list.")
        frame.status:SetText(Summary(counts) .. (RC.guildName and (" from <" .. RC.guildName .. ">") or ""))
        frame.action:SetText("Select All")
        frame.edit:SetText(text)
        frame:Show()
        frame.edit:SetFocus()
        frame.edit:HighlightText()
    else
        if not RC.Gankers:IsOfficer(RC:PlayerFullName()) then
            RC:Print(RC.COLORS.WARNING .. "Only officers can import a backup.|r")
            return
        end
        frame.exportText = nil
        frame.title:SetText("Import Backup")
        frame.help:SetText("Paste a backup with Ctrl+V, then click Import. Newer changes in your current " ..
            "list are kept, so an old backup can't undo anything.")
        frame.action:SetText("Import")
        frame.edit:SetText("")
        frame:Show()
        frame.edit:SetFocus()
    end
end

function SyncLog:BackupAction()
    local frame = self.backupWindow
    if frame.mode == "export" then
        frame.edit:SetFocus()
        frame.edit:HighlightText()
        return
    end

    local backup, problem = RC.Gankers:ReadBackup(frame.edit:GetText())
    if not backup then
        frame.status:SetText(problem)
        frame.status:SetTextColor(1, 0.3, 0.3)
        return
    end

    local text = "Import this backup?\n\n" .. Summary(backup.counts)
    if backup.exported then
        text = text .. "\nSaved " .. date("%m/%d/%Y %H:%M", backup.exported)
    end
    if backup.guild and RC.guildName and backup.guild:lower() ~= RC.guildName:lower() then
        text = text .. "\n\n" .. RC.COLORS.WARNING .. "This backup is from <" .. backup.guild ..
            ">, not <" .. RC.guildName .. ">. Its list will be shared with your guild.|r"
    end
    frame:Hide()
    StaticPopup_Show(IMPORT_POPUP, text, nil, backup)
end
