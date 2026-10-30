--[[
	SocialController - the VIP chat tag: messages from players with the VIP pass (the
	server sets their LL_VIP attribute) get a gold [VIP] prefix in the chat window. The gold
	name over their head is a BillboardGui the server builds (PlayerService).
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local SocialController = {}

-- The prefix for a chat message's sender (nil = none). Pure, for tests.
function SocialController.prefixFor(player)
	if player and player:GetAttribute("LL_VIP") == true then
		return '<font color="#FFCD46">[VIP]</font> '
	end
	return nil
end

function SocialController.init()
	pcall(function()
		TextChatService.OnIncomingMessage = function(message)
			local props = Instance.new("TextChatMessageProperties")
			local source = message.TextSource
			local player = source and Players:GetPlayerByUserId(source.UserId)
			local prefix = SocialController.prefixFor(player)
			if prefix then
				props.PrefixText = prefix .. message.PrefixText
			end
			return props
		end
	end)
end

return SocialController
