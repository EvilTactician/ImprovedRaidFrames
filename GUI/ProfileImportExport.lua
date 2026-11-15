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

--- Populate our "Profile Import/Export" options table for our Blizzard interface options
function ImprovedRaidFrames:CreateProfileImportExportOptions()
	local import_export = {
		name = L["Profile"] .. " " .. L["Import"] .. "/" .. L["Export"],
		type = "group",
		order = 1,
		args = {
			Header = {
				order = 1,
				name = L["Profile"] .. " " .. L["Import"] .. "/" .. L["Export"],
				type = "header",
			},
			Instructions = {
				order = 2,
				name = L["ImportExport_Desc"],
				type = "description",
				fontSize = "medium",
			},
			TextBox = {
				order = 3,
				name = L["Import or Export the current profile:"],
				desc = self.RED_COLOR:WrapTextInColorCode(L["ImportExport_WarningDesc"]),
				type = "input",
				multiline = 22,
				confirm = function()
					return L["ImportWarning"]
				end,
				validate = false,
				set = function(self, input)
					ImprovedRaidFrames:DeserializeAndDecompressProfile(input)
				end,
				get = function()
					return ImprovedRaidFrames:SerializeAndCompressProfile()
				end,
				width = "full",
			},
		},
	}

	return import_export
end