local L = require("./loader")
local StackLayout = L.shared("StackLayout")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Stack: " .. name, fn = fn })
end

test("arrangement changes at the documented thresholds", function()
	local expect = { [1] = "Hand", [3] = "Hand", [4] = "Bundle", [12] = "Bundle", [13] = "Stack", [36] = "Stack", [37] = "Tower", [90] = "Tower", [91] = "Crate", [5000] = "Crate" }
	for n, mode in pairs(expect) do
		local layout = StackLayout.layout({ Cash = n }, 24)
		assert(layout.mode == mode, string.format("%d items -> %s, expected %s", n, layout.mode, mode))
	end
	assert(#StackLayout.layout({}, 24).pieces == 0, "empty stack has no pieces")
end)

test("layout is deterministic", function()
	local a = StackLayout.layout({ Cash = 20, Gold = 9 }, 24)
	local b = StackLayout.layout({ Gold = 9, Cash = 20 }, 24)
	assert(#a.pieces == #b.pieces, "same piece count")
	for i, p in ipairs(a.pieces) do
		local q = b.pieces[i]
		assert(p.category == q.category and p.x == q.x and p.y == q.y and p.z == q.z and p.yaw == q.yaw, "piece " .. i .. " differs")
	end
end)

test("piece budget is respected and the rest is reported hidden", function()
	for _, n in ipairs({ 5, 30, 80, 300, 2000 }) do
		for _, budget in ipairs({ 6, 12, 24 }) do
			local layout = StackLayout.layout({ Gold = n }, budget)
			assert(#layout.pieces <= budget, string.format("%d pieces > budget %d", #layout.pieces, budget))
			assert(layout.hidden >= 0 and layout.count == n, "count / hidden")
		end
	end
	assert(StackLayout.layout({ Gold = 300 }, 24).crate, "very large stacks use the crate")
end)

test("heavy metals sit at the bottom, gems on top", function()
	local layout = StackLayout.layout({ Diamond = 6, Gold = 6, Cash = 6 }, 24)
	local lowest = {}
	for _, p in ipairs(layout.pieces) do
		lowest[p.category] = math.min(lowest[p.category] or math.huge, p.y)
	end
	assert(lowest.Gold <= lowest.Cash and lowest.Cash <= lowest.Diamond, "stacking order")
end)

local function overlaps(a, b)
	if a.layer ~= b.layer then
		return false
	end
	local P = StackLayout.PieceSize
	local function extent(p)
		local hx, hz = P.X / 2 * p.scale, P.Z / 2 * p.scale
		if math.abs(math.abs(p.yaw) - math.pi / 2) < 1e-3 then
			hx, hz = hz, hx
		end
		return hx, hz
	end
	local ax, az = extent(a)
	local bx, bz = extent(b)
	return math.abs(a.x - b.x) < ax + bx - 1e-3 and math.abs(a.z - b.z) < az + bz - 1e-3
end

test("bars interlock on alternate layers without overlapping", function()
	for _, mode in ipairs({ { n = 30 }, { n = 80 } }) do
		local layout = StackLayout.layout({ Gold = mode.n }, 24)
		local turned = 0
		for i, a in ipairs(layout.pieces) do
			if a.layer % 2 == 1 and math.abs(a.yaw - math.pi / 2) < 1e-6 then
				turned += 1
			end
			for j = i + 1, #layout.pieces do
				assert(not overlaps(a, layout.pieces[j]), string.format("pieces %d and %d overlap (%s)", i, j, layout.mode))
			end
		end
		assert(turned > 0, layout.mode .. ": odd layers should be turned 90 degrees")
	end
	-- Gems never interlock.
	for _, p in ipairs(StackLayout.layout({ Diamond = 30 }, 24).pieces) do
		assert(p.yaw == 0, "gem trays stay square")
	end
end)

test("within each arrangement, more items never make a lower stack", function()
	for _, range in ipairs({ { 1, 3 }, { 4, 12 }, { 13, 36 }, { 37, 90 } }) do
		local last = -math.huge
		for n = range[1], range[2] do
			local top = -math.huge
			for _, p in ipairs(StackLayout.layout({ Cash = n }, 24).pieces) do
				top = math.max(top, p.y)
			end
			assert(top >= last - 1e-9, string.format("%d items gave a lower stack than %d", n, n - 1))
			last = top
		end
	end
end)

return cases
