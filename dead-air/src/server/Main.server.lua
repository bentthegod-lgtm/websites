--[[
	DEAD AIR - server bootstrap.
	Creates remotes, wires the services together and starts the round loop.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

-- Underground lighting: no sky, almost no ambient light, faint yellow haze.
Lighting.Ambient = Color3.fromRGB(12, 11, 8)
Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Lighting.Brightness = 0
Lighting.ClockTime = 0
Lighting.FogColor = Color3.fromRGB(20, 18, 12)
Lighting.FogStart = 40
Lighting.FogEnd = 260
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0.15
local function lightingEffect(className, name, props)
	local effect = Lighting:FindFirstChild(name) or Instance.new(className)
	effect.Name = name
	for k, v in pairs(props) do
		effect[k] = v
	end
	effect.Parent = Lighting
end
lightingEffect("Atmosphere", "DA_Atmosphere", {
	Density = 0.32,
	Offset = 0,
	Color = Color3.fromRGB(196, 182, 140),
	Decay = Color3.fromRGB(60, 54, 40),
	Glare = 0,
	Haze = 1.2,
})
lightingEffect("ColorCorrectionEffect", "DA_Grade", {
	TintColor = Color3.fromRGB(255, 246, 222),
	Saturation = -0.25,
	Contrast = 0.12,
	Brightness = 0,
})
lightingEffect("BloomEffect", "DA_Bloom", { Intensity = 0.6, Size = 22, Threshold = 1.6 })

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Net = require(Shared.Net)
Net.setup()

local Services = script.Parent:WaitForChild("Services")

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local registry = {
	Remotes = remotes,
	SoundConfig = require(Shared.Config.SoundConfig),
	DataService = require(Services.DataService),
	PlayerService = require(Services.PlayerService),
	NoiseService = require(Services.NoiseService),
	DoorService = require(Services.DoorService),
	HidingService = require(Services.HidingService),
	ItemService = require(Services.ItemService),
	ObjectiveService = require(Services.ObjectiveService),
	MonsterService = require(Services.MonsterService),
	HorrorEventService = require(Services.HorrorEventService),
	RoundService = require(Services.RoundService),
}

for _, name in ipairs({
	"DataService",
	"PlayerService",
	"NoiseService",
	"DoorService",
	"HidingService",
	"ItemService",
	"ObjectiveService",
	"MonsterService",
	"HorrorEventService",
	"RoundService",
}) do
	registry[name].init(registry)
end

registry.DataService.start()
registry.PlayerService.start()
registry.ItemService.start()
registry.RoundService.start()

print("[DeadAir] Server ready.")
