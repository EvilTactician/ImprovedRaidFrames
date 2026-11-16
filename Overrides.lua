-- Improved Raid Frames is a World of Warcraft® user interface addon, based on Enhanced Raid Frames.
-- Copyright (c) 2017-2023 Britt W. Yazel
-- This code is licensed under the MIT license (see LICENSE for details)

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames
local LibRangeCheck = LibStub("LibRangeCheck-3.0")

local UnitInRange = C_UnitInRange

-------------------------------------------------------------------------
-------------------------------------------------------------------------

-- Compact Raid Frame's original functions, which we wrap below
local CRF_UpdateBuffs = CompactUnitFrame_UpdateBuffs
local CRF_UpdateDebuffs = CompactUnitFrame_UpdateDebuffs
local CRF_UpdateDispellableDebuffs = CompactUnitFrame_UpdateDispellableDebuffs
local CRF_UpdateInRange = CompactUnitFrame_UpdateInRange

--- Check whether we handle the stock aura and range options for this frame.
--- If Enhanced Raid Frames is still enabled, we leave these to it.
local function ShouldOverride(frame)
	return ImprovedRaidFrames.db and not ImprovedRaidFrames.erfLoaded and ImprovedRaidFrames.frames[frame]
end

-- Stock buff/debuff/dispellable icons.
-- Enhanced Raid Frames hid these icons each time they were shown, so Compact Raid Frame still scanned every aura.
-- We skip the scan entirely when the icons are turned off.
if CRF_UpdateBuffs and CRF_UpdateDebuffs and CRF_UpdateDispellableDebuffs
		and CompactUnitFrame_HideAllBuffs and CompactUnitFrame_HideAllDebuffs and CompactUnitFrame_HideAllDispelDebuffs then
	function CompactUnitFrame_UpdateBuffs(frame)
		if ShouldOverride(frame) and not ImprovedRaidFrames.db.profile.showBuffs then
			CompactUnitFrame_HideAllBuffs(frame)
			return
		end
		return CRF_UpdateBuffs(frame)
	end

	function CompactUnitFrame_UpdateDebuffs(frame)
		if ShouldOverride(frame) and not ImprovedRaidFrames.db.profile.showDebuffs then
			CompactUnitFrame_HideAllDebuffs(frame)
			return
		end
		return CRF_UpdateDebuffs(frame)
	end

	function CompactUnitFrame_UpdateDispellableDebuffs(frame)
		if ShouldOverride(frame) and not ImprovedRaidFrames.db.profile.showDispellableDebuffs then
			CompactUnitFrame_HideAllDispelDebuffs(frame)
			return
		end
		return CRF_UpdateDispellableDebuffs(frame)
	end
else
	ImprovedRaidFrames:FeatureUnavailable("stock aura visibility")
end

-- Range fade.
-- Enhanced Raid Frames hooked this function, so every range check ran twice (once by Compact Raid Frame, then again by
-- Enhanced Raid Frames). We replace it, so each check runs once.
if CRF_UpdateInRange then
	function CompactUnitFrame_UpdateInRange(frame)
		if ShouldOverride(frame) then
			return ImprovedRaidFrames:UpdateInRange(frame)
		end
		return CRF_UpdateInRange(frame)
	end
else
	ImprovedRaidFrames:FeatureUnavailable("range fade")
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Refresh the stock buff/debuff/dispellable icons on all frames after the visibility options changed
function ImprovedRaidFrames:UpdateAllStockAuraVisibility()
	if self.erfLoaded or not CompactUnitFrame_UpdateAuras then
		return
	end
	self:ForEachFrame(function(frame)
		self:UpdateStockAuraVisibility(frame)
	end)
end

--- Refresh the stock buff/debuff/dispellable icons on a single frame
---@param frame table @The frame to refresh
function ImprovedRaidFrames:UpdateStockAuraVisibility(frame)
	if not self.ShouldContinue(frame, true) then
		return
	end

	-- Our wrapped Compact Raid Frame functions hide or scan the icons based on the current options
	CompactUnitFrame_UpdateBuffs(frame)
	CompactUnitFrame_UpdateDebuffs(frame)
	CompactUnitFrame_UpdateDispellableDebuffs(frame)
end

--- Cache the LibRangeCheck checker for the chosen distance, so we don't look it up on every range check
function ImprovedRaidFrames:UpdateRangeChecker()
	self.rangeChecker = nil
	if self.db.profile.customRangeCheck then
		self.rangeChecker = LibRangeCheck:GetFriendChecker(self.db.profile.customRange)
	end
end

--- Updates the frame alpha based on if a unit is in range or not.
--- This replaces the default CompactUnitFrame_UpdateInRange function for our frames.
---@param frame table @The frame to update the alpha on
function ImprovedRaidFrames:UpdateInRange(frame)
	if self.erfLoaded or not self.ShouldContinue(frame, true) then
		return
	end

	-- Respect Compact Raid Frame's own setting for fading out-of-range units
	if not frame.optionTable or not frame.optionTable.fadeOutOfRange then
		frame.healthBar:SetAlpha(1)
		return
	end

	-- Sometimes the "displayed unit" is different than the actual unit, so we'll check both.
	-- (E.g. If we're in a vehicle, we'll use the vehicle unit instead of the player unit.)
	local effectiveUnit = frame.unit
	if frame.unit ~= frame.displayedUnit then
		effectiveUnit = frame.displayedUnit
	end

	local inRange, checkedRange

	-- Try to use LibRangeCheck if we have a custom range set
	if self.rangeChecker then
		-- If we have a valid range checker, use it
		inRange = self.rangeChecker(effectiveUnit)
		checkedRange = true
	end

	-- If we haven't successfully checked the range yet, use the default range checking function
	if not checkedRange then
		inRange, checkedRange = UnitInRange(effectiveUnit)
	end

	-- If we weren't able to check the range for some reason, treat them as being in-range as a fallback.
	if checkedRange and not inRange then
		frame.healthBar:SetAlpha(self.db.profile.rangeAlpha)
	else
		frame.healthBar:SetAlpha(1)
	end
end

--- Set the background alpha amount based on a defined value by the user.
---@param frame table @The frame to set the background alpha on
function ImprovedRaidFrames:UpdateBackgroundAlpha(frame)
	if self.erfLoaded or not self.ShouldContinue(frame) then
		return
	end

	-- Set the background alpha to the user defined value
	frame.background:SetAlpha(self.db.profile.backgroundAlpha)
end

--- Set the scale of the overall raid frame container.
--- The container holds secure frames, so it can't be scaled in combat. We apply the scale once combat ends.
function ImprovedRaidFrames:UpdateScale()
	if self.erfLoaded then
		return
	end

	if InCombatLockdown() then
		if not self.scalePending then
			self.scalePending = true
			self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				self.scalePending = nil
				self:UpdateScale()
			end)
		end
		return
	end

	CompactRaidFrameContainer:SetScale(self.db.profile.frameScale)
	if CompactPartyFrame then
		CompactPartyFrame:SetScale(self.db.profile.frameScale)
	end
end

-- Background alpha and target markers are reapplied whenever Compact Raid Frame fully updates a frame (for example
-- when the group changes), replacing Enhanced Raid Frames' throttled roster update.
if CompactUnitFrame_UpdateAll then
	hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
		if ImprovedRaidFrames.db and ImprovedRaidFrames.frames[frame] and frame.unitExists then
			ImprovedRaidFrames:UpdateBackgroundAlpha(frame)
			ImprovedRaidFrames:UpdateTargetMarker(frame)
		end
	end)
end
