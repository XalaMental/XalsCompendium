-- Xal's Compendium
-- Data.lua holds the tracking data model: the built-in quest catalog,
-- personal per-character progress, and the logic that resolves the two
-- into a single "is this done" answer for display.
--
-- Catalog and progress are deliberately separate tables (never merged) so
-- future catalog updates (via the automated extraction pipeline) can never
-- touch or corrupt a player's own saved progress.

XComp.Data = XComp.Data or {}
local D = XComp.Data

-------------------------------------------------
-- Catalog (built-in quest data - empty until the extraction pipeline fills
-- it in)
-------------------------------------------------
-- Hierarchy, locked 2026-08-08 after researching real precedent: the old
-- "Main Faction/Secondary Faction/PvP" category split was traced to
-- DailyTracker's own localization strings (a French->English translation
-- artifact, not validated English UI copy), and 3 other real, active
-- addons (QuestTally, Weekly To-Do Tracker, Routine) were checked - NONE
-- of them split by faction tier at all. Replaced with:
--
--   Current/Legacy (top tier - not a specific expansion name, just whether
--   content belongs to the active expansion or an older one)
--     -> Daily/Weekly/One-time (unchanged)
--       -> content-type category (synthesized from Weekly To-Do Tracker's
--          Great Vault/Currencies/Weekly Events/Quests and Routine's
--          Professions/Prey/Crests & Delves/Story Campaign groupings)
--         -> items
--
-- collapsed = true everywhere by default, per the locked "all sections
-- collapsed on first install" decision - this matters even more now given
-- Legacy is likely to be sparse; it just sits collapsed and out of the way.
local CONTENT_CATEGORIES = {
	{ key = "greatVault", label = "Great Vault" },
	{ key = "currencies", label = "Currencies" },
	{ key = "weeklyEvents", label = "Weekly Events" },
	{ key = "professions", label = "Professions" },
	{ key = "reputation", label = "Reputation" },
	{ key = "storyCampaign", label = "Story/Campaign" },
	{ key = "worldQuests", label = "World Quests" },
	{ key = "custom", label = "Custom" },
}

local function BuildCategories()
	local categories = {}
	for _, c in ipairs(CONTENT_CATEGORIES) do
		table.insert(categories, { key = c.key, label = c.label, collapsed = true, items = {} })
	end
	return categories
end

local function BuildTypes()
	return {
		{
			key = "daily", label = "Daily", resetType = "daily", collapsed = true,
			description = "Daily quests reset every day at server reset.",
			categories = BuildCategories(),
		},
		{
			key = "weekly", label = "Weekly", resetType = "weekly", collapsed = true,
			description = "Weekly quests reset every week at server reset.",
			categories = BuildCategories(),
		},
		{
			key = "onetime", label = "One-time", resetType = "none", collapsed = true,
			description = "One-time quests never reset once completed.",
			categories = BuildCategories(),
		},
	}
end

D.Catalog = {
	tiers = {
		{ key = "current", label = "Current", collapsed = true, types = BuildTypes() },
		{ key = "legacy", label = "Legacy", collapsed = true, types = BuildTypes() },
	},
}

-- Catalog item shape (for reference - the extraction pipeline fills these in):
-- {
--     uid = "unique-stable-id",       -- ours, stable across patches even if questID changes
--     name = "Quest Name",
--     questID = 12345,                -- nil for non-quest / manual-only items
--     children = {},                  -- nested sub-items (tree structure), empty if none
-- }

-- Searches the whole catalog (every tier/type/category, including nested
-- children) for the item matching a given questID - used by the
-- completion-popup feature (build-plan item 10) to identify which tracked
-- item just got turned in from a QUEST_TURNED_IN event.
function D:FindItemByQuestID(questID)
	local function searchItems(items)
		for _, item in ipairs(items) do
			if item.questID == questID then return item end
			if item.children and #item.children > 0 then
				local found = searchItems(item.children)
				if found then return found end
			end
		end
		return nil
	end

	for _, tier in ipairs(self.Catalog.tiers) do
		for _, typeSection in ipairs(tier.types) do
			for _, category in ipairs(typeSection.categories) do
				local found = searchItems(category.items)
				if found then return found end
			end
		end
	end
	return nil
end

