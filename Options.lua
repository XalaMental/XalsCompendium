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
-- THREE pages within each path (real separate sections, not one long list,
-- per explicit user request - matches XalsXpeditedRoutes' SettingsPanel.lua,
-- which splits into Waypoint/Map Markers/Gather Tally/Database/Integrations
-- rather than one long page): General (tracked sections + auto-size),
-- Appearance (frameless/transparency/scale), and Colors (accent + background
-- color). Native panel uses genuine Settings.RegisterCanvasLayoutSubcategory
-- pages; standalone window uses a simple tab switcher between three
-- containers in the same frame.

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

-- Tracks every populated container of each kind so ResetToDefaults can
-- refresh all of them (native General, native Appearance, standalone
-- General, standalone Appearance) regardless of which one the user
-- clicked "Reset" from.
local generalContainers = {}
local appearanceContainers = {}
local colorsContainers = {}
local backupContainers = {}

-- Standing rule: every customizable feature needs a small, unobtrusive
-- "reset to default" option. Clears per-type enable/disable overrides,
-- per-item colors, and appearance settings (frameless/bgAlpha/scale/
-- accentColor) back to default - one unified reset rather than a separate
-- button per customizable feature.
function O:ResetToDefaults()
	XComp_DB.settings.typeEnabled = {}
	XComp_DB.settings.frameless = nil
	XComp_DB.settings.bgAlpha = nil
	XComp_DB.settings.scale = nil
	XComp_DB.settings.typeOrder = nil
	XComp_DB.settings.categoryOrder = nil
	XComp_DB.itemColors = {}
	XComp_DB.accentColor = nil
	XComp_DB.bgColor = nil
	if XComp.UI then
		XComp.UI:ApplyTheme()
		if XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
			XComp.UI:RefreshSections()
		end
	end
	for _, c in ipairs(generalContainers) do self:PopulateGeneralRows(c) end
	for _, c in ipairs(appearanceContainers) do self:PopulateAppearanceRows(c) end
	for _, c in ipairs(colorsContainers) do self:PopulateColorsRows(c) end
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
local CATEGORY_KEYS = { "greatVault", "currencies", "weeklyEvents", "professions", "reputation", "storyCampaign", "worldQuests", "custom" }

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
-- Flat, self-drawn button matching Compendium's OWN locked button spec -
-- thin LIGHT (not accent-colored) border, semi-transparent dark fill,
-- plain white text, no bevel/gradient. Reference: the EllesmereUI Game
-- Menu screenshot the user provided when this addon's look was first
-- locked in. Used for every button in the addon (Reset to Defaults, Run
-- Diagnostics, the standalone window's tabs) instead of Blizzard's chunky
-- UIPanelButtonTemplate. Optional :SetSelected() is only used by tabs.
local BTN_BORDER = { 0.75, 0.75, 0.78, 1 }
local BTN_BORDER_SELECTED = { 1, 1, 1, 1 }

local function MakeFlatButton(parent, anchorTo, width, text, onClick)
	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	btn:SetSize(width, 22)
	if anchorTo then
		btn:SetPoint("LEFT", anchorTo, "RIGHT", 4, 0)
	elseif anchorTo == false then
		-- caller positions the button itself (SetPoint called after return)
	else
		btn:SetPoint("LEFT", parent, "LEFT", 0, 0)
	end
	btn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 2,
	})
	btn:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
	btn:SetBackdropBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText(text)
	label:SetTextColor(1, 1, 1, 1)
	btn.label = label

	btn:SetScript("OnEnter", function(self)
		if not self.selected then self:SetBackdropColor(0.18, 0.18, 0.18, 0.75) end
	end)
	btn:SetScript("OnLeave", function(self)
		if not self.selected then self:SetBackdropColor(0.1, 0.1, 0.1, 0.6) end
	end)
	btn:SetScript("OnClick", onClick)

	function btn:SetSelected(selected)
		self.selected = selected
		if selected then
			self:SetBackdropColor(0.22, 0.22, 0.22, 0.85)
			self:SetBackdropBorderColor(BTN_BORDER_SELECTED[1], BTN_BORDER_SELECTED[2], BTN_BORDER_SELECTED[3], BTN_BORDER_SELECTED[4])
		else
			self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
			self:SetBackdropBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])
		end
	end

	return btn
