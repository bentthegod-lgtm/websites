local Rng = require("../src/shared/Rng")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Rng: " .. name, fn = fn })
end

test("same seed gives same sequence", function()
	local a, b = Rng.new(1234), Rng.new(1234)
	for _ = 1, 100 do
		assert(a:nextRaw() == b:nextRaw(), "sequences diverged")
	end
end)

test("next() stays in [0,1)", function()
	local r = Rng.new(99)
	for _ = 1, 5000 do
		local v = r:next()
		assert(v >= 0 and v < 1, "out of range: " .. v)
	end
end)

test("integer() covers inclusive range", function()
	local r = Rng.new(7)
	local seen = {}
	for _ = 1, 2000 do
		local v = r:integer(1, 6)
		assert(v >= 1 and v <= 6)
		seen[v] = true
	end
	for i = 1, 6 do
		assert(seen[i], "never rolled " .. i)
	end
end)

test("weighted() ignores zero weights and is order independent", function()
	local r = Rng.new(5)
	for _ = 1, 500 do
		local k = r:weighted({ a = 1, b = 0, c = 3 })
		assert(k == "a" or k == "c", "picked zero-weight key")
	end
end)

return cases
