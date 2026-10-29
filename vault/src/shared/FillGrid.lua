--[[
	FillGrid - where the pickups that fill a pool sit: a tight jittered grid over the whole
	treasure surface (every step, terrace and ramp, wall to wall), so the pool reads as one
	solid pile of loot. Pure and deterministic (same seed -> same slots).

	A slot is { x, z, h (surface height below the rim), slope (radians, about x), yaw,
	lift (tiny random height so neighbours don't z-fight), bonus (Rare Loot Luck multiplier:
	1 at the rim .. 1.8 at the deep end) }.
	`exclude` is a list of { x0, x1, z0, z1 } boxes (the vault door's swing, the rare-event
	spot) kept clear. VaultBuilder additionally drops any slot that is buried in a part or
	not standable (Reach).
]]

local PoolProfile = require(script.Parent.PoolProfile)
local Rng = require(script.Parent.Rng)

local FillGrid = {}

FillGrid.Spacing = 2.4
FillGrid.Jitter = 0.35
FillGrid.Margin = 1.3 -- from the pool walls
FillGrid.StepEdge = 0.35 -- keep items off stair noses

local P = PoolProfile.Pool

local function excluded(list, x, z)
	for _, box in ipairs(list or {}) do
		if x >= box[1] and x <= box[2] and z >= box[3] and z <= box[4] then
			return true
		end
	end
	return false
end
FillGrid.excluded = excluded

function FillGrid.generate(seed, exclude, spacing)
	spacing = spacing or FillGrid.Spacing
	local rng = Rng.new(seed)
	local slots = {}
	local row = 0
	local function add(jx, jz)
		if not excluded(exclude, jx, jz) and not PoolProfile.nearStepEdge(jz, FillGrid.StepEdge) then
			local h, slope = PoolProfile.surface(jz)
			table.insert(slots, {
				x = jx,
				z = jz,
				h = h,
				slope = slope,
				yaw = rng:NextNumber(-0.45, 0.45) + (if rng:NextNumber() < 0.5 then 0 else math.pi / 2),
				lift = rng:NextNumber(0, 0.12),
				bonus = 1 + 0.8 * (-h / P.depth),
			})
		end
	end
	-- The grand steps: one row along the middle of every step.
	local stairs = PoolProfile.Profile[1]
	local run = (stairs.z1 - stairs.z0) / stairs.steps
	for i = 1, stairs.steps do
		row += 1
		local zc = stairs.z0 + (i - 0.5) * run
		local x = P.x0 + FillGrid.Margin + (if row % 2 == 0 then spacing / 2 else 0)
		while x <= P.x1 - FillGrid.Margin do
			add(x + rng:NextNumber(-FillGrid.Jitter, FillGrid.Jitter), zc + rng:NextNumber(-0.15, 0.15))
			x += spacing
		end
	end
	-- Everything below the steps: a brick-pattern jittered grid.
	local z = stairs.z1 + spacing * 0.45
	while z <= P.z1 - FillGrid.Margin * 0.6 do
		row += 1
		-- Offset alternate rows by half a spacing (a brick pattern packs tighter).
		local x = P.x0 + FillGrid.Margin + (if row % 2 == 0 then spacing / 2 else 0)
		while x <= P.x1 - FillGrid.Margin do
			local jx = x + rng:NextNumber(-FillGrid.Jitter, FillGrid.Jitter)
			local jz = z + rng:NextNumber(-FillGrid.Jitter, FillGrid.Jitter)
			jz = math.clamp(jz, stairs.z1 + 0.3, P.z1 - 0.6)
			add(jx, jz)
			x += spacing
		end
		z += spacing * 0.87
	end
	return slots
end

-- Largest distance from any sample point of the surface to its nearest slot (coverage).
function FillGrid.maxGap(slots, exclude, step)
	step = step or 0.8
	local cell = 4
	local grid = {}
	for _, s in ipairs(slots) do
		local k = math.floor(s.x / cell) .. ":" .. math.floor(s.z / cell)
		grid[k] = grid[k] or {}
		table.insert(grid[k], s)
	end
	local worst, at = 0, nil
	local x = P.x0 + FillGrid.Margin
	while x <= P.x1 - FillGrid.Margin do
		local z = P.z0 + 1
		while z <= P.z1 - 1 do
			if not excluded(exclude, x, z) then
				local best = math.huge
				for dx = -1, 1 do
					for dz = -1, 1 do
						for _, s in ipairs(grid[(math.floor(x / cell) + dx) .. ":" .. (math.floor(z / cell) + dz)] or {}) do
							best = math.min(best, math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2))
						end
					end
				end
				if best > worst then
					worst, at = best, Vector2.new(x, z)
				end
			end
			z += step
		end
		x += step
	end
	return worst, at
end

return FillGrid
