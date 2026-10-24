local Rng = require("../src/shared/Rng")
local MazeGen = require("../src/shared/MazeGen")
local MapConfig = require("../src/shared/Config/MapConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "MazeGen: " .. name, fn = fn })
end

test("500 seeds all produce valid, fully connected layouts", function()
	for seed = 1, 500 do
		local layout = MazeGen.generate(MapConfig, Rng.new(seed * 7919))
		local ok, reason = MazeGen.validate(layout, MapConfig)
		assert(ok, "seed " .. seed .. ": " .. tostring(reason))
	end
end)

test("same seed reproduces the same layout", function()
	local a = MazeGen.generate(MapConfig, Rng.new(4242))
	local b = MazeGen.generate(MapConfig, Rng.new(4242))
	for i, cell in ipairs(a.cells) do
		assert(cell.kind == b.cells[i].kind, "kind differs at " .. i)
	end
	assert(#a.edgeKeys == #b.edgeKeys)
end)

test("different seeds produce different layouts", function()
	local differences = 0
	local a = MazeGen.generate(MapConfig, Rng.new(1))
	local b = MazeGen.generate(MapConfig, Rng.new(2))
	for i, cell in ipairs(a.cells) do
		if cell.kind ~= b.cells[i].kind then
			differences += 1
		end
	end
	assert(differences > 5, "layouts nearly identical")
end)

test("special rooms have one heavy door entrance from an ordinary cell", function()
	for seed = 1, 100 do
		local layout = MazeGen.generate(MapConfig, Rng.new(seed))
		for _, name in ipairs(MapConfig.SpecialRooms) do
			local cell = layout.cells[layout.specials[name]]
			local edge = layout.edges[MazeGen.edgeKey(cell.index, cell.entrance)]
			assert(edge and edge.heavy and edge.kind == "Door", name .. " entrance is not a heavy door")
			assert(not layout.cells[cell.entrance].special)
		end
	end
end)

test("layouts contain loops for escaping chases", function()
	local totalExtra = 0
	for seed = 1, 50 do
		local layout = MazeGen.generate(MapConfig, Rng.new(seed))
		local cellsCount = layout.width * layout.height
		totalExtra += #layout.edgeKeys - (cellsCount - 1)
	end
	assert(totalExtra / 50 >= 5, "too few loops on average: " .. totalExtra / 50)
end)

test("lockers and monster spawn are placed sensibly", function()
	for seed = 1, 100 do
		local layout = MazeGen.generate(MapConfig, Rng.new(seed))
		assert(#layout.lockers >= MapConfig.LockerCount * 0.7, "too few lockers")
		local spawn = layout.cells[layout.monsterSpawn]
		assert(not spawn.special and spawn.kind ~= "Start", "monster spawns in special room")
		assert(spawn.distance >= 4, "monster spawns too close to start")
	end
end)

test("every objective room has a hiding spot right outside its door", function()
	for seed = 1, 200 do
		local layout = MazeGen.generate(MapConfig, Rng.new(seed))
		for _, name in ipairs(MapConfig.SpecialRooms) do
			local entrance = layout.cells[layout.specials[name]].entrance
			local found = layout.cells[entrance].kind == "Start"
			for _, locker in ipairs(layout.lockers) do
				if locker.cell == entrance then
					found = true
				end
			end
			assert(found, "seed " .. seed .. ": no hiding spot outside " .. name)
		end
	end
end)

test("item cells avoid special rooms and the start room", function()
	for seed = 1, 100 do
		local rng = Rng.new(seed)
		local layout = MazeGen.generate(MapConfig, rng)
		local picks = MazeGen.pickItemCells(layout, rng, 8)
		assert(#picks == 8, "not enough item cells")
		for _, cell in ipairs(picks) do
			assert(not cell.special and cell.kind ~= "Start")
		end
	end
end)

return cases
