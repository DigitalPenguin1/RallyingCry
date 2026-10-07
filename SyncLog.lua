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
    local log = RC.db.syncLog
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
        RC.db.lastSyncReceived = time()
    end
    SyncLog:Add(text)
end

-- Called for every ganker, bounty, or KOS guild record a guildmate sends.
-- applied is false when we already had that version or newer.
function SyncLog:CountRecord(sender, relay, kind, applied, label)
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
    for _, ganker in pairs(RC.db.gankers) do
        if not ganker.removedBy then
            gankers = gankers + 1
        end
    end
    for _, guild in pairs(RC.db.kosGuilds) do
        if not guild.removedBy then
            guilds = guilds + 1
        end
    end
    for _, bounty in pairs(RC.db.bounties) do
        if bounty.status == "open" or bounty.status == "claimed" or bounty.status == "denied" then
            bounties = bounties + 1
        end
    end
    self.summary:SetText(
        "Gankers: |cffffffff" .. gankers .. "|r     KOS guilds: |cffffffff" .. guilds ..
        "|r     Open bounties: |cffffffff" .. bounties .. "|r\n" ..
        "Last update from a guildmate: |cffffffff" .. TimeAgo(RC.db.lastSyncReceived) .. "|r")
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
        wipe(RC.db.syncLog)
        SyncLog.messages:Clear()
    end)
    clear:SetPoint("LEFT", syncNow, "RIGHT", 8, 0)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", syncNow, "BOTTOMLEFT", 0, -12)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    Theme.SkinWindow(box)

    local messages = CreateFrame("ScrollingMessageFrame", nil, box)
    messages:SetPoint("TOPLEFT", 10, -10)
    messages:SetPoint("BOTTOMRIGHT", -10, 10)
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
        for _, entry in ipairs(RC.db.syncLog) do
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
