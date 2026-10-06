-- Rallying Cry - Ganker List and Bounties
-- A guild-shared list of gankers, with gold bounties guildmates can pledge on
-- them. The addon can't hold or move gold: a bounty is a pledge, the hunter
-- claims it, the poster confirms the kill and mails the gold themselves.
--
-- Every ganker and every bounty is a record stamped with server time. Changes
-- go to the whole guild and the newest stamp wins. On login a client asks for
-- records it missed, and one guildmate answers for everyone.

local RC = RallyingCry

local Gankers = {}
RC.Gankers = Gankers

-- Guild rank indexes that count as officers (0 is the Guild Master). Officers
-- can remove anyone from the list; everyone else only their own additions.
local OFFICER_RANK_MAX = 1

-- Removed gankers and finished bounties are dropped after this many seconds
local PURGE_AFTER = 30 * 24 * 60 * 60

-- Responders wait a random delay so only one of them answers a sync request
local SYNC_DELAY_MIN, SYNC_DELAY_MAX = 2, 10

-- Seconds between sync messages, under the game's addon message throttle
local SYNC_PACE = 1.1
local SYNC_MAX_RECORDS = 150

-- Don't repeat the "ganker spotted" warning for the same player within this many seconds
local WARN_COOLDOWN = 60

local MAX_BOUNTY = 1000000

-- open: waiting for a hunter. claimed: hunter says they got the kill.
-- denied: poster said no, can be claimed again. paid / withdrawn: finished.
local BOUNTY_STATUS = { open = true, claimed = true, denied = true, paid = true, withdrawn = true }
local BOUNTY_ACTIVE = { open = true, claimed = true, denied = true }
local BOUNTY_CLAIMABLE = { open = true, denied = true }

local CLAIM_POPUP = "RALLYINGCRY_CLAIM"

local rankByName = {}
local warnedAt = {}
local pendingSync = {}
local sendQueue = {}
local sendTicker
local shownClaims = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function Now()
    return GetServerTime()
end

local function OrNil(value)
    value = RC.CleanText(value)
    return value ~= "" and value or nil
end

local function Me()
    return RC:PlayerFullName()
end

local function BountyKey(name, poster)
    return name .. "|" .. poster
end

-- Next stamp for a record, always past the one it replaces so two edits in
-- the same second still apply in order
local function NextStamp(current)
    local now = Now()
    if current and current.updated and current.updated >= now then
        return current.updated + 1
    end
    return now
end

function RC.FormatGold(gold)
    local text = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    return "|cffffd100" .. text .. "g|r"
end

----------------------------------------------------------------------
-- Guild ranks
----------------------------------------------------------------------

function Gankers:RefreshRoster()
    wipe(rankByName)
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        name = name and RC.NormalizeName(name)
        if name then
            rankByName[name] = rankIndex
        end
    end
end

function Gankers:IsOfficer(name)
    local rank = rankByName[name]
    return rank ~= nil and rank <= OFFICER_RANK_MAX
end

function Gankers:CanRemove(name, ganker)
    return ganker ~= nil and (name == ganker.addedBy or self:IsOfficer(name))
end

----------------------------------------------------------------------
-- Wire format
-- KOS  ~ relay ~ name ~ addedBy ~ reports ~ lastSeen ~ updated ~ removedBy ~ zone ~ reason
-- BNTY ~ relay ~ name ~ poster ~ gold ~ status ~ claimant ~ updated
-- relay is "r" when the record is being passed along in a sync, empty when
-- the sender made the change themselves.
----------------------------------------------------------------------

local function EncodeGanker(g, relay)
    return RC.Pack("KOS", relay and "r" or "", g.name, g.addedBy, g.reports or 0, g.lastSeen or "",
        g.updated, g.removedBy or "", RC.CleanText(g.zone, 40), RC.CleanText(g.reason, 60))
end

local function EncodeBounty(b, relay)
    return RC.Pack("BNTY", relay and "r" or "", b.name, b.poster, b.gold, b.status, b.claimant or "", b.updated)
end

local function Refresh()
    if RC.GankerList then
        RC.GankerList:Refresh()
    end
end

----------------------------------------------------------------------
-- Merging
----------------------------------------------------------------------

