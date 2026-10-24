-- Xal's Compendium
-- Options.lua holds the settings panel: the required module page listing
-- every trackable section (name + description + on/off toggle), styled to
-- match the main window rather than a generic Blizzard template page.
--
-- Two access paths, NOT equal priority:
--   1. O:ToggleStandalone() (/xcp options) - the DEFAULT/primary settings
--      window. Point to this one by default anywhere the addon needs to
--      send a player to settings (minimap button right-click, help text,
--      etc.) once those exist.
--   2. O:Register() - Blizzard's native Options -> AddOns list, via the
--      modern Settings API (Settings.RegisterCanvasLayoutCategory). An
--      ADDITIONAL/secondary method, for players who go looking there out
--      of habit - not the one we promote as "the" settings menu.
--
-- Pages within each path (real separate sections, not one long list, per
-- explicit user request - matches XalsXpeditedRoutes' SettingsPanel.lua,
-- which splits into Waypoint/Map Markers/Gather Tally/Database/Integrations
-- rather than one long page): General (tracked sections + auto-size) and
-- Appearance (frameless/transparency/scale/icon). Native panel uses genuine
-- Settings.RegisterCanvasLayoutSubcategory pages; standalone window uses a
-- simple tab switcher between containers in the same frame.
--
-- Accent/background color and text font/outline/size are NOT
-- player-customizable (2026-09-29 correction - a prior "Colors" settings
-- page let players override both away from the current brand look, which
-- defeated the point of having one). XComp.GetAccentColor()/GetBgColor()
-- and the TitleFont/BodyFont font objects still exist as the single source
-- of truth every file reads from, they just always resolve to the fixed
-- brand values now - see Core.lua.

XComp.Options = XComp.Options or {}
local O = XComp.Options

-- Background color/alpha are live (XComp.GetBgColor from Core.lua, settings
-- alpha) so both settings windows stay visually consistent with the main
-- tracker's own customizable background, not a separate fixed color.
local function GetPanelBg()
	local r, g, b = XComp.GetBgColor()
	return r, g, b, 0.95
end

-------------------------------------------------
-- Section enable/disable state
-------------------------------------------------
local function EnsureTypeEnabledTable()
	XComp_DB.settings = XComp_DB.settings or {}
	XComp_DB.settings.typeEnabled = XComp_DB.settings.typeEnabled or {}
	return XComp_DB.settings.typeEnabled
end

function O:IsTypeEnabled(key)
	local t = EnsureTypeEnabledTable()
	if t[key] == nil then return true end -- default: enabled
	return t[key]
end

function O:SetTypeEnabled(key, value)
	EnsureTypeEnabledTable()[key] = value
end

-------------------------------------------------
-- Legacy tier enable/disable + per-zone selection (2026-09-29) - Legacy
-- isn't a "type" like Daily/Weekly/One-time (shared across both tiers), it's
-- a whole TIER, so it needs its own toggle rather than reusing
-- IsTypeEnabled. Opt-IN, not opt-out (corrected same day - the first pass
-- had this backwards): with no zones checked, Legacy contributes nothing at
-- all, to both the tracker's Legacy tab AND the floating icon's count.
-- Checking a zone is what turns it on for both.
-------------------------------------------------
function O:IsLegacyEnabled()
	local s = XComp_DB.settings
	if not s or s.legacyEnabled == nil then return true end
	return s.legacyEnabled
end

function O:SetLegacyEnabled(value)
	XComp_DB.settings = XComp_DB.settings or {}
	XComp_DB.settings.legacyEnabled = value
end

-- Whether a given Legacy group name (a real zone, or a category label for
-- anything zoneless) should render/count. Opt-in: nothing shows until it's
-- actually checked.
function O:IsLegacyZoneEnabled(zoneName)
	local zones = XComp_DB.settings and XComp_DB.settings.legacyZones
	if not zones then return false end
	return zones[zoneName] == true
end

function O:SetLegacyZoneEnabled(zoneName, value)
	XComp_DB.settings = XComp_DB.settings or {}
	XComp_DB.settings.legacyZones = XComp_DB.settings.legacyZones or {}
	XComp_DB.settings.legacyZones[zoneName] = value or nil
end

-- Tracks every populated container of each kind so ResetToDefaults can
-- refresh all of them (native General, native Appearance, standalone
-- General, standalone Appearance) regardless of which one the user
-- clicked "Reset" from.
local generalContainers = {}
local appearanceContainers = {}
local backupContainers = {}

-- Standing rule: every customizable feature needs a small, unobtrusive
-- "reset to default" option. Clears per-type enable/disable overrides and
-- appearance settings (frameless/bgAlpha/scale) back to default - one
-- unified reset rather than a separate button per customizable feature.
function O:ResetToDefaults()
	XComp_DB.settings.typeEnabled = {}
	XComp_DB.settings.frameless = nil
	XComp_DB.settings.bgAlpha = nil
	XComp_DB.settings.scale = nil
	XComp_DB.settings.idleAlpha = nil
	XComp_DB.settings.typeOrder = nil
	XComp_DB.settings.categoryOrder = nil
	XComp_DB.settings.floatingIconSize = nil
	if XComp.SetFloatingIconSize then XComp.SetFloatingIconSize(52) end
	if XComp.UI then
		XComp.UI:ApplyTheme()
		XComp.UI:ApplyIdleAlpha()
		if XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
			XComp.UI:RefreshSections()
		end
	end
	for _, c in ipairs(generalContainers) do self:PopulateGeneralRows(c) end
	for _, c in ipairs(appearanceContainers) do self:PopulateAppearanceRows(c) end
end

-------------------------------------------------
-- Module reordering (build-plan item 8) - real precedent confirmed via
-- Kaliel's Tracker (CurseForge), which has this exact feature ("Modules
-- order inside the tracker"). Shared across both tiers, same rule already
-- used for the enable/disable toggle and header colors - a type/category is
-- one shared thing that happens to appear under both Current and Legacy,
-- not two independent copies with independent order.
-------------------------------------------------
local TYPE_KEYS = { "daily", "weekly", "onetime" }
local CATEGORY_KEYS = { "greatVault", "currencies", "weeklyEvents", "professions", "reputation", "storyCampaign", "worldQuests", "custom", "holidayEvents" }

local function EnsureOrderTable(settingsKey, defaultKeys)
	XComp_DB.settings = XComp_DB.settings or {}
	local order = XComp_DB.settings[settingsKey]
	if not order then
		order = {}
		for i, k in ipairs(defaultKeys) do order[i] = k end
		XComp_DB.settings[settingsKey] = order
	end
	-- Append any keys missing from a saved order (e.g. new content added
	-- after the user already customized their order) so nothing silently
	-- disappears from the list.
	for _, k in ipairs(defaultKeys) do
		local found = false
		for _, existing in ipairs(order) do
			if existing == k then found = true break end
		end
		if not found then table.insert(order, k) end
	end
	return order
end

function O:GetOrderedTypes(tier)
	local order = EnsureOrderTable("typeOrder", TYPE_KEYS)
	local byKey = {}
	for _, t in ipairs(tier.types) do byKey[t.key] = t end
	local ordered = {}
	for _, key in ipairs(order) do
		if byKey[key] then table.insert(ordered, byKey[key]) end
	end
	return ordered
end

function O:GetOrderedCategories(typeSection)
	local order = EnsureOrderTable("categoryOrder", CATEGORY_KEYS)
	local byKey = {}
	for _, c in ipairs(typeSection.categories) do byKey[c.key] = c end
	local ordered = {}
	for _, key in ipairs(order) do
		if byKey[key] then table.insert(ordered, byKey[key]) end
	end
	return ordered
end

-- direction: -1 moves earlier in the list, 1 moves later. isEnabledFn
-- (optional) skips PAST disabled entries when looking for a neighbor to
-- swap with, instead of swapping with the literal next slot - otherwise a
-- module sitting next to a disabled one would eat a click doing nothing
-- visible (it swapped with an invisible neighbor), or a visible reorder
-- could get blocked by disabled entries at the very end of the list even
-- though a visible module is still reachable further along.
local function MoveKey(settingsKey, defaultKeys, key, direction, isEnabledFn)
	local order = EnsureOrderTable(settingsKey, defaultKeys)
	local idx
	for i, k in ipairs(order) do
		if k == key then idx = i break end
	end
	if not idx then return end
	local j = idx + direction
	while j >= 1 and j <= #order do
		if not isEnabledFn or isEnabledFn(order[j]) then
			order[idx], order[j] = order[j], order[idx]
			return
		end
		j = j + direction
	end
end

function O:MoveType(key, direction)
	MoveKey("typeOrder", TYPE_KEYS, key, direction, function(k) return self:IsTypeEnabled(k) end)
end

function O:MoveCategory(key, direction)
	MoveKey("categoryOrder", CATEGORY_KEYS, key, direction)
end

-------------------------------------------------
-- Shared content (used by BOTH the Blizzard-native panel AND the
-- standalone window - two separate, independent access paths to the same
-- settings, not one path styled two ways)
-------------------------------------------------
-- Text-link button - Xal's current shared brand button (superseded the old
-- boxed/bordered version 2026-08-17/18, "I don't like the blocky look").
-- Plain text, no fill, no border - selection/hover carried entirely by
-- label color/brightness. Unselected label is the addon's fixed accent
-- color by default; selected/hover is white. A standalone window's own
-- SIDEBAR nav tabs override the unselected color to XComp.SIDEBAR_UNSELECTED
-- instead (via :SetUnselectedColor() below) - narrowly scoped to sidebar
-- links only, per the family standard. Used for every button in the addon
-- instead of Blizzard's chunky UIPanelButtonTemplate. Optional
-- :SetSelected() is only used by tabs.
local LINE_THICKNESS = 2 -- still used by the header divider below

local function MakeFlatButton(parent, anchorTo, width, text, onClick)
	local btn = CreateFrame("Button", nil, parent)
	PixelUtil.SetSize(btn, width, 22)
	if anchorTo then
		btn:SetPoint("LEFT", anchorTo, "RIGHT", 4, 0)
	elseif anchorTo == false then
		-- caller positions the button itself (SetPoint called after return)
	else
		btn:SetPoint("LEFT", parent, "LEFT", 0, 0)
	end

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(text)
	local ar, ag, ab = XComp.GetAccentColor()
	label:SetTextColor(ar, ag, ab, 1)
	btn.label = label
	btn.unselectedColor = { ar, ag, ab }

	btn:SetScript("OnEnter", function(self)
		if not self.selected then label:SetTextColor(1, 1, 1, 1) end
	end)
	btn:SetScript("OnLeave", function(self)
		if not self.selected then
			local c = self.unselectedColor
			label:SetTextColor(c[1], c[2], c[3], 1)
		end
	end)
	btn:SetScript("OnClick", onClick)

	btn.selectedColor = { 1, 1, 1 }

	function btn:SetSelected(selected)
		self.selected = selected
		if selected then
			local c = self.selectedColor
			label:SetTextColor(c[1], c[2], c[3], 1)
		else
			local c = self.unselectedColor
			label:SetTextColor(c[1], c[2], c[3], 1)
		end
	end

	-- Sidebar tabs call these once, right after creation, to switch their
	-- selected/unselected colors away from the default white/accent pair to
	-- the sidebar-specific accent/muted-blue-gray pair instead - narrowly
	-- scoped to a standalone window's own sidebar nav, per the family
	-- standard (a selected sidebar link is the accent color, not white).
	function btn:SetSelectedColor(r, g, b)
		self.selectedColor = { r, g, b }
		if self.selected then label:SetTextColor(r, g, b, 1) end
	end

	function btn:SetUnselectedColor(r, g, b)
		self.unselectedColor = { r, g, b }
		if not self.selected then label:SetTextColor(r, g, b, 1) end
	end

	-- Bumps the label's font size, keeping whatever font/flags it already
	-- has - per the family's confirmed settings-panel typography standard
	-- (label text at 14px, Blizzard's ~10-12px default reads too small
	-- against busy WoW terrain). Sidebar nav tabs call this; ordinary
	-- buttons elsewhere keep the default size.
	function btn:SetFontSize(size)
		local fontPath, _, flags = label:GetFont()
		label:SetFont(fontPath, size, flags)
	end

	return btn
