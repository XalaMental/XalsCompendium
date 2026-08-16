-- Xal's Compendium
-- Daily & weekly quest and activity tracker.
--
-- Core.lua creates the shared XComp table every other file attaches to,
-- and sets up SavedVariables defaults. Loaded first (see .toc).

XComp = XComp or {}

XComp_DB = XComp_DB or {}
XComp_CharDB = XComp_CharDB or {}

-- Hidden dev-only switch (2026-08-12) - the untracked-quest auto-detection
-- system (Data.lua/Core.lua/Options.lua/UI.lua) is OFF by default for
-- every install, including real CurseForge downloads. It only turns on via
-- this undocumented slash command - nothing in the settings UI, nothing in
-- the changelog references it. Explicit requirement: this is Xal's own
-- personal collection tool riding inside the same addon, not a player-facing
-- feature - it must do nothing at all unless deliberately switched on.
function XComp.IsDevMode()
	return XComp_DB.devMode == true
end

-------------------------------------------------
-- Shared theme
-------------------------------------------------
-- Default gold/copper accent (matches Craft Courier's C_ACCENT). Customizable
-- via XComp_DB.accentColor - GetAccentColor() is the single source of truth
-- every file should read from, so the whole addon re-themes consistently
-- rather than each file having its own hardcoded copy.
XComp.DEFAULT_ACCENT = { 0.72, 0.55, 0.22 }
function XComp.GetAccentColor()
	local c = XComp_DB.accentColor
	if c then return c[1], c[2], c[3] end
	return XComp.DEFAULT_ACCENT[1], XComp.DEFAULT_ACCENT[2], XComp.DEFAULT_ACCENT[3]
end

-- Background fill color - separate from accent (borders/text) and separate
-- from the transparency slider (alpha only). Single source of truth so the
-- main tracker AND both settings windows stay visually consistent with each
-- other instead of only one of them picking up a custom background.
XComp.DEFAULT_BG = { 0.035, 0.035, 0.035 }
function XComp.GetBgColor()
	local c = XComp_DB.bgColor
	if c then return c[1], c[2], c[3] end
	return XComp.DEFAULT_BG[1], XComp.DEFAULT_BG[2], XComp.DEFAULT_BG[3]
end

-- Standard dark text shadow - used only by the fixed-branding Morpheus
-- titles (window titles), which are NOT part of the customizable font
-- system below by design (the branded look stays fixed). Everything else
-- readable gets its shadow from the shared font objects instead.
function XComp.ApplyTextShadow(fontString)
	fontString:SetShadowOffset(1, -1)
	fontString:SetShadowColor(0, 0, 0, 1)
end

-------------------------------------------------
-- Customizable text (font, size, outline, shadow) - build-plan item, ported
-- from the exact working pattern already shipping in XalsQuestCompass
-- (FONT_OPTIONS/OUTLINE_OPTIONS tables, shared CreateFont() objects,
-- ApplyFontSettings with a pcall fallback). "Custom" points at this addon's
-- OWN Fonts/CustomFont.ttf - unlike Compass, no font file ships here by
-- default (that would mean copying someone else's licensed asset into a
-- second addon); drop your own .ttf there with that exact name to use it.
-------------------------------------------------
XComp.FONT_OPTIONS = {
	{ key = "FRIZQT", name = "Friz Quadrata (default)", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "ARIALN", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ key = "SKURRI", name = "Skurri", path = "Fonts\\SKURRI.TTF" },
	{ key = "MORPHEUS", name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ key = "CUSTOM", name = "Simply Sans Bold", path = "Interface\\AddOns\\XalsCompendium\\Fonts\\CustomFont.ttf" },
}

XComp.OUTLINE_OPTIONS = {
	{ key = "NONE", name = "None", flag = "" },
	{ key = "OUTLINE", name = "Outline", flag = "OUTLINE" },
	{ key = "THICKOUTLINE", name = "Thick Outline", flag = "THICKOUTLINE" },
}

function XComp.GetFontOption(key)
	for _, opt in ipairs(XComp.FONT_OPTIONS) do
		if opt.key == key then return opt end
	end
	return XComp.FONT_OPTIONS[1]
end

function XComp.GetOutlineOption(key)
	for _, opt in ipairs(XComp.OUTLINE_OPTIONS) do
		if opt.key == key then return opt end
	end
	return XComp.OUTLINE_OPTIONS[1]
end

-- Two shared font objects - everything readable draws from one of these via
-- :SetFontObject(), so a single settings change updates the whole addon at
-- once instead of touching dozens of individual FontStrings. TitleFont is
-- for prominent text (section/type headers, settings row names); BodyFont
-- is for secondary text (item labels, descriptions).
XComp.TitleFont = CreateFont("XalsCompendiumTitleFont")
XComp.BodyFont = CreateFont("XalsCompendiumBodyFont")
-- Seeded with a guaranteed-valid stock font immediately, so anything using
-- these before ApplyFontSettings() runs never hits a "Font not set" error.
XComp.TitleFont:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
XComp.BodyFont:SetFont("Fonts\\FRIZQT__.TTF", 11, "")

function XComp.ApplyFontSettings()
	XComp_DB.text = XComp_DB.text or {}
	local t = XComp_DB.text
	if t.fontKey == nil then t.fontKey = "CUSTOM" end
	if t.outlineKey == nil then t.outlineKey = "OUTLINE" end
	if t.fontSize == nil then t.fontSize = 13 end
	local opt = XComp.GetFontOption(t.fontKey)
	local outline = XComp.GetOutlineOption(t.outlineKey)
	local size = t.fontSize

	local ok = pcall(function()
		XComp.TitleFont:SetFont(opt.path, size + 2, outline.flag)
		XComp.BodyFont:SetFont(opt.path, math.max(8, size - 2), outline.flag)
	end)
	if not ok then
		-- Falls back to the default stock font if a custom/missing file was picked.
		local default = XComp.FONT_OPTIONS[1]
		XComp.TitleFont:SetFont(default.path, size + 2, outline.flag)
		XComp.BodyFont:SetFont(default.path, math.max(8, size - 2), outline.flag)
	end

	local shadowOn = t.shadowEnabled
	if shadowOn == nil then shadowOn = true end
	local sc = t.shadowColor or { 0, 0, 0 }
	XComp.TitleFont:SetShadowOffset(shadowOn and 1 or 0, shadowOn and -1 or 0)
	XComp.TitleFont:SetShadowColor(sc[1], sc[2], sc[3], shadowOn and 1 or 0)
	XComp.BodyFont:SetShadowOffset(shadowOn and 1 or 0, shadowOn and -1 or 0)
	XComp.BodyFont:SetShadowColor(sc[1], sc[2], sc[3], shadowOn and 1 or 0)

	if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
		XComp.UI:RefreshSections()
	end
end

-------------------------------------------------
-- Shared widgets
-------------------------------------------------
-- Standing design rule: every window's close control is a text/link-style
-- "Close" (not an icon X button), bottom-right. Shared here so every
-- window across the addon stays consistent instead of drifting apart.
function XComp.MakeCloseButton(parent, onClick)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(50, 20)
	btn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText("Close")
	local r, g, b = XComp.GetAccentColor()
	label:SetTextColor(r, g, b, 1)
	btn.label = label

	btn:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
	btn:SetScript("OnLeave", function()
		local ar, ag, ab = XComp.GetAccentColor()
		label:SetTextColor(ar, ag, ab, 1)
	end)
	btn:SetScript("OnClick", onClick or function() parent:Hide() end)

	return btn
end

-- Hand-drawn checkbox - Xal's shared brand checkbox (locked in 2026-08-12).
-- Blizzard's native UICheckButtonTemplate was confirmed rendering with its
-- bottom border missing entirely in-game, so every checkbox in the addon
-- uses this instead: same pixel-snapped 4-texture border technique as
-- MakeFlatButton (Options.lua), sourced from the addon's own live accent
-- color. Shared here (not duplicated in Options.lua) so UI.lua's checkboxes
-- can use it too. API differs slightly from a native CheckButton: set
-- cb.OnToggle instead of :SetScript("OnClick", ...) - the checked state is
-- already flipped by the time OnToggle runs, matching the native behavior
-- where GetChecked() reflects the NEW state inside OnClick.
function XComp.MakeCheckbox(parent, size)
	size = size or 22
	local cb = CreateFrame("Button", nil, parent)
	PixelUtil.SetSize(cb, size, size)

	-- Matches Quest Compass's Brand.MakeCheckbox exactly (2026-08-15
	-- correction - checked its real BrandStyle.lua: identical 4-texture
	-- border, same 2px LINE_THICKNESS floor, same 0.6 bg alpha). The
	-- checkbox was never actually "too thick" relative to the real
	-- reference addon - only relative to the mockup's browser-rendered
	-- checkbox, which no real addon in the suite matches.
	local bg = cb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

	local ar, ag, ab = XComp.GetAccentColor()

	local borderTop = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderTop, "TOPLEFT", cb, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderTop, "TOPRIGHT", cb, "TOPRIGHT", 0, 0)
	PixelUtil.SetHeight(borderTop, 2)
	borderTop:SetColorTexture(ar, ag, ab, 1)

	local borderBottom = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetHeight(borderBottom, 2)
	borderBottom:SetColorTexture(ar, ag, ab, 1)

	local borderLeft = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderLeft, "TOPLEFT", cb, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", cb, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetWidth(borderLeft, 2)
	borderLeft:SetColorTexture(ar, ag, ab, 1)

	local borderRight = cb:CreateTexture(nil, "ARTWORK")
	PixelUtil.SetPoint(borderRight, "TOPRIGHT", cb, "TOPRIGHT", 0, 0)
	PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
	PixelUtil.SetWidth(borderRight, 2)
	borderRight:SetColorTexture(ar, ag, ab, 1)

	-- Texture, not a FontString "X" - a font glyph's CENTER anchor centers
	-- against the font's full line-height box (ascender/descender padding
	-- included), not the glyph's actual ink, so it visually drifts off-true-
	-- center. Blizzard's own checkmark texture centers exactly where told,
	-- no font-metrics guesswork - confirmed 2026-08-13 on Quest Compass,
	-- now the standard everywhere.
	local check = cb:CreateTexture(nil, "OVERLAY")
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check:SetVertexColor(ar, ag, ab, 1)
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

