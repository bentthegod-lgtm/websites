--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Every client->server remote is type-checked, range-checked and rate limited on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "SproutValleyRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"TileAction", -- (index: number, toolKind: string, toolId: string?)  toolKind: none|seed|gear|skip
	"MovePlant", -- (fromIndex: number, toIndex: number)  needs a Trowel
	"BuySeed", -- (cropId: string)
	"BuyGear", -- (gearId: string)
	"ExpandPlot", -- ()
	"Sell", -- (mode: "All"|"Item", itemId: number?)
	"Favorite", -- (itemId: number)
	"Gift", -- (targetUserId: number, itemId: number)
	"ShopBuy", -- (key: string)  developer product or game pass key
	"ClaimDaily", -- ()
	"RedeemCode", -- (code: string)
	"SetSetting", -- (key: string, value: boolean)
	"Travel", -- (destination: "Garden"|"Seeds"|"Gear"|"Sell")

	-- server -> client
	"Profile", -- (snapshot: table)
	"Stock", -- (stock: table)
	"Notify", -- (text: string, kind: string?)
	"Announce", -- (text: string, color: {r,g,b}?)
	"Effect", -- (kind: string, data: table)
	"OpenPanel", -- (name: string)
	"Leaderboard", -- (rows: table)
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
