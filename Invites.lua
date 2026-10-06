-- Rallying Cry - Accept / Decline and Group Invites
-- Incoming alerts pop an Accept/Decline window. Accept sets a waypoint and
-- tells the alerter over the guild channel, and the alerter's client invites
-- them. Replies ride the GUILD channel (not whispers) so only guildmates can
-- trigger an invite.

local RC = RallyingCry

local POPUP = "RALLYINGCRY_ALERT"

-- Seconds before an unanswered popup closes itself
local POPUP_TIMEOUT = 60

-- Seconds after sending an alert that accepts still get invited
local ACCEPT_WINDOW = 600

local MAX_PARTY = 5
local MAX_RAID = 40

-- Why an invite didn't happen, sent back to the responder as a short code
local NOINVITE_REASONS = {
    notleader = "they aren't the group leader",
    full = "their group is full",
    failed = "the invite failed",
    off = "they have auto-invite turned off",
}

local popupBySender = {}
local pendingInvites = {}

local function ShortName(fullName)
    return Ambiguate(fullName, "guild")
end

StaticPopupDialogs[POPUP] = {
    text = "%s",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(dialog, data)
        RC:AcceptAlert(data)
    end,
    OnHide = function(dialog)
        local data = dialog.data
        if data and popupBySender[data.sender] == data then
            popupBySender[data.sender] = nil
        end
    end,
    timeout = POPUP_TIMEOUT,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    multiple = 1,
}

----------------------------------------------------------------------
-- Responder side
----------------------------------------------------------------------

function RC:ShowAlertPopup(alert)
    -- A newer alert from the same guildmate replaces their old popup
    self:HideAlertPopup(alert.sender)
    local text = RC.FormatAlert(alert) .. "\n\nAccept to join their group and get a waypoint."
    if StaticPopup_Show(POPUP, text, nil, alert) then
        popupBySender[alert.sender] = alert
    end
end

function RC:HideAlertPopup(sender)
    local alert = popupBySender[sender]
    if alert then
        popupBySender[sender] = nil
        StaticPopup_Hide(POPUP, alert)
    end
end

function RC:AcceptAlert(alert)
    local who = ShortName(alert.sender)
    self:SetWaypoint(alert, true)

    local grouped = IsInGroup()
    local payload = table.concat({ RC.PROTOCOL, "JOIN", alert.sender, grouped and "grouped" or "" }, "~")
    local ok, reason = self:SendGuild(payload)
    if not ok then
        self:Print(RC.COLORS.ERROR .. "Couldn't answer " .. who .. ": " .. reason .. "|r")
        return
    end

    if grouped then
        self:Print("Told " .. who .. " you're on the way. You're already in a group, so they can't invite you.")
    else
        self:Print("Answered " .. who .. "'s call. Waypoint set, invite incoming.")
    end
end

----------------------------------------------------------------------
-- Alerter side
----------------------------------------------------------------------

local function CanInvite()
    if not IsInGroup() then
        return true
    end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))
end

-- Returns true once the invite is sent (or queued behind a raid conversion),
-- otherwise false plus a NOINVITE_REASONS code
function RC:InviteResponder(name)
    if not CanInvite() then
        return false, "notleader"
    end

    local members = GetNumGroupMembers()
    if IsInRaid() then
        if members >= MAX_RAID then
            return false, "full"
        end
    elseif members >= MAX_PARTY then
        if not (self.db.autoRaid and UnitIsGroupLeader("player")) then
            return false, "full"
        end
        -- Converting is async; invite once the roster says we're a raid
        table.insert(pendingInvites, name)
        C_PartyInfo.ConvertToRaid()
        return true
    end

    if not pcall(C_PartyInfo.InviteUnit, name) then
        return false, "failed"
    end
    return true
end

function RC:FlushPendingInvites()
    if #pendingInvites == 0 or not IsInRaid() then
        return
    end
    local names = pendingInvites
    pendingInvites = {}
    for _, name in ipairs(names) do
        pcall(C_PartyInfo.InviteUnit, name)
    end
end

function RC:HandleResponse(kind, sender, subject, extra)
    -- Every guildmate hears every reply; only the one it's addressed to acts
    if subject ~= self:PlayerFullName() then
        return
    end
    local who = ShortName(sender)

    if kind == "NOINVITE" then
        local reason = NOINVITE_REASONS[extra] or NOINVITE_REASONS.failed
        self:Print(RC.COLORS.WARNING .. "Couldn't get an invite: " .. reason .. ". Follow the waypoint.|r")
        return
    end

    -- JOIN: someone accepted our alert
    local active = self.activeAlert
    if not active or GetTime() - active.sentAt > ACCEPT_WINDOW then
        self:Debug("ignored late JOIN from " .. sender)
        return
    end
    if active.responders[sender] then
        return
    end
    active.responders[sender] = true

    if extra == "grouped" then
        self:Print(RC.COLORS.SUCCESS .. who .. " is on the way|r (already in a group).")
        return
    end
    local ok, code = false, "off"
    if self.db.autoInvite then
        ok, code = self:InviteResponder(sender)
    end
    if ok then
        self:Print(RC.COLORS.SUCCESS .. who .. " is on the way.|r Invite sent.")
    else
        if code ~= "off" then
            self:Print(RC.COLORS.SUCCESS .. who .. " is on the way.|r Couldn't invite: " .. NOINVITE_REASONS[code] .. ".")
        else
            self:Print(RC.COLORS.SUCCESS .. who .. " is on the way.|r")
        end
        self:SendGuild(table.concat({ RC.PROTOCOL, "NOINVITE", sender, code }, "~"))
    end
end
