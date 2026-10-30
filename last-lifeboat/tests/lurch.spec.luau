local L = require("./loader")
local GameConfig = L.shared("Config/GameConfig")
local LurchMath = L.shared("LurchMath")
local ShipGen = L.shared("ShipGen")
local V3, CF = L.roblox.Vector3, L.roblox.CFrame

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Lurch: " .. name, fn = fn })
end

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-4)
end

test("tilt grows with every lurch (small first, big later) up to the ship's max; sink too", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		local n = LurchMath.expectedLurches(def)
		assert(n >= 7 and n <= 16, key .. " lurches " .. n)
		local prevTilt, prevStep = 0, 0
		for k = 1, n do
			local t = LurchMath.tiltAt(def, k, n)
			local step = t - prevTilt
			assert(t > prevTilt, "tilt must grow")
			assert(step >= prevStep - 1e-6, "lurches should get bigger, not smaller")
			assert(step <= 4.5, key .. " one lurch tilts " .. step .. " degrees")
			prevTilt, prevStep = t, step
		end
		assert(near(prevTilt, def.MaxTilt), "final tilt")
		assert(def.MaxTilt >= 22 and def.MaxTilt <= 28, "max tilt out of 22-28")
		assert(near(LurchMath.sinkAt(def, n, n), def.MaxSink) and LurchMath.sinkAt(def, 1, n) < 2, "sink")
		assert(LurchMath.tiltAt(def, n + 5, n) == def.MaxTilt, "tilt clamps after N")
	end
end)

test("pivot delta: bow goes down and stern comes up relative to it; the pivot itself only sinks", function()
	local def = GameConfig.Ships.Aurora
	local base = CF.new(70, 0, -120)
	local p = LurchMath.pivot(base, 3, 10)
	assert(near(p.Position.Y, -3) and near(p.Position.X, 70) and near(p.Position.Z, -120), "pivot moved sideways")
	local bow0 = base:PointToWorldSpace(V3.new(0, 6, def.Length)).Y
	local bow1 = p:PointToWorldSpace(V3.new(0, 6, def.Length)).Y
	assert(bow1 < bow0 - def.Length * math.sin(math.rad(10)) + 1, "bow did not go down")
	assert(near(LurchMath.tiltOf(p, base), 10, 1e-3), "tilt read back " .. LurchMath.tiltOf(p, base))
	-- delta applied to a ship point equals the new pivot's mapping of that point
	local d = LurchMath.delta(base, p)
	local localPoint = V3.new(5, 20, 100)
	local viaDelta = d * base:PointToWorldSpace(localPoint)
	local direct = p:PointToWorldSpace(localPoint)
	assert((viaDelta - direct).Magnitude < 1e-3, "delta mismatch")
end)

test("client relocate: same place relative to the ship, upright, turned with the ship's yaw", function()
	local base = CF.new(70, 0, -80)
	local old = LurchMath.pivot(base, 1, 4)
	local new = LurchMath.pivot(base, 2, 7)
	local feet = old * CF.new(-6, 9, 60)
	local rootCF = CF.lookAt(feet.Position, feet.Position + V3.new(1, 0, 0))
	local after = LurchMath.relocate(old, new, rootCF)
	local relBefore = old:PointToObjectSpace(rootCF.Position)
	local relAfter = new:PointToObjectSpace(after.Position)
	assert((relBefore - relAfter).Magnitude < 1e-3, "character drifted relative to the ship")
	assert(near(after.UpVector.Y, 1, 1e-4), "character not upright")
	assert(near(after.LookVector.Y, 0, 1e-4), "facing not level")
	-- a yawed ship turns the character with it
	local yawBase = CF.new(0, 0, 0) * CF.Angles(0, math.rad(30), 0)
	local yawed = LurchMath.relocate(CF.new(), yawBase, CF.lookAt(V3.new(0, 5, 10), V3.new(0, 5, 0)))
	local before = V3.new(0, 0, -1)
	local angle = math.deg(math.acos(math.clamp(yawed.LookVector:Dot(before), -1, 1)))
	assert(near(angle, 30, 1e-2), "yaw not applied: " .. angle)
	-- lift
	local lifted = LurchMath.relocate(old, new, rootCF, 0.5)
	assert(near(lifted.Position.Y - after.Position.Y, 0.5), "lift")
end)

test("waterline: dry before the first lurch; lower decks and the bow flood first; the lifeboat stays dry", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		local plan = ShipGen.plan(key, 1)
		local base = CF.new(GameConfig.World.ShipX, 0, -def.Length / 2)
		-- round start: everything above water
		for _, deck in ipairs(plan.decks) do
			assert(base:PointToWorldSpace(V3.new(0, deck.y, def.Length)).Y > 0, "a deck starts underwater")
		end
		local n = LurchMath.expectedLurches(def)
		local final = LurchMath.pivotFor(def, base, n, n)
		local lowBow = LurchMath.worldY(final, 0, plan.decks[1].y, def.Length - 8)
		assert(lowBow < -20, key .. " the lowest bow never floods: " .. lowBow)
		local boat = LurchMath.worldY(final, plan.lifeboat.x, plan.lifeboat.y, plan.lifeboat.z)
		assert(boat > 6, key .. " the lifeboat goes under: " .. boat)
		-- waterline maths agrees with the transform
		local t, s = LurchMath.tiltAt(def, n // 2, n), LurchMath.sinkAt(def, n // 2, n)
		local h = plan.decks[2].y
		local zw = LurchMath.waterlineZ(h, t, s)
		local mid = LurchMath.pivot(base, s, t)
		if zw > 0 and zw < def.Length then
			assert(LurchMath.worldY(mid, 0, h, zw - 2) > 0 and LurchMath.worldY(mid, 0, h, zw + 2) < 0, "waterline off")
		end
		-- the deepest bow point stays inside the ocean trench
		local keelBow = LurchMath.worldY(LurchMath.pivot(base, def.MaxSink, def.MaxTilt + GameConfig.Sinking.FinalPlungeTilt), 0, GameConfig.Ship.Keel, def.Length)
		assert(keelBow > -GameConfig.World.TrenchDepth, key .. " bow goes below the trench: " .. keelBow)
	end
	assert(LurchMath.waterlineZ(10, 0, 0) == math.huge)
end)

test("slide: none on a gentle tilt, downhill toward the bow on a steep one, Grip reduces it", function()
	local base = CF.new()
	local steep = LurchMath.pivot(base, 0, 20)
	assert(LurchMath.slide(LurchMath.pivot(base, 0, 8), 8, 25, 1).Magnitude == 0, "slides on a gentle tilt")
	local s = LurchMath.slide(steep, 20, 25, 1)
	assert(s.Magnitude > 0 and s.Z > 0 and near(s.Y, 0), "slide not downhill toward the bow")
	local gripped = LurchMath.slide(steep, 20, 25, 0.3)
	assert(near(gripped.Magnitude, s.Magnitude * 0.3, 1e-3), "grip")
	assert(s.Magnitude <= GameConfig.Sinking.SlideAccel + 1e-6, "slide too strong")
end)

test("onShip: aboard inside the hull box, not on the dock", function()
	local def = GameConfig.Ships.Gull
	local base = CF.new(GameConfig.World.ShipX, 0, -def.Length / 2)
	assert(LurchMath.onShip(base, base:PointToWorldSpace(V3.new(0, 10, 50)), def.Length, def.Beam, 40))
	assert(not LurchMath.onShip(base, V3.new(-36, 6, 0), def.Length, def.Beam, 40), "dock counts as aboard")
end)

return cases
