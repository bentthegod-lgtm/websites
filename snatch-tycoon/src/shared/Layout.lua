--[[
	World layout math (pure numbers, unit tested). WorldBuilder turns these into CFrames.

	Plots are numbered 1..8: 1-4 on the -X side of the carpet, 5-8 on the +X side.
	Each plot's local frame has -Z pointing at the carpet (the open front of the base).
]]

local Layout = {}

-- Returns world x, z of the plot centre and the yaw (radians) that makes local -Z face
-- the carpet.
function Layout.plotPosition(index, plotCfg)
	local side = if index <= plotCfg.PerSide then -1 else 1
	local k = (index - 1) % plotCfg.PerSide
	local z = (k - (plotCfg.PerSide - 1) / 2) * plotCfg.Spacing
	local x = side * plotCfg.OffsetX
	-- yaw = +90deg turns -Z into -X (for the +X side we want to face -X).
	local yaw = if side > 0 then math.pi / 2 else -math.pi / 2
	return x, z, yaw
end

-- Local x, z of a pedestal (slot 1 is at the back, furthest from the entrance).
function Layout.pedestalLocal(slot, plotCfg)
	local index = slot - 1
	local row = math.floor(index / plotCfg.Columns)
	local col = index % plotCfg.Columns
	local x = (col - (plotCfg.Columns - 1) / 2) * plotCfg.ColumnSpacing
	local z = plotCfg.BackRowZ - row * plotCfg.RowSpacing
	return x, z
end

-- Is a point (in plot-local x, z) inside the base floor? margin shrinks the area.
function Layout.insideLocal(lx, lz, plotCfg, margin)
	margin = margin or 0
	return math.abs(lx) <= plotCfg.Width / 2 - margin and math.abs(lz) <= plotCfg.Depth / 2 - margin
end

-- Plot-local z of the front edge (laser door line).
function Layout.frontZ(plotCfg)
	return -plotCfg.Depth / 2
end

return Layout
