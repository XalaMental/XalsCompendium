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

	-- Hide-completed filter toggle.
	local filterCB = XComp.MakeCheckbox(f, 18)
	filterCB:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
	filterCB:SetChecked(XComp_DB.settings and XComp_DB.settings.hideCompleted or false)
	filterCB.OnToggle = function(self)
		XComp_DB.settings = XComp_DB.settings or {}
		XComp_DB.settings.hideCompleted = self:GetChecked() and true or false
		U:RefreshSections()
	end
	local filterLbl = f:CreateFontString(nil, "OVERLAY")
	filterLbl:SetFontObject(XComp.BodyFont)
	filterLbl:SetPoint("LEFT", filterCB, "RIGHT", 2, 0)
	filterLbl:SetText("Hide completed")
	f.filterCB = filterCB
	f.filterLbl = filterLbl

	local divider = f:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -68)
	divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -68)
	f.divider = divider

	-- Icon row: Great Vault, roster-refresh, item level - moved here (below
	-- the divider, own row) per explicit correction; anchored at the title
	-- instead, they crammed into the title text once the window got
	-- narrowed toward its width minimum.
	local vaultBtn = CreateFrame("Button", nil, f)
	vaultBtn:SetSize(24, 24)
	vaultBtn:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
	local vaultIcon = vaultBtn:CreateTexture(nil, "ARTWORK")
	vaultIcon:SetAllPoints()
	-- Real locked-reward atlas from Blizzard's own Blizzard_WeeklyRewards.lua
	-- source - the actual keyhole/lock graphic the vault UI itself shows.
	vaultIcon:SetAtlas("evergreen-weeklyrewards-reward-locked")
	vaultBtn.icon = vaultIcon
	vaultBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
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
		GameTooltip:SetText("Open Great Vault")
		GameTooltip:Show()
	end)
	vaultBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.vaultBtn = vaultBtn

	-- Manual roster-snapshot refresh (build-plan item 19) - updates
	-- automatically on login/refresh already, this forces one right before
	-- logging off. Classic icon FILE (INV_Misc_Head_Human_01), not a modern
	-- atlas name - several atlas guesses went wrong earlier this session.
	local refreshBtn = CreateFrame("Button", nil, f)
	refreshBtn:SetSize(24, 24)
	refreshBtn:SetPoint("LEFT", vaultBtn, "RIGHT", 6, 0)
	local refreshIcon = refreshBtn:CreateTexture(nil, "ARTWORK")
	refreshIcon:SetAllPoints()
	refreshIcon:SetTexture("Interface\\Icons\\INV_Misc_Head_Human_01")
	refreshBtn.icon = refreshIcon
	refreshBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	refreshBtn:SetScript("OnClick", function()
		XComp.Data:UpdateRosterSnapshot()
		U:ShowCompletionToast("Character snapshot updated for the Alts page")
	end)
	refreshBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Refresh this character's Alts page snapshot")
		GameTooltip:AddLine("Updates automatically as you play - click this right before logging off to make sure it's current.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.refreshBtn = refreshBtn

	-- Item level display (build-plan item 20, display half). Plain display,
	-- not a button - opening the Character panel on click was redundant
	-- (that's just the C keybind), removed per explicit correction.
	local ilvlFrame = CreateFrame("Frame", nil, f)
	ilvlFrame:SetSize(84, 24)
	ilvlFrame:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
	local ilvlText = ilvlFrame:CreateFontString(nil, "OVERLAY")
	-- TitleFont instead of BodyFont - noticeably bigger (fontSize+2 vs
	-- fontSize-2) per explicit "make it more prominent" request, while still
	-- tracking the user's customizable font/outline/size settings live,
	-- same as everything else that uses these shared font objects.
	ilvlText:SetFontObject(XComp.TitleFont)
	ilvlText:SetAllPoints()
	ilvlText:SetJustifyH("LEFT")
	XComp.ApplyTextShadow(ilvlText)
	f.ilvlText = ilvlText

	-- Sections render inside a real scroll frame, not a plain container -
	-- content that exceeds the visible area scrolls instead of spilling
	-- outside the window border (confirmed bug with the earlier plain-
	-- container + auto-resize-only approach). Standard native
	-- UIPanelScrollFrameTemplate.
	local scrollFrame = CreateFrame("ScrollFrame", "XalsCompendiumScrollFrame", f, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", vaultBtn, "BOTTOMLEFT", 0, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)

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
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(scrollChild:GetHeight() - self:GetHeight(), 0)
		local newScroll = self:GetVerticalScroll() - delta * 40
		newScroll = math.max(0, math.min(newScroll, maxScroll))
		self:SetVerticalScroll(newScroll)
	end)

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
	-- (Options.lua Appearance page), default 0 (fully invisible).
	f:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
	f:SetScript("OnLeave", function(self)
		U:ApplyIdleAlpha()
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
		f.title, f.overallLabel, f.filterCB, f.filterLbl, f.divider,
		f.vaultBtn, f.refreshBtn, f.ilvlText, f.scrollFrame, f.resizeGrip, f.closeBtn,
	}
	for _, el in ipairs(fullElements) do
		if el then
			if minimized then el:Hide() else el:Show() end
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
	else
		local br, bg, bb = XComp.GetBgColor()
		f:SetBackdropColor(br, bg, bb, GetBgAlpha())
		f:SetBackdropBorderColor(ar, ag, ab, 1)
	end

	f.title:SetTextColor(ar, ag, ab, 1)
	f.divider:SetColorTexture(ar, ag, ab, IsFrameless() and 0 or 1)

	-- Scale: uniformly zooms the ENTIRE window (text, icons, spacing, all
	-- of it) via native Frame:SetScale, distinct from the corner-drag
	-- resize (which only changes width/height, not the size of contents).
	local scale = (XComp_DB.settings and XComp_DB.settings.scale) or 1
	f:SetScale(scale)
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
local INDENT_TIER, INDENT_TYPE, INDENT_CATEGORY, INDENT_ITEM = 0, 14, 28, 42

-- Collapse state for the top-level Currencies section (build-plan item 14)
-- - a sibling of Current/Legacy, not nested under Daily/Weekly, since
-- Great Vault progress and currency amounts aren't daily/weekly quest
-- items. Same "resets each session" behavior as tier/type/category
-- collapse state (those live on the catalog objects, rebuilt fresh on
-- every login rather than persisted).
local currenciesSectionCollapsed = true
local vaultSubCollapsed = true
local currencyListSubCollapsed = true

-- Right-click on an item row (or a color-enabled header) to color-code it
-- (native ColorPickerFrame, current post-10.2.5 API -
-- SetupColorPickerAndShow, not the old deprecated OpenColorPicker global).
-- Colors are account-wide cosmetic prefs, cleared via "Reset to Defaults"
-- in Options.lua. Declared here, BEFORE MakeCollapseHeader/MakeItemRow
-- below, since both call it and Lua locals are only visible after their
-- declaration point.
local function OpenItemColorPicker(item, label)
	local r, g, b = XComp.Data:GetItemColor(item.uid)
	r, g, b = r or 1, g or 1, b or 1

	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		swatchFunc = function()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			XComp.Data:SetItemColor(item.uid, nr, ng, nb)
			label:SetTextColor(nr, ng, nb, 1)
		end,
		cancelFunc = function()
			local pr, pg, pb = ColorPickerFrame:GetPreviousValues()
			if pr then
				label:SetTextColor(pr, pg, pb, 1)
			end
		end,
	})
