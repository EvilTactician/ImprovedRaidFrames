-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

-- Import libraries
local L = LibStub("AceLocale-3.0"):GetLocale("ImprovedRaidFrames")

-- Constants
local THIRD_WIDTH = 1.25

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Populate our "Heal Prediction" options table for our Blizzard interface options
function ImprovedRaidFrames:CreateHealPredictionOptions()
	--- Shared setter: store the value and redraw the heal prediction
	local function Set(key)
		return function(_, value)
			self.db.profile[key] = value
			self:UpdateHealPredictionOptions()
		end
	end

	--- Shared getter
	local function Get(key)
		return function()
			return self.db.profile[key]
		end
	end

	--- The heal prediction options do nothing while the Heal Extension addon is still enabled
	local function HealExDisabled()
		return self.healExLoaded
	end

	local healPredictionOptions = {
		type = "group",
		name = L["Heal Prediction"],
		args = {
			instructions = {
				type = "description",
				name = L["healPredictionOptions_desc"],
				fontSize = "medium",
				order = 1,
			},
			healExNotice = {
				type = "description",
				name = self.RED_COLOR:WrapTextInColorCode(L["healExLoadedNotice"]),
				fontSize = "medium",
				hidden = function()
					return not self.healExLoaded
				end,
				order = 2,
			},
			-------------------------------------------------
			healHeader = {
				type = "header",
				name = L["Heal Prediction"],
				order = 10,
			},
			healPrediction = {
				type = "toggle",
				name = L["Incoming Heals"],
				desc = L["healPrediction_desc"],
				get = Get("healPrediction"),
				set = Set("healPrediction"),
				disabled = HealExDisabled,
				width = THIRD_WIDTH,
				order = 11,
			},
			healPredictionHots = {
				type = "toggle",
				name = L["Include Heals over Time"],
				desc = L["healPredictionHots_desc"],
				get = Get("healPredictionHots"),
				set = Set("healPredictionHots"),
				disabled = function()
					return self.healExLoaded or not self.db.profile.healPrediction
				end,
				width = THIRD_WIDTH,
				order = 12,
			},
			absorbs = {
				type = "toggle",
				name = L["Absorb Shields"],
				desc = L["absorbs_desc"],
				get = Get("absorbs"),
				set = Set("absorbs"),
				disabled = HealExDisabled,
				width = THIRD_WIDTH,
				order = 13,
			},
			healAbsorbs = {
				type = "toggle",
				name = L["Heal Absorbs"],
				desc = L["healAbsorbs_desc"],
				get = Get("healAbsorbs"),
				set = Set("healAbsorbs"),
				disabled = HealExDisabled,
				width = THIRD_WIDTH,
				order = 14,
			},
			-------------------------------------------------
			botHealsHeader = {
				type = "header",
				name = L["Playerbot Heals"],
				order = 20,
			},
			botHealsDescription = {
				type = "description",
				name = L["botHeals_longdesc"],
				fontSize = "medium",
				order = 21,
			},
			botHeals = {
				type = "toggle",
				name = L["Show Playerbot Heals"],
				desc = L["botHeals_desc"],
				get = Get("botHeals"),
				set = function(_, value)
					self.db.profile.botHeals = value
					self:UpdateBotHealSubscription()
				end,
				width = THIRD_WIDTH * 2,
				order = 22,
			},
			botHealsStatus = {
				type = "description",
				name = function()
					return L["Server module:"] .. " " .. self:GetBotHealStatusText()
				end,
				fontSize = "medium",
				order = 23,
			},
		}
	}

	return healPredictionOptions
end