end

-- Hand-drawn checkbox - shared XComp.MakeCheckbox, defined in Core.lua so
-- both this file and UI.lua can use it.
local MakeCheckbox = XComp.MakeCheckbox

-------------------------------------------------
-- Standing Discord link (2026-09-29) - the real Discord wordmark logo as
-- the clickable element itself, no separate text label, matching the
-- current family standard (confirmed 2026-09-20 on Roster Roundup: "just
-- the logo, no separate text"). Lua can't open a browser directly, so
-- clicking it pops a copy-a-URL box instead. Lives at the bottom of the
-- standalone window's sidebar, visible on every page - see
-- BuildStandaloneWindow below.
-------------------------------------------------
local DISCORD_URL = "https://discord.gg/9SwrQDJeCe"
local DISCORD_LOGO_ICON = "Interface\\AddOns\\XalsCompendium\\Textures\\DiscordLogo.png"
local DISCORD_LOGO_ASPECT = 42 / 280

local copyBoxFrame

local function ShowCopyBox(caption, url)
	if not url or url == "" then return end

	if not copyBoxFrame then
		local f = CreateFrame("Frame", "XalsCompendiumCopyBox", UIParent)
		f:SetSize(360, 130)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetToplevel(true)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		f:SetClampedToScreen(true)
		tinsert(UISpecialFrames, "XalsCompendiumCopyBox")

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(GetPanelBg())

		local cbr, cbg, cbb = XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3]
		local border = f:CreateTexture(nil, "ARTWORK")
		border:SetColorTexture(cbr, cbg, cbb, 1)
		PixelUtil.SetHeight(border, 2)
		border:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		border:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

		local car, cag, cab = XComp.GetAccentColor()
		f.caption = f:CreateFontString(nil, "OVERLAY")
		f.caption:SetFont(XComp.TITLE_FONT_PATH, 15, "")
		f.caption:SetTextColor(car, cag, cab, 1)
		f.caption:SetPoint("TOP", f, "TOP", 0, -14)

		local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
		box:SetHeight(22)
		box:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -46)
		box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -46)
		box:SetAutoFocus(true)
		box:SetFontObject("GameFontHighlightSmall")
		box:SetScript("OnTextChanged", function(self)
			if self.locked then return end
			self.locked = true
			self:SetText(f.url or "")
			self:HighlightText()
			self.locked = false
		end)
		box:SetScript("OnEscapePressed", function() f:Hide() end)
		f.box = box

		local hint = f:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(XComp.BodyFont)
		hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
		hint:SetText("Ctrl+C to copy")

		XComp.MakeCloseButton(f)

		copyBoxFrame = f
	end

	copyBoxFrame.url = url
	copyBoxFrame.caption:SetText(caption or "Copy this link")
	copyBoxFrame.box.locked = true
	copyBoxFrame.box:SetText(url)
	copyBoxFrame.box.locked = false
	copyBoxFrame:Show()
	copyBoxFrame.box:SetFocus()
	copyBoxFrame.box:HighlightText()
end

local function MakeDiscordLogoLink(parent, width)
	width = width or 116
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width, width * DISCORD_LOGO_ASPECT)

	local logo = btn:CreateTexture(nil, "ARTWORK")
	logo:SetAllPoints()
	logo:SetTexture(DISCORD_LOGO_ICON)
	logo:SetAlpha(0.9)
	btn.logo = logo

	btn:SetScript("OnEnter", function() logo:SetAlpha(1) end)
	btn:SetScript("OnLeave", function() logo:SetAlpha(0.9) end)
	btn:SetScript("OnClick", function()
		ShowCopyBox("Join us on Discord", DISCORD_URL)
	end)

	return btn
end

-- Builds the common header (title, divider) onto any parent frame - shared
-- between the native panel and the standalone window so both look
-- identical without duplicating the layout code. "Reset to Defaults" used
-- to live here (every page), moved to live only on the Backup page instead
-- (2026-09-29) - it's a real, semi-destructive action, belongs with the
-- other backup/restore controls, not floating on every single page.
local function BuildHeader(parent)
	local ar, ag, ab = XComp.GetAccentColor()

	local title = parent:CreateFontString(nil, "OVERLAY")
	title:SetFont(XComp.TITLE_FONT_PATH, 20, "")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
	title:SetTextColor(ar, ag, ab, 1)
	title:SetText("Xal's Compendium")
	XComp.ApplyTextShadow(title)

	local divider = parent:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(ar, ag, ab, 1)
	divider:SetHeight(LINE_THICKNESS)
	divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	divider:SetPoint("RIGHT", parent, "RIGHT", -16, 0)

	return divider
end

-- Shared scroll setup for both access paths - content that exceeds the
-- visible area scrolls instead of spilling past the panel border.
--
-- ROW_INSET bakes a consistent margin (top/left/right) into a "content"
-- frame nested INSIDE the real scroll child, rather than into the scroll
-- child itself - confirmed via debug output that ScrollFrame:SetScrollChild()
-- silently overrides any position anchor given to the child (width changes
-- go through, position changes don't), so the real scroll child must stay
-- flush at (0,0) and full width; only this inner content frame gets offset.
-- Every row anchors to the CONTENT frame's edges at 0, so it automatically
-- gets the margin without needing to know about it.
local ROW_INSET = 12

local function MakeScrollingRowsContainer(parent, topAnchor, bottomOffset)
	local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -12)
	scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, bottomOffset or 16)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
	scrollChild:SetWidth(scrollFrame:GetWidth())
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)
	scrollFrame:SetScript("OnSizeChanged", function(self, width) scrollChild:SetWidth(width) end)

	-- Mouse wheel scrolling isn't automatic for a scroll frame built via
	-- CreateFrame in Lua - UIPanelScrollFrameTemplate only wires it up for
	-- XML-defined instances. Confirmed real bug (Currencies page was tall
	-- enough to need scrolling and couldn't). Step size and clamping match
	-- Blizzard's own ScrollFrameTemplate_OnMouseWheel behavior.
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(scrollChild:GetHeight() - self:GetHeight(), 0)
		local newScroll = self:GetVerticalScroll() - delta * 40
		newScroll = math.max(0, math.min(newScroll, maxScroll))
		self:SetVerticalScroll(newScroll)
	end)

	local content = CreateFrame("Frame", nil, scrollChild)
	content:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", ROW_INSET, -ROW_INSET)
	content:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -ROW_INSET, -ROW_INSET)
	content:SetHeight(1)
	-- Content's height drives the scroll range, but only the real scroll
	-- child's height actually does that - this keeps them in sync (plus
	-- room for the same margin at the bottom) whenever a Populate* function
	-- calls container:SetHeight().
	hooksecurefunc(content, "SetHeight", function(self, height)
		scrollChild:SetHeight(height + ROW_INSET * 2)
	end)

	return content
end

