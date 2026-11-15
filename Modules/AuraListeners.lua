-- Improved Raid Frames is a World of Warcraft® user interface addon, based on Enhanced Raid Frames.
-- Copyright (c) 2017-2023 Britt W. Yazel
-- This code is licensed under the MIT license (see LICENSE for details)

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

local UnitAura = C_UnitAura
local allAuraFilters = { "HELPFUL", "HARMFUL" }

-------------------------------------------------------------------------
-------------------------------------------------------------------------

-- Enhanced Raid Frames created its own UNIT_AURA listener frame for every raid frame and scanned each unit separately
-- from Compact Raid Frame. We scan right after Compact Raid Frame updates a frame's auras instead, which happens on
-- every UNIT_AURA for that unit (delivered by our shared event frame), on every full frame update (for example when the
-- group changes) and when entering or leaving combat. That covers everything the listener frames and the throttled
-- roster update in Enhanced Raid Frames did.
if CompactUnitFrame_UpdateAuras then
	hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
		if ImprovedRaidFrames.db and ImprovedRaidFrames.frames[frame] and not frame.onUpdateFrame then
			ImprovedRaidFrames:UpdateUnitAuras_Classic(frame)
		end
	end)
else
	ImprovedRaidFrames:FeatureUnavailable("aura indicators")
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Scans all raid frame units and updates the unitAuras table with all auras on each unit.
function ImprovedRaidFrames:UpdateAllAuras()
	self:ForEachFrame(function(frame)
		self:UpdateUnitAuras_Classic(frame, true)
	end)
end

