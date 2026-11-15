-- Improved Raid Frames is a World of Warcraft® user interface addon.
-- This file is part of Improved Raid Frames and is licensed under the MIT license (see LICENSE for details)

-- Playerbot heals.
--
-- LibHealComm-4.0 only knows about another player's heals when that player's client tells the group about them.
-- Playerbots have no client, so their heals never show. The AzerothCore server module mod-playerbot-heal-tracker
-- sends the standard LibHealComm messages on the bots' behalf, but only to players who ask for them.
--
-- This file does the asking. When the "Show playerbot heals" option is on, we send a HELLO to the server; the module
-- answers with an ACK, which tells us it is installed. The heal messages themselves are handled by LibHealComm-4.0, so
-- any addon using it (not just this one) shows the bot heals.
--
-- Protocol (addon messages, prefix IRFBH, whispered to ourselves so the server can see them):
--   client -> server   HELLO:<protocol>        start sending playerbot heal data to me
--   client -> server   BYE:<protocol>          stop sending it
--   server -> client   ACK:<protocol>:<moduleVersion>

-- Create a local handle to our addon table
---@type ImprovedRaidFrames
local ImprovedRaidFrames = _G.ImprovedRaidFrames

local L = LibStub("AceLocale-3.0"):GetLocale("ImprovedRaidFrames")

local PREFIX = "IRFBH"
local PROTOCOL = 1

-- How long we wait for the server module to answer before deciding it isn't installed
local ACK_TIMEOUT = 10

-- Status values shown in the options
ImprovedRaidFrames.BOT_HEALS_OFF = "off"
ImprovedRaidFrames.BOT_HEALS_WAITING = "waiting"
ImprovedRaidFrames.BOT_HEALS_DETECTED = "detected"
ImprovedRaidFrames.BOT_HEALS_NOT_DETECTED = "notdetected"

ImprovedRaidFrames.botHealStatus = ImprovedRaidFrames.BOT_HEALS_OFF

-------------------------------------------------------------------------
-------------------------------------------------------------------------

--- Send a message to the server module
---@param command string @HELLO or BYE
local function SendToServer(command)
	SendAddonMessage(PREFIX, command .. ":" .. PROTOCOL, "WHISPER", UnitName("player"))
end

local listener = CreateFrame("Frame", "ImprovedRaidFramesBotHealsListener")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:SetScript("OnEvent", function(_, _, prefix, message)
	if prefix ~= PREFIX then
		return
	end

	local command, protocol, moduleVersion = strsplit(":", message)
	if command == "ACK" then
		ImprovedRaidFrames.botHealModuleVersion = moduleVersion
		ImprovedRaidFrames.botHealModuleProtocol = tonumber(protocol)
		if ImprovedRaidFrames.botHealsSubscribed then
			ImprovedRaidFrames.botHealStatus = ImprovedRaidFrames.BOT_HEALS_DETECTED
			ImprovedRaidFrames:NotifyBotHealStatusChanged()
		end
	end
end)

--- Refresh the options window if it is showing the bot heal status
function ImprovedRaidFrames:NotifyBotHealStatusChanged()
	LibStub("AceConfigRegistry-3.0"):NotifyChange("IRF Heal Prediction Options")
end

--- Ask the server for playerbot heal data, or tell it to stop, to match the current option
function ImprovedRaidFrames:UpdateBotHealSubscription()
	if not self.db then
		return
	end

	if self.db.profile.botHeals then
		if self.botHealsSubscribed then
			return
		end
		self.botHealsSubscribed = true
		self.botHealStatus = self.BOT_HEALS_WAITING
		SendToServer("HELLO")

		-- If the server module doesn't answer, it isn't installed
		if self.botHealAckTimer then
			self:CancelTimer(self.botHealAckTimer)
		end
		self.botHealAckTimer = self:ScheduleTimer(function()
			self.botHealAckTimer = nil
			if self.botHealsSubscribed and self.botHealStatus == self.BOT_HEALS_WAITING then
				self.botHealStatus = self.BOT_HEALS_NOT_DETECTED
				self:Print(L["botHealsNotDetected"])
				self:NotifyBotHealStatusChanged()
			end
		end, ACK_TIMEOUT)
	else
		if not self.botHealsSubscribed then
			return
		end
		self.botHealsSubscribed = false
		self.botHealStatus = self.BOT_HEALS_OFF
		SendToServer("BYE")
	end

	self:NotifyBotHealStatusChanged()
end

--- Text describing the current playerbot heal status, for the options
---@return string
function ImprovedRaidFrames:GetBotHealStatusText()
	local status = self.botHealStatus
	if status == self.BOT_HEALS_DETECTED then
		return self.GREEN_COLOR:WrapTextInColorCode(string.format(L["botHealsStatusDetected"], tostring(self.botHealModuleVersion)))
	elseif status == self.BOT_HEALS_WAITING then
		return self.YELLOW_COLOR:WrapTextInColorCode(L["botHealsStatusWaiting"])
	elseif status == self.BOT_HEALS_NOT_DETECTED then
		return self.RED_COLOR:WrapTextInColorCode(L["botHealsStatusNotDetected"])
	end
	return L["botHealsStatusOff"]
end
