local load = require("./loader")
local Seating = load("Seating")
local Rng = load("Rng")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Seating: " .. name, fn = fn })
end

local function desks()
	local list = {}
	local i = 0
	for row = 1, 3 do
		for col = 1, 4 do
			i += 1
			table.insert(list, { index = i, row = row, col = col, vip = row == 3 and (col == 1 or col == 4) })
		end
	end
	return list
end

local function byIndex(list)
	local m = {}
	for _, d in ipairs(list) do
		m[d.index] = d
	end
	return m
end

test("12 students get 12 distinct desks", function()
	local students = {}
	for i = 1, 12 do
		table.insert(students, { id = i, friends = {} })
	end
	local result = Seating.assign(students, desks(), Rng.new(1))
	local used = {}
	for i = 1, 12 do
		assert(result[i], "student " .. i .. " has no desk")
		assert(not used[result[i]], "desk shared")
		used[result[i]] = true
	end
end)

test("VIPs get the VIP desks in the back", function()
	local d = desks()
	local m = byIndex(d)
	local students = { { id = "a", vip = true, friends = {} }, { id = "b", friends = {} }, { id = "c", vip = true, friends = {} } }
	local result = Seating.assign(students, d, Rng.new(2))
	assert(m[result.a].vip and m[result.c].vip)
	assert(not m[result.b].vip)
end)

test("friends sit next to each other (party seating)", function()
	local d = desks()
	local m = byIndex(d)
	for seed = 1, 30 do
		local students = {
			{ id = "x", friends = { y = true } },
			{ id = "y", friends = { x = true, z = true } },
			{ id = "z", friends = { y = true } },
			{ id = "loner1", friends = {} },
			{ id = "loner2", friends = {} },
		}
		local r = Seating.assign(students, d, Rng.new(seed))
		local rows = { m[r.x].row, m[r.y].row, m[r.z].row }
		assert(rows[1] == rows[2] and rows[2] == rows[3], "group split across rows")
		local cols = { m[r.x].col, m[r.y].col, m[r.z].col }
		table.sort(cols)
		assert(cols[3] - cols[1] == 2, "group not contiguous")
	end
end)

test("a friend of a VIP sits next to the VIP", function()
	local d = desks()
	local m = byIndex(d)
	local students = { { id = "vip", vip = true, friends = { pal = true } }, { id = "pal", friends = { vip = true } } }
	local r = Seating.assign(students, d, Rng.new(3))
	assert(Seating.adjacent(m[r.vip], m[r.pal]), "pal not next to the VIP")
end)

return cases