end

-- colorKey is optional - when given, right-click opens the same color
-- picker used for items, so this header's label can be custom-colored too
-- (currently used for the Daily/Weekly/One-time type headers specifically,
-- per user request - reuses Data.lua's generic per-uid color storage with
-- a "type:" prefix so these never collide with real item uids).
local function MakeCollapseHeader(parent, text, indent, isCollapsed, onToggle, colorKey)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(ROW_H)

	local arrow = btn:CreateFontString(nil, "OVERLAY")
	arrow:SetFontObject(XComp.TitleFont)
	arrow:SetPoint("LEFT", btn, "LEFT", indent, 0)
	arrow:SetText(isCollapsed and ">" or "v")
	btn.arrow = arrow

	local label = btn:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(XComp.TitleFont)
	label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
	label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
	label:SetJustifyH("LEFT")
	local ar, ag, ab = XComp.GetAccentColor()
	if colorKey then
		local cr, cg, cbb = XComp.Data:GetItemColor(colorKey)
		if cr then ar, ag, ab = cr, cg, cbb end
	end
	label:SetTextColor(ar, ag, ab, 1)
	label:SetText(text)

	btn:SetScript("OnClick", onToggle)

	if colorKey then
		btn:SetScript("OnMouseUp", function(_, button)
			if button == "RightButton" then
				OpenItemColorPicker({ uid = colorKey }, label)
			end
		end)
	end

	return btn