-- Store a ganker record if it's newer than ours. Returns true if it was.
function Gankers:MergeGanker(record)
    local current = RC.db.gankers[record.name]
    if current and current.updated >= record.updated then
        return false
    end
    RC.db.gankers[record.name] = record
    Refresh()
    return true
end

function Gankers:MergeBounty(record, live)
    local key = BountyKey(record.name, record.poster)
    local previous = RC.db.bounties[key]
    if previous and previous.updated >= record.updated then
        return false
    end
    RC.db.bounties[key] = record
    self:OnBountyChanged(record, previous, live)
    Refresh()
    return true
end

function Gankers:OnBountyChanged(bounty, previous, live)
    local me = Me()
    local target = RC.DisplayName(bounty.name)

    if bounty.poster == me and bounty.status == "claimed" then
        self:ShowClaimPopup(bounty)
        return
    end
    if not live then
        return
    end

    local poster = RC.DisplayName(bounty.poster)
    if bounty.claimant == me and bounty.poster ~= me then
        if bounty.status == "paid" then
            RC:Print(RC.COLORS.SUCCESS .. poster .. " confirmed your kill on " .. target .. ".|r Expect " ..
                RC.FormatGold(bounty.gold) .. " in the mail.")
        elseif bounty.status == "denied" then
            RC:Print(RC.COLORS.WARNING .. poster .. " denied your claim on " .. target .. ".|r")
        end
    elseif bounty.status == "open" and not (previous and BOUNTY_ACTIVE[previous.status]) then
        RC:Print(poster .. " put a " .. RC.FormatGold(bounty.gold) .. " bounty on " ..
            RC.COLORS.ERROR .. target .. "|r.")
    end
end

----------------------------------------------------------------------
-- Making changes (each one is stored locally, then sent to the guild)
----------------------------------------------------------------------

local function Publish(kind, record)
    if kind == "KOS" then
        Gankers:MergeGanker(record)
        RC:SendGuild(EncodeGanker(record))
    else
        Gankers:MergeBounty(record, false)
        RC:SendGuild(EncodeBounty(record))
    end
end

local function RequireGuild()
    if IsInGuild() then
        return true
    end
    RC:Print(RC.COLORS.ERROR .. "You need to be in a guild to use the ganker list.|r")
    return false
end

-- Listed (and not removed) ganker record, or nil
function Gankers:Get(name)
    local ganker = name and RC.db.gankers[name]
    if ganker and not ganker.removedBy then
        return ganker
    end
end

-- Sighting from one of our own alerts: add them, or bump their report count
function Gankers:Report(name, zone)
    name = RC.NormalizeName(name)
    if not name or not IsInGuild() then
        return
    end
    local current = self:Get(name)
    Publish("KOS", {
        name = name,
        addedBy = current and current.addedBy or Me(),
        reason = current and current.reason,
        reports = (current and current.reports or 0) + 1,
        lastSeen = Now(),
        zone = zone,
        updated = NextStamp(RC.db.gankers[name]),
    })
end

function Gankers:Add(name, reason)
    name = RC.NormalizeName(name)
    if not name then
        RC:Print("Usage: /rc kos add <name> [reason]")
        return
    end
    if not RequireGuild() then
        return
    end
    reason = OrNil(reason)
    local current = self:Get(name)
    Publish("KOS", {
        name = name,
        addedBy = current and current.addedBy or Me(),
        reason = reason or (current and current.reason),
        reports = current and current.reports or 0,
        lastSeen = current and current.lastSeen,
        zone = current and current.zone,
        updated = NextStamp(RC.db.gankers[name]),
    })
    RC:Print((current and "Updated " or "Added ") .. RC.COLORS.ERROR .. RC.DisplayName(name) ..
        "|r " .. (current and "on" or "to") .. " the guild ganker list.")
end

function Gankers:Remove(name)
    name = RC.NormalizeName(name)
    local current = self:Get(name)
    if not current then
        RC:Print((name and RC.DisplayName(name) or "That player") .. " isn't on the ganker list.")
        return
    end
    if not self:CanRemove(Me(), current) then
        RC:Print(RC.COLORS.WARNING .. "Only " .. RC.DisplayName(current.addedBy) ..
            " (who added them) or an officer can remove " .. RC.DisplayName(name) .. ".|r")
        return
    end
    local record = CopyTable(current)
    record.removedBy = Me()
    record.updated = NextStamp(current)
    Publish("KOS", record)
    RC:Print("Removed " .. RC.DisplayName(name) .. " from the ganker list.")