-------------------------------------------------
-- Reset epochs
-------------------------------------------------
-- A "reset epoch" is a stable number identifying the current reset cycle
-- for a given reset type - it stays the same for the whole day/week, then
-- changes the instant that reset actually happens. We use the upcoming
-- reset's own timestamp as that number: C_DateAndTime.GetSecondsUntilX()
-- counts down in real time, so time() + secondsUntil always points at the
-- same future instant until that reset fires, then jumps to the next one.
--
-- Deliberately NOT using the older GetQuestResetTime() - it has a
-- documented bug where it returns garbage (time since Unix epoch) on the
-- very first UI load after login, only becoming reliable after a second
-- update event. C_DateAndTime.GetSecondsUntilDailyReset()/
-- GetSecondsUntilWeeklyReset() have no such caveat documented.
function D:GetResetEpoch(resetType)
	if resetType == "daily" then
		return math.floor(time() + C_DateAndTime.GetSecondsUntilDailyReset())
	elseif resetType == "weekly" then
		return math.floor(time() + C_DateAndTime.GetSecondsUntilWeeklyReset())
	end
	-- "none" (one-time items) never reset, so there's only ever one cycle -
	-- a fixed epoch means a manual override on these simply never expires.
	return 0
end

-------------------------------------------------
-- Personal progress (per-character SavedVariables)
-------------------------------------------------
-- XComp_CharDB.progress[uid] = {
--     manualOverride = true/false/nil,  -- nil = trust auto-detection
--     overrideSetAt = <resetEpoch>,     -- which reset cycle the override belongs to
-- }
local function EnsureProgressTable()
	XComp_CharDB.progress = XComp_CharDB.progress or {}
	return XComp_CharDB.progress
end

-- Called with the current reset epoch for an item's reset type (daily/weekly/
-- none) - if the override was set in a previous cycle, it's stale and gets
-- cleared, reverting that item back to trusting auto-detection.
function D:ClearStaleOverride(uid, currentResetEpoch)
	local progress = EnsureProgressTable()
	local entry = progress[uid]
	if entry and entry.manualOverride ~= nil and entry.overrideSetAt ~= currentResetEpoch then
		entry.manualOverride = nil
		entry.overrideSetAt = nil
	end
end

function D:SetManualOverride(uid, value, currentResetEpoch)
	local progress = EnsureProgressTable()
	progress[uid] = progress[uid] or {}
	progress[uid].manualOverride = value
	progress[uid].overrideSetAt = currentResetEpoch
end

-------------------------------------------------
-- Status resolution (auto-detection + manual override + objective progress)
-------------------------------------------------
-- Returns: complete (bool), numFulfilled (number|nil), numRequired (number|nil),
-- isManualOverride (bool) - the last one lets the UI show "this is a manual
-- correction" differently from a naturally auto-detected state, if wanted later.
function D:GetItemStatus(item, currentResetEpoch)
	local progress = EnsureProgressTable()
	local entry = progress[item.uid]

	if entry and entry.manualOverride ~= nil then
		if entry.overrideSetAt == currentResetEpoch then
			return entry.manualOverride, nil, nil, true
		end
		-- Override belongs to a previous cycle - stale. Clean it up now
		-- (storage hygiene) rather than leaving it to linger in SavedVariables.
		self:ClearStaleOverride(item.uid, currentResetEpoch)
	end

	if not item.questID then
		-- No quest ID at all means this item can ONLY ever be tracked
		-- manually - with no override set, it defaults to not complete.
		return false, nil, nil, false
	end

	local isComplete = C_QuestLog.IsQuestFlaggedCompleted(item.questID)

	-- Multi-step objectives (e.g. "1/5 dungeons") - standard part of every
	-- quest item's status, not a separate feature. GetQuestObjectives can
	-- return nothing on the first call if the quest isn't cached yet; that's
	-- not an error, just means no objective breakdown is available this check.
	local numFulfilled, numRequired
	local objectives = C_QuestLog.GetQuestObjectives(item.questID)
	if objectives and objectives[1] then
		numFulfilled, numRequired = objectives[1].numFulfilled, objectives[1].numRequired
	end

	return isComplete, numFulfilled, numRequired, false
end

-------------------------------------------------
-- Time-gated items/sections (build-plan item 21) - an item's optional
-- activeFrom/activeUntil (Unix timestamps, nil = no restriction) let the
-- extraction pipeline (build-plan item 13) flag limited-time content (e.g.
-- an anniversary event) so it automatically disappears from the tracker
-- outside its real window - purely data-driven, not a "let players create
-- their own timed section" UI (that's the deferred custom-tabs item).
-------------------------------------------------
function D:IsWithinActiveWindow(item)
	local now = time()
	if item.activeFrom and now < item.activeFrom then return false end
	if item.activeUntil and now > item.activeUntil then return false end
	return true
