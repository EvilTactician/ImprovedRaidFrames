-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Focus and click-casting support for the Compact Raid Frame unit frames.
--
-- Setting focus is a protected action: addon code can't do it, only a secure button the player clicks. So:
--  * Ctrl-left-click on a raid frame focuses that unit, in and out of combat (a secure click attribute).
--  * When our right-click menu opens out of combat, a secure button is placed exactly over its "Set Focus" line.
--    The game doesn't allow showing or moving secure buttons in combat, so in combat that line is greyed out and
--    Ctrl-click is the way to focus.
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

-- The secure button we place over the menu's "Set Focus" line
local focusButton = CreateFrame("Button", "ImprovedRaidFramesMenuFocusButton", UIParent, "SecureActionButtonTemplate")
focusButton:SetFrameStrata("FULLSCREEN_DIALOG")
focusButton:SetFrameLevel(100)
focusButton:RegisterForClicks("LeftButtonUp")
focusButton:Hide()

-- Our own highlight, as the menu line under us no longer sees the mouse
local highlight = focusButton:CreateTexture(nil, "HIGHLIGHT")
highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
highlight:SetBlendMode("ADD")
highlight:SetAllPoints(focusButton)

-- Close the menu once focus has been set or cleared
focusButton:SetScript("PostClick", function()
	C_CloseDropDownMenus()
end)

-- Keep the menu open while the mouse is over us (the menu closes itself a moment after the mouse leaves it)
focusButton:SetScript("OnEnter", function()
	if C_UIDropDownMenu_StopCounting then
		C_UIDropDownMenu_StopCounting(C_DropDownList1)
	end
end)
focusButton:SetScript("OnLeave", function()
	if C_UIDropDownMenu_StartCounting then
		C_UIDropDownMenu_StartCounting(C_DropDownList1)
	end
end)

--- Hide the secure focus button (only possible out of combat)
local function HideFocusButton()
	if focusButton:IsShown() and not InCombatLockdown() then
		focusButton:Hide()
	end
end

--- Put the secure focus button over the "Set Focus" / "Clear Focus" line of our menu.
--- Called right after the menu is shown.
---@param dropDown table @Our unit menu dropdown, with .unit, .focusButtonIndex and .focusIsClear set
function ImprovedRaidFrames:PlaceMenuFocusButton(dropDown)
	if InCombatLockdown() or not dropDown.focusButtonIndex then
		return
	end

	local row = _G["C_DropDownList1Button" .. dropDown.focusButtonIndex]
	if not row or not row:IsVisible() or not row:GetLeft() then
		return
	end

	-- Clear focus with a macro, as there is no secure "clear focus" action type we can rely on
	if dropDown.focusIsClear then
		focusButton:SetAttribute("type1", "macro")
		focusButton:SetAttribute("macrotext1", "/clearfocus")
		focusButton:SetAttribute("unit", nil)
	else
		focusButton:SetAttribute("type1", "focus")
		focusButton:SetAttribute("macrotext1", nil)
		focusButton:SetAttribute("unit", dropDown.unit)
	end

	-- Position by screen coordinates rather than anchoring to the (insecure) menu line
	local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
	focusButton:ClearAllPoints()
	focusButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", row:GetLeft() * scale, row:GetBottom() * scale)
	focusButton:SetWidth(row:GetWidth() * scale)
	focusButton:SetHeight(row:GetHeight() * scale)
	focusButton:Show()
end

-- Hide the button when the menu closes
C_DropDownList1:HookScript("OnHide", HideFocusButton)

-- Hide it as combat starts; secure buttons can't be hidden once combat lockdown is active
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		if focusButton:IsShown() then
			focusButton:Hide()
			-- The menu's "Set Focus" line would no longer work, so close the menu
			if C_UIDROPDOWNMENU_OPEN_MENU == ImprovedRaidFrames.unitDropDown then
				C_CloseDropDownMenus()
			end
		end
	else
		-- In case the menu closed during combat
		if not C_DropDownList1:IsShown() then
			HideFocusButton()
		end
	end
end)
