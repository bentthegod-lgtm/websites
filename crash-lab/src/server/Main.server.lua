--[[
	CRASH LAB - server bootstrap.
	Sets up lighting, remotes and the facilities, wires the services together, and drives
	the simulation from one Heartbeat connection (launch charges, crash runs, moving
	targets) so nothing runs its own per-object loop.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
local LightingPresets = require(Shared.LightingPresets)
-- The hub's look; each client switches to its facility's preset (LightingController).
LightingPresets.apply(Lighting, LightingPresets.IndustrialLab)
Net.setup()

local Services = script.Parent:WaitForChild("Services")
local FacilityBuilder = require(script.Parent:WaitForChild("World"):WaitForChild("FacilityBuilder"))

local remotes = {}
for _, name in ipairs(Net.Names) do
	remotes[name] = Net.event(name)
end

local ORDER = {
	"Analytics",
	"DataService",
	"UpgradeService",
	"PadService",
	"LaunchService",
	"CrashService",
	"CourseService",
	"ScoringService",
	"QuestService",
	"DuelService",
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

local world = FacilityBuilder.build()
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
	registry.LaunchService.step()
	registry.CrashService.step()
	registry.CourseService.step(dt)
end)

local counts = {}
for id, f in pairs(world.facilities) do
	table.insert(counts, string.format("%s %d", id, f.parts))
end
table.sort(counts)
print(string.format("[CrashLab] Server ready (%d parts: %s).", world.partCount, table.concat(counts, ", ")))
