-- Xal's Compendium
-- UI.lua holds the main tracker window.
--
-- Visual style locked in during design discussion: dark charcoal panel,
-- thin gold/copper border, Morpheus-font header with a gold divider line
-- beneath it, clean rounded-border buttons (built in Options.lua/UI.lua
-- as sections get rendered). Default position is the left side of the
-- screen (right side is already crowded by the default Blizzard UI), all
-- sections collapsed on first install.

XComp.UI = XComp.UI or {}
local U = XComp.UI

-------------------------------------------------
-- Theme
-------------------------------------------------
-- Background color reads from XComp.GetBgColor() (Core.lua, customizable
-- via the Colors settings page) - its ALPHA is a separate customizable
-- slider. Accent color reads from XComp.GetAccentColor() (Core.lua) so it
-- can be customized too.
local function GetBgAlpha()
	local a = XComp_DB.settings and XComp_DB.settings.bgAlpha
	if a == nil then return 0.95 end
	return a
end

local function IsFrameless()
	return XComp_DB.settings and XComp_DB.settings.frameless
end

local FRAME_W, FRAME_H = 380, 480
local ROW_INSET = 12

-- The manual-completion confirm popup (see GetCompletePopup/ShowCompletePopup
-- below) - declared up here so CreateMainFrame's OnHide handler can close it
-- too, alongside every other place that already does (RefreshSections).
local completePopup

-- Shared hover handling for the fade-when-idle behavior - called from BOTH
-- the main frame's OnEnter/OnLeave and the side strip's (see
-- CreateSideStrip), so moving the mouse onto the side strip counts as
-- still hovering the window instead of triggering a fade-out. Hold/fade
-- durations increased 2026-08-16 (explicit request: the previous 0.5s
-- hold read as "almost instant").
local HOVER_FADE_HOLD = 5
local HOVER_FADE_DURATION = 0.4

function U:HandleHoverEnter()
	local f = self.mainFrame
	if not f then return end
	f.fadeOutToken = nil
	f:SetAlpha(1)
end

function U:HandleHoverLeave()
	local f = self.mainFrame
	if not f then return end
	local token = {}
	f.fadeOutToken = token
	C_Timer.After(HOVER_FADE_HOLD, function()
		if f.fadeOutToken ~= token then return end
		if f:IsMouseOver() then return end
		-- sideStrip lives on the UI object (self), not on the frame table -
		-- checking f.sideStrip here was always nil, the real bug.
		if self.sideStrip and self.sideStrip:IsShown() and self.sideStrip:IsMouseOver() then return end
		local idle = (XComp_DB.settings and XComp_DB.settings.idleAlpha) or 0
		UIFrameFadeOut(f, HOVER_FADE_DURATION, f:GetAlpha(), idle)
	end)
end

