--[[
	Snatch a Blobby - server bootstrap.
	Lighting, remotes, world, then the services in dependency order.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Bright, saturated cartoon daylight.
Lighting.ClockTime = 14.2
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(120, 116, 140)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 146, 170)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
local function lightingEffect(className, name, props)
	local effect = Lighting:FindFirstChild(name) or Instance.new(className)
	effect.Name = name
	for k, v in pairs(props) do
		effect[k] = v
	end
	effect.Parent = Lighting
end
lightingEffect("Atmosphere", "ST_Atmosphere", {
	Density = 0.28,
	Offset = 0.1,
	Color = Color3.fromRGB(200, 220, 255),
	Decay = Color3.fromRGB(150, 170, 220),
	Glare = 0.2,
	Haze = 0.6,
})
lightingEffect("ColorCorrectionEffect", "ST_Grade", { Saturation = 0.18, Contrast = 0.08, Brightness = 0.02, TintColor = Color3.fromRGB(255, 250, 245) })
lightingEffect("BloomEffect", "ST_Bloom", { Intensity = 0.6, Size = 24, Threshold = 1.4 })
lightingEffect("SunRaysEffect", "ST_SunRays", { Intensity = 0.06, Spread = 0.6 })

pcall(function()
	Players.RespawnTime = 3
end)

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local Net = require(Shared.Net)
Net.setup()

local Services = script.Parent:WaitForChild("Services")

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local registry = { Remotes = remotes }
local order = {
	"DataService",
	"FeedService",
	"PlayerService",
	"ShopService",
	"PlotService",
	"BlobbyService",
	"StealService",
	"CarpetService",
	"EventService",
	"RewardService",
	"LeaderboardService",
}
for _, name in ipairs(order) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(order) do
	registry[name].init(registry)
end

local WorldBuilder = require(Services.WorldBuilder)
local world = WorldBuilder.build()
registry.World = world
registry.PlotService.setWorld(world)
registry.BlobbyService.setWorld(world)
registry.CarpetService.setWorld(world)
registry.EventService.setWorld(world)
registry.LeaderboardService.setWorld(world)

-- Start order matters: ProfileLoaded handlers run in this order (plot -> passes ->
-- Blobbies -> rewards/offline earnings), Releasing handlers too. DataService starts last
-- so every handler is connected before the first profile loads.
for _, name in ipairs({
	"FeedService",
	"PlayerService",
	"ShopService",
	"BlobbyService",
	"RewardService",
	"StealService",
	"PlotService",
	"EventService",
	"CarpetService",
	"LeaderboardService",
	"DataService",
}) do
	registry[name].start()
end

print("[SnatchTycoon] Server ready.")
