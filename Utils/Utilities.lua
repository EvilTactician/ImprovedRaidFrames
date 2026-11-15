-- Improved Raid Frames is a World of Warcraft® user interface addon, based on Enhanced Raid Frames.
-- Copyright (c) 2017-2023 Britt W. Yazel
-- This code is licensed under the MIT license (see LICENSE for details)

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

-- Import libraries
local L = LibStub("AceLocale-3.0"):GetLocale("ImprovedRaidFrames")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Test for whether or not we should continue processing a given unit
---@param frame table @The frame to test
---@param skipVisibilityCheck boolean @Process the frame even if it is hidden
---@param allowPets boolean @Also process pet frames (Enhanced Raid Frames only handled pets for range checks)
---@return boolean @Whether or not we should continue processing the unit
function ImprovedRaidFrames.ShouldContinue(frame, skipVisibilityCheck, allowPets)
	-- Don't do any work if the frame is nil
	if not frame then
		return false
	end

	-- Check that we have a unit, and only process player, raid, and party units
	if not frame.unit or (not frame.unit:find("player", 1, true)
			and not frame.unit:find("raid", 1, true)
			and not frame.unit:find("party", 1, true)) then
		return false
	end

	-- Pet frames only get the range fade, like they did with Enhanced Raid Frames
	if not allowPets and frame.unit:find("pet", 1, true) then
		return false
	end
	
	-- Check that we have a frame and that it is visible
	if not skipVisibilityCheck then
		-- Don't do any work if the raid frames aren't shown
		if not CompactRaidFrameContainer:IsShown() and CompactPartyFrame and not CompactPartyFrame:IsShown() then
			return false
		end

		-- Don't do any work if the frame isn't shown
		if not frame:IsShown() then
			return false
		end
	end

	return true
end

--- Serialize and compress the profile for copy+paste.
---@return string @The serialized and compressed profile
function ImprovedRaidFrames:SerializeAndCompressProfile()
	local serialized = self:Serialize(self.db.profile) -- Serialize the database into a single string value
	local compressed = LibDeflate:CompressZlib(serialized) -- Compress the serialized data
	local encoded = LibDeflate:EncodeForPrint(compressed) -- Encode the compressed data for print for easy copy+paste
	return encoded
end

--- Deserialize and decompress the profile from copy+paste.
---@param input string @The input string to deserialize and decompress
function ImprovedRaidFrames:DeserializeAndDecompressProfile(input)
	-- Stop here if the input is empty
	if input == "" then
		self:Print(L["No data to import."] .. " " .. L["Aborting."])
		return
	end

	-- Decode and check if decoding worked properly
	local decoded = LibDeflate:DecodeForPrint(input)
	if not decoded then
		self:Print(L["Decoding failed."] .. " " .. L["Aborting."])
		return
	end

	-- Decompress and verify if decompression worked properly
	local decompressed = LibDeflate:DecompressZlib(decoded)
	if not decompressed then
		self:Print(L["Decompression failed."] .. " " .. L["Aborting."])
		return
	end

	-- Deserialize the data and return it back into a table format
	local success, newProfile = self:Deserialize(decompressed)

	-- If we successfully deserialize, load the new table into the database
	if success and newProfile then
		for k, v in pairs(newProfile) do
			if type(v) == "table" then
				self.db.profile[k] = CopyTable(v)
			else
				self.db.profile[k] = v
			end
		end

		-- Apply the imported settings. (Enhanced Raid Frames re-created the database object here, which lost the profile
		-- change callbacks; the profile already falls back to the defaults for anything the import didn't include.)
		self:RefreshConfig()
	else
		self:Print(L["Data import Failed."] .. " " .. L["Aborting."])
	end
end

--- Check whether the Enhanced Raid Frames settings are available to copy (Enhanced Raid Frames must be enabled)
---@return boolean
function ImprovedRaidFrames:CanImportEnhancedRaidFrames()
	local erfDB = _G.EnhancedRaidFramesDB
	return type(erfDB) == "table" and type(erfDB.profiles) == "table" and next(erfDB.profiles) ~= nil
end

--- Copy all Enhanced Raid Frames profiles (and which character uses which profile) into Improved Raid Frames.
--- Our settings use the same layout, so the profiles can be copied as they are. A UI reload applies them.
function ImprovedRaidFrames:ImportEnhancedRaidFrames()
	if not self:CanImportEnhancedRaidFrames() then
		self:Print(L["erfImportUnavailable"])
		return
	end

	local erfDB = _G.EnhancedRaidFramesDB
	local sv = self.db.sv

	-- Profiles
	sv.profiles = sv.profiles or {}
	for name, profile in pairs(erfDB.profiles) do
		sv.profiles[name] = CopyTable(profile)
	end

	-- Which profile each character uses
	if type(erfDB.profileKeys) == "table" then
		sv.profileKeys = sv.profileKeys or {}
		for char, profileName in pairs(erfDB.profileKeys) do
			sv.profileKeys[char] = profileName
		end
	end

	-- Dual spec profile settings
	if type(erfDB.namespaces) == "table" and type(erfDB.namespaces["LibDualSpec-1.0"]) == "table" then
		sv.namespaces = sv.namespaces or {}
		sv.namespaces["LibDualSpec-1.0"] = CopyTable(erfDB.namespaces["LibDualSpec-1.0"])
	end

	self.db.global.erfImportOffered = true
	StaticPopup_Show("IMPROVEDRAIDFRAMES_RELOAD")
end

--- Offer to copy the Enhanced Raid Frames settings, once, if they are available
function ImprovedRaidFrames:OfferEnhancedRaidFramesImport()
	if self.db.global.erfImportOffered or not self:CanImportEnhancedRaidFrames() then
		return
	end
	self.db.global.erfImportOffered = true
	StaticPopup_Show("IMPROVEDRAIDFRAMES_ERF_IMPORT")
end

StaticPopupDialogs["IMPROVEDRAIDFRAMES_ERF_IMPORT"] = {
	text = L["erfImportPrompt"],
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ImprovedRaidFrames:ImportEnhancedRaidFrames()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["IMPROVEDRAIDFRAMES_RELOAD"] = {
	text = L["erfImportDone"],
	button1 = RELOADUI or "Reload UI",
	button2 = CANCEL,
	OnAccept = function()
		ReloadUI()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}