--- Check if we're tracking an aura, and if so add it to the IRF_unitAuras table
---@param parentFrame table @The raid frame that we're updating
---@param auraData table @The aura information
---@return boolean @True if we added the aura
function ImprovedRaidFrames:addToAuraTable(parentFrame, auraData)
	-- Quickly check if we're watching for this aura, and ignore if we aren't.
	-- We use lookup tables built from the aura strings, so a spell ID like 774 no longer also matches 17740.
	local lowerName = auraData.name:lower()
	local dispelName = auraData.dispelName
	if self.trackedAuraNames[lowerName]
			or self.trackedAuraIds[auraData.spellId]
			-- Check if the aura is a debuff that we can dispel, and if we're tracking the wildcard for "dispel"
			or (auraData.isHarmful and self.trackDispelWildcard and dispelName and self.myDispelTypes[dispelName])
			-- Check if the aura is a debuff, and if it has a dispelName see if we're tracking the wildcard for it
			or (auraData.isHarmful and dispelName and dispelName ~= "" and self.trackedAuraNames[dispelName:lower()]) then

		-- Lowercase the aura name for consistency
		auraData.name = lowerName

		-- Append our auraData to the IRF_unitAuras table
		local unitAuras = parentFrame.IRF_unitAuras
		unitAuras[#unitAuras + 1] = auraData

		-- Return true if we added an aura
		return true
	end
end

--- Called when Compact Raid Frame updates a unit's auras, and is used to store aura information for a given unit.
--- Unit aura information for tracked auras is stored in the IRF_unitAuras table.
--- The aura tables are reused between scans, so a busy raid no longer creates dozens of new tables per aura change.
---@param parentFrame table @The raid frame to update
---@param forceRefresh boolean @Whether or not to force a full refresh
function ImprovedRaidFrames:UpdateUnitAuras_Classic(parentFrame, forceRefresh)
	if self.erfLoaded or not self.ShouldContinue(parentFrame) then
		return
	end

	local unit = parentFrame.unit

	-- Keep a record of how many auras we had previously
	local numPreviousAuras = 0
	if parentFrame.IRF_unitAuras then
		numPreviousAuras = #parentFrame.IRF_unitAuras
	end

	-- Create or clear out the tables for the unit
	local unitAuras = parentFrame.IRF_unitAuras
	if not unitAuras then
		unitAuras = {}
		parentFrame.IRF_unitAuras = unitAuras
		parentFrame.IRF_auraPool = {}
	end
	for i = #unitAuras, 1, -1 do
		unitAuras[i] = nil
	end

	-- If no indicator watches any aura, there is nothing to scan
	if self.hasTrackedAuras then
		local pool = parentFrame.IRF_auraPool
		local poolIndex = 1

		-- Iterate through all buffs and debuffs on the unit
		for _, filter in ipairs(allAuraFilters) do
			-- Counter to keep track of our aura index
			local auraIndex = 1

			-- Loop through all auras on the unit until we run out
			while true do
				local name, icon, applications, dispelName, duration, expirationTime, sourceUnit, _, _, spellId, _, _, _, _, timeMod = UnitAura(unit, auraIndex, filter)

				-- Verify that we have an aura name as a proxy for if we've run out of auras to scan
				if not name then
					break
				end

				-- Reuse a table from this frame's pool
				local auraData = pool[poolIndex]
				if not auraData then
					auraData = {}
					pool[poolIndex] = auraData
				end

				auraData.name = name
				auraData.icon = icon
				auraData.applications = applications
				auraData.dispelName = dispelName
				auraData.duration = duration
				auraData.expirationTime = expirationTime
				auraData.sourceUnit = sourceUnit
				auraData.spellId = spellId
				auraData.timeMod = timeMod

				-- Set our isHelpful/isHarmful flags to match the C_UnitAuras API syntax for compatibility with the rest of the addon
				auraData.isHelpful = (filter == "HELPFUL") or nil
				auraData.isHarmful = (filter == "HARMFUL") or nil

				-- Add our auraIndex into the table
				auraData.auraIndex = auraIndex

				-- Add our auraData to the IRF_unitAuras table; only tracked auras use up a pool table
				if self:addToAuraTable(parentFrame, auraData) then
					poolIndex = poolIndex + 1
				end

				-- Increment the aura index counter
				auraIndex = auraIndex + 1
			end
		end
	end

	-- Only update the indicators if we have at least 1 tracked aura in our table
	-- or if we had a tracked aura in our table previously and now we don't (to clear indicators)
	if #unitAuras > 0 or numPreviousAuras ~= 0 or forceRefresh then
		self:UpdateIndicators(parentFrame)
	end
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Work out which debuff types the player can dispel, for the "dispel" wildcard.
--- Enhanced Raid Frames used LibDispel for this, which isn't available in the 3.3.5a backport, so the wildcard never
--- matched anything. We check the spellbook instead; this only runs when our spells change.
function ImprovedRaidFrames:UpdateDispelTypes()
	local types = self.myDispelTypes
	wipe(types)

	-- Collect the names of the dispel spells we look for
	local wanted = {}
	for spellId, dispelTypes in pairs(self.DISPEL_SPELLS) do
		local name = GetSpellInfo(spellId)
		if name then
			wanted[name] = dispelTypes
		end
	end
	local wantedPet = {}
	for spellId, dispelTypes in pairs(self.DISPEL_PET_SPELLS) do
		local name = GetSpellInfo(spellId)
		if name then
			wantedPet[name] = dispelTypes
		end
	end

	-- Scan the spellbook (and the pet spellbook) for them
	local function Scan(bookType, lookup)
		local i = 1
		while true do
			local name = GetSpellName(i, bookType)
			if not name then
				break
			end
			if lookup[name] then
				for _, dispelType in ipairs(lookup[name]) do
					types[dispelType] = true
				end
			end
			i = i + 1
		end
	end

	Scan(BOOKTYPE_SPELL, wanted)
	if HasPetSpells() then
		Scan(BOOKTYPE_PET, wantedPet)
	end

	-- Refresh indicators that use the wildcard
	if self.trackDispelWildcard then
		self:UpdateAllAuras()
	end
end

-- Debuff types the player can dispel: ["Magic"] = true, ...
ImprovedRaidFrames.myDispelTypes = {}
