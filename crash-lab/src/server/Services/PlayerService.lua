--[[
	PlayerService - characters, settings and state requests.

	* Character parts go into the "CL_Player" collision group, so dummies and debris pass
	  through players (nobody can block, or be bowled over by, another player's run).
	* Settings: only known keys with legal values are saved (validated here).
	* RequestState: a client asking for the current profile / pads / leaderboard (throttled).
]]

local Players = game:GetService("Players")

local PlayerService = {}

local services
local lastState = {}
local lastSettings = {}

local SETTING_RULES = {
	Master = { kind = "number", min = 0, max = 1 },
	Music = { kind = "number", min = 0, max = 1 },
	Effects = { kind = "number", min = 0, max = 1 },
	Ambient = { kind = "number", min = 0, max = 1 },
	UI = { kind = "number", min = 0, max = 1 },
	Sensitivity = { kind = "number", min = 0.2, max = 3 },
	CameraShake = { kind = "boolean" },
	FollowCam = { kind = "boolean" },
	ReducedEffects = { kind = "boolean" },
}

function PlayerService.init(registry)
	services = registry
end

local function setGroup(part)
	if part:IsA("BasePart") then
		part.CollisionGroup = services.CrashService.Groups.Player
	end
end

function PlayerService.onCharacter(player, character)
	for _, d in ipairs(character:GetDescendants()) do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)
	-- Respawn in the facility the player was in.
	services.CourseService.onCharacter(player, character)
end

function PlayerService.saveSettings(player, incoming)
	local data = services.DataService.getProfile(player)
	if not data or type(incoming) ~= "table" then
		return false
	end
	for key, rule in pairs(SETTING_RULES) do
		local v = incoming[key]
		if rule.kind == "number" and type(v) == "number" and v == v then
			data.Settings[key] = math.clamp(v, rule.min, rule.max)
		elseif rule.kind == "boolean" and type(v) == "boolean" then
			data.Settings[key] = v
		end
	end
	services.DataService.markDirty(player)
	return true
end

function PlayerService.onPlayerRemoving(player)
	lastState[player] = nil
	lastSettings[player] = nil
end

function PlayerService.start()
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			PlayerService.onCharacter(player, character)
		end)
		if player.Character then
			PlayerService.onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	local remotes = services.Remotes
	remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		local t = os.clock()
		if lastSettings[player] and t - lastSettings[player] < 0.5 then
			return
		end
		lastSettings[player] = t
		PlayerService.saveSettings(player, settings)
	end)
	remotes.RequestState.OnServerEvent:Connect(function(player)
		local t = os.clock()
		if lastState[player] and t - lastState[player] < 2 then
			return
		end
		lastState[player] = t
		if services.DataService.getProfile(player) then
			services.DataService.sendProfile(player)
		end
		remotes.PadState:FireClient(player, services.PadService.state())
		remotes.Leaderboard:FireClient(player, services.LeaderboardService.rows())
	end)
end

return PlayerService
