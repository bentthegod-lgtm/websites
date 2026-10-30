--[[
	ClientState - the client's copy of what the server says (profile, round, team, boards)
	plus signals the other controllers listen to. The client never decides outcomes: it
	displays server state and sends requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local LootMath = require(Shared.LootMath)

local ClientState = {}

ClientState.profile = nil
ClientState.round = { phase = "Lobby", votes = {}, readyIds = {} }
ClientState.team = {}
ClientState.leaderboard = { Escapes = {}, Banked = {} }
ClientState.settings = nil
ClientState.lastResults = nil

ClientState.ProfileChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.RoundChanged = Signal.new()
ClientState.TeamChanged = Signal.new()
ClientState.Notified = Signal.new() -- (text, kind)
ClientState.Announced = Signal.new() -- (text, color)
ClientState.WorldSound = Signal.new() -- (name, position)
ClientState.Results = Signal.new() -- (summary)
ClientState.LeaderboardChanged = Signal.new()
ClientState.Braced = Signal.new() -- (seconds)
ClientState.Lurched = Signal.new() -- (oldPivot, newPivot, info)
ClientState.Knocked = Signal.new() -- (velocity)
ClientState.GrappleOk = Signal.new() -- (target)
ClientState.FlareArrow = Signal.new() -- (seconds, target)
ClientState.Cinematic = Signal.new() -- (kind, data)
ClientState.MenuRequested = Signal.new() -- (tab)

function ClientState.player()
	return Players.LocalPlayer
end

function ClientState.root()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function ClientState.humanoid()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- My round values (server-set attributes).
function ClientState.me()
	local p = Players.LocalPlayer
	return {
		state = p:GetAttribute("LL_State") or "Lobby",
		oxygen = p:GetAttribute("LL_Oxygen") or 12,
		oxygenMax = p:GetAttribute("LL_OxygenMax") or 12,
		carried = LootMath.decode(p:GetAttribute("LL_Carried")),
		slots = p:GetAttribute("LL_Slots") or 3,
		bleedEnds = p:GetAttribute("LL_BleedEnds"),
		reviveStart = p:GetAttribute("LL_ReviveStart"),
		aboard = p:GetAttribute("LL_Aboard") == true,
		inRound = p:GetAttribute("LL_InRound") == true,
		grapple = p:GetAttribute("LL_Grapple") == true,
		grappleReady = p:GetAttribute("LL_GrappleReady"),
		flares = p:GetAttribute("LL_Flares") or 0,
		jackets = p:GetAttribute("LL_Jackets") or 0,
		swim = p:GetAttribute("LL_SwimMult") or 1,
		grip = p:GetAttribute("LL_GripMult") or 1,
		climb = p:GetAttribute("LL_ClimbMult") or 1,
	}
end

-- The ship currently at the dock / sinking (cached; looked up at most twice a second).
local shipCache, shipCheckedAt = nil, -math.huge
function ClientState.ship()
	if shipCache and shipCache.Parent then
		return shipCache
	end
	shipCache = nil
	local now = os.clock()
	if now - shipCheckedAt < 0.5 then
		return nil
	end
	shipCheckedAt = now
	local folder = workspace:FindFirstChild("LastLifeboatShips")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Ship") then
				shipCache = m
				return m
			end
		end
	end
	return nil
end

function ClientState.serverNow()
	return workspace:GetServerTimeNow()
end

function ClientState.inRound()
	local r = ClientState.round
	return (r.phase == "Running" or r.phase == "Launching") and r.participants ~= nil and r.participants[tostring(Players.LocalPlayer.UserId)] == true
end

function ClientState.escapes()
	local p = ClientState.profile
	return p and p.stats and p.stats.Escapes or 0
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

-- Saves are coalesced: several slider taps send one save a moment later.
local savePending = false
function ClientState.saveSettings()
	if not ClientState.settings or savePending then
		return
	end
	savePending = true
	task.delay(1.2, function()
		savePending = false
		if ClientState.settings then
			Net.event("SaveSettings"):FireServer(ClientState.settings)
		end
	end)
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
		local before = ClientState.round and ClientState.round.phase
		ClientState.round = state or ClientState.round
		if ClientState.round.phase == "Running" and before ~= "Running" then
			ClientState.roundStartedAt = os.clock()
		elseif ClientState.round.phase == "Lobby" then
			ClientState.roundStartedAt = nil
		end
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
	on("WorldSound", function(name, position)
		ClientState.WorldSound:Fire(name, position)
	end)
	on("Results", function(summary)
		ClientState.lastResults = summary
		ClientState.Results:Fire(summary)
	end)
	on("Leaderboard", function(rows)
		ClientState.leaderboard = rows or { Escapes = {}, Banked = {} }
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
	on("Brace", function(seconds)
		ClientState.Braced:Fire(seconds)
	end)
	on("Lurch", function(old, new, info)
		ClientState.Lurched:Fire(old, new, info)
	end)
	on("Knockback", function(v)
		ClientState.Knocked:Fire(v)
	end)
	on("GrappleOk", function(target)
		ClientState.GrappleOk:Fire(target)
	end)
	on("FlareArrow", function(seconds, target)
		ClientState.FlareArrow:Fire(seconds, target)
	end)
	on("Cinematic", function(kind, data)
		ClientState.Cinematic:Fire(kind, data)
	end)
	on("OpenMenu", function(tab)
		ClientState.MenuRequested:Fire(tab)
	end)
end

return ClientState
