--[[
	FeedService - server-wide announcements (steal attempts, rare spawns, events...).
	Shown in the HUD feed and, when `chat` is true, as a system message in the chat.
]]

local FeedService = {}

local services

function FeedService.init(registry)
	services = registry
end

-- color: { r, g, b }
function FeedService.announce(text, color, chat)
	if type(text) ~= "string" then
		return
	end
	services.Remotes.Feed:FireAllClients(text, color or { 255, 255, 255 }, chat == true)
end

function FeedService.start() end

return FeedService
