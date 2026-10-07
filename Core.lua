-- Rallying Cry - Core
-- Saved settings, the guild message protocol, sending alerts, and slash commands.
-- Every alert goes over the hidden GUILD addon channel, so only guildmates
-- running Rallying Cry ever see it.

local addonName = ...

RallyingCry = {}
local RC = RallyingCry

RC.VERSION = "0.4.0"

-- Addon message prefix (16 characters max)
RC.PREFIX = "RallyingCry"

-- Bump when the message format changes in a way older versions can't read
RC.PROTOCOL = 1

RC.COLORS = {
    BRAND = "|cffffd100",   -- Blizzard gold text, bright enough to stand out in chat
    SUCCESS = "|cff00ff00",
    ERROR = "|cffff0000",
    WARNING = "|cffffff00",
    DEBUG = "|cffff8800",
    INFO = "|cffaaaaaa",
    RESET = "|r",
}

-- Alert types. The key is what goes over the wire, so don't rename one
-- without bumping RC.PROTOCOL.
RC.ALERTS = {
    HELP = {
        label = "Ganked!",
        verb = "is being ganked",
        tooltip = "Call guildmates to your location.",
        color = "|cffff3333",
        sound = SOUNDKIT.RAID_WARNING,
    },
    WPVP = {
        label = "World PvP",
        verb = "found world PvP",
        tooltip = "Let the guild know there's a fight worth joining.",
        color = "|cffff8000",
        sound = SOUNDKIT.READY_CHECK,
    },
    HUNT = {
        label = "Hunt Ganker",
        verb = "is hunting a ganker",
        tooltip = "Rally a hunting party. Your enemy player target is sent as the ganker.",
        color = "|cff3399ff",
        sound = SOUNDKIT.RAID_WARNING,
    },
    CLEAR = {
        label = "All Clear",
        verb = "is safe now",
        tooltip = "Call off your last alert.",
        color = "|cff00ff00",
    },
}
RC.ALERT_ORDER = { "HELP", "WPVP", "HUNT", "CLEAR" }

-- Handlers for every non-alert message, keyed by the second field. Each gets
-- (RC, sender, ...remaining fields). Registered by Invites.lua and Gankers.lua.
RC.MessageHandlers = {}

local DEFAULTS = {
    sound = true,
    banner = true,
    autoWaypoint = false,
    showPanel = true,
    showMinimap = true,
    popup = true,
    autoInvite = true,
    autoRaid = true,
    debug = false,
    panelPoint = nil,
    muted = {},
    log = {},
    -- Ganker list, bounties, KOS guilds, and sync log, one bucket per guild
    guilds = {},
    kosWarn = true,
    kosAutoAdd = true,
}

-- Seconds between alerts from you, so one button mash doesn't spam the guild
local SEND_COOLDOWN = 10

-- How long your alert stays active: guildmates can answer it, and you can
-- call it off with All Clear
RC.ACTIVE_ALERT_WINDOW = 600

-- Max length of the free-text note
local NOTE_MAX = 100

local FIELD_SEP = "~"

-- WoW drops addon messages longer than this
RC.MAX_MESSAGE = 255

-- Keybinding labels (ESC > Options > Keybindings > AddOns)
BINDING_HEADER_RALLYINGCRY = "Rallying Cry"
BINDING_NAME_RALLYINGCRY_HELP = "Send: Ganked!"
BINDING_NAME_RALLYINGCRY_WPVP = "Send: World PvP"
BINDING_NAME_RALLYINGCRY_HUNT = "Send: Hunt Ganker"
BINDING_NAME_RALLYINGCRY_CLEAR = "Send: All Clear"
BINDING_NAME_RALLYINGCRY_WAYPOINT = "Waypoint to last alert"
BINDING_NAME_RALLYINGCRY_PANEL = "Toggle alert panel"
BINDING_NAME_RALLYINGCRY_GANKERS = "Toggle ganker list"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

function RC:Print(msg)
    print(RC.COLORS.BRAND .. "[Rallying Cry]|r " .. msg)
end

