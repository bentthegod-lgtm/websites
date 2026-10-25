--[[
	PHONES AWAY! - server bootstrap.
	Sets up lighting, remotes and the school, then wires the services together.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Bright, sunny school morning.
Lighting.ClockTime = 10.2
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(150, 145, 135)
Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 150)
Lighting.EnvironmentDiffuseScale = 0.5
Lighting.EnvironmentSpecularScale = 0.3
local function lightingEffect(className, name, props)
	local effect = Lighting:FindFirstChild(name) or Instance.new(className)
	effect.Name = name
	for k, v in pairs(props) do
		effect[k] = v
	end
	effect.Parent = Lighting
	return effect
end
lightingEffect("ColorCorrectionEffect", "PA_Grade", { TintColor = Color3.fromRGB(255, 250, 242), Saturation = 0.15, Contrast = 0.06, Brightness = 0.02 })
lightingEffect("BloomEffect", "PA_Bloom", { Intensity = 0.35, Size = 20, Threshold = 1.5 })

Players.CharacterAutoLoads = true

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
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
	"CosmeticService",
	"PhoneService",
	"TestService",
	"TeacherService",
	"ClassmateService",
	"RewardService",
	"RoundService",
	"LeaderboardService",
}

local world = require(Services.ClassroomBuilder).build()
local registry = { Remotes = remotes, World = world }
for _, name in ipairs(ORDER) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(ORDER) do
	registry[name].init(registry)
end

registry.TeacherService.setup()
registry.LeaderboardService.setBoard(world.board)
world.shopPrompt.Triggered:Connect(function(player)
	remotes.Effect:FireClient(player, "OpenShop", {})
end)

registry.ShopService.start()
registry.CosmeticService.start()
registry.PhoneService.start()
registry.TestService.start()
registry.ClassmateService.start()
registry.RewardService.start()
registry.RoundService.start()
registry.LeaderboardService.start()
registry.DataService.start() -- last: loading profiles calls into every other service

print("[PhonesAway] Server ready. Phones away, class!")