-------------------------------------------------
-- Minimap button (LibDataBroker + LibDBIcon)
-------------------------------------------------
-- Left-click toggles the main tracker. Right-click opens the STANDALONE
-- settings window specifically (not the Blizzard-native one) - per the
-- locked requirement that the standalone window is the default/primary
-- settings menu.
-- Minimap icon art - own custom silhouette (parchment scroll + quill), not
-- Blizzard's circular mask. New filename on every revision (WoW's client
-- can cache a texture path even across /reload) - bump to _v2, _v3, etc.
-- if this ever needs a redo, don't overwrite this file in place.
local MINIMAP_ICON = "Interface\\AddOns\\XalsCompendium\\Textures\\MinimapIcon_v1.png"

local function RegisterMinimapButton()
	local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("XalsCompendium", {
		type = "launcher",
		text = "Xal's Compendium",
		icon = MINIMAP_ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				XComp.Options:ToggleStandalone()
			else
				XComp.UI:Toggle()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("Xal's Compendium")
			tooltip:AddLine("|cff999999Left-click|r to open the tracker")
			tooltip:AddLine("|cff999999Right-click|r to open settings")
		end,
	})

	XComp_DB.minimap = XComp_DB.minimap or { hide = false }
	local icon = LibStub("LibDBIcon-1.0")
	icon:Register("XalsCompendium", ldb, XComp_DB.minimap)

	-- Full custom shape (not Blizzard's circular mask) - confirmed technique,
	-- see project_addon_visual_brand.md's "Minimap icon technique" section.
	icon:SetButtonSize("XalsCompendium", 34)
	icon:RemoveButtonBorder("XalsCompendium")
	icon:RemoveButtonBackground("XalsCompendium")
	icon:SetButtonIcon("XalsCompendium", MINIMAP_ICON, 34, "CENTER", 0, 0)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local addonName = ...
		if addonName ~= "XalsCompendium" then return end
		f:UnregisterEvent("ADDON_LOADED")
		XComp.ApplyFontSettings()
		-- Roster snapshot BEFORE Options:Register() - the Alts settings page
		-- builds and populates itself as part of Register(), so if this ran
		-- after, the CURRENT character wouldn't have an entry yet the first
		-- time that page gets built (real bug: showed only other alts, never
		-- yourself, until something else happened to refresh it later).
		XComp.Data:UpdateRosterSnapshot()
		XComp.Options:Register()
		RegisterMinimapButton()
		XComp.Data:AutoBackupIfNeeded()
		-- Maintenance reminder (build-plan item 21) - checked once now, then
		-- on a recurring 30-minute ticker so it can still fire even if the
		-- tracker window never gets opened this session. CheckMaintenanceReminder
		-- itself no-ops unless reset is actually close AND weekly content is
		-- still incomplete AND it hasn't already reminded this cycle.
		XComp.Data:CheckMaintenanceReminder()
		C_Timer.NewTicker(1800, function() XComp.Data:CheckMaintenanceReminder() end)
		if XComp.WhatsNew then XComp.WhatsNew:CheckAndShow() end
		-- Untracked-quest auto-detection - dev-only, see XComp.IsDevMode
		-- above. Off for every real player by default; only runs at all
		-- once the hidden slash command has switched it on for this
		-- account. Delayed half a second - the quest log isn't always
		-- fully populated the instant ADDON_LOADED fires.
		--
		-- NO LONGER auto-injects into the live tracker's "Custom" category
		-- (2026-08-16 correction - redundant with, and confusing next to,
		-- the separate Untracked Export report button that already exists
		-- for reviewing these; detected quests still populate that report,
		-- they just don't also clutter the real visible list anymore).
		if XComp.IsDevMode() then
			C_Timer.After(0.5, function()
				XComp.Data:ScanQuestLogForUntracked()
			end)
		end
	elseif event == "QUEST_ACCEPTED" then
		-- Live catch for anything accepted DURING this session, same
		-- detection as the login scan above - dev-only, same gate.
		if not XComp.IsDevMode() then return end
		local questID = ...
		XComp.Data:CheckQuestForCatalog(questID)
	elseif event == "QUEST_TURNED_IN" then
		-- Completion popup while the window's closed (build-plan item 10) -
		-- match the turned-in quest against the catalog; if it's a tracked
		-- item, either live-refresh the window (if open) or show the toast
		-- (if not), same as a manual checkbox click already does for the
		-- open-window case.
		local questID = ...
		local item = XComp.Data:FindItemByQuestID(questID)
		if item then
			if XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
				XComp.UI:RefreshSections()
			else
				XComp.UI:ShowCompletionToast("Completed: " .. item.name)
			end
		end
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		-- Currency goal popup (build-plan item 14 extension) - verified
		-- against Warcraft Wiki: fires with (currencyType, quantity,
		-- quantityChange, quantityGainSource, destroyReason), quantity
		-- being the new post-change total. Checks only the 3 fixed goal
		-- slots (Options -> Currency Goals), not every tracked currency.
		local currencyType, quantity = ...
		local slots = XComp_DB.settings and XComp_DB.settings.currencyGoalSlots
		if slots then
			for _, slot in ipairs(slots) do
				if slot.currencyID == currencyType and slot.goal and slot.goal > 0 then
					XComp_DB.currencyGoalsReached = XComp_DB.currencyGoalsReached or {}
					if quantity >= slot.goal then
						if not XComp_DB.currencyGoalsReached[currencyType] then
							XComp_DB.currencyGoalsReached[currencyType] = true
							local info = C_CurrencyInfo.GetCurrencyInfo(currencyType)
							local name = info and info.name or ("Currency " .. currencyType)
							XComp.UI:ShowCompletionToast(string.format("Goal reached: %s (%d)", name, slot.goal))
						end
					else
						-- Dropped back below goal (spent it) - allow re-notifying later.
						XComp_DB.currencyGoalsReached[currencyType] = nil
					end
				end
			end
		end
	end
end)

SLASH_XALSCOMPENDIUM1 = "/xcp"
SlashCmdList["XALSCOMPENDIUM"] = function(msg)
	if msg == "options" then
		XComp.Options:ToggleStandalone()
	elseif msg == "diag" then
		XComp.UI:ShowDiagnostics()
	elseif msg == "devmode" then
		-- Hidden, undocumented toggle for the dev-only auto-detection
		-- system - deliberately not listed anywhere in help text, settings,
		-- or the changelog. See XComp.IsDevMode above.
		XComp_DB.devMode = not XComp_DB.devMode
		print("|cff999999Xal's Compendium:|r dev mode " .. (XComp_DB.devMode and "ON" or "OFF"))
	else
		XComp.UI:Toggle()
	end
end
