--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Clients only ever send requests (an item id, an upgrade key, a depth number). The server
	checks type, range, distance, cooldown and rate on every one and computes all values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "VaultRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"Collect", -- (lootId: number)
	"Deposit", -- (machineId: string)   (also the machine's ProximityPrompt / auto-deposit zone)
	"BuyUpgrade", -- (key: string)
	"BuyPerk", -- (key: string)   Vault Token perk
	"UnlockDepth", -- (depth: number)
	"Travel", -- (depth: number)   elevator ride
	"Rebirth", -- (confirm: string)   must be "REBIRTH"
	"Tutorial", -- (action: "Skip" | "Replay")
	"RedeemCode", -- (code: string)
	"SaveSettings", -- (settings: table)
	"ShopBuy", -- (key: string)   Robux products / passes
	"BuyCosmetic", -- (kind: string, id: string)   Vault Token cosmetics
	"Equip", -- (kind: string, id: string)

	-- server -> client
	"Profile", -- (snapshot)
	"Inventory", -- (carried: { count, slots, capacity, value, items = { [lootId] = n } })
	"Collected", -- (userId, lootId, itemId, position, value)   to everyone (pickup fx)
	"Deposited", -- (userId, summary)   to everyone (machine fx); the owner shows the summary
	"Elevator", -- (phase: "Depart" | "Arrive" | "Cancel", data)
	"RareEvent", -- (phase: "Spawn" | "Gone", data)
	"Notify", -- (text, kind)
	"Popup", -- (kind, data)  achievement / discovery / daily / depth / rebirth
	"Announce", -- (text, color)
	"Leaderboard", -- (boards)
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