end

-- Pledge gold on a ganker, or withdraw your bounty with 0
function Gankers:PostBounty(name, gold)
    name = RC.NormalizeName(name)
    gold = math.floor(tonumber(gold) or -1)
    if not name or gold < 0 then
        RC:Print("Usage: /rc bounty <name> <gold>  (0 withdraws your bounty)")
        return
    end
    if gold > MAX_BOUNTY then
        RC:Print(RC.COLORS.WARNING .. "Bounties top out at " .. RC.FormatGold(MAX_BOUNTY) .. ".|r")
        return
    end
    if not RequireGuild() then
        return
    end

    local me = Me()
    local current = RC.db.bounties[BountyKey(name, me)]
    local display = RC.DisplayName(name)

    if gold == 0 then
        if not (current and BOUNTY_ACTIVE[current.status]) then
            RC:Print("You don't have a bounty on " .. display .. ".")
            return
        end
        local record = CopyTable(current)
        record.status = "withdrawn"
        record.updated = NextStamp(current)
        Publish("BNTY", record)
        RC:Print("Withdrew your bounty on " .. display .. ".")
        return
    end

    if current and current.status == "claimed" then
        RC:Print(RC.COLORS.WARNING .. "Settle the open claim on " .. display .. " first.|r")
        return
    end

    if not self:Get(name) then
        self:Add(name, "Bounty target")
    end
    Publish("BNTY", {
        name = name,
        poster = me,
        gold = gold,
        status = "open",
        updated = NextStamp(current),
    })
    RC:Print("Your bounty on " .. RC.COLORS.ERROR .. display .. "|r is now " .. RC.FormatGold(gold) .. ".")
end

-- Claim every open bounty on a ganker (other than your own)
function Gankers:Claim(name)
    name = RC.NormalizeName(name)
    if not name then
        RC:Print("Usage: /rc claim <name>")
        return
    end
    if not RequireGuild() then
        return
    end
    local me = Me()
    local count, total = 0, 0
    for _, bounty in pairs(RC.db.bounties) do
        if bounty.name == name and bounty.poster ~= me and BOUNTY_CLAIMABLE[bounty.status] then
            local record = CopyTable(bounty)
            record.status = "claimed"
            record.claimant = me
            record.updated = NextStamp(bounty)
            Publish("BNTY", record)
            count = count + 1
            total = total + bounty.gold
        end
    end
    if count == 0 then
        RC:Print("There's no open bounty on " .. RC.DisplayName(name) .. " to claim.")
    else
        RC:Print("Claimed " .. count .. (count == 1 and " bounty" or " bounties") .. " worth " ..
            RC.FormatGold(total) .. " on " .. RC.DisplayName(name) .. ". The posters will confirm.")
    end
end

function Gankers:ResolveClaim(key, confirmed)
    local bounty = RC.db.bounties[key]
    shownClaims[key] = nil
    if not bounty or bounty.status ~= "claimed" or bounty.poster ~= Me() then
        return
    end
    local record = CopyTable(bounty)
    record.status = confirmed and "paid" or "denied"
    record.updated = NextStamp(bounty)
    Publish("BNTY", record)
    if confirmed then
        RC:Print(RC.COLORS.SUCCESS .. "Bounty paid out.|r Mail " .. RC.FormatGold(bounty.gold) .. " to " ..
            RC.DisplayName(bounty.claimant) .. ".")
    else
        RC:Print("Denied " .. RC.DisplayName(bounty.claimant) .. "'s claim on " .. RC.DisplayName(bounty.name) ..
            ". Your bounty is open again.")
    end
end

----------------------------------------------------------------------
-- Queries for the list window
----------------------------------------------------------------------

function Gankers:ActiveBounties(name)
    local list, total = {}, 0
    for _, bounty in pairs(RC.db.bounties) do
        if bounty.name == name and BOUNTY_ACTIVE[bounty.status] then
            table.insert(list, bounty)
            total = total + bounty.gold
        end
    end
    table.sort(list, function(a, b) return a.gold > b.gold end)
    return list, total
end

-- True if you can claim at least one bounty on this ganker
function Gankers:CanClaim(name)
    local me = Me()
    for _, bounty in pairs(RC.db.bounties) do
        if bounty.name == name and bounty.poster ~= me and BOUNTY_CLAIMABLE[bounty.status] then
            return true
        end
    end
    return false
