-- Rallying Cry - Forever Theme
-- Gold and bronze sampled from the Forever action bar (same palette as
-- Classic Fishing Companion's Forever theme).

local RC = RallyingCry

local Theme = {}
RC.Theme = Theme

-- Palette (r, g, b[, a])
Theme.GOLD = { 0.66, 0.50, 0.19, 1 }         -- Action bar slot border
Theme.GOLD_LIGHT = { 0.82, 0.66, 0.31, 1 }   -- Highlighted border, titles
Theme.BRONZE_DARK = { 0.13, 0.10, 0.04 }     -- Window background
Theme.BRONZE = { 0.22, 0.17, 0.08 }          -- Buttons

-- Banner tints behind the KOS window's faction crest
Theme.FACTION = {
    Horde = { 0.55, 0.06, 0.04 },
    Alliance = { 0.08, 0.22, 0.55 },
}

Theme.WINDOW_ALPHA = 0.95

Theme.WINDOW_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local BUTTON_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Unpack a palette entry with an optional alpha override
function Theme.Color(color, alpha)
    return color[1], color[2], color[3], alpha or color[4] or 1
end

function Theme.SkinWindow(frame)
    frame:SetBackdrop(Theme.WINDOW_BACKDROP)
    frame:SetBackdropColor(Theme.Color(Theme.BRONZE_DARK, Theme.WINDOW_ALPHA))
    frame:SetBackdropBorderColor(Theme.Color(Theme.GOLD))
end

-- Restyle a UIPanelButtonTemplate button. The template swaps its red art on
-- press and hover, so the art is faded out with alpha rather than hidden.
function Theme.SkinButton(button)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if button[key] then
            button[key]:SetAlpha(0)
        end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local texture = button[getter] and button[getter](button)
        if texture then
            texture:SetAlpha(0)
        end
    end

    if not button.SetBackdrop then
        Mixin(button, BackdropTemplateMixin)
        button:HookScript("OnSizeChanged", button.OnBackdropSizeChanged)
    end
    button:SetBackdrop(BUTTON_BACKDROP)
    button:SetBackdropColor(Theme.Color(Theme.BRONZE, 0.9))
    button:SetBackdropBorderColor(Theme.Color(Theme.GOLD))

    -- HIGHLIGHT layer shows on mouseover
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", -3, 3)
    highlight:SetColorTexture(Theme.Color(Theme.GOLD_LIGHT, 0.15))
end

-- A gold X that sits inside the window's top-right corner, in place of
-- Blizzard's red close button. Hides the parent unless given onClick.
function Theme.CreateCloseButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(18, 18)
    button:SetPoint("TOPRIGHT", -6, -6)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 1, 0)
    label:SetText("X")
    label:SetTextColor(Theme.Color(Theme.GOLD))

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(Theme.Color(Theme.GOLD_LIGHT, 0.15))

    button:SetScript("OnEnter", function()
        label:SetTextColor(1, 0.9, 0.6)
    end)
    button:SetScript("OnLeave", function()
        label:SetTextColor(Theme.Color(Theme.GOLD))
    end)
    button:SetScript("OnMouseDown", function()
        label:SetPoint("CENTER", 2, -1)
    end)
    button:SetScript("OnMouseUp", function()
        label:SetPoint("CENTER", 1, 0)
    end)
    button:SetScript("OnClick", onClick or function()
        parent:Hide()
    end)
    return button
end

----------------------------------------------------------------------
-- Guild crest
----------------------------------------------------------------------

-- Round faction crests (ui_hordeicon-round, ui_allianceicon-round)
Theme.FACTION_CRESTS = { Horde = 2175464, Alliance = 2175463 }

-- Crest when the player's faction isn't known
local ADDON_ICON = "Interface\\Icons\\Ability_Warrior_RallyingCry"

local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The tabard is drawn as a gold rim, then the guild's border and background
-- colors, with the emblem on top. Insets are for a 50px crest and scale
-- with its size.
local TABARD_RINGS = {
    -- key, inset from the crest's edge
    { "rim", 0 },
    { "border", 3 },
    { "background", 6 },
}
local EMBLEM_INSET = 8

-- Every emblem on one sheet, 16 to a row in 64px cells, the way Blizzard's
-- large guild tabards pick theirs by emblemStyle. (emblemFileID is only
-- half an emblem, for mirrored tabard halves.)
local EMBLEM_SHEET = "Interface\\GuildFrame\\GuildEmblemsLG_01"
local EMBLEM_COLUMNS = 16
local EMBLEM_CELL = 64 / 1024

-- A crest-sized frame showing the guild's tabard, or the faction crest when
-- there's no tabard. Position it, then call RefreshGuildCrest.
function Theme.CreateGuildCrest(parent, size)
    local crest = CreateFrame("Frame", nil, parent)
    crest:SetSize(size, size)
    local scale = size / 50

    crest.fallback = crest:CreateTexture(nil, "ARTWORK")
    crest.fallback:SetAllPoints()

    crest.tabard = {}
    for level, ring in ipairs(TABARD_RINGS) do
        local key, inset = ring[1], ring[2] * scale
        local disc = crest:CreateTexture(nil, "ARTWORK", nil, level)
        disc:SetPoint("TOPLEFT", inset, -inset)
        disc:SetPoint("BOTTOMRIGHT", -inset, inset)
        disc:SetColorTexture(1, 1, 1)
        -- Each disc is cut round by its own mask
        local mask = crest:CreateMaskTexture()
        mask:SetAllPoints(disc)
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        disc:AddMaskTexture(mask)
        crest.tabard[key] = disc
    end
    crest.tabard.rim:SetVertexColor(Theme.Color(Theme.GOLD))

    -- Emblems are drawn 7/8 as wide as they are tall
    local emblem = crest:CreateTexture(nil, "ARTWORK", nil, #TABARD_RINGS + 1)
    local height = size - EMBLEM_INSET * scale * 2
    emblem:SetSize(height * 7 / 8, height)
    emblem:SetPoint("CENTER")
    emblem:SetTexture(EMBLEM_SHEET)
    crest.tabard.emblem = emblem
    return crest
end

-- The player's guild tabard, or nil if there's no guild or it never
-- designed one
local function TabardInfo()
    if not (IsInGuild() and C_GuildInfo and C_GuildInfo.GetGuildTabardInfo) then
        return nil
    end
    local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
    return ok and info and info.emblemStyle and info or nil
end

function Theme.RefreshGuildCrest(crest, faction)
    local info = TabardInfo()
    for _, part in pairs(crest.tabard) do
        part:SetShown(info ~= nil)
    end
    crest.fallback:SetShown(info == nil)
    if info then
        crest.tabard.border:SetVertexColor(info.borderColor:GetRGB())
        crest.tabard.background:SetVertexColor(info.backgroundColor:GetRGB())
        local x = (info.emblemStyle % EMBLEM_COLUMNS) * EMBLEM_CELL
        local y = math.floor(info.emblemStyle / EMBLEM_COLUMNS) * EMBLEM_CELL
        crest.tabard.emblem:SetTexCoord(x, x + EMBLEM_CELL, y, y + EMBLEM_CELL)
        crest.tabard.emblem:SetVertexColor(info.emblemColor:GetRGB())
    elseif faction and Theme.FACTION_CRESTS[faction] then
        crest.fallback:SetTexture(Theme.FACTION_CRESTS[faction])
        crest.fallback:SetTexCoord(0, 1, 0, 1)
    else
        crest.fallback:SetTexture(ADDON_ICON)
        crest.fallback:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end
