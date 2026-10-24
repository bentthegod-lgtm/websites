--[[
	SPROUT VALLEY - server bootstrap.
	Sets up lighting, remotes and the village, then wires the services together.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sunny cozy day (WeatherController tweens this on the client during events).
Lighting.ClockTime = 14.5
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(140, 135, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 140)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.4
Lighting.FogColor = Color3.fromRGB(200, 225, 255)
Lighting.FogStart = 200
Lighting.FogEnd = 1200
local function lightingEffect(className, name, props)
	local effect = Lighting:FindFirstChild(name) or Instance.new(className)
	effect.Name = name
	for k, v in pairs(props) do
		effect[k] = v
	end
	effect.Parent = Lighting
	return effect
end
lightingEffect("Atmosphere", "SV_Atmosphere", { Density = 0.22, Offset = 0.1, Color = Color3.fromRGB(200, 225, 255), Decay = Color3.fromRGB(150, 180, 220), Glare = 0.2, Haze = 0.6 })
lightingEffect("ColorCorrectionEffect", "SV_Grade", { TintColor = Color3.fromRGB(255, 250, 240), Saturation = 0.12, Contrast = 0.05, Brightness = 0.02 })
lightingEffect("BloomEffect", "SV_Bloom", { Intensity = 0.4, Size = 24, Threshold = 1.4 })
lightingEffect("SunRaysEffect", "SV_SunRays", { Intensity = 0.06, Spread = 0.6 })

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)
Net.setup()

local Services = script.Parent:WaitForChild("Services")

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"DataService",
	"ShopService",
	"PlotService",
	"StockService",
	"SellService",
	"WeatherService",
	"RewardsService",
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

local village = require(Services.VillageBuilder).build()
registry.PlotService.setVillage(village)
registry.StockService.setStalls(village.stalls)
registry.PlayerService.setVillage(village)
registry.LeaderboardService.setBoard(village.board)

registry.ShopService.start()
registry.PlotService.start()
registry.StockService.start()
registry.SellService.start()
registry.WeatherService.run()
registry.RewardsService.start()
registry.PlayerService.start()
registry.LeaderboardService.start()
registry.DataService.start() -- last: loading profiles calls into every other service

print("[SproutValley] Server ready.")