end

-- Listed gankers, biggest bounty first, then most recently seen
function Gankers:Sorted()
    local rows = {}
    for name, ganker in pairs(RC.db.gankers) do
        if not ganker.removedBy then
            local _, total = self:ActiveBounties(name)
            table.insert(rows, { ganker = ganker, bounty = total })
        end
    end
    table.sort(rows, function(a, b)
        if a.bounty ~= b.bounty then
            return a.bounty > b.bounty
        end
        return (a.ganker.lastSeen or a.ganker.updated) > (b.ganker.lastSeen or b.ganker.updated)
    end)
    return rows
end

----------------------------------------------------------------------
-- Claim confirmation popup (for the bounty poster)
----------------------------------------------------------------------

StaticPopupDialogs[CLAIM_POPUP] = {
    text = "%s",
    button1 = "Confirm",
    button2 = "Deny",
    OnAccept = function(dialog, key)
        Gankers:ResolveClaim(key, true)
    end,
    OnCancel = function(dialog, key)
        Gankers:ResolveClaim(key, false)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    showAlert = true,
    multiple = 1,
}

function Gankers:ShowClaimPopup(bounty)
    local key = BountyKey(bounty.name, bounty.poster)
    if shownClaims[key] then
        return
    end
    local text = RC.DisplayName(bounty.claimant) .. " claims your " .. RC.FormatGold(bounty.gold) ..
        " bounty on " .. RC.COLORS.ERROR .. RC.DisplayName(bounty.name) .. "|r.\n\n" ..
        "Confirm if they got the kill. You'll mail the gold yourself."
    if StaticPopup_Show(CLAIM_POPUP, text, nil, key) then
        shownClaims[key] = true
    end
end

-- Claims that came in while we were offline, or before a /reload
function Gankers:ShowPendingClaims()
    local me = Me()
    for _, bounty in pairs(RC.db.bounties) do
        if bounty.poster == me and bounty.status == "claimed" then
            self:ShowClaimPopup(bounty)
        end
    end
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

RC.MessageHandlers.KOS = function(_, sender, relay, name, addedBy, reports, lastSeen, updated, removedBy, zone, reason)
    local record = {
        name = RC.NormalizeName(name),
        addedBy = OrNil(addedBy),
        reports = tonumber(reports) or 0,
        lastSeen = tonumber(lastSeen),
        updated = tonumber(updated),
        removedBy = OrNil(removedBy),
        zone = OrNil(zone),
        reason = OrNil(reason),
    }
    if not (record.name and record.addedBy and record.updated) then
        return
    end
    if record.removedBy then
        -- Removals have to come from the remover, unless relayed in a sync,
        -- and the remover has to be allowed to remove
        if relay ~= "r" and sender ~= record.removedBy then
            return
        end
        if not Gankers:CanRemove(record.removedBy, record) then
            RC:Debug("ignored removal of " .. record.name .. " by " .. record.removedBy)
            return
        end
    end
    Gankers:MergeGanker(record)
end

RC.MessageHandlers.BNTY = function(_, sender, relay, name, poster, gold, status, claimant, updated)
    local record = {
        name = RC.NormalizeName(name),
        poster = OrNil(poster),
        gold = tonumber(gold),
        status = status,
        claimant = OrNil(claimant),
        updated = tonumber(updated),
    }
    if not (record.name and record.poster and record.gold and record.updated and BOUNTY_STATUS[status]) then
        return
    end
    if record.gold < 0 or record.gold > MAX_BOUNTY then
        return
    end
    -- Live changes come from the poster, or from the hunter making a claim
    if relay ~= "r" and sender ~= record.poster and not (status == "claimed" and sender == record.claimant) then
        return
    end
    Gankers:MergeBounty(record, relay ~= "r")
end

----------------------------------------------------------------------
-- Sync
-- SYNCREQ ~ requester ~ since       "send me anything newer than since"
-- SYNCACK ~ requester ~ latest      "I'm answering, and I'm current up to latest"
----------------------------------------------------------------------

function Gankers:LatestStamp()
    local latest = 0
    for _, ganker in pairs(RC.db.gankers) do
        latest = math.max(latest, ganker.updated)
    end
    for _, bounty in pairs(RC.db.bounties) do
        latest = math.max(latest, bounty.updated)
    end
    return latest