end

-------------------------------------------------
-- Progress counters
-------------------------------------------------
-- Recursively counts an item list (including nested children, per the
-- tree/questline structure) and returns completed, total. A parent item
-- counts as its own unit alongside its children, not instead of them.
-- Items outside their active window (see IsWithinActiveWindow above) are
-- skipped entirely - neither counted nor considered "incomplete".
function D:CountItems(items, resetEpoch)
	local completed, total = 0, 0
	for _, item in ipairs(items) do
		if self:IsWithinActiveWindow(item) then
			total = total + 1
			local isComplete = self:GetItemStatus(item, resetEpoch)
			if isComplete then completed = completed + 1 end

			if item.children and #item.children > 0 then
				local childCompleted, childTotal = self:CountItems(item.children, resetEpoch)
				completed = completed + childCompleted
				total = total + childTotal
			end
		end
	end
	return completed, total
end

function D:CountCategory(category, resetEpoch)
	return self:CountItems(category.items, resetEpoch)
end

-------------------------------------------------
-- Per-item color-coding (account-wide cosmetic preference)
-------------------------------------------------
local function EnsureItemColorsTable()
	XComp_DB.itemColors = XComp_DB.itemColors or {}
	return XComp_DB.itemColors
end

-- Returns r, g, b or nil if no custom color is set (caller should fall
-- back to the default label color).
function D:GetItemColor(uid)
	local c = EnsureItemColorsTable()[uid]
	if not c then return nil end
	return c[1], c[2], c[3]
end

function D:SetItemColor(uid, r, g, b)
	EnsureItemColorsTable()[uid] = { r, g, b }
end

function D:ClearItemColor(uid)
	EnsureItemColorsTable()[uid] = nil
end

function D:CountType(typeSection)
	local resetEpoch = self:GetResetEpoch(typeSection.resetType)
	local completed, total = 0, 0
	for _, category in ipairs(typeSection.categories) do
		local c, t = self:CountCategory(category, resetEpoch)
		completed = completed + c
		total = total + t
	end
	return completed, total
end

-- Sums CountType across every type in a tier (Current/Legacy), respecting
-- the settings panel's per-type enable/disable toggle - same rule the
-- overall total already applies, centralized here so UI.lua doesn't
-- duplicate the enabled-check logic per tier.
function D:CountTier(tier)
	local completed, total = 0, 0
	for _, typeSection in ipairs(tier.types) do
		if XComp.Options:IsTypeEnabled(typeSection.key) then
			local c, t = self:CountType(typeSection)
			completed = completed + c
			total = total + t
		end
	end
	return completed, total
end

-------------------------------------------------
-- Maintenance reminder popup (build-plan item 21, other half) - warns once
-- per reset cycle if weekly reset is coming up soon and weekly content is
-- still incomplete. Reuses C_DateAndTime.GetSecondsUntilWeeklyReset(),
-- the same function D:GetResetEpoch already uses - confirmed reliable with
-- no first-load caveat (unlike the older GetQuestResetTime).
-------------------------------------------------
local MAINTENANCE_WARNING_SECONDS = 3 * 60 * 60 -- 3 hours

function D:CheckMaintenanceReminder()
	local secondsLeft = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if not secondsLeft or secondsLeft <= 0 or secondsLeft > MAINTENANCE_WARNING_SECONDS then
		return
	end

	local weeklyEpoch = self:GetResetEpoch("weekly")
	XComp_DB.maintenanceReminderShownForEpoch = XComp_DB.maintenanceReminderShownForEpoch or {}
	if XComp_DB.maintenanceReminderShownForEpoch[weeklyEpoch] then
		return -- already reminded this cycle
	end

	local completed, total = 0, 0
	for _, tier in ipairs(self.Catalog.tiers) do
		if XComp.Options:IsTypeEnabled("weekly") then
			local typeSection = tier.types[2] -- weekly is always index 2, see BuildTypes()
			local c, t = self:CountType(typeSection)
			completed = completed + c
			total = total + t
		end
	end

	if total > 0 and completed < total then
		local hours = math.ceil(secondsLeft / 3600)
		XComp.UI:ShowCompletionToast(string.format(
			"Weekly reset in ~%d hour%s - %d/%d weekly items still incomplete!",
			hours, hours == 1 and "" or "s", completed, total))
	end

	XComp_DB.maintenanceReminderShownForEpoch[weeklyEpoch] = true