-------------------------------------------------
-- Page 1: General (tracked sections + auto-size)
-------------------------------------------------
function O:PopulateGeneralRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local ROW_H = 62
	local ROW_GAP = 16
	local anchorTo = nil
	local totalHeight = 0

	-- Type keys are shared across both Current and Legacy tiers (same
	-- Daily/Weekly/One-time definitions under each) - toggling one here
	-- affects that type in BOTH tiers at once, rather than doubling this
	-- list with a separate row per tier. Listed in the user's saved order
	-- (GetOrderedTypes) rather than raw catalog order, with up/down buttons
	-- to adjust it right here - build-plan item 8 (module reordering),
	-- modeled after Kaliel's Tracker's "Modules order" list living in its
	-- OWN settings menu, not inline on the tracker window itself.
	local orderedTypes = self:GetOrderedTypes(XComp.Data.Catalog.tiers[1])
	for typeIndex, typeSection in ipairs(orderedTypes) do
		local row = CreateFrame("Frame", nil, container)
		row:SetHeight(ROW_H)
		row:ClearAllPoints()
		if anchorTo then
			row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -ROW_GAP)
			totalHeight = totalHeight + ROW_H + ROW_GAP
		else
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
			totalHeight = totalHeight + ROW_H
		end
		row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		anchorTo = row
		table.insert(container.rows, row)

		local cb = MakeCheckbox(row, 22)
		cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		cb:SetChecked(self:IsTypeEnabled(typeSection.key))
		cb.OnToggle = function(btn)
			self:SetTypeEnabled(typeSection.key, btn:GetChecked() and true or false)
			if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
				XComp.UI:RefreshSections()
			end
		end

		-- Order buttons, top-right of the row.
		local downBtn = CreateFrame("Button", nil, row)
		downBtn:SetSize(20, 20)
		downBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
		local downLbl = downBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		downLbl:SetPoint("CENTER")
		downLbl:SetText("v")
		local canDown = typeIndex < #orderedTypes
		downLbl:SetTextColor(canDown and 1 or 0.35, canDown and 1 or 0.35, canDown and 1 or 0.35, 1)
		downBtn:SetEnabled(canDown)
		downBtn:SetScript("OnClick", function()
			self:MoveType(typeSection.key, 1)
			self:PopulateGeneralRows(container)
			if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
				XComp.UI:RefreshSections()
			end
		end)

		local upBtn = CreateFrame("Button", nil, row)
		upBtn:SetSize(20, 20)
		upBtn:SetPoint("RIGHT", downBtn, "LEFT", -2, 0)
		local upLbl = upBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		upLbl:SetPoint("CENTER")
		upLbl:SetText("^")
		local canUp = typeIndex > 1
		upLbl:SetTextColor(canUp and 1 or 0.35, canUp and 1 or 0.35, canUp and 1 or 0.35, 1)
		upBtn:SetEnabled(canUp)
		upBtn:SetScript("OnClick", function()
			self:MoveType(typeSection.key, -1)
			self:PopulateGeneralRows(container)
			if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
				XComp.UI:RefreshSections()
			end
		end)

		local name = row:CreateFontString(nil, "OVERLAY")
		name:SetFontObject(XComp.TitleFont)
		name:SetPoint("LEFT", cb, "RIGHT", 6, 8)
		name:SetPoint("RIGHT", upBtn, "LEFT", -6, 0)
		name:SetJustifyH("LEFT")
		local nar, nag, nab = XComp.GetAccentColor()
		name:SetTextColor(nar, nag, nab, 1)
		name:SetText(typeSection.label)

		local desc = row:CreateFontString(nil, "OVERLAY")
		desc:SetFontObject(XComp.BodyFont)
		desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
		desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		desc:SetJustifyH("LEFT")
		desc:SetText(typeSection.description or "")
	end

	-- Auto-size fallback toggle (build-plan item 5's safety requirement) -
	-- appended after the type rows as a general setting, not tied to any
	-- one section.
	local sizeRow = CreateFrame("Frame", nil, container)
	sizeRow:SetHeight(ROW_H)
	sizeRow:ClearAllPoints()
	if anchorTo then
		sizeRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -ROW_GAP)
	else
		sizeRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	end
	sizeRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, sizeRow)
	totalHeight = totalHeight + ROW_H + ROW_GAP

	local sizeCB = MakeCheckbox(sizeRow, 22)
	sizeCB:SetPoint("TOPLEFT", sizeRow, "TOPLEFT", 0, 0)
	sizeCB:SetChecked(not (XComp_DB.settings and XComp_DB.settings.autoSize == false))
	sizeCB.OnToggle = function(btn)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.autoSize = btn:GetChecked() and true or false
		if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
			XComp.UI:RefreshSections()
		end
	end

	local sizeName = sizeRow:CreateFontString(nil, "OVERLAY")
	sizeName:SetFontObject(XComp.TitleFont)
	sizeName:SetPoint("LEFT", sizeCB, "RIGHT", 6, 8)
	local szr, szg, szb = XComp.GetAccentColor()
	sizeName:SetTextColor(szr, szg, szb, 1)
	sizeName:SetText("Auto-size window")

	local sizeDesc = sizeRow:CreateFontString(nil, "OVERLAY")
	sizeDesc:SetFontObject(XComp.BodyFont)
	sizeDesc:SetPoint("TOPLEFT", sizeName, "BOTTOMLEFT", 0, -4)
	sizeDesc:SetPoint("RIGHT", sizeRow, "RIGHT", 0, 0)
	sizeDesc:SetJustifyH("LEFT")
	sizeDesc:SetText("Automatically resize the tracker to fit visible content. Turn off to keep a fixed size (e.g. if resizing ever misbehaves).")
	-- Real bug fixed 2026-09-29: anchorTo never got reassigned to sizeRow
	-- after building it, so the Legacy row below ended up anchored to the
	-- same point as sizeRow itself - both landed on top of one another,
	-- reading as a garbled overlapping mess (caught via screenshot).
	anchorTo = sizeRow

	-- Legacy tier toggle (2026-09-29) - Legacy isn't a "type" like Daily/
	-- Weekly/One-time above (those are shared across both tiers), it's a
	-- whole separate TIER, so it gets its own row here rather than joining
	-- that loop.
	local legacyRow = CreateFrame("Frame", nil, container)
	legacyRow:SetHeight(ROW_H)
	legacyRow:ClearAllPoints()
	if anchorTo then
		legacyRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -ROW_GAP)
	else
		legacyRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	end
	legacyRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, legacyRow)
	totalHeight = totalHeight + ROW_H + ROW_GAP
	anchorTo = legacyRow

	local legacyCB = MakeCheckbox(legacyRow, 22)
	legacyCB:SetPoint("TOPLEFT", legacyRow, "TOPLEFT", 0, 0)
	legacyCB:SetChecked(self:IsLegacyEnabled())

	local legacyName = legacyRow:CreateFontString(nil, "OVERLAY")
	legacyName:SetFontObject(XComp.TitleFont)
	legacyName:SetPoint("LEFT", legacyCB, "RIGHT", 6, 8)
	legacyName:SetPoint("RIGHT", legacyRow, "RIGHT", 0, 0)
	legacyName:SetJustifyH("LEFT")
	local lar, lag, lab = XComp.GetAccentColor()
	legacyName:SetTextColor(lar, lag, lab, 1)
	legacyName:SetText("Legacy")

	local legacyDesc = legacyRow:CreateFontString(nil, "OVERLAY")
	legacyDesc:SetFontObject(XComp.BodyFont)
	legacyDesc:SetPoint("TOPLEFT", legacyName, "BOTTOMLEFT", 0, -4)
	legacyDesc:SetPoint("RIGHT", legacyRow, "RIGHT", 0, 0)
	legacyDesc:SetJustifyH("LEFT")
	legacyDesc:SetText("Old-expansion catch-up content. Nothing shows until you check an expansion below - also counts toward the floating icon once checked.")

	-- Expansion/zone picker - a real dropdown BUTTON, closed by default with
	-- a live selected-count, NOT an inline checklist sitting jumbled on top
	-- of the row below it (that was the actual layout bug, on top of the
	-- anchorTo bug above - confirmed via mockup + screenshot 2026-09-29).
	-- Expand/collapse state is per-session only (not saved), since it's a
	-- pure display convenience, not a real setting.
	local zoneNames = XComp.Data:GetLegacyZoneNames()
	local selectedCount = 0
	for _, zoneName in ipairs(zoneNames) do
		if self:IsLegacyZoneEnabled(zoneName) then selectedCount = selectedCount + 1 end
	end

	local dropdownBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
	dropdownBtn:SetHeight(26)
	dropdownBtn:SetWidth(190)
	dropdownBtn:SetPoint("TOPLEFT", legacyRow, "BOTTOMLEFT", 28, -8)
	dropdownBtn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 2,
	})
	dropdownBtn:SetBackdropColor(0.08, 0.07, 0.12, 1)
	dropdownBtn:SetBackdropBorderColor(XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3], 1)
	table.insert(container.rows, dropdownBtn)
	anchorTo = dropdownBtn
	totalHeight = totalHeight + 26 + 8 + ROW_GAP

	local dropdownLabel = dropdownBtn:CreateFontString(nil, "OVERLAY")
	dropdownLabel:SetFontObject(XComp.BodyFont)
	dropdownLabel:SetPoint("LEFT", dropdownBtn, "LEFT", 10, 0)
	local dar, dag, dab = XComp.GetAccentColor()
	dropdownLabel:SetTextColor(dar, dag, dab, 1)
	local expanded = self.legacyZonesExpanded
	dropdownLabel:SetText(string.format("Select Expansions (%d selected) %s", selectedCount, expanded and "\226\150\180" or "\226\150\190"))

	dropdownBtn:SetScript("OnClick", function()
		self.legacyZonesExpanded = not self.legacyZonesExpanded
		self:PopulateGeneralRows(container)
	end)
	dropdownBtn:SetShown(self:IsLegacyEnabled())

	-- Expanded panel - a clean bordered grid, only built at all while open,
	-- so a closed dropdown costs nothing and can never overlap anything.
	local zoneGrid
	if expanded and self:IsLegacyEnabled() then
		local ZONE_GRID_COLS = 2
		local ZONE_COL_WIDTH = 190
		local zoneRowCount = math.max(math.ceil(#zoneNames / ZONE_GRID_COLS), 1)
		local zoneGridHeight = zoneRowCount * 22 + 16

		zoneGrid = CreateFrame("Frame", nil, container, "BackdropTemplate")
		zoneGrid:SetHeight(zoneGridHeight)
		zoneGrid:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -8)
		zoneGrid:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		zoneGrid:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 2,
		})
		zoneGrid:SetBackdropColor(0.08, 0.07, 0.12, 1)
		zoneGrid:SetBackdropBorderColor(XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3], 1)
		table.insert(container.rows, zoneGrid)
		anchorTo = zoneGrid
		totalHeight = totalHeight + zoneGridHeight + ROW_GAP

		if #zoneNames == 0 then
			local noneText = zoneGrid:CreateFontString(nil, "OVERLAY")
			noneText:SetFontObject(XComp.BodyFont)
			noneText:SetPoint("TOPLEFT", zoneGrid, "TOPLEFT", 10, -8)
			noneText:SetText("No Legacy content in the catalog yet.")
		end

		for i, zoneName in ipairs(zoneNames) do
			local col = (i - 1) % ZONE_GRID_COLS
			local rowIdx = math.floor((i - 1) / ZONE_GRID_COLS)
			local zcb = MakeCheckbox(zoneGrid, 16)
			zcb:SetPoint("TOPLEFT", zoneGrid, "TOPLEFT", 10 + col * ZONE_COL_WIDTH, -8 - rowIdx * 22)
			zcb:SetChecked(self:IsLegacyZoneEnabled(zoneName))
			zcb.OnToggle = function(btn)
				self:SetLegacyZoneEnabled(zoneName, btn:GetChecked() and true or false)
				self:PopulateGeneralRows(container)
				if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
					XComp.UI:RefreshSections()
				end
			end
			local zlabel = zoneGrid:CreateFontString(nil, "OVERLAY")
			zlabel:SetFontObject(XComp.BodyFont)
			zlabel:SetPoint("LEFT", zcb, "RIGHT", 4, 0)
			zlabel:SetJustifyH("LEFT")
			zlabel:SetText(zoneName)
		end
	end

	-- Full rebuild on toggle (not just SetShown) so the container's height
	-- recalculates too - otherwise hiding the dropdown/grid leaves a dead
	-- gap where it used to be instead of the page actually shrinking.
	legacyCB.OnToggle = function(btn)
		self:SetLegacyEnabled(btn:GetChecked() and true or false)
		self:PopulateGeneralRows(container)
		if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
			XComp.UI:RefreshSections()
		end
	end

	container:SetHeight(math.max(totalHeight, 1))
end

-------------------------------------------------
-- Page 2: Appearance (frameless mode, background transparency, accent
-- color) - a genuinely separate page from General, per explicit user
-- request, not just a visual section within one long list.
-------------------------------------------------
local sliderNameCounter = 0
local dropdownNameCounter = 0

