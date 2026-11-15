-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Heal prediction: incoming heals (LibHealComm-4.0), absorb shields and heal absorbs (SpecializedAbsorbs-1.0).
-- This replaces Compact Raid Frames: Heal Extension by Tsoukie, which drew these on Compact Raid Frame's own bars.
--
-- Differences from the Heal Extension:
--  * Each feature can be switched on or off.
--  * Heal Extension registered 13 library callbacks on every frame, so every heal or absorb update called up to 80
--    handlers, each calling UnitGUID(). We register the callbacks once and look the frames up by GUID.
--  * Heal Extension missed refreshes when a healing modifier changed (e.g. Mortal Strike) or a unit disappeared.
--  * Heal absorbs (e.g. Necrotic Strike) are shown; the library tracked them but nothing displayed them.

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

local GetTime = GetTime
local UnitGUID = UnitGUID
local select = select

local HEALCOMM = LibStub:GetLibrary("LibHealComm-4.0", true)
local ABSORBS = LibStub:GetLibrary("SpecializedAbsorbs-1.0", true)

-- Incoming heals are summed over the next few seconds, as the Heal Extension did
local HEAL_WINDOW = 5

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Mark the heal prediction of every frame showing a GUID as needing a redraw.
--- Compact Raid Frame redraws it at most once per frame, however many updates arrive.
---@param guid string @The unit GUID
local function RefreshGUID(guid)
	local list = guid and ImprovedRaidFrames:GetFramesForGUID(guid)
	if list then
		for i = 1, #list do
			CompactUnitFrame_SetHealPredictionDirty(list[i])
		end
	end
end

--- Mark every frame's heal prediction as needing a redraw (for effects that cover an area)
local function RefreshAll()
	ImprovedRaidFrames:ForEachFrame(CompactUnitFrame_SetHealPredictionDirty)
end

-- Library callbacks are registered without an extra argument, so CallbackHandler calls them as func(event, ...).
-- HealComm_HealStarted/Updated/Delayed/Stopped(event, casterGUID, spellID, healType, endTime, ...targets)
local function OnHealComm(_, _, _, _, _, ...)
	for i = 1, select("#", ...) do
		RefreshGUID((select(i, ...)))
	end
end

-- HealComm_ModifierChanged(event, guid, modifier) and HealComm_GUIDDisappeared(event, guid)
local function OnHealCommUnit(_, guid)
	RefreshGUID(guid)
end

-- SpecializedAbsorbs: EffectApplied(event, srcGUID, srcName, dstGUID, ...)
local function OnAbsorbApplied(_, _, _, dstGUID)
	RefreshGUID(dstGUID)
end

-- SpecializedAbsorbs: EffectUpdated(event, guid, ...), EffectRemoved(event, guid, ...), UnitUpdated(event, guid, ...),
-- UnitCleared(event, guid)
local function OnAbsorbUnit(_, guid)
	RefreshGUID(guid)
end

-- SpecializedAbsorbs: AreaCreated, AreaUpdated, AreaCleared (effects that cover several units)
local function OnAbsorbArea()
	RefreshAll()
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Incoming heals on a unit, optionally only those from one healer.
--- Replaces the !!!ClassicAPI version, like the Heal Extension did, but honours our options.
function ImprovedRaidFrames.UnitGetIncomingHeals(unit, healer, isGUID)
	local db = ImprovedRaidFrames.db
	if not (unit and HEALCOMM and db and db.profile.healPrediction) then
		return 0
	end

	if not isGUID then
		unit = UnitGUID(unit)
		healer = healer and UnitGUID(healer)
	end
	if not unit then
		return 0
	end

	local flags = db.profile.healPredictionHots and HEALCOMM.ALL_HEALS or HEALCOMM.CASTED_HEALS
	return HEALCOMM:GetHealAmount(unit, flags, GetTime() + HEAL_WINDOW, healer) or 0
end