-------------------------------------------------
-- Main window
-------------------------------------------------
function U:CreateMainFrame()
	if self.mainFrame then return self.mainFrame end

	local f = CreateFrame("Frame", "XalsCompendiumMainFrame", UIParent, "BackdropTemplate")
	-- Registering the frame's global name here makes Blizzard's own Escape-key
	-- handling close it, same as every other UI panel in the game - no custom
	-- key-binding code needed.
	tinsert(UISpecialFrames, "XalsCompendiumMainFrame")
	f:SetSize(FRAME_W, FRAME_H)
	f:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
	-- DIALOG strata so it renders above other UI (confirmed via screenshot:
	-- the player unit frame's health bar was showing through the bottom of
	-- the standalone Options window - same fix applied here for
	-- consistency) - a plain frame defaults to MEDIUM otherwise.
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})

	-- Panel background art (2026-08-15) - dark green swirl texture sitting
	-- on top of the flat backdrop color, below everything else (border,
	-- dividers, text all draw at ARTWORK/OVERLAY, above this BORDER-layer
	-- texture). Tested stretched across the full resize range (280x200 to
	-- 380x800) with no visible distortion, since the source art is soft/
	-- low-detail enough that directional stretching doesn't show. Hidden
	-- in frameless mode and its own alpha follows the same Background
	-- Transparency slider as everything else - see ApplyTheme below.
	local bgImage = f:CreateTexture(nil, "BORDER")
	bgImage:SetAllPoints(f)
	bgImage:SetTexture("Interface\\AddOns\\XalsCompendium\\Textures\\PanelBackground.jpg")
	f.bgImage = bgImage

	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if not XComp_DB.settings or not XComp_DB.settings.locked then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	-- Corner-handle resizing, gated on holding Shift while dragging - a
	-- safeguard against accidental resizes during normal use.
	f:SetResizable(true)
	f:SetResizeBounds(280, 200, 600, 800)
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

	local title = f:CreateFontString(nil, "OVERLAY")
	title:SetFont("Interface\\AddOns\\XalsCompendium\\Fonts\\CustomFont.ttf", 20, "")
	title:SetPoint("TOP", f, "TOP", 0, -16)
	title:SetText("Xal's Compendium")
	XComp.ApplyTextShadow(title)
	f.title = title

	-- Minimize button - collapses the tracker down to a small "D: x  W: y"
	-- pill in the same spot, for tucking it out of the way (SilverDragon's
	-- minimized bar was the explicit reference, 2026-08-12). Text/link style,
	-- same convention as XComp.MakeCloseButton.
	local minimizeBtn = CreateFrame("Button", nil, f)
	minimizeBtn:SetSize(20, 20)
	minimizeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
	local minimizeLabel = minimizeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	minimizeLabel:SetPoint("CENTER")
	minimizeLabel:SetText("-")
	do
		local mr, mg, mb = XComp.GetAccentColor()
		minimizeLabel:SetTextColor(mr, mg, mb, 1)
	end
	minimizeBtn.label = minimizeLabel
	minimizeBtn:SetScript("OnEnter", function() minimizeLabel:SetTextColor(1, 1, 1, 1) end)
	minimizeBtn:SetScript("OnLeave", function()
		local ar2, ag2, ab2 = XComp.GetAccentColor()
		minimizeLabel:SetTextColor(ar2, ag2, ab2, 1)
	end)
	minimizeBtn:SetScript("OnClick", function() U:ToggleMinimized() end)
	f.minimizeBtn = minimizeBtn

	-- Minimized-state label ("D: x   W: y") - only shown while minimized,
	-- replaces the whole scroll/content area.
	local minimizedLabel = f:CreateFontString(nil, "OVERLAY")
	minimizedLabel:SetFontObject(XComp.TitleFont)
	minimizedLabel:SetPoint("LEFT", f, "LEFT", 16, 0)
	minimizedLabel:SetJustifyH("LEFT")
	XComp.ApplyTextShadow(minimizedLabel)
	minimizedLabel:Hide()
	f.minimizedLabel = minimizedLabel

	-- Overall total, since sections start collapsed by default - this is
	-- the only at-a-glance progress view without expanding anything.
	local overall = f:CreateFontString(nil, "OVERLAY")
	overall:SetFontObject(XComp.BodyFont)
	overall:SetPoint("TOP", title, "BOTTOM", 0, -4)
	f.overallLabel = overall

	-- Hide-completed toggle - moved to a bottom-left text-link button
	-- (2026-08-15, explicit request: "the header section should be a
	-- clean visual look") instead of a checkbox+label sitting under the
	-- title. Same text/link style as XComp.MakeCloseButton, mirrored to
	-- the opposite bottom corner.
	local filterToggle = CreateFrame("Button", nil, f)
	filterToggle:SetSize(110, 20)
	filterToggle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 8)
	local filterToggleLabel = filterToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	filterToggleLabel:SetPoint("LEFT")
	filterToggle.label = filterToggleLabel
	local function RefreshFilterToggleLabel()
		local hidden = XComp_DB.settings and XComp_DB.settings.hideCompleted
		filterToggleLabel:SetText(hidden and "Show completed" or "Hide completed")
	end
	RefreshFilterToggleLabel()
	local far, fag, fab = XComp.GetAccentColor()
	filterToggleLabel:SetTextColor(far, fag, fab, 1)
	filterToggle:SetScript("OnEnter", function() filterToggleLabel:SetTextColor(1, 1, 1, 1) end)
	filterToggle:SetScript("OnLeave", function()
		local ar2, ag2, ab2 = XComp.GetAccentColor()
		filterToggleLabel:SetTextColor(ar2, ag2, ab2, 1)
	end)
	filterToggle:SetScript("OnClick", function()
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.hideCompleted = not XComp_DB.settings.hideCompleted
		RefreshFilterToggleLabel()
		U:RefreshSections()
	end)
	f.filterToggle = filterToggle

	local divider = f:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -68)
	divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -68)
	f.divider = divider

	-- View tabs (Daily / Weekly / Legacy) - replaces the old Tier/Type
	-- collapsible-arrow tree and the roster-refresh/ilvl icon row entirely
	-- (rebuilt 2026-08-15, explicit correction: tabs belong below the
	-- divider, not in the header; ilvl and the manual roster-refresh button
	-- are cut, both redundant/fluff - ilvl duplicates the C keybind, and
	-- the refresh button duplicates what RefreshSections already does
	-- automatically on every redraw). Great Vault/currencies moved to the
	-- separate side strip (see CreateSideStrip below), not a tab at all.
	-- Only one view renders at a time; the subtitle above shows that view's
	-- own completion count, not a combined total.
	local TAB_DEFS = {
		{ key = "daily", label = "Daily" },
		{ key = "weekly", label = "Weekly" },
		{ key = "legacy", label = "Legacy" },
	}
	local tabRow = CreateFrame("Frame", nil, f)
	tabRow:SetSize(200, 20)
	tabRow:SetPoint("TOP", divider, "BOTTOM", 0, -8)
	local tabButtons = {}
	local function RefreshTabHighlight()
		local selected = (XComp_DB.settings and XComp_DB.settings.selectedType) or "weekly"
		local ar3, ag3, ab3 = XComp.GetAccentColor()
		for _, tb in ipairs(tabButtons) do
			if tb.key == selected then
				tb.label:SetTextColor(1, 1, 1, 1)
			else
				tb.label:SetTextColor(ar3, ag3, ab3, 0.6)
			end
		end
	end
	local prevTab
	for _, def in ipairs(TAB_DEFS) do
		local tb = CreateFrame("Button", nil, tabRow)
		tb.key = def.key
		local lbl = tb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetText(def.label)
		tb.label = lbl
		tb:SetSize(lbl:GetStringWidth() + 12, 20)
		lbl:SetPoint("CENTER")
		if prevTab then
			tb:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
		else
			tb:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
		end
		tb:SetScript("OnClick", function()
			XComp_DB.settings = XComp_DB.settings or {}
			XComp_DB.settings.selectedType = def.key
			RefreshTabHighlight()
			U:RefreshSections()
		end)
		table.insert(tabButtons, tb)
		prevTab = tb
	end
	f.tabRow = tabRow
	f.RefreshTabHighlight = RefreshTabHighlight
	RefreshTabHighlight()

	-- Sections render inside a real scroll frame, not a plain container -
	-- content that exceeds the visible area scrolls instead of spilling
	-- outside the window border (confirmed bug with the earlier plain-
	-- container + auto-resize-only approach). Plain ScrollFrame, NOT
	-- UIPanelScrollFrameTemplate (2026-08-15 correction - Blizzard's default
	-- arrow-button scrollbar was already explicitly rejected once, in Quest
	-- Compass: see its CreateScrollableSection helper in
	-- XalsQuestCompass.lua, "NOT Blizzard's default arrow-button scrollbar
	-- (explicitly disliked)"). Ported the same thin custom scrollbar here
	-- instead of Blizzard's template, for consistency across the addon
	-- suite.
	local scrollFrame = CreateFrame("ScrollFrame", "XalsCompendiumScrollFrame", f)
	scrollFrame:SetPoint("TOPLEFT", tabRow, "BOTTOMLEFT", 0, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 40)

	-- Thin custom scrollbar (ported from Quest Compass's CreateScrollableSection)
	-- - a native Slider drives the actual scroll position, restyled to a
	-- thin accent-gold thumb with no track background and no arrow buttons.
	-- Auto-hides when content fits without scrolling.
	local scrollTrack = CreateFrame("Frame", nil, f, "BackdropTemplate")
	scrollTrack:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 10, 0)
	scrollTrack:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 10, 0)
	scrollTrack:SetWidth(8)
	scrollTrack:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	scrollTrack:SetBackdropColor(1, 1, 1, 0.08)
	scrollTrack:Hide()

	local scrollThumb = CreateFrame("Slider", nil, scrollTrack)
	scrollThumb:SetOrientation("VERTICAL")
	scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
	scrollThumb:SetPoint("BOTTOM", scrollTrack, "BOTTOM", 0, 0)
	scrollThumb:SetWidth(8)
	scrollThumb:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
	local scrollThumbTex = scrollThumb:GetThumbTexture()
	do
		local sar, sag, sab = XComp.GetAccentColor()
		scrollThumbTex:SetVertexColor(sar, sag, sab, 1)
	end
	scrollThumbTex:SetWidth(8)

	local suppressScrollCallback = false
	scrollThumb:SetScript("OnValueChanged", function(self, value)
		if suppressScrollCallback then return end
		scrollFrame:SetVerticalScroll(value)
	end)
	f.scrollTrack = scrollTrack
	f.scrollThumb = scrollThumb

	-- Width tracks the scroll frame automatically via anchors (including
	-- if the window itself gets resized wider/narrower via the corner
	-- grip); height is set manually in RefreshSections based on actual
	-- content, since ScrollFrame needs an explicit child height to know
	-- how far there is to scroll.
	--
	-- ROW_INSET bakes a consistent margin into a "content" frame nested
	-- INSIDE the real scroll child, not into the scroll child itself -
	-- confirmed via debug output that ScrollFrame:SetScrollChild() silently
	-- overrides any position anchor given to the child (only width changes
	-- go through), so the real scroll child must stay flush at (0,0) and
	-- full width; only this inner content frame gets offset. Every row
	-- anchors to the CONTENT frame's edges at 0, so it automatically gets
	-- the margin without needing to know about it.
	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
	scrollChild:SetWidth(scrollFrame:GetWidth())
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)
	scrollFrame:SetScript("OnSizeChanged", function(self, width) scrollChild:SetWidth(width) end)

	-- Mouse wheel scrolling isn't automatic for a scroll frame built via
	-- CreateFrame in Lua - UIPanelScrollFrameTemplate only wires it up for
	-- XML-defined instances. Confirmed real bug elsewhere in the addon
	-- (Options.lua's Currencies page) - fixed here too for consistency.
	-- Moves the thumb (its OnValueChanged then drives the actual scroll),
	-- same as Quest Compass's CreateScrollableSection.
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		scrollThumb:SetValue(scrollThumb:GetValue() - delta * 40)
	end)

	-- Called after content is (re)built and the window's final height is
	-- set, so the thumb's range/size reflects the real visible area.
	function f.UpdateScrollRange()
		local visibleHeight = scrollFrame:GetHeight()
		local contentHeight = scrollChild:GetHeight()
		local maxScroll = math.max(0, contentHeight - visibleHeight)
		suppressScrollCallback = true
		scrollThumb:SetMinMaxValues(0, maxScroll)
		scrollThumb:SetValue(0)
		suppressScrollCallback = false
		scrollFrame:SetVerticalScroll(0)
		if maxScroll > 0 then
			scrollTrack:Show()
			local ratio = math.min(1, visibleHeight / contentHeight)
			scrollThumbTex:SetHeight(math.max(20, visibleHeight * ratio))
		else
			scrollTrack:Hide()
		end
	end

	local sectionsContent = CreateFrame("Frame", nil, scrollChild)
	sectionsContent:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", ROW_INSET, -ROW_INSET)
	sectionsContent:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -ROW_INSET, -ROW_INSET)
	sectionsContent:SetHeight(1)
	hooksecurefunc(sectionsContent, "SetHeight", function(self, height)
		scrollChild:SetHeight(height + ROW_INSET * 2)
	end)

	f.scrollFrame = scrollFrame
	f.sectionsContainer = sectionsContent

	-- Text/link-style close button, bottom-right - the standing convention
	-- for every window in this addon (see XComp.MakeCloseButton in Core.lua).
	-- Nudged further left than the default position here specifically,
	-- since this window (unlike the standalone settings window) also has
	-- a resize grip occupying the very corner.
	local closeBtn = XComp.MakeCloseButton(f)
	closeBtn:ClearAllPoints()
	closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 8)
	f.closeBtn = closeBtn

	-- Fade-to-transparent when the mouse isn't over the window (explicit
	-- request 2026-08-12) - always snaps to full opacity on hover; the
	-- non-hover target opacity is the player-adjustable Idle Opacity slider
	-- (Options.lua Appearance page), default 0 (fully invisible). Wired to
	-- BOTH the main frame and the side strip (see CreateSideStrip) via
	-- U:HandleHoverEnter/Leave below - moving onto the side strip counts as
	-- still hovering the window, and leaving either one starts the same
	-- fade countdown (2026-08-16 correction: the side strip wasn't
	-- included before, so mousing over its icons made the window vanish).
	f:SetScript("OnEnter", function() U:HandleHoverEnter() end)
	f:SetScript("OnLeave", function() U:HandleHoverLeave() end)

	-- Closes the complete-confirm popup no matter HOW the window closes
	-- (the "Close" button, Escape, or U:Toggle all end up here) - same real
	-- bug as the RefreshSections fix above, just covering every hide path
	-- at once instead of each one individually.
	f:SetScript("OnHide", function()
		if completePopup then
			completePopup:Hide()
			completePopup.openForUID = nil
		end
	end)

	f:Hide()
	self.mainFrame = f
	self:ApplyTheme()
	self:ApplyIdleAlpha()
	self:ApplyMinimizedState()
	return f
