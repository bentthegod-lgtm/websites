--[[
	CHAOS KARTS - server bootstrap.
	Sets up the dusk lighting and the remotes, builds the lobby at once and the track + city
	over the next frames (fast startup), wires the services together and drives the whole
	game from one Heartbeat connection.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Net = require(Shared.Net)
local GameConfig = require(Shared.Config.GameConfig)
Net.setup()

local Services = script.Parent:WaitForChild("Services")
local World = require(script.Parent:WaitForChild("World"):WaitForChild("World"))
World.lighting()

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"DataService",
	"ShopService",
	"RewardService",
	"PlayerService",
	"KartEffects",
	"KartService",
	"BotService",
	"EventDirector",
	"RaceService",
	"LeaderboardService",
}

local registry = { Remotes = remotes }
for _, name in ipairs(ORDER) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(ORDER) do
	registry[name].init(registry)
end

local map = require(Shared.Maps:WaitForChild(GameConfig.Race.Map))
local world = World.new(map, workspace)
for _, name in ipairs(ORDER) do
	if registry[name].setWorld then
		registry[name].setWorld(world)
	end
end
for _, name in ipairs(ORDER) do
	if name ~= "DataService" and registry[name].start then
		registry[name].start()
	end
end
registry.DataService.start() -- last: loading profiles calls into every other service

local announced = false
RunService.Heartbeat:Connect(function(dt)
	if not world.ready then
		world:step(World.PartsPerStep)
		if world.ready and not announced then
			announced = true
			print(string.format("[ChaosKarts] Track and city built: %d parts over %d frames (worst frame %.1f ms).", world.job.made, world.timings.frames, world.timings.worst * 1000))
			registry.RaceService.broadcastState()
		end
	end
	registry.RaceService.step(dt)
end)

print(string.format("[ChaosKarts] Server ready: lobby %d parts in %.3fs; %d track / city parts queued.", world.lobby.partCount, world.timings.lobby, world.plan.total))
