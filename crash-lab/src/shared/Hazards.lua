--[[
	Hazards - pure maths for the facility hazards, shared by the server and the tests.

	Wind (High-Altitude Launch Facility):
	  gust(seed, index, wind)       -> Vector3 change in velocity for gust number `index`
	                                   of a run. Deterministic per run seed; |gust| <= MaxGust.
	  capGust(total, gust, max)     -> the gust shortened so |total + gust| <= max: a run's
	                                   accumulated wind can never exceed MaxTotal.
	  runSeed(userId, launches)     -> a run's seed (same inputs, same gusts).

	Gravity (Experimental Gravity Lab):
	  volumeAt(volumes, p, flipOff) -> the volume containing local position p (or nil);
	                                   flip volumes are skipped while flipOff is true.
	  liftForce(mass, gravity, s)   -> the upward force that makes a part of `mass` feel
	                                   s * gravity (s = 1 normal, 0.3 low-g, -0.5 flipped).
]]

local Rng = require(script.Parent.Rng)

local Hazards = {}

function Hazards.runSeed(userId, launches)
	return ((tonumber(userId) or 0) * 7919 + (tonumber(launches) or 0) * 104729 + 13) % 2147483646 + 1
end

function Hazards.gust(seed, index, wind)
	local rng = Rng.new(seed * 31 + index * 977 + 7)
	local max = wind.MaxGust
	-- Mostly sideways (across the canyon), a little up / down and along the course.
	local v = Vector3.new(rng:NextNumber(-1, 1) * max, rng:NextNumber(-1, 1) * max * (wind.Vertical or 0.25), rng:NextNumber(-1, 1) * max * 0.3)
	if v.Magnitude > max then
		v = v.Unit * max
	end
	return v
end

function Hazards.capGust(total, gust, maxTotal)
	local after = total + gust
	if after.Magnitude <= maxTotal then
		return gust
	end
	return after.Unit * maxTotal - total
end

local function inside(volume, p)
	local d = p - volume.Center
	local h = volume.Size / 2
	return math.abs(d.X) <= h.X and math.abs(d.Y) <= h.Y and math.abs(d.Z) <= h.Z
end
Hazards.inside = inside

function Hazards.volumeAt(volumes, p, flipOff)
	for _, volume in ipairs(volumes or {}) do
		if not (volume.Flip and flipOff) and inside(volume, p) then
			return volume
		end
	end
	return nil
end

function Hazards.liftForce(mass, gravity, scale)
	return mass * gravity * (1 - scale)
end

return Hazards
