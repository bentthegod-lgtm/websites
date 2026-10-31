--[[
	Remote definitions. The server creates them once (Net.setup); clients wait for them.
	Clients only send requests and their own kart state; the server validates every
	argument (types, NaN, ranges, rate limits, distances) and decides every outcome.

	Kart replication:
	  client -> server  KartState(pos: Vector3, vel: Vector3, yaw: number, flags: number,
	                    seq: number) at GameConfig.Net.SendRate (~20 Hz), throttled.
	  server -> clients Karts(snapshot) at BroadcastRate (~15 Hz): every accepted kart
	                    (players and bots) with the server time; clients buffer ~100 ms and
	                    interpolate the remote karts.
	  server -> client  KartCorrect(cframe, vel, reason) when a move was rejected
	                    (teleport back), KartRespawn(cframe, ghostSeconds), KartEffect(kind,
	                    params, source).
	Personal race values travel as player attributes (CK_*); the race as RaceState.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "ChaosKartsRemotes"

Net.Names = {
	-- client -> server
	"RequestState", -- ()
	"SetReady", -- (ready: boolean)
	"KartState", -- (pos, vel, yaw, flags, seq)
	"Respawn", -- (reason: string)
	"UseItem", -- () Stage 3 stub
	"SelectVehicle", -- (id: string)
	"ShopBuy", -- (key: string)
	"ClaimDaily", -- ()
	"RedeemCode", -- (code: string)
	"SaveSettings", -- (settings: table)

	-- server -> client
	"Profile", -- (snapshot)
	"RaceState", -- (state)
	"Karts", -- (snapshot)
	"KartCorrect", -- (cframe, vel, reason)
	"KartRespawn", -- (cframe, ghostSeconds)
	"KartEffect", -- (kind, params, source)
	"RaceEvent", -- (kind, data)  lap / finish / checkpoint / wrongway / skip
	"Results", -- (summary)
	"EventStart", -- (payload)
	"EventStop", -- (instanceId)
	"Notify", -- (text, kind)
	"Announce", -- (text, color)
	"Leaderboard", -- (boards)
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

local function finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Net.finite = finite

-- Validates a Vector3 from a client: right type, finite, within `maxMagnitude` if given.
function Net.vector(v, maxMagnitude)
	if typeof(v) ~= "Vector3" then
		return nil
	end
	if not (finite(v.X) and finite(v.Y) and finite(v.Z)) then
		return nil
	end
	if maxMagnitude and v.Magnitude > maxMagnitude then
		return nil
	end
	return v
end

function Net.number(x, min, max)
	if not finite(x) then
		return nil
	end
	if (min and x < min) or (max and x > max) then
		return nil
	end
	return x
end

return Net
