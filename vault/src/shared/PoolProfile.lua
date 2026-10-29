--[[
	PoolProfile - the shape of every depth's treasure pool (shared: the server builds it,
	the fill grid and the unit tests read it). Coordinates are relative to the depth's rim
	(y0) with x across the pool and z away from the elevator.
]]

local PoolProfile = {}

PoolProfile.Pool = { x0 = -52, x1 = 52, z0 = -46, z1 = 50, depth = 42 }
local P = PoolProfile.Pool

-- The walkable profile along z (heights relative to the rim). Steps rise 1.0 over 1.78;
-- ramps are about 31 degrees; the deep end is flat in front of the vault door.
PoolProfile.Profile = {
	{ kind = "stairs", z0 = -46, z1 = -30, h0 = 0, h1 = -9, steps = 9 },
	{ kind = "flat", z0 = -30, z1 = -26, h0 = -9, h1 = -9 },
	{ kind = "ramp", z0 = -26, z1 = -8, h0 = -9, h1 = -20 },
	{ kind = "flat", z0 = -8, z1 = -4, h0 = -20, h1 = -20 },
	{ kind = "ramp", z0 = -4, z1 = 14, h0 = -20, h1 = -31 },
	{ kind = "flat", z0 = 14, z1 = 18, h0 = -31, h1 = -31 },
	{ kind = "ramp", z0 = 18, z1 = 36, h0 = -31, h1 = -42 },
	{ kind = "flat", z0 = 36, z1 = 50, h0 = -42, h1 = -42 },
}

-- Height of the treasure surface at z (relative to the rim) and its slope angle.
function PoolProfile.surface(z)
	for _, seg in ipairs(PoolProfile.Profile) do
		if z >= seg.z0 and z <= seg.z1 then
			if seg.kind == "stairs" then
				local run = (seg.z1 - seg.z0) / seg.steps
				local i = math.clamp(math.floor((z - seg.z0) / run) + 1, 1, seg.steps)
				return seg.h0 - i * (seg.h0 - seg.h1) / seg.steps, 0
			elseif seg.kind == "ramp" then
				local t = (z - seg.z0) / (seg.z1 - seg.z0)
				return seg.h0 + (seg.h1 - seg.h0) * t, math.atan2(seg.h0 - seg.h1, seg.z1 - seg.z0)
			end
			return seg.h0, 0
		end
	end
	return if z < P.z0 then 0 else -P.depth, 0
end

-- Is z on a stair step close to its edge (where a fill item would overhang the riser)?
function PoolProfile.nearStepEdge(z, margin)
	local seg = PoolProfile.Profile[1]
	if z < seg.z0 or z > seg.z1 then
		return false
	end
	local run = (seg.z1 - seg.z0) / seg.steps
	local t = (z - seg.z0) % run
	return t < margin or t > run - margin
end

return PoolProfile
