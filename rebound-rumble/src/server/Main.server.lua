--[[
	REBOUND RUMBLE - server bootstrap.
	Creates remotes, builds the lobby, wires the services together and starts the loops.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local Net = require(Shared.Net)
Net.setup()

-- Baseline post-processing (the client tints it per arena).
local function lightingEffect(className, name, props)
	local effect = Lighting:FindFirstChild(name) or Instance.new(className)
	effect.Name = name
	for k, v in pairs(props) do
		effect[k] = v
	end
	effect.Parent = Lighting
end
lightingEffect("BloomEffect", "RR_Bloom", { Intensity = 0.8, Size = 28, Threshold = 1.2 })
lightingEffect("ColorCorrectionEffect", "RR_Grade", { Saturation = 0.15, Contrast = 0.08 })
lightingEffect("Atmosphere", "RR_Atmosphere", { Density = 0.28, Haze = 0.6, Glare = 0.2 })

local Services = script.Parent:WaitForChild("Services")

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local order = {
	"DataService",
	"ShopService",
	"LeaderboardService",
	"RewardService",
	"CosmeticService",
	"AbilityService",
	"BotService",
	"BallService",
	"MatchService",
}

local registry = { Remotes = remotes }
for _, name in ipairs(order) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(order) do
	registry[name].init(registry)
end

local lobby = require(Services.LobbyBuilder).build(workspace)
registry.MatchService.setLobby(lobby)
registry.LeaderboardService.setBoard(lobby.board)

for _, name in ipairs(order) do
	if registry[name].start then
		registry[name].start()
	end
end

RunService.Heartbeat:Connect(function(dt)
	registry.BallService.step(dt)
	registry.BotService.step(dt)
end)

print("[ReboundRumble] Server ready.")
