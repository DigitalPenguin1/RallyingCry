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

-- One checkbox per sound. Keys are alert types, plus KOS for the ganker warning.
local SOUND_OPTIONS = {
    { key = "HELP", label = "Ganked! (zeppelin horn)",
      tooltip = "Play the zeppelin horn when a guildmate is being ganked." },
    { key = "WPVP", label = "World PvP (ready check)",
      tooltip = "Play the ready check sound when a guildmate finds world PvP." },
    { key = "HUNT", label = "Hunt Ganker (zeppelin horn)",
      tooltip = "Play the zeppelin horn when a guildmate rallies a hunting party." },
    { key = "KOS", label = "Ganker spotted (raid warning)",
      tooltip = "Play the raid warning when you target or mouse over a listed ganker or a KOS guild member." },
}

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
    AddCheckbox(category, "autoWaypoint", "Auto-waypoint",
        "Put a map waypoint on every alert as it arrives, without needing to Accept.",
        false,
        function() return RC.db.autoWaypoint end,
        function(value) RC.db.autoWaypoint = value end)

    AddHeader(layout, "Sounds")
    AddDBCheckbox(category, "sound", "Sounds",
        "Play sounds for alerts and ganker warnings. Turn off to silence all of them; the boxes below turn off one at a time.")
    for _, sound in ipairs(SOUND_OPTIONS) do
        AddCheckbox(category, "sound" .. sound.key, sound.label, sound.tooltip, true,
            function() return not RC.db.quietSounds[sound.key] end,
            function(value) RC.db.quietSounds[sound.key] = (not value) or nil end)
    end

    AddHeader(layout, "Alert Types")
    for _, alertType in ipairs(RC.ALERT_ORDER) do
        local info = RC.ALERTS[alertType]
        -- All Clear has no window, banner, or sound to turn off
        if alertType ~= "CLEAR" then
            AddCheckbox(category, "show" .. alertType, info.label,
                "When off, " .. info.label .. " alerts still show in chat, but with no window, banner, or sound.",
                true,
                function() return not RC.db.muted[alertType] end,
                function(value) RC.db.muted[alertType] = (not value) or nil end)
        end
    end

    AddHeader(layout, "When Guildmates Answer Your Alert")
    AddDBCheckbox(category, "autoInvite", "Auto-invite",
        "Invite guildmates to your group when they accept your alert.")
    AddDBCheckbox(category, "autoRaid", "Convert to raid when full",
        "If your party is full and you lead it, turn it into a raid so more guildmates can join.")

    AddHeader(layout, "Ganker List")
    AddDBCheckbox(category, "kosAutoAdd", "Add gankers from your alerts",
        "When your Ganked! or Hunt alert names an enemy player, add them to the guild ganker list.")
    AddDBCheckbox(category, "kosWarn", "Warn when you see a listed ganker",
        "Chat warning and a sound when you target or mouse over someone on the list, or a member of a KOS guild. Names can be hidden in combat, so this may not fire mid-fight.")

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
    if Settings.RegisterCanvasLayoutSubcategory then
        Settings.RegisterCanvasLayoutSubcategory(category, RC.SyncLog:CreatePage(), "Sync")
    end
    self:RegisterAbout(category)
end

----------------------------------------------------------------------
-- About page
----------------------------------------------------------------------

local SUPPORT_URL = "https://buymeacoffee.com/relyk22"
local GITHUB_URL = "https://github.com/DigitalPenguin1/RallyingCry"

-- WoW can't open links, so show them in a box the player can copy from.
-- Typing into it just puts the URL back.
local function CreateLinkBox(parent, url)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(320, 20)
    box:SetAutoFocus(false)
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnTextChanged", function(b, userInput)
        if userInput then
            b:SetText(url)
            b:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(b)
        b:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(b)
        b:HighlightText(0, 0)
    end)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

local function AddText(parent, anchor, text, font, gap, r, g, b)
    local line = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 8))
    line:SetWidth(560)
    line:SetJustifyH("LEFT")
    line:SetText(text)
    if r then
        line:SetTextColor(r, g, b)
    end
    return line
end

function Options:RegisterAbout(category)
    if not Settings.RegisterCanvasLayoutSubcategory then
        return
    end

    local frame = CreateFrame("Frame")
    local Theme = RC.Theme

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Rallying Cry")
    title:SetTextColor(Theme.Color(Theme.GOLD_LIGHT))

    local version = AddText(frame, title, "Version: |cffffd100" .. RC.VERSION .. "|r", "GameFontHighlight", 12)
    local author = AddText(frame, version, "Developed by: |cff00ccffRelyk|r", "GameFontHighlight", 4)

    local thanks = AddText(frame, author, "Thank you for using Rallying Cry!", "GameFontNormalLarge", 20)
    local about = AddText(frame, thanks,
        "Call your guild for backup in WoW: Forever. Send an alert when you're ganked, find world PvP, " ..
        "or want a party to hunt a ganker down, and guildmates can Accept to join your group with a waypoint to you. " ..
        "Type /rc in chat for every command.", "GameFontHighlight", 8)

    local support = AddText(frame, about, "If you enjoy this addon and want to support development:", "GameFontNormal", 20)
    local coffee = AddText(frame, support, "Buy me a coffee at:", "GameFontHighlight", 8, 0, 1, 0)
    local coffeeBox = CreateLinkBox(frame, SUPPORT_URL)
    coffeeBox:SetPoint("TOPLEFT", coffee, "BOTTOMLEFT", 6, -4)

    local bugs = AddText(frame, coffeeBox, "Found a bug or have an idea? Open an issue on GitHub:", "GameFontHighlight", 16)
    bugs:SetPoint("TOPLEFT", coffeeBox, "BOTTOMLEFT", -6, -16)
    local githubBox = CreateLinkBox(frame, GITHUB_URL)
    githubBox:SetPoint("TOPLEFT", bugs, "BOTTOMLEFT", 6, -4)

    AddText(frame, githubBox, "Click a link and press Ctrl+C to copy it.", "GameFontDisableSmall", 8)
        :SetPoint("TOPLEFT", githubBox, "BOTTOMLEFT", -6, -8)

    Settings.RegisterCanvasLayoutSubcategory(category, frame, "About")
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
