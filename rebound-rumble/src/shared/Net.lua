--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Every client -> server remote is type-checked and rate limited on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "ReboundRumbleRemotes"

Net.Names = {
	-- client -> server
	"Parry", -- (clientServerTime: number, aimDirection: Vector3)
	"UseAbility", -- (slot: number, moveDirection: Vector3?)
	"SetReady", -- (ready: boolean)
	"BuyAbility", -- (abilityId: string)
	"EquipAbility", -- (slot: number, abilityId: string)  lobby only
	"OpenCrate", -- (crateKey: string)
	"EquipCosmetic", -- (category: string, id: string)
	"ShopBuy", -- (productKey: string)
	"BuyPass", -- (passKey: string)
	"RedeemCode", -- (code: string)
	"ClaimDaily", -- ()
	"InviteSent", -- ()
	"SaveSettings", -- (settings: table)
	"RequestState", -- ()

	-- server -> client
	"MatchState", -- (state: string, data: table)
	"Roster", -- (contestants: table)
	"BallSync", -- (snapshot: table)
	"BallEvent", -- (kind: string, data: table)
	"ParryResult", -- (ok: boolean, reason: string, cooldown: number)
	"AbilityFx", -- (kind: string, data: table)  movement abilities run on the owning client
	"Fx", -- (kind: string, data: table)  visual effects for everyone
	"KillFeed", -- (entry: table)
	"Announce", -- (text: string, kind: string?)
	"Results", -- (results: table)
	"CrateResult", -- (result: table)
	"CodeResult", -- (ok: boolean, message: string)
	"Profile", -- (profile: table)
	"Notify", -- (text: string, kind: string?)
	"Goals", -- (goals: table)
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
