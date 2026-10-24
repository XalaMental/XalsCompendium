-- FloatingIcon.lua
-- Xal's Compendium
--
-- A floating on-screen icon, separate from the fixed minimap button, that
-- only exists while there's at least one daily/weekly item in the catalog
-- still outstanding (not yet completed). The moment everything's done for
-- the day/week, it hides entirely - no idle/dimmed state, same fail-closed
-- pattern as the completion toast. Draggable, position remembered.
--
-- Same glow/pulse technique as Quest Compass's compact icon and Armoire/
-- Reins' zone alert icon (Interface\Cooldown\star4, ADD blend, bounce alpha
-- 0.35-0.85 over 1.1s) - reads as the same visual language across the
-- family, tinted with the addon's fixed brand accent (XComp.GetAccentColor()
-- - no gold anywhere anymore, see Core.lua).
--
-- Deliberately bigger than the fixed minimap button (34px) - this is meant
-- to read as a clear at-a-glance alert from across the screen, not blend in
-- at the same size as the always-there minimap icon. Size itself is a
-- slider on the Appearance page (XComp_DB.settings.floatingIconSize) rather
-- than a fixed number - easier to get right for a real screen/UI scale than
-- fine-tuning a hardcoded constant back and forth.
local DEFAULT_ICON_SIZE = 52
local MIN_ICON_SIZE, MAX_ICON_SIZE = 32, 128
local ICON_PATH = "Interface\\AddOns\\XalsCompendium\\Textures\\MinimapIcon_v1.png"
local DEFAULT_POS = { x = 0, y = -220 }
local BADGE_RATIO = 22 / 64 -- badge stays proportional to icon size, not fixed

local function GetIconSize()
	local s = XComp_DB.settings and XComp_DB.settings.floatingIconSize
	if not s then return DEFAULT_ICON_SIZE end
	return math.max(MIN_ICON_SIZE, math.min(MAX_ICON_SIZE, s))
end

local icon

-- Applies the current size to every piece of the icon (art, glow, badge +
-- its ring) - shared by BuildIcon (first creation) and the live slider
-- callback (XComp.SetFloatingIconSize) so neither one can drift out of sync
-- with the other.
local function ApplyIconSize(f, size)
	f:SetSize(size, size)
	f.glow:SetSize(size * 1.875, size * 1.875)
	local badgeSize = math.floor(size * BADGE_RATIO + 0.5)
	f.badge:SetSize(badgeSize, badgeSize)
	f.badgeRing:SetSize(badgeSize + 4, badgeSize + 4)
end

