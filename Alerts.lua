-- Rallying Cry - Incoming Alerts
-- Shows guildmates' alerts (chat line, screen banner, sound), keeps a short
-- log, and sets map waypoints to them.

local RC = RallyingCry

-- Max alerts kept in the saved log
local LOG_SIZE = 25

-- Ignore repeats of the same alert type from the same sender inside this window
local DUPLICATE_WINDOW = 5

local recentBySender = {}

local function ShortName(fullName)
    return Ambiguate(fullName, "guild")
end

local function FormatCoords(alert)
    if alert.x and alert.y then
        return string.format("%.1f, %.1f", alert.x * 100, alert.y * 100)
    end
end

function RC.FormatLocation(alert)
    local place = alert.zone
    if alert.subzone then
        place = alert.subzone .. ", " .. place
    end
    local coords = FormatCoords(alert)
    if coords then
        place = place .. " (" .. coords .. ")"
    end
    return place
end

function RC.FormatAlert(alert)
    local info = RC.ALERTS[alert.type]
    local text = info.color .. ShortName(alert.sender) .. " " .. info.verb .. "|r"
    if alert.type ~= "CLEAR" then
        text = text .. " at " .. RC.FormatLocation(alert)
    end
    if alert.target then
        text = text .. ". Ganker: " .. RC.COLORS.ERROR .. RC.DisplayName(alert.target) .. "|r"
        if alert.targetGuild then
            text = text .. " <" .. alert.targetGuild .. ">"
            if RC.Gankers:MatchGuild(alert.targetGuild) then
                text = text .. RC.COLORS.ERROR .. " (KOS guild)|r"
            end
        end
        local _, bounty = RC.Gankers:ActiveBounties(RC.NormalizeName(alert.target) or alert.target)
        if bounty > 0 then
            text = text .. " (bounty " .. RC.FormatGold(bounty) .. ")"
        end
    end
    if alert.note then
        text = text .. ". \"" .. alert.note .. "\""
    end
    return text
end

local function AddToLog(alert)
    local log = RC.db.log
    table.insert(log, 1, {
        time = time(),
        type = alert.type,
        sender = alert.sender,
        mapID = alert.mapID,
        x = alert.x,
        y = alert.y,
        zone = alert.zone,
        subzone = alert.subzone,
        target = alert.target,
        targetGuild = alert.targetGuild,
        note = alert.note,
    })
    for i = #log, LOG_SIZE + 1, -1 do
        log[i] = nil
    end
end

-- Our own banner instead of the raid warning frame, which sits right where
-- the Accept/Decline popups open. This one goes below the popups.
local BANNER_OFFSET = -340
local BANNER_HOLD = 4
local BANNER_FADE = 1.5
local banner

local function GetBanner()
    if banner then
        return banner
    end
    banner = CreateFrame("Frame", "RallyingCryBanner", UIParent)
    banner:SetSize(900, 60)
    banner:SetPoint("TOP", UIParent, "TOP", 0, BANNER_OFFSET)
    banner:SetFrameStrata("HIGH")
    banner:Hide()

    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner.text:SetAllPoints()
    banner.text:SetJustifyH("CENTER")
    banner.text:SetShadowOffset(2, -2)

    banner.fade = banner:CreateAnimationGroup()
    local alpha = banner.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetStartDelay(BANNER_HOLD)
    alpha:SetDuration(BANNER_FADE)
    banner.fade:SetScript("OnFinished", function()
        banner:Hide()
    end)
    return banner
end

local function ShowBanner(text)
    local frame = GetBanner()
    frame.fade:Stop()
    frame.text:SetText(text)
    frame:SetAlpha(1)
    frame:Show()
    frame.fade:Play()
end

function RC:HandleAlert(alert)
    local now = GetTime()
    local key = alert.sender .. ":" .. alert.type
    if recentBySender[key] and now - recentBySender[key] < DUPLICATE_WINDOW then
        self:Debug("dropped duplicate " .. key)
        return
    end
    recentBySender[key] = now

    AddToLog(alert)
    local text = RC.FormatAlert(alert)
    self:Print(text)

    if alert.type == "CLEAR" then
        self:HideAlertPopup(alert.sender)
        if self.lastAlert and self.lastAlert.sender == alert.sender then
            self.lastAlert = nil
        end
        if self:ClearWaypointFrom(alert.sender) then
            self:Print(RC.COLORS.INFO .. "Removed the waypoint to " .. ShortName(alert.sender) .. ".|r")
        end
        return
    end

    self.lastAlert = alert

    if self.db.muted[alert.type] then
        return
    end

    if self.db.banner then
        ShowBanner(text)
    end

    local sound = RC.ALERTS[alert.type].sound
    if self.db.sound and sound then
        PlaySound(sound, "Master")
    end

    if self.db.autoWaypoint then
        self:SetWaypoint(alert, true)
    end

    if self.db.popup then
        self:ShowAlertPopup(alert)
    end
end

-- Puts a map pin on the alert and tracks it. Returns false when the alert has
-- no usable position (sender was in an instance, or the map doesn't allow pins).
function RC:SetWaypoint(alert, quiet)
    if not (alert and alert.mapID and alert.x and alert.y) then
        if not quiet then
            self:Print(RC.COLORS.WARNING .. "That alert has no map position.|r")
        end
        return false
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(alert.mapID) then
        if not quiet then
            self:Print(RC.COLORS.WARNING .. "Can't place a waypoint on that map.|r")
        end
        return false
    end

    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(alert.mapID, alert.x, alert.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    self.waypointAlert = alert
    if not quiet then
        self:Print("Waypoint set to " .. ShortName(alert.sender) .. " at " .. RC.FormatLocation(alert) .. ".")
    end
    return true
end

-- Removes the map pin we set for this sender's alert. Leaves it alone if the
-- player has since placed a pin of their own. Returns true if one was removed.
function RC:ClearWaypointFrom(sender)
    local alert = self.waypointAlert
    if not (alert and alert.sender == sender) then
        return false
    end
    self.waypointAlert = nil
    local point = C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
    if not point or point.uiMapID ~= alert.mapID then
        return false
    end
    local x, y = point.position:GetXY()
    if math.abs(x - alert.x) > 0.001 or math.abs(y - alert.y) > 0.001 then
        return false
    end
    C_Map.ClearUserWaypoint()
    return true
end

function RC:WaypointToLastAlert()
    if not self.lastAlert then
        self:Print("No active alert to go to.")
        return
    end
    self:SetWaypoint(self.lastAlert)
end

function RC:PrintLog()
    local log = self.db.log
    if #log == 0 then
        self:Print("No alerts logged yet.")
        return
    end
    self:Print("Recent alerts:")
    for i = 1, math.min(#log, 10) do
        local entry = log[i]
        print("  " .. RC.COLORS.INFO .. date("%m/%d %H:%M", entry.time) .. "|r " .. RC.FormatAlert(entry))
    end
end
