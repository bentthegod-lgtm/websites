--[[
	VAULT - server bootstrap.
	Applies the starting lighting, creates the remotes, builds the vault (seven depths and
	the shared elevator shaft), wires the services together, and drives the loot / magnet /
	deposit-zone work from one Heartbeat connection (no per-object loops).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)
local LightingPresets = require(Shared.LightingPresets)

-- The deepest pool bottom sits ~585 studs down: keep characters there alive.
workspace.FallenPartsDestroyHeight = -3000
LightingPresets.apply(Lighting, LightingPresets.CashVault)
Net.setup()

local Services = script.Parent:WaitForChild("Services")
local VaultBuilder = require(script.Parent:WaitForChild("World"):WaitForChild("VaultBuilder"))

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"Analytics",
	"DataService",
	"PlayerService",
	"ShopService",
	"UpgradeService",
	"QuestService",
	"LootService",
	"DepositService",
	"ElevatorService",
	"LeaderboardService",
}

local registry = { Remotes = remotes }
for _, name in ipairs(ORDER) do
	registry[name] = require(Services[name])
end
for _, name in ipairs(ORDER) do
	registry[name].init(registry)
end

local world = VaultBuilder.build()
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
	registry.LootService.step(dt)
	registry.DepositService.step(dt)
	registry.PlayerService.step(dt)
end)

print(string.format("[Vault] Server ready: %d depths, %d world parts.", #world.depths, world.partCount))
