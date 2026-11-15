-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Our own right-click menu for the Compact Raid Frame unit frames.
--
-- Compact Raid Frame opened Blizzard's shared unit popup menu (UnitPopup / UIDropDownMenu) from addon code. That
-- taints Blizzard's dropdown code: after the raid frames have been created, "Set Focus" can be blocked in other
-- menus too (target frame, party frames), with the error naming CompactRaidFrame. It also used the RAID_PLAYER menu,
-- which has no Main Tank / Main Assist entries.
--
-- We build the menu with !!!ClassicAPI's separate dropdown copy (C_UIDropDownMenu), so Blizzard's menu code is never
-- touched. Focus can't be set from addon code at all; Focus.lua puts a secure button over our "Set Focus" line when
-- the menu opens out of combat, and Ctrl-left-click focuses at any time.

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

local L = LibStub("AceLocale-3.0"):GetLocale("ImprovedRaidFrames")

if not (C_UIDropDownMenu_Initialize and C_ToggleDropDownMenu and C_UIDropDownMenu_AddButton and C_UIDropDownMenu_CreateInfo
		and C_CloseDropDownMenus and CompactUnitFrame_SetMenuFunc) then
	ImprovedRaidFrames:FeatureUnavailable("unit menu")
	return
end

local RAID_TARGET_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

-- Loot methods in the order Blizzard's menu shows them
local LOOT_METHODS = {
	{ "freeforall", LOOT_FREE_FOR_ALL or "Free for All" },
	{ "roundrobin", LOOT_ROUND_ROBIN or "Round Robin" },
	{ "master", LOOT_MASTER_LOOTER or "Master Looter" },
	{ "group", LOOT_GROUP_LOOT or "Group Loot" },
	{ "needbeforegreed", LOOT_NEED_BEFORE_GREED or "Need Before Greed" },
}

-------------------------------------------------------------------------
-------------------------------------------------------------------------

-- The one dropdown frame all unit frames share
local dropDown = CreateFrame("Frame", "ImprovedRaidFramesUnitDropDown", UIParent, "C_UIDropDownMenuTemplate")
dropDown:Hide()
ImprovedRaidFrames.unitDropDown = dropDown

--- Add a button to the menu
---@param level number @Menu level
---@param text string @Button text
---@param func function|nil @Click handler, called with (button, arg1, arg2)
---@param options table|nil @Extra info fields
---@return number @The index of the new button in its menu level
local function AddButton(level, text, func, options)
	local info = C_UIDropDownMenu_CreateInfo()
	info.text = text
	info.func = func
	info.notCheckable = true
	if options then
		for k, v in pairs(options) do
			info[k] = v
		end
	end
	C_UIDropDownMenu_AddButton(info, level)
	return _G["C_DropDownList" .. level].numButtons
end

--- Get information about our rights and the unit's place in the group
local function GetGroupInfo(unit)
	local inRaid = GetNumRaidMembers() > 0
	local inParty = GetNumPartyMembers() > 0
	local isLeader = (inRaid and IsRaidLeader()) or (not inRaid and inParty and IsPartyLeader())
	local isAssistant = inRaid and IsRaidOfficer() and not IsRaidLeader()

	-- The unit's rank in the raid: 2 = leader, 1 = assistant, 0 = member
	local unitRank = 0
	local raidIndex = inRaid and UnitInRaid(unit)
	if raidIndex then
		unitRank = select(2, GetRaidRosterInfo(raidIndex + 1)) or 0
	end

	return inRaid, inParty, isLeader, isAssistant, raidIndex, unitRank
end

-------------------------------------------------------------------------
------------------------------- Menu levels -----------------------------
-------------------------------------------------------------------------

--- Raid target icon submenu
local function AddRaidTargetButtons(unit, level)
	local current = GetRaidTargetIndex(unit)
	for i = 1, 8 do
		AddButton(level, _G["RAID_TARGET_" .. i] or ("Icon " .. i), function()
			-- Choosing the icon the unit already has removes it, like Blizzard's menu
			if GetRaidTargetIndex(unit) == i then
				SetRaidTarget(unit, 0)
			else
				SetRaidTarget(unit, i)
			end
		end, {
			icon = RAID_TARGET_TEXTURE .. i,
			notCheckable = false,
			checked = (current == i),
		})
	end
	AddButton(level, RAID_TARGET_NONE or NONE, function()
		SetRaidTarget(unit, 0)
	end, {
		notCheckable = false,
		checked = not current,
	})
end

--- Loot method submenu
local function AddLootMethodButtons(level)
	local current = GetLootMethod()
	for _, method in ipairs(LOOT_METHODS) do
		local value, text = method[1], method[2]
		AddButton(level, text, function()
			if value == "master" then
				SetLootMethod("master", UnitName("player"))
			else
				SetLootMethod(value)
			end
		end, {
			notCheckable = false,
			isRadio = true,
			checked = (current == value),
		})
	end