end

-- Builds the common header (title, divider, reset button) onto any parent
-- frame - shared between the native panel and the standalone window so
-- both look identical without duplicating the layout code.
local function BuildHeader(parent, onReset)
	local ar, ag, ab = XComp.GetAccentColor()

	local title = parent:CreateFontString(nil, "OVERLAY")
	title:SetFont("Fonts\\MORPHEUS.TTF", 20, "")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
	title:SetTextColor(ar, ag, ab, 1)
	title:SetText("Xal's Compendium")
	XComp.ApplyTextShadow(title)

	local divider = parent:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(ar, ag, ab, 1)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	divider:SetPoint("RIGHT", parent, "RIGHT", -16, 0)

	local resetBtn = MakeFlatButton(parent, false, 130, "Reset to Defaults", onReset)
	resetBtn:ClearAllPoints()
	resetBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -16)

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

		local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		cb:SetSize(22, 22)
		cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		cb:SetChecked(self:IsTypeEnabled(typeSection.key))
		cb:SetScript("OnClick", function(btn)
			self:SetTypeEnabled(typeSection.key, btn:GetChecked() and true or false)
			if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
				XComp.UI:RefreshSections()
			end
		end)

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

	local sizeCB = CreateFrame("CheckButton", nil, sizeRow, "UICheckButtonTemplate")
	sizeCB:SetSize(22, 22)
	sizeCB:SetPoint("TOPLEFT", sizeRow, "TOPLEFT", 0, 0)
	sizeCB:SetChecked(not (XComp_DB.settings and XComp_DB.settings.autoSize == false))
	sizeCB:SetScript("OnClick", function(btn)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.autoSize = btn:GetChecked() and true or false
		if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
			XComp.UI:RefreshSections()
		end
	end)

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
	local framelessCB = CreateFrame("CheckButton", nil, framelessRow, "UICheckButtonTemplate")
	framelessCB:SetSize(22, 22)
	framelessCB:SetPoint("TOPLEFT", framelessRow, "TOPLEFT", 0, 0)
	framelessCB:SetChecked(XComp_DB.settings and XComp_DB.settings.frameless or false)
	framelessCB:SetScript("OnClick", function(btn)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.frameless = btn:GetChecked() and true or false
		if XComp.UI then XComp.UI:ApplyTheme() end
	end)
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

	container:SetHeight(math.max(totalHeight, 1))
end

-------------------------------------------------
-- Page 3: Colors (accent color, background color) - split into its own
-- page once it grew past a single swatch, matching how Routes' Waypoint/
-- Map Markers/Gather Tally pages are each their own topic rather than one
-- long list. Also documents the third color mechanism (per-item/header
-- right-click coloring) that already exists in the main tracker but had no
-- mention anywhere in Options.
-------------------------------------------------
local function MakeColorSwatchRow(container, anchorTo, label, getColor, setColor, desc)
	local row = CreateFrame("Frame", nil, container)
	row:SetHeight(56)
	row:ClearAllPoints()
	local rowHeight = 56 + 18
	if anchorTo then
		row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -18)
	else
		row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
	end
	row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, row)

	local swatch = CreateFrame("Button", nil, row)
	swatch:SetSize(26, 26)
	swatch:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	local swatchTex = swatch:CreateTexture(nil, "OVERLAY")
	swatchTex:SetAllPoints()
	local r, g, b = getColor()
	swatchTex:SetColorTexture(r, g, b, 1)
	swatch:SetScript("OnClick", function()
		local cr, cg, cb = getColor()
		ColorPickerFrame:SetupColorPickerAndShow({
			r = cr, g = cg, b = cb,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				setColor(nr, ng, nb)
				swatchTex:SetColorTexture(nr, ng, nb, 1)
				if XComp.UI then XComp.UI:ApplyTheme() end
			end,
			cancelFunc = function()
				local pr, pg, pb = ColorPickerFrame:GetPreviousValues()
				if pr then
					setColor(pr, pg, pb)
					swatchTex:SetColorTexture(pr, pg, pb, 1)
					if XComp.UI then XComp.UI:ApplyTheme() end
				end
			end,
		})
	end)

	local name = row:CreateFontString(nil, "OVERLAY")
	name:SetFontObject(XComp.TitleFont)
	name:SetPoint("LEFT", swatch, "RIGHT", 8, 10)
	local ar, ag, ab = XComp.GetAccentColor()
	name:SetTextColor(ar, ag, ab, 1)
	name:SetText(label)

	local descFS = row:CreateFontString(nil, "OVERLAY")
	descFS:SetFontObject(XComp.BodyFont)
	descFS:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
	descFS:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	descFS:SetJustifyH("LEFT")
	descFS:SetText(desc)

	return row, rowHeight
