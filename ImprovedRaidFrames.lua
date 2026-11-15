-- Improved Raid Frames is a World of Warcraft® user interface addon, based on Enhanced Raid Frames.
-- Copyright (c) 2017-2023 Britt W. Yazel
-- This code is licensed under the MIT license (see LICENSE for details)

-- Backport based on: v3.12.6

--- ImprovedRaidFrames is the main addon object for the Improved Raid Frames add-on.
---@class ImprovedRaidFrames : AceAddon-3.0 @The main addon object for the Improved Raid Frames add-on
_G.ImprovedRaidFrames = LibStub("AceAddon-3.0"):NewAddon("ImprovedRaidFrames", "AceTimer-3.0", "AceHook-3.0",
		"AceEvent-3.0", "AceBucket-3.0", "AceConsole-3.0", "AceSerializer-3.0")

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

-- Import libraries
local L = LibStub("AceLocale-3.0"):GetLocale("ImprovedRaidFrames")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")

-- The addon versions Improved Raid Frames was written and tested against
ImprovedRaidFrames.TESTED_CRF_VERSION = "1.14"
ImprovedRaidFrames.TESTED_CLASSICAPI_VERSION = "1.32"

-- Detect the addons we replace. If they are still enabled, we leave their features to them so nothing runs twice.
ImprovedRaidFrames.erfLoaded = IsAddOnLoaded("EnhancedRaidFrames") and true or false
ImprovedRaidFrames.healExLoaded = IsAddOnLoaded("CompactRaidFrame_HealEx") and true or false

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Called directly after the addon is fully loaded.
--- We do initialization tasks here, such as loading our saved variables or setting up slash commands.
function ImprovedRaidFrames:OnInitialize()
	-- The replaced addons may load after us on some clients, so check again now that all addons are loaded
	self.erfLoaded = self.erfLoaded or (IsAddOnLoaded("EnhancedRaidFrames") and true or false)
	self.healExLoaded = self.healExLoaded or (IsAddOnLoaded("CompactRaidFrame_HealEx") and true or false)

	-- Set up our database
	self:InitializeDatabase()

	-- Run our database migration if necessary
	self:MigrateDatabase()

	-- Setup config panels in the Blizzard interface options
	self:InitializeConfigPanels()

	-- Register callbacks for profile switching
	self.db.RegisterCallback(self, "OnProfileChanged", function()
		self:MigrateDatabase()
		self:RefreshConfig()
	end)
	self.db.RegisterCallback(self, "OnProfileCopied", function()
		self:MigrateDatabase()
		self:RefreshConfig()
	end)
	self.db.RegisterCallback(self, "OnProfileReset", function()
		self:MigrateDatabase()
		self:RefreshConfig()
	end)
end

--- Called during the PLAYER_LOGIN event when most of the data provided by the game is already present.
--- We perform more startup tasks here, such as registering events, hooking functions, creating frames, or getting
--- information from the game that wasn't yet available during :OnInitialize()
function ImprovedRaidFrames:OnEnable()
	-- Tell the user about anything that could affect how we work
	self:CheckDependencies()

	-- Start the heal prediction module straight away, so incoming heals are tracked from the first frame update
	self:EnableHealPrediction()

	local function Await(Init) -- 3.3.5a Client: Hacky, but certain unit information is unavailable, so wait.
		if ( Init ) then
			self:ScheduleTimer(Await, .5)
			self:UnregisterEvent(Init, Await)
		else
			-- Populate our starting config values
			self:RefreshConfig()

			-- Run a full update of all auras for a starting point
			self:UpdateAllAuras()

			-- Force a full update of all frames when a raid target icon changes
			self:RegisterEvent("RAID_TARGET_UPDATE", function()
				self:UpdateAllTargetMarkers()
			end)

			-- Re-check which debuff types we can dispel when our spells change
			self:RegisterEvent("SPELLS_CHANGED", function()
				self:UpdateDispelTypes()
			end)
			self:UpdateDispelTypes()

			-- Ask the server for playerbot heal data if the option is enabled
			self:UpdateBotHealSubscription()

			-- Offer to copy the settings from Enhanced Raid Frames, once
			self:OfferEnhancedRaidFramesImport()

			-- Register our slash command to open the config panel
			self:RegisterChatCommand("irf", function()
				InterfaceOptionsFrame_OpenToCategory("Improved Raid Frames")
			end)
		end
	end

	self:RegisterEvent("PLAYER_ENTERING_WORLD", Await)
end