function RC:Debug(msg)
    if self.db and self.db.debug then
        print(RC.COLORS.DEBUG .. "[Rallying Cry Debug]|r " .. tostring(msg))
    end
end

-- Forever runs the Midnight API, where unit data can come back as "secret"
-- values (mostly in combat). Secrets can't be compared, concatenated, or sent,
-- so treat them as unknown.
function RC.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function RC.Readable(value)
    if value == nil or RC.IsSecret(value) then
        return nil
    end
    return value
end

-- Strip anything that could break the wire format or inject chat escape codes
-- Drops a multi-byte character that a byte-length cut left half finished
local function TrimPartialUTF8(text)
    local i = #text
    while i > 0 and text:byte(i) >= 128 and text:byte(i) < 192 do
        i = i - 1
    end
    if i > 0 and text:byte(i) >= 192 then
        local lead = text:byte(i)
        local length = lead >= 240 and 4 or lead >= 224 and 3 or 2
        if #text - i + 1 < length then
            return text:sub(1, i - 1)
        end
    end
    return text
end

function RC.CleanText(text, maxLen)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("[|" .. FIELD_SEP .. "]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if maxLen and #text > maxLen then
        text = TrimPartialUTF8(text:sub(1, maxLen))
    end
    return text
end

-- Forever is realmless: every character has a first name and a surname, and
-- that pair is what's unique. UnitName returns the surname where other
-- clients return the realm. Blizzard joins the two with this separator.
local function SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

function RC.UsesSurnames()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

-- One name format for every comparison. On Forever: "First Surname", with any
-- realm suffix dropped. Elsewhere: "Name-Realm" with the realm filled in, so
-- connected realms don't split one player into two entries. Only the first
-- letter of each word is capitalized. Nil if empty.
function RC.NormalizeName(name)
    name = RC.CleanText(name, 50)
    local short, realm = name:match("^([^%-]+)%-?(.*)$")
    if not short then
        return nil
    end
    short = short:gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
    short = short:gsub("(%S)(%S*)", function(first, rest)
        if first:byte() < 128 then
            first = first:upper()
        end
        return first .. rest
    end)
    if short == "" then
        return nil
    end
    if RC.UsesSurnames() then
        return short
    end
    realm = realm:gsub("%s", "")
    if realm == "" then
        realm = GetNormalizedRealmName() or ""
    end
    return realm ~= "" and (short .. "-" .. realm) or short
end

-- Name for display: drops the realm when it's your own
function RC.DisplayName(name)
    return Ambiguate(name, "none")
end

-- Joins fields into a message, after the protocol number. Nil becomes empty.
function RC.Pack(...)
    local fields = { RC.PROTOCOL }
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        fields[i + 1] = value == nil and "" or tostring(value)
    end
    return table.concat(fields, FIELD_SEP)
end

-- Normalized full name of a unit, or nil if it's unknown or hidden
function RC:UnitFullName(unit)
    local name, second = UnitName(unit)
    name, second = RC.Readable(name), RC.Readable(second)
    if not name or name == "" then
        return nil
    end
    if second and second ~= "" then
        -- second is the surname on Forever, the realm everywhere else
        name = name .. (RC.UsesSurnames() and SurnameSeparator() or "-") .. second
    end
    return RC.NormalizeName(name)
end

function RC:PlayerFullName()
    if not self.fullName then
        self.fullName = self:UnitFullName("player")
    end
    return self.fullName
end

-- Current map, position (0-1 coords), zone, and subzone. Position is nil
-- inside instances, where the game hides it.
function RC:GetPlayerLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    local x, y
    if mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            x, y = pos:GetXY()
        end
    end
    local zone = RC.Readable(GetZoneText()) or "Unknown"
    local subzone = RC.Readable(GetSubZoneText())
    if subzone == "" or subzone == zone then
        subzone = nil
    end
    return mapID, x, y, zone, subzone
end

-- Normalized name of a unit if it's an attackable enemy player, otherwise
-- nil. Any of these unit queries can return a secret in combat, which reads
-- as "no unit" here.
function RC:GetHostileUnitName(unit)
    local ok, name = pcall(function()
        local exists = UnitExists(unit)
        if RC.IsSecret(exists) or not exists then
            return nil
        end
        local isPlayer = UnitIsPlayer(unit)
        local canAttack = UnitCanAttack("player", unit)
        if RC.IsSecret(isPlayer) or RC.IsSecret(canAttack) or not isPlayer or not canAttack then
            return nil
        end
        return RC:UnitFullName(unit)
    end)
    return ok and name or nil
end

-- Guild name of a unit (plus its realm outside Forever), or nil. Can be
-- hidden in combat. Forever has no realms, only playstyle shards, so the
-- shard label the game returns there isn't passed on.
function RC:GetUnitGuild(unit)
    local ok, guild, _, _, realm = pcall(GetGuildInfo, unit)
    if not ok then
        return nil
    end
    guild = RC.Readable(guild)
    if not guild or guild == "" then
        return nil
    end
    if RC.UsesSurnames() then
        return guild
    end
    return guild, RC.Readable(realm)
end

-- Splits "<name> <rest>". A Forever name is two words (first name and
-- surname), so it takes two words there and one elsewhere.
function RC.SplitNameArg(text)
    text = text or ""
    local name, rest
    if RC.UsesSurnames() then
        name, rest = text:match("^%s*(%S+%s+%S+)%s*(.-)%s*$")
    end
    if not name then
        name, rest = text:match("^%s*(%S+)%s*(.-)%s*$")
    end
    return name, rest or ""
end

function RC:GetHostileTargetName()
    return self:GetHostileUnitName("target")
end

----------------------------------------------------------------------
-- Protocol
-- protocol ~ type ~ mapID ~ x ~ y ~ zone ~ subzone ~ target ~ note
-- Coordinates are 0-1 with 4 decimals. Empty fields mean unknown.
----------------------------------------------------------------------

-- The note gets whatever room is left under the message limit. The guild
-- field is last so clients older than it still read everything before it.
function RC.Encode(alert)
    local fields = {
        RC.PROTOCOL,
        alert.type,
        alert.mapID or "",
        alert.x and string.format("%.4f", alert.x) or "",
        alert.y and string.format("%.4f", alert.y) or "",
        RC.CleanText(alert.zone, 40),
        RC.CleanText(alert.subzone, 40),
        RC.CleanText(alert.target, 40),
        "",
        RC.CleanText(alert.targetGuild, 30),
    }
    local room = RC.MAX_MESSAGE - #table.concat(fields, FIELD_SEP)
    fields[9] = RC.CleanText(alert.note, math.min(NOTE_MAX, room))
    return table.concat(fields, FIELD_SEP)
end

function RC.Decode(text)
    local protocol, alertType, mapID, x, y, zone, subzone, target, note, targetGuild = strsplit(FIELD_SEP, text)
    protocol = tonumber(protocol)
    if not protocol or not RC.ALERTS[alertType] then
        return nil
    end
    local function orNil(s)
        s = RC.CleanText(s)
        return s ~= "" and s or nil
    end
    return {
        protocol = protocol,
        type = alertType,
        mapID = tonumber(mapID),
        x = tonumber(x),
        y = tonumber(y),
        zone = orNil(zone) or "Unknown",
        subzone = orNil(subzone),
        target = orNil(target),
        note = orNil(note),
        targetGuild = orNil(targetGuild),
    }
end

-- C_ChatInfo.SendAddonMessage returns an Enum.SendAddonMessageResult on the
-- modern API. Returns true on success, or false plus a reason.
function RC:SendGuild(text)
    if #text > RC.MAX_MESSAGE then
        self:Debug("message too long to send (" .. #text .. "): " .. text)
        return false, "message too long"
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, "the game is blocking addon messages right now"
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, RC.PREFIX, text, "GUILD")
    if not ok then
        return false, tostring(result)
    end
    if result == nil or result == true then
        return true
    end
    if Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success then
        return true
    end
    return false, "send failed (" .. tostring(result) .. ")"
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

function RC:HasActiveAlert()
    return self.activeAlert ~= nil and GetTime() - self.activeAlert.sentAt <= RC.ACTIVE_ALERT_WINDOW
end

function RC:SendAlert(alertType, note)
    local info = RC.ALERTS[alertType]
    if not info then
        return
    end

    if not IsInGuild() then
        self:Print(RC.COLORS.ERROR .. "You need to be in a guild to use Rallying Cry.|r")
        return
    end

    local now = GetTime()
    if alertType == "CLEAR" and not self:HasActiveAlert() then
        self:Print("You don't have an active alert to call off.")
        return
    end
    if alertType ~= "CLEAR" and self.lastSentAt and now - self.lastSentAt < SEND_COOLDOWN then
        local wait = math.ceil(SEND_COOLDOWN - (now - self.lastSentAt))
        self:Print(RC.COLORS.WARNING .. "Easy there. You can send another alert in " .. wait .. "s.|r")
        return
    end

    local mapID, x, y, zone, subzone = self:GetPlayerLocation()
    local target = alertType ~= "CLEAR" and self:GetHostileTargetName() or nil
    local targetGuild = target and self:GetUnitGuild("target")
    note = RC.CleanText(note, NOTE_MAX)

    -- "/rc hunt Gankname some note" names the ganker when you don't have them targeted
    if alertType == "HUNT" and not target and note ~= "" then
        local name, rest = RC.SplitNameArg(note)
        target, note = RC.NormalizeName(name), rest
    end

    local alert = {
        type = alertType,
        mapID = mapID,
        x = x,
        y = y,
        zone = zone,
        subzone = subzone,
        target = target,
        targetGuild = targetGuild,
        note = note,
    }

    local payload = RC.Encode(alert)
    self:Debug("send " .. payload)

    local ok, reason = self:SendGuild(payload)
    if not ok then
        self:Print(RC.COLORS.ERROR .. "Couldn't send alert: " .. reason .. "|r")
        return
    end

    if alertType == "CLEAR" then
        self.activeAlert = nil
    else
        self.lastSentAt = now
        self.activeAlert = { type = alertType, sentAt = now, responders = {} }
    end
    self:Print("Sent " .. info.color .. info.label .. "|r to your guild" ..
        (target and (" (target: " .. RC.DisplayName(target) .. ")") or "") .. ".")

    if target and self.db.kosAutoAdd and (alertType == "HELP" or alertType == "HUNT") then
        self.Gankers:Report(target, subzone and (subzone .. ", " .. zone) or zone, targetGuild)
    end
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

function RC:OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= RC.PREFIX or channel ~= "GUILD" then
        return
    end
    if RC.IsSecret(text) or RC.IsSecret(sender) then
        return
    end
    -- Compare names in one format everywhere (see NormalizeName)
    sender = RC.NormalizeName(sender)
    if not sender or sender == self:PlayerFullName() then
        return
    end

    self:Debug("recv " .. sender .. ": " .. text)

    local handler = RC.MessageHandlers[(select(2, strsplit(FIELD_SEP, text)))]
    if handler then
        handler(self, sender, select(3, strsplit(FIELD_SEP, text)))
        return
    end

    local alert = RC.Decode(text)
    if not alert then
        self:Debug("ignored malformed alert from " .. sender)
        return
    end
    alert.sender = sender
    self:HandleAlert(alert)
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Per-guild data
-- SavedVariables are account-wide, so the shared lists are kept per guild.
-- An alt in another guild never sees this guild's list, and never sends it
-- to their guild when answering a sync.
----------------------------------------------------------------------

local GUILD_LISTS = { "gankers", "bounties", "kosGuilds", "syncLog" }

local function NewGuildData()
    local data = {}
    for _, key in ipairs(GUILD_LISTS) do
        data[key] = {}
    end
    return data
end

-- Throwaway lists for when there's no guild (or it hasn't loaded yet)
RC.guild = NewGuildData()