--- Total absorb shields on a unit
function ImprovedRaidFrames.UnitGetTotalAbsorbs(unit)
	local db = ImprovedRaidFrames.db
	if not (unit and ABSORBS and db and db.profile.absorbs) then
		return 0
	end
	local guid = UnitGUID(unit)
	return guid and ABSORBS.UnitTotal(guid) or 0
end

--- Total heal absorbs on a unit (healing that will be absorbed, e.g. Necrotic Strike)
function ImprovedRaidFrames.UnitGetTotalHealAbsorbs(unit)
	local db = ImprovedRaidFrames.db
	if not (unit and ABSORBS and db and db.profile.healAbsorbs) then
		return 0
	end
	local healAbsorbs = ABSORBS.Core and ABSORBS.Core.GUIDtoAbsorbHealSpells
	local guid = UnitGUID(unit)
	local amount = healAbsorbs and guid and healAbsorbs[guid]
	if amount and amount > 0 then
		return amount
	end
	return 0
end

--- Turn heal prediction on: register the library callbacks once, and route the functions Compact Raid Frame uses to us.
function ImprovedRaidFrames:EnableHealPrediction()
	-- The Heal Extension does all of this itself if it's still enabled
	if self.healExLoaded or self.healPredictionEnabled then
		return
	end
	if not (CompactUnitFrame_SetHealPredictionDirty and DefaultCompactUnitFrameOptions) then
		self:FeatureUnavailable("heal prediction")
		return
	end
	self.healPredictionEnabled = true

	-- Compact Raid Frame calls these globals when it draws the heal prediction bars
	UnitGetIncomingHeals = self.UnitGetIncomingHeals
	UnitGetTotalAbsorbs = self.UnitGetTotalAbsorbs
	UnitGetTotalHealAbsorbs = self.UnitGetTotalHealAbsorbs

	if HEALCOMM then
		HEALCOMM.RegisterCallback(self, "HealComm_HealStarted", OnHealComm)
		HEALCOMM.RegisterCallback(self, "HealComm_HealUpdated", OnHealComm)
		HEALCOMM.RegisterCallback(self, "HealComm_HealDelayed", OnHealComm)
		HEALCOMM.RegisterCallback(self, "HealComm_HealStopped", OnHealComm)
		HEALCOMM.RegisterCallback(self, "HealComm_ModifierChanged", OnHealCommUnit)
		HEALCOMM.RegisterCallback(self, "HealComm_GUIDDisappeared", OnHealCommUnit)
	end

	if ABSORBS then
		ABSORBS.RegisterCallback(self, "EffectApplied", OnAbsorbApplied)
		ABSORBS.RegisterCallback(self, "EffectUpdated", OnAbsorbUnit)
		ABSORBS.RegisterCallback(self, "EffectRemoved", OnAbsorbUnit)
		ABSORBS.RegisterCallback(self, "UnitUpdated", OnAbsorbUnit)
		ABSORBS.RegisterCallback(self, "UnitCleared", OnAbsorbUnit)
		ABSORBS.RegisterCallback(self, "AreaCreated", OnAbsorbArea)
		ABSORBS.RegisterCallback(self, "AreaUpdated", OnAbsorbArea)
		ABSORBS.RegisterCallback(self, "AreaCleared", OnAbsorbArea)
	end

	self:UpdateHealPredictionOptions()
end

--- Apply the heal prediction options: turn Compact Raid Frame's heal prediction bars on or off and redraw them
function ImprovedRaidFrames:UpdateHealPredictionOptions()
	if not self.healPredictionEnabled then
		return
	end

	local profile = self.db.profile
	local anyEnabled = (profile.healPrediction or profile.absorbs or profile.healAbsorbs) and true or false
	DefaultCompactUnitFrameOptions.displayHealPrediction = anyEnabled
	if DefaultCompactMiniFrameOptions then
		DefaultCompactMiniFrameOptions.displayHealPrediction = anyEnabled
	end

	-- Redraw every frame, including pet frames
	for frame in pairs(self.frames) do
		if frame.unit then
			CompactUnitFrame_SetHealPredictionDirty(frame)
		end
	end
end
