--[[
	CRASH LAB - server bootstrap.
	Sets up lighting, remotes and the facility, wires the services together, and drives
	the simulation from one Heartbeat connection (launch charges, crash runs, moving
	targets) so nothing runs its own per-object loop.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Bright, clean industrial daylight: warm sun, cool shadows, a little atmospheric depth.
Lighting.ClockTime = 14.2
Lighting.GeographicLatitude = 30
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(120, 122, 132)
Lighting.OutdoorAmbient = Color3.fromRGB(140, 144, 156)
Lighting.EnvironmentDiffuseScale = 0.5
Lighting.EnvironmentSpecularScale = 0.55
Lighting.ShadowSoftness = 0.2
local function effect(className, name, props)
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = Lighting
	return e
end
effect("Atmosphere", "CL_Atmosphere", { Density = 0.22, Offset = 0.1, Color = Color3.fromRGB(200, 210, 225), Decay = Color3.fromRGB(120, 130, 150), Glare = 0.2, Haze = 0.8 })
effect("ColorCorrectionEffect", "CL_Grade", { TintColor = Color3.fromRGB(255, 250, 242), Saturation = 0.05, Contrast = 0.07, Brightness = 0.02 })
effect("BloomEffect", "CL_Bloom", { Intensity = 0.3, Size = 20, Threshold = 1.7 })
effect("SunRaysEffect", "CL_SunRays", { Intensity = 0.04, Spread = 0.5 })

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
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

print(string.format("[CrashLab] Server ready (%d facility parts).", world.partCount))
