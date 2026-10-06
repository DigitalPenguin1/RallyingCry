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
