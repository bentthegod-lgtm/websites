--[[
	LootService - every loose item in the vault, the carried inventory, the Cash Magnet,
	Auto-Collect and rare loot events. Everything here is server-authoritative.

	Registry: loot[id] = { id, def, depth, point, position, model, pulledBy, pulledAt,
	expires }. A claim is atomic: collect() checks and removes the entry in one go with no
	yields, so when two players reach the same bill on the same frame exactly one gets it.

	Pickup checks: profile loaded, item exists on the player's depth, distance to the item
	(collection radius + latency slack), the pickup cooldown, and carrying capacity. The
	value is fixed at pickup from the player's current stats and added to profile.Carried.

	Filling: every pool is FULL. Each depth has ~1,700 fill slots (VaultBuilder / FillGrid)
	tiling its whole treasure surface; every slot holds one pickup, rolled from LootTable
	with the slot's depth bonus and the best Rare Loot Luck among players there (Epic+ stay
	capped by MaxActive). A collected slot refills RefillDelay seconds later (a FIFO queue,
	at most FillPerTick spawns per tick). A depth's fill only exists while it is OCCUPIED (a
	player on it, behind its upper neighbour's vault door, or riding the elevator to it);
	30 s after the last player leaves it is unloaded and its stand-in slabs show instead.
	Common to rare pickups are single parts, Epic+ detailed models; all are pooled.
	Rare loot events drop a special item at a depth's rare spot for a few minutes (global
	gap + per-depth cooldown).

	Lookups: one SpatialHash per depth (8-stud buckets) for the magnet and Auto-Collect, so
	nothing loops over thousands of items. Collect claims are by id and atomic.

	Magnet: every MagnetTick the nearest MagnetMaxPull free items inside the magnet radius
	slide toward the player (reserved for them while pulled; their slot stays theirs until
	collected). Auto-Collect picks up the nearest free item inside its small radius at its
	own interval.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local LootConfig = require(Shared.Config.LootConfig)
local LootTable = require(Shared.LootTable)
local SpatialHash = require(Shared.SpatialHash)
local RefillQueue = require(Shared.RefillQueue)
local LootModels = require(Shared.LootModels)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Format = require(Shared.Format)

local LootService = {}

local services
local world
local loot = {} -- [id] = entry
local byDepth = {} -- [depth] = { [id] = entry }
local active = {} -- [depth] = { [itemId] = count }
local counts = {} -- [depth] = items alive
local slotEntry = {} -- [depth] = { [slotIndex] = entry }
local hashes = {} -- [depth] = SpatialHash of entry ids
local state = {} -- [depth] = { active, emptySince, queue, standinShown }
local occupancyClock = 0
local pool = {} -- [itemId] = { models / parts }
local pivotOffset = {} -- [itemId] = base -> pivot offset
local nextId = 0
local rng = Random.new()
local lastPickup = {}
local lastAuto = {}
local lastFullNotice = {}
local magnetClock = 0
local rare = { nextAt = 0, depthAt = {}, entry = nil }