end

local function MakeItemRow(parent, item, indent, resetEpoch)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row:EnableMouse(true)

	local cb = XComp.MakeCheckbox(row, 18)
	cb:SetPoint("LEFT", row, "LEFT", indent, 0)

	local label = row:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(XComp.BodyFont)
	label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	label:SetJustifyH("LEFT")

	local complete, numFulfilled, numRequired = XComp.Data:GetItemStatus(item, resetEpoch)
	cb:SetChecked(complete)

	local text = item.name
	if numFulfilled and numRequired then
		text = text .. string.format(" (%d/%d)", numFulfilled, numRequired)
	end
	label:SetText(text)

	local cr, cg, cb2 = XComp.Data:GetItemColor(item.uid)
	if cr then label:SetTextColor(cr, cg, cb2, 1) end

	-- TomTom waypoint button (build-plan item 11) - only shown for items
	-- with a real questID, since C_QuestLog.GetNextWaypoint needs one.
	-- Verified against EverythingQuests' actual installed/working code
	-- (Modules/ChainGuide/Waypoint.lua): GetNextWaypoint's mapID/x/y are
	-- passed straight into TomTom:AddWaypoint with no scaling - both
	-- already agree on the same 0-1 coordinate system.
	if item.questID then
		local mapBtn = CreateFrame("Button", nil, row)
		mapBtn:SetSize(16, ROW_H)
		mapBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
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
		label:SetPoint("RIGHT", mapBtn, "LEFT", -4, 0)
	end

	cb.OnToggle = function(self)
		XComp.Data:SetManualOverride(item.uid, self:GetChecked() and true or false, resetEpoch)
		-- Without this, the checkbox's own checked state flips (native
		-- behavior) but nothing else does - counts, smart sorting, and the
		-- overall total all stay stale until something unrelated happens to
		-- trigger a full refresh. A checkbox click needs to redraw the list.
		XComp.UI:RefreshSections()
	end

	-- CheckButton only registers left-click by default, so a right-click
	-- anywhere on the row (including over the checkbox) passes through to
	-- this handler untouched.
	row:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			OpenItemColorPicker(item, label)
		end
	end)

	return row
end

