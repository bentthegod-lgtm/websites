--[[
	LootService - every loose item in the vault, the carried inventory, the Cash Magnet,
	Auto-Collect and rare loot events. Everything here is server-authoritative.

	Registry: loot[id] = { id, def, depth, point, position, model, pulledBy, pulledAt,
	expires }. A claim is atomic: collect() checks and removes the entry in one go with no
	yields, so when two players reach the same bill on the same frame exactly one gets it.

	Pickup checks: profile loaded, item exists on the player's depth, distance to the item
	(collection radius + latency slack), the pickup cooldown, and carrying capacity. The
	value is fixed at pickup from the player's current stats and added to profile.Carried.

	Spawning: each depth has validated spawn points (VaultBuilder); a depth refills one item
	per RespawnInterval up to its ActiveLoot cap, rolled from LootTable with the best Rare
	Loot Luck among players on that depth. Collected models go back to a per-item pool and
	are reused. Rare loot events drop a special item next to a depth's landmark for a few
	minutes (global gap + per-depth cooldown).

	Magnet: every MagnetTick, up to MagnetMaxPull items inside the magnet radius slide toward
	the player (reserved for them while pulled). Auto-Collect picks up items inside its small
	radius at its own interval. Both run from one loop over each depth's items.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local LootConfig = require(Shared.Config.LootConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local LootTable = require(Shared.LootTable)
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
local usedPoints = {} -- [depth] = { [pointIndex] = id }
local nextSpawn = {}
local pool = {} -- [itemId] = { models }
local pivotOffset = {} -- [itemId] = base -> pivot offset
local nextId = 0
local rng = Random.new()
local lastPickup = {}
local lastAuto = {}
local lastFullNotice = {}
local magnetClock = 0
local rare = { nextAt = 0, depthAt = {}, entry = nil }

LootService.Debug = { spawned = 0, reused = 0 }

function LootService.init(registry)
	services = registry
end

function LootService.setWorld(newWorld)
	world = newWorld
	for depth in pairs(world.depths) do
		byDepth[depth] = {}
		active[depth] = {}
		counts[depth] = 0
		usedPoints[depth] = {}
		nextSpawn[depth] = 0
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
	model = LootModels.build(itemId, base, GameConfig.LootScale)
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
	if #pool[entry.def.Id] < 24 then
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
	if point then
		usedPoints[depth][point.index] = id
	end
	LootService.Debug.spawned += 1
	return entry
end

-- Spawns one normal item on a depth at a random free spawn point. Returns the entry or nil.
function LootService.spawnOne(depth, luck)
	local record = world.depths[depth]
	local def = DepthConfig.get(depth)
	if not record or counts[depth] >= def.ActiveLoot then
		return nil
	end
	local free = {}
	for _, point in ipairs(record.points) do
		if not usedPoints[depth][point.index] then
			table.insert(free, point)
		end
	end
	if #free == 0 then
		return nil
	end
	local point = free[rng:NextInteger(1, #free)]
	local item = LootTable.roll(depth, active[depth], luck or 1, rng, point.size)
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
	active[entry.depth][entry.def.Id] = math.max(0, (active[entry.depth][entry.def.Id] or 1) - 1)
	counts[entry.depth] = math.max(0, counts[entry.depth] - 1)
	if entry.point then
		usedPoints[entry.depth][entry.point.index] = nil
	end
	releaseModel(entry)
	if rare.entry == entry then
		rare.entry = nil
	end
end

function LootService.fill(depth, fraction)
	local def = DepthConfig.get(depth)
	local target = math.floor(def.ActiveLoot * (fraction or 1))
	local guard = 0
	while counts[depth] < target and guard < def.ActiveLoot * 3 do
		guard += 1
		LootService.spawnOne(depth, 1)
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
		if not lastFullNotice[player] or now - lastFullNotice[player] > 2.5 then
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
				local pulled = 0
				for _, entry in pairs(list) do
					if pulled >= GameConfig.MagnetMaxPull then
						break
					end
					local offset = rootPos - entry.position
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local free = not entry.pulledBy or entry.pulledBy == player or now - (entry.pulledAt or 0) > 3
					if free and flat.Magnitude <= stats.MagnetRadius and flat.Magnitude > 2.2 then
						pulled += 1
						entry.pulledBy = player
						entry.pulledAt = now
						local step = math.min(flat.Magnitude - 2, stats.MagnetSpeed * dt)
						local floorY = world.depths[depth].y0
						local y = entry.position.Y + (floorY - entry.position.Y) * math.min(1, dt * 4)
						local newPos = Vector3.new(entry.position.X, y, entry.position.Z) + flat.Unit * step
						entry.position = newPos
						entry.base = CFrame.new(newPos) * entry.base.Rotation
						if entry.model then
							entry.model:PivotTo(entry.base * pivotOffset[entry.def.Id])
						end
						if entry.point then
							usedPoints[depth][entry.point.index] = nil
							entry.point = nil -- it left its spawn point; the point is free again
						end
					end
				end
			end
			if list and stats.AutoRadius > 0 and (not lastAuto[player] or now - lastAuto[player] >= stats.AutoInterval) then
				local best, bestDist = nil, math.huge
				for _, entry in pairs(list) do
					local d = (entry.position - rootPos).Magnitude
					if d <= stats.AutoRadius and d < bestDist then
						best, bestDist = entry, d
					end
				end
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
	local base = record.rarePoint or record.points[1].cframe
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
	for depth, record in pairs(world.depths) do
		if now >= nextSpawn[depth] then
			nextSpawn[depth] = now + record.def.RespawnInterval
			if counts[depth] < record.def.ActiveLoot then
				LootService.spawnOne(depth, bestLuck(depth))
			end
		end
	end
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

function LootService.rareEntry()
	return rare.entry
end

function LootService.onProfileLoaded(player)
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
		LootService.fill(depth, 0.85)
	end
	rare.nextAt = os.clock() + GameConfig.RareEvent.MinGap
	services.Remotes.Collect.OnServerEvent:Connect(function(player, id)
		LootService.collect(player, id)
	end)
end

return LootService