LootService.Debug = { spawned = 0, reused = 0, activations = 0, unloads = 0 }
LootService.FillPerTick = 300 -- pickups materialised per 0.1 s tick (spreads a pool's fill over ~0.6 s)
LootService.UnloadAfter = 30 -- seconds a depth stays filled after its last player leaves

function LootService.init(registry)
	services = registry
end

function LootService.setWorld(newWorld)
	world = newWorld
	for depth in pairs(world.depths) do
		byDepth[depth] = {}
		active[depth] = {}
		counts[depth] = 0
		slotEntry[depth] = {}
		hashes[depth] = SpatialHash.new(8)
		state[depth] = { active = false, emptySince = nil, queue = RefillQueue.new() }
	end
end

-- Models ------------------------------------------------------------------------------------

local function takeModel(itemId, base)
	local list = pool[itemId]
	local model = list and table.remove(list)
	if model then
		model:PivotTo(base * pivotOffset[itemId])
		LootService.Debug.reused += 1
		return model
	end
	if LootModels.isSimple(itemId) then
		model = LootModels.simple(itemId, base)
	else
		model = LootModels.build(itemId, base, GameConfig.LootScale)
	end
	pivotOffset[itemId] = base:ToObjectSpace(model:GetPivot())
	return model
end

local function releaseModel(entry)
	local model = entry.model
	entry.model = nil
	if not model then
		return
	end
	model.Parent = nil
	pool[entry.def.Id] = pool[entry.def.Id] or {}
	if #pool[entry.def.Id] < (if LootModels.isSimple(entry.def.Id) then 1500 else 24) then
		table.insert(pool[entry.def.Id], model)
	else
		model:Destroy()
	end
end

-- Spawning ----------------------------------------------------------------------------------

local function bestLuck(depth)
	local luck = 1
	for _, player in ipairs(services.PlayerService.playersOnDepth(depth)) do
		luck = math.max(luck, services.DataService.stats(player).Luck)
	end
	return luck
end

local function register(depth, def, point, position, base)
	nextId += 1
	local id = nextId
	local model = takeModel(def.Id, base)
	model:SetAttribute("LootId", id)
	model:SetAttribute("Depth", depth)
	model.Parent = world.lootFolder
	local entry = { id = id, def = def, depth = depth, point = point, position = position, base = base, model = model }
	loot[id] = entry
	byDepth[depth][id] = entry
	active[depth][def.Id] = (active[depth][def.Id] or 0) + 1
	counts[depth] += 1
	hashes[depth]:insert(id, position)
	if point then
		slotEntry[depth][point.index] = entry
	end
	LootService.Debug.spawned += 1
	return entry
end

-- Fills one slot of a depth's pool (if it is empty). Returns the entry or nil.
function LootService.fillSlot(depth, point, luck)
	if slotEntry[depth][point.index] then
		return nil
	end
	-- Deeper in the pool the luck is better (point.bonus; LootTable caps luck at 2x).
	local item = LootTable.rollFill(depth, active[depth], (luck or 1) * (point.bonus or 1), rng)
	if not item then
		return nil
	end
	return register(depth, item, point, point.cframe.Position, point.cframe)
end

local function unregister(entry)
	loot[entry.id] = nil
	local list = byDepth[entry.depth]
	if list then
		list[entry.id] = nil
	end
	hashes[entry.depth]:remove(entry.id)
	active[entry.depth][entry.def.Id] = math.max(0, (active[entry.depth][entry.def.Id] or 1) - 1)
	counts[entry.depth] = math.max(0, counts[entry.depth] - 1)
	local st = state[entry.depth]
	if entry.point then
		slotEntry[entry.depth][entry.point.index] = nil
		if st.active then
			st.queue:push(entry.point, os.clock() + world.depths[entry.depth].def.RefillDelay)
		end
	end
	releaseModel(entry)
	if rare.entry == entry then
		rare.entry = nil
	end
end

local function showStandin(depth, shown)
	local record = world.depths[depth]
	if record.standin and state[depth].standinShown ~= shown then
		state[depth].standinShown = shown
		for _, p in ipairs(record.standin:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = if shown then 0 else 1
			end
		end
	end
end

-- Materialise a depth's fill (queued; `immediate` fills every slot right now).
function LootService.activate(depth, immediate)
	local st = state[depth]
	if not st then
		return
	end
	st.emptySince = nil
	if not st.active then
		st.active = true
		LootService.Debug.activations += 1
		st.queue:clear()
		local now = os.clock()
		for _, point in ipairs(world.depths[depth].points) do
			st.queue:push(point, now)
		end
		showStandin(depth, false)
	end
	if immediate then
		local luck = bestLuck(depth)
		for _, point in ipairs(st.queue:popDue(math.huge)) do
			LootService.fillSlot(depth, point, luck)
		end
	end
end

-- Unload a depth's fill (nobody there): every pickup goes back to the pool.
function LootService.unload(depth)
	local st = state[depth]
	if not st or not st.active then
		return
	end
	st.active = false
	st.emptySince = nil
	st.queue:clear()
	LootService.Debug.unloads += 1
	for _, entry in pairs(byDepth[depth]) do
		if entry.def.Special then
			services.Remotes.RareEvent:FireAllClients("Gone", { depth = depth, item = entry.def.Id })
		end
		unregister(entry)
	end
	showStandin(depth, true)
end

function LootService.isActive(depth)
	return state[depth] ~= nil and state[depth].active
end

-- Which depths someone is on or heading to (a vault tunnel, an elevator ride).
local function occupied()
	local set = {}
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		local root = services.PlayerService.root(player)
		if root then
			local d = services.PlayerService.depthOf(player)
			set[d] = true
			local pos = root.CFrame.Position
			local record = world.depths[d]
			if record and pos.Z > GameConfig.RoomBack - 12 and pos.Y < record.y0 - 30 then
				set[d + 1] = true -- behind the vault door, on the way down
			end
		end
		local target = services.ElevatorService.rideTarget(player)
		if target then
			set[target] = true
		end
	end
	return set
end

local function stepFill(now)
	occupancyClock += 1
	if occupancyClock >= 5 then -- every 0.5 s
		occupancyClock = 0
		local set = occupied()
		for depth, st in pairs(state) do
			if set[depth] then
				LootService.activate(depth)
			elseif st.active then
				st.emptySince = st.emptySince or now
				if now - st.emptySince >= LootService.UnloadAfter then
					LootService.unload(depth)
				end
			end
		end
	end
	for depth, st in pairs(state) do
		if st.active and st.queue:size() > 0 then
			local due = st.queue:popDue(now, LootService.FillPerTick)
			if #due > 0 then
				local luck = bestLuck(depth)
				for _, point in ipairs(due) do
					LootService.fillSlot(depth, point, luck)
				end
			end
		end
	end
end

-- Carried inventory -------------------------------------------------------------------------

function LootService.carried(player)
	local data = services.DataService.getProfile(player)
	return data and data.Carried
end

function LootService.inventoryView(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local c = data.Carried
	return { count = c.Count, slots = c.Slots, capacity = services.DataService.stats(player).Capacity, value = c.Value, items = c.Items }
end

function LootService.sendInventory(player)
	local view = LootService.inventoryView(player)
	if view and player.Parent then
		services.Remotes.Inventory:FireClient(player, view)
	end
	services.PlayerService.updateAttributes(player)
end

-- Empties the carried stack and returns what was in it (DepositService, rebirth).
function LootService.takeCarried(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local carried = data.Carried
	data.Carried = services.DataService.emptyCarried()
	services.DataService.markDirty(player)
	return carried
end

-- Collection --------------------------------------------------------------------------------

--[[
	Collect an item for a player. Returns (true, value) or (false, reason).
	opts.auto: Auto-Collect (its own interval instead of the manual pickup cooldown).
]]
function LootService.collect(player, id, opts)
	opts = opts or {}
	local data = services.DataService.getProfile(player)
	if not data or services.DataService.isLeaving(player) then
		return false, "not loaded"
	end
	if type(id) ~= "number" or id ~= id then
		return false, "bad id"
	end
	local entry = loot[math.floor(id)]
	if not entry then
		return false, "gone"
	end
	local root = services.PlayerService.root(player)
	if not root then
		return false, "no character"
	end
	if services.PlayerService.depthOf(player) ~= entry.depth then
		return false, "other depth"
	end
	if entry.depth > data.HighestDepth then
		return false, "locked depth" -- only reachable by teleporting there
	end
	local stats = services.DataService.stats(player)
	local now = os.clock()
	local reach = (if opts.auto then stats.AutoRadius else stats.Radius) + GameConfig.CollectSlack
	if (root.CFrame.Position - entry.position).Magnitude > reach then
		return false, "too far"
	end
	if not opts.auto and lastPickup[player] and now - lastPickup[player] < stats.PickupInterval * GameConfig.CooldownTolerance then
		return false, "cooldown"
	end
	if entry.pulledBy and entry.pulledBy ~= player and now - (entry.pulledAt or 0) < 3 then
		return false, "reserved"
	end
	local def = entry.def
	local slots = Economy.slotsFor(def, stats)
	if data.Carried.Slots + slots > stats.Capacity then
		-- Auto-Collect retries every interval: only a manual press says "full".
		if not opts.auto and (not lastFullNotice[player] or now - lastFullNotice[player] > 2.5) then
			lastFullNotice[player] = now
			services.Remotes.Popup:FireClient(player, "StackFull", { capacity = stats.Capacity })
		end
		return false, "full"
	end
	-- Claim: remove from the world first (atomic: nothing below yields).
	unregister(entry)
	if opts.auto then
		lastAuto[player] = now
	else
		lastPickup[player] = now
	end
	local value = Economy.itemValue(def, stats)
	local carried = data.Carried
	carried.Items[def.Id] = (carried.Items[def.Id] or 0) + 1
	carried.Count += 1
	carried.Slots += slots
	carried.Value += value
	services.DataService.markDirty(player)
	for _, key in ipairs(Progress.collectStats(def)) do
		services.DataService.bump(player, key, 1)
	end
	local rank = LootConfig.rank(def)
	if rank >= 4 then
		services.DataService.bump(player, "RareFinds", 1)
		services.Analytics.funnel(player, "FirstRare")
	end
	services.QuestService.discover(player, def)
	services.QuestService.tutorialEvent(player, "Collect")
	services.Analytics.funnel(player, "FirstPickup")
	if def.Special then
		services.QuestService.specialFound(player, def)
		services.Remotes.Announce:FireAllClients(string.format("%s found the %s! (+$%s)", player.DisplayName, def.Name, Format.short(value)), LootConfig.Rarities[def.Rarity].Color)
		services.Remotes.RareEvent:FireAllClients("Gone", { depth = entry.depth, item = def.Id, by = player.DisplayName })
	end
	services.Remotes.Collected:FireAllClients(player.UserId, entry.id, def.Id, entry.position, value)
	if carried.Slots >= stats.Capacity then
		services.DataService.bump(player, "FullStacks", 1)
		services.Analytics.funnel(player, "FirstFullStack")
		services.Remotes.Popup:FireClient(player, "StackFull", { capacity = stats.Capacity })
	end
	LootService.sendInventory(player)
	return true, value
end

-- Magnet and Auto-Collect -------------------------------------------------------------------

local function stepMagnet(dt)
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		local root = services.PlayerService.root(player)
		local data = services.DataService.getProfile(player)
		if root and data then
			local stats = services.DataService.stats(player)
			local depth = services.PlayerService.depthOf(player)
			local list = if depth <= data.HighestDepth then byDepth[depth] else nil
			local rootPos = root.CFrame.Position
			local now = os.clock()
			if list and stats.MagnetRadius > 0 and data.Carried.Slots < stats.Capacity then
				-- The nearest MagnetMaxPull free items in range slide in (spatial hash lookup).
				local candidates = {}
				for _, id in ipairs(hashes[depth]:query(rootPos, stats.MagnetRadius)) do
					local entry = loot[id]
					local offset = rootPos - entry.position
					local dist = Vector3.new(offset.X, 0, offset.Z).Magnitude
					local free = not entry.pulledBy or entry.pulledBy == player or now - (entry.pulledAt or 0) > 3
					if free and dist > 2.2 then
						table.insert(candidates, { entry = entry, dist = dist })
					end
				end
				table.sort(candidates, function(a, b)
					return a.dist < b.dist
				end)
				for i = 1, math.min(#candidates, GameConfig.MagnetMaxPull) do
					local entry = candidates[i].entry
					local offset = rootPos - entry.position
					local flat = Vector3.new(offset.X, 0, offset.Z)
					do
						entry.pulledBy = player
						entry.pulledAt = now
						local step = math.min(flat.Magnitude - 2, stats.MagnetSpeed * dt)
						-- Items glide toward the player's feet (the pool floor is sloped).
						local floorY = rootPos.Y - 2.6
						local y = entry.position.Y + (floorY - entry.position.Y) * math.min(1, dt * 4)
						local newPos = Vector3.new(entry.position.X, y, entry.position.Z) + flat.Unit * step
						entry.position = newPos
						entry.base = CFrame.new(newPos) * entry.base.Rotation
						hashes[depth]:move(entry.id, newPos)
						if entry.model then
							entry.model:PivotTo(entry.base * pivotOffset[entry.def.Id])
						end
					end
				end
			end
			if list and stats.AutoRadius > 0 and data.Carried.Slots < stats.Capacity and (not lastAuto[player] or now - lastAuto[player] >= stats.AutoInterval) then
				local bestId = hashes[depth]:nearest(rootPos, stats.AutoRadius, function(id)
					local entry = loot[id]
					return not entry.pulledBy or entry.pulledBy == player or now - (entry.pulledAt or 0) >= 3
				end)
				local best = bestId and loot[bestId]
				if best then
					LootService.collect(player, best.id, { auto = true })
				end
			end
		end
	end
end

-- Rare loot events --------------------------------------------------------------------------

function LootService.spawnRare(depth)
	local def = LootConfig.SpecialByDepth[depth]
	local record = world.depths[depth]
	if not def or not record or rare.entry then
		return nil
	end
	local base = record.rarePoint
	LootService.activate(depth)
	local entry = register(depth, def, nil, base.Position, base)
	entry.expires = os.clock() + GameConfig.RareEvent.Lifetime
	rare.entry = entry
	rare.depthAt[depth] = os.clock() + GameConfig.RareEvent.DepthCooldown
	services.Remotes.RareEvent:FireAllClients("Spawn", { depth = depth, item = def.Id, name = def.Name, rarity = def.Rarity, position = base.Position, lifetime = GameConfig.RareEvent.Lifetime })
	return entry
end

local function stepRare(now)
	local cfg = GameConfig.RareEvent
	if rare.entry and rare.entry.expires and now >= rare.entry.expires then
		local depth, item = rare.entry.depth, rare.entry.def.Id
		unregister(rare.entry)
		services.Remotes.RareEvent:FireAllClients("Gone", { depth = depth, item = item })
	end
	if now < rare.nextAt or rare.entry then
		return
	end
	rare.nextAt = now + rng:NextNumber(cfg.MinGap, cfg.MaxGap)
	local candidates = {}
	for depth in pairs(world.depths) do
		if (not rare.depthAt[depth] or now >= rare.depthAt[depth]) and #services.PlayerService.playersOnDepth(depth) > 0 then
			table.insert(candidates, depth)
		end
	end
	if #candidates > 0 then
		LootService.spawnRare(candidates[rng:NextInteger(1, #candidates)])
	end
end

-- Main step (Heartbeat from Main.server) ----------------------------------------------------

function LootService.step(dt)
	magnetClock += dt
	if magnetClock < GameConfig.MagnetTick then
		return
	end
	local tickDt = math.min(magnetClock, 0.5)
	magnetClock = 0
	local now = os.clock()
	stepMagnet(tickDt)
	stepFill(now)
	stepRare(now)
end

function LootService.items(depth)
	return byDepth[depth]
end

function LootService.get(id)
	return loot[id]
end

function LootService.count(depth)
	return counts[depth] or 0
end

-- Nearest pickup on a depth within radius of a position (spatial hash).
function LootService.nearest(depth, position, radius, filter)
	local id = hashes[depth] and hashes[depth]:nearest(position, radius, filter and function(key)
		return filter(loot[key])
	end)
	return id and loot[id]
end

-- The pickup currently on a fill slot (nil while it waits to refill).
function LootService.slot(depth, index)
	return slotEntry[depth] and slotEntry[depth][index]
end

function LootService.queued(depth)
	return state[depth] and state[depth].queue:size() or 0
end

function LootService.rareEntry()
	return rare.entry
end

function LootService.onProfileLoaded(player)
	local data = services.DataService.getProfile(player)
	LootService.activate(data and data.CurrentDepth or 1, true) -- the pool is full on arrival
	LootService.sendInventory(player)
end

function LootService.onPlayerRemoving(player)
	lastPickup[player] = nil
	lastAuto[player] = nil
	lastFullNotice[player] = nil
	for _, entry in pairs(loot) do
		if entry.pulledBy == player then
			entry.pulledBy = nil
		end
	end
end

function LootService.start()
	for depth in pairs(world.depths) do
		showStandin(depth, true) -- empty depths show their stand-in until someone arrives
	end
	rare.nextAt = os.clock() + GameConfig.RareEvent.MinGap
	services.Remotes.Collect.OnServerEvent:Connect(function(player, id)
		LootService.collect(player, id)
	end)
end

return LootService
