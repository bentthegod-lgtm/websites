--[[
	LightingController - each facility has its own look (LightingPresets): sunny mountain
	air at High-Altitude, dusty orange floodlight at the Destruction Zone, dark neon at the
	Gravity Lab. Lighting is a single global service, so the CLIENT applies the preset of
	the facility its character is standing in; the change is local to this player and
	never affects anyone else. Checked twice a second (and right after a travel).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local LightingPresets = require(Shared.LightingPresets)

local ClientState = require(script.Parent.ClientState)

local LightingController = {}

LightingController.current = nil

-- Applies the preset for the facility at `position` if it differs from the current one.
-- Returns the facility id.
function LightingController.update(position)
	local course = CourseConfig.facilityAt(position)
	if course.Id ~= LightingController.current then
		LightingController.current = course.Id
		LightingPresets.apply(Lighting, LightingPresets[course.Id] or LightingPresets.IndustrialLab)
		ClientState.FacilityChanged:Fire(course.Id)
	end
	return course.Id
end

function LightingController.init()
	task.spawn(function()
		while true do
			local root = ClientState.root()
			if root then
				LightingController.update(root.Position)
			end
			task.wait(0.5)
		end
	end)
end

return LightingController