end

-- Sets the window's alpha to fully opaque if the mouse is currently over it,
-- otherwise to the player's configured Idle Opacity (default 0). Callable
-- both from the OnLeave script above and live from the settings slider.
function U:ApplyIdleAlpha()
	local f = self.mainFrame
	if not f then return end
	if f:IsMouseOver() then
		f:SetAlpha(1)
	else
		local idle = (XComp_DB.settings and XComp_DB.settings.idleAlpha) or 0
		f:SetAlpha(idle)
	end
end

-- Collapses the tracker down to a small "D: x   W: y" pill in the same spot
-- (minimize button toggles this) - everything except the minimize/close
-- buttons and the D/W label hides, and the window shrinks to fit. Persisted
-- in XComp_DB.settings.minimized so it stays minimized across reloads.
function U:ApplyMinimizedState()
	local f = self.mainFrame
	if not f then return end
	local minimized = XComp_DB.settings and XComp_DB.settings.minimized

	local fullElements = {
		f.title, f.overallLabel, f.tabRow, f.filterToggle, f.divider,
		f.scrollFrame, f.resizeGrip, f.closeBtn,
	}
	-- Not part of fullElements below - its Show/Hide is driven by whether
	-- content actually overflows (UpdateScrollRange), not just minimized
	-- state, so a blanket Show() here would undo that auto-hide.
	if f.scrollTrack and minimized then
		f.scrollTrack:Hide()
	end

	for _, el in ipairs(fullElements) do
		if el then
			if minimized then el:Hide() else el:Show() end
		end
	end
	if self.sideStrip then
		local stripEnabled = not (XComp_DB.settings and XComp_DB.settings.showSideStrip == false)
		if minimized or not stripEnabled then
			self.sideStrip:Hide()
		else
			self.sideStrip:Show()
		end
	end

	if minimized then
		local dailyLeft, weeklyLeft = XComp.Data:GetDailyWeeklyLeft()
		f.minimizedLabel:SetText(string.format("D: %d   W: %d", dailyLeft, weeklyLeft))
		f.minimizedLabel:Show()
		f.minimizeBtn.label:SetText("+")
		-- Only actually resize on the transition INTO minimized, not on
		-- every RefreshSections call while already minimized - avoids
		-- fighting anything else that might touch the frame's size.
		if not f._minimized then
			f:SetSize(190, 36)
		end
	else
		f.minimizedLabel:Hide()
		f.minimizeBtn.label:SetText("-")
		-- Same idea: only resize back on the transition OUT of minimized -
		-- doing this unconditionally every refresh would fight both the
		-- corner-drag resize and the auto-size-to-content logic below.
		if f._minimized then
			f:SetSize(FRAME_W, FRAME_H)
		end
	end
	f._minimized = minimized
end

function U:ToggleMinimized()
	XComp_DB.settings = XComp_DB.settings or {}
	XComp_DB.settings.minimized = not XComp_DB.settings.minimized
	self:ApplyMinimizedState()
end