function O:PopulateAppearanceRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local APPEAR_ROW_H = 56
	local APPEAR_ROW_GAP = 18
	local appearAnchor = nil
	local totalHeight = 0

	local function NextAppearRow(height)
		local row = CreateFrame("Frame", nil, container)
		row:SetHeight(height)
		row:ClearAllPoints()
		if appearAnchor then
			row:SetPoint("TOPLEFT", appearAnchor, "BOTTOMLEFT", 0, -APPEAR_ROW_GAP)
			totalHeight = totalHeight + height + APPEAR_ROW_GAP
		else
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
			totalHeight = totalHeight + height
		end
		row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		appearAnchor = row
		table.insert(container.rows, row)
		return row
	end

	-- Frameless mode: secondary opt-in, default remains the branded look.
	local framelessRow = NextAppearRow(APPEAR_ROW_H)
	local framelessCB = MakeCheckbox(framelessRow, 22)
	framelessCB:SetPoint("TOPLEFT", framelessRow, "TOPLEFT", 0, 0)
	framelessCB:SetChecked(XComp_DB.settings and XComp_DB.settings.frameless or false)
	framelessCB.OnToggle = function(btn)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.frameless = btn:GetChecked() and true or false
		if XComp.UI then XComp.UI:ApplyTheme() end
	end
	local framelessName = framelessRow:CreateFontString(nil, "OVERLAY")
	framelessName:SetFontObject(XComp.TitleFont)
	framelessName:SetPoint("LEFT", framelessCB, "RIGHT", 6, 8)
	local flr, flg, flb = XComp.GetAccentColor()
	framelessName:SetTextColor(flr, flg, flb, 1)
	framelessName:SetText("Frameless mode")
	local framelessDesc = framelessRow:CreateFontString(nil, "OVERLAY")
	framelessDesc:SetFontObject(XComp.BodyFont)
	framelessDesc:SetPoint("TOPLEFT", framelessName, "BOTTOMLEFT", 0, -4)
	framelessDesc:SetPoint("RIGHT", framelessRow, "RIGHT", 0, 0)
	framelessDesc:SetJustifyH("LEFT")
	framelessDesc:SetText("Minimal HUD style - strips the background/border entirely.")

	-- Great Vault/currencies side strip toggle (2026-08-15, explicit
	-- request) - on by default, off for players who only want quest
	-- content and consider vault/currency info "added information" they
	-- don't need cluttering the window.
	local stripRow = NextAppearRow(APPEAR_ROW_H)
	local stripCB = MakeCheckbox(stripRow, 22)
	stripCB:SetPoint("TOPLEFT", stripRow, "TOPLEFT", 0, 0)
	stripCB:SetChecked(not (XComp_DB.settings and XComp_DB.settings.showSideStrip == false))
	stripCB.OnToggle = function(btn)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.showSideStrip = btn:GetChecked() and true or false
		if XComp.UI then XComp.UI:RefreshSideStrip() end
	end
	local stripName = stripRow:CreateFontString(nil, "OVERLAY")
	stripName:SetFontObject(XComp.TitleFont)
	stripName:SetPoint("LEFT", stripCB, "RIGHT", 6, 8)
	local slr, slg, slb = XComp.GetAccentColor()
	stripName:SetTextColor(slr, slg, slb, 1)
	stripName:SetText("Show Great Vault / currencies strip")
	local stripDesc = stripRow:CreateFontString(nil, "OVERLAY")
	stripDesc:SetFontObject(XComp.BodyFont)
	stripDesc:SetPoint("TOPLEFT", stripName, "BOTTOMLEFT", 0, -4)
	stripDesc:SetPoint("RIGHT", stripRow, "RIGHT", 0, 0)
	stripDesc:SetJustifyH("LEFT")
	stripDesc:SetText("A small icon panel outside the tracker's right edge for Great Vault progress and tracked currencies. Turn off if you only want quest content.")

	-- Floating icon toggle + reposition - the icon itself has no visible
	-- chrome to right-click, so if it ever ends up dragged off-screen (or a
	-- resolution/UI-scale change moves it there) this is the only way back;
	-- same reason every other floating icon in the family needs a menu
	-- entry, not just a drag handle.
	local iconRow = NextAppearRow(APPEAR_ROW_H)
	local iconCB = MakeCheckbox(iconRow, 22)
	iconCB:SetPoint("TOPLEFT", iconRow, "TOPLEFT", 0, 0)
	iconCB:SetChecked(not (XComp_DB.settings and XComp_DB.settings.showFloatingIcon == false))
	iconCB.OnToggle = function(btn)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.showFloatingIcon = btn:GetChecked() and true or false
		if XComp.RefreshFloatingIcon then XComp.RefreshFloatingIcon() end
	end
	local iconName = iconRow:CreateFontString(nil, "OVERLAY")
	iconName:SetFontObject(XComp.TitleFont)
	iconName:SetPoint("LEFT", iconCB, "RIGHT", 6, 8)
	local ilr, ilg, ilb = XComp.GetAccentColor()
	iconName:SetTextColor(ilr, ilg, ilb, 1)
	iconName:SetText("Show floating icon")
	local iconDesc = iconRow:CreateFontString(nil, "OVERLAY")
	iconDesc:SetFontObject(XComp.BodyFont)
	iconDesc:SetPoint("TOPLEFT", iconName, "BOTTOMLEFT", 0, -4)
	iconDesc:SetPoint("RIGHT", iconRow, "RIGHT", -140, 0)
	iconDesc:SetJustifyH("LEFT")
	iconDesc:SetText("A draggable on-screen icon that shows up whenever daily/weekly quests are still outstanding, separate from the minimap button.")
	local iconResetBtn = MakeFlatButton(iconRow, false, 130, "Reset Icon Position", function()
		if XComp.ResetFloatingIconPosition then XComp.ResetFloatingIconPosition() end
	end)
	iconResetBtn:ClearAllPoints()
	iconResetBtn:SetPoint("TOPRIGHT", iconRow, "TOPRIGHT", 0, 0)

	-- Floating icon size slider - live, not a "set and reload/reset to see
	-- it" control (explicit correction: fine-tuning a hardcoded size back
	-- and forth wasn't good enough). Same per-container instance-caching
	-- pattern as the transparency/scale sliders below, for the same reason.
	local iconSizeRow = NextAppearRow(50)
	local iconSizeSlider = container.iconSizeSlider
	if not iconSizeSlider then
		sliderNameCounter = sliderNameCounter + 1
		local uniqueName = "XalsCompendiumFloatingIconSizeSlider" .. sliderNameCounter
		iconSizeSlider = CreateFrame("Slider", uniqueName, iconSizeRow, "OptionsSliderTemplate")
		_G[uniqueName.."Low"]:SetText("32")
		_G[uniqueName.."High"]:SetText("128")
		container.iconSizeSlider = iconSizeSlider
	else
		iconSizeSlider:SetParent(iconSizeRow)
	end
	iconSizeSlider:ClearAllPoints()
	iconSizeSlider:SetPoint("TOPLEFT", iconSizeRow, "TOPLEFT", 4, -14)
	iconSizeSlider:SetWidth(340)
	iconSizeSlider:SetMinMaxValues(32, 128)
	iconSizeSlider:SetValueStep(2)
	iconSizeSlider:SetObeyStepOnDrag(true)
	local iconSizeStart = (XComp_DB.settings and XComp_DB.settings.floatingIconSize) or 52
	iconSizeSlider:SetValue(iconSizeStart)
	_G[iconSizeSlider:GetName().."Text"]:SetText("Floating Icon Size: " .. iconSizeStart)
	iconSizeSlider:Show()
	iconSizeSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value + 0.5)
		_G[self:GetName().."Text"]:SetText("Floating Icon Size: " .. value)
		if XComp.SetFloatingIconSize then XComp.SetFloatingIconSize(value) end
	end)

	-- Background transparency slider. Named explicitly (not nil) because
	-- OptionsSliderTemplate's Low/High/Text sub-widgets are resolved via
	-- _G[name.."Low"] etc., which requires the frame to actually have a
	-- global name. Cached ON the container itself (`container.bgAlphaSlider`)
	-- so each of the two Appearance pages (native + standalone) gets and
	-- keeps its own persistent instance, rather than one shared slider
	-- getting "stolen" between them (real bug found via user screenshot).
	local alphaRow = NextAppearRow(50)
	local alphaSlider = container.bgAlphaSlider
	if not alphaSlider then
		sliderNameCounter = sliderNameCounter + 1
		local uniqueName = "XalsCompendiumBgAlphaSlider" .. sliderNameCounter
		alphaSlider = CreateFrame("Slider", uniqueName, alphaRow, "OptionsSliderTemplate")
		_G[uniqueName.."Low"]:SetText("0%")
		_G[uniqueName.."High"]:SetText("100%")
		container.bgAlphaSlider = alphaSlider
	else
		alphaSlider:SetParent(alphaRow)
	end
	alphaSlider:ClearAllPoints()
	alphaSlider:SetPoint("TOPLEFT", alphaRow, "TOPLEFT", 4, -14)
	alphaSlider:SetWidth(340)
	alphaSlider:SetMinMaxValues(0, 1)
	alphaSlider:SetValueStep(0.05)
	alphaSlider:SetObeyStepOnDrag(true)
	local alphaStart = XComp_DB.settings and XComp_DB.settings.bgAlpha or 0.95
	alphaSlider:SetValue(alphaStart)
	_G[alphaSlider:GetName().."Text"]:SetText(string.format("Background Transparency: %d%%", math.floor(alphaStart * 100 + 0.5)))
	alphaSlider:Show()
	alphaSlider:SetScript("OnValueChanged", function(self, value)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.bgAlpha = value
		_G[self:GetName().."Text"]:SetText(string.format("Background Transparency: %d%%", math.floor(value * 100 + 0.5)))
		if XComp.UI then XComp.UI:ApplyTheme() end
	end)

	-- Window scale slider - uniformly zooms the ENTIRE main tracker window
	-- (text, icons, spacing) via native Frame:SetScale, distinct from the
	-- corner-drag resize (which only changes width/height). Same
	-- per-container instance-caching pattern as the transparency slider,
	-- for the same reason (avoid the "stolen slider" bug across 4 possible
	-- containers).
	local scaleRow = NextAppearRow(50)
	local scaleSlider = container.scaleSlider
	if not scaleSlider then
		sliderNameCounter = sliderNameCounter + 1
		local uniqueName = "XalsCompendiumScaleSlider" .. sliderNameCounter
		scaleSlider = CreateFrame("Slider", uniqueName, scaleRow, "OptionsSliderTemplate")
		_G[uniqueName.."Low"]:SetText("50%")
		_G[uniqueName.."High"]:SetText("200%")
		container.scaleSlider = scaleSlider
	else
		scaleSlider:SetParent(scaleRow)
	end
	scaleSlider:ClearAllPoints()
	scaleSlider:SetPoint("TOPLEFT", scaleRow, "TOPLEFT", 4, -14)
	scaleSlider:SetWidth(340)
	scaleSlider:SetMinMaxValues(0.5, 2)
	scaleSlider:SetValueStep(0.05)
	scaleSlider:SetObeyStepOnDrag(true)
	local scaleStart = (XComp_DB.settings and XComp_DB.settings.scale) or 1
	scaleSlider:SetValue(scaleStart)
	_G[scaleSlider:GetName().."Text"]:SetText(string.format("Window Scale: %d%%", math.floor(scaleStart * 100 + 0.5)))
	scaleSlider:Show()
	scaleSlider:SetScript("OnValueChanged", function(self, value)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.scale = value
		_G[self:GetName().."Text"]:SetText(string.format("Window Scale: %d%%", math.floor(value * 100 + 0.5)))
		if XComp.UI then XComp.UI:ApplyTheme() end
	end)

	-- Idle opacity slider - how transparent the main tracker is while the
	-- mouse ISN'T over it (it always snaps to full opacity on hover). Default
	-- 0% (fully invisible until moused over), player-adjustable rather than
	-- locked - explicit request 2026-08-12. Same per-container
	-- instance-caching pattern as the other two sliders above.
	local idleRow = NextAppearRow(50)
	local idleSlider = container.idleAlphaSlider
	if not idleSlider then
		sliderNameCounter = sliderNameCounter + 1
		local uniqueName = "XalsCompendiumIdleAlphaSlider" .. sliderNameCounter
		idleSlider = CreateFrame("Slider", uniqueName, idleRow, "OptionsSliderTemplate")
		_G[uniqueName.."Low"]:SetText("0%")
		_G[uniqueName.."High"]:SetText("100%")
		container.idleAlphaSlider = idleSlider
	else
		idleSlider:SetParent(idleRow)
	end
	idleSlider:ClearAllPoints()
	idleSlider:SetPoint("TOPLEFT", idleRow, "TOPLEFT", 4, -14)
	idleSlider:SetWidth(340)
	idleSlider:SetMinMaxValues(0, 1)
	idleSlider:SetValueStep(0.05)
	idleSlider:SetObeyStepOnDrag(true)
	local idleStart = (XComp_DB.settings and XComp_DB.settings.idleAlpha) or 0
	idleSlider:SetValue(idleStart)
	_G[idleSlider:GetName().."Text"]:SetText(string.format("Idle Opacity (not moused over): %d%%", math.floor(idleStart * 100 + 0.5)))
	idleSlider:Show()
	idleSlider:SetScript("OnValueChanged", function(self, value)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.idleAlpha = value
		_G[self:GetName().."Text"]:SetText(string.format("Idle Opacity (not moused over): %d%%", math.floor(value * 100 + 0.5)))
		if XComp.UI then XComp.UI:ApplyIdleAlpha() end
	end)

	container:SetHeight(math.max(totalHeight, 1))
end

-------------------------------------------------
-- Page 4: Currencies (build-plan item 14) - a checklist populated LIVE from
-- the player's own Currency tab (C_CurrencyInfo.GetCurrencyListSize/
-- GetCurrencyListInfo, verified against Warcraft Wiki), so real currency
-- names show up instead of asking the player to type raw currency IDs.
-- Grouped under the SAME expansion/category headers the game's own
-- Currency tab uses (the header rows already present in the list, e.g.
-- "Midnight") - a divider line under each header, then that group's
-- currencies laid out in a column grid instead of one long vertical list.
-------------------------------------------------
local CURRENCY_GRID_COLS = 4
local CURRENCY_COL_WIDTH = 92