end

-------------------------------------------------
-- Great Vault + currency tracking (build-plan item 14) - live, auto-
-- generated read-only lines under the Great Vault / Currencies categories,
-- using Blizzard's own live data instead of manual checkboxes. Verified
-- against Warcraft Wiki: C_WeeklyRewards.GetActivities() returns an array
-- of WeeklyRewardActivityInfo {type, progress, threshold, ...}; type is
-- Enum.WeeklyRewardChestThresholdType (Activities=1 [M+/Delves],
-- RankedPvP=2, Raid=3, World=6 - the four reward-earning categories;
-- None/AlsoReceive/Concession are internal, not shown).
-- C_CurrencyInfo.GetCurrencyInfo(id) returns {name, quantity, maxQuantity,
-- quantityEarnedThisWeek, maxWeeklyQuantity, canEarnPerWeek, ...}. "Weekly
-- Events" gets no special API integration - there's no single unified
-- Blizzard API for arbitrary rotating weekly events, so it stays a manual
-- category like any other (already supported by the generic item system).
-------------------------------------------------
local VAULT_TYPE_LABELS = {
	[1] = "Mythic+/Delves",
	[2] = "Rated PvP",
	[3] = "Raid",
	[6] = "World",
}

function D:GetVaultProgress()
	local lines = {}
	if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return lines end
	local activities = C_WeeklyRewards.GetActivities()
	if not activities then return lines end
	for _, activity in ipairs(activities) do
		local label = VAULT_TYPE_LABELS[activity.type]
		if label then
			table.insert(lines, {
				label = label,
				progress = activity.progress or 0,
				threshold = activity.threshold or 0,
				filled = (activity.progress or 0) >= (activity.threshold or 0),
			})
		end
	end
	return lines
end

-- Which currencies to show is user-configured via a checklist (Options ->
-- Currencies, populated live from the player's own Currency tab so real
-- names are always shown - no typing raw currency IDs) rather than auto-
-- discovered - there's no reliable "every currency this account cares
-- about" API, and most currencies aren't relevant to a given player.
-- trackedCurrencyIDs is a set ({[currencyID] = true}), not an array.
function D:GetTrackedCurrencies()
	local ids = XComp_DB.settings and XComp_DB.settings.trackedCurrencyIDs
	if not ids then return {} end
	local results = {}
	for id, isTracked in pairs(ids) do
		if isTracked then
			local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
			if info then
				table.insert(results, info)
			end
		end
	end
	return results
end

