-- Rallying Cry - Settings Page
-- Registers a page under ESC > Options > AddOns. Every checkbox is a proxy
-- over RallyingCryDB, so the slash commands and this page edit the same values.

local RC = RallyingCry

local Options = {}
RC.Options = Options

local function AddHeader(layout, text)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function AddCheckbox(category, key, name, tooltip, default, getValue, setValue)
    local setting = Settings.RegisterProxySetting(category, "RallyingCry_" .. key,
        Settings.VarType.Boolean, name, default, getValue, setValue)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- Checkbox for a plain true/false field in RallyingCryDB
local function AddDBCheckbox(category, key, name, tooltip)
    AddCheckbox(category, key, name, tooltip, true,
        function() return RC.db[key] end,
        function(value) RC.db[key] = value end)
end

function Options:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end

    local category, layout = Settings.RegisterVerticalLayoutCategory("Rallying Cry")
    self.category = category

    AddHeader(layout, "Incoming Alerts")
    AddDBCheckbox(category, "popup", "Accept / Decline window",
        "Pop up a window for Ganked!, World PvP, and Hunt alerts. Accept joins the sender's group and sets a waypoint.")
    AddDBCheckbox(category, "banner", "Screen banner",
        "Show alerts in the middle of the screen like a raid warning.")
    AddDBCheckbox(category, "sound", "Sound",
        "Play a sound when an alert comes in.")
    AddCheckbox(category, "autoWaypoint", "Auto-waypoint",
        "Put a map waypoint on every alert as it arrives, without needing to Accept.",
        false,
        function() return RC.db.autoWaypoint end,
        function(value) RC.db.autoWaypoint = value end)

    AddHeader(layout, "Alert Types")
    for _, alertType in ipairs(RC.ALERT_ORDER) do
        local info = RC.ALERTS[alertType]
        AddCheckbox(category, "show" .. alertType, info.label,
            "When off, " .. info.label .. " alerts still show in chat, but with no window, banner, or sound.",
            true,
            function() return not RC.db.muted[alertType] end,
            function(value) RC.db.muted[alertType] = (not value) or nil end)
    end

    AddHeader(layout, "When Guildmates Answer Your Alert")
    AddDBCheckbox(category, "autoInvite", "Auto-invite",
        "Invite guildmates to your group when they accept your alert.")
    AddDBCheckbox(category, "autoRaid", "Convert to raid when full",
        "If your party is full and you lead it, turn it into a raid so more guildmates can join.")

    AddHeader(layout, "Panel & Minimap")
    AddCheckbox(category, "showPanel", "Show button panel",
        "The draggable panel with one button per alert. You can also use /rc panel or the keybindings.",
        true,
        function() return RC.db.showPanel end,
        function(value)
            if value then
                RC.Panel:Show()
            else
                RC.Panel:Hide(true)
            end
        end)

    AddCheckbox(category, "showMinimap", "Show minimap button",
        "Left-click toggles the panel, right-click opens these settings. Drag it to move it around the minimap.",
        true,
        function() return RC.db.showMinimap end,
        function(value) RC.MinimapButton:SetShown(value) end)

    Settings.RegisterAddOnCategory(category)
end

function Options:Open()
    if not self.category then
        RC:Print(RC.COLORS.WARNING .. "The settings page isn't available. Type /rc to see slash commands.|r")
        return
    end
    if InCombatLockdown() then
        RC:Print(RC.COLORS.WARNING .. "Settings can't open in combat.|r")
        return
    end
    Settings.OpenToCategory(self.category:GetID())
end
