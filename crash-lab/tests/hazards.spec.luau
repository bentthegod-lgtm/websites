local L = require("./loader")
local Hazards = L.shared("Hazards")
local CourseConfig = L.shared("Config/CourseConfig")
local Vector3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Hazards: " .. name, fn = fn })
end

local WIND = CourseConfig.Courses.HighAltitude.Wind

test("wind gusts are deterministic per run seed and never stronger than MaxGust", function()
	local seed = Hazards.runSeed(1234, 17)
	assert(seed == Hazards.runSeed(1234, 17) and seed ~= Hazards.runSeed(1234, 18), "seed not per run")
	local differs = false
	for i = 1, 40 do
		local a, b = Hazards.gust(seed, i, WIND), Hazards.gust(seed, i, WIND)
		assert((a - b).Magnitude == 0, "gust " .. i .. " not deterministic")
		assert(a.Magnitude <= WIND.MaxGust + 1e-6, "gust " .. i .. " too strong")
		if (a - Hazards.gust(seed + 1, i, WIND)).Magnitude > 1e-3 then
			differs = true
		end
	end
	assert(differs, "different seeds give the same wind")
end)

test("the run's accumulated wind is capped at MaxTotal", function()
	local total = Vector3.new(0, 0, 0)
	-- Worst case: every gust pushes the same way.
	for _ = 1, 30 do
		local gust = Hazards.capGust(total, Vector3.new(WIND.MaxGust, 0, 0), WIND.MaxTotal)
		total += gust
		assert(total.Magnitude <= WIND.MaxTotal + 1e-3, "total over the cap")
	end
	assert(math.abs(total.Magnitude - WIND.MaxTotal) < 1e-3, "cap never reached")
	-- A gust back the other way is never shortened.
	local back = Hazards.capGust(total, Vector3.new(-WIND.MaxGust, 0, 0), WIND.MaxTotal)
	assert((back - Vector3.new(-WIND.MaxGust, 0, 0)).Magnitude < 1e-6)
end)

test("gravity volumes: lookup, flip switch-off and the lift force", function()
	local volumes = CourseConfig.Courses.GravityLab.Gravity.Volumes
	local lowG, flip = volumes[1], volumes[2]
	assert(Hazards.volumeAt(volumes, lowG.Center) == lowG)
	assert(Hazards.volumeAt(volumes, lowG.Center + Vector3.new(0, lowG.Size.Y, 0)) == nil, "outside counted as inside")
	assert(Hazards.volumeAt(volumes, flip.Center) == flip and flip.Scale < 0)
	assert(Hazards.volumeAt(volumes, flip.Center, true) == nil, "flip column not switched off")
	assert(Hazards.volumeAt(volumes, Vector3.new(0, 5, 0)) == nil, "launch deck inside a field")
	-- Net force = weight - lift = mass * g * scale.
	local mass, g = 2.5, 196.2
	for _, scale in ipairs({ 1, 0.3, 0.2, 0, -0.5 }) do
		local lift = Hazards.liftForce(mass, g, scale)
		assert(math.abs((mass * g - lift) - mass * g * scale) < 1e-9, "wrong lift at scale " .. scale)
	end
	assert(Hazards.liftForce(mass, g, 1) == 0, "normal gravity should need no force")
end)

return cases
