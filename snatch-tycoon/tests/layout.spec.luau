local H = require("./helpers")
local Layout = require("../src/shared/Layout")
local GameConfig = require("../src/shared/Config/GameConfig")
local cases, test = H.suite("Layout")
local P = GameConfig.Plot

test("eight plots, none overlapping, none on the carpet", function()
	local spots = {}
	for i = 1, GameConfig.MaxPlayers do
		local x, z = Layout.plotPosition(i, P)
		assert(math.abs(x) - P.Depth / 2 > GameConfig.Carpet.Width / 2 + 4, "plot " .. i .. " touches the carpet")
		for _, other in ipairs(spots) do
			local sameSide = (x > 0) == (other.x > 0)
			if sameSide then
				assert(math.abs(z - other.z) >= P.Width + 8, "plots overlap")
			end
		end
		table.insert(spots, { x = x, z = z })
		assert(z - P.Width / 2 > GameConfig.Carpet.StartZ and z + P.Width / 2 < GameConfig.Carpet.EndZ, "plot beyond carpet ends")
	end
end)

test("plots face the carpet", function()
	for i = 1, GameConfig.MaxPlayers do
		local x, _, yaw = Layout.plotPosition(i, P)
		-- local -Z rotated by yaw: (-sin yaw, -cos yaw)
		local fx = -math.sin(yaw)
		assert(fx * x < 0, "plot " .. i .. " faces away from the carpet")
		H.near(math.cos(yaw), 0, 1e-9)
	end
end)

test("all pedestals fit inside the base and leave the entrance clear", function()
	local seen = {}
	for slot = 1, GameConfig.MaxPedestals do
		local x, z = Layout.pedestalLocal(slot, P)
		assert(Layout.insideLocal(x, z, P, 3), "pedestal " .. slot .. " outside")
		assert(z - 4 > Layout.frontZ(P) + 5, "pedestal " .. slot .. " blocks the entrance")
		local key = x .. "," .. z
		assert(not seen[key], "two pedestals in one spot")
		seen[key] = true
	end
	assert(P.Columns * P.Rows >= GameConfig.MaxPedestals)
end)

test("insideLocal", function()
	assert(Layout.insideLocal(0, 0, P))
	assert(not Layout.insideLocal(0, -P.Depth / 2 - 1, P))
	assert(not Layout.insideLocal(P.Width, 0, P))
end)

return cases
