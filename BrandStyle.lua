-- BrandStyle.lua
-- Xal's Compendium
--
-- Xal's shared visual brand, current as of 2026-09-28: dark indigo solid
-- background + dark brick red as the ONE accent color everywhere - titles,
-- section headers, checkbox/link text, every button label - no separate
-- orange anymore (confirmed 2026-09-25, "everything the same dark red, no
-- exceptions"). Borders/dividers use a subtle near-black indigo instead of
-- standing out in the accent color. Buttons are borderless text links, not
-- boxed (confirmed 2026-08-17/18 - "I don't like the blocky look"). Every
-- border/divider line is at least 2px - a 1px line can fail to render
-- reliably depending on UI scale.
--
-- Used ONLY by WhatsNew.lua's splash screen here - Compendium's own live
-- windows (the tracker and both settings panels) intentionally keep using
-- XComp.GetAccentColor()/GetBgColor() from Core.lua instead of the fixed
-- colors below, since Compendium already lets players customize those two
-- colors themselves (a feature no other addon has). The splash is a
-- one-time branded screen shared in spirit with every other addon's splash,
-- so it uses the fixed brand colors like they do.
local addonName, addonTable = ...
addonTable.BrandStyle = {}
local Brand = addonTable.BrandStyle

-- ── Colours (r, g, b) ─────────────────────────────────────────
-- Old bronze-gold and the 2026-09-02 burnt-orange default are both kept
-- defined (not deleted or repointed) only in case an addon ever grows an
-- explicit "Classic" style option - neither is used as a default color
-- anywhere below anymore.
Brand.ACCENT = { 0.72, 0.55, 0.22 }   -- warm bronze-gold (Classic only, unused by default)
Brand.ACCENT_ORANGE = { 0.72, 0.30, 0.0 } -- 2026-09-02 default, superseded (unused by default)
Brand.GOLD   = { 0.60, 0.47, 0.30 }   -- secondary/body text tone (still used for muted body copy like item lists)
Brand.BG     = { 0.03, 0.028, 0.06, 1 } -- dark indigo leaning purple (#08070f), fully opaque - solid color, no background image by default

Brand.HEADER_COLOR = { 0.4078, 0.0784, 0.0902 } -- #681417, dark brick red.
    -- Titles, the header divider, selected sidebar-style links, section
    -- headers, checkbox/slider label text, and every button/link label -
    -- literally everywhere Brand.ACCENT/ACCENT_ORANGE used to be the
    -- default. Do not reach for ACCENT/ACCENT_ORANGE for a new default call
    -- site - only an explicit Classic-flagged one re-tints to those.
Brand.DIVIDER_COLOR = { 0.0627, 0.0627, 0.1255 } -- #101020, near-black indigo.
    -- Every OTHER divider (section/list dividers), plus panel/card edges
    -- (DrawBorder()'s default color) and the outer window border.
Brand.SIDEBAR_UNSELECTED = { 0.196, 0.196, 0.392 } -- #323264, muted blue-gray.
    -- An UNselected link in a standalone window's own sidebar. Selected
    -- uses Brand.HEADER_COLOR above, not white and not accent-orange.
Brand.LINE_THICKNESS = 2 -- minimum for ANY border/divider - never go below this
Brand.SAFE_MARGIN = 14

-- ── T()  ─ solid-colour texture rectangle.
function Brand.T(parent, x, y, w, h, r, g, b, a, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    PixelUtil.SetPoint(tex, "TOPLEFT", parent, "TOPLEFT", x, -y)
    PixelUtil.SetSize(tex, w, h)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

-- ── FS()  ─ a FontString with a specific font/size/colour.
function Brand.FS(parent, text, fontPath, size, flags, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath, size, flags or "")
    fs:SetText(text)
    fs:SetTextColor(r, g, b, 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- ── BodyFS()  ─ Brand.FS pre-wired to the body font, with a subtle drop
-- shadow so small body text stays legible over busy backgrounds.
function Brand.BodyFS(parent, text, size, r, g, b)
    local fs = Brand.FS(parent, text, Brand.BODY_FONT_PATH, size, "", r or 0.85, g or 0.85, b or 0.85)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    return fs
end

-- ── Font paths ────────────────────────────────────────────────
-- Header/title font: Cinzel Bold (bundled, SIL OFL). Body/label font: Inter
-- Regular/SemiBold (bundled, SIL OFL) - current go-forward pairing.
Brand.TITLE_FONT_PATH = "Interface\\AddOns\\XalsCompendium\\Fonts\\Cinzel-Bold.ttf"
Brand.BODY_FONT_PATH = "Interface\\AddOns\\XalsCompendium\\Fonts\\Inter-Regular.ttf"
Brand.BODY_FONT_PATH_SEMIBOLD = "Interface\\AddOns\\XalsCompendium\\Fonts\\Inter-SemiBold.ttf"

-- ── Title()  ─ the branded title treatment, with its drop-shadow layer, in
-- one call. Returns the visible (front) fontstring.
function Brand.Title(parent, text, size, anchorPoint, relTo, relPoint, x, y)
    local shadow = Brand.FS(parent, text, Brand.TITLE_FONT_PATH, size, "OUTLINE", 0, 0, 0)
    PixelUtil.SetPoint(shadow, anchorPoint, relTo, relPoint, x + 4, y - 4)
    shadow:SetJustifyH("CENTER")

    local title = Brand.FS(parent, text, Brand.TITLE_FONT_PATH, size, "OUTLINE",
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3])
    PixelUtil.SetPoint(title, anchorPoint, relTo, relPoint, x, y)
    title:SetJustifyH("CENTER")
    return title
end

-- Unselected label color - Brand.HEADER_COLOR, the one accent color
-- everywhere now, not a separate orange.
local BTN_LABEL_UNSELECTED = Brand.HEADER_COLOR

-- ── MakeButton()  ─ text-link style: plain text, no fill, no border.
-- Selected vs. normal state is carried entirely by label color/brightness.
-- Call btn:SetSelected(true/false) to toggle white (selected) vs. the
-- unselected dark red.
function Brand.MakeButton(parent, text, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent)
    PixelUtil.SetSize(btn, w, h)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
    btn.label = label

    btn.selectedColor = { 1, 1, 1 }
    btn.unselectedColor = BTN_LABEL_UNSELECTED

    btn:SetScript("OnEnter", function(self)
        if not self.selected then label:SetTextColor(1, 1, 1, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.selected then
            local c = self.unselectedColor
            label:SetTextColor(c[1], c[2], c[3], 1)
        end
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    function btn:SetSelected(selected)
        self.selected = selected
        local c = selected and self.selectedColor or self.unselectedColor
        label:SetTextColor(c[1], c[2], c[3], 1)
    end

    function btn:SetSelectedColor(r, g, b)
        self.selectedColor = { r, g, b }
        if self.selected then label:SetTextColor(r, g, b, 1) end
    end

    function btn:SetUnselectedColor(r, g, b)
        self.unselectedColor = { r, g, b }
        if not self.selected then label:SetTextColor(r, g, b, 1) end
    end

    function btn:SetBorderColor(r, g, bC, a)
        label:SetTextColor(r, g, bC, a)
    end

    return btn
end

-- ── MakeCloseButton()  ─ text-link style close ("Close" in dark red,
-- brightens to white on hover) - replaces the boxed "X" button.
function Brand.MakeCloseButton(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(50, 20)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText("Close")
    label:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 1)
    btn.label = label

    btn:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 1)
    end)
    btn:SetScript("OnClick", onClick or function() parent:Hide() end)

    return btn
end

-- ── MakeLinkButton()  ─ a second, deliberately plain button style for
-- inline quick-toggles (no border/fill).
function Brand.MakeLinkButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFont(Brand.BODY_FONT_PATH, 12, "")
    label:SetPoint("CENTER")
    btn.label = label

    function btn:SetLabel(text, r, g, b)
        label:SetText(text)
        if r then label:SetTextColor(r, g, b, 1) end
        btn.baseColor = { r or Brand.HEADER_COLOR[1], g or Brand.HEADER_COLOR[2], b or Brand.HEADER_COLOR[3] }
    end

    btn:HookScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
    btn:HookScript("OnLeave", function()
        local c = btn.baseColor or Brand.HEADER_COLOR
        label:SetTextColor(c[1], c[2], c[3], 1)
    end)

    return btn
end

-- ── DrawBorder()  ─ single clean line around a frame, in Brand.DIVIDER_COLOR.
-- Use inset 1 for a standalone window's true outer edge, inset 0 (or the
-- default 6) for a panel/card edge within a page.
function Brand.DrawBorder(f, inset)
    inset = inset or 6
    local thick = Brand.LINE_THICKNESS
    local r, g, b = Brand.DIVIDER_COLOR[1], Brand.DIVIDER_COLOR[2], Brand.DIVIDER_COLOR[3]

    local top = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(top, "TOPLEFT", f, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(top, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
    PixelUtil.SetHeight(top, thick)
    top:SetColorTexture(r, g, b, 1)

    local bottom = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    PixelUtil.SetHeight(bottom, thick)
    bottom:SetColorTexture(r, g, b, 1)

    local left = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(left, "TOPLEFT", f, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    PixelUtil.SetWidth(left, thick)
    left:SetColorTexture(r, g, b, 1)

    local right = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(right, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    PixelUtil.SetWidth(right, thick)
    right:SetColorTexture(r, g, b, 1)

    return top, bottom, left, right
end

-- ── DrawDivider()  ─ the thin section-separator line used between content
-- blocks (feature lists, header bars, etc.) - Brand.DIVIDER_COLOR.
function Brand.DrawDivider(parent, x, y, width)
    return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS,
        Brand.DIVIDER_COLOR[1], Brand.DIVIDER_COLOR[2], Brand.DIVIDER_COLOR[3], 1)
end

-- ── DrawHeaderDivider()  ─ the ONE divider directly under a window's main
-- title, in Brand.HEADER_COLOR - its own distinct color, separate from every
-- other divider (which uses DrawDivider above).
function Brand.DrawHeaderDivider(parent, x, y, width)
    return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS,
        Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3], 1)
end

-- ── ApplyBackground()  ─ the standard opaque dark-indigo frame background.
function Brand.ApplyBackground(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Brand.BG[1], Brand.BG[2], Brand.BG[3], Brand.BG[4])
    return bg
end

-- ── ApplyBackgroundImage()  ─ the OLD shared dark-swirl texture art. NOT
-- called by default anymore - kept only for an explicit "Classic" style
-- option, not for new panels by default.
function Brand.ApplyBackgroundImage(f)
    local img = f:CreateTexture(nil, "BORDER")
    img:SetAllPoints(f)
    img:SetTexture("Interface\\AddOns\\XalsCompendium\\Textures\\PanelBackground.jpg")
    return img
end

-- ── MakeCheckbox()  ─ hand-drawn checkbox, same pixel-snapped 4-texture
-- border technique as MakeButton/DrawBorder. Usage differs slightly from a
-- native CheckButton: set `cb.OnToggle = function(self) ... end` instead of
-- `cb:SetScript("OnClick", ...)`.
function Brand.MakeCheckbox(parent, size)
    size = size or 22
    local cb = CreateFrame("Button", nil, parent)
    PixelUtil.SetSize(cb, size, size)

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

    local thick = Brand.LINE_THICKNESS
    local r, g, b = Brand.HEADER_COLOR[1], Brand.HEADER_COLOR[2], Brand.HEADER_COLOR[3]

    local borderTop = cb:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderTop, "TOPLEFT", cb, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(borderTop, "TOPRIGHT", cb, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(borderTop, thick)
    borderTop:SetColorTexture(r, g, b, 1)

    local borderBottom = cb:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(borderBottom, thick)
    borderBottom:SetColorTexture(r, g, b, 1)

    local borderLeft = cb:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderLeft, "TOPLEFT", cb, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(borderLeft, thick)
    borderLeft:SetColorTexture(r, g, b, 1)

    local borderRight = cb:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderRight, "TOPRIGHT", cb, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(borderRight, thick)
    borderRight:SetColorTexture(r, g, b, 1)

    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetVertexColor(r, g, b, 1)
    PixelUtil.SetSize(check, size - 4, size - 4)
    check:SetPoint("CENTER", cb, "CENTER", 0, 0)
    check:Hide()

    cb.checked = false
    function cb:SetChecked(state)
        self.checked = state and true or false
        if self.checked then check:Show() else check:Hide() end
    end
    function cb:GetChecked()
        return self.checked
    end

    cb:SetScript("OnEnter", function() bg:SetColorTexture(0.18, 0.18, 0.18, 0.75) end)
    cb:SetScript("OnLeave", function() bg:SetColorTexture(0.1, 0.1, 0.1, 0.6) end)
    cb:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.OnToggle then self.OnToggle(self) end
    end)

    return cb
end

-- ── ShowContextMenu()  ─ a right-click menu built entirely from brand
-- widgets (bordered background, text-link entries) - NOT Blizzard's
-- UIDropDownMenu/EasyMenu.
--
-- options is an array of { label, r, g, b, onClick } - r/g/b optional
-- (defaults to Brand.HEADER_COLOR).
local contextMenu, clickCatcher

function Brand.ShowContextMenu(options)
    if not clickCatcher then
        clickCatcher = CreateFrame("Button", nil, UIParent)
        clickCatcher:SetAllPoints(UIParent)
        clickCatcher:SetFrameStrata("FULLSCREEN")
        clickCatcher:Hide()
    end

    if not contextMenu then
        contextMenu = CreateFrame("Frame", nil, UIParent)
        contextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        Brand.ApplyBackground(contextMenu)
        Brand.DrawBorder(contextMenu, 4)
        contextMenu.buttons = {}
        contextMenu:Hide()
    end

    local ROW_H, PAD = 22, 10
    local width = 90
    for i, opt in ipairs(options) do
        local btn = contextMenu.buttons[i]
        if not btn then
            btn = Brand.MakeLinkButton(contextMenu)
            btn:SetHeight(ROW_H)
            contextMenu.buttons[i] = btn
        end
        btn:SetLabel(opt.label, opt.r or Brand.HEADER_COLOR[1], opt.g or Brand.HEADER_COLOR[2], opt.b or Brand.HEADER_COLOR[3])
        btn:SetPoint("TOPLEFT", contextMenu, "TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
        btn:SetScript("OnClick", function()
            clickCatcher:Hide()
            contextMenu:Hide()
            if opt.onClick then opt.onClick() end
        end)
        btn:Show()
        local w = btn.label:GetStringWidth() + 4
        if w > width then width = w end
    end
    for i = #options + 1, #contextMenu.buttons do
        contextMenu.buttons[i]:Hide()
    end
    for _, btn in ipairs(contextMenu.buttons) do btn:SetWidth(width) end

    contextMenu:SetSize(width + PAD * 2, #options * ROW_H + PAD * 2)

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    contextMenu:ClearAllPoints()
    contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)

    clickCatcher:Show()
    clickCatcher:SetScript("OnClick", function()
        clickCatcher:Hide()
        contextMenu:Hide()
    end)
    contextMenu:Show()
end
