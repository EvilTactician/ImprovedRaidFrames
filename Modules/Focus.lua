-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Focus and click-casting support for the Compact Raid Frame unit frames.
--
-- Setting focus is a protected action: addon code can't do it, only a secure button the player clicks. So:
--  * Ctrl-left-click on a raid frame focuses that unit, in and out of combat (a secure click attribute).
--  * When our right-click menu opens out of combat, secure buttons are placed exactly over its "Set Focus", "Main Tank"
--    and "Main Assist" lines (Blizzard-only actions). The game doesn't allow showing or moving secure buttons in combat,
--    so in combat those lines are greyed out and Ctrl-click is the way to focus.
--  * Frames are registered with Clique (ClickCastFrames), for players who use it.

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Set up Ctrl-left-click focus and Clique on a unit frame. Runs out of combat (the frame registry makes sure of that),
--- and is safe to run more than once.
---@param frame table @The unit frame
local function SetUpFrame(frame)
	-- Ctrl-left-click focuses. This takes precedence over Compact Raid Frame's "*type1" (any modifier) = target.
	frame:SetAttribute("ctrl-type1", "focus")

	-- Clique reads this table (and picks up frames added to it later)
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[frame] = true
end

ImprovedRaidFrames:RegisterFrameCreatedCallback(SetUpFrame)

-------------------------------------------------------------------------
-------------------------------------------------------------------------

-- Secure buttons we place over the menu lines with Blizzard-only actions (Set Focus / Clear Focus, Main Tank,
-- Main Assist). They sit in the TOOLTIP layer: the menu raises itself to the front of its own layer every time it opens,
-- so buttons in the same layer ended up underneath it after a few openings.
local MAX_SECURE_BUTTONS = 3
local secureButtons = {}

--- Close the menu once the action has been done
local function OnPostClick()
	C_CloseDropDownMenus()
end

-- Keep the menu open while the mouse is over us (the menu closes itself a moment after the mouse leaves it)
local function OnEnter()
	if C_UIDropDownMenu_StopCounting then
		C_UIDropDownMenu_StopCounting(C_DropDownList1)
	end
end
local function OnLeave()
	if C_UIDropDownMenu_StartCounting then
		C_UIDropDownMenu_StartCounting(C_DropDownList1)
	end
end

for i = 1, MAX_SECURE_BUTTONS do
	local button = CreateFrame("Button", "ImprovedRaidFramesMenuSecureButton" .. i, UIParent, "SecureActionButtonTemplate")
	button:SetFrameStrata("TOOLTIP")
	button:RegisterForClicks("LeftButtonUp")
	button:Hide()

	-- Our own highlight, as the menu line under us no longer sees the mouse
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	highlight:SetBlendMode("ADD")
	highlight:SetAllPoints(button)

	button:SetScript("PostClick", OnPostClick)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)

	secureButtons[i] = button
end

--- Hide the secure buttons (only possible out of combat)
local function HideSecureButtons()
	if InCombatLockdown() then
		return
	end
	for _, button in ipairs(secureButtons) do
		if button:IsShown() then
			button:Hide()
		end
	end
end

--- Put a secure button over each menu line with a Blizzard-only action. Called right after the menu is shown.
---@param dropDown table @Our unit menu dropdown; .secureLines lists { index, type, unit, macrotext } per line
function ImprovedRaidFrames:PlaceMenuSecureButtons(dropDown)
	if InCombatLockdown() then
		return
	end

	local lines = dropDown.secureLines or {}
	for i, button in ipairs(secureButtons) do
		local line = lines[i]
		local row = line and _G["C_DropDownList1Button" .. line.index]

		if row and row:IsVisible() and row:GetLeft() then
			button:SetAttribute("type1", line.type)
			button:SetAttribute("unit", line.unit)
			button:SetAttribute("macrotext1", line.macrotext)

			-- Position by screen coordinates rather than anchoring to the (insecure) menu line
			local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", row:GetLeft() * scale, row:GetBottom() * scale)
			button:SetWidth(row:GetWidth() * scale)
			button:SetHeight(row:GetHeight() * scale)
			button:Show()
		elseif button:IsShown() then
			button:Hide()
		end
	end
end

-- Hide the buttons when the menu closes
C_DropDownList1:HookScript("OnHide", HideSecureButtons)

-- Hide them as combat starts; secure buttons can't be hidden once combat lockdown is active
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		local anyShown = false
		for _, button in ipairs(secureButtons) do
			if button:IsShown() then
				anyShown = true
			end
		end
		if anyShown then
			HideSecureButtons()
			-- The menu's secure lines would no longer work, so close the menu
			if C_UIDROPDOWNMENU_OPEN_MENU == ImprovedRaidFrames.unitDropDown then
				C_CloseDropDownMenus()
			end
		end
	else
		-- In case the menu closed during combat
		if not C_DropDownList1:IsShown() then
			HideSecureButtons()
		end
	end
end)