end

function O:PopulateColorsRows(container)
	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local totalHeight = 0

	local accentRow, accentH = MakeColorSwatchRow(container, nil, "Accent color",
		function() return XComp.GetAccentColor() end,
		function(r, g, b) XComp_DB.accentColor = { r, g, b } end,
		"Borders, titles, and default label color used throughout the addon.")
	totalHeight = totalHeight + accentH

	local bgRow, bgH = MakeColorSwatchRow(container, accentRow, "Background color",
		function() return XComp.GetBgColor() end,
		function(r, g, b) XComp_DB.bgColor = { r, g, b } end,
		"The panel fill color behind everything (transparency is set separately, on the Appearance page).")
	totalHeight = totalHeight + bgH

	local noteRow = CreateFrame("Frame", nil, container)
	noteRow:SetHeight(50)
	noteRow:SetPoint("TOPLEFT", bgRow, "BOTTOMLEFT", 0, -18)
	noteRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, noteRow)
	totalHeight = totalHeight + 50 + 18

	local noteText = noteRow:CreateFontString(nil, "OVERLAY")
	noteText:SetFontObject(XComp.BodyFont)
	noteText:SetPoint("TOPLEFT", noteRow, "TOPLEFT", 0, 0)
	noteText:SetPoint("RIGHT", noteRow, "RIGHT", 0, 0)
	noteText:SetJustifyH("LEFT")
	noteText:SetText("Individual quest items and the Daily/Weekly/One-time headers can also be given their own color - right-click any of them directly in the tracker window.")

	-- Text section: font/outline/size/shadow, ported from XalsQuestCompass's
	-- working ApplyFontSettings/FONT_OPTIONS pattern (Core.lua). Dropdowns
	-- are instance-cached on the container, same reason as the sliders
	-- above (UIDropDownMenuTemplate needs a real global name, and
	-- Populate* runs more than once per container over its lifetime).
	XComp_DB.text = XComp_DB.text or {}

	local textHeaderRow = CreateFrame("Frame", nil, container)
	textHeaderRow:SetHeight(20)
	textHeaderRow:SetPoint("TOPLEFT", noteRow, "BOTTOMLEFT", 0, -18)
	textHeaderRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, textHeaderRow)
	totalHeight = totalHeight + 20 + 18
	local textHeaderText = textHeaderRow:CreateFontString(nil, "OVERLAY")
	textHeaderText:SetFontObject(XComp.TitleFont)
	textHeaderText:SetPoint("TOPLEFT", textHeaderRow, "TOPLEFT", 0, 0)
	textHeaderText:SetText("Text")
	local thr, thg, thb = XComp.GetAccentColor()
	textHeaderText:SetTextColor(thr, thg, thb, 1)

	local fontRow = CreateFrame("Frame", nil, container)
	fontRow:SetHeight(46)
	fontRow:SetPoint("TOPLEFT", textHeaderRow, "BOTTOMLEFT", 0, -6)
	fontRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, fontRow)
	totalHeight = totalHeight + 46 + 6

	local fontLabel = fontRow:CreateFontString(nil, "OVERLAY")
	fontLabel:SetFontObject(XComp.BodyFont)
	fontLabel:SetPoint("TOPLEFT", fontRow, "TOPLEFT", 0, 0)
	fontLabel:SetText("Font")

	local fontDropdown = container.fontDropdown
	if not fontDropdown then
		dropdownNameCounter = dropdownNameCounter + 1
		fontDropdown = CreateFrame("Frame", "XalsCompendiumFontDropdown" .. dropdownNameCounter, fontRow, "UIDropDownMenuTemplate")
		container.fontDropdown = fontDropdown
	else
		fontDropdown:SetParent(fontRow)
	end
	fontDropdown:ClearAllPoints()
	fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -4)
	UIDropDownMenu_SetWidth(fontDropdown, 220)
	local function RefreshFontDropdownText()
		UIDropDownMenu_SetText(fontDropdown, XComp.GetFontOption(XComp_DB.text.fontKey).name)
	end
	UIDropDownMenu_Initialize(fontDropdown, function(self, level)
		for _, opt in ipairs(XComp.FONT_OPTIONS) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = opt.name
			info.checked = (XComp_DB.text.fontKey == opt.key)
			info.func = function()
				XComp_DB.text.fontKey = opt.key
				RefreshFontDropdownText()
				XComp.ApplyFontSettings()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	RefreshFontDropdownText()
	fontDropdown:Show()

	local outlineRow = CreateFrame("Frame", nil, container)
	outlineRow:SetHeight(46)
	outlineRow:SetPoint("TOPLEFT", fontRow, "BOTTOMLEFT", 0, -8)
	outlineRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, outlineRow)
	totalHeight = totalHeight + 46 + 8

	local outlineLabel = outlineRow:CreateFontString(nil, "OVERLAY")
	outlineLabel:SetFontObject(XComp.BodyFont)
	outlineLabel:SetPoint("TOPLEFT", outlineRow, "TOPLEFT", 0, 0)
	outlineLabel:SetText("Font Outline")

	local outlineDropdown = container.outlineDropdown
	if not outlineDropdown then
		dropdownNameCounter = dropdownNameCounter + 1
		outlineDropdown = CreateFrame("Frame", "XalsCompendiumOutlineDropdown" .. dropdownNameCounter, outlineRow, "UIDropDownMenuTemplate")
		container.outlineDropdown = outlineDropdown
	else
		outlineDropdown:SetParent(outlineRow)
	end
	outlineDropdown:ClearAllPoints()
	outlineDropdown:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", -16, -4)
	UIDropDownMenu_SetWidth(outlineDropdown, 220)
	local function RefreshOutlineDropdownText()
		UIDropDownMenu_SetText(outlineDropdown, XComp.GetOutlineOption(XComp_DB.text.outlineKey).name)
	end
	UIDropDownMenu_Initialize(outlineDropdown, function(self, level)
		for _, opt in ipairs(XComp.OUTLINE_OPTIONS) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = opt.name
			info.checked = (XComp_DB.text.outlineKey == opt.key)
			info.func = function()
				XComp_DB.text.outlineKey = opt.key
				RefreshOutlineDropdownText()
				XComp.ApplyFontSettings()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	RefreshOutlineDropdownText()
	outlineDropdown:Show()

	local sizeRow2 = CreateFrame("Frame", nil, container)
	sizeRow2:SetHeight(50)
	sizeRow2:SetPoint("TOPLEFT", outlineRow, "BOTTOMLEFT", 0, -8)
	sizeRow2:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, sizeRow2)
	totalHeight = totalHeight + 50 + 8

	local fontSizeSlider = container.fontSizeSlider
	if not fontSizeSlider then
		sliderNameCounter = sliderNameCounter + 1
		local uniqueName = "XalsCompendiumFontSizeSlider" .. sliderNameCounter
		fontSizeSlider = CreateFrame("Slider", uniqueName, sizeRow2, "OptionsSliderTemplate")
		_G[uniqueName.."Low"]:SetText("10")
		_G[uniqueName.."High"]:SetText("22")
		container.fontSizeSlider = fontSizeSlider
	else
		fontSizeSlider:SetParent(sizeRow2)
	end
	fontSizeSlider:ClearAllPoints()
	fontSizeSlider:SetPoint("TOPLEFT", sizeRow2, "TOPLEFT", 4, -14)
	fontSizeSlider:SetWidth(340)
	fontSizeSlider:SetMinMaxValues(10, 22)
	fontSizeSlider:SetValueStep(1)
	fontSizeSlider:SetObeyStepOnDrag(true)
	local fontSizeStart = XComp_DB.text.fontSize or 13
	fontSizeSlider:SetValue(fontSizeStart)
	_G[fontSizeSlider:GetName().."Text"]:SetText("Font Size: " .. fontSizeStart)
	fontSizeSlider:Show()
	fontSizeSlider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value + 0.5)
		XComp_DB.text.fontSize = value
		_G[self:GetName().."Text"]:SetText("Font Size: " .. value)
		XComp.ApplyFontSettings()
	end)

	local shadowRow = CreateFrame("Frame", nil, container)
	shadowRow:SetHeight(26)
	shadowRow:SetPoint("TOPLEFT", sizeRow2, "BOTTOMLEFT", 0, -4)
	shadowRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	table.insert(container.rows, shadowRow)
	totalHeight = totalHeight + 26 + 4

	local shadowCB = CreateFrame("CheckButton", nil, shadowRow, "UICheckButtonTemplate")
	shadowCB:SetSize(22, 22)
	shadowCB:SetPoint("TOPLEFT", shadowRow, "TOPLEFT", 0, 0)
	local shadowEnabled = XComp_DB.text.shadowEnabled
	if shadowEnabled == nil then shadowEnabled = true end
	shadowCB:SetChecked(shadowEnabled)
	shadowCB:SetScript("OnClick", function(btn)
		XComp_DB.text.shadowEnabled = btn:GetChecked() and true or false
		XComp.ApplyFontSettings()
	end)
	local shadowLabel = shadowRow:CreateFontString(nil, "OVERLAY")
	shadowLabel:SetFontObject(XComp.BodyFont)
	shadowLabel:SetPoint("LEFT", shadowCB, "RIGHT", 6, 8)
	shadowLabel:SetText("Text shadow")

	local shadowColorRow, shadowColorH = MakeColorSwatchRow(container, shadowRow, "Shadow color",
		function()
			local c = XComp_DB.text.shadowColor or { 0, 0, 0 }
			return c[1], c[2], c[3]
		end,
		function(r, g, b)
			XComp_DB.text.shadowColor = { r, g, b }
			XComp.ApplyFontSettings()
		end,
		"Only visible when Text shadow (above) is turned on.")
	totalHeight = totalHeight + shadowColorH

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
			divider:SetHeight(1)
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
				local cb = CreateFrame("CheckButton", nil, cell, "UICheckButtonTemplate")
				cb:SetSize(18, 18)
				cb:SetPoint("LEFT", cell, "LEFT", 0, 0)
				cb:SetChecked(tracked[currencyID] == true)
				cb:SetScript("OnClick", function(btn)
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
				end)

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
		for _, c in ipairs(colorsContainers) do XComp.Options:PopulateColorsRows(c) end
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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

	local charSidebar = CreateFrame("Frame", nil, panel)
	charSidebar:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -14)
	charSidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 16)
	charSidebar:SetWidth(140)

	local ar, ag, ab = XComp.GetAccentColor()
	local vDivider1 = panel:CreateTexture(nil, "ARTWORK")
	vDivider1:SetWidth(1)
	vDivider1:SetColorTexture(ar, ag, ab, 1)
	vDivider1:SetPoint("TOPLEFT", charSidebar, "TOPRIGHT", 10, 0)
	vDivider1:SetPoint("BOTTOMLEFT", charSidebar, "BOTTOMRIGHT", 10, 0)

	local sectionSidebar = CreateFrame("Frame", nil, panel)
	sectionSidebar:SetPoint("TOPLEFT", vDivider1, "TOPRIGHT", 12, 0)
	sectionSidebar:SetPoint("BOTTOMLEFT", vDivider1, "BOTTOMRIGHT", 12, 0)
	sectionSidebar:SetWidth(100)

	local vDivider2 = panel:CreateTexture(nil, "ARTWORK")
	vDivider2:SetWidth(1)
	vDivider2:SetColorTexture(ar, ag, ab, 1)
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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.appearancePanel = panel
	self:PopulateAppearanceRows(rowsContainer)
	table.insert(appearanceContainers, rowsContainer)
	return panel
