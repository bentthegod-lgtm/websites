--[[
	WorldQuery - the in-game groundQuery for KartPhysics: workspace raycasts against the
	built track.
	  ground(probe)       one ray straight down from `probe` against Track/Ground (roads,
	                      shoulders, shortcuts, pads, the grass floor). The part's
	                      Surface / Course attributes say what it is.
	  walls(pos, radius)  8 horizontal rays (radius long) against Track/Walls; returns the
	                      deepest contact's flattened normal and depth.
	KartPhysics samples the ground under its 4 wheel points every step. If the track isn't
	there (still streaming in), the analytic TrackQuery is used instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local KartStats = require(Shared.Config.KartStats)

local WorldQuery = {}
WorldQuery.__index = WorldQuery

local DIRS = {}
for i = 0, 7 do
	local a = i / 8 * math.pi * 2
	table.insert(DIRS, Vector3.new(math.cos(a), 0, math.sin(a)))
end

function WorldQuery.new(trackFolder)
	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = { trackFolder:WaitForChild("Ground") }
	local walls = RaycastParams.new()
	walls.FilterType = Enum.RaycastFilterType.Include
	walls.FilterDescendantsInstances = { trackFolder:WaitForChild("Walls") }
	return setmetatable({ groundParams = ground, wallParams = walls, cache = {} }, WorldQuery)
end

function WorldQuery:info(part)
	local c = self.cache[part]
	if not c then
		c = { surface = part:GetAttribute("Surface") or "Road", course = part:GetAttribute("Course") or "main" }
		self.cache[part] = c
	end
	return c
end

function WorldQuery:ground(probe)
	local result = workspace:Raycast(probe, Vector3.new(0, -KartStats.MaxProbe, 0), self.groundParams)
	if not result then
		return nil
	end
	local info = self:info(result.Instance)
	return result.Position.Y, result.Normal, info.surface, info.course
end

function WorldQuery:walls(pos, radius)
	local bestN, bestD = nil, 0
	for _, dir in ipairs(DIRS) do
		local result = workspace:Raycast(pos, dir * radius, self.wallParams)
		if result then
			local depth = radius - result.Distance
			if depth > bestD then
				local n = Vector3.new(result.Normal.X, 0, result.Normal.Z)
				if n.Magnitude > 0.1 then
					bestN, bestD = n.Unit, depth
				end
			end
		end
	end
	return bestN, bestD
end

return WorldQuery