-- Currency Goals (build-plan item 14 extension) - 3 fixed slots living at
-- the bottom of THIS SAME page (not a separate tab, per explicit user
-- correction), each a dropdown listing only the currencies checked above
-- (not the full game list) plus a target amount. Toast fires via
-- CURRENCY_DISPLAY_UPDATE in Core.lua once the live quantity reaches the
-- goal. Hardcoded to 3 slots - can add a 4th dropdown later if anyone asks.
local CURRENCY_GOAL_SLOTS = 3

local function GetTrackedCurrencyOptions()
	local tracked = XComp_DB.settings and XComp_DB.settings.trackedCurrencyIDs
	local options = {}
	if not tracked then return options end
	for id, isTracked in pairs(tracked) do
		if isTracked then
			local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
			if info then
				table.insert(options, { id = id, name = info.name })
			end
		end
	end
	table.sort(options, function(a, b) return a.name < b.name end)
	return options
end

function O:PopulateCurrencyChecklistRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	XComp_DB.settings = XComp_DB.settings or {}
	XComp_DB.settings.trackedCurrencyIDs = XComp_DB.settings.trackedCurrencyIDs or {}
	local tracked = XComp_DB.settings.trackedCurrencyIDs

	local introRow = CreateFrame("Frame", nil, container)
	introRow:SetHeight(40)
	introRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	introRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, introRow)
	local introText = introRow:CreateFontString(nil, "OVERLAY")
	introText:SetFontObject(XComp.BodyFont)
	introText:SetPoint("TOPLEFT", introRow, "TOPLEFT", 0, 0)
	introText:SetPoint("RIGHT", introRow, "RIGHT", 0, 0)
	introText:SetJustifyH("LEFT")
	introText:SetText("Pick which currencies show up under the tracker's Currencies section - listing everything currently in your own Currency tab (Character panel), grouped the same way.")
	XComp.ApplyTextShadow(introText)

	local anchorTo = introRow
	local totalHeight = 40

	local size = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0
	local shown = 0

	-- Pre-pass: merge every header BEFORE "Legacy" into one group (labeled
	-- with the first header's name, e.g. "Midnight") - the game's own list
	-- splits current-expansion currencies across several parallel headers
	-- (Season 1, Dungeon and Raid, Miscellaneous, Player vs Player, etc.),
	-- but the user wants those combined into a single current-expansion
	-- section. "Legacy" and anything after it stays broken out per header
	-- (per-expansion), same as the game's own list.
	local groups = {}
	local currentMerged = nil
	local inLegacy = false
	for idx = 1, size do
		local info = C_CurrencyInfo.GetCurrencyListInfo(idx)
		if info then
			if info.isHeader then
				if info.name == "Legacy" then
					inLegacy = true
				end
				if inLegacy then
					table.insert(groups, { label = info.name, items = {} })
				end
				-- Pre-Legacy headers don't start a new group - their items
				-- fall through to currentMerged below.
			elseif inLegacy then
				local g = groups[#groups]
				if g then table.insert(g.items, info) end
			else
				if not currentMerged then
					currentMerged = { label = info.name and "" or "", items = {} }
				end
				currentMerged.items[#currentMerged.items + 1] = info
			end
		end
	end
	if currentMerged and #currentMerged.items > 0 then
		-- Label the merged current-expansion group with the very first
		-- header name seen (e.g. "Midnight").
		local firstHeaderInfo
		for idx = 1, size do
			local info = C_CurrencyInfo.GetCurrencyListInfo(idx)
			if info and info.isHeader then
				firstHeaderInfo = info
				break
			end
		end
		currentMerged.label = firstHeaderInfo and firstHeaderInfo.name or "Current"
		table.insert(groups, 1, currentMerged)
	end

	for _, group in ipairs(groups) do
		if #group.items > 0 then
			-- Group header + divider line.
			local headerRow = CreateFrame("Frame", nil, container)
			headerRow:SetHeight(24)
			headerRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -14)
			headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
			table.insert(container.rows, headerRow)
			anchorTo = headerRow
			totalHeight = totalHeight + 24 + 14

			local headerText = headerRow:CreateFontString(nil, "OVERLAY")
			headerText:SetFontObject(XComp.TitleFont)
			headerText:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
			local ar, ag, ab = XComp.GetAccentColor()
			headerText:SetTextColor(ar, ag, ab, 1)
			headerText:SetText(group.label)

			local divider = headerRow:CreateTexture(nil, "ARTWORK")
			divider:SetHeight(2)
			divider:SetColorTexture(ar, ag, ab, 0.6)
			divider:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -4)
			divider:SetPoint("RIGHT", headerRow, "RIGHT", 0, 0)

			-- Grid of checkboxes for this group's currencies.
			local rows = math.ceil(#group.items / CURRENCY_GRID_COLS)
			local gridRow = CreateFrame("Frame", nil, container)
			gridRow:SetHeight(rows * 30)
			gridRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -8)
			gridRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
			table.insert(container.rows, gridRow)
			anchorTo = gridRow
			totalHeight = totalHeight + rows * 30 + 8

			for gi, entry in ipairs(group.items) do
				shown = shown + 1
				local col = (gi - 1) % CURRENCY_GRID_COLS
				local gridRowIdx = math.floor((gi - 1) / CURRENCY_GRID_COLS)

				local cell = CreateFrame("Frame", nil, gridRow)
				cell:SetSize(CURRENCY_COL_WIDTH, 26)
				cell:SetPoint("TOPLEFT", gridRow, "TOPLEFT", col * CURRENCY_COL_WIDTH, -gridRowIdx * 30)

				local currencyID = entry.currencyID
				local cb = MakeCheckbox(cell, 18)
				cb:SetPoint("LEFT", cell, "LEFT", 0, 0)
				cb:SetChecked(tracked[currencyID] == true)
				cb.OnToggle = function(btn)
					tracked[currencyID] = btn:GetChecked() and true or nil
					if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
						XComp.UI:RefreshSections()
					end
					-- Full re-populate, not just a toggle - the Goals sub-tab
					-- (same shared container, repopulated fresh every time
					-- that pill is clicked - see BuildCurrenciesSubTabs)
					-- picks up this change on its own the next time it's
					-- shown, so only the checklist itself needs a refresh.
					self:PopulateCurrencyChecklistRows(container)
				end

				local name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				name:SetPoint("LEFT", cb, "RIGHT", 4, 0)
				name:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
				name:SetJustifyH("LEFT")
				name:SetWordWrap(false)
				name:SetText(entry.name)
			end
		end
	end

	if shown == 0 then
		local emptyRow = CreateFrame("Frame", nil, container)
		emptyRow:SetHeight(28)
		emptyRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
		emptyRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		table.insert(container.rows, emptyRow)
		totalHeight = totalHeight + 28 + 6

		local emptyText = emptyRow:CreateFontString(nil, "OVERLAY")
		emptyText:SetFontObject(XComp.BodyFont)
		emptyText:SetPoint("TOPLEFT", emptyRow, "TOPLEFT", 0, 0)
		emptyText:SetText("No currencies found in your Currency tab yet.")
	end

	container:SetHeight(math.max(totalHeight, 1))
end

-------------------------------------------------
-- Currency Goals - real sub-TAB of the Currencies page (per explicit user
-- correction - not appended content on the same scrolling list). 3 fixed
-- slots, each a dropdown listing only currencies checked on the checklist
-- sub-tab. Toast fires via CURRENCY_DISPLAY_UPDATE in Core.lua.
-------------------------------------------------
function O:PopulateCurrencyGoalsRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	XComp_DB.settings = XComp_DB.settings or {}

	local goalsHintRow = CreateFrame("Frame", nil, container)
	goalsHintRow:SetHeight(40)
	goalsHintRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	goalsHintRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, goalsHintRow)

	local goalsHintText = goalsHintRow:CreateFontString(nil, "OVERLAY")
	goalsHintText:SetFontObject(XComp.BodyFont)
	goalsHintText:SetPoint("TOPLEFT", goalsHintRow, "TOPLEFT", 0, 0)
	goalsHintText:SetPoint("RIGHT", goalsHintRow, "RIGHT", 0, 0)
	goalsHintText:SetJustifyH("LEFT")
	goalsHintText:SetText("Pick up to 3 checked currencies (from the Currencies sub-tab) and a target amount - you'll get a popup the moment you reach it.")

	local anchorTo = goalsHintRow
	local totalHeight = 40

	XComp_DB.settings.currencyGoalSlots = XComp_DB.settings.currencyGoalSlots or {}
	local slots = XComp_DB.settings.currencyGoalSlots
	local goalOptions = GetTrackedCurrencyOptions()
	container.goalDropdowns = container.goalDropdowns or {}

	for slotIndex = 1, CURRENCY_GOAL_SLOTS do
		slots[slotIndex] = slots[slotIndex] or {}
		local slot = slots[slotIndex]

		local slotRow = CreateFrame("Frame", nil, container)
		slotRow:SetHeight(56)
		slotRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -16)
		slotRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		table.insert(container.rows, slotRow)
		anchorTo = slotRow
		totalHeight = totalHeight + 56 + 16

		local slotLabel = slotRow:CreateFontString(nil, "OVERLAY")
		slotLabel:SetFontObject(XComp.BodyFont)
		slotLabel:SetPoint("TOPLEFT", slotRow, "TOPLEFT", 0, 0)
		local sar, sag, sab = XComp.GetAccentColor()
		slotLabel:SetTextColor(sar, sag, sab, 1)
		slotLabel:SetText("Goal " .. slotIndex)

		-- Dropdown, cached on the container like the Font/Outline dropdowns
		-- (needs a real global name; Populate* can run more than once).
		local dropdown = container.goalDropdowns[slotIndex]
		if not dropdown then
			dropdownNameCounter = dropdownNameCounter + 1
			dropdown = CreateFrame("Frame", "XalsCompendiumGoalDropdown" .. dropdownNameCounter, slotRow, "UIDropDownMenuTemplate")
			container.goalDropdowns[slotIndex] = dropdown
		else
			dropdown:SetParent(slotRow)
		end
		dropdown:ClearAllPoints()
		dropdown:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", -16, -4)
		UIDropDownMenu_SetWidth(dropdown, 200)

		local function RefreshDropdownText()
			if slot.currencyID then
				local info = C_CurrencyInfo.GetCurrencyInfo(slot.currencyID)
				UIDropDownMenu_SetText(dropdown, info and info.name or "(currency no longer tracked)")
			else
				UIDropDownMenu_SetText(dropdown, "None selected")
			end
		end
		UIDropDownMenu_Initialize(dropdown, function(self, level)
			local info = UIDropDownMenu_CreateInfo()
			info.text = "None selected"
			info.checked = (slot.currencyID == nil)
			info.func = function()
				slot.currencyID = nil
				RefreshDropdownText()
			end
			UIDropDownMenu_AddButton(info, level)

			for _, opt in ipairs(goalOptions) do
				local optInfo = UIDropDownMenu_CreateInfo()
				optInfo.text = opt.name
				optInfo.checked = (slot.currencyID == opt.id)
				optInfo.func = function()
					slot.currencyID = opt.id
					XComp_DB.currencyGoalsReached = XComp_DB.currencyGoalsReached or {}
					XComp_DB.currencyGoalsReached[opt.id] = nil
					RefreshDropdownText()
				end
				UIDropDownMenu_AddButton(optInfo, level)
			end
		end)
		RefreshDropdownText()
		dropdown:Show()

		local goalInput = CreateFrame("EditBox", nil, slotRow, "InputBoxTemplate")
		goalInput:SetSize(100, 20)
		goalInput:SetPoint("LEFT", dropdown, "RIGHT", 24, 3)
		goalInput:SetAutoFocus(false)
		goalInput:SetNumeric(true)
		goalInput:SetText(slot.goal and tostring(slot.goal) or "")
		goalInput:SetScript("OnEnterPressed", function(self)
			local val = tonumber(self:GetText())
			slot.goal = (val and val > 0) and val or nil
			if slot.currencyID then
				XComp_DB.currencyGoalsReached = XComp_DB.currencyGoalsReached or {}
				XComp_DB.currencyGoalsReached[slot.currencyID] = nil
			end
			self:ClearFocus()
		end)
		goalInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

		local goalHint = slotRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		goalHint:SetPoint("LEFT", goalInput, "RIGHT", 6, 0)
		goalHint:SetText("target amount")
	end

	container:SetHeight(math.max(totalHeight, 1))
