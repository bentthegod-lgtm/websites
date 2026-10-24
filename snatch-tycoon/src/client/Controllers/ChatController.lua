--[[
	ChatController - server announcements as system messages in the chat, and the [VIP]
	chat tag (players with the VIP pass have the VIP attribute set by the server).
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ClientState = require(script.Parent.ClientState)

local ChatController = {}

local function hex(color)
	if type(color) ~= "table" then
		return "FFFFFF"
	end
	return string.format("%02X%02X%02X", color[1] or 255, color[2] or 255, color[3] or 255)
end

local function escape(text)
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

function ChatController.system(text, color)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			general:DisplaySystemMessage(string.format('<font color="#%s">%s</font>', hex(color), escape(text)))
		end
	end)
end

function ChatController.init()
	ClientState.Feed:Connect(function(text, color, chat)
		if chat then
			ChatController.system(text, color)
		end
	end)
	pcall(function()
		TextChatService.OnIncomingMessage = function(message)
			local props = Instance.new("TextChatMessageProperties")
			local source = message.TextSource
			local speaker = source and Players:GetPlayerByUserId(source.UserId)
			if speaker and speaker:GetAttribute("VIP") then
				props.PrefixText = '<font color="#FFD23C">[VIP]</font> ' .. message.PrefixText
			end
			return props
		end
	end)
end

return ChatController
