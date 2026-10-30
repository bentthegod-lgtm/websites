--[[
	LAST LIFEBOAT - server bootstrap.
	Sets up the dusk lighting, remotes and the harbour dock, wires the services together and
	drives the whole game from one Heartbeat connection (RoundService.step). Nothing big is
	built synchronously: the Terrain ocean and the ships are built a few blocks / a few
	hundred parts per frame, so startup never comes near Roblox's script timeout.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local Net = require(Shared.Net)
Net.setup()

-- Harbour at dusk: low warm sun, purple-orange sky, soft haze, bloom on the lights.
Lighting.ClockTime = 18.2
Lighting.Brightness = 1.6
Lighting.Ambient = Color3.fromRGB(96, 84, 110)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 120, 130)
Lighting.ColorShift_Top = Color3.fromRGB(255, 190, 140)
if not Lighting:FindFirstChildOfClass("Atmosphere") then
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(230, 170, 150)
	atmosphere.Decay = Color3.fromRGB(110, 80, 120)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting
end
if not Lighting:FindFirstChildOfClass("BloomEffect") then
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
end
if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end
pcall(function()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		terrain.WaterColor = Color3.fromRGB(26, 72, 92)
		terrain.WaterTransparency = 0.55
		terrain.WaterWaveSize = 0.12
		terrain.WaterWaveSpeed = 8
		terrain.WaterReflectance = 0.6
	end
end)

local Services = script.Parent:WaitForChild("Services")
local LobbyBuilder = require(script.Parent:WaitForChild("World"):WaitForChild("LobbyBuilder"))

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"DataService",
	"ShopService",
	"UpgradeService",
	"RewardService",
	"PlayerService",
	"ShipService",
	"SurvivalService",
	"LootService",
	"ObstacleService",
	"LifeboatService",
	"AbilityService",
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

local t0 = os.clock()
local world = LobbyBuilder.build(workspace)
local lobbyTime = os.clock() - t0
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

print(string.format("[LastLifeboat] Server ready: harbour %d parts in %.3fs; the sea and the ship build over the next frames.", world.partCount, lobbyTime))
