--[[
	World - builds Chaos City for the server.

	  World.new(mapDef, parent) builds the LOBBY immediately (small, so players can spawn),
	  compiles the map data and the analytic TrackQuery, and queues the track + city as a
	  BuildJob. world:step(n) builds n more parts (Main.server: PartsPerStep per Heartbeat);
	  world.ready turns true when everything exists. Races can't start before that.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local MapData = require(Shared.MapData)
local TrackQuery = require(Shared.TrackQuery)
local BuildJob = require(script.Parent.BuildJob)
local TrackBuilder = require(script.Parent.TrackBuilder)
local CityBuilder = require(script.Parent.CityBuilder)
local LobbyBuilder = require(script.Parent.LobbyBuilder)

local World = {}
World.__index = World

World.PartsPerStep = 350

function World.new(mapDef, parent)
	local t0 = os.clock()
	local root = Instance.new("Folder")
	root.Name = "ChaosKartsWorld"
	root.Parent = parent
	local data = MapData.compile(mapDef)
	local compileTime = os.clock() - t0
	local t1 = os.clock()
	local lobby = LobbyBuilder.build(root, data)
	local lobbyTime = os.clock() - t1
	local t2 = os.clock()
	local job = BuildJob.new(root)
	local track = TrackBuilder.plan(data, job)
	local city = CityBuilder.plan(data, job)
	local planTime = os.clock() - t2
	local self = setmetatable({
		root = root,
		data = data,
		query = TrackQuery.new(data),
		lobby = lobby,
		job = job,
		ready = false,
		plan = { track = track.parts, city = city.parts, total = job:count() },
		timings = { compile = compileTime, lobby = lobbyTime, plan = planTime, build = 0, frames = 0, worst = 0 },
		plaza = city.plaza,
	}, World)
	return self
end

function World:step(n)
	if self.ready then
		return true
	end
	local t = os.clock()
	local done = self.job:step(n or World.PartsPerStep)
	local dt = os.clock() - t
	self.timings.build += dt
	self.timings.frames += 1
	self.timings.worst = math.max(self.timings.worst, dt)
	if done then
		self.ready = true
		self.startLights = self.job.tagged.StartLights or {}
		self.trackFolder = self.root:FindFirstChild("Track")
	end
	return done
end

function World:partCount()
	local n = 0
	for _, d in ipairs(self.root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- The city at dusk: low warm sun, purple-orange sky, neon everywhere, bloom.
function World.lighting()
	Lighting.ClockTime = 17.6
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(110, 96, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 130, 160)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 196, 150)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.15
		atmosphere.Color = Color3.fromRGB(240, 180, 170)
		atmosphere.Decay = Color3.fromRGB(120, 90, 150)
		atmosphere.Glare = 0.35
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.8
		bloom.Size = 30
		bloom.Threshold = 1.3
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Saturation = 0.18
		cc.Contrast = 0.08
		cc.Parent = Lighting
	end
end

return World