-- Re-applies frameless mode, background transparency, accent color, and
-- window scale - callable both at creation and live whenever an
-- appearance setting changes, so Options.lua doesn't need to know the
-- frame's internals.
function U:ApplyTheme()
	local f = self.mainFrame
	if not f then return end

	local ar, ag, ab = XComp.GetAccentColor()

	if IsFrameless() then
		f:SetBackdropColor(0, 0, 0, 0)
		f:SetBackdropBorderColor(0, 0, 0, 0)
		if f.bgImage then f.bgImage:Hide() end
	else
		local br, bg, bb = XComp.GetBgColor()
		f:SetBackdropColor(br, bg, bb, GetBgAlpha())
		f:SetBackdropBorderColor(ar, ag, ab, 1)
		if f.bgImage then
			f.bgImage:Show()
			f.bgImage:SetAlpha(GetBgAlpha())
		end
	end

	f.title:SetTextColor(ar, ag, ab, 1)
	f.divider:SetColorTexture(ar, ag, ab, IsFrameless() and 0 or 1)

	-- Scale: uniformly zooms the ENTIRE window (text, icons, spacing, all
	-- of it) via native Frame:SetScale, distinct from the corner-drag
	-- resize (which only changes width/height, not the size of contents).
	local scale = (XComp_DB.settings and XComp_DB.settings.scale) or 1
	f:SetScale(scale)

	self:ApplySideStripTheme()
end

-------------------------------------------------
-- Side strip: Great Vault + tracked currencies (2026-08-15, explicit
-- request) - a separate narrow panel outside the main window's right edge,
-- not a tab and not inside the scrollable content, so it's never affected
-- by list length or the scrollbar/resize grip. Toggled entirely off via
-- Options for players who only want quest content. Parented to the main
-- frame, so it shows/hides for free whenever the main frame does (a child
-- frame's effective visibility already follows its parent's) - no extra
-- wiring needed in U:Toggle.
-------------------------------------------------
local SIDE_ICON_SIZE = 28
local SIDE_ICON_GAP = 8

local function IsSideStripEnabled()
	return not (XComp_DB.settings and XComp_DB.settings.showSideStrip == false)
end

function U:CreateSideStrip()
	if self.sideStrip then return self.sideStrip end
	local main = self:CreateMainFrame()

	-- Sized to hug its own icon content, NOT stretched to match the main
	-- window's full height (that was a real bug - a tall near-empty box
	-- next to a short icon list). Height is set explicitly in
	-- RefreshSideStrip once the icon count is known.
	local strip = CreateFrame("Frame", "XalsCompendiumSideStrip", main, "BackdropTemplate")
	strip:SetSize(SIDE_ICON_SIZE + 16, SIDE_ICON_SIZE + 16)
	strip:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
	strip:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	strip.icons = {}

	-- Counts as hovering the main window too (see U:HandleHoverEnter/Leave
	-- above) - without this, moving the mouse onto the strip's icons made
	-- the whole window fade out from under it.
	strip:EnableMouse(true)
	strip:SetScript("OnEnter", function() U:HandleHoverEnter() end)
	strip:SetScript("OnLeave", function() U:HandleHoverLeave() end)

	self.sideStrip = strip
	return strip
end

function U:ApplySideStripTheme()
	local strip = self.sideStrip
	if not strip then return end
	local ar, ag, ab = XComp.GetAccentColor()
	if IsFrameless() then
		strip:SetBackdropColor(0, 0, 0, 0)
		strip:SetBackdropBorderColor(0, 0, 0, 0)
	else
		local br, bg, bb = XComp.GetBgColor()
		strip:SetBackdropColor(br, bg, bb, GetBgAlpha())
		strip:SetBackdropBorderColor(ar, ag, ab, 1)
	end
end

local function MakeSideIcon(strip, texture, anchorTo)
	local btn = CreateFrame("Button", nil, strip)
	btn:SetSize(SIDE_ICON_SIZE, SIDE_ICON_SIZE)
	if anchorTo then
		btn:SetPoint("TOP", anchorTo, "BOTTOM", 0, -SIDE_ICON_GAP)
	else
		btn:SetPoint("TOP", strip, "TOP", 0, -8)
	end
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	if texture then icon:SetTexture(texture) end
	btn.icon = icon
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	-- HookScript, not SetScript - every caller sets its own OnEnter/OnLeave
	-- for the tooltip right after this returns, which would otherwise wipe
	-- out a plain SetScript here. Hooked scripts run alongside whatever the
	-- caller sets later, so this survives (2026-08-16 fix: the strip's own
	-- parent-level OnEnter wasn't reliably keeping the window visible while
	-- actually hovering an icon button on top of it - wiring it directly to
	-- every button removes that dependency entirely).
	btn:HookScript("OnEnter", function() U:HandleHoverEnter() end)
	btn:HookScript("OnLeave", function() U:HandleHoverLeave() end)

	return btn
end

-- Rebuilds the icon list (vault + whichever currencies are tracked) - cheap
-- enough to just do a full rebuild alongside RefreshSections rather than
-- diffing, same approach the main content list already uses.
function U:RefreshSideStrip()
	local strip = self:CreateSideStrip()
	self:ApplySideStripTheme()

	if not IsSideStripEnabled() then
		strip:Hide()
		return
	end
	strip:Show()

	for _, btn in ipairs(strip.icons) do
		btn:Hide()
		btn:SetParent(nil)
	end
	strip.icons = {}

	local anchorTo = nil

	local vaultLines = XComp.Data:GetVaultProgress()
	if #vaultLines > 0 then
		local vaultBtn = MakeSideIcon(strip, nil, anchorTo)
		-- Gold/unlocked variant (2026-08-16 correction) - the gray "locked"
		-- atlas read as a dim, washed-out icon. Real atlas either way, from
		-- Blizzard's own Blizzard_WeeklyRewards.lua source.
		vaultBtn.icon:SetAtlas("evergreen-weeklyrewards-reward-unlocked")
		vaultBtn:SetScript("OnClick", function()
			if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
				C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
			end
			if WeeklyRewardsFrame:IsShown() then
				WeeklyRewardsFrame:Hide()
			else
				WeeklyRewardsFrame:Show()
			end
		end)
		vaultBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Great Vault")
			for _, v in ipairs(vaultLines) do
				local vaultText = string.format("%s: %d/%d%s", v.label, v.progress, v.threshold, v.filled and " (filled)" or "")
				GameTooltip:AddLine(vaultText, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		vaultBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		table.insert(strip.icons, vaultBtn)
		anchorTo = vaultBtn
	end

	local currencyLines = XComp.Data:GetTrackedCurrencies()
	for _, c in ipairs(currencyLines) do
		local curBtn = MakeSideIcon(strip, c.iconFileID, anchorTo)
		curBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local curText
			if c.canEarnPerWeek and c.maxWeeklyQuantity and c.maxWeeklyQuantity > 0 then
				curText = string.format("%s: %d (%d/%d this week)", c.name, c.quantity, c.quantityEarnedThisWeek or 0, c.maxWeeklyQuantity)
			else
				curText = string.format("%s: %d", c.name, c.quantity)
			end
			GameTooltip:SetText(curText)
			GameTooltip:Show()
		end)
		curBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		table.insert(strip.icons, curBtn)
		anchorTo = curBtn
	end

	local iconCount = #strip.icons
	if iconCount == 0 then
		strip:Hide()
	else
		strip:Show()
		strip:SetHeight(8 + (iconCount * SIDE_ICON_SIZE) + ((iconCount - 1) * SIDE_ICON_GAP) + 8)
	end
