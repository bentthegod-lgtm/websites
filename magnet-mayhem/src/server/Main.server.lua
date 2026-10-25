--[[
	MAGNET MAYHEM - server bootstrap.
	Sets up lighting, remotes and the world, then wires the services together.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Rustyard: warm late-afternoon sun, golden haze, cool shadows (clients blend to each
-- zone's preset from ZoneConfig as they move between zones).
Lighting.ClockTime = 16.6
Lighting.GeographicLatitude = 38
Lighting.Brightness = 2.6
Lighting.Ambient = Color3.fromRGB(118, 104, 92)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 132, 112)
Lighting.EnvironmentDiffuseScale = 0.55
Lighting.EnvironmentSpecularScale = 0.6
Lighting.ShadowSoftness = 0.25
Lighting.FogColor = Color3.fromRGB(214, 182, 140)
Lighting.FogStart = 150
Lighting.FogEnd = 900
local function effect(className, name, props)
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = Lighting
	return e
end
effect("Atmosphere", "MM_Atmosphere", { Density = 0.3, Offset = 0.15, Color = Color3.fromRGB(222, 190, 150), Decay = Color3.fromRGB(160, 120, 90), Glare = 0.35, Haze = 1.4 })
effect("ColorCorrectionEffect", "MM_Grade", { TintColor = Color3.fromRGB(255, 238, 214), Saturation = -0.08, Contrast = 0.08, Brightness = 0.02 })
effect("BloomEffect", "MM_Bloom", { Intensity = 0.35, Size = 22, Threshold = 1.6 })
effect("SunRaysEffect", "MM_SunRays", { Intensity = 0.05, Spread = 0.55 })

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Net = require(Shared.Net)
Net.setup()

local Services = script.Parent:WaitForChild("Services")
local WorldBuilder = require(script.Parent:WaitForChild("World"):WaitForChild("WorldBuilder"))

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"Analytics",
	"DataService",
	"UpgradeService",
	"ScrapService",
	"MagnetService",
	"EconomyService",
	"ZoneService",
	"QuestService",
	"EventService",
	"ShopService",
	"PlayerService",
	"LeaderboardService",
}

local registry = { Remotes = remotes }
for _, name in ipairs(ORDER) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(ORDER) do
	registry[name].init(registry)
end

local world = WorldBuilder.build()
for _, name in ipairs({ "ScrapService", "EconomyService", "ZoneService", "PlayerService", "LeaderboardService" }) do
	registry[name].setWorld(world)
end

for _, name in ipairs({ "ScrapService", "MagnetService", "EconomyService", "ZoneService", "QuestService", "EventService", "ShopService", "UpgradeService", "PlayerService", "LeaderboardService" }) do
	registry[name].start()
end
registry.DataService.start() -- last: loading profiles calls into every other service

print(string.format("[MagnetMayhem] Server ready (%d world parts).", world.partCount))
