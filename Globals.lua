-- Improved Raid Frames is a World of Warcraft® user interface addon, based on Enhanced Raid Frames.
-- Copyright (c) 2017-2023 Britt W. Yazel
-- This code is licensed under the MIT license (see LICENSE for details)

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

-- Import libraries
local L = LibStub("AceLocale-3.0"):GetLocale("ImprovedRaidFrames")

-------------------------------------------------------------------------
-------------------------------------------------------------------------

-- Set Classic and Classic_Era flags
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
	ImprovedRaidFrames.isWoWClassicEra = true
elseif WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
	ImprovedRaidFrames.isWoWClassic = true
end

-- Declare Color Global Constants
ImprovedRaidFrames.NORMAL_COLOR = CreateColor(1.0, 0.82, 0.0) --the default game yellow text color
ImprovedRaidFrames.WHITE_COLOR = CreateColor(1.0, 1.0, 1.0) --default game white color for text
ImprovedRaidFrames.RED_COLOR = CreateColor(0.8, 0.1, 0.1) --solid red color
ImprovedRaidFrames.YELLOW_COLOR = CreateColor(1.0, 0.82, 0.0) --solid yellow color
ImprovedRaidFrames.GREEN_COLOR = CreateColor(0.6627, 0.8235, 0.4431) --poison text color
ImprovedRaidFrames.PURPLE_COLOR = CreateColor(0.6392, 0.1882, 0.7882) --curse text color
ImprovedRaidFrames.BROWN_COLOR = CreateColor(0.7804, 0.6118, 0.4314) --disease text color
ImprovedRaidFrames.BLUE_COLOR = CreateColor(0.0, 0.4392, 0.8706) --magic text color

-- Declare Global positions table
ImprovedRaidFrames.POSITIONS = {}
ImprovedRaidFrames.POSITIONS[1] = L["Top-Left"]
ImprovedRaidFrames.POSITIONS[2] = L["Top"]
ImprovedRaidFrames.POSITIONS[3] = L["Top-Right"]
ImprovedRaidFrames.POSITIONS[4] = L["Left"]
ImprovedRaidFrames.POSITIONS[5] = L["Center"]
ImprovedRaidFrames.POSITIONS[6] = L["Right"]
ImprovedRaidFrames.POSITIONS[7] = L["Bottom-Left"]
ImprovedRaidFrames.POSITIONS[8] = L["Bottom"]
ImprovedRaidFrames.POSITIONS[9] = L["Bottom-Right"]

-- Declare Global iconCache table with pre-populated values
ImprovedRaidFrames.iconCache = {}
ImprovedRaidFrames.iconCache["poison"] = [[Interface\ICONS\Ability_creature_poison_02]]
ImprovedRaidFrames.iconCache["disease"] = [[Interface\ICONS\Ability_creature_disease_02]]
ImprovedRaidFrames.iconCache["curse"] = [[Interface\ICONS\Ability_creature_cursed_03]]
ImprovedRaidFrames.iconCache["magic"] = [[Interface\ICONS\Spell_holy_dispelmagic]]

ImprovedRaidFrames.RAID_MARKER_COORDS = {
	{0, .25, 0, .25},
	{.25, .5, 0, .25},
	{.5, .75, 0, .25},
	{.75, 1, 0, .25},
	{0, .25, .25, .5},
	{.25, .5, .25, .5},
	{.5, .75, .25, .5},
	{.75, 1, .25, .5},
}

-- Dispel spells used for the "dispel" indicator wildcard (replaces LibDispel, which the 3.3.5a backport doesn't have).
-- Each spell lists the debuff types it removes. Any rank of the spell counts.
ImprovedRaidFrames.DISPEL_SPELLS = {
	[527] = { "Magic" }, -- Priest: Dispel Magic
	[528] = { "Disease" }, -- Priest: Cure Disease
	[552] = { "Disease" }, -- Priest: Abolish Disease
	[1152] = { "Poison", "Disease" }, -- Paladin: Purify
	[4987] = { "Magic", "Poison", "Disease" }, -- Paladin: Cleanse
	[526] = { "Poison", "Disease" }, -- Shaman: Cure Toxins
	[51886] = { "Curse", "Poison", "Disease" }, -- Shaman: Cleanse Spirit
	[2782] = { "Curse" }, -- Druid: Remove Curse
	[8946] = { "Poison" }, -- Druid: Cure Poison
	[2893] = { "Poison" }, -- Druid: Abolish Poison
	[475] = { "Curse" }, -- Mage: Remove Curse
}

-- Pet spells used for the "dispel" wildcard
ImprovedRaidFrames.DISPEL_PET_SPELLS = {
	[19505] = { "Magic" }, -- Warlock Felhunter: Devour Magic
}