end

-------------------------------------------------
-- Page 5: Diagnostics (build-plan item 12) - a "Run Diagnostics" button
-- that opens the copyable report window (UI.lua's ShowDiagnostics). Kept
-- to a button + explanation here rather than embedding the report's own
-- scrollable EditBox inside this already-scrolling page - nesting one
-- scroll region inside another is exactly the kind of fragile setup that
-- caused this session's scroll bugs in the first place.
-------------------------------------------------
function O:PopulateDiagnosticsRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local introRow = CreateFrame("Frame", nil, container)
	introRow:SetHeight(70)
	introRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	introRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, introRow)

	local introText = introRow:CreateFontString(nil, "OVERLAY")
	introText:SetFontObject(XComp.BodyFont)
	introText:SetPoint("TOPLEFT", introRow, "TOPLEFT", 0, 0)
	introText:SetPoint("RIGHT", introRow, "RIGHT", 0, 0)
	introText:SetJustifyH("LEFT")
	introText:SetText("Scans the whole catalog for items with no quest ID set, and (for anything currently in your quest log) checks whether the catalog's Daily/Weekly classification matches what the game actually reports. Produces a copyable report with a Wowhead link per item - useful for reporting bad catalog data.")
	XComp.ApplyTextShadow(introText)

	local btnRow = CreateFrame("Frame", nil, container)
	btnRow:SetHeight(30)
	btnRow:SetPoint("TOPLEFT", introRow, "BOTTOMLEFT", 0, -14)
	btnRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, btnRow)

	local runBtn = MakeFlatButton(btnRow, false, 160, "Run Diagnostics", function() XComp.UI:ShowDiagnostics() end)
	runBtn:ClearAllPoints()
	runBtn:SetPoint("TOPLEFT", btnRow, "TOPLEFT", 0, 0)

	-- Export Detected Quests - dev-only, see XComp.IsDevMode (Core.lua).
	-- Not created at all for a regular player - there is nothing to click,
	-- nothing to discover, when dev mode is off (the default for everyone).
	if XComp.IsDevMode() then
		local exportBtn = MakeFlatButton(btnRow, runBtn, 190, "Export Detected Quests", function() XComp.UI:ShowUntrackedExport() end)
	end

	container:SetHeight(70 + 14 + 30)
end

-------------------------------------------------
-- Page 6: Backup (build-plan item 16) - a safeguard against losing streaks,
-- manual overrides, or settings. One automatic snapshot per day (Core.lua's
-- ADDON_LOADED handler -> Data.lua's AutoBackupIfNeeded) plus a manual
-- "Backup Now" button here; up to 5 kept, each restorable or deletable.
-- Restoring/deleting are the two genuinely destructive actions this addon
-- has, so both get a real confirmation popup rather than firing on the
-- first click.
-------------------------------------------------
StaticPopupDialogs["XCOMP_RESTORE_BACKUP"] = {
	text = "Restore this backup? Your CURRENT settings, streaks, and manual overrides will be replaced with what's in this backup.",
	button1 = "Restore",
	button2 = "Cancel",
	OnAccept = function(self, index)
		XComp.Data:RestoreBackup(index)
		for _, c in ipairs(backupContainers) do XComp.Options:PopulateBackupRows(c) end
		for _, c in ipairs(generalContainers) do XComp.Options:PopulateGeneralRows(c) end
		for _, c in ipairs(appearanceContainers) do XComp.Options:PopulateAppearanceRows(c) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["XCOMP_DELETE_BACKUP"] = {
	text = "Delete this backup? This can't be undone.",
	button1 = "Delete",
	button2 = "Cancel",
	OnAccept = function(self, index)
		XComp.Data:DeleteBackup(index)
		for _, c in ipairs(backupContainers) do XComp.Options:PopulateBackupRows(c) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function O:PopulateBackupRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local introRow = CreateFrame("Frame", nil, container)
	introRow:SetHeight(54)
	introRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	introRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, introRow)

	local introText = introRow:CreateFontString(nil, "OVERLAY")
	introText:SetFontObject(XComp.BodyFont)
	introText:SetPoint("TOPLEFT", introRow, "TOPLEFT", 0, 0)
	introText:SetPoint("RIGHT", introRow, "RIGHT", 0, 0)
	introText:SetJustifyH("LEFT")
	introText:SetText("A safety net for your settings, streaks, and manual overrides - one automatic backup is taken per day, and you can also take one yourself. Keeps the last 5.")
	XComp.ApplyTextShadow(introText)

	local btnRow = CreateFrame("Frame", nil, container)
	btnRow:SetHeight(30)
	btnRow:SetPoint("TOPLEFT", introRow, "BOTTOMLEFT", 0, -10)
	btnRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, btnRow)

	local backupBtn = MakeFlatButton(btnRow, false, 140, "Backup Now", function()
		XComp.Data:CreateBackup("Manual")
		for _, c in ipairs(backupContainers) do self:PopulateBackupRows(c) end
	end)
	backupBtn:ClearAllPoints()
	backupBtn:SetPoint("TOPLEFT", btnRow, "TOPLEFT", 0, 0)

	-- "Reset to Defaults" - moved here from the shared page header (2026-09-
	-- 29): a real, semi-destructive settings action belongs with the other
	-- backup/restore controls, not floating on every single page.
	local resetBtn = MakeFlatButton(btnRow, backupBtn, 150, "Reset to Defaults", function()
		self:ResetToDefaults()
	end)

	local anchorTo = btnRow
	local totalHeight = 54 + 10 + 30

	local backups = XComp.Data:GetBackups()
	if #backups == 0 then
		local emptyRow = CreateFrame("Frame", nil, container)
		emptyRow:SetHeight(24)
		emptyRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -14)
		emptyRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		table.insert(container.rows, emptyRow)
		totalHeight = totalHeight + 24 + 14

		local emptyText = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		emptyText:SetPoint("TOPLEFT", emptyRow, "TOPLEFT", 0, 0)
		emptyText:SetText("No backups yet.")
	else
		for index, backup in ipairs(backups) do
			local row = CreateFrame("Frame", nil, container)
			row:SetHeight(30)
			row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -10)
			row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
			table.insert(container.rows, row)
			anchorTo = row
			totalHeight = totalHeight + 30 + 10

			local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetPoint("LEFT", row, "LEFT", 0, 0)
			label:SetJustifyH("LEFT")
			label:SetText(string.format("%s - %s", date("%Y-%m-%d %H:%M", backup.timestamp), backup.label or "Manual"))

			local deleteBtn = MakeFlatButton(row, false, 70, "Delete", function()
				StaticPopup_Show("XCOMP_DELETE_BACKUP", nil, nil, index)
			end)
			deleteBtn:ClearAllPoints()
			deleteBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

			local restoreBtn = MakeFlatButton(row, false, 80, "Restore", function()
				StaticPopup_Show("XCOMP_RESTORE_BACKUP", nil, nil, index)
			end)
			restoreBtn:ClearAllPoints()
			restoreBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -8, 0)
		end
	end

	container:SetHeight(totalHeight)
end

-------------------------------------------------
-- Page 7: Reputation (build-plan item 15) - plain read-only list of every
-- faction, Esc-menu native settings ONLY per explicit user request (not the
-- tracker, not the standalone window - this one page breaks from the
-- "everywhere the same" pattern on purpose).
-------------------------------------------------
function O:PopulateReputationRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local introRow = CreateFrame("Frame", nil, container)
	introRow:SetHeight(30)
	introRow:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	introRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, introRow)

	local introText = introRow:CreateFontString(nil, "OVERLAY")
	introText:SetFontObject(XComp.BodyFont)
	introText:SetPoint("TOPLEFT", introRow, "TOPLEFT", 0, 0)
	introText:SetPoint("RIGHT", introRow, "RIGHT", 0, 0)
	introText:SetJustifyH("LEFT")
	introText:SetText("Every faction you have standing with.")
	XComp.ApplyTextShadow(introText)

	local anchorTo = introRow
	local totalHeight = 30

	local factions = XComp.Data:GetAllFactions()
	for _, f in ipairs(factions) do
		if f.isHeader and not f.isHeaderWithRep then
			-- Pure section header (e.g. "Classic", "The War Within") - a
			-- label only, no standing bar.
			local headerRow = CreateFrame("Frame", nil, container)
			headerRow:SetHeight(22)
			headerRow:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -10)
			headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
			table.insert(container.rows, headerRow)
			anchorTo = headerRow
			totalHeight = totalHeight + 22 + 10

			local headerText = headerRow:CreateFontString(nil, "OVERLAY")
			headerText:SetFontObject(XComp.TitleFont)
			headerText:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
			local ar, ag, ab = XComp.GetAccentColor()
			headerText:SetTextColor(ar, ag, ab, 1)
			headerText:SetText(f.name)
		else
			local row = CreateFrame("Frame", nil, container)
			row:SetHeight(22)
			row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", f.isChild and 16 or 0, -6)
			row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
			table.insert(container.rows, row)
			anchorTo = row
			totalHeight = totalHeight + 22 + 6

			local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
			nameText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
			nameText:SetJustifyH("LEFT")

			local standingLabel = _G["FACTION_STANDING_LABEL" .. (f.reaction or 0)] or ""
			local range = (f.nextReactionThreshold or 0) - (f.currentReactionThreshold or 0)
			local progress = (f.currentStanding or 0) - (f.currentReactionThreshold or 0)
			local progressText = ""
			if range > 0 then
				progressText = string.format(" (%d / %d)", progress, range)
			end
			nameText:SetText(string.format("%s - %s%s", f.name, standingLabel, progressText))
		end
	end

	container:SetHeight(totalHeight)
end

-- Seventh native subcategory page - Esc-menu only, see comment above.
function O:BuildReputationPanel()
	if self.reputationPanel then return self.reputationPanel end

	local panel = CreateFrame("Frame")
	panel.name = "Reputation"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.reputationPanel = panel
	self:PopulateReputationRows(rowsContainer)
	return panel
end

-------------------------------------------------
-- Page 9: Alts (build-plan item 19) - Esc-menu only, same reasoning as
-- Reputation (a "check on my alts" browsing activity, not something the
-- quick floating popup needs). Two nested vertical sidebars, same visual
-- language as the standalone window's tab sidebar: characters (far left,
-- with a same-day completion count) -> sections (Daily/Weekly/One-time,
-- middle column) -> a read-only breakdown for that character+section on the
-- right. Cross-character data comes from Data.lua's roster snapshot system
-- - see the big comment there for why it can only ever be "as of their last
-- login," not live.
-------------------------------------------------
local ALT_SECTION_KEYS = { "daily", "weekly", "onetime" }
local ALT_SECTION_LABELS = { daily = "Daily", weekly = "Weekly", onetime = "One-time" }

