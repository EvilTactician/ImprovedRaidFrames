-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Frame registry and shared event handling for the Compact Raid Frame unit frames.
--
-- Compact Raid Frame registers every unit event on every unit frame, and each frame then checks whether the event is
-- for its own unit. In a 40-man raid with pets that means every UNIT_HEALTH, UNIT_AURA, UNIT_MANA, ... is delivered to
-- up to 80 frames. We unregister those unit events from the frames and deliver each event only to the frame(s) showing
-- that unit, through one shared event frame.
--
-- Compact Raid Frame also keeps an OnUpdate script running on every visible frame just to check range every 0.5
-- seconds. We replace that with one shared timer that checks all frames.

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

local pairs, ipairs, next, wipe = pairs, ipairs, next, wipe
local UnitGUID = UnitGUID
local InCombatLockdown = InCombatLockdown

-------------------------------------------------------------------------
-------------------------------------------------------------------------

-- Every Compact Raid Frame unit frame we manage: [frame] = true
local frames = {}
ImprovedRaidFrames.frames = frames

-- Unit token -> array of frames showing that unit (e.g. "raid5" -> { CompactRaidFrame7 })
local unitMap = {}

-- Unit GUID -> array of frames showing that unit. Rebuilt when the group changes.
local guidMap = {}
local guidMapPool = {}
local guidMapDirty = true

-- Frames that need a range check: [frame] = true
local rangeFrames = {}

-- Callbacks run once for every new frame: function(frame)
local frameCreatedCallbacks = {}

-- Frame actions that must wait until we leave combat: [frame] = true
local pendingSecureSetup = {}

-- Names of the Compact Raid Frame unit frames we manage. Other users of CompactUnitFrame (if any) are left alone.
local MANAGED_FRAME_NAMES = {
	"^CompactRaidFrame%d+$",
	"^CompactRaidGroup%d+Member%d+$",
	"^CompactPartyFrameMember%d+$",
}

-- Unit events that Compact Raid Frame registers on every frame and only handles when the event is for the frame's own
-- unit (or, for vehicle events, for the player). These are delivered through our shared event frame instead.
local UNIT_EVENTS = {
	"UNIT_MAXHEALTH",
	"UNIT_HEALTH",
	"UNIT_MAXMANA",
	"UNIT_RAGE",
	"UNIT_MANA",
	"UNIT_ENERGY",
	"UNIT_RUNIC_POWER",
	"UNIT_AURA",
	"UNIT_THREAT_SITUATION_UPDATE",
	"UNIT_THREAT_LIST_UPDATE",
	"PLAYER_FLAGS_CHANGED",
	"UNIT_LEVEL",
	"UNIT_MODEL_CHANGED",
	"UNIT_DISPLAYPOWER",
	"UNIT_POWER_BAR_SHOW",
	"UNIT_POWER_BAR_HIDE",
	"UNIT_NAME_UPDATE",
	"UNIT_PET",
	"UNIT_FLAGS",
	"READY_CHECK_CONFIRM",
	"UNIT_ENTERED_VEHICLE",
	"UNIT_EXITED_VEHICLE",
}

-- How often we check range, in seconds (same as Compact Raid Frame)
local RANGE_CHECK_INTERVAL = 0.5

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Check whether a frame is one of the Compact Raid Frame unit frames we manage
---@param frame table @The frame to check
---@return boolean
local function IsManagedFrameName(frame)
	local name = frame and frame.GetName and frame:GetName()
	if not name then
		return false
	end
	for _, pattern in ipairs(MANAGED_FRAME_NAMES) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

--- Remove a frame from an array of frames
local function RemoveFromList(list, frame)
	for i = #list, 1, -1 do
		if list[i] == frame then
			table.remove(list, i)
		end
	end
end

