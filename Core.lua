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
-- Fixed brand colors/fonts (2026-09-29 correction) - Compendium used to let
-- players override the accent and background color, and pick their own
-- font/outline/size, via a "Colors" settings page. Jason's own words: "take
-- out the background color and accent color, period... just leave it with
-- ours, ours is the default" - meaning not just a better default, the
-- override capability itself is gone. GetAccentColor()/GetBgColor() and the
-- TitleFont/BodyFont objects below remain the single source of truth every
-- file reads from (so the whole addon still re-themes from one place if
-- the brand colors ever change again), they just no longer consult
-- XComp_DB.accentColor/bgColor/text at all.
XComp.DEFAULT_ACCENT = { 0.4078, 0.0784, 0.0902 } -- #681417, dark brick red
function XComp.GetAccentColor()
	return XComp.DEFAULT_ACCENT[1], XComp.DEFAULT_ACCENT[2], XComp.DEFAULT_ACCENT[3]
end

-- Background fill color - separate from accent (borders/text) and separate
-- from the transparency slider (alpha only). Single source of truth so the
-- main tracker AND both settings windows stay visually consistent with each
-- other.
XComp.DEFAULT_BG = { 0.03, 0.028, 0.06 } -- #08070f, dark indigo
function XComp.GetBgColor()
	return XComp.DEFAULT_BG[1], XComp.DEFAULT_BG[2], XComp.DEFAULT_BG[3]
end

-- Fixed structural divider/border color - #101020, near-black indigo, from
-- the family-wide 2026-09-20 brand rollout. Every window's own OUTER border
-- and card/panel edges use this instead of the accent color, so the accent
-- reads clearly on titles/labels/buttons without recoloring every border in
-- the addon too. The ONE exception is the header divider directly under a
-- window's title, which stays the accent color.
XComp.DIVIDER_COLOR = { 0.0627, 0.0627, 0.1255 }

-- Fixed unselected-sidebar-link color - #323264, muted blue-gray, from the
-- same 2026-09-20 rollout. ONLY for an unselected link in a standalone
-- window's own sidebar (the Options window's General/Currencies/
-- Diagnostics/Backup tabs when they're not the active page) - selected
-- still uses the accent color, and this never applies to an ordinary
-- button elsewhere. Sidebar tabs used to fall back to the same accent color
-- as everything else, which read as "every tab is active at once" instead
-- of showing one clear current page.
XComp.SIDEBAR_UNSELECTED = { 0.196, 0.196, 0.392 }

-- Fixed title font - Cinzel Bold, the current go-forward brand pairing.
-- This is for every window's own fixed "Xal's Compendium" branded title
-- text specifically.
XComp.TITLE_FONT_PATH = "Interface\\AddOns\\XalsCompendium\\Fonts\\Cinzel-Bold.ttf"

-- Standard dark text shadow - used by fixed-branding titles (window
-- titles). Everything else readable gets its shadow from the shared font
-- objects instead.
function XComp.ApplyTextShadow(fontString)
	fontString:SetShadowOffset(1, -1)
	fontString:SetShadowColor(0, 0, 0, 1)
end

-------------------------------------------------
-- Shared readable-text fonts - Cinzel Bold for prominent text (section/type
-- headers, settings row names), Inter Regular for secondary text (item
-- labels, descriptions). Fixed, not player-customizable (see the note
-- above) - everything readable still draws from one of these two objects
-- via :SetFontObject() so the whole addon stays visually consistent from
-- one place, they just never change once set.
-------------------------------------------------
XComp.TitleFont = CreateFont("XalsCompendiumTitleFont")
XComp.BodyFont = CreateFont("XalsCompendiumBodyFont")

function XComp.ApplyFontSettings()
	XComp.TitleFont:SetFont(XComp.TITLE_FONT_PATH, 15, "OUTLINE")
	XComp.BodyFont:SetFont("Interface\\AddOns\\XalsCompendium\\Fonts\\Inter-Regular.ttf", 13, "")

	XComp.TitleFont:SetShadowOffset(1, -1)
	XComp.TitleFont:SetShadowColor(0, 0, 0, 1)
	XComp.BodyFont:SetShadowOffset(1, -1)
	XComp.BodyFont:SetShadowColor(0, 0, 0, 1)

	if XComp.UI and XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then
		XComp.UI:RefreshSections()
	end
end
-- Seeded immediately (not just at ADDON_LOADED) so anything using these
-- fonts before Core's own login handler runs never hits a "Font not set"
-- error - same guarantee the old stock-font seed gave, just pointed at the
-- real brand font from the start instead of a placeholder.
XComp.ApplyFontSettings()

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
f:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "CALENDAR_UPDATE_EVENT_LIST" then
		XComp.Data:ClearHolidayCache()
		if XComp.RefreshFloatingIcon then XComp.RefreshFloatingIcon() end
		if XComp.UI.mainFrame and XComp.UI.mainFrame:IsShown() then XComp.UI:RefreshSections() end
		return
	end
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
		-- Calendar data has to be requested from the server, and not while
		-- the client is still loading; CALENDAR_UPDATE_EVENT_LIST above
		-- re-checks holiday items once it arrives.
		C_Timer.After(10, function() C_Calendar.OpenCalendar() end)
		-- Floating icon (separate from the fixed minimap button) - set its
		-- initial state now, independent of whether the tracker window ever
		-- gets opened this session, then keep it current on a ticker so it
		-- reappears on its own the moment a daily/weekly reset happens
		-- without needing a relog.
		if XComp.RefreshFloatingIcon then
			XComp.RefreshFloatingIcon()
			C_Timer.NewTicker(600, function() XComp.RefreshFloatingIcon() end)
		end
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
				if XComp.RefreshFloatingIcon then XComp.RefreshFloatingIcon() end
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