--- Called when our addon is manually being disabled during a running session.
--- We primarily use this to unhook scripts, unregister events, or hide frames that we created.
function ImprovedRaidFrames:OnDisable()
	-- Empty --
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Create a table containing our default database values
function ImprovedRaidFrames:InitializeDatabase()
	-- Set up database defaults
	local defaults = self:CreateDefaults()

	-- Create database object
	self.db = AceDB:New("ImprovedRaidFramesDB", defaults) --ImprovedRaidFramesDB is our saved variable table

	-- Enhance database and profile options using LibDualSpec
	if not self.isWoWClassicEra then
		-- Not available in Classic Era
		-- Enhance the database object with per spec profile features
		LibStub("LibDualSpec-1.0"):EnhanceDatabase(self.db, "ImprovedRaidFrames")
		-- Enhance the profile options table with per spec profile features
		LibStub("LibDualSpec-1.0"):EnhanceOptions(AceDBOptions:GetOptionsTable(self.db), self.db)
	end
end

--- Set up our configuration panels and add them to the Blizzard interface options
function ImprovedRaidFrames:InitializeConfigPanels()
	-- Build our config panels
	AceConfigRegistry:RegisterOptionsTable("Improved Raid Frames", self:CreateGeneralOptions())
	AceConfigRegistry:RegisterOptionsTable("IRF Indicator Options", self:CreateIndicatorOptions())
	AceConfigRegistry:RegisterOptionsTable("IRF Target Marker Options", self:CreateIconOptions())
	AceConfigRegistry:RegisterOptionsTable("IRF Heal Prediction Options", self:CreateHealPredictionOptions())
	AceConfigRegistry:RegisterOptionsTable("IRF Profiles", AceDBOptions:GetOptionsTable(self.db))
	AceConfigRegistry:RegisterOptionsTable("IRF Import Export Profile Options", self:CreateProfileImportExportOptions())

	-- Add to config panels to in-game interface options
	AceConfigDialog:AddToBlizOptions("Improved Raid Frames", "Improved Raid Frames")
	AceConfigDialog:AddToBlizOptions("IRF Indicator Options", L["Indicator Options"], "Improved Raid Frames")
	AceConfigDialog:AddToBlizOptions("IRF Target Marker Options", L["Target Marker Options"], "Improved Raid Frames")
	AceConfigDialog:AddToBlizOptions("IRF Heal Prediction Options", L["Heal Prediction"], "Improved Raid Frames")
	AceConfigDialog:AddToBlizOptions("IRF Profiles", L["Profiles"], "Improved Raid Frames")
	AceConfigDialog:AddToBlizOptions("IRF Import Export Profile Options",
			(L["Profile"] .. " " .. L["Import"] .. "/" .. L["Export"]), "Improved Raid Frames")
end

--- Refresh everything that is affected by changes to the configuration
function ImprovedRaidFrames:RefreshConfig()
	self:GenerateAuraStrings()
	self:UpdateRangeChecker()
	self:UpdateScale()
	self:ForEachFrame(function(frame)
		self:UpdateIndicators(frame, true)
		self:UpdateBackgroundAlpha(frame)
		self:UpdateInRange(frame)
		self:UpdateTargetMarker(frame, true)
	end)
	-- Rescan auras, so changes to the watched auras show straight away rather than at the next aura change
	self:UpdateAllAuras()
	self:UpdateAllStockAuraVisibility()
	self:UpdateHealPredictionOptions()
	self:UpdateBotHealSubscription()
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Check the addons we depend on and the addons we replace, and tell the user about anything relevant.
function ImprovedRaidFrames:CheckDependencies()
	-- Version notice for the addons we build on
	local crfVersion = GetAddOnMetadata("CompactRaidFrame", "Version")
	local apiVersion = GetAddOnMetadata("!!!ClassicAPI", "Version")
	if crfVersion ~= self.TESTED_CRF_VERSION or apiVersion ~= self.TESTED_CLASSICAPI_VERSION then
		self:Print(string.format(L["versionNotice"], tostring(crfVersion), tostring(apiVersion),
				self.TESTED_CRF_VERSION, self.TESTED_CLASSICAPI_VERSION))
	end

	-- Features we had to switch off because something we rely on is missing
	if self.missingFeatures and #self.missingFeatures > 0 then
		self:Print(L["missingFeatures"] .. " " .. table.concat(self.missingFeatures, ", "))
	end

	-- Addons we replace
	if self.erfLoaded then
		self:Print(L["erfLoadedNotice"])
	end
	if self.healExLoaded then
		self:Print(L["healExLoadedNotice"])
	end
end

--- Record a feature that could not be enabled, so it can be reported once at login.
---@param name string @The name of the feature
function ImprovedRaidFrames:FeatureUnavailable(name)
	self.missingFeatures = self.missingFeatures or {}
	table.insert(self.missingFeatures, name)
end