--- Add a frame to the unit map under a unit token
local function AddToUnitMap(unit, frame)
	if not unit then
		return
	end
	local list = unitMap[unit]
	if not list then
		list = {}
		unitMap[unit] = list
	end
	for i = 1, #list do
		if list[i] == frame then
			return
		end
	end
	list[#list + 1] = frame
end

--- Update the unit map entries for a frame after its unit changed
local function UpdateUnitMap(frame)
	-- Remove the frame from the units it was listed under before
	if frame.IRF_mappedUnit and unitMap[frame.IRF_mappedUnit] then
		RemoveFromList(unitMap[frame.IRF_mappedUnit], frame)
	end
	if frame.IRF_mappedDisplayedUnit and unitMap[frame.IRF_mappedDisplayedUnit] then
		RemoveFromList(unitMap[frame.IRF_mappedDisplayedUnit], frame)
	end

	-- Compact Raid Frame stops listening to events when a frame has no unit, so we do the same
	frame.IRF_mappedUnit = frame.unit
	frame.IRF_mappedDisplayedUnit = (frame.displayedUnit ~= frame.unit) and frame.displayedUnit or nil
	AddToUnitMap(frame.IRF_mappedUnit, frame)
	AddToUnitMap(frame.IRF_mappedDisplayedUnit, frame)
end

-------------------------------------------------------------------------
------------------------ Shared unit event frame ------------------------
-------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "ImprovedRaidFramesEventFrame")
ImprovedRaidFrames.eventFrame = eventFrame

--- Deliver an event to one Compact Raid Frame unit frame, exactly as Compact Raid Frame's own OnEvent would get it
local function Deliver(frame, event, ...)
	local handler = frame.OnEvent or CompactUnitFrame_OnEvent
	handler(frame, event, ...)
end

eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
	-- Group changes alter which player each unit token refers to, so the GUID map needs rebuilding
	if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		guidMapDirty = true
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Run the secure frame setup that had to wait for the end of combat
		for frame in pairs(pendingSecureSetup) do
			pendingSecureSetup[frame] = nil
			ImprovedRaidFrames:RunFrameCreatedCallbacks(frame)
		end
		return
	end

	-- Deliver the event to the frame(s) showing this unit
	local list = unitMap[unit]
	if list then
		for i = 1, #list do
			Deliver(list[i], event, unit, ...)
		end
	end

	-- Compact Raid Frame also updates every frame when the player enters or leaves a vehicle
	if unit == "player" and (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") then
		for frame in pairs(frames) do
			if frame.unit and frame.IRF_mappedUnit ~= "player" and frame.IRF_mappedDisplayedUnit ~= "player" then
				Deliver(frame, event, unit, ...)
			end
		end
	end

	-- The units shown by our frames may have changed, so the GUID map needs rebuilding
	if event == "UNIT_PET" or event == "UNIT_NAME_UPDATE" then
		guidMapDirty = true
	end
end)

for _, event in ipairs(UNIT_EVENTS) do
	eventFrame:RegisterEvent(event)
end
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

-------------------------------------------------------------------------
-------------------------------- GUID map -------------------------------
-------------------------------------------------------------------------

