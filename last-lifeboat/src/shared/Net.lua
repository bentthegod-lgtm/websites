--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Clients only send requests (ready, vote, purchases, grapple target...); the server
	validates every argument and decides every outcome.

	Fast-changing personal values (oxygen, state, carried loot, bleed-out time) travel as
	player attributes (LL_*); ship state (tilt, next lurch, launch time) as Workspace
	attributes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "LastLifeboatRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"SetReady", -- (ready: boolean)
	"Vote", -- (shipKey: string)
	"ShopBuy", -- (key: string)  Robux items
	"BuyUpgrade", -- (key: string)  coin upgrades
	"ClaimDaily", -- ()
	"RedeemCode", -- (code: string)
	"SaveSettings", -- (settings: table)
	"Grapple", -- (target: Vector3)
	"UseFlare", -- ()
	"DropLoot", -- (slot: number)

	-- server -> client
	"Profile", -- (snapshot)
	"RoundState", -- (state)
	"Team", -- (rows)
	"Notify", -- (text, kind)
	"Announce", -- (text, color)
	"Results", -- (summary)
	"Leaderboard", -- (boards)
	"Brace", -- (seconds)
	"Lurch", -- (oldPivot: CFrame, newPivot: CFrame, info)
	"WorldSound", -- (name, position?)
	"Knockback", -- (velocity: Vector3)
	"GrappleOk", -- (target: Vector3)
	"FlareArrow", -- (seconds, target: Vector3)
	"Cinematic", -- (kind, data)
	"OpenMenu", -- (tab)
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

-- Validates a Vector3 from a client: right type, finite, within `maxMagnitude` if given.
function Net.vector(v, maxMagnitude)
	if typeof(v) ~= "Vector3" then
		return nil
	end
	for _, c in ipairs({ v.X, v.Y, v.Z }) do
		if c ~= c or c == math.huge or c == -math.huge then
			return nil
		end
	end
	if maxMagnitude and v.Magnitude > maxMagnitude then
		return nil
	end
	return v
end

return Net
