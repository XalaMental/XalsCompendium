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

-- First real seed data (2026-08-12) - Current -> Weekly -> Weekly Events.
-- Sourced by cross-referencing the local weekly-checker tool's real
-- Blizzard API data against Icy Veins' current weekly to-do list, then
-- hand-verified: 3 "Void Assaults" quests (Blizzard's own category field)
-- matching Icy Veins' described rotating Void Strikes system, plus 5
-- "Dungeon" category quests confirmed by the user as the weekly rotating
-- dungeon-of-the-week quest board (picked up from NPCs by the bank) - a
-- real, recurring weekly system, not one-time content, despite sharing a
-- name with the dungeon itself.
do
	local currentTier = D.Catalog.tiers[1]
	local weeklyType = currentTier.types[2]
	local weeklyEvents = weeklyType.categories[3]

	local seedItems = {
		{ uid = "quest-96049", name = "Stalkers of the Stars", questID = 96049, zone = "Voidstorm", children = {} },
		{ uid = "quest-96080", name = "Void Strike", questID = 96080, zone = "Voidstorm", children = {} },
		{ uid = "quest-96703", name = "Veterans of the Great Dark", questID = 96703, zone = "Voidstorm", children = {} },
		-- Weekly dungeon board - a ROTATING single slot, only ONE of these
		-- 5 dungeons is actually the live/offered quest in any given week
		-- (confirmed by the user 2026-08-13 - Murder Row was this week's,
		-- the other 4 weren't simultaneously active). questIDs (plural) -
		-- GetItemStatus treats it complete if ANY one is flagged completed.
		-- Tagged by pickup location (Silvermoon City), not by which dungeon
		-- is live that week - confirmed 2026-08-15, same reasoning as The
		-- World Awaits.
		{ uid = "weekly-dungeon-rotation", name = "Weekly Dungeon Quest (rotates)", questIDs = { 93751, 93752, 93753, 93754, 93758 }, zone = "Silvermoon City", children = {} },
		{ uid = "quest-98220", name = "Altar of Fangs", questID = 98220, zone = "Vaults of Atal'Utek", children = {} },
		-- Showdown on Val / Naigtal - ANOTHER rotating pool (confirmed by
		-- the user 2026-08-14: "if Val is active one week Naigtal will be
		-- active the next"), same shape as the dungeon board above. Normal
		-- and Heroic stay separate pools from each other since not every
		-- player runs Heroic and they're independently completable.
		-- Tagged by pickup NPC (Riftblade Maella, primary location
		-- Silvermoon City) - confirmed 2026-08-15, same reasoning as the
		-- dungeon board above.
		{ uid = "showdown-rotation-normal", name = "Showdown Zone (rotates)", questIDs = { 96713, 96716, 96717 }, zone = "Silvermoon City", children = {} },
		{ uid = "showdown-rotation-heroic", name = "Showdown Zone (Heroic, rotates)", questIDs = { 96714, 96718 }, zone = "Silvermoon City", children = {} },
		-- Batch from the dev-only auto-detection tool's export report
		-- (2026-08-12), each individually verified against Wowhead before
		-- being added - not a raw dump. Left OUT: Tracking Quest (75511,
		-- Blizzard's own "Hidden Quest" type - not meant to be player-facing)
		-- and Special Assignment: Capstone 1 - Unlock (91193, an unlock/
		-- prerequisite step rather than the actual reward quest).
		-- isRotating = true - Blizzard's own live data tagged these as
		-- "recurring" (Enum.QuestFrequency.ResetByScheduler) when detected,
		-- confirming they're task/world-quest-style content with a real
		-- on/off availability window, not a fixed always-there weekly.
		-- RenderItemTree hides these entirely when XComp.Data:IsItemActive()
		-- says they're not currently live.
		{ uid = "quest-94385", name = "Void Assaults: Eversong Woods", questID = 94385, zone = "Eversong Woods", isRotating = true, children = {} },
		{ uid = "quest-94386", name = "Void Assaults: Zul'Aman", questID = 94386, zone = "Zul'Aman", isRotating = true, children = {} },
		{ uid = "quest-96640", name = "Bounty of the Cursed", questID = 96640, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		-- Murder Row (93752) is part of the rotating dungeon-board pool
		-- above, not a standalone item - see "Weekly Dungeon Quest (rotates)".
		{ uid = "quest-95440", name = "Housewarming", questID = 95440, zone = "Housing", children = {} },
		{ uid = "quest-95413", name = "Community Engagement", questID = 95413, zone = "Housing", children = {} },
		{ uid = "quest-95416", name = "Going Postal", questID = 95416, zone = "Housing", children = {} },
		{ uid = "quest-95438", name = "Lost Animals", questID = 95438, zone = "Housing", children = {} },
		{ uid = "quest-98204", name = "Cursed Keepsake", questID = 98204, zone = "Housing", children = {} },
		-- Purging the Vaults/Turn Back the Surge - Blizzard tagged these
		-- plain "Weekly" (not ResetByScheduler) when detected, so NOT
		-- marked isRotating - standard fixed weekly resets, not a
		-- pick-one-of-several rotation.
		{ uid = "quest-95520", name = "Purging the Vaults", questID = 95520, zone = "Vaults of Atal'Utek", children = {} },
		{ uid = "quest-96995", name = "Turn Back the Surge", questID = 96995, zone = "The Coiled Isle", children = {} },
		{ uid = "quest-98419", name = "Shoulder to Shoulder", questID = 98419, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		{ uid = "quest-96642", name = "Decisive Incursions", questID = 96642, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		{ uid = "quest-98232", name = "Midnight: Vaults of Atal'Utek", questID = 98232, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		-- Confirmed by Jason 2026-08-16, flagged "recurring" (ResetByScheduler)
		-- when live-detected, same as the other Vaults of Atal'Utek isRotating items.
		{ uid = "quest-96643", name = "From Whence it Came", questID = 96643, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		{ uid = "quest-98420", name = "What's Out There?", questID = 98420, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		{ uid = "quest-96644", name = "Essence of Malice", questID = 96644, zone = "Vaults of Atal'Utek", isRotating = true, children = {} },
		-- Confirmed by Jason 2026-08-17 - both Naigtal.
		{ uid = "quest-97086", name = "Dangerous Enemies: Naigtal (Heroic)", questID = 97086, zone = "Naigtal", isRotating = true, children = {} },
		{ uid = "quest-96942", name = "Oh Captain, Die Captain!", questID = 96942, zone = "Naigtal", children = {} },
		-- Batch from real Wowhead research (2026-08-17), all verified before
		-- adding - see compendium_changelog_dev.md for the full research
		-- notes. "More Disruption" pairs with the already-added "Dangerous
		-- Enemies: Naigtal (Heroic)" above.
		{ uid = "quest-97087", name = "More Disruption: Naigtal (Heroic)", questID = 97087, zone = "Naigtal", isRotating = true, children = {} },
		{ uid = "quest-96029", name = "Special Assignment: Face the Swarm", questID = 96029, zone = "The Coiled Isle", isRotating = true, children = {} },
		{ uid = "quest-94795", name = "Special Assignment: Agents of the Shield", questID = 94795, zone = "Voidstorm", isRotating = true, children = {} },
		{ uid = "quest-94391", name = "Special Assignment: Push Back the Light", questID = 94391, zone = "Harandar", isRotating = true, children = {} },
		{ uid = "quest-91700", name = "Darkness Unmade", questID = 91700, zone = "Voidstorm", children = {} },
		{ uid = "quest-96941", name = "A Pertinent Punishment", questID = 96941, zone = "Val", isRotating = true, children = {} },
		{ uid = "quest-97128", name = "Lair: Nymrissa Wavecaller", questID = 97128, zone = "Tidebound Grotto", children = {} },
		{ uid = "quest-89268", name = "Lost Legends", questID = 89268, zone = "Harandar", children = {} },
		-- The REAL trackable "Shade and Claw" quest is 92139, NOT 95435 -
		-- 95435 is just an Emissary wrapper with no combat objectives of its
		-- own, 92139 is the actual Capstone World Quest with real kill/
		-- destroy objectives. Confirmed via Wowhead's own See-Also link and
		-- Relevant Locations box.
		{ uid = "quest-92139", name = "Special Assignment: Shade and Claw", questID = 92139, zone = "Eversong Woods", isRotating = true, children = {} },
		-- No fixed zone (multi-zone/event-based content, same treatment as
		-- The World Awaits) - falls back to grouping under its category
		-- label instead of a zone section.
		{ uid = "quest-95468", name = "Hope in the Darkest Corners", questID = 95468, children = {} },
		{ uid = "quest-89507", name = "Abundant Offerings", questID = 89507, children = {} },
		{ uid = "quest-93608", name = "A Burning Path Through Time", questID = 93608, children = {} },
		{ uid = "quest-93784", name = "A Gnawing Void of Curiosity", questID = 93784, zone = "Silvermoon City", children = {} },
		-- The "Prey" hunt system - player picks the zone, so no fixed zone
		-- tag. A Nightmarish Task is the weekly capstone tying the two
		-- Nightmare-tier hunts together.
		{ uid = "quest-95021", name = "Prey: Janoa the Fang (Nightmare)", questID = 95021, children = {} },
		{ uid = "quest-95024", name = "Prey: Kadani the Claw (Nightmare)", questID = 95024, children = {} },
		{ uid = "quest-94446", name = "A Nightmarish Task", questID = 94446, children = {} },
	}
	for _, item in ipairs(seedItems) do
		table.insert(weeklyEvents.items, item)
	end

	local worldQuests = weeklyType.categories[7]
	local worldQuestItems = {
		{ uid = "quest-96492", name = "Special Assignment: Demand and Supply", questID = 96492, zone = "The Coiled Isle", isRotating = true, children = {} },
		{ uid = "quest-96307", name = "Special Assignment: Wraith Wrath", questID = 96307, zone = "The Coiled Isle", isRotating = true, children = {} },
		{ uid = "quest-94865", name = "Special Assignment: What Remains of a Temple Broken", questID = 94865, zone = "Zul'Aman", isRotating = true, children = {} },
		-- Confirmed 2026-08-17: "add it in. If stuff comes up that we were
		-- wrong, we can just change it" - real player testing is expected to
		-- surface corrections, not a reason to hold off adding. Detected as
		-- plain "weekly" (not "recurring"/ResetByScheduler), so NOT marked
		-- isRotating - same standard-fixed-weekly treatment as Purging the
		-- Vaults/Turn Back the Surge. No zone (battleground-based, "Win 4
		-- Battleground matches" - not tied to any world zone).
		{ uid = "quest-93593", name = "A Call to Battle", questID = 93593, children = {} },
		-- Not zone-specific content itself (just "complete 10 world quests
		-- anywhere"), but the quest is picked up from an NPC in Silvermoon
		-- City - tagged by pickup location per Jason's explicit call
		-- 2026-08-15: "probably Silver Moon would be the correct tag...
		-- tag it in the spot wherever the NPC that gives it comes from."
		{ uid = "quest-93605", name = "The World Awaits", questID = 93605, zone = "Silvermoon City", children = {} },
		{ uid = "quest-94866", name = "Special Assignment: Ours Once More!", questID = 94866, zone = "Zul'Aman", isRotating = true, children = {} },
		{ uid = "quest-92848", name = "Special Assignment: The Grand Magister's Drink", questID = 92848, zone = "Eversong Woods", isRotating = true, children = {} },
		{ uid = "quest-89354", name = "Preparing for Battle", questID = 89354, zone = "Voidstorm", isRotating = true, children = {} },
		{ uid = "quest-94743", name = "Special Assignment: Precision Excision", questID = 94743, zone = "Voidstorm", isRotating = true, children = {} },
	}
	-- daily-cadence "Prey" content and worldQuestItems both feed the same
	-- Weekly-type World Quests category above; this one's a real Daily,
	-- inserted separately below into the Daily type's own World Quests
	-- category.
	for _, item in ipairs(worldQuestItems) do
		table.insert(worldQuests.items, item)
	end

	local professions = weeklyType.categories[4]
	table.insert(professions.items, { uid = "quest-93691", name = "Blacksmithing Services Requested", questID = 93691, children = {} })
	table.insert(professions.items, { uid = "quest-93695", name = "Leatherworking Services Requested", questID = 93695, zone = "Silvermoon City", children = {} })

	-- Daily-frequency housing/neighborhood content - bucketed under Custom
	-- (not "Weekly Events", which would read wrong under the Daily type).
	local dailyType = currentTier.types[1]
	local dailyCustom = dailyType.categories[8]
	local dailyItems = {
		{ uid = "quest-95336", name = "Frenzied Fossicking", questID = 95336, zone = "Housing", children = {} },
		{ uid = "quest-95407", name = "Autumnal Addresses", questID = 95407, zone = "Housing", children = {} },
		{ uid = "quest-95768", name = "My Stuff's Better Than Your Stuff", questID = 95768, zone = "Housing", children = {} },
		{ uid = "quest-95673", name = "Suspicious Scare-gull", questID = 95673, zone = "Housing", children = {} },
	}
	for _, item in ipairs(dailyItems) do
		table.insert(dailyCustom.items, item)
	end

	local dailyWorldQuests = dailyType.categories[7]
	table.insert(dailyWorldQuests.items, { uid = "quest-96528", name = "Prey: Anguish from Beyond", questID = 96528, zone = "The Coiled Isle", children = {} })

	-- Legacy tier - old-expansion content, confirmed via Wowhead as
	-- Battle for Azeroth (Azerite), The War Within (Lynx Rescue, Titanic
	-- Resurgence), not Midnight, so these belong under Legacy rather than
	-- Current.
	local legacyTier = D.Catalog.tiers[2]
	local legacyWeekly = legacyTier.types[2]
	local legacyWorldQuests = legacyWeekly.categories[7]
	local legacyItems = {
		{ uid = "quest-53436", name = "Azerite for the Alliance", questID = 53436, zone = "Legacy", isRotating = true, children = {} },
		{ uid = "quest-82158", name = "Special Assignment: Lynx Rescue", questID = 82158, zone = "Legacy", isRotating = true, children = {} },
		{ uid = "quest-82154", name = "Special Assignment: Titanic Resurgence", questID = 82154, zone = "Legacy", isRotating = true, children = {} },
		{ uid = "quest-82155", name = "Special Assignment: Shadows Below", questID = 82155, zone = "Legacy", isRotating = true, children = {} },
		-- Real Wowhead research batch, 2026-08-17.
		{ uid = "quest-82156", name = "Special Assignment: When the Deeps Stir", questID = 82156, zone = "Legacy", isRotating = true, children = {} },
		{ uid = "quest-82157", name = "Special Assignment: Rise of the Colossals", questID = 82157, zone = "Legacy", isRotating = true, children = {} },
		{ uid = "quest-72291", name = "Story of a Memorable Victory", questID = 72291, zone = "Legacy", children = {} },
		{ uid = "quest-82946", name = "Rollin' Down in the Deeps", questID = 82946, zone = "Legacy", children = {} },
		-- "Making a Deposit" x3 (89061/89062/89063) - confirmed genuinely
		-- indistinguishable on Wowhead (identical text/rewards/NPC), same
		-- rotating-pool treatment as the dungeon board. K'aresh/Ghosts of
		-- K'aresh (patch 11.2.0) - older than Midnight, so Legacy.
		{ uid = "making-a-deposit-rotation", name = "Making a Deposit (rotates)", questIDs = { 89061, 89062, 89063 }, zone = "Legacy", children = {} },
	}
	for _, item in ipairs(legacyItems) do
		table.insert(legacyWorldQuests.items, item)
	end

	-- Sureki Incursion: Southern Swarm - the one Legacy item detected as a
	-- daily rather than weekly, so it needs the Legacy tier's Daily type
	-- populated too, not just Weekly like everything else above.
	local legacyDaily = legacyTier.types[1]
	table.insert(legacyDaily.categories[7].items,
		{ uid = "quest-87477", name = "Sureki Incursion: Southern Swarm", questID = 87477, zone = "Legacy", children = {} })
end

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
			if item.questIDs then
				for _, qid in ipairs(item.questIDs) do
					if qid == questID then return item end
				end
			end
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

	-- questIDs (plural) is for a ROTATING single weekly/daily slot - only
	-- ONE of the listed quests is actually live/offered in any given cycle
	-- (e.g. the "dungeon of the week" board only ever has ONE of the 5
	-- possible dungeon quests active at a time - confirmed by the user
	-- 2026-08-13, "it's trying to make every single one of those a weekly
	-- quest at the same time. That's not how it works"). The item as a
	-- whole is complete if ANY one of them is flagged completed - whichever
	-- one wasn't this cycle's active quest was never offered in the first
	-- place, so it can never itself be flagged, and never falsely blocks
	-- the item from reading complete.
	if item.questIDs then
		local isComplete = false
		for _, qid in ipairs(item.questIDs) do
			if C_QuestLog.IsQuestFlaggedCompleted(qid) then
				isComplete = true
				break
			end
		end
		return isComplete, nil, nil, false
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

-- Whether this item is CURRENTLY offered/active this cycle - not every
-- catalog item has a fixed weekly slot; a lot of the rotating content
-- (Special Assignments, Void Assaults, Showdown zones, etc.) only becomes
-- available/completable at certain times, not simultaneously every week.
-- C_TaskQuest.IsActive is the real, direct Blizzard check for this (same
-- system that drives World Quest availability) - confirmed real API,
-- not guessed. Returns false for anything that was never a task-type
-- quest to begin with (regular NPC-given quests like housing weeklies),
-- so a false result does NOT necessarily mean "not available" for those -
-- only meaningful as a positive "this is up right now" signal.
function D:IsItemActive(item)
	if item.questIDs then
		for _, qid in ipairs(item.questIDs) do
			if C_TaskQuest.IsActive(qid) then return true end
		end
		return false
	end
	if not item.questID then return false end
	return C_TaskQuest.IsActive(item.questID)
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

-- Daily/Weekly items still left across BOTH tiers (Current + Legacy),
-- matching type key "daily"/"weekly" regardless of which tier they're under
-- - same "type is shared across tiers" rule CountTier already applies. Used
-- by the minimized tracker bar's "D/W" counts.
function D:GetDailyWeeklyLeft()
	local dailyCompleted, dailyTotal, weeklyCompleted, weeklyTotal = 0, 0, 0, 0
	for _, tier in ipairs(self.Catalog.tiers) do
		for _, typeSection in ipairs(tier.types) do
			if XComp.Options:IsTypeEnabled(typeSection.key) then
				local c, t = self:CountType(typeSection)
				if typeSection.key == "daily" then
					dailyCompleted = dailyCompleted + c
					dailyTotal = dailyTotal + t
				elseif typeSection.key == "weekly" then
					weeklyCompleted = weeklyCompleted + c
					weeklyTotal = weeklyTotal + t
				end
			end
		end
	end
	return dailyTotal - dailyCompleted, weeklyTotal - weeklyCompleted
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
		if item.questIDs then
			-- Rotating pool (e.g. "dungeon of the week") - list every
			-- possible quest ID's link, but frequency mismatch-checking is
			-- skipped since only ONE is ever actually live/cached at a time.
			local links = {}
			for _, qid in ipairs(item.questIDs) do
				table.insert(links, string.format("id %d (https://www.wowhead.com/quest=%d)", qid, qid))
			end
			table.insert(lines, string.format("%s | %s - rotating pool: %s", path, item.name, table.concat(links, ", ")))
		elseif not item.questID then
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
-- Untracked repeatable quest detection (2026-08-12) - the local Icy Veins
-- cross-referencing tool can only ever catch quests that site has already
-- published, which misses brand-new zone content until a guide exists for
-- it. This catches it directly instead, straight from the player's own
-- quest log, using the same C_QuestLog.GetInfo().frequency technique
-- RunDiagnostics already relies on - no need to wait on a third-party site.
-------------------------------------------------
local function EnsureUntrackedTable()
	XComp_DB.untrackedQuests = XComp_DB.untrackedQuests or {}
	return XComp_DB.untrackedQuests
end

-- Checks a single questID: if it's a live Daily/Weekly/recurring quest (per
-- the game's own classification) and isn't anywhere in the catalog yet,
-- records it. Returns true if this was a NEW find (not already recorded),
-- so callers can decide whether to show a one-time notification.
--
-- Enum.QuestFrequency has a THIRD value beyond Daily/Weekly - ResetByScheduler
-- (confirmed against Blizzard's own generated API docs, 2026-08-12) - for
-- content whose repeat cadence is driven by some other recurring system
-- instead of the standard daily/weekly reset. Missing this was almost
-- certainly why some real repeatable quests weren't getting caught. Tagged
-- as "recurring" rather than guessed at daily/weekly, since the enum alone
-- doesn't say which cadence it actually follows - InjectAutoDetectedItems
-- below treats it as weekly for bucketing purposes (most common case for
-- this kind of content), and the export report keeps the honest
-- "recurring" label so it gets double-checked by hand.
function D:CheckQuestForCatalog(questID)
	if not questID then return false end
	if self:FindItemByQuestID(questID) then return false end -- already tracked

	local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	if not logIndex then return false end
	local info = C_QuestLog.GetInfo(logIndex)
	if not info or not info.frequency then return false end

	local liveType
	if info.frequency == Enum.QuestFrequency.Daily then
		liveType = "daily"
	elseif info.frequency == Enum.QuestFrequency.Weekly then
		liveType = "weekly"
	elseif info.frequency == Enum.QuestFrequency.ResetByScheduler then
		liveType = "recurring"
	end
	if not liveType then return false end -- one-time quest, not what we're after

	local untracked = EnsureUntrackedTable()
	if untracked[questID] then return false end -- already recorded

	-- Best-guess zone (2026-08-16, explicit request - "it should tell you
	-- which zone it's from" instead of making Jason look each one up by
	-- hand). C_QuestLog.GetNextWaypoint (already used elsewhere in this
	-- file for the TomTom Map button, so confirmed real/working) gives a
	-- mapID for the quest; C_Map.GetMapInfo turns that into a real zone
	-- name. Not always available (e.g. quest has no active waypoint that
	-- moment), so this is a helpful guess to double-check by hand, not a
	-- guaranteed answer.
	local zoneName
	local mapID = select(1, C_QuestLog.GetNextWaypoint(questID))
	if mapID then
		local mapInfo = C_Map.GetMapInfo(mapID)
		zoneName = mapInfo and mapInfo.name
	end

	untracked[questID] = { name = info.title, frequency = liveType, firstSeen = time(), zoneGuess = zoneName }
	return true, info.title, liveType
end

-- Scans the WHOLE current quest log, not just newly-accepted quests - so
-- anything picked up before this update ever ran gets caught too, not just
-- quests accepted from here on out.
function D:ScanQuestLogForUntracked()
	local found = {}
	local numEntries = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, numEntries do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			if self:CheckQuestForCatalog(info.questID) then
				table.insert(found, info.questID)
			end
		end
	end
	return found
end

-- Prunes any entry that's since been manually added to the real catalog -
-- without this, GetUntrackedReport kept listing quests forever after they
-- were already tracked (real bug found 2026-08-16: everything added to
-- Data.lua earlier tonight was still showing up here, since nothing ever
-- cleared the saved untrackedQuests entry once the real catalog entry
-- existed).
function D:GetUntrackedQuests()
	local untracked = EnsureUntrackedTable()
	local list = {}
	for questID, entry in pairs(untracked) do
		if self:FindItemByQuestID(questID) then
			untracked[questID] = nil
		else
			table.insert(list, { questID = questID, name = entry.name, frequency = entry.frequency, firstSeen = entry.firstSeen, zoneGuess = entry.zoneGuess })
		end
	end
	table.sort(list, function(a, b) return a.firstSeen > b.firstSeen end)
	return list
end

function D:ClearUntrackedQuest(questID)
	local untracked = EnsureUntrackedTable()
	untracked[questID] = nil
end

-- Copyable export report (same shape/purpose as RunDiagnostics) - the
-- auto-detected Custom-category items only live on THIS player's account;
-- getting them properly sorted into the real shared catalog (so every
-- player gets them, not just whoever happened to pick the quest up first)
-- means handing this list off by hand, same as the very first 8 seed items
-- were. One line per detected quest: name, ID, Daily/Weekly, Wowhead link.
function D:GetUntrackedReport()
	local list = self:GetUntrackedQuests()
	local lines = {}
	table.insert(lines, string.format("Xal's Compendium - %d auto-detected quest%s not yet in the shared catalog.",
		#list, #list == 1 and "" or "s"))
	table.insert(lines, "")
	for _, entry in ipairs(list) do
		local zonePart = entry.zoneGuess and (" - " .. entry.zoneGuess .. " (best guess)") or ""
		table.insert(lines, string.format("%s (id %d) - %s%s - https://www.wowhead.com/quest=%d",
			entry.name, entry.questID, entry.frequency, zonePart, entry.questID))
	end
	return lines
end

-- Turns every recorded untracked find into a REAL, live, trackable catalog
-- item under Current -> Daily/Weekly -> Custom (explicit follow-up to the
-- detection above, 2026-08-12: "is there a way we can... make it so it
-- automatically acknowledges those in the addon?"). Sourced entirely from
-- XComp_DB.untrackedQuests (account-wide, persists across sessions/reloads)
-- rather than needing a Data.lua edit - the Catalog table itself is rebuilt
-- fresh every session, so this has to re-run every time XComp_DB is
-- available, not just once. Safe to call repeatedly - skips anything
-- already present (checked via FindItemByQuestID) instead of duplicating.
function D:InjectAutoDetectedItems()
	local untracked = EnsureUntrackedTable()
	local currentTier = self.Catalog.tiers[1] -- "current" - freshly detected content is never Legacy
	for questID, entry in pairs(untracked) do
		if not self:FindItemByQuestID(questID) then
			-- "recurring" (Enum.QuestFrequency.ResetByScheduler) doesn't map
			-- to a real type key on its own - bucketed under Weekly as the
			-- most common cadence for that kind of content, since it still
			-- needs to land somewhere to be trackable at all. The export
			-- report keeps the honest "recurring" label so this guess gets
			-- double-checked by hand when it's added to the real catalog.
			local bucketKey = entry.frequency
			if bucketKey == "recurring" then bucketKey = "weekly" end
			local typeSection
			for _, t in ipairs(currentTier.types) do
				if t.key == bucketKey then typeSection = t break end
			end
			if typeSection then
				local customCategory
				for _, c in ipairs(typeSection.categories) do
					if c.key == "custom" then customCategory = c break end
				end
				if customCategory then
					table.insert(customCategory.items, {
						uid = "quest-" .. questID,
						name = entry.name,
						questID = questID,
						children = {},
					})
				end
			end
		end
	end
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
