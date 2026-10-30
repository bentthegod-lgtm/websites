--[[
	LurchMath - the sinking maths (pure, unit-tested; used by the server and the client).

	A ship's pivot is its stern at the waterline. Lurch k of N (N = lurches expected in a
	round) puts the pivot at
	    base * CFrame.new(0, -sink_k, 0) * CFrame.Angles(rad(tilt_k), 0, 0)
	A positive rotation about local X lowers +Z (the bow): bow down, stern up.
	  tilt_k = MaxTilt * (k / N) ^ TiltCurve      (small lurches first, big ones later)
	  sink_k = MaxSink * k / N
	Terrain water is static at Y = 0, so every part of a deck that ends up below 0 floods.

	Clients move their OWN character by the same delta on a lurch (relocate): the position
	follows the ship, the character stays upright and turns with the ship's yaw.
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local LurchMath = {}

local Sinking = GameConfig.Sinking

function LurchMath.expectedLurches(def)
	local mean = (def.LurchEvery[1] + def.LurchEvery[2]) / 2
	return math.max(1, math.floor(def.RoundTime / mean))
end

function LurchMath.tiltAt(def, k, n)
	n = n or LurchMath.expectedLurches(def)
	local f = math.clamp(k / n, 0, 1)
	return def.MaxTilt * f ^ Sinking.TiltCurve
end

function LurchMath.sinkAt(def, k, n)
	n = n or LurchMath.expectedLurches(def)
	return def.MaxSink * math.clamp(k / n, 0, 1)
end

-- The pivot for a given sink (studs) and tilt (degrees) from the starting pivot `base`.
function LurchMath.pivot(base, sink, tiltDeg)
	return base * CFrame.new(0, -sink, 0) * CFrame.Angles(math.rad(tiltDeg), 0, 0)
end

function LurchMath.pivotFor(def, base, k, n)
	return LurchMath.pivot(base, LurchMath.sinkAt(def, k, n), LurchMath.tiltAt(def, k, n))
end

-- World transform that carries anything riding on the ship from oldPivot to newPivot.
function LurchMath.delta(oldPivot, newPivot)
	return newPivot * oldPivot:Inverse()
end

-- Where a character standing at `cf` (on the ship) should be after the lurch: the same
-- place relative to the ship, kept upright, its facing turned with the ship's yaw.
function LurchMath.relocate(oldPivot, newPivot, cf, lift)
	local moved = LurchMath.delta(oldPivot, newPivot) * cf
	local pos = moved.Position + Vector3.new(0, lift or 0, 0)
	local look = moved.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		local before = cf.LookVector
		flat = Vector3.new(before.X, 0, before.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
	end
	return CFrame.lookAt(pos, pos + flat.Unit)
end

-- Bow-down tilt in degrees read back from a pivot (its local +Z pointing down).
function LurchMath.tiltOf(pivot, base)
	local forward = pivot:VectorToWorldSpace(Vector3.zAxis)
	if base then
		forward = base:VectorToObjectSpace(forward)
	end
	return math.deg(math.asin(math.clamp(-forward.Y, -1, 1)))
end

-- Ship-local Z beyond which a deck at local height h is underwater (math.huge = dry).
function LurchMath.waterlineZ(h, tiltDeg, sink)
	local t = math.rad(tiltDeg)
	local s = math.sin(t)
	local value = h * math.cos(t) - sink
	if s < 1e-6 then
		return if value > 0 then math.huge else -math.huge
	end
	return value / s
end

-- World height of a ship-local point under a pivot.
function LurchMath.worldY(pivot, x, y, z)
	return pivot:PointToWorldSpace(Vector3.new(x, y, z)).Y
end

-- Downhill acceleration (world vector, studs/s^2) for a character on a tilted deck.
-- Zero below SlideTilt; scales up to SlideAccel at the ship's max tilt; Grip multiplies it.
function LurchMath.slide(pivot, tiltDeg, maxTilt, gripMult)
	if tiltDeg <= Sinking.SlideTilt then
		return Vector3.zero
	end
	local bow = pivot:VectorToWorldSpace(Vector3.zAxis)
	local flat = Vector3.new(bow.X, 0, bow.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.zero
	end
	local f = math.clamp((tiltDeg - Sinking.SlideTilt) / math.max(1, maxTilt - Sinking.SlideTilt), 0, 1)
	return flat.Unit * Sinking.SlideAccel * (0.35 + 0.65 * f) * math.clamp(gripMult or 1, 0, 1)
end

-- Is a world point inside the ship's box (used to decide who rides a lurch)?
function LurchMath.onShip(pivot, position, length, beam, height)
	local p = pivot:PointToObjectSpace(position)
	return p.Z >= -6 and p.Z <= length + 6 and math.abs(p.X) <= beam / 2 + 4 and p.Y >= -8 and p.Y <= height + 20
end

-- Seconds until the next lurch, with valve delays already added by the caller.
function LurchMath.interval(def, rng)
	return rng:NextNumber(def.LurchEvery[1], def.LurchEvery[2])
end

return LurchMath
