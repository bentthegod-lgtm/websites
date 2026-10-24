--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	All client->server remotes are validated and rate limited on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "DeadAirRemotes"

Net.Names = {
	-- client -> server
	"SetMovement", -- (sprintHeld: boolean, crouchOn: boolean)
	"ToggleFlashlight", -- ()
	"ThrowItem", -- (lookDirection: Vector3, slot: number?)
	"DropItem", -- (slot: number)
	"ExitHide", -- ()
	"SetReady", -- (ready: boolean)  only while standing in a party elevator
	"SetDifficulty", -- (name: string)  party elevator leader only
	"ShopBuy", -- (productKey: string)
	"ShopArm", -- (boostKey: string, on: boolean) use this boost on my next run
	"SaveSettings", -- (settings: table)
	"EquipCosmetic", -- (id: string)
	"RequestState", -- () ask for a full state resync after the client loads

	-- server -> client
	"RoundState", -- (state: string, data: table)
	"Party", -- (members: table)
	"Objective", -- (snapshot: table)
	"Inventory", -- (items: table)
	"Notify", -- (text: string, kind: string?)
	"NoiseFeedback", -- (loudness01: number) your own last noise, for the HUD meter
	"HorrorEvent", -- (name: string, data: table)
	"MonsterCue", -- (cue: string, data: table)
	"WorldSound", -- (audioKey: string, position: Vector3, volumeScale: number)
	"Results", -- (results: table)
	"Profile", -- (profile: table)
	"Lore", -- (note: table)
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
