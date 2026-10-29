local L = require("./loader")
local Motion = L.shared("Motion")
local CourseConfig = L.shared("Config/CourseConfig")
local Vector3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Motion: " .. name, fn = fn })
end

test("moving-target velocity is the derivative of its position (finite difference)", function()
	local moving = 0
	for _, def in ipairs(CourseConfig.Targets) do
		if def.Motion then
			moving += 1
			for _, t in ipairs({ 0, 0.4, 1.3, 2.75, 5.1, 7.9 }) do
				local h = 1e-2 -- Vector3 is float32: a tiny h only measures rounding
				local numeric = (Motion.position(def, t + h) - Motion.position(def, t - h)) / (2 * h)
				local v = Motion.velocity(def, t)
				assert((numeric - v).Magnitude < 0.02, string.format("%s at t=%.2f: %s vs %s", def.Id, t, tostring(numeric), tostring(v)))
			end
			-- Peak speed is A * 2pi / Period at the centre of the swing.
			local peak = Motion.velocity(def, 0).X
			assert(math.abs(peak - def.Motion.Amplitude * 2 * math.pi / def.Motion.Period) < 1e-3)
		else
			assert(Motion.velocity(def, 3) == Vector3.new(0, 0, 0) and Motion.position(def, 3) == def.Position, def.Id .. " should be still")
		end
	end
	assert(moving >= 2, "expected the swinging and sliding targets")
end)

return cases
