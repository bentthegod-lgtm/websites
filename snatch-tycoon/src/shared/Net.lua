--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Every client -> server remote is type checked, NaN checked and rate limited on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "SnatchTycoonRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"LockBase", -- ()
	"Slap", -- ()
	"DropCarried", -- ()
	"Rebirth", -- ()
	"ClaimDaily", -- ()
	"RedeemCode", -- (code: string)
	"ShopBuy", -- (productKey: string)
	"PassBuy", -- (passKey: string)
	"SaveSettings", -- (settings: { Music: boolean, Sfx: boolean })

	-- server -> client
	"Profile", -- (snapshot: table) full state, sent on change
	"Tick", -- (tick: table) cash / income / lock timers, every second
	"Notify", -- (text: string, kind: string?)
	"Feed", -- (text: string, color: {r,g,b}?, chat: boolean?) server-wide announcement
	"Popup", -- (kind: string, data: table) cash numbers, big reveals, rewards
	"Events", -- (events: table) active events and countdowns
	"Sfx", -- (soundKey: string, position: Vector3?)
	"Knockback", -- (velocity: Vector3) you got slapped
	"SlapFx", -- (from: Vector3, to: Vector3) everyone sees the slap
	"Carry", -- (info: table?) what you're carrying (nil = nothing)
	"Alarm", -- (thiefName: string, blobbyName: string) someone is stealing from you
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