function O:PopulateAltsContent(container, charKey, sectionKey)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local entry = charKey and XComp_DB.roster and XComp_DB.roster[charKey]
	local anchorTo = nil
	local totalHeight = 0

	local function AddLine(text, height)
		height = height or 20
		local row = CreateFrame("Frame", nil, container)
		row:SetHeight(height)
		if anchorTo then
			row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
		else
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
		end
		row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		table.insert(container.rows, row)
		anchorTo = row
		totalHeight = totalHeight + height + 6

		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		return fs
	end

	if not entry then
		AddLine("No characters logged in with Xal's Compendium yet - play one to add it here.")
		container:SetHeight(math.max(totalHeight, 1))
		return
	end

	local ar, ag, ab = XComp.GetAccentColor()
	local header = AddLine(string.format("%s - %s", entry.name, ALT_SECTION_LABELS[sectionKey]), 22)
	header:SetFontObject(XComp.TitleFont)
	header:SetTextColor(ar, ag, ab, 1)

	local lastSeenText = entry.lastSeen and date("%Y-%m-%d %H:%M", entry.lastSeen) or "unknown"
	local lastSeenLine = AddLine("As of last login: " .. lastSeenText, 18)
	lastSeenLine:SetTextColor(0.6, 0.6, 0.6, 1)

	for _, tier in ipairs(XComp.Data.Catalog.tiers) do
		local snap = entry.tiers and entry.tiers[tier.key] and entry.tiers[tier.key][sectionKey]
		if snap then
			AddLine(string.format("%s: %d / %d", tier.label, snap.completed, snap.total))
		end
	end

	local streak = entry.streaks and entry.streaks["current:" .. sectionKey]
	if streak then
		AddLine(string.format("Streak: %d current, %d best", streak.current, streak.best))
	end

	container:SetHeight(math.max(totalHeight, 1))
end

function O:RefreshAltsPanel(panel)
	local roster = XComp.Data:GetRosterList()

	if not panel.selectedCharKey or not (XComp_DB.roster and XComp_DB.roster[panel.selectedCharKey]) then
		panel.selectedCharKey = roster[1] and roster[1].charKey
	end
	panel.selectedSection = panel.selectedSection or "daily"

	if panel.charButtons then
		for _, b in ipairs(panel.charButtons) do b:Hide(); b:SetParent(nil) end
	end
	panel.charButtons = {}

	if #roster == 0 then
		local emptyText = panel.charSidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		emptyText:SetPoint("TOPLEFT", panel.charSidebar, "TOPLEFT", 0, 0)
		emptyText:SetPoint("RIGHT", panel.charSidebar, "RIGHT", 0, 0)
		emptyText:SetJustifyH("LEFT")
		emptyText:SetWordWrap(true)
		emptyText:SetText("No characters yet.")
		table.insert(panel.charButtons, emptyText)
	else
		local anchorBtn = nil
		for _, entry in ipairs(roster) do
			local daily = entry.tiers and entry.tiers.current and entry.tiers.current.daily
			local countText = daily and string.format("%d/%d today", daily.completed, daily.total) or "no data yet"
			local btn = MakeFlatButton(panel.charSidebar, false, 130,
				entry.name .. "\n|cff999999" .. countText .. "|r",
				function()
					panel.selectedCharKey = entry.charKey
					self:RefreshAltsPanel(panel)
				end)
			btn:ClearAllPoints()
			btn:SetHeight(34)
			if anchorBtn then
				btn:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
			else
				btn:SetPoint("TOPLEFT", panel.charSidebar, "TOPLEFT", 0, 0)
			end
			local sar, sag, sab = XComp.GetAccentColor()
			btn:SetSelectedColor(sar, sag, sab)
			btn:SetUnselectedColor(XComp.SIDEBAR_UNSELECTED[1], XComp.SIDEBAR_UNSELECTED[2], XComp.SIDEBAR_UNSELECTED[3])
			btn:SetFontSize(14)
			btn:SetSelected(entry.charKey == panel.selectedCharKey)
			table.insert(panel.charButtons, btn)
			anchorBtn = btn
		end
	end

	if not panel.sectionButtons then
		panel.sectionButtons = {}
		local anchorSec = nil
		for _, key in ipairs(ALT_SECTION_KEYS) do
			local btn = MakeFlatButton(panel.sectionSidebar, false, 90, ALT_SECTION_LABELS[key], function()
				panel.selectedSection = key
				self:RefreshAltsPanel(panel)
			end)
			btn:ClearAllPoints()
			if anchorSec then
				btn:SetPoint("TOPLEFT", anchorSec, "BOTTOMLEFT", 0, -4)
			else
				btn:SetPoint("TOPLEFT", panel.sectionSidebar, "TOPLEFT", 0, 0)
			end
			local sar2, sag2, sab2 = XComp.GetAccentColor()
			btn:SetSelectedColor(sar2, sag2, sab2)
			btn:SetUnselectedColor(XComp.SIDEBAR_UNSELECTED[1], XComp.SIDEBAR_UNSELECTED[2], XComp.SIDEBAR_UNSELECTED[3])
			btn:SetFontSize(14)
			table.insert(panel.sectionButtons, btn)
			anchorSec = btn
		end
	end
	-- Buttons are only built once (cached on panel.sectionButtons), but
	-- selection changes on every click - re-apply which one's selected
	-- every refresh.
	for i, key in ipairs(ALT_SECTION_KEYS) do
		panel.sectionButtons[i]:SetSelected(key == panel.selectedSection)
	end

	self:PopulateAltsContent(panel.contentContainer, panel.selectedCharKey, panel.selectedSection)
end

-- Ninth native subcategory page - Esc-menu only, see comment above.
function O:BuildAltsPanel()
	if self.altsPanel then return self.altsPanel end

	local panel = CreateFrame("Frame")
	panel.name = "Alts"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	local charSidebar = CreateFrame("Frame", nil, panel)
	charSidebar:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -14)
	charSidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 16)
	charSidebar:SetWidth(140)

	local vDivider1 = panel:CreateTexture(nil, "ARTWORK")
	vDivider1:SetWidth(2)
	vDivider1:SetColorTexture(XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3], 1)
	vDivider1:SetPoint("TOPLEFT", charSidebar, "TOPRIGHT", 10, 0)
	vDivider1:SetPoint("BOTTOMLEFT", charSidebar, "BOTTOMRIGHT", 10, 0)

	local sectionSidebar = CreateFrame("Frame", nil, panel)
	sectionSidebar:SetPoint("TOPLEFT", vDivider1, "TOPRIGHT", 12, 0)
	sectionSidebar:SetPoint("BOTTOMLEFT", vDivider1, "BOTTOMRIGHT", 12, 0)
	sectionSidebar:SetWidth(100)

	local vDivider2 = panel:CreateTexture(nil, "ARTWORK")
	vDivider2:SetWidth(2)
	vDivider2:SetColorTexture(XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3], 1)
	vDivider2:SetPoint("TOPLEFT", sectionSidebar, "TOPRIGHT", 10, 0)
	vDivider2:SetPoint("BOTTOMLEFT", sectionSidebar, "BOTTOMRIGHT", 10, 0)

	local contentAnchor = CreateFrame("Frame", nil, panel)
	contentAnchor:SetPoint("TOPLEFT", vDivider2, "TOPRIGHT", 12, 0)
	contentAnchor:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, 0)
	contentAnchor:SetHeight(1)

	local contentContainer = MakeScrollingRowsContainer(panel, contentAnchor, 16)

	panel.charSidebar = charSidebar
	panel.sectionSidebar = sectionSidebar
	panel.contentContainer = contentContainer

	-- Re-populates every time this page is actually navigated to (not just
	-- once at build time) - this is roster data, it changes as you (and
	-- your alts) actually play, so it needs to be fresh whenever you look
	-- at it, not frozen from whenever the settings panel first got built.
	panel:SetScript("OnShow", function() self:RefreshAltsPanel(panel) end)

	self.altsPanel = panel
	self:RefreshAltsPanel(panel)
	return panel
end

-- Sixth native subcategory page.
function O:BuildBackupPanel()
	if self.backupPanel then return self.backupPanel end

	local panel = CreateFrame("Frame")
	panel.name = "Backup"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.backupPanel = panel
	self:PopulateBackupRows(rowsContainer)
	table.insert(backupContainers, rowsContainer)
	return panel
end

-------------------------------------------------
-- Access path 1: Blizzard's native Options -> AddOns list
-------------------------------------------------
function O:BuildPanel()
	if self.panel then return self.panel end

	local panel = CreateFrame("Frame")
	panel.name = "Xal's Compendium"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.panel = panel
	self:PopulateGeneralRows(rowsContainer)
	table.insert(generalContainers, rowsContainer)
	return panel
end

-- A genuine separate subcategory page under the native panel, not a
-- visual section within it - Settings.RegisterCanvasLayoutSubcategory,
-- same modern API family as RegisterCanvasLayoutCategory.
function O:BuildAppearancePanel()
	if self.appearancePanel then return self.appearancePanel end

	local panel = CreateFrame("Frame")
	panel.name = "Appearance"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.appearancePanel = panel
	self:PopulateAppearanceRows(rowsContainer)
	table.insert(appearanceContainers, rowsContainer)
	return panel
end

-- Builds a real sub-tab bar (Currencies / Goals) inside whatever parent is
-- given, anchored below topAnchor - used by BOTH the native Currencies
-- subcategory page and the standalone window's Currencies tab, so they
-- can't visually drift apart. Returns the wrapper frame (what the OUTER
-- tab/page system shows or hides as a unit) plus both inner containers.
local function BuildCurrenciesSubTabs(O, parent, topAnchor, bottomOffset)
	-- Direct children of `parent`, same as every other tab's content
	-- (General/Appearance/Diagnostics all anchor straight to the panel) - no
	-- extra wrapper frame layer.
	local subTabBar = CreateFrame("Frame", nil, parent)
	subTabBar:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -6)
	subTabBar:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -6)
	subTabBar:SetHeight(22)

	-- ONE scroll region shared by both sub-tabs - which rows are inside it
	-- swaps based on which pill is selected. The previous approach used TWO
	-- separate ScrollFrames sitting in the exact same rect, Show/Hide'd
	-- against each other - confirmed real bug (visibly doubled scrollbar,
	-- and the hidden one still eating wheel input meant for the visible
	-- one). One shared scroll region removes that whole class of bug -
	-- there's only ever one scrollbar because there's only ever one
	-- ScrollFrame.
	local container = MakeScrollingRowsContainer(parent, subTabBar, bottomOffset)
	local scroll = container:GetParent():GetParent()

	local checklistTab = MakeFlatButton(subTabBar, nil, 100, "Currencies", function() end)
	local goalsTab = MakeFlatButton(subTabBar, checklistTab, 100, "Goals", function() end)

	local activeIsChecklist = true
	local function ShowChecklist()
		activeIsChecklist = true
		checklistTab:SetSelected(true)
		goalsTab:SetSelected(false)
		O:PopulateCurrencyChecklistRows(container)
		scroll:SetVerticalScroll(0)
	end
	local function ShowGoals()
		activeIsChecklist = false
		checklistTab:SetSelected(false)
		goalsTab:SetSelected(true)
		O:PopulateCurrencyGoalsRows(container)
		scroll:SetVerticalScroll(0)
	end
	checklistTab:SetScript("OnClick", ShowChecklist)
	goalsTab:SetScript("OnClick", ShowGoals)
	ShowChecklist()

	-- Group object standing in for the old wrapper frame - the outer tab
	-- systems (native subcategory page, standalone window) need one handle
	-- to Show/Hide the whole Currencies section as a unit.
	local group = CreateFrame("Frame", nil, parent)
	group:SetAllPoints(subTabBar)
	function group:Show()
		subTabBar:Show()
		scroll:Show()
		scroll:EnableMouseWheel(true)
	end
	function group:Hide()
		subTabBar:Hide()
		scroll:Hide()
		scroll:EnableMouseWheel(false)
	end
	-- Repopulates whichever sub-tab (Currencies/Goals) is currently active,
	-- without changing which one is selected - used when the standalone
	-- window reopens, to pick up changes made via the native panel.
	function group:RefreshActive()
		if activeIsChecklist then ShowChecklist() else ShowGoals() end
	end
	-- Left shown by default (matches every other tab's container, which
	-- also defaults to shown and relies on its host panel/tab system for
	-- visibility) - the standalone window's own tab switcher immediately
	-- hides this on any tab other than Currencies right after construction.

	return group, container