end

-- Third native subcategory page - accent + background color swatches.
function O:BuildColorsPanel()
	if self.colorsPanel then return self.colorsPanel end

	local panel = CreateFrame("Frame")
	panel.name = "Colors"

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(GetPanelBg())

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

	local rowsContainer = MakeScrollingRowsContainer(panel, divider)
	panel.rowsContainer = rowsContainer

	self.colorsPanel = panel
	self:PopulateColorsRows(rowsContainer)
	table.insert(colorsContainers, rowsContainer)
	return panel
end

-- Builds a real sub-tab bar (Currencies / Goals) inside whatever parent is
-- given, anchored below topAnchor - used by BOTH the native Currencies
-- subcategory page and the standalone window's Currencies tab, so they
-- can't visually drift apart. Returns the wrapper frame (what the OUTER
-- tab/page system shows or hides as a unit) plus both inner containers.
local function BuildCurrenciesSubTabs(O, parent, topAnchor, bottomOffset)
	-- Direct children of `parent`, same as every other tab's content
	-- (General/Appearance/Colors/Diagnostics all anchor straight to the
	-- panel) - no extra wrapper frame layer.
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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

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

	local divider = BuildHeader(panel, function() self:ResetToDefaults() end)

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
	f:SetPoint("CENTER")
	-- DIALOG strata so it renders above other UI (confirmed via screenshot:
	-- the player unit frame's health bar was showing through the bottom of
	-- this window) - a plain frame defaults to MEDIUM otherwise.
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	f:SetBackdropColor(GetPanelBg())
	local sar, sag, sab = XComp.GetAccentColor()
	f:SetBackdropBorderColor(sar, sag, sab, 1)

	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

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

	local divider = BuildHeader(f, function() self:ResetToDefaults() end)

	-- Tabs run down the LEFT side with a vertical divider between them and
	-- the page content, matching the Esc-menu's own settings layout -
	-- replaces the old horizontal row across the top, which ran out of
	-- width once a 6th tab (Backup) got added.
	local sidebar = CreateFrame("Frame", nil, f)
	sidebar:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)
	sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 34)
	sidebar:SetWidth(100)

	local vDivider = f:CreateTexture(nil, "ARTWORK")
	vDivider:SetWidth(1)
	local var, vag, vab = XComp.GetAccentColor()
	vDivider:SetColorTexture(var, vag, vab, 1)
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
	local colorsContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	local currenciesWrapper, currencyContainer = BuildCurrenciesSubTabs(self, f, contentTop, 32)
	local diagnosticsContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	local backupContainer = MakeScrollingRowsContainer(f, contentTop, 32)
	f.generalContainer = generalContainer
	f.appearanceContainer = appearanceContainer
	f.colorsContainer = colorsContainer
	f.currenciesWrapper = currenciesWrapper
	f.currencyContainer = currencyContainer
	f.diagnosticsContainer = diagnosticsContainer
	f.backupContainer = backupContainer
	table.insert(generalContainers, generalContainer)
	table.insert(appearanceContainers, appearanceContainer)
	table.insert(colorsContainers, colorsContainer)
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
	for _, c in ipairs({ generalContainer, appearanceContainer, colorsContainer, currencyContainer, diagnosticsContainer, backupContainer }) do
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
		colorsContainer:GetParent():GetParent(),
		currenciesWrapper,
		diagnosticsContainer:GetParent():GetParent(),
		backupContainer:GetParent():GetParent(),
	}
	local labels = { "General", "Appearance", "Colors", "Currencies", "Diagnostics", "Backup" }
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
		tabs[i] = tab
		anchorTab = tab
	end

	local function ShowGeneralTab() ShowTab(1) end
	f.ShowGeneralTab = ShowGeneralTab

	f:Hide()
	self.standaloneFrame = f
	self:PopulateGeneralRows(generalContainer)
	self:PopulateAppearanceRows(appearanceContainer)
	self:PopulateColorsRows(colorsContainer)
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
		self:PopulateColorsRows(f.colorsContainer)
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

	local colorsPanel = self:BuildColorsPanel()
	Settings.RegisterCanvasLayoutSubcategory(category, colorsPanel, colorsPanel.name)

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
