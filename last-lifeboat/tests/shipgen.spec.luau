local L = require("./loader")
local GameConfig = L.shared("Config/GameConfig")
local ShipGen = L.shared("ShipGen")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "ShipGen: " .. name, fn = fn })
end

local SEEDS = { 1, 7, 42, 99, 1234, 5150, 31337, 8675309 }

test("every ship plans with the configured decks, themes bottom to top and a whole number of cells", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		local plan = ShipGen.plan(key, 3)
		assert(#plan.decks == #def.Decks, key .. " deck count")
		assert(plan.decks[#plan.decks].theme == "TopDeck" and plan.decks[#plan.decks].top, key .. " top deck")
		for i = 2, #plan.decks do
			assert(plan.decks[i].y - plan.decks[i - 1].y == GameConfig.Ship.DeckHeight, "deck spacing")
		end
		assert(plan.decks[1].y > 0, key .. ": the lowest deck must start above sea level")
		assert(plan.cellCount * GameConfig.Ship.CellLength == def.Length)
	end
	assert(#GameConfig.Ships.Gull.Decks == 3 and #GameConfig.Ships.Aurora.Decks == 5 and #GameConfig.Ships.Leviathan.Decks == 7)
end)

test("hull tapers to a narrow bow and rounds off at the stern", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		local mid = ShipGen.widthAt(def, def.Length / 2)
		assert(mid == def.Beam, key .. " midship width")
		assert(ShipGen.widthAt(def, def.Length) <= GameConfig.Ship.BowTip + 1e-6, key .. " bow tip")
		local prev = math.huge
		for z = def.Length - GameConfig.Ship.BowCells * GameConfig.Ship.CellLength, def.Length, 4 do
			local w = ShipGen.widthAt(def, z)
			assert(w <= prev + 1e-6, key .. " bow not tapering at z=" .. z)
			prev = w
		end
		assert(ShipGen.widthAt(def, 0) < def.Beam and ShipGen.widthAt(def, 0) >= def.Beam * 0.6, key .. " stern")
	end
end)

test("lifeboat reachable from spawn on every ship and seed, without diving, with every bulkhead shut", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			assert(plan.spawn.deck == 1 and plan.spawn.cell >= plan.cellCount - GameConfig.Ship.BowCells, key .. ": spawn not at the bow of the lowest deck")
			assert(plan.lifeboat.deck == #plan.decks and plan.lifeboat.cell == 1, key .. ": lifeboat not at the stern of the top deck")
			local seen = ShipGen.reachable(plan, { noDive = true })
			local d = seen[ShipGen.node(plan.lifeboat.deck, plan.lifeboat.cell)]
			assert(d ~= nil, string.format("%s seed %d: lifeboat unreachable", key, seed))
			assert(d >= #plan.decks - 1, "path too short to be real")
		end
	end
end)

test("decks connected: every cell of every deck is reachable (bulkheads shut, no dives)", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			local ok, d, c = ShipGen.allConnected(plan, { noDive = true })
			assert(ok, string.format("%s seed %d: deck %s cell %s cut off", key, seed, tostring(d), tostring(c)))
		end
	end
end)

test("every loot spot is reachable, inside the hull, off the walkway and clear of other features", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			local seen = ShipGen.reachable(plan, { noDive = true })
			assert(#plan.loot >= #plan.decks * 3, key .. " too little loot: " .. #plan.loot)
			for _, spot in ipairs(plan.loot) do
				assert(seen[ShipGen.node(spot.deck, spot.cell)] ~= nil, "loot spot unreachable")
				local cell = plan.cells[spot.cell]
				assert(spot.z > cell.z0 and spot.z < cell.z1, "loot outside its cell")
				assert(math.abs(spot.x) < cell.width / 2 - 1, "loot in the hull wall")
				assert(math.abs(spot.x) > GameConfig.Ship.WalkwayHalf, "loot on the walkway")
				for _, conn in ipairs(plan.connectors) do
					if conn.cell == spot.cell and (conn.from == spot.deck or conn.to == spot.deck) then
						local hx, hz = ShipGen.connectorFootprint(conn.kind)
						assert(not ShipGen.overlaps(ShipGen.rect(spot.x, spot.z, 1, 1), ShipGen.rect(conn.x, conn.z, hx, hz)), "loot on a stairwell")
					end
				end
			end
		end
	end
end)

test("the top deck keeps the deckhouse, helm and lifeboat clear of loot", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			local dh = plan.deckhouse
			assert(dh and dh.z1 > dh.z0 and dh.halfWidth > 4, key .. " deckhouse")
			for _, spot in ipairs(plan.loot) do
				if spot.deck == #plan.decks then
					local inHouse = spot.z > dh.z0 - 1.2 and spot.z < dh.z1 + 1.2 and math.abs(spot.x) < dh.halfWidth + 1.2
					assert(not inHouse, string.format("%s seed %d: loot inside the deckhouse", key, seed))
					assert(not (spot.z < 19 and math.abs(spot.x) < 10), "loot in the lifeboat")
				end
			end
		end
	end
end)

test("route choice: each boundary has a dry way up; some routes are blocked; bow shafts are dive shortcuts", function()
	local blocked, dives = 0, 0
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			for d = 1, #plan.decks - 1 do
				local dry, total = 0, 0
				for _, conn in ipairs(plan.connectors) do
					if conn.from == d then
						total += 1
						if not conn.blocked and not conn.dive then
							dry += 1
						end
						if conn.blocked then
							blocked += 1
						end
						if conn.dive then
							dives += 1
							assert(conn.kind == "Shaft" and conn.cell >= plan.cellCount - GameConfig.Ship.BowCells, "dive shaft not at the bow")
							assert(d < #plan.decks - 1, "dive shaft into the top deck")
						end
						local w = plan.cells[conn.cell].width
						local hx = ShipGen.connectorFootprint(conn.kind)
						assert(math.abs(conn.x) + hx <= w / 2, string.format("%s connector sticks out of the hull (cell %d)", key, conn.cell))
					end
				end
				assert(dry >= 1, string.format("%s seed %d: no dry way up from deck %d", key, seed, d))
				assert(total >= 2 or plan.cellCount < 10, "only one route up")
			end
			-- Dining hall rises by the grand staircase.
			for d, deck in ipairs(plan.decks) do
				if deck.theme == "DiningHall" then
					local grand = false
					for _, conn in ipairs(plan.connectors) do
						grand = grand or (conn.from == d and conn.kind == "GrandStair")
					end
					assert(grand, "no grand staircase")
				end
			end
		end
	end
	assert(blocked >= 6, "routes are never blocked (" .. blocked .. ")")
	assert(dives >= 6, "no dive shortcuts (" .. dives .. ")")
end)

test("connectors never stack in the same cell on neighbouring decks", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			local used = {}
			for _, conn in ipairs(plan.connectors) do
				for _, deck in ipairs({ conn.from, conn.to }) do
					local k = ShipGen.node(deck, conn.cell)
					assert(not used[k], string.format("%s seed %d: two connectors share deck %d cell %d", key, seed, deck, conn.cell))
					used[k] = true
				end
			end
		end
	end
end)

test("bulkheads are shortcuts with two levers on the bow side; valves one per interior deck", function()
	local bulkheads = 0
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			for _, b in ipairs(plan.bulkheads) do
				bulkheads += 1
				assert(#b.levers == 2, "levers")
				assert(b.levers[1].x < 0 and b.levers[2].x > 0, "levers on both sides")
				for _, lever in ipairs(b.levers) do
					assert(lever.z > b.z, "lever not on the bow side")
				end
				assert(ShipGen.allConnected(plan, { bulkheadsOpen = true, noDive = true }), "opening a bulkhead disconnects?")
			end
			assert(#plan.valves == #plan.decks - 1, key .. " valves " .. #plan.valves)
			local seenDeck = {}
			for _, v in ipairs(plan.valves) do
				assert(not seenDeck[v.deck], "two valves on one deck")
				seenDeck[v.deck] = true
			end
		end
	end
	assert(bulkheads >= 10, "too few bulkheads: " .. bulkheads)
end)

test("hazards match their decks: steam below, chandeliers in the dining hall, wires in the flooding bow half", function()
	local kinds = {}
	for _, key in ipairs(GameConfig.ShipOrder) do
		local plan = ShipGen.plan(key, 11)
		for _, h in ipairs(plan.hazards) do
			kinds[h.kind] = (kinds[h.kind] or 0) + 1
			local theme = plan.decks[h.deck].theme
			if h.kind == "Chandelier" then
				assert(theme == "DiningHall")
			elseif h.kind == "Steam" then
				assert(theme == "EngineRoom" or theme == "CrewQuarters" or theme == "CargoHold", "steam in " .. theme)
			elseif h.kind == "Wires" then
				assert(h.cell >= math.floor(plan.cellCount * 0.45), "wires not in the bow half")
			end
		end
	end
	assert(kinds.Steam and kinds.Chandelier and kinds.Wires, "missing a hazard type")
end)

test("part budget: estimate within budget for every ship and seed (Leviathan 1,500-5,000)", function()
	for _, key in ipairs(GameConfig.ShipOrder) do
		for _, seed in ipairs(SEEDS) do
			local plan = ShipGen.plan(key, seed)
			assert(plan.partEstimate <= plan.def.PartBudget, string.format("%s seed %d: %d parts > budget %d", key, seed, plan.partEstimate, plan.def.PartBudget))
		end
	end
	local big = ShipGen.plan("Leviathan", 5).partEstimate
	assert(big >= 1500 and big <= 5000, "Leviathan estimate " .. big)
end)

test("plans are deterministic per seed and differ between seeds", function()
	local a, b, c = ShipGen.plan("Aurora", 77), ShipGen.plan("Aurora", 77), ShipGen.plan("Aurora", 78)
	assert(#a.loot == #b.loot and a.loot[1].x == b.loot[1].x and a.connectors[1].cell == b.connectors[1].cell, "not deterministic")
	local same = #a.loot == #c.loot and a.loot[1].x == c.loot[1].x and a.loot[2].z == c.loot[2].z
	assert(not same, "seed has no effect")
end)

return cases
