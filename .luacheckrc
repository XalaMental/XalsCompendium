-- .luacheckrc
-- Xal's Compendium
--
-- Scoped to the actual WoW API calls and globals this addon uses (not a
-- copy-pasted full addon's config) - add to `globals`/`read_globals` as new
-- API calls get added, rather than pulling in a giant generic list.
std = "lua51"

-- This addon's own cross-file globals (declared in Core.lua, attached to by
-- every other file).
globals = {
    "XComp",
    "XComp_DB",
    "XComp_CharDB",
    "StaticPopupDialogs", -- a real mutable table addons add popup entries to
    "ColorPickerFrame", -- Blizzard's own color picker, fields set directly on it
    "SLASH_XALSCOMPENDIUM1",
    "SlashCmdList",
}

-- Read-only: real WoW client API/globals + the bundled libs' own globals.
read_globals = {
    "CreateFrame",
    "CreateFont",
    "UIParent",
    "GameTooltip",
    "WeeklyRewardsFrame",
    "PixelUtil",
    "LibStub",
    "hooksecurefunc",
    "tinsert",
    "wipe",
    "UISpecialFrames",
    "IsShiftKeyDown",
    "UnitName",
    "GetRealmName",
    "GetAverageItemLevel",
    "StaticPopup_Show",
    "StaticPopup_Hide",
    "Settings",
    "C_AddOns",
    "C_Timer",
    "C_QuestLog",
    "C_DateAndTime",
    "C_WeeklyRewards",
    "C_CurrencyInfo",
    "C_Reputation",
    "C_TaskQuest",
    "C_Map",
    "time",
    "date",
    "Enum",
    "UnitClass",
    "UIFrameFadeOut",
    "ChatFontNormal",
    "TomTom", -- optional third-party addon, checked with IsAddOnLoaded before use
    "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_SetText",
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton",
    "QuestMapFrame_OpenToQuestDetails",
}

-- Textures/backdrop tables and long chained SetPoint calls read as "unused
-- variable"/line-length noise in generated UI code like this - not real bugs.
max_line_length = false
unused_args = false
