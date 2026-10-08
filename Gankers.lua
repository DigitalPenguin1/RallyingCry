-- Rallying Cry - Ganker List and Bounties
-- A guild-shared list of gankers, with gold bounties guildmates can pledge on
-- them, plus a list of KOS guilds whose members all count as gankers. The addon can't hold or move gold: a bounty is a pledge, the hunter
-- claims it, the poster confirms the kill and mails the gold themselves.
--
-- Every ganker and every bounty is a record stamped with server time. Changes
-- go to the whole guild and the newest stamp wins. On login a client asks for
-- records it missed, and one guildmate answers for everyone.

local RC = RallyingCry

local Gankers = {}
RC.Gankers = Gankers

-- Officers are ranks with the guild's "Remove Member" permission. If a client
-- can't read rank permissions, rank indexes up to this one count instead
-- (0 is the Guild Master). Officers can remove anyone from the ganker list,
-- and only officers can add or remove KOS guilds.
local REMOVE_MEMBER_FLAG = 8
local OFFICER_RANK_FALLBACK = 1

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
-- Set once the login sync is scheduled; guild changes after that ask on their own
local loginSyncScheduled = false

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

local officerRanks = {}

-- rankIndex is 0-based (roster), rank flags are looked up 1-based
local function RankIsOfficer(rankIndex)
    if officerRanks[rankIndex] == nil then
        local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rankIndex + 1)
        if ok and type(flags) == "table" and flags[REMOVE_MEMBER_FLAG] ~= nil then
            officerRanks[rankIndex] = flags[REMOVE_MEMBER_FLAG] == true
        else
            officerRanks[rankIndex] = rankIndex <= OFFICER_RANK_FALLBACK
        end
    end
    return officerRanks[rankIndex]
end

function Gankers:RefreshRoster()
    wipe(rankByName)
    wipe(officerRanks)
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        name = name and RC.NormalizeName(name)
        if name then
            rankByName[name] = rankIndex
        end
    end
end

function Gankers:IsOfficer(name)
    -- Sync messages can arrive before the first roster update
    if next(rankByName) == nil then
        self:RefreshRoster()
    end
    local rank = rankByName[name]
    return rank ~= nil and RankIsOfficer(rank)
end

function Gankers:CanRemove(name, ganker)
    return ganker ~= nil and (name == ganker.addedBy or self:IsOfficer(name))
end

----------------------------------------------------------------------
-- Wire format
-- KOS  ~ relay ~ name ~ addedBy ~ reports ~ lastSeen ~ updated ~ removedBy ~ zone ~ reason ~ guild
-- BNTY ~ relay ~ name ~ poster ~ gold ~ status ~ claimant ~ updated
-- KOSG ~ relay ~ guild ~ realm ~ addedBy ~ updated ~ removedBy ~ reason ~ numbered
-- relay is "r" when the record is being passed along in a sync, empty when
-- the sender made the change themselves.
----------------------------------------------------------------------

local function EncodeGanker(g, relay)
    return RC.Pack("KOS", relay and "r" or "", g.name, g.addedBy, g.reports or 0, g.lastSeen or "",
        g.updated, g.removedBy or "", RC.CleanText(g.zone, 40), RC.CleanText(g.reason, 50),
        RC.CleanText(g.guild, 30))
end

local function EncodeGuild(g, relay)
    return RC.Pack("KOSG", relay and "r" or "", RC.CleanText(g.name, 30), g.realm or "", g.addedBy,
        g.updated, g.removedBy or "", RC.CleanText(g.reason, 60), g.numbered and "1" or "")
end

-- Matches on the guild name alone. Forever has no realms, and elsewhere
-- guild names rarely clash across connected realms.
local function GuildKey(name)
    return name:lower()
end

-- Guild families. A KOS entry can cover more than one guild:
--   numbered: "Olympus" also matches Olympus 2, Olympus II, Olympus #3, Olympus2
--   wildcard: "Olympus*" matches every guild whose name starts with Olympus
local MIN_WILDCARD_PREFIX = 3

local function IsWildcard(name)
    return name:sub(-1) == "*"
end