local function BuildIcon()
	if icon then return icon end

	local size = GetIconSize()
	local f = CreateFrame("Button", "XalsCompendiumFloatingIcon", UIParent)
	f:SetSize(size, size)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()

	local pos = (XComp_DB.floatingIconPos and XComp_DB.floatingIconPos.x) and XComp_DB.floatingIconPos or DEFAULT_POS
	f:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)

	local ar, ag, ab = XComp.GetAccentColor()

	-- Glow sits behind the icon texture, additive-blended so it reads as
	-- light rather than a flat colored circle - same technique as every
	-- other floating icon in the family. Blue specifically (not the accent
	-- red) - Jason's own correction, 2026-09-29.
	local GLOW_COLOR = { 0.25, 0.55, 0.95 }
	local glow = f:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture("Interface\\Cooldown\\star4")
	glow:SetBlendMode("ADD")
	glow:SetSize(size * 1.875, size * 1.875)
	glow:SetPoint("CENTER")
	glow:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
	f.glow = glow

	local glowAnim = glow:CreateAnimationGroup()
	glowAnim:SetLooping("BOUNCE")
	local glowAlpha = glowAnim:CreateAnimation("Alpha")
	glowAlpha:SetFromAlpha(0.35)
	glowAlpha:SetToAlpha(0.85)
	glowAlpha:SetDuration(1.1)
	glowAlpha:SetSmoothing("IN_OUT")
	f.glowAnim = glowAnim

	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture(ICON_PATH)
	f.texture = tex

	-- Count badge - a real circle (Blizzard's own round indicator asset,
	-- recolored via SetVertexColor), NOT a backdrop-textured square. A plain
	-- WHITE8x8 backdrop box was rendering as an actual square block in-game -
	-- real bug, confirmed via screenshot. Stays proportional to the icon
	-- (BADGE_RATIO), not a fixed size, so it keeps reading as "smaller than
	-- the icon" at any slider setting. A slightly larger dark copy sits
	-- behind it as a thin ring, same as the mockup's subtle outline, so the
	-- badge doesn't blend into the icon art under it.
	local badgeSize = math.floor(size * BADGE_RATIO + 0.5)
	local badgeRing = f:CreateTexture(nil, "OVERLAY", nil, 1)
	badgeRing:SetTexture("Interface\\COMMON\\Indicator-Gray")
	badgeRing:SetSize(badgeSize + 4, badgeSize + 4)
	badgeRing:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
	local dr, dg, db = XComp.GetBgColor()
	badgeRing:SetVertexColor(dr, dg, db)
	f.badgeRing = badgeRing

	local badge = f:CreateTexture(nil, "OVERLAY", nil, 2)
	badge:SetTexture("Interface\\COMMON\\Indicator-Gray")
	badge:SetSize(badgeSize, badgeSize)
	badge:SetPoint("CENTER", badgeRing, "CENTER", 0, 0)
	badge:SetVertexColor(ar, ag, ab)
	f.badge = badge

	local badgeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
	badgeText:SetTextColor(1, 1, 1, 1)
	badge.text = badgeText

	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		XComp_DB.floatingIconPos = { x = cx - ux, y = cy - uy }
	end)

	f:SetScript("OnClick", function() XComp.UI:Toggle() end)

	f:SetScript("OnEnter", function(self)
		local car, cag, cab = XComp.GetAccentColor()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Xal's Compendium", car, cag, cab)
		local n = self.outstandingCount or 0
		if n > 0 then
			GameTooltip:AddLine(n .. " daily/weekly quest" .. (n == 1 and "" or "s") .. " still open in this zone", 1, 1, 1)
		else
			GameTooltip:AddLine("Nothing in this zone - still outstanding elsewhere", 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("Click to open the tracker", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	icon = f
	return f
end

-- Visibility and the badge NUMBER are two separate questions (2026-09-29
-- correction): the icon itself shows as long as there's SOMETHING
-- outstanding ANYWHERE ("be there if there are dailies, weeklies, or
-- whatever"), via XComp.Data:GetDailyWeeklyLeft() (global). The NUMBER on
-- it only ever reflects your CURRENT zone, via
-- XComp.Data:GetDailyWeeklyLeftInCurrentZone() - it can read 0 while the
-- icon (and its glow) is still up, meaning nothing's outstanding here
-- specifically, but something is somewhere else.
function XComp.RefreshFloatingIcon()
	local enabled = not (XComp_DB.settings and XComp_DB.settings.showFloatingIcon == false)
	if not enabled then
		if icon then icon:Hide() end
		return
	end

	local dailyLeft, weeklyLeft = XComp.Data:GetDailyWeeklyLeft()
	local total = dailyLeft + weeklyLeft

	if total <= 0 then
		if icon then icon:Hide() end
		return
	end

	local zoneDaily, zoneWeekly = XComp.Data:GetDailyWeeklyLeftInCurrentZone()
	local zoneTotal = zoneDaily + zoneWeekly

	local f = BuildIcon()
	f.outstandingCount = zoneTotal
	f.badge.text:SetText(tostring(zoneTotal))
	f:Show()
	f.glow:Show()
	if not f.glowAnim:IsPlaying() then f.glowAnim:Play() end
end

-- Live size change - the Appearance page's slider calls this on every drag
-- tick (OptionsSliderTemplate's OnValueChanged), not just on release, so the
-- icon visibly resizes as you drag instead of needing a reset/reload to see
-- the new size take effect.
function XComp.SetFloatingIconSize(size)
	XComp_DB.settings = XComp_DB.settings or {}
	XComp_DB.settings.floatingIconSize = size
	if icon then ApplyIconSize(icon, GetIconSize()) end
end

-- The icon has no right-click menu / visible chrome of its own to recover
-- it with, so this is the only way back if it's ever dragged off-screen (or
-- a resolution/UI-scale change carries it there) - exposed on the
-- Appearance settings page next to the enable checkbox.
function XComp.ResetFloatingIconPosition()
	XComp_DB.floatingIconPos = nil
	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_POS.x, DEFAULT_POS.y)
	end
end
