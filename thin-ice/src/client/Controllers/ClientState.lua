--[[
	ClientState - the client's copy of what the server says (profile, round, team, board)
	plus signals the other controllers listen to. The client never decides outcomes: it
	displays server state and sends requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {}

ClientState.profile = nil
ClientState.round = { phase = "Lobby", votes = {}, readyIds = {} }
ClientState.team = {}
ClientState.leaderboard = {}
ClientState.settings = nil
ClientState.mode = "Walk"

ClientState.ProfileChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.RoundChanged = Signal.new()
ClientState.TeamChanged = Signal.new()
ClientState.Notified = Signal.new() -- (text, kind)
ClientState.Announced = Signal.new() -- (text, color)
ClientState.WorldSound = Signal.new() -- (category, position, extra)
ClientState.MonsterCue = Signal.new() -- (kind, position, userId)
ClientState.Results = Signal.new() -- (summary)
ClientState.LeaderboardChanged = Signal.new()
ClientState.ModeChanged = Signal.new() -- (mode)

function ClientState.player()
	return Players.LocalPlayer
end

function ClientState.root()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- My survival values (server-set attributes).
function ClientState.me()
	local p = Players.LocalPlayer
	return {
		warmth = p:GetAttribute("TI_Warmth"),
		stamina = p:GetAttribute("TI_Stamina"),
		state = p:GetAttribute("TI_State"),
		snowballs = p:GetAttribute("TI_Snowballs"),
		mode = p:GetAttribute("TI_Mode"),
		carrying = p:GetAttribute("TI_Carrying") == true,
		inWater = p:GetAttribute("TI_InWater") == true,
	}
end

-- The Antlered's model while a round is on (cached; looked up at most once a second).
local monsterCache, monsterCheckedAt = nil, -math.huge
function ClientState.monster()
	if monsterCache and monsterCache.Parent then
		return monsterCache
	end
	monsterCache = nil
	local now = os.clock()
	if now - monsterCheckedAt < 1 then
		return nil
	end
	monsterCheckedAt = now
	local worldFolder = workspace:FindFirstChild("ThinIceWorld")
	local lake = worldFolder and worldFolder:FindFirstChild("Lake")
	if lake then
		for _, round in ipairs(lake:GetChildren()) do
			local m = round:FindFirstChild("Antlered")
			if m then
				monsterCache = m
				return m
			end
		end
	end
	return nil
end

function ClientState.inRound()
	local r = ClientState.round
	return (r.phase == "Running" or r.phase == "Sled") and r.participants ~= nil and r.participants[tostring(Players.LocalPlayer.UserId)] == true
end

function ClientState.setting(key)
	local s = ClientState.settings or (ClientState.profile and ClientState.profile.settings)
	return s and s[key]
end

function ClientState.applySettings(changes)
	ClientState.settings = ClientState.settings or {}
	for k, v in pairs(changes) do
		ClientState.settings[k] = v
	end
	ClientState.SettingsChanged:Fire(ClientState.settings)
end

function ClientState.saveSettings()
	if ClientState.settings then
		Net.event("SaveSettings"):FireServer(ClientState.settings)
	end
end

function ClientState.setMode(mode)
	if ClientState.mode ~= mode then
		ClientState.mode = mode
		Net.event("SetMoveMode"):FireServer(mode)
		ClientState.ModeChanged:Fire(mode)
	end
end

function ClientState.init()
	local function on(name, fn)
		Net.event(name).OnClientEvent:Connect(fn)
	end
	on("Profile", function(snapshot)
		local first = ClientState.profile == nil
		ClientState.profile = snapshot
		if first or not ClientState.settings then
			ClientState.settings = table.clone(snapshot.settings or {})
			ClientState.SettingsChanged:Fire(ClientState.settings)
		end
		ClientState.ProfileChanged:Fire(snapshot)
	end)
	on("RoundState", function(state)
		ClientState.round = state or ClientState.round
		ClientState.RoundChanged:Fire(ClientState.round)
	end)
	on("Team", function(rows)
		ClientState.team = rows or {}
		ClientState.TeamChanged:Fire(ClientState.team)
	end)
	on("Notify", function(text, kind)
		ClientState.Notified:Fire(text, kind)
	end)
	on("Announce", function(text, color)
		ClientState.Announced:Fire(text, color)
	end)
	on("WorldSound", function(category, position, extra)
		ClientState.WorldSound:Fire(category, position, extra)
	end)
	on("MonsterCue", function(kind, position, userId)
		ClientState.MonsterCue:Fire(kind, position, userId)
	end)
	on("Results", function(summary)
		ClientState.Results:Fire(summary)
	end)
	on("Leaderboard", function(rows)
		ClientState.leaderboard = rows or {}
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
end

return ClientState
