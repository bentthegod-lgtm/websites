--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Every client -> server remote is type-checked, range-checked and rate limited on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "MagnetMayhemRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"Magnet", -- (on: boolean)
	"Pulse", -- ()
	"Sprint", -- (on: boolean)
	"Sell", -- ()  (also by standing on the sell pad / the shredder prompt)
	"BuyUpgrade", -- (key: string)
	"BuyTier", -- ()
	"UnlockZone", -- (zoneId: string)
	"Prestige", -- (confirm: string)  must be "CONFIRM"
	"Tutorial", -- (action: "Skip" | "Replay")
	"Equip", -- (kind: "Skin" | "Trail", id: string)
	"ShopBuy", -- (key: string)
	"RedeemCode", -- (code: string)
	"SaveSettings", -- (settings: table)

	-- server -> client
	"Profile", -- (snapshot)
	"Attract", -- (batch: { {id, userId, duration, anticipation, pulse} })
	"Collected", -- (batch: { {id, userId, scrap, value, lucky} })
	"Released", -- (ids: {number})
	"SellFx", -- (userId, amount, count, big)
	"Notify", -- (text, kind)
	"Popup", -- (kind, data)  rare discovery, achievement, quest, tier, zone
	"Announce", -- (text, color)
	"Event", -- (state table for the current world event or nil)
	"Leaderboard", -- (rows)
}

local folder

function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server-only")
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(Net.Names) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Net.event(name)
	if not folder then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	local remote = folder:FindFirstChild(name) or folder:WaitForChild(name, 10)
	assert(remote, "Unknown remote " .. tostring(name))
	return remote
end

return Net
