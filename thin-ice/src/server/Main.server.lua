--[[
	THIN ICE - server bootstrap.
	Sets up the night lighting, remotes and the shore camp, wires the services together and
	drives the whole game from one Heartbeat connection (RoundService.step). The lake itself
	is built per round, a few tiles per frame, so startup stays quick.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local Net = require(Shared.Net)
Net.setup()

-- Night over the lake: cold blue ambient, a little fog, soft bloom on the fires.
Lighting.ClockTime = 0.3
Lighting.Ambient = Color3.fromRGB(70, 86, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(90, 110, 150)
Lighting.FogColor = Color3.fromRGB(40, 54, 84)
if not Lighting:FindFirstChildOfClass("Atmosphere") then
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(120, 150, 200)
	atmosphere.Decay = Color3.fromRGB(40, 50, 80)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
end
if not Lighting:FindFirstChildOfClass("BloomEffect") then
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

local Services = script.Parent:WaitForChild("Services")
local LobbyBuilder = require(script.Parent:WaitForChild("World"):WaitForChild("LobbyBuilder"))

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"DataService",
	"NoiseService",
	"WeatherService",
	"SurvivalService",
	"IceService",
	"ObjectiveService",
	"MonsterService",
	"RewardService",
	"ShopService",
	"PlayerService",
	"RoundService",
	"LeaderboardService",
}

local registry = { Remotes = remotes }
for _, name in ipairs(ORDER) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(ORDER) do
	registry[name].init(registry)
end

local world = LobbyBuilder.build(workspace)
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

RunService.Heartbeat:Connect(function(dt)
	registry.RoundService.step(dt)
end)

print(string.format("[ThinIce] Server ready (%d shore parts; the lake is built each round).", world.partCount))