end

--- Loot threshold submenu
local function AddLootThresholdButtons(level)
	local current = GetLootThreshold()
	for quality = 2, 6 do
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		AddButton(level, _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality), function()
			SetLootThreshold(quality)
		end, {
			notCheckable = false,
			isRadio = true,
			checked = (current == quality),
			colorCode = color and color.hex,
		})
	end
end

--- The "Set Focus" / "Clear Focus" line. Focus.lua puts a secure button over it when the menu opens out of combat.
local function AddFocusButton(unit, level)
	local isFocus = UnitIsUnit(unit, "focus")
	local text = isFocus and (CLEAR_FOCUS or L["Clear Focus"]) or (SET_FOCUS or L["Set Focus"])
	local index
	if InCombatLockdown() then
		-- In combat the secure button can't be placed, so show how to focus instead
		index = AddButton(level, text .. " " .. L["(Ctrl-click)"], nil, { disabled = true })
		dropDown.focusButtonIndex = nil
	else
		index = AddButton(level, text, function()
			-- Only reached if the secure button wasn't over this line
			ImprovedRaidFrames:Print(L["focusHint"])
		end)
		dropDown.focusButtonIndex = index
	end
	dropDown.focusIsClear = isFocus
	return index
end

--- Menu for a player in our party or raid
local function AddGroupMemberButtons(unit, level)
	local name = GetUnitName(unit, true)
	local inRaid, _, isLeader, isAssistant, raidIndex, unitRank = GetGroupInfo(unit)
	local canInspect = CanInspect(unit)
	local connected = UnitIsConnected(unit)

	AddFocusButton(unit, level)

	AddButton(level, WHISPER or L["Whisper"], function()
		ChatFrame_SendTell(name)
	end)
	AddButton(level, INSPECT or L["Inspect"], function()
		InspectUnit(unit)
	end, { disabled = not canInspect })
	AddButton(level, ACHIEVEMENT_BUTTON or L["Achievements"], function()
		InspectAchievements(unit)
	end, { disabled = not canInspect })
	AddButton(level, TRADE or L["Trade"], function()
		InitiateTrade(unit)
	end, { disabled = not connected })
	AddButton(level, FOLLOW or L["Follow"], function()
		FollowUnit(name)
	end, { disabled = not connected })

	-- Raid target icons: anyone in a party, only the leader and assistants in a raid
	if not inRaid or isLeader or isAssistant then
		AddButton(level, RAID_TARGET_ICON or L["Raid Target Icon"], nil, { hasArrow = true, value = "RAID_TARGET" })
	end

	-- Leader actions
	if isLeader then
		AddButton(level, L["Promote to Leader"], function()
			PromoteToLeader(name)
		end, { disabled = not connected })
	end

	if inRaid and isLeader then
		if unitRank == 1 then
			AddButton(level, L["Demote Assistant"], function()
				DemoteAssistant(name)
			end)
		elseif unitRank == 0 then
			AddButton(level, L["Promote to Assistant"], function()
				PromoteToAssistant(name)
			end)
		end
	end

	-- Main Tank / Main Assist: raid only, for the leader and assistants
	if inRaid and (isLeader or isAssistant) and raidIndex then
		local isMainTank = GetPartyAssignment("MAINTANK", unit)
		local isMainAssist = GetPartyAssignment("MAINASSIST", unit)
		AddButton(level, MAIN_TANK or L["Main Tank"], function()
			if isMainTank then
				ClearPartyAssignment("MAINTANK", name)
			else
				SetPartyAssignment("MAINTANK", name)
			end
		end, { notCheckable = false, checked = isMainTank and true or false })
		AddButton(level, MAIN_ASSIST or L["Main Assist"], function()
			if isMainAssist then
				ClearPartyAssignment("MAINASSIST", name)
			else
				SetPartyAssignment("MAINASSIST", name)
			end
		end, { notCheckable = false, checked = isMainAssist and true or false })
	end

	-- Master looter
	if isLeader and GetLootMethod() == "master" then
		AddButton(level, L["Make Master Looter"], function()
			SetLootMethod("master", name)
		end, { disabled = not connected })
	end

	-- Removing someone: the party leader, or the raid leader and assistants (assistants can't remove other assistants)
	if (not inRaid and isLeader) or (inRaid and (isLeader or (isAssistant and unitRank == 0))) then
		AddButton(level, inRaid and L["Remove from Raid"] or L["Uninvite"], function()
			UninviteUnit(name)
		end)
	end
end

--- Menu for ourselves
local function AddSelfButtons(unit, level)
	local inRaid, inParty, isLeader = GetGroupInfo(unit)

	AddFocusButton(unit, level)

	if not inRaid or isLeader or IsRaidOfficer() then
		AddButton(level, RAID_TARGET_ICON or L["Raid Target Icon"], nil, { hasArrow = true, value = "RAID_TARGET" })
	end

	if isLeader then
		AddButton(level, LOOT_METHOD or L["Loot Method"], nil, { hasArrow = true, value = "LOOT_METHOD" })
		AddButton(level, LOOT_THRESHOLD or L["Loot Threshold"], nil, { hasArrow = true, value = "LOOT_THRESHOLD" })

		if inParty and not inRaid then
			AddButton(level, CONVERT_TO_RAID or L["Convert to Raid"], function()
				ConvertToRaid()
			end)
		elseif inRaid and GetNumRaidMembers() <= MAX_PARTY_MEMBERS + 1 then
			AddButton(level, CONVERT_TO_PARTY or L["Convert to Party"], function()
				ConvertToParty()
			end)
		end
	end

	if inRaid or inParty then
		AddButton(level, PARTY_LEAVE or L["Leave Party"], function()
			LeaveParty()
		end)
	end
end

--- Menu for a vehicle, a pet, or any other unit
local function AddOtherButtons(unit, level, isVehicle)
	local inRaid, _, isLeader, isAssistant = GetGroupInfo(unit)

	AddFocusButton(unit, level)

	if not inRaid or isLeader or isAssistant then
		AddButton(level, RAID_TARGET_ICON or L["Raid Target Icon"], nil, { hasArrow = true, value = "RAID_TARGET" })
	end

	if isVehicle then
		AddButton(level, L["Leave Vehicle"], function()
			VehicleExit()
		end)
	end
end

--- Build the menu for the unit the menu was opened on
local function InitializeMenu(self, level)
	local unit = self.unit
	if not unit or not UnitExists(unit) then
		return
	end
	level = level or 1

	if level == 1 then
		-- Title: the unit's name
		AddButton(level, GetUnitName(unit, true) or UNKNOWN, nil, { isTitle = true })

		if UnitIsUnit(unit, "player") then
			AddSelfButtons(unit, level)
		elseif UnitIsUnit(unit, "vehicle") then
			-- The vehicle check must come before the pet check, as a vehicle may also count as your pet
			AddOtherButtons(unit, level, true)
		elseif UnitIsPlayer(unit) and (UnitInRaid(unit) or UnitInParty(unit)) then
			AddGroupMemberButtons(unit, level)
		else
			AddOtherButtons(unit, level, false)
		end

		AddButton(level, CANCEL, function()
			C_CloseDropDownMenus()
		end)
	elseif level == 2 then
		local value = C_UIDROPDOWNMENU_MENU_VALUE
		if value == "RAID_TARGET" then
			AddRaidTargetButtons(unit, level)
		elseif value == "LOOT_METHOD" then
			AddLootMethodButtons(level)
		elseif value == "LOOT_THRESHOLD" then
			AddLootThresholdButtons(level)
		end
	end
end

C_UIDropDownMenu_Initialize(dropDown, InitializeMenu, "MENU")

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Open our menu for a unit frame. Called by the frame's secure "menu" click action (right-click).
---@param frame table @The unit frame that was clicked
function ImprovedRaidFrames.ShowUnitMenu(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		return
	end

	-- Opening the menu for a different frame while it's open would otherwise just close it
	if C_DropDownList1:IsShown() and dropDown.ownerFrame ~= frame then
		C_CloseDropDownMenus()
	end

	dropDown.unit = unit
	dropDown.ownerFrame = frame
	dropDown.focusButtonIndex = nil
	C_ToggleDropDownMenu(1, nil, dropDown, frame:GetName(), 0, 0)

	-- Put the secure focus button over our "Set Focus" line
	if C_DropDownList1:IsShown() and C_UIDROPDOWNMENU_OPEN_MENU == dropDown then
		ImprovedRaidFrames:PlaceMenuFocusButton(dropDown)
	end
end

--- Give a frame our menu instead of Blizzard's
local function UseOurMenu(frame)
	frame.menu = ImprovedRaidFrames.ShowUnitMenu
end

-- Compact Raid Frame calls this from every unit frame's OnLoad to set up the right-click menu. Its version initialised
-- Blizzard's dropdown from addon code, which is the start of the taint. Ours never touches Blizzard's dropdown.
function CompactUnitFrame_SetMenuFunc(frame, menuFunc)
	UseOurMenu(frame)
end

-- Frames created before we loaded
for frame in pairs(ImprovedRaidFrames.frames) do
	UseOurMenu(frame)
end
