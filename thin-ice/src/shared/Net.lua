--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Clients only ever send requests (ready, vote, move mode, throw direction, purchases);
	the server validates every argument and decides every outcome.

	Fast-changing personal values (warmth, stamina, state, snowballs) travel as player
	attributes (TI_*) instead of remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "ThinIceRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"SetReady", -- (ready: boolean)
	"Vote", -- (difficulty: string)
	"SetMoveMode", -- ("Walk" | "Sneak" | "Sprint")
	"Throw", -- (direction: Vector3)
	"ShopBuy", -- (key: string)  Robux items
	"BuyCosmetic", -- (kind: string, id: string)  coin cosmetics
	"Equip", -- (kind: string, id: string)
	"ClaimDaily", -- ()
	"RedeemCode", -- (code: string)
	"SaveSettings", -- (settings: table)

	-- server -> client
	"Profile", -- (snapshot)
	"RoundState", -- (state)
	"Team", -- (rows)
	"WorldSound", -- (category, position)
	"MonsterCue", -- (kind, data)
	"Notify", -- (text, kind)
	"Announce", -- (text, color)
	"Results", -- (summary)
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