end

-- Fourth native subcategory page - the currency tracking checklist + goals,
-- as two real sub-tabs (not appended content - see BuildCurrenciesSubTabs).
function O:BuildCurrenciesPanel()
	if self.currenciesPanel then return self.currenciesPanel end

	local panel = CreateFrame("Frame")
	panel.name = "Currencies"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	-- BuildCurrenciesSubTabs already populates the default (Currencies)
	-- sub-tab internally - no separate Populate calls needed here.
	local wrapper, container = BuildCurrenciesSubTabs(self, panel, divider)
	panel.rowsContainer = container

	self.currenciesPanel = panel
	return panel
end

-- Sixth native subcategory page - the diagnostics report button.
function O:BuildDiagnosticsPanel()
	if self.diagnosticsPanel then return self.diagnosticsPanel end

	local panel = CreateFrame("Frame")
	panel.name = "Diagnostics"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.diagnosticsPanel = panel
	self:PopulateDiagnosticsRows(rowsContainer)
	return panel
end

-------------------------------------------------
-- Access path 2: standalone floating window, entirely independent of
-- Blizzard's Settings system - a real second way to reach the same
-- settings, not just a shortcut into path 1. Two tabs (General/
-- Appearance) switch between two separate containers in the same window.
-------------------------------------------------
function O:BuildStandaloneWindow()
	if self.standaloneFrame then return self.standaloneFrame end

	local f = CreateFrame("Frame", "XalsCompendiumOptionsFrame", UIParent, "BackdropTemplate")
	-- Registering the frame's global name here makes Blizzard's own Escape-key
	-- handling close it, same as every other UI panel in the game.
	tinsert(UISpecialFrames, "XalsCompendiumOptionsFrame")
	-- Wider than before - the left-hand tab sidebar (plus its divider and
	-- margins) eats a fixed ~155px, and the currency grid especially still
	-- needs real width to lay out in columns.
	f:SetSize(560, 480)
	-- Anchors to a screen CORNER (only used the first time; once dragged,
	-- its real position is remembered permanently via
	-- XComp_DB.optionsWindowPoint) - part of a shared corner scheme across
	-- every Xal's addon's big settings window, see the "Default window
	-- position" rule in the shared brand-style memory.
	local savedPoint = XComp_DB.optionsWindowPoint
	if savedPoint then
		f:SetPoint(savedPoint[1], UIParent, savedPoint[2], savedPoint[3], savedPoint[4])
	else
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 40)
	end
	-- DIALOG strata so it renders above other UI (confirmed via screenshot:
	-- the player unit frame's health bar was showing through the bottom of
	-- this window) - a plain frame defaults to MEDIUM otherwise.
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	f:SetBackdropColor(GetPanelBg())
	f:SetBackdropBorderColor(XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3], 1)

	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		XComp_DB.optionsWindowPoint = { point, relPoint, x, y }
	end)

	-- Corner-handle resizing, gated on holding Shift while dragging - same
	-- pattern as the main tracker window's resize grip (UI.lua).
	f:SetResizable(true)
	f:SetResizeBounds(420, 320, 800, 700)
	local resizeGrip = CreateFrame("Button", nil, f)
	resizeGrip:SetSize(16, 16)
	resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeGrip:SetScript("OnMouseDown", function()
		if IsShiftKeyDown() then
			f:StartSizing("BOTTOMRIGHT")
		end
	end)
	resizeGrip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
	f.resizeGrip = resizeGrip

	-- Text/link-style close button, bottom-right - the standing convention
	-- for every window in this addon (see XComp.MakeCloseButton in Core.lua).
	-- Nudged left of its default spot, same reason as the main tracker
	-- window: the resize grip now occupies the very corner.
	local closeBtn = XComp.MakeCloseButton(f)
	closeBtn:ClearAllPoints()
	closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 8)

	local divider = BuildHeader(f)

	-- Tabs run down the LEFT side with a vertical divider between them and
	-- the page content, matching the Esc-menu's own settings layout -
	-- replaces the old horizontal row across the top, which ran out of
	-- width once a 6th tab (Backup) got added.
	local sidebar = CreateFrame("Frame", nil, f)
	sidebar:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)
	sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 34)
	sidebar:SetWidth(100)

	-- Standing Discord link - bottom of the sidebar, visible on every page
	-- (not just one tab), same placement Quest Compass already uses.
	local discordLogo = MakeDiscordLogoLink(sidebar, 84)
	discordLogo:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 0)

	local vDivider = f:CreateTexture(nil, "ARTWORK")
	vDivider:SetWidth(2)
	vDivider:SetColorTexture(XComp.DIVIDER_COLOR[1], XComp.DIVIDER_COLOR[2], XComp.DIVIDER_COLOR[3], 1)
	vDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
	vDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 10, 0)

	-- Zero-height anchor frame marking where page content starts (right of
	-- the vertical divider, level with the top of the sidebar) - every
	-- content container below anchors to THIS the same way they used to
	-- anchor below the old horizontal tab bar, so none of that positioning
	-- logic (or BuildCurrenciesSubTabs) needed to change, just what it
	-- points at.
	local contentTop = CreateFrame("Frame", nil, f)
	contentTop:SetPoint("TOPLEFT", vDivider, "TOPRIGHT", 12, 0)
	contentTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, 0)
	contentTop:SetHeight(1)

	local generalContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	local appearanceContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	local currenciesWrapper, currencyContainer = BuildCurrenciesSubTabs(self, f, contentTop, 32)
	local diagnosticsContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	local backupContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	f.generalContainer = generalContainer
	f.appearanceContainer = appearanceContainer
	f.currenciesWrapper = currenciesWrapper
	f.currencyContainer = currencyContainer
	f.diagnosticsContainer = diagnosticsContainer
	f.backupContainer = backupContainer
	table.insert(generalContainers, generalContainer)
	table.insert(appearanceContainers, appearanceContainer)
	table.insert(backupContainers, backupContainer)

	-- This window sits at DIALOG strata (so it renders above other UI - see
	-- the SetFrameStrata call above), but a plain CreateFrame child does NOT
	-- inherit its parent's strata - it defaults to MEDIUM regardless. Mouse
	-- wheel targeting is strata-sensitive in a way normal clicks aren't, so
	-- every scroll frame in this window needs to be bumped up to DIALOG too,
	-- or wheel events aimed at it can lose out to something else on screen.
	-- The native settings panel never hits this because it isn't forced to
	-- a custom strata at all - real, confirmed difference (floating window
	-- broken, native panel fine, identical scroll code otherwise).
	for _, c in ipairs({ generalContainer, appearanceContainer, currencyContainer, diagnosticsContainer, backupContainer }) do
		c:GetParent():GetParent():SetFrameStrata("DIALOG")
	end

	-- The REAL scroll frame widget for each tab - GetParent() alone only
	-- reaches the inner scrollChild, not the actual ScrollFrame. Using just
	-- that was a real bug: it left every tab's actual scroll frame (with
	-- its own scrollbar, wheel-enabled) permanently shown and stacked on
	-- top of each other the whole time, only ever hiding the rows inside
	-- them - not the extra scrollbars/wheel targets themselves.
	local panels = {
		generalContainer:GetParent():GetParent(),
		appearanceContainer:GetParent():GetParent(),
		currenciesWrapper,
		diagnosticsContainer:GetParent():GetParent(),
		backupContainer:GetParent():GetParent(),
	}
	local labels = { "General", "Appearance", "Currencies", "Diagnostics", "Backup" }
	local tabs = {}

	local function ShowTab(activeIndex)
		for i, frame in ipairs(panels) do
			tabs[i]:SetSelected(i == activeIndex)
			if i == activeIndex then frame:Show() else frame:Hide() end
		end
	end

	local anchorTab = nil
	for i, label in ipairs(labels) do
		local tab = MakeFlatButton(sidebar, false, 100, label, function() ShowTab(i) end)
		tab:ClearAllPoints()
		if anchorTab then
			tab:SetPoint("TOPLEFT", anchorTab, "BOTTOMLEFT", 0, -4)
		else
			tab:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
		end
		-- Sidebar links specifically use the accent color when selected (not
		-- white) and the muted blue-gray when not - narrowly scoped to this
		-- sidebar, per the family standard.
		local sar, sag, sab = XComp.GetAccentColor()
		tab:SetSelectedColor(sar, sag, sab)
		tab:SetUnselectedColor(XComp.SIDEBAR_UNSELECTED[1], XComp.SIDEBAR_UNSELECTED[2], XComp.SIDEBAR_UNSELECTED[3])
		tab:SetFontSize(14)
		tabs[i] = tab
		anchorTab = tab
	end

	local function ShowGeneralTab() ShowTab(1) end
	f.ShowGeneralTab = ShowGeneralTab

	f:Hide()
	self.standaloneFrame = f
	self:PopulateGeneralRows(generalContainer)
	self:PopulateAppearanceRows(appearanceContainer)
	-- Currencies already populated its default sub-tab internally, inside
	-- BuildCurrenciesSubTabs - no separate call needed here.
	self:PopulateDiagnosticsRows(diagnosticsContainer)
	self:PopulateBackupRows(backupContainer)
	ShowGeneralTab()
	return f
end

function O:ToggleStandalone()
	local f = self:BuildStandaloneWindow()
	if f:IsShown() then
		f:Hide()
	else
		-- Pick up any changes made via the native panel, and always reopen
		-- on the General tab for a consistent starting point.
		self:PopulateGeneralRows(f.generalContainer)
		self:PopulateAppearanceRows(f.appearanceContainer)
		f.currenciesWrapper:RefreshActive()
		self:PopulateDiagnosticsRows(f.diagnosticsContainer)
		self:PopulateBackupRows(f.backupContainer)
		f.ShowGeneralTab()
		f:Show()
	end
end

-------------------------------------------------
-- Registration
-------------------------------------------------
local registered = false
function O:Register()
	if registered then return end
	registered = true

	local panel = self:BuildPanel()
	local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
	self.category = category

	local appearancePanel = self:BuildAppearancePanel()
	Settings.RegisterCanvasLayoutSubcategory(category, appearancePanel, appearancePanel.name)

	local currenciesPanel = self:BuildCurrenciesPanel()
	Settings.RegisterCanvasLayoutSubcategory(category, currenciesPanel, currenciesPanel.name)

	local diagnosticsPanel = self:BuildDiagnosticsPanel()
	Settings.RegisterCanvasLayoutSubcategory(category, diagnosticsPanel, diagnosticsPanel.name)

	local backupPanel = self:BuildBackupPanel()
	Settings.RegisterCanvasLayoutSubcategory(category, backupPanel, backupPanel.name)

	local reputationPanel = self:BuildReputationPanel()
	Settings.RegisterCanvasLayoutSubcategory(category, reputationPanel, reputationPanel.name)

	local altsPanel = self:BuildAltsPanel()
	Settings.RegisterCanvasLayoutSubcategory(category, altsPanel, altsPanel.name)
end
