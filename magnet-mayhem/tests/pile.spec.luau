local L = require("./loader")
local PileLayout = L.shared("PileLayout")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "PileLayout: " .. name, fn = fn })
end

test("slots are deterministic (no reshuffling)", function()
	for i = 1, 60 do
		local x1, y1, z1 = PileLayout.slot(i, 3.2, 1, 1)
		local x2, y2, z2 = PileLayout.slot(i, 3.2, 1, 1)
		assert(x1 == x2 and y1 == y2 and z1 == z2)
	end
end)

test("rings fill in order and grow outward and upward", function()
	assert(PileLayout.ringOf(1) == 0)
	assert(PileLayout.ringOf(7) == 0 and PileLayout.ringOf(8) == 1)
	local _, y1 = PileLayout.slot(1, 0, 1, 1)
	local _, y50 = PileLayout.slot(50, 0, 1, 1)
	assert(y50 > y1 + 2)
	assert(PileLayout.topHeight(50) > PileLayout.topHeight(5))
end)

test("pieces never sit inside the character or below head height", function()
	for i = 1, 120 do
		for _, t in ipairs({ 0, 1.7, 9.3 }) do
			local x, y, z = PileLayout.slot(i, t, 0.4, 0.7)
			assert(math.sqrt(x * x + z * z) >= 1.9, "slot " .. i .. " inside the body")
			assert(y >= 2.6, "slot " .. i .. " too low (covers the character)")
		end
	end
end)

test("no two pieces share a spot", function()
	local seen = {}
	for i = 1, 80 do
		local x, y, z = PileLayout.slot(i, 0, 1, 1)
		local key = string.format("%.2f:%.2f:%.2f", x, y, z)
		assert(not seen[key], "slot " .. i .. " duplicates slot " .. tostring(seen[key]))
		seen[key] = i
	end
end)

test("packing upgrade makes the pile tighter", function()
	local x1, y1, z1 = PileLayout.slot(30, 0, 1, 1)
	local x2, y2, z2 = PileLayout.slot(30, 0, 1, 0.7)
	assert(math.sqrt(x2 * x2 + z2 * z2) < math.sqrt(x1 * x1 + z1 * z1))
	assert(y2 < y1)
end)

test("overflow cluster grows slowly and is capped", function()
	assert(PileLayout.clusterSize(0) == 0)
	assert(PileLayout.clusterSize(10) < PileLayout.clusterSize(1000))
	assert(PileLayout.clusterSize(1e9) <= 7)
end)

return cases
