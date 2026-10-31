--[[
	PlayerService - per-player bookkeeping outside the race: attributes the client reads
	(CK_Level, CK_Vehicle, CK_VIP), settings saves (only known keys with legal values),
	vehicle selection (cosmetic only - every vehicle drives the same) and the state request
	a client sends when it starts. Characters stay in the lobby; while racing, RaceService
	parks them out of sight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Progress = require(Shared.Progress)
local VehicleRegistry = require(Shared.Vehicles.Registry)
local RateLimit = require(script.Parent.RateLimit)

local PlayerService = {}

local services
local world
local limit = RateLimit.new(2, 4)

function PlayerService.init(registry)
	services = registry
end

function PlayerService.setWorld(newWorld)
	world = newWorld
end

function PlayerService.refresh(player)
	local data = services.DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	player:SetAttribute("CK_Level", (Progress.level(data.XP)))
	player:SetAttribute("CK_Vehicle", data.Vehicle)
	player:SetAttribute("CK_VIP", services.ShopService.ownsPass(player, "VIP"))
end

function PlayerService.onProfileLoaded(player)
	PlayerService.refresh(player)
end

function PlayerService.vehicleOf(player)
	local data = services.DataService.getProfile(player)
	return if data then data.Vehicle else VehicleRegistry.DEFAULT
end

-- Stage 1: every vehicle is free. Stage 7 adds unlocks (cosmetic only).
function PlayerService.selectVehicle(player, id)
	local data = services.DataService.getProfile(player)
	if not data or not VehicleRegistry.exists(id) then
		return false
	end
	data.Vehicle = id
	services.DataService.markDirty(player)
	PlayerService.refresh(player)
	services.DataService.sendProfile(player)
	return true
end

function PlayerService.saveSettings(player, settings)
	local data = services.DataService.getProfile(player)
	if not data or type(settings) ~= "table" then
		return false
	end
	local defaults = services.DataService.defaultSettings()
	for key, default in pairs(defaults) do
		local v = settings[key]
		if type(default) == "number" and type(v) == "number" and v == v then
			data.Settings[key] = math.clamp(v, 0, 1)
		elseif type(default) == "boolean" and type(v) == "boolean" then
			data.Settings[key] = v
		end
	end
	services.DataService.markDirty(player)
	return true
end

function PlayerService.onPlayerRemoving(player)
	limit:forget(player)
end

function PlayerService.start()
	local remotes = services.Remotes
	remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		if limit:allow(player) then
			PlayerService.saveSettings(player, settings)
		end
	end)
	remotes.SelectVehicle.OnServerEvent:Connect(function(player, id)
		if not limit:allow(player) or type(id) ~= "string" or #id > 40 then
			return
		end
		if PlayerService.selectVehicle(player, id) then
			remotes.Notify:FireClient(player, "Kart selected: " .. VehicleRegistry.get(id).Name .. " (looks only - every kart drives the same).", "good")
		end
	end)
	remotes.RequestState.OnServerEvent:Connect(function(player)
		if not limit:allow(player) then
			return
		end
		services.DataService.sendProfile(player)
		services.RaceService.sendState(player)
		if services.LeaderboardService then
			remotes.Leaderboard:FireClient(player, services.LeaderboardService.rows())
		end
		if services.EventDirector then
			services.EventDirector.syncPlayer(player)
		end
	end)
	-- lobby kiosks open the matching menu tab
	local prompts = world and world.lobby and world.lobby.prompts or {}
	for tab, p in pairs(prompts) do
		p.Triggered:Connect(function(player)
			remotes.OpenMenu:FireClient(player, tab)
		end)
	end
	PlayerService.prompts = prompts
end

return PlayerService