local function HasNumberSuffix(rest)
    return rest:match("^[%s%-#]*%d+$") ~= nil or rest:match("^%s+[IVXLivxl]+$") ~= nil
end

local function EntryMatches(entry, guildName)
    local base, guild = entry.name:lower(), guildName:lower()
    if IsWildcard(base) then
        local prefix = base:sub(1, -2)
        return #prefix >= MIN_WILDCARD_PREFIX and guild:sub(1, #prefix) == prefix
    end
    if guild == base then
        return true
    end
    return entry.numbered == true and guild:sub(1, #base) == base and HasNumberSuffix(guildName:sub(#base + 1))
end

-- "Olympus 2" -> "Olympus", "Olympus III" -> "Olympus". Nil if it isn't numbered.
function RC.GuildBaseName(name)
    local base = name:match("^(.-)[%s%-#]*%d+$") or name:match("^(.-)%s+[IVXL]+$")
    if base and base:match("%S") then
        return base
    end
end

-- "<Olympus> + numbered" or "<Olympus*>" for lists and chat
function RC.GuildLabel(entry)
    local label = "<" .. entry.name .. ">"
    if entry.numbered and not IsWildcard(entry.name) then
        label = label .. " |cff808080+ numbered|r"
    end
    return label
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
    local current = RC.guild.gankers[record.name]
    if current and current.updated >= record.updated then
        return false
    end
    RC.guild.gankers[record.name] = record
    if Gankers.imported then
        table.insert(Gankers.imported, { updated = record.updated, payload = EncodeGanker(record, true) })
    end
    Refresh()
    return true
end

function Gankers:MergeGuild(record)
    local key = GuildKey(record.name)
    local current = RC.guild.kosGuilds[key]
    if current and current.updated >= record.updated then
        return false
    end
    RC.guild.kosGuilds[key] = record
    if Gankers.imported then
        table.insert(Gankers.imported, { updated = record.updated, payload = EncodeGuild(record, true) })
    end
    Refresh()
    return true
end

function Gankers:MergeBounty(record, live)
    local key = BountyKey(record.name, record.poster)
    local previous = RC.guild.bounties[key]
    if previous and previous.updated >= record.updated then
        return false
    end
    RC.guild.bounties[key] = record
    if Gankers.imported then
        table.insert(Gankers.imported, { updated = record.updated, payload = EncodeBounty(record, true) })
    end
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
    elseif kind == "KOSG" then
        Gankers:MergeGuild(record)
        RC:SendGuild(EncodeGuild(record))
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
    local ganker = name and RC.guild.gankers[name]
    if ganker and not ganker.removedBy then
        return ganker
    end
end

-- Sighting from one of our own alerts: add them, or bump their report count
function Gankers:Report(name, zone, guild)
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
        guild = guild or (current and current.guild),
        updated = NextStamp(RC.guild.gankers[name]),
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
        guild = current and current.guild,
        updated = NextStamp(RC.guild.gankers[name]),
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

-- Listed (and not removed) KOS guild record, or nil
function Gankers:GetGuild(name)
    local guild = name and RC.guild.kosGuilds[GuildKey(name)]
    if guild and not guild.removedBy then
        return guild
    end
end

-- numbered defaults to on: adding "Olympus" covers Olympus 2, Olympus II, ...
function Gankers:AddGuild(name, realm, reason, numbered)
    name = OrNil(RC.CleanText(name, 30))
    if numbered == nil then
        numbered = true
    end
    if not name then
        RC:Print("Usage: /rc kos guild add <guild name> [- reason]")
        return
    end
    if not RequireGuild() then
        return
    end
    if not self:IsOfficer(Me()) then
        RC:Print(RC.COLORS.WARNING .. "Only officers can add KOS guilds.|r")
        return
    end
    if IsWildcard(name) and #name - 1 < MIN_WILDCARD_PREFIX then
        RC:Print(RC.COLORS.WARNING .. "Use at least " .. MIN_WILDCARD_PREFIX .. " letters before the *.|r")
        return
    end
    local myGuild = GetGuildInfo("player")
    if myGuild and EntryMatches({ name = name, numbered = numbered }, myGuild) then
        RC:Print(RC.COLORS.WARNING .. "That would include your own guild.|r")
        return
    end
    reason = OrNil(reason)
    local current = self:GetGuild(name)
    Publish("KOSG", {
        name = current and current.name or name,
        realm = realm or (current and current.realm),
        addedBy = current and current.addedBy or Me(),
        reason = reason or (current and current.reason),
        numbered = numbered and not IsWildcard(name) or nil,
        updated = NextStamp(RC.guild.kosGuilds[GuildKey(name)]),
    })
    local covers = ""
    if IsWildcard(name) then
        covers = " Covers every guild starting with " .. name:sub(1, -2) .. "."
    elseif numbered then
        covers = " Also covers " .. name .. " 2, " .. name .. " II, and so on."
    end
    RC:Print((current and "Updated " or "Added ") .. RC.COLORS.ERROR .. "<" .. name .. ">|r " ..
        (current and "on" or "to") .. " the KOS guild list." .. covers)
end

function Gankers:RemoveGuild(name)
    local current = self:GetGuild(OrNil(name))
    if not current then
        RC:Print("<" .. (name or "") .. "> isn't on the KOS guild list.")
        return
    end
    if not self:IsOfficer(Me()) then
        RC:Print(RC.COLORS.WARNING .. "Only officers can remove KOS guilds.|r")
        return
    end
    local record = CopyTable(current)
    record.removedBy = Me()
    record.updated = NextStamp(current)
    Publish("KOSG", record)
    RC:Print("Removed <" .. current.name .. "> from the KOS guild list.")
end

-- The KOS entry that covers a guild (exactly, as a numbered alt, or by
-- wildcard), or nil
function Gankers:MatchGuild(guildName)
    if not guildName then
        return nil
    end
    local exact = self:GetGuild(guildName)
    if exact then
        return exact
    end
    for _, entry in pairs(RC.guild.kosGuilds) do
        if not entry.removedBy and EntryMatches(entry, guildName) then
            return entry
        end
    end
end

function Gankers:SortedGuilds()
    local rows = {}
    for _, guild in pairs(RC.guild.kosGuilds) do
        if not guild.removedBy then
            table.insert(rows, guild)
        end
    end
    table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
    return rows
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
    local current = RC.guild.bounties[BountyKey(name, me)]
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
    for _, bounty in pairs(RC.guild.bounties) do
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
    local bounty = RC.guild.bounties[key]
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
    for _, bounty in pairs(RC.guild.bounties) do
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
    for _, bounty in pairs(RC.guild.bounties) do
        if bounty.name == name and bounty.poster ~= me and BOUNTY_CLAIMABLE[bounty.status] then
            return true
        end
    end
    return false
end

-- Listed gankers, biggest bounty first, then most recently seen
function Gankers:Sorted()
    local rows = {}
    for name, ganker in pairs(RC.guild.gankers) do
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
    for _, bounty in pairs(RC.guild.bounties) do
        if bounty.poster == me and bounty.status == "claimed" then
            self:ShowClaimPopup(bounty)
        end
    end
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

RC.MessageHandlers.KOS = function(_, sender, relay, name, addedBy, reports, lastSeen, updated, removedBy, zone, reason, guild)
    local record = {
        name = RC.NormalizeName(name),
        addedBy = RC.NormalizeName(addedBy),
        reports = tonumber(reports) or 0,
        lastSeen = tonumber(lastSeen),
        updated = tonumber(updated),
        removedBy = RC.NormalizeName(removedBy),
        zone = OrNil(zone),
        reason = OrNil(reason),
        guild = OrNil(guild),
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
            RC.SyncLog:Add("Ignored " .. RC.DisplayName(sender) .. "'s removal of " .. RC.DisplayName(record.name) ..
                " (" .. RC.DisplayName(record.removedBy) .. " can't remove it)")
            return
        end
    end
    RC.SyncLog:CountRecord(sender, relay == "r", "KOS", Gankers:MergeGanker(record), RC.DisplayName(record.name))
end

RC.MessageHandlers.BNTY = function(_, sender, relay, name, poster, gold, status, claimant, updated)
    local record = {
        name = RC.NormalizeName(name),
        poster = RC.NormalizeName(poster),
        gold = tonumber(gold),
        status = status,
        claimant = RC.NormalizeName(claimant),
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
        RC.SyncLog:Add("Ignored a bounty change from " .. RC.DisplayName(sender) .. " (not theirs to change)")
        return
    end
    RC.SyncLog:CountRecord(sender, relay == "r", "BNTY", Gankers:MergeBounty(record, relay ~= "r"),
        RC.DisplayName(record.name))
end

RC.MessageHandlers.KOSG = function(_, sender, relay, name, realm, addedBy, updated, removedBy, reason, numbered)
    local record = {
        name = OrNil(RC.CleanText(name, 30)),
        realm = OrNil(realm),
        addedBy = RC.NormalizeName(addedBy),
        updated = tonumber(updated),
        removedBy = RC.NormalizeName(removedBy),
        reason = OrNil(reason),
        numbered = numbered == "1" or nil,
    }
    if not (record.name and record.addedBy and record.updated) then
        return
    end
    -- Officers only: whoever made the change (the adder, or the remover) has
    -- to be an officer, and a live change has to come from them directly
    local actor = record.removedBy or record.addedBy
    if relay ~= "r" and sender ~= actor and not (record.removedBy == nil and Gankers:IsOfficer(sender)) then
        return
    end
    if not Gankers:IsOfficer(actor) then
        RC.SyncLog:Add("Ignored a KOS guild change to <" .. record.name .. "> from " .. RC.DisplayName(sender) ..
            " (" .. RC.DisplayName(actor) .. " isn't an officer)")
        return
    end
    RC.SyncLog:CountRecord(sender, relay == "r", "KOSG", Gankers:MergeGuild(record), "<" .. record.name .. ">")
end

----------------------------------------------------------------------
-- Sync
-- SYNCREQ ~ requester ~ since       "send me anything newer than since"
-- SYNCACK ~ requester ~ latest      "I'm answering, and I'm current up to latest"
----------------------------------------------------------------------

function Gankers:LatestStamp()
    local latest = 0
    for _, ganker in pairs(RC.guild.gankers) do
        latest = math.max(latest, ganker.updated)
    end
    for _, bounty in pairs(RC.guild.bounties) do
        latest = math.max(latest, bounty.updated)
    end
    for _, guild in pairs(RC.guild.kosGuilds) do
        latest = math.max(latest, guild.updated)
    end
    return latest
end

local function RecordsSince(since)
    local records = {}
    for _, ganker in pairs(RC.guild.gankers) do
        if ganker.updated > since then
            table.insert(records, { updated = ganker.updated, payload = EncodeGanker(ganker, true) })
        end
    end
    for _, bounty in pairs(RC.guild.bounties) do
        if bounty.updated > since then
            table.insert(records, { updated = bounty.updated, payload = EncodeBounty(bounty, true) })
        end
    end
    for _, guild in pairs(RC.guild.kosGuilds) do
        if guild.updated > since then
            table.insert(records, { updated = guild.updated, payload = EncodeGuild(guild, true) })
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
        -- An oversized record would fail forever and stall the queue
        if #record.payload <= RC.MAX_MESSAGE then
            table.insert(sendQueue, record.payload)
        end
    end
    if not sendTicker and #sendQueue > 0 then
        sendTicker = C_Timer.NewTicker(SYNC_PACE, SendNextQueued)
    end
end

function Gankers:RequestSync()
    if not IsInGuild() then
        return
    end
    local since = self:LatestStamp()
    if RC:SendGuild(RC.Pack("SYNCREQ", Me(), since)) then
        RC.SyncLog:Add(since == 0 and "Asked the guild for the full list" or
            "Asked the guild for anything new since " .. date("%m/%d %H:%M", since))
    else
        RC.SyncLog:Add("Couldn't ask the guild for updates right now. Try Sync Now later.")
    end
end

RC.MessageHandlers.SYNCREQ = function(_, sender, requester, since)
    requester = RC.NormalizeName(requester)
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
        local records = RecordsSince(since)
        QueueRecords(records)
        RC.SyncLog:Add("Sending " .. #records .. (#records == 1 and " update" or " updates") .. " to |cffffffff" ..
            RC.DisplayName(requester) .. "|r, who just logged in")
    end)
end

RC.MessageHandlers.SYNCACK = function(_, sender, requester, latest)
    requester = RC.NormalizeName(requester)
    if requester == Me() then
        RC.SyncLog:Add("|cffffffff" .. RC.DisplayName(sender) .. "|r is sending you updates")
    end
    local timer = pendingSync[requester]
    -- Stand down unless we know about newer changes than the one answering
    if timer and Gankers:LatestStamp() <= (tonumber(latest) or 0) then
        timer:Cancel()
        pendingSync[requester] = nil
    end
end

-- Joined, left, or switched guilds: drop anything tied to the old one
function Gankers:OnGuildChanged()
    wipe(rankByName)
    wipe(warnedAt)
    wipe(shownClaims)
    wipe(sendQueue)
    for requester, timer in pairs(pendingSync) do
        timer:Cancel()
        pendingSync[requester] = nil
    end
    Refresh()
    -- Joined a guild mid-session: fetch its list instead of waiting for a relog
    if loginSyncScheduled and RC.guildName then
        C_Timer.After(3, function()
            Gankers:RequestSync()
        end)
    end
end

local function Purge()
    local cutoff = Now() - PURGE_AFTER
    for name, ganker in pairs(RC.guild.gankers) do
        if ganker.removedBy and ganker.updated < cutoff then
            RC.guild.gankers[name] = nil
        end
    end
    for key, bounty in pairs(RC.guild.bounties) do
        if not BOUNTY_ACTIVE[bounty.status] and bounty.updated < cutoff then
            RC.guild.bounties[key] = nil
        end
    end
    for key, guild in pairs(RC.guild.kosGuilds) do
        if guild.removedBy and guild.updated < cutoff then
            RC.guild.kosGuilds[key] = nil
        end
    end
end

----------------------------------------------------------------------
-- Backup (export / import)
-- A backup is every record written as its sync message, one per line,
-- after a header line, then compressed and base64 encoded: "RC1:<data>".
-- Importing feeds each line through the same checks as a sync, so the
-- newest version still wins and an old backup can't undo newer changes.
----------------------------------------------------------------------

local BACKUP_PREFIX = "RC1:"

function Gankers:ExportString()
    local lines = { RC.Pack("BACKUP", RC.guildName or "", time()) }
    local counts = { KOS = 0, BNTY = 0, KOSG = 0 }
    for _, ganker in pairs(RC.guild.gankers) do
        table.insert(lines, EncodeGanker(ganker, true))
        counts.KOS = counts.KOS + 1
    end
    for _, bounty in pairs(RC.guild.bounties) do
        table.insert(lines, EncodeBounty(bounty, true))
        counts.BNTY = counts.BNTY + 1
    end
    for _, guild in pairs(RC.guild.kosGuilds) do
        table.insert(lines, EncodeGuild(guild, true))
        counts.KOSG = counts.KOSG + 1
    end
    local ok, encoded = pcall(function()
        local packed = C_EncodingUtil.CompressString(table.concat(lines, "\n"))
        return packed and C_EncodingUtil.EncodeBase64(packed)
    end)
    if not ok or not encoded then
        return nil
    end
    return BACKUP_PREFIX .. encoded, counts
end

-- Reads a pasted backup. Returns { guild, exported, lines, counts } or nil
-- plus a message saying what's wrong.
function Gankers:ReadBackup(text)
    text = (text or ""):gsub("%s", "")
    if text == "" then
        return nil, "Paste a backup first."
    end
    if text:sub(1, #BACKUP_PREFIX) ~= BACKUP_PREFIX then
        return nil, "That isn't a Rallying Cry backup. It should start with " .. BACKUP_PREFIX
    end
    local ok, raw = pcall(function()
        local packed = C_EncodingUtil.DecodeBase64(text:sub(#BACKUP_PREFIX + 1))
        return packed and C_EncodingUtil.DecompressString(packed)
    end)
    if not ok or not raw then
        return nil, "The backup is damaged or cut off. Make sure you copied all of it."
    end
    local lines = { strsplit("\n", raw) }
    local _, kind, guild, exported = strsplit("~", lines[1] or "")
    if kind ~= "BACKUP" then
        return nil, "The backup is damaged or cut off. Make sure you copied all of it."
    end
    local backup = {
        guild = guild ~= "" and guild or nil,
        exported = tonumber(exported),
        lines = {},
        counts = { KOS = 0, BNTY = 0, KOSG = 0 },
    }
    for i = 2, #lines do
        local recordKind = select(2, strsplit("~", lines[i]))
        if backup.counts[recordKind] then
            table.insert(backup.lines, lines[i])
            backup.counts[recordKind] = backup.counts[recordKind] + 1
        end
    end
    return backup
end

-- Officers only. Returns how many records were new, or nil if refused.
function Gankers:Import(backup)
    if not IsInGuild() then
        RC:Print(RC.COLORS.ERROR .. "You need to be in a guild to import a backup.|r")
        return nil
    end
    if not self:IsOfficer(Me()) then
        RC:Print(RC.COLORS.WARNING .. "Only officers can import a backup.|r")
        return nil
    end
    self.imported = {}
    RC.SyncLog.muted = true
    for _, line in ipairs(backup.lines) do
        local fields = { strsplit("~", line) }
        local handler = RC.MessageHandlers[fields[2]]
        if handler then
            -- "r" in the third field marks it as passed along, like a sync
            handler(RC, Me(), select(3, unpack(fields)))
        end
    end
    RC.SyncLog.muted = nil
    local imported = self.imported
    self.imported = nil

    -- Share what was new with the rest of the guild
    QueueRecords(imported)
    RC.SyncLog:Add("Imported a backup" .. (backup.guild and (" of <" .. backup.guild .. ">") or "") ..
        (backup.exported and (" from " .. date("%m/%d %H:%M", backup.exported)) or "") .. ": " ..
        #imported .. " of " .. #backup.lines .. " entries were new" ..
        (#imported > 0 and ", and they're being shared with the guild" or ""))
    return #imported
end

----------------------------------------------------------------------
-- "Ganker spotted" warnings
----------------------------------------------------------------------

function Gankers:CheckUnit(unit)
    if not RC.db.kosWarn then
        return
    end
    local name = RC:GetHostileUnitName(unit)
    if not name then
        return
    end
    local guild = RC:GetUnitGuild(unit)
    local ganker = self:Get(name)
    local kosGuild = guild and self:MatchGuild(guild)
    if not (ganker or kosGuild) then
        return
    end
    local now = GetTime()
    if warnedAt[name] and now - warnedAt[name] < WARN_COOLDOWN then
        return
    end
    warnedAt[name] = now

    local display = RC.DisplayName(name) .. (guild and (" <" .. guild .. ">") or "")
    local text
    if ganker then
        local _, bounty = self:ActiveBounties(name)
        local details = "reported " .. ganker.reports .. (ganker.reports == 1 and " time" or " times")
        if bounty > 0 then
            details = details .. ", bounty " .. RC.FormatGold(bounty)
        end
        if kosGuild then
            details = details .. ", KOS guild"
        end
        text = RC.COLORS.ERROR .. "Ganker spotted: " .. display .. "|r (" .. details .. ")"
    else
        text = RC.COLORS.ERROR .. "KOS guild: " .. display .. "|r" ..
            (kosGuild.reason and (" (" .. kosGuild.reason .. ")") or "")
    end
    RC:Print(text)
    UIErrorsFrame:AddMessage(text)
    if RC:SoundOn("KOS") then
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
        -- Make sure this guild's lists are loaded before touching them
        RC:SelectGuildData()
        Purge()
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
            -- Give the guild channel a moment to come up before asking
            C_Timer.After(8, function()
                Gankers:RequestSync()
                Gankers:ShowPendingClaims()
            end)
        end
        loginSyncScheduled = true
    elseif event == "GUILD_ROSTER_UPDATE" then
        Gankers:RefreshRoster()
    elseif event == "PLAYER_TARGET_CHANGED" then
        Gankers:CheckUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Gankers:CheckUnit("mouseover")
    end
end)