-- Read-only line (no checkbox) for live-generated info that isn't a
-- checkable item - Great Vault progress and tracked currency amounts
-- (build-plan item 14).
local function MakeInfoRow(parent, indent, text)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	local label = row:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(XComp.BodyFont)
	label:SetPoint("LEFT", row, "LEFT", indent, 0)
	label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	label:SetJustifyH("LEFT")
	label:SetText(text)
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

	-- Tier is the new outermost level (Current/Legacy) - added 2026-08-08,
	-- replacing the old flat type-list-at-top-level structure. Type keys
	-- are shared across tiers (see Options.lua), so IsTypeEnabled applies
	-- identically inside both.
	for _, tier in ipairs(XComp.Data.Catalog.tiers) do
		local tierCompleted, tierTotal = XComp.Data:CountTier(tier)
		overallCompleted = overallCompleted + tierCompleted
		overallTotal = overallTotal + tierTotal

		if not (hideCompleted and tierCompleted == tierTotal and tierTotal > 0) then
			local tierText = string.format("%s (%d/%d)", tier.label, tierCompleted, tierTotal)
			local tierHeader = MakeCollapseHeader(container, tierText, INDENT_TIER, tier.collapsed, function()
				tier.collapsed = not tier.collapsed
				self:RefreshSections()
			end)
			PlaceRow(tierHeader)

			if not tier.collapsed then
				-- Reorder position/arrow-availability is computed against
				-- only the ENABLED types, not the raw saved order - a
				-- disabled (toggled-off) type is invisible, so it shouldn't
				-- eat a reorder click doing nothing, or block a visible type
				-- from showing it can still move further.
				local visibleTypes = {}
				for _, t in ipairs(XComp.Options:GetOrderedTypes(tier)) do
					if XComp.Options:IsTypeEnabled(t.key) then table.insert(visibleTypes, t) end
				end
				for typeIndex, typeSection in ipairs(visibleTypes) do
					do
						-- Computed once per type (not per item) - every item
						-- under this type shares the same reset cycle.
						local resetEpoch = XComp.Data:GetResetEpoch(typeSection.resetType)

						local typeCompleted, typeTotal = XComp.Data:CountType(typeSection)
						XComp.Data:UpdateStreak(tier.key, typeSection, resetEpoch, typeCompleted, typeTotal)

						-- With the filter on, a type with nothing left to show
						-- (every item across every category already complete)
						-- is skipped entirely rather than showing an empty,
						-- pointless header.
						if not (hideCompleted and typeCompleted == typeTotal and typeTotal > 0) then
							local typeText = string.format("%s (%d/%d)", typeSection.label, typeCompleted, typeTotal)
							local streakCurrent, streakBest = XComp.Data:GetStreak(tier.key, typeSection.key)
							if streakCurrent then
								typeText = typeText .. string.format(" - streak %d/%d", streakCurrent, streakBest)
							end
							-- colorKey shared across both tiers (same "type:daily"
							-- regardless of Current/Legacy), matching how the
							-- enable/disable toggle already treats a type as one
							-- thing that happens to appear under both tiers.
							local typeHeader = MakeCollapseHeader(container, typeText, INDENT_TYPE, typeSection.collapsed, function()
								typeSection.collapsed = not typeSection.collapsed
								self:RefreshSections()
							end, "type:" .. typeSection.key)
							PlaceRow(typeHeader)

							if not typeSection.collapsed then
								local orderedCategories = XComp.Options:GetOrderedCategories(typeSection)
								for catIndex, category in ipairs(orderedCategories) do
									local catCompleted, catTotal = XComp.Data:CountCategory(category, resetEpoch)

									if not (hideCompleted and catCompleted == catTotal and catTotal > 0) then
										local catText = string.format("%s (%d/%d)", category.label, catCompleted, catTotal)
										local catHeader = MakeCollapseHeader(container, catText, INDENT_CATEGORY, category.collapsed, function()
											category.collapsed = not category.collapsed
											self:RefreshSections()
										end)
										PlaceRow(catHeader)

										if not category.collapsed then
											-- Smart sorting: completed items sink to the
											-- bottom, incomplete ones stay on top - always
											-- on, not a toggle. Two-pass split preserves
											-- each group's original relative order
											-- (stable), rather than relying on
											-- table.sort's unstable ordering.
											local incompleteItems, completedItems = {}, {}
											for _, item in ipairs(category.items) do
												local isComplete = XComp.Data:GetItemStatus(item, resetEpoch)
												if isComplete then
													table.insert(completedItems, item)
												else
													table.insert(incompleteItems, item)
												end
											end

											for _, item in ipairs(incompleteItems) do
												RenderItemTree(container, item, INDENT_ITEM, resetEpoch, hideCompleted, PlaceRow)
											end
											if not hideCompleted then
												for _, item in ipairs(completedItems) do
													RenderItemTree(container, item, INDENT_ITEM, resetEpoch, hideCompleted, PlaceRow)
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Currencies (build-plan item 14) - own top-level section, sibling to
	-- Current/Legacy, per explicit user request: Great Vault progress and
	-- tracked currency amounts aren't daily/weekly quest items, so they
	-- don't belong three levels deep under a specific type.
	do
		local currenciesHeader = MakeCollapseHeader(container, "Currencies", INDENT_TIER, currenciesSectionCollapsed, function()
			currenciesSectionCollapsed = not currenciesSectionCollapsed
			self:RefreshSections()
		end)
		PlaceRow(currenciesHeader)

		if not currenciesSectionCollapsed then
			local vaultHeader = MakeCollapseHeader(container, "Great Vault", INDENT_TYPE, vaultSubCollapsed, function()
				vaultSubCollapsed = not vaultSubCollapsed
				self:RefreshSections()
			end)
			PlaceRow(vaultHeader)

			if not vaultSubCollapsed then
				local vaultLines = XComp.Data:GetVaultProgress()
				if #vaultLines == 0 then
					PlaceRow(MakeInfoRow(container, INDENT_ITEM, "No active Great Vault progress this week."))
				else
					for _, v in ipairs(vaultLines) do
						local vaultText = string.format("%s: %d/%d%s", v.label, v.progress, v.threshold, v.filled and " (filled)" or "")
						PlaceRow(MakeInfoRow(container, INDENT_ITEM, vaultText))
					end
				end
			end

			local currencyHeader = MakeCollapseHeader(container, "Tracked Currencies", INDENT_TYPE, currencyListSubCollapsed, function()
				currencyListSubCollapsed = not currencyListSubCollapsed
				self:RefreshSections()
			end)
			PlaceRow(currencyHeader)

			if not currencyListSubCollapsed then
				local currencyLines = XComp.Data:GetTrackedCurrencies()
				if #currencyLines == 0 then
					PlaceRow(MakeInfoRow(container, INDENT_ITEM, "No currencies picked yet - Options -> Currencies."))
				else
					for _, c in ipairs(currencyLines) do
						local curText
						if c.canEarnPerWeek and c.maxWeeklyQuantity and c.maxWeeklyQuantity > 0 then
							curText = string.format("%s: %d (%d/%d this week)", c.name, c.quantity, c.quantityEarnedThisWeek or 0, c.maxWeeklyQuantity)
						else
							curText = string.format("%s: %d", c.name, c.quantity)
						end
						PlaceRow(MakeInfoRow(container, INDENT_ITEM, curText))
					end
				end
			end
		end
	end

	f.overallLabel:SetText(string.format("%d / %d complete", overallCompleted, overallTotal))
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
		local HEADER_AND_FOOTER = 148 -- top offset (68) + icon row (24) + icon row gap (8) + content gap (8) + bottom padding (40)
		local minH, maxH = 200, 800
		local targetH = HEADER_AND_FOOTER + contentHeight
		if targetH < minH then targetH = minH end
		if targetH > maxH then targetH = maxH end
		f:SetHeight(targetH)
	end

	-- Keeps this character's alt-roster snapshot (build-plan item 19)
	-- current through the session, not just at login - cheap since
	-- CountType is already computed for the header counts above.
	XComp.Data:UpdateRosterSnapshot()

	if f.ilvlText then
		local _, avgEquipped = GetAverageItemLevel()
		f.ilvlText:SetText(string.format("ilvl %d", math.floor(avgEquipped or 0)))
	end
end