-------------------------------------------------
-- Diagnostics (build-plan item 12) - a copyable report flagging catalog
-- items with no questID at all (manual-only, can't auto-detect), and, for
-- anything currently in the player's quest log, comparing the LIVE
-- Daily/Weekly classification against what the catalog says (per the
-- "Weekly quest detection - SOLVED" research: C_QuestLog.GetInfo(index)
-- .frequency, Enum.QuestFrequency, verified against Blizzard's generated
-- API docs and FrameXML - not guessed). Also generates a Wowhead link per
-- item with a questID, so a bug report can link straight to the quest.
-------------------------------------------------
function D:RunDiagnostics()
	local lines = {}
	local mismatches, noQuestID, total = 0, 0, 0

	local function checkItem(path, item, resetType)
		total = total + 1
		if not item.questID then
			noQuestID = noQuestID + 1
			table.insert(lines, string.format("%s | %s - no quest ID set (manual-only)", path, item.name))
		else
			local mismatchNote = ""
			local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(item.questID)
			if logIndex then
				local info = C_QuestLog.GetInfo(logIndex)
				if info and info.frequency then
					local liveType
					if info.frequency == Enum.QuestFrequency.Daily then
						liveType = "daily"
					elseif info.frequency == Enum.QuestFrequency.Weekly then
						liveType = "weekly"
					end
					if liveType and resetType and liveType ~= resetType then
						mismatches = mismatches + 1
						mismatchNote = string.format(" - MISMATCH: catalog says %s, live says %s", resetType, liveType)
					end
				end
			end
			local link = string.format("https://www.wowhead.com/quest=%d", item.questID)
			table.insert(lines, string.format("%s | %s (id %d)%s - %s", path, item.name, item.questID, mismatchNote, link))
		end

		if item.children and #item.children > 0 then
			for _, child in ipairs(item.children) do
				checkItem(path, child, resetType)
			end
		end
	end

	for _, tier in ipairs(self.Catalog.tiers) do
		for _, typeSection in ipairs(tier.types) do
			local resetType = (typeSection.resetType == "daily" or typeSection.resetType == "weekly") and typeSection.resetType or nil
			for _, category in ipairs(typeSection.categories) do
				local path = string.format("%s > %s > %s", tier.label, typeSection.label, category.label)
				for _, item in ipairs(category.items) do
					checkItem(path, item, resetType)
				end
			end
		end
	end

	table.insert(lines, 1, "")
	table.insert(lines, 1, string.format("Xal's Compendium diagnostics - %d items checked, %d with no quest ID, %d frequency mismatches.", total, noQuestID, mismatches))
	return lines
end

-------------------------------------------------
-- Streak tracking (build-plan item 9) - real precedent confirmed via
-- QuestTally (CurseForge), which tracks a current + best streak. Per-
-- character (personal accomplishment, not account-wide), and tracked per
-- tier+type combo (e.g. "current:daily") since Current and Legacy have
-- separate item pools under the same type key - matches how CountType
-- already operates on one tier's typeSection instance at a time. Only
-- applies to daily/weekly (resetType ~= "none") - one-time content never
-- cycles, so "streak" has no meaning there.
-------------------------------------------------
local function EnsureStreakTable()
	XComp_CharDB.streaks = XComp_CharDB.streaks or {}
	return XComp_CharDB.streaks
end

-- Called once per RefreshSections for each visible tier+type - cheap to
-- call repeatedly within the same reset cycle (idempotent until the epoch
-- actually changes). completed/total reflect that type's current state.
function D:UpdateStreak(tierKey, typeSection, resetEpoch, completed, total)
	if typeSection.resetType == "none" then return end

	local streaks = EnsureStreakTable()
	local streakKey = tierKey .. ":" .. typeSection.key
	local s = streaks[streakKey]
	local wasFullyComplete = (total > 0 and completed == total)

	if not s then
		streaks[streakKey] = { current = 0, best = 0, lastEpoch = resetEpoch, lastWasComplete = wasFullyComplete }
		return
	end

	if resetEpoch == s.lastEpoch then
		-- Still the same cycle - just keep the "was it complete" flag
		-- current in case this is the last check before reset.
		s.lastWasComplete = wasFullyComplete
	else
		-- The cycle rolled over since we last checked - finalize the
		-- PREVIOUS cycle's outcome into the streak, then start tracking
		-- the new one.
		if s.lastWasComplete then
			s.current = s.current + 1
			if s.current > s.best then s.best = s.current end
		else
			s.current = 0
		end
		s.lastEpoch = resetEpoch
		s.lastWasComplete = wasFullyComplete
	end
end

-- Returns current, best - or nil, nil if this type has no streak concept
-- (one-time content) or hasn't been observed yet.
function D:GetStreak(tierKey, typeKey)
	local streaks = EnsureStreakTable()
	local s = streaks[tierKey .. ":" .. typeKey]
	if not s then return nil, nil end
	return s.current, s.best
end

-------------------------------------------------
-- Alt roster (build-plan item 19) - each character writes a snapshot of its
-- own progress into the ACCOUNT-WIDE save (XComp_DB.roster). A logged-in
-- character can never read another character's own SavedVariablesPerCharacter
-- file - that's a hard WoW client restriction, not a design choice - but
-- every character CAN read XComp_DB, since that's one shared file. Same
-- trick every real alt-tracking addon (Altoholic, AlterEgo) uses. This means
-- the roster shows each alt as of their LAST login/play session, never truly
-- live while they're offline - not possible any other way.
-------------------------------------------------
local function CharKey()
	return UnitName("player") .. "-" .. GetRealmName()
end

function D:UpdateRosterSnapshot()
	XComp_DB.roster = XComp_DB.roster or {}
	local _, classToken = UnitClass("player")

	local tiersSnapshot = {}
	local streaksSnapshot = {}
	for _, tier in ipairs(self.Catalog.tiers) do
		local typesSnapshot = {}
		for _, typeSection in ipairs(tier.types) do
			local completed, total = self:CountType(typeSection)
			typesSnapshot[typeSection.key] = { completed = completed, total = total }
			if typeSection.resetType ~= "none" then
				local current, best = self:GetStreak(tier.key, typeSection.key)
				if current then
					streaksSnapshot[tier.key .. ":" .. typeSection.key] = { current = current, best = best }
				end
			end
		end
		tiersSnapshot[tier.key] = typesSnapshot
	end

	XComp_DB.roster[CharKey()] = {
		name = UnitName("player"),
		realm = GetRealmName(),
		classToken = classToken,
		lastSeen = time(),
		tiers = tiersSnapshot,
		streaks = streaksSnapshot,
	}
end

-- Sorted by name so the roster list doesn't reshuffle on every refresh.
function D:GetRosterList()
	local list = {}
	if XComp_DB.roster then
		for charKey, entry in pairs(XComp_DB.roster) do
			entry.charKey = charKey
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-------------------------------------------------
-- Backup manager (build-plan item 16) - a safeguard against losing streaks,
-- manual overrides, or settings to an accidental "Reset to Defaults" click
-- or a bad SavedVariables write. Snapshots XComp_DB (account-wide settings)
-- and XComp_CharDB (per-character progress/streaks) together, since a
-- restore needs both back in sync with each other.
-------------------------------------------------
local MAX_BACKUPS = 5

local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = DeepCopy(v)
	end
	return copy
end

-- label is optional, defaults to "Manual" - distinguishes the automatic
-- once-a-day login snapshot from ones the player took on purpose.
function D:CreateBackup(label)
	XComp_DB.backups = XComp_DB.backups or {}

	local dbCopy = DeepCopy(XComp_DB)
	dbCopy.backups = nil -- never nest previous backups inside a new one

	table.insert(XComp_DB.backups, 1, {
		timestamp = time(),
		label = label or "Manual",
		db = dbCopy,
		charDb = DeepCopy(XComp_CharDB),
	})
	while #XComp_DB.backups > MAX_BACKUPS do
		table.remove(XComp_DB.backups)
	end
end

-- Called once per login (Core.lua's ADDON_LOADED handler) - only actually
-- creates a snapshot if the most recent one is more than a day old, so
-- reloading the UI repeatedly doesn't burn through the 5-slot cap.
function D:AutoBackupIfNeeded()
	local backups = XComp_DB.backups
	local mostRecent = backups and backups[1]
	if not mostRecent or (time() - mostRecent.timestamp) > 86400 then
		self:CreateBackup("Auto")
	end
end

function D:GetBackups()
	return XComp_DB.backups or {}
end

-- Restores both DBs from the snapshot at `index` (1 = most recent). Keeps
-- the backup list itself intact across the restore, otherwise restoring an
-- older snapshot would also roll back the list of available backups,
-- silently deleting newer ones the player might still want.
function D:RestoreBackup(index)
	local backups = XComp_DB.backups
	local snapshot = backups and backups[index]
	if not snapshot then return false end

	local keepBackups = XComp_DB.backups
	XComp_DB = DeepCopy(snapshot.db)
	XComp_DB.backups = keepBackups
	XComp_CharDB = DeepCopy(snapshot.charDb)

	XComp.ApplyFontSettings()
	if XComp.UI and XComp.UI.mainFrame then
		XComp.UI:ApplyTheme()
		if XComp.UI.mainFrame:IsShown() then
			XComp.UI:RefreshSections()
		end
	end
	return true
end

function D:DeleteBackup(index)
	if XComp_DB.backups then
		table.remove(XComp_DB.backups, index)
	end
end

-------------------------------------------------
-- Reputation display (build-plan item 15) - plain read-only list, Esc-menu
-- settings only per explicit user request (not the tracker, not the
-- standalone window). C_Reputation.GetFactionDataByIndex/GetNumFactions
-- confirmed via Warcraft Wiki (FactionData fields: factionID, name,
-- reaction, currentStanding, currentReactionThreshold, nextReactionThreshold,
-- isHeader, isHeaderWithRep, isChild, isCollapsed). Collapsed headers hide
-- their children from that index-based list - real quirk inherited from the
-- old GetFactionInfo API, confirmed by the mere existence of
-- C_Reputation.ExpandAllFactionHeaders() as a dedicated API to work around
-- it - so it's called first to make sure nothing's silently missing.
-------------------------------------------------
function D:GetAllFactions()
	local list = {}
	if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
		return list
	end
	if C_Reputation.ExpandAllFactionHeaders then
		C_Reputation.ExpandAllFactionHeaders()
	end
	local numFactions = C_Reputation.GetNumFactions()
	for i = 1, numFactions do
		local info = C_Reputation.GetFactionDataByIndex(i)
		if info then
			table.insert(list, info)
		end
	end
	return list
end