end

-------------------------------------------------
-- Completion popup while the tracker window is closed (build-plan item 10)
-- - a small, self-fading toast so a tracked quest completing doesn't go
-- unnoticed just because the window wasn't open. Standard native
-- C_Timer/UIFrameFadeOut APIs, not a custom animation system.
-------------------------------------------------
function U:ShowCompletionToast(text)
	local toast = self.toastFrame
	if not toast then
		toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		toast:SetSize(280, 50)
		toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
		toast:SetFrameStrata("HIGH")
		toast:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		local tbr, tbg, tbb = XComp.GetBgColor()
		toast:SetBackdropColor(tbr, tbg, tbb, 0.95)

		local label = toast:CreateFontString(nil, "OVERLAY")
		label:SetFontObject(XComp.TitleFont)
		label:SetPoint("CENTER")
		label:SetWidth(260)
		label:SetJustifyH("CENTER")
		toast.label = label

		self.toastFrame = toast
	end

	local ar, ag, ab = XComp.GetAccentColor()
	toast:SetBackdropBorderColor(ar, ag, ab, 1)
	toast.label:SetTextColor(ar, ag, ab, 1)
	toast.label:SetText(text)
	toast:SetAlpha(1)
	toast:Show()

	if toast.fadeTimer then toast.fadeTimer:Cancel() end
	toast.fadeTimer = C_Timer.NewTimer(3, function()
		UIFrameFadeOut(toast, 1, toast:GetAlpha(), 0)
	end)
end