end

local function RecordsSince(since)
    local records = {}
    for _, ganker in pairs(RC.db.gankers) do
        if ganker.updated > since then
            table.insert(records, { updated = ganker.updated, payload = EncodeGanker(ganker, true) })
        end
    end
    for _, bounty in pairs(RC.db.bounties) do
        if bounty.updated > since then
            table.insert(records, { updated = bounty.updated, payload = EncodeBounty(bounty, true) })
        end
    end
    table.sort(records, function(a, b) return a.updated > b.updated end)
    for i = #records, SYNC_MAX_RECORDS + 1, -1 do
        records[i] = nil
    end
    return records
end

local function SendNextQueued()
    local payload = sendQueue[1]
    if not payload then
        sendTicker:Cancel()
        sendTicker = nil
        return
    end
    -- Throttled sends stay at the front of the queue and go next tick
    if RC:SendGuild(payload) then
        table.remove(sendQueue, 1)
    end
end

local function QueueRecords(records)
    for _, record in ipairs(records) do
        table.insert(sendQueue, record.payload)
    end
    if not sendTicker and #sendQueue > 0 then
        sendTicker = C_Timer.NewTicker(SYNC_PACE, SendNextQueued)
    end
end

function Gankers:RequestSync()
    if IsInGuild() then
        RC:SendGuild(RC.Pack("SYNCREQ", Me(), self:LatestStamp()))
    end
end

RC.MessageHandlers.SYNCREQ = function(_, sender, requester, since)
    since = tonumber(since)
    if requester ~= sender or not since or pendingSync[requester] then
        return
    end
    if #RecordsSince(since) == 0 then
        return
    end
    local delay = SYNC_DELAY_MIN + math.random() * (SYNC_DELAY_MAX - SYNC_DELAY_MIN)
    pendingSync[requester] = C_Timer.NewTimer(delay, function()
        pendingSync[requester] = nil
        RC:SendGuild(RC.Pack("SYNCACK", requester, Gankers:LatestStamp()))
        QueueRecords(RecordsSince(since))
        RC:Debug("answering sync for " .. requester)
    end)
end

RC.MessageHandlers.SYNCACK = function(_, sender, requester, latest)
    local timer = pendingSync[requester]
    -- Stand down unless we know about newer changes than the one answering
    if timer and Gankers:LatestStamp() <= (tonumber(latest) or 0) then
        timer:Cancel()
        pendingSync[requester] = nil
    end
end

local function Purge()
    local cutoff = Now() - PURGE_AFTER
    for name, ganker in pairs(RC.db.gankers) do
        if ganker.removedBy and ganker.updated < cutoff then
            RC.db.gankers[name] = nil
        end
    end
    for key, bounty in pairs(RC.db.bounties) do
        if not BOUNTY_ACTIVE[bounty.status] and bounty.updated < cutoff then
            RC.db.bounties[key] = nil
        end
    end
end

----------------------------------------------------------------------
-- "Ganker spotted" warnings
----------------------------------------------------------------------

function Gankers:CheckUnit(unit)
    if not RC.db.kosWarn then
        return
    end
    local name = RC:GetHostileUnitName(unit)
    local ganker = self:Get(name)
    if not ganker then
        return
    end
    local now = GetTime()
    if warnedAt[name] and now - warnedAt[name] < WARN_COOLDOWN then
        return
    end
    warnedAt[name] = now

    local _, bounty = self:ActiveBounties(name)
    local details = "reported " .. ganker.reports .. (ganker.reports == 1 and " time" or " times")
    if bounty > 0 then
        details = details .. ", bounty " .. RC.FormatGold(bounty)
    end
    local text = RC.COLORS.ERROR .. "Ganker spotted: " .. RC.DisplayName(name) .. "|r (" .. details .. ")"
    RC:Print(text)
    UIErrorsFrame:AddMessage(text)
    if RC.db.sound then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Purge()
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
            -- Give the guild channel a moment to come up before asking
            C_Timer.After(8, function()
                Gankers:RequestSync()
                Gankers:ShowPendingClaims()
            end)
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        Gankers:RefreshRoster()
    elseif event == "PLAYER_TARGET_CHANGED" then
        Gankers:CheckUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Gankers:CheckUnit("mouseover")
    end
end)