function RC:SelectGuildData()
    local guildName = IsInGuild() and RC.Readable(GetGuildInfo("player")) or nil
    if guildName == self.guildName and (guildName or not IsInGuild()) then
        return
    end
    if IsInGuild() and not guildName then
        -- In a guild, but its name hasn't loaded yet; GUILD_ROSTER_UPDATE retries
        return
    end
    self.guildName = guildName
    if not guildName then
        self.guild = NewGuildData()
    else
        local key = guildName:lower()
        local data = self.db.guilds[key]
        if not data then
            data = NewGuildData()
            self.db.guilds[key] = data
            -- Lists saved before they were kept per guild belong to this one
            for _, list in ipairs(GUILD_LISTS) do
                if type(self.db[list]) == "table" then
                    data[list] = self.db[list]
                    self.db[list] = nil
                end
            end
            data.lastSyncReceived, self.db.lastSyncReceived = self.db.lastSyncReceived, nil
        end
        for _, list in ipairs(GUILD_LISTS) do
            data[list] = data[list] or {}
        end
        data.name = guildName
        self.guild = data
    end
    self:Debug("using saved lists for " .. (guildName or "no guild"))
    if self.Gankers then
        self.Gankers:OnGuildChanged()
    end
end

local function ApplyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = type(value) == "table" and {} or value
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then
            return
        end
        RallyingCryDB = RallyingCryDB or {}
        ApplyDefaults(RallyingCryDB, DEFAULTS)
        RC.db = RallyingCryDB
        C_ChatInfo.RegisterAddonMessagePrefix(RC.PREFIX)
        RC.Options:Register()
    elseif event == "PLAYER_LOGIN" then
        RC:SelectGuildData()
        RC.Panel:Create()
        RC.MinimapButton:Create()
        -- Wait for the login chat spam to settle
        C_Timer.After(10, function()
            RC:Print(RC.COLORS.SUCCESS .. "Loaded!|r v" .. RC.VERSION .. " by |cff00ccffRelyk|r. " ..
                "Click the minimap button or type " .. RC.COLORS.DEBUG .. "/rc|r for commands.")
            if not IsInGuild() then
                RC:Print(RC.COLORS.INFO .. "You're not in a guild, so alerts are off until you join one.|r")
            end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        RC:OnAddonMessage(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RC:FlushPendingInvites()
    elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        RC:SelectGuildData()
    end
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

local SEND_COMMANDS = {
    gank = "HELP",
    wpvp = "WPVP",
    pvp = "WPVP",
    hunt = "HUNT",
    clear = "CLEAR",
    safe = "CLEAR",
}

local function OnOff(value)
    return value and (RC.COLORS.SUCCESS .. "on|r") or (RC.COLORS.ERROR .. "off|r")
end

local function PrintUsage()
    RC:Print("v" .. RC.VERSION .. " commands:")
    print("  /rc gank [note] - you're being ganked, call for help")
    print("  /rc wpvp [note] - there's world PvP here")
    print("  /rc hunt [name] [note] - hunting a ganker (uses your target if it's an enemy player)")
    print("  /rc clear - call off your alert")
    print("  /rc go - waypoint to the last alert")
    print("  /rc log - recent alerts")
    print("  /rc kos - open the guild ganker list")
    print("  /rc kos add <name> [reason] | /rc kos remove <name>")
    print("  /rc kos guild add <guild> [- reason] | /rc kos guild remove <guild>")
    print("  /rc bounty <name> <gold> - pledge gold on a ganker (0 withdraws)")
    print("  /rc claim <name> - claim the bounties on a ganker you killed")
    print("  /rc export | /rc import - back up or restore the guild's ganker list (import: officers)")
    print("  /rc settings - open the settings page")
    print("  /rc panel - show/hide the button panel")
    print("  /rc minimap - show/hide the minimap button")
    print("  /rc sound | banner | waypoint - toggle sound, screen banner, auto-waypoint")
    print("  /rc popup - toggle the Accept/Decline window for incoming alerts")
    print("  /rc invite - toggle auto-inviting guildmates who accept your alert")
    print("  /rc raid - toggle turning your party into a raid when it fills up")
    print("  /rc mute <gank|wpvp|hunt> - silence one alert type")
end

SLASH_RALLYINGCRY1 = "/rc"
SLASH_RALLYINGCRY2 = "/rallyingcry"
SlashCmdList["RALLYINGCRY"] = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if SEND_COMMANDS[cmd] then
        RC:SendAlert(SEND_COMMANDS[cmd], rest)
    elseif cmd == "go" then
        RC:WaypointToLastAlert()
    elseif cmd == "log" then
        RC:PrintLog()
    elseif cmd == "kos" or cmd == "gankers" or cmd == "list" then
        local sub, args = rest:match("^(%S*)%s*(.-)$")
        sub = sub:lower()
        if sub == "add" then
            local name, reason = RC.SplitNameArg(args)
            RC.Gankers:Add(name, reason)
        elseif sub == "remove" or sub == "del" then
            RC.Gankers:Remove(args)
        elseif sub == "guild" then
            -- Guild names have spaces, so a reason goes after " - "
            local action, rest2 = args:match("^(%S*)%s*(.-)$")
            local guild, reason = rest2:match("^(.-)%s+%-%s+(.*)$")
            guild = guild or rest2
            if action:lower() == "add" then
                RC.Gankers:AddGuild(guild, nil, reason)
            elseif action:lower() == "remove" or action:lower() == "del" then
                RC.Gankers:RemoveGuild(guild)
            else
                RC:Print("Usage: /rc kos guild add <guild name> [- reason]  |  /rc kos guild remove <guild name>")
            end
        else
            RC.GankerList:Toggle()
        end
    elseif cmd == "bounty" then
        -- The gold amount is the last word, so names of any length work
        local name, gold = rest:match("^(.-)%s+(%d+)%s*$")
        RC.Gankers:PostBounty(name or rest, gold)
    elseif cmd == "claim" then
        RC.Gankers:Claim(rest)
    elseif cmd == "export" then
        RC.SyncLog:ShowBackup("export")
    elseif cmd == "import" then
        RC.SyncLog:ShowBackup("import")
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        RC.Options:Open()
    elseif cmd == "minimap" then
        RC.MinimapButton:Toggle()
    elseif cmd == "panel" then
        RC.Panel:Toggle()
    elseif cmd == "sound" then
        RC.db.sound = not RC.db.sound
        RC:Print("Alert sound " .. OnOff(RC.db.sound))
    elseif cmd == "banner" then
        RC.db.banner = not RC.db.banner
        RC:Print("Screen banner " .. OnOff(RC.db.banner))
    elseif cmd == "waypoint" then
        RC.db.autoWaypoint = not RC.db.autoWaypoint
        RC:Print("Auto-waypoint on new alerts " .. OnOff(RC.db.autoWaypoint))
    elseif cmd == "popup" then
        RC.db.popup = not RC.db.popup
        RC:Print("Accept/Decline window " .. OnOff(RC.db.popup))
    elseif cmd == "invite" then
        RC.db.autoInvite = not RC.db.autoInvite
        RC:Print("Auto-invite guildmates who accept " .. OnOff(RC.db.autoInvite))
    elseif cmd == "raid" then
        RC.db.autoRaid = not RC.db.autoRaid
        RC:Print("Convert to raid when your party is full " .. OnOff(RC.db.autoRaid))
    elseif cmd == "mute" then
        local alertType = SEND_COMMANDS[rest:lower()]
        if not alertType or alertType == "CLEAR" then
            RC:Print("Usage: /rc mute <gank|wpvp|hunt>")
            return
        end
        RC.db.muted[alertType] = not RC.db.muted[alertType] or nil
        RC:Print(RC.ALERTS[alertType].label .. " alerts " ..
            (RC.db.muted[alertType] and "muted (chat only)" or "unmuted"))
    elseif cmd == "debug" then
        RC.db.debug = not RC.db.debug
        RC:Print("Debug " .. OnOff(RC.db.debug))
    elseif cmd == "version" then
        RC:Print("Version " .. RC.VERSION .. " (protocol " .. RC.PROTOCOL .. ")")
    else
        PrintUsage()
    end
end