-------------------------------------------------
-- Diagnostic report window (build-plan item 12) - a copyable multi-line
-- report (/xcp diag). Standard EditBox-nested-in-ScrollFrame "export
-- string" pattern used broadly across WoW addons for copyable text - the
-- EditBox is the scroll child itself, so (same lesson as the row-padding
-- bug) only its WIDTH is set explicitly; no position anchor is fought with
-- SetScrollChild.
-------------------------------------------------
function U:ShowDiagnostics()
	local lines = XComp.Data:RunDiagnostics()
	local text = table.concat(lines, "\n")

	local f = self.diagFrame
	if not f then
		f = CreateFrame("Frame", "XalsCompendiumDiagFrame", UIParent, "BackdropTemplate")
		tinsert(UISpecialFrames, "XalsCompendiumDiagFrame")
		f:SetSize(560, 440)
		-- Staggered off dead-center - see the "Default window position"
		-- rule in the shared brand-style memory.
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		local br, bg, bb = XComp.GetBgColor()
		f:SetBackdropColor(br, bg, bb, 0.97)
		local ar, ag, ab = XComp.GetAccentColor()
		f:SetBackdropBorderColor(ar, ag, ab, 1)

		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)

		local title = f:CreateFontString(nil, "OVERLAY")
		title:SetFont("Interface\\AddOns\\XalsCompendium\\Fonts\\CustomFont.ttf", 18, "")
		title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
		title:SetTextColor(ar, ag, ab, 1)
		title:SetText("Xal's Compendium - Diagnostics")
		XComp.ApplyTextShadow(title)

		local hint = f:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(XComp.BodyFont)
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
		hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText("Click inside, Ctrl+A then Ctrl+C to copy - paste into a bug report.")

		local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
		scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)

		local editBox = CreateFrame("EditBox", nil, scrollFrame)
		editBox:SetMultiLine(true)
		editBox:SetFontObject(ChatFontNormal)
		editBox:SetAutoFocus(false)
		editBox:SetWidth(scrollFrame:GetWidth())
		editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scrollFrame:SetScrollChild(editBox)
		scrollFrame:SetScript("OnSizeChanged", function(self, width) editBox:SetWidth(width) end)
		-- Same manual wheel-scroll fix as the other scroll frames in this
		-- addon - UIPanelScrollFrameTemplate doesn't wire this up
		-- automatically when built via CreateFrame in Lua.
		scrollFrame:EnableMouseWheel(true)
		scrollFrame:SetScript("OnMouseWheel", function(self, delta)
			local maxScroll = math.max(editBox:GetHeight() - self:GetHeight(), 0)
			local newScroll = self:GetVerticalScroll() - delta * 40
			newScroll = math.max(0, math.min(newScroll, maxScroll))
			self:SetVerticalScroll(newScroll)
		end)
		f.editBox = editBox

		XComp.MakeCloseButton(f)

		f:Hide()
		self.diagFrame = f
	end

	f.editBox:SetText(text)
	f.editBox:SetHeight(math.max(#lines * 14, 300))
	f:Show()
	-- SetFocus() so Ctrl+A/Ctrl+C works immediately - HighlightText() alone
	-- visually selects the text but doesn't give the box keyboard focus, so
	-- copying required an extra manual click first without this.
	f.editBox:SetFocus()
	f.editBox:HighlightText()
end

-- Export window for auto-detected quests (2026-08-12 follow-up) - identical
-- copy-box pattern to ShowDiagnostics above, own separate frame so both can
-- be open independently. This is the actual bridge Jason asked for: the
-- Custom-category auto-add only lives on his own account, so this report is
-- what he copies over so the finds can get sorted into the REAL shared
-- catalog and shipped to everyone in a real release.
function U:ShowUntrackedExport()
	local lines = XComp.Data:GetUntrackedReport()
	local text = table.concat(lines, "\n")

	local f = self.untrackedFrame
	if not f then
		f = CreateFrame("Frame", "XalsCompendiumUntrackedFrame", UIParent, "BackdropTemplate")
		tinsert(UISpecialFrames, "XalsCompendiumUntrackedFrame")
		f:SetSize(560, 440)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		local br, bg, bb = XComp.GetBgColor()
		f:SetBackdropColor(br, bg, bb, 0.97)
		local ar, ag, ab = XComp.GetAccentColor()
		f:SetBackdropBorderColor(ar, ag, ab, 1)

		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)

		local title = f:CreateFontString(nil, "OVERLAY")
		title:SetFont("Interface\\AddOns\\XalsCompendium\\Fonts\\CustomFont.ttf", 18, "")
		title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
		title:SetTextColor(ar, ag, ab, 1)
		title:SetText("Xal's Compendium - Auto-Detected Quests")
		XComp.ApplyTextShadow(title)

		local hint = f:CreateFontString(nil, "OVERLAY")
		hint:SetFontObject(XComp.BodyFont)
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
		hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText("Click inside, Ctrl+A then Ctrl+C to copy - send this list over to get them added to the real catalog.")

		local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
		scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)

		local editBox = CreateFrame("EditBox", nil, scrollFrame)
		editBox:SetMultiLine(true)
		editBox:SetFontObject(ChatFontNormal)
		editBox:SetAutoFocus(false)
		editBox:SetWidth(scrollFrame:GetWidth())
		editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scrollFrame:SetScrollChild(editBox)
		scrollFrame:SetScript("OnSizeChanged", function(self, width) editBox:SetWidth(width) end)
		scrollFrame:EnableMouseWheel(true)
		scrollFrame:SetScript("OnMouseWheel", function(self, delta)
			local maxScroll = math.max(editBox:GetHeight() - self:GetHeight(), 0)
			local newScroll = self:GetVerticalScroll() - delta * 40
			newScroll = math.max(0, math.min(newScroll, maxScroll))
			self:SetVerticalScroll(newScroll)
		end)
		f.editBox = editBox

		XComp.MakeCloseButton(f)

		f:Hide()
		self.untrackedFrame = f
	end

	f.editBox:SetText(text)
	f.editBox:SetHeight(math.max(#lines * 14, 300))
	f:Show()
	f.editBox:SetFocus()
	f.editBox:HighlightText()
end

function U:Toggle()
	local f = self:CreateMainFrame()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		self:RefreshSections()
		self:ApplyIdleAlpha()
	end
end

-------------------------------------------------
-- Section tree rendering
-------------------------------------------------
local ROW_H = 26
-- Two levels now: a flat section header (zone or category name) and its
-- items - the old Tier/Type/Category nesting is gone (rebuilt 2026-08-15).
local INDENT_TIER, INDENT_TYPE = 0, 14

-- Zone-grouping redesign (2026-08-15, per the approved mockup) - one fixed
-- color per named zone, shown as the header's left-edge bar - not cycled/
-- assigned automatically, so a given zone always reads the same color
-- across sessions.
local ZONE_COLORS = {
	["Eversong Woods"] = { 0.30, 0.62, 0.86 },
	["Zul'Aman"] = { 0.75, 0.32, 0.32 },
	["Voidstorm"] = { 0.55, 0.40, 0.85 },
	["The Coiled Isle"] = { 0.35, 0.68, 0.45 },
	["Vaults of Atal'Utek"] = { 0.68, 0.45, 0.85 },
	["Housing"] = { 0.85, 0.45, 0.60 },
	["Silvermoon City"] = { 0.82, 0.68, 0.25 },
	["Legacy"] = { 0.55, 0.55, 0.55 },
}
local ZONE_COLOR_DEFAULT = { 0.60, 0.60, 0.60 }

local function GetZoneColor(zoneName)
	return unpack(ZONE_COLORS[zoneName] or ZONE_COLOR_DEFAULT)
end

-- Collapse state per zone/group name - real sections now (2026-08-15,
-- confirmed spec: "Sections are by definition collapsed... I want it to be
-- clean"), collapsed by default. Module-level (not persisted), same as the
-- old tier/type/category collapse state used to work, just keyed by name
-- instead of living on a catalog object (zone groups aren't catalog nodes).
local sectionCollapsed = {}
local function IsSectionCollapsed(name)
	if sectionCollapsed[name] == nil then sectionCollapsed[name] = true end
	return sectionCollapsed[name]
end

local function MakeZoneHeader(parent, indent, zoneName, completed, total, onToggle)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)

	local zr, zg, zb = GetZoneColor(zoneName)

	local bar = row:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
	bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", indent, 0)
	bar:SetWidth(3)
	bar:SetColorTexture(zr, zg, zb, 1)

	local labelLeftAnchor = bar

	local label = row:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(XComp.BodyFont)
	label:SetPoint("LEFT", labelLeftAnchor, "RIGHT", 6, 0)
	label:SetJustifyH("LEFT")
	label:SetText(zoneName)
	label:SetTextColor(zr, zg, zb, 1)

	if total then
		local countText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		countText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		countText:SetText(string.format("%d/%d", completed, total))
	end

	row:SetScript("OnClick", function()
		sectionCollapsed[zoneName] = not IsSectionCollapsed(zoneName)
		if onToggle then onToggle() end
	end)

	return row
end

-- Manual-completion confirm popup (2026-08-15 correction: the inline
-- checkbox on every row is gone - "one of the pet peeves I have"). Clicking
-- an item's name opens this instead: a small "Complete?" window with a
-- checkbox inside it, so marking something done manually is a deliberate
-- two-step action, not a single click sitting right there in the list.
-- Strikethrough (via MakeItemRow's own text styling) is still what shows
-- completion at a glance - this popup is only the INPUT, not the display.
-- One shared frame, repositioned per click, rather than building a new
-- frame every time. (`completePopup` itself is declared near the top of
-- the file, not here, so CreateMainFrame's OnHide handler can reach it.)
local function GetCompletePopup()
	if completePopup then return completePopup end

	-- Sized with real bottom padding below the checkbox (2026-08-16 fix -
	-- the previous 50px height didn't leave room for the checkbox at all,
	-- so it rendered flush against/past the popup's own bottom border).
	local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	popup:SetSize(150, 76)
	popup:SetFrameStrata("TOOLTIP")
	popup:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	local br, bg, bb = XComp.GetBgColor()
	popup:SetBackdropColor(br, bg, bb, 0.98)
	local ar, ag, ab = XComp.GetAccentColor()
	popup:SetBackdropBorderColor(ar, ag, ab, 1)

	local label = popup:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(XComp.BodyFont)
	label:SetPoint("TOP", popup, "TOP", 0, -12)
	label:SetText("Complete?")
	label:SetTextColor(ar, ag, ab, 1)
	popup.label = label

	local cb = XComp.MakeCheckbox(popup, 20)
	cb:SetPoint("TOP", label, "BOTTOM", 0, -10)
	popup.checkbox = cb

	popup:Hide()
	completePopup = popup
	return popup
end

-- Real toggle (2026-08-16 fix): clicking the SAME item's name a second time
-- while its popup is already open closes it again, instead of only ever
-- being able to open it. Clicking a DIFFERENT item's name while one is
-- already open just moves it there, same as before.
local function ShowCompletePopup(anchorFrame, item, resetEpoch)
	local popup = GetCompletePopup()
	if popup:IsShown() and popup.openForUID == item.uid then
		popup:Hide()
		popup.openForUID = nil
		return
	end

	popup:ClearAllPoints()
	popup:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)
	popup.openForUID = item.uid

	local complete = XComp.Data:GetItemStatus(item, resetEpoch)
	popup.checkbox:SetChecked(complete)
	popup.checkbox.OnToggle = function(self)
		XComp.Data:SetManualOverride(item.uid, self:GetChecked() and true or false, resetEpoch)
		popup:Hide()
		popup.openForUID = nil
		XComp.UI:RefreshSections()
	end

	popup:Show()
end

local function MakeItemRow(parent, item, indent, resetEpoch)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row:EnableMouse(true)

	local label = row:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(XComp.BodyFont)
	label:SetPoint("LEFT", row, "LEFT", indent, 0)
	label:SetJustifyH("LEFT")

	local complete, numFulfilled, numRequired = XComp.Data:GetItemStatus(item, resetEpoch)

	local text = item.name
	if numFulfilled and numRequired then
		text = text .. string.format(" (%d/%d)", numFulfilled, numRequired)
	end
	label:SetText(text)

	-- Color priority: complete (dimmed gray + strikethrough), then active
	-- rotating/task-quest content (whole name turns green - only
	-- meaningful for rotating content, which is otherwise hidden entirely
	-- while offline this cycle, so anything shown here that isn't complete
	-- is, by definition, live right now). Per-item custom color-coding
	-- removed 2026-08-16 - never an actual request, was added unprompted.
	if complete then
		label:SetTextColor(0.42, 0.40, 0.36, 1)
	elseif item.isRotating or item.questIDs then
		label:SetTextColor(0.35, 0.85, 0.40, 1)
	end

	-- Strikethrough (2026-08-15 correction: the inline checkbox is gone, so
	-- this is now the ONLY at-a-glance completion signal). WoW FontStrings
	-- have no native strikethrough - a thin texture line drawn across the
	-- text's own measured width, vertically centered, fakes it.
	local strikeLine
	if complete then
		strikeLine = row:CreateTexture(nil, "OVERLAY")
		-- Plain SetHeight(1) doesn't pixel-snap, so it rendered as a thick
		-- blurry bar instead of a true thin line (2026-08-16 correction) -
		-- PixelUtil.SetHeight is what every other thin line in this addon
		-- already uses (checkbox borders, dividers) for exactly this reason.
		PixelUtil.SetHeight(strikeLine, 1)
		strikeLine:SetColorTexture(0.42, 0.40, 0.36, 1)
		-- A LEFT anchor on a FontString centers against its full line-height
		-- box (ascender/descender padding included), NOT the actual glyph
		-- ink - same root cause already documented on the checkbox's
		-- checkmark texture above. That left the line sitting in the gap
		-- below the letters instead of through them. Offsetting down from
		-- TOP by ~42% of the font's point size lands it through the
		-- letters' visual middle instead.
		local fontSize = select(2, label:GetFont()) or 12
		PixelUtil.SetPoint(strikeLine, "TOPLEFT", label, "TOPLEFT", 0, -(fontSize * 0.42))
		strikeLine:SetWidth(math.max(label:GetStringWidth(), 1))
	end

	local rightAnchor = row

	-- TomTom waypoint button (build-plan item 11) - only shown for items
	-- with a real questID, since C_QuestLog.GetNextWaypoint needs one.
	-- Verified against EverythingQuests' actual installed/working code
	-- (Modules/ChainGuide/Waypoint.lua): GetNextWaypoint's mapID/x/y are
	-- passed straight into TomTom:AddWaypoint with no scaling - both
	-- already agree on the same 0-1 coordinate system.
	if item.questID then
		local mapBtn = CreateFrame("Button", nil, row)
		mapBtn:SetSize(16, ROW_H)
		if rightAnchor == row then
			mapBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		else
			mapBtn:SetPoint("RIGHT", rightAnchor, "LEFT", -6, 0)
		end
		local mapLabel = mapBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		mapLabel:SetPoint("CENTER")
		mapLabel:SetText("Map")
		local mar, mag, mab = XComp.GetAccentColor()
		mapLabel:SetTextColor(mar, mag, mab, 1)
		XComp.ApplyTextShadow(mapLabel)
		mapBtn:SetScript("OnClick", function()
			if not (TomTom and TomTom.AddWaypoint) then
				print("|cffEBB706Xal's Compendium|r: TomTom is not installed.")
				return
			end
			local mapID, x, y = C_QuestLog.GetNextWaypoint(item.questID)
			if mapID and x and y then
				TomTom:AddWaypoint(mapID, x, y, { title = item.name })
			else
				print("|cffEBB706Xal's Compendium|r: no waypoint available for " .. item.name .. " right now.")
			end
		end)
		rightAnchor = mapBtn
	end
	if rightAnchor ~= row then
		label:SetPoint("RIGHT", rightAnchor, "LEFT", -4, 0)
	end

	-- Left-click the name to open the manual-completion confirm popup;
	-- right-click opens the real in-game quest log entry (2026-08-16
	-- correction - was the color picker, which was never actually
	-- requested). QuestMapFrame_OpenToQuestDetails is the real, current
	-- Blizzard API for this - confirmed in Blizzard's own UI source and
	-- used by Kaliel's Tracker, not guessed.
	row:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			local questID = item.questID
			if not questID and item.questIDs then
				for _, qid in ipairs(item.questIDs) do
					if C_QuestLog.IsOnQuest(qid) or C_TaskQuest.IsActive(qid) then
						questID = qid
						break
					end
				end
			end
			if questID then
				QuestMapFrame_OpenToQuestDetails(questID)
			else
				print("|cffEBB706Xal's Compendium|r: no quest log entry available for " .. item.name .. " right now.")
			end
		else
			ShowCompletePopup(row, item, resetEpoch)
		end
	end)

	return row
end

-- Renders an item and recurses into its children (nested sub-tasks/
-- questline steps), each one indented further than its parent. Original
-- implementation built on our own existing row/anchor system - not based
-- on or copied from any other addon's code, per the idea-only permission
-- for this concept.
local function RenderItemTree(container, item, indent, resetEpoch, hideCompleted, placeFn)
	-- Time-gated items (build-plan item 21) - outside their active window,
	-- skip entirely (self-filtering covers both top-level calls and
	-- recursive children, one check point instead of duplicating it at
	-- every call site).
	if not XComp.Data:IsWithinActiveWindow(item) then return end

	-- Rotating content (isRotating flag, or a questIDs pool like the
	-- dungeon board/Showdown zones) only shows when it's genuinely live
	-- this cycle - hides the "every possible option shown at once" mess
	-- this whole redesign started from. NEVER hides something already
	-- completed this cycle - a finished Void Assault should still show
	-- checked off, not vanish just because its offer window closed after
	-- you turned it in.
	if item.isRotating or item.questIDs then
		local isComplete = XComp.Data:GetItemStatus(item, resetEpoch)
		if not isComplete and not XComp.Data:IsItemActive(item) then
			return
		end
	end

	placeFn(MakeItemRow(container, item, indent, resetEpoch))

	if item.children and #item.children > 0 then
		for _, child in ipairs(item.children) do
			local childComplete = XComp.Data:GetItemStatus(child, resetEpoch)
			if not (hideCompleted and childComplete) then
				RenderItemTree(container, child, indent + 14, resetEpoch, hideCompleted, placeFn)
			end
		end
	end
end

-- Rebuilds the whole visible section tree from XComp.Data.Catalog. Simple
-- full-redraw approach for now (destroys and recreates every row) rather
-- than incremental updates - fine at this scale, worth revisiting only if
-- it turns out to be slow once the real catalog is much larger.
function U:RefreshSections()
	local f = self:CreateMainFrame()
	local container = f.sectionsContainer

	-- Real bug fixed 2026-08-16: the complete-confirm popup was anchored to
	-- an item row, but every refresh destroys and recreates ALL rows below
	-- (SetParent(nil)) - the popup itself is a separate frame parented to
	-- UIParent, so it was never affected by that and just stayed floating
	-- on screen, detached from anything, if a refresh happened while it was
	-- open. Any refresh now closes it outright rather than leaving it
	-- anchored to a row that's about to stop existing.
	if completePopup then
		completePopup:Hide()
		completePopup.openForUID = nil
	end

	if container.rows then
		for _, row in ipairs(container.rows) do
			row:Hide()
			row:SetParent(nil)
		end
	end
	container.rows = {}

	local anchorTo = nil
	local contentHeight = 0
	local function PlaceRow(row)
		row:ClearAllPoints()
		if anchorTo then
			row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
			contentHeight = contentHeight + ROW_H + 2
		else
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
			contentHeight = contentHeight + ROW_H
		end
		row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
		anchorTo = row
		table.insert(container.rows, row)
	end

	local overallCompleted, overallTotal = 0, 0
	local hideCompleted = XComp_DB.settings and XComp_DB.settings.hideCompleted

	-- Full rebuild 2026-08-15 to match the approved mockup exactly: the old
	-- Tier(Current/Legacy) > Type(Daily/Weekly/One-time) > Category
	-- collapsible-arrow tree is gone completely, not extended. Every
	-- enabled type across both tiers is still walked once (that's what
	-- keeps counts/streaks correct), but nothing from that walk renders a
	-- header - it only collects items into flat, named groups. A real zone
	-- tag groups an item under its zone (colored bar + icon); anything
	-- without one groups under its category label instead, so nothing
	-- vanishes just because it hasn't been zone-tagged yet.
	local ZONE_RENDER_ORDER = {
		"Eversong Woods", "Zul'Aman", "Voidstorm", "The Coiled Isle",
		"Vaults of Atal'Utek", "Housing", "Legacy",
	}
	local groupOrder, groups = {}, {}
	local function GetGroup(name)
		if not groups[name] then
			groups[name] = {}
			table.insert(groupOrder, name)
		end
		return groups[name]
	end

	-- The selected tab (Daily/Weekly/Legacy) picks which tier+type(s) get
	-- walked - "daily"/"weekly" are the Current tier's matching type only;
	-- "legacy" pulls every type under the Legacy tier combined (that tier's
	-- content is small enough it doesn't need its own Daily/Weekly split).
	-- The subtitle count is scoped to this same selection, matching the
	-- mockup ("Weekly - 5/30 complete", not a combined grand total).
	local selectedType = (XComp_DB.settings and XComp_DB.settings.selectedType) or "weekly"
	for _, tier in ipairs(XComp.Data.Catalog.tiers) do
		local tierMatches = (selectedType == "legacy" and tier.key == "legacy")
			or (selectedType ~= "legacy" and tier.key == "current")
		if tierMatches then
			for _, typeSection in ipairs(XComp.Options:GetOrderedTypes(tier)) do
				if XComp.Options:IsTypeEnabled(typeSection.key)
					and (selectedType == "legacy" or typeSection.key == selectedType) then
					local resetEpoch = XComp.Data:GetResetEpoch(typeSection.resetType)
					local typeCompleted, typeTotal = XComp.Data:CountType(typeSection)
					XComp.Data:UpdateStreak(tier.key, typeSection, resetEpoch, typeCompleted, typeTotal)
					overallCompleted = overallCompleted + typeCompleted
					overallTotal = overallTotal + typeTotal

					for _, category in ipairs(XComp.Options:GetOrderedCategories(typeSection)) do
						for _, item in ipairs(category.items) do
							local groupName = item.zone or category.label
							table.insert(GetGroup(groupName), { item = item, resetEpoch = resetEpoch })
						end
					end
				end
			end
		end
	end

	-- Completed items sink to the bottom within a group, always on (not a
	-- toggle) - same behavior the old tree had, just one flat level now
	-- instead of buried under Tier > Type > Category.
	local function RenderGroup(groupName, entries)
		local incomplete, completed = {}, {}
		for _, e in ipairs(entries) do
			local isComplete = XComp.Data:GetItemStatus(e.item, e.resetEpoch)
			local isHiddenRotation = (e.item.isRotating or e.item.questIDs)
				and not isComplete and not XComp.Data:IsItemActive(e.item)
			if not isHiddenRotation then
				if isComplete then
					table.insert(completed, e)
				else
					table.insert(incomplete, e)
				end
			end
		end
		local groupTotal = #incomplete + #completed
		if groupTotal == 0 then return end
		if hideCompleted and #incomplete == 0 then return end

		PlaceRow(MakeZoneHeader(container, INDENT_TIER, groupName, #completed, groupTotal, function()
			self:RefreshSections()
		end))

		if not IsSectionCollapsed(groupName) then
			for _, e in ipairs(incomplete) do
				RenderItemTree(container, e.item, INDENT_TYPE, e.resetEpoch, hideCompleted, PlaceRow)
			end
			if not hideCompleted then
				for _, e in ipairs(completed) do
					RenderItemTree(container, e.item, INDENT_TYPE, e.resetEpoch, hideCompleted, PlaceRow)
				end
			end
		end
	end

	for _, zoneName in ipairs(ZONE_RENDER_ORDER) do
		if groups[zoneName] then
			RenderGroup(zoneName, groups[zoneName])
			groups[zoneName] = nil
		end
	end
	for _, groupName in ipairs(groupOrder) do
		if groups[groupName] then
			RenderGroup(groupName, groups[groupName])
		end
	end

	local viewLabels = { daily = "Daily", weekly = "Weekly", legacy = "Legacy" }
	f.overallLabel:SetText(string.format("%s - %d/%d complete", viewLabels[selectedType], overallCompleted, overallTotal))
	if f.RefreshTabHighlight then f.RefreshTabHighlight() end
	self:RefreshSideStrip()
	self:ApplyMinimizedState()

	-- Scroll child height must always match actual content, regardless of
	-- auto-size settings - this is what makes overflow physically
	-- impossible now (content that doesn't fit scrolls, never spills past
	-- the border), independent of whatever the window's own height is.
	container:SetHeight(math.max(contentHeight, 1))

	-- Auto-sizing window: grows/shrinks with visible content, up to a cap.
	-- Defaults on, but respects a fixed-size fallback
	-- (XComp_DB.settings.autoSize = false) per the locked safety
	-- requirement, in case this ever misbehaves - user keeps a manual
	-- escape hatch rather than being stuck with it. Content beyond the cap
	-- simply scrolls within the window instead of growing it further.
	local autoSize = not (XComp_DB.settings and XComp_DB.settings.autoSize == false)
	if autoSize and not (XComp_DB.settings and XComp_DB.settings.minimized) then
		local HEADER_AND_FOOTER = 154 -- top offset (68) + tab row (20) + tab row gap (8) + content gap (8) + bottom padding (40) + border padding (10)
		local minH, maxH = 200, 800
		local targetH = HEADER_AND_FOOTER + contentHeight
		if targetH < minH then targetH = minH end
		if targetH > maxH then targetH = maxH end
		f:SetHeight(targetH)
	end

	if f.UpdateScrollRange then f.UpdateScrollRange() end

	-- Keeps this character's alt-roster snapshot (build-plan item 19)
	-- current through the session, not just at login - cheap since
	-- CountType is already computed for the header counts above. This is
	-- also now the ONLY thing that updates it - the manual refresh button
	-- was removed 2026-08-15 as redundant with this call.
	XComp.Data:UpdateRosterSnapshot()
end