--- Rebuild the GUID -> frames map. Only done when the group changes, so heal and absorb updates can find their frames
--- with a single table lookup instead of every frame calling UnitGUID() for every update.
local function RebuildGUIDMap()
	for guid, list in pairs(guidMap) do
		wipe(list)
		guidMapPool[#guidMapPool + 1] = list
		guidMap[guid] = nil
	end

	for frame in pairs(frames) do
		local unit = frame.displayedUnit or frame.unit
		local guid = unit and UnitGUID(unit)
		if guid then
			local list = guidMap[guid]
			if not list then
				list = table.remove(guidMapPool) or {}
				guidMap[guid] = list
			end
			list[#list + 1] = frame
		end
	end

	guidMapDirty = false
end

--- Get the frames currently showing a unit GUID
---@param guid string @The unit GUID
---@return table|nil @Array of frames, or nil if no frame shows this GUID
function ImprovedRaidFrames:GetFramesForGUID(guid)
	if guidMapDirty then
		RebuildGUIDMap()
	end
	return guidMap[guid]
end

--- Mark the GUID map as needing a rebuild
function ImprovedRaidFrames:InvalidateGUIDMap()
	guidMapDirty = true
end

-------------------------------------------------------------------------
---------------------------- Shared range timer -------------------------
-------------------------------------------------------------------------

local rangeTimer = CreateFrame("Frame", "ImprovedRaidFramesRangeTimer")
local rangeElapsed = 0
rangeTimer:SetScript("OnUpdate", function(_, elapsed)
	rangeElapsed = rangeElapsed + elapsed
	if rangeElapsed < RANGE_CHECK_INTERVAL then
		return
	end
	rangeElapsed = 0

	-- Keep the GUID map fresh between group changes as well (cheap when nothing changed)
	if guidMapDirty then
		RebuildGUIDMap()
	end

	for frame in pairs(rangeFrames) do
		-- Hidden frames would not have run their OnUpdate either
		if frame:IsVisible() then
			CompactUnitFrame_UpdateInRange(frame)
		end
	end
end)

-------------------------------------------------------------------------
----------------------------- Frame registry ----------------------------
-------------------------------------------------------------------------

--- Register a callback that is run once for every Compact Raid Frame unit frame (existing and future ones).
--- Callbacks that change secure attributes are safe: if a frame is created in combat, they are run after combat.
--- Callbacks must be safe to run more than once for the same frame.
---@param func function @Callback, called with the frame
function ImprovedRaidFrames:RegisterFrameCreatedCallback(func)
	frameCreatedCallbacks[#frameCreatedCallbacks + 1] = func
	for frame in pairs(frames) do
		if InCombatLockdown() then
			pendingSecureSetup[frame] = true
		elseif not pendingSecureSetup[frame] then
			func(frame)
		end
	end
end

--- Run all frame-created callbacks for a frame
---@param frame table @The unit frame
function ImprovedRaidFrames:RunFrameCreatedCallbacks(frame)
	if InCombatLockdown() then
		pendingSecureSetup[frame] = true
		return
	end
	for _, func in ipairs(frameCreatedCallbacks) do
		func(frame)
	end
end

--- Run a function for every managed unit frame that is showing a unit
---@param func function @Called with the frame
function ImprovedRaidFrames:ForEachFrame(func)
	for frame in pairs(frames) do
		if frame.unit then
			func(frame)
		end
	end
end

--- Take over a newly created Compact Raid Frame unit frame
local function ManageFrame(frame)
	if frames[frame] or not IsManagedFrameName(frame) then
		return
	end
	frames[frame] = true

	-- Stop the frame listening to unit events itself; our shared event frame delivers them instead
	for _, event in ipairs(UNIT_EVENTS) do
		frame:UnregisterEvent(event)
	end

	-- The frame may already have a unit (frames that existed before we loaded)
	if frame.unit then
		UpdateUnitMap(frame)
	end

	guidMapDirty = true
	ImprovedRaidFrames:RunFrameCreatedCallbacks(frame)
end

--- Called after Compact Raid Frame has set a frame's unit
local function OnSetUnit(frame)
	if not frames[frame] then
		return
	end
	UpdateUnitMap(frame)
	guidMapDirty = true
end

--- Called after Compact Raid Frame has checked whether a frame's unit exists.
--- Compact Raid Frame starts a per-frame OnUpdate range check here; we move the frame to our shared range timer.
local function OnUpdateVisible(frame)
	if not frames[frame] then
		return
	end
	if frame.rangeCheck then
		frame.rangeCheck = nil
		rangeFrames[frame] = true
	else
		-- Compact Raid Frame decided this frame needs no range check (no unit, or it is the player)
		rangeFrames[frame] = nil
	end
	-- Let Compact Raid Frame drop the OnUpdate script now the range check no longer needs it.
	-- Compact Raid Frame's SetUnit resets frame.needsUpdate without removing the script, after which its own check
	-- never removes it, so the OnUpdate ran on every rendered frame for good. Re-syncing the flag fixes that.
	if frame:GetScript("OnUpdate") and not frame.needsUpdate then
		frame.needsUpdate = true
	end
	CompactUnitFrame_CheckNeedsUpdate(frame)
end

-- Install our hooks. These must exist before Compact Raid Frame creates its first unit frame.
if CompactUnitFrame_OnLoad and CompactUnitFrame_SetUnit and CompactUnitFrame_UpdateVisible and CompactUnitFrame_OnEvent then
	hooksecurefunc("CompactUnitFrame_OnLoad", ManageFrame)
	hooksecurefunc("CompactUnitFrame_SetUnit", OnSetUnit)
	hooksecurefunc("CompactUnitFrame_UpdateVisible", OnUpdateVisible)

	-- Take over any frames that already exist
	local function TryExisting(name)
		local frame = _G[name]
		if frame and frame.healthBar then
			ManageFrame(frame)
			if frame.unit then
				OnUpdateVisible(frame)
			end
			return true
		end
	end

	local i = 1
	while TryExisting("CompactRaidFrame" .. i) do
		i = i + 1
	end
	for group = 1, 8 do
		for member = 1, 5 do
			TryExisting("CompactRaidGroup" .. group .. "Member" .. member)
		end
	end
	for member = 1, 5 do
		TryExisting("CompactPartyFrameMember" .. member)
	end
else
	ImprovedRaidFrames:FeatureUnavailable("frame registry")
	-- Without the registry, still give the rest of the addon a way to find frames
	function ImprovedRaidFrames:GetFramesForGUID()
		return nil
	end
end
