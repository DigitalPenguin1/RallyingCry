-- Rallying Cry - Core
-- Saved settings, the guild message protocol, sending alerts, and slash commands.
-- Every alert goes over the hidden GUILD addon channel, so only guildmates
-- running Rallying Cry ever see it.

local addonName = ...

RallyingCry = {}
local RC = RallyingCry

RC.VERSION = "0.1.0"

-- Addon message prefix (16 characters max)
RC.PREFIX = "RallyingCry"

-- Bump when the message format changes in a way older versions can't read
RC.PROTOCOL = 1

RC.COLORS = {
    BRAND = "|cffff3333",
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
        color = "|cffa335ee",
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

local DEFAULTS = {
    sound = true,
    banner = true,
    autoWaypoint = false,
    showPanel = true,
    debug = false,
    panelPoint = nil,
    muted = {},
    log = {},
}

-- Seconds between alerts from you, so one button mash doesn't spam the guild
local SEND_COOLDOWN = 10

-- Max length of the free-text note
local NOTE_MAX = 100

local FIELD_SEP = "~"

-- Keybinding labels (ESC > Options > Keybindings > AddOns)
BINDING_HEADER_RALLYINGCRY = "Rallying Cry"
BINDING_NAME_RALLYINGCRY_HELP = "Send: Ganked!"
BINDING_NAME_RALLYINGCRY_WPVP = "Send: World PvP"
BINDING_NAME_RALLYINGCRY_HUNT = "Send: Hunt Ganker"
BINDING_NAME_RALLYINGCRY_CLEAR = "Send: All Clear"
BINDING_NAME_RALLYINGCRY_WAYPOINT = "Waypoint to last alert"
BINDING_NAME_RALLYINGCRY_PANEL = "Toggle alert panel"

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
function RC.CleanText(text, maxLen)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("[|" .. FIELD_SEP .. "]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if maxLen and #text > maxLen then
        text = text:sub(1, maxLen)
    end
    return text
end

function RC:PlayerFullName()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName()
    if realm then
        return name .. "-" .. realm
    end
    return name
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

-- Name of your current target if it's an attackable enemy player, otherwise
-- nil. Any of these unit queries can return a secret in combat, which reads
-- as "no target" here.
function RC:GetHostileTargetName()
    local ok, name = pcall(function()
        local exists = UnitExists("target")
        if RC.IsSecret(exists) or not exists then
            return nil
        end
        local isPlayer = UnitIsPlayer("target")
        local canAttack = UnitCanAttack("player", "target")
        if RC.IsSecret(isPlayer) or RC.IsSecret(canAttack) or not isPlayer or not canAttack then
            return nil
        end
        local unitName, realm = UnitName("target")
        unitName = RC.Readable(unitName)
        if not unitName then
            return nil
        end
        realm = RC.Readable(realm)
        if realm and realm ~= "" then
            unitName = unitName .. "-" .. realm
        end
        return unitName
    end)
    return ok and name or nil
end

----------------------------------------------------------------------
-- Protocol
-- protocol ~ type ~ mapID ~ x ~ y ~ zone ~ subzone ~ target ~ note
-- Coordinates are 0-1 with 4 decimals. Empty fields mean unknown.
----------------------------------------------------------------------

function RC.Encode(alert)
    return table.concat({
        RC.PROTOCOL,
        alert.type,
        alert.mapID or "",
        alert.x and string.format("%.4f", alert.x) or "",
        alert.y and string.format("%.4f", alert.y) or "",
        RC.CleanText(alert.zone, 60),
        RC.CleanText(alert.subzone, 60),
        RC.CleanText(alert.target, 60),
        RC.CleanText(alert.note, NOTE_MAX),
    }, FIELD_SEP)
end

function RC.Decode(text)
    local protocol, alertType, mapID, x, y, zone, subzone, target, note = strsplit(FIELD_SEP, text)
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
    }
end

-- C_ChatInfo.SendAddonMessage returns an Enum.SendAddonMessageResult on the
-- modern API. Returns true on success, or false plus a reason.
local function SendGuildAddonMessage(text)
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
    if alertType ~= "CLEAR" and self.lastSentAt and now - self.lastSentAt < SEND_COOLDOWN then
        local wait = math.ceil(SEND_COOLDOWN - (now - self.lastSentAt))
        self:Print(RC.COLORS.WARNING .. "Easy there. You can send another alert in " .. wait .. "s.|r")
        return
    end

    local mapID, x, y, zone, subzone = self:GetPlayerLocation()
    local target = alertType ~= "CLEAR" and self:GetHostileTargetName() or nil
    note = RC.CleanText(note, NOTE_MAX)

    -- "/rc hunt Gankname some note" names the ganker when you don't have them targeted
    if alertType == "HUNT" and not target and note ~= "" then
        local first, rest = note:match("^(%S+)%s*(.*)$")
        target, note = first, rest
    end

    local alert = {
        type = alertType,
        mapID = mapID,
        x = x,
        y = y,
        zone = zone,
        subzone = subzone,
        target = target,
        note = note,
    }

    local payload = RC.Encode(alert)
    self:Debug("send " .. payload)

    local ok, reason = SendGuildAddonMessage(payload)
    if not ok then
        self:Print(RC.COLORS.ERROR .. "Couldn't send alert: " .. reason .. "|r")
        return
    end

    if alertType ~= "CLEAR" then
        self.lastSentAt = now
    end
    self:Print("Sent " .. info.color .. info.label .. "|r to your guild" ..
        (target and (" (target: " .. target .. ")") or "") .. ".")
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
    if sender == self:PlayerFullName() or sender == UnitName("player") then
        return
    end

    self:Debug("recv " .. sender .. ": " .. text)

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
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then
            return
        end
        RallyingCryDB = RallyingCryDB or {}
        ApplyDefaults(RallyingCryDB, DEFAULTS)
        RC.db = RallyingCryDB
        C_ChatInfo.RegisterAddonMessagePrefix(RC.PREFIX)
    elseif event == "PLAYER_LOGIN" then
        RC.Panel:Create()
        if not IsInGuild() then
            RC:Print(RC.COLORS.INFO .. "You're not in a guild, so alerts are off until you join one.|r")
        end
    elseif event == "CHAT_MSG_ADDON" then
        RC:OnAddonMessage(...)
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
    print("  /rc panel - show/hide the button panel")
    print("  /rc sound | banner | waypoint - toggle sound, screen banner, auto-waypoint")
    print("  /rc mute <gank|wpvp|hunt|clear> - silence one alert type")
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
    elseif cmd == "mute" then
        local alertType = SEND_COMMANDS[rest:lower()]
        if not alertType then
            RC:Print("Usage: /rc mute <gank|wpvp|hunt|clear>")
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

function RallyingCry_OnAddonCompartmentClick()
    RC.Panel:Toggle()
end
