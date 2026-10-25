--[[
	ScrapService - the authoritative registry of every scrap object lying in the world.

	* One central registry (no per-object scripts or loops) plus a spatial hash grid, so a
	  magnet query only looks at the few cells around the player.
	* Spawning refills each zone toward its ZoneConfig.MaxScrap (and the global cap in
	  PerformanceConfig), picking a weighted region, then a weighted scrap entry.
	* Claims are atomic: claim() succeeds for exactly one player; release() puts an object
	  back; consume() removes it for good. Rewards are handled by MagnetService.
	* World models are anchored, non-colliding and non-queryable. Clients animate the
	  flight locally; the server never moves a claimed object.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local ScrapConfig = require(Shared.Config.ScrapConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local ScrapModels = require(Shared.ScrapModels)

local ScrapService = {}

local services
local world
local items = {} -- [id] = item
local grid = {} -- [cellKey] = { [id] = item }
local zoneCounts = {}
local totalCount = 0
local nextId = 0
local rng = Random.new()
local CELL = PerformanceConfig.GridCell
local DESPAWN_AFTER = 600 -- unclaimed scrap is recycled after this many seconds

ScrapService.stormMultiplier = 1
ScrapService.stormShardChance = 0

local zoneEntries = {} -- [zoneId] = { defs }
local stormEntries = {}

function ScrapService.init(registry)
	services = registry
	for _, def in ipairs(ScrapConfig.List) do
		if def.StormOnly then
			table.insert(stormEntries, def)
		else
			zoneEntries[def.Zone] = zoneEntries[def.Zone] or {}
			table.insert(zoneEntries[def.Zone], def)
		end
	end
end

function ScrapService.setWorld(newWorld)
	world = newWorld
end

local function cellKey(x, z)
	return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

local function gridAdd(item)
	local k = cellKey(item.position.X, item.position.Z)
	item.cell = k
	grid[k] = grid[k] or {}
	grid[k][item.id] = item
end

local function gridRemove(item)
	local cell = item.cell and grid[item.cell]
	if cell then
		cell[item.id] = nil
		if next(cell) == nil then
			grid[item.cell] = nil
		end
	end
end

function ScrapService.get(id)
	return items[id]
end

function ScrapService.count(zoneId)
	if zoneId then
		return zoneCounts[zoneId] or 0
	end
	return totalCount
end

function ScrapService.all()
	return items
end

-- Picks a weighted entry. `boost` multiplies the weight of rare-or-better entries.
local function pickDef(list, maxRank, boost)
	local total = 0
	local weights = {}
	for i, def in ipairs(list) do
		local w = 0
		if not maxRank or ScrapConfig.rank(def) <= maxRank then
			w = def.Weight
			if boost and ScrapConfig.rank(def) >= 3 then
				w *= boost
			end
		end
		weights[i] = w
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for i, def in ipairs(list) do
		roll -= weights[i]
		if roll <= 0 then
			return def
		end
	end
	return list[#list]
end

local function pickRegion(regions)
	local total = 0
	for _, r in ipairs(regions) do
		total += r.weight
	end
	local roll = rng:NextNumber() * total
	for _, r in ipairs(regions) do
		roll -= r.weight
		if roll <= 0 then
			return r
		end
	end
	return regions[#regions]
end

local function blocked(x, z)
	for _, b in ipairs(world.blockers or {}) do
		local dx, dz = x - b.x, z - b.z
		if dx * dx + dz * dz < b.r * b.r then
			return true
		end
	end
	return false
end

-- Creates one scrap object. opts: { def = scrapDef, position = Vector3 } (tests and events).
function ScrapService.spawn(zoneId, opts)
	opts = opts or {}
	if totalCount >= PerformanceConfig.MaxActiveScrapTotal then
		return nil
	end
	local regions = world and world.regions[zoneId]
	if not regions or #regions == 0 then
		return nil
	end
	local def, position = opts.def, opts.position
	if not position then
		for _ = 1, 8 do
			local region = pickRegion(regions)
			local x = region.cx + (rng:NextNumber() - 0.5) * region.w
			local z = region.cz + (rng:NextNumber() - 0.5) * region.h
			if not blocked(x, z) then
				position = Vector3.new(x, world.heightAt(x, z), z)
				if not def then
					if ScrapService.stormShardChance > 0 and rng:NextNumber() < ScrapService.stormShardChance then
						def = pickDef(stormEntries)
					else
						def = pickDef(zoneEntries[zoneId] or {}, region.maxRank, region.rareBoost)
					end
				end
				break
			end
		end
	end
	if not def or not position then
		return nil
	end
	nextId += 1
	local id = nextId
	local cf = CFrame.new(position + Vector3.new(0, def.Size * 0.32, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model = ScrapModels.build(def.Id, cf)
	model.Name = tostring(id)
	model:SetAttribute("ScrapId", def.Id)
	model:SetAttribute("Zone", zoneId)
	if ScrapConfig.rank(def) >= 4 then
		-- Epic / legendary: a small glint so they read as special (no lights, no walls).
		local glint = Instance.new("ParticleEmitter")
		glint.Name = "Glint"
		glint.Rate = if def.Rarity == "Legendary" then 6 else 2
		glint.Lifetime = NumberRange.new(0.6, 1.2)
		glint.Speed = NumberRange.new(0.5, 1.5)
		glint.Size = NumberSequence.new(0.25, 0)
		glint.LightEmission = 1
		local c = ScrapConfig.Rarities[def.Rarity].Color
		glint.Color = ColorSequence.new(Color3.fromRGB(c[1], c[2], c[3]))
		glint.Parent = model.PrimaryPart
	end
	model.Parent = world.scrapFolder
	local item = { id = id, def = def, zone = zoneId, position = cf.Position, model = model, spawnedAt = os.clock() }
	items[id] = item
	gridAdd(item)
	zoneCounts[zoneId] = (zoneCounts[zoneId] or 0) + 1
	totalCount += 1
	if def.Rarity == "Legendary" and not opts.quiet then
		local zone = ZoneConfig.ById[zoneId]
		services.Remotes.Announce:FireAllClients(string.format("A %s surfaced somewhere in %s!", def.Name, if zone then zone.Name else zoneId), ScrapConfig.Rarities.Legendary.Color)
	end
	return item
end

-- Unclaimed objects within `radius` of `position`, nearest first.
function ScrapService.query(position, radius)
	local out = {}
	local r2 = radius * radius
	local minX, maxX = math.floor((position.X - radius) / CELL), math.floor((position.X + radius) / CELL)
	local minZ, maxZ = math.floor((position.Z - radius) / CELL), math.floor((position.Z + radius) / CELL)
	for cx = minX, maxX do
		for cz = minZ, maxZ do
			local cell = grid[cx .. ":" .. cz]
			if cell then
				for _, item in pairs(cell) do
					if not item.claimedBy then
						local d = item.position - position
						local dist2 = d.X * d.X + d.Z * d.Z + (d.Y * d.Y) * 0.25
						if dist2 <= r2 then
							item.dist2 = dist2
							table.insert(out, item)
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist2 < b.dist2
	end)
	return out
end

-- Atomic claim: only one player can hold an object.
function ScrapService.claim(item, player)
	if not item or items[item.id] ~= item or item.claimedBy then
		return false
	end
	item.claimedBy = player
	return true
end

function ScrapService.release(item)
	if item and items[item.id] == item then
		item.claimedBy = nil
		item.spawnedAt = os.clock()
	end
end

-- Removes an object for good. Returns true only the first time (no double awards).
function ScrapService.consume(item)
	if not item or items[item.id] ~= item then
		return false
	end
	items[item.id] = nil
	gridRemove(item)
	zoneCounts[item.zone] = math.max(0, (zoneCounts[item.zone] or 1) - 1)
	totalCount = math.max(0, totalCount - 1)
	if item.model then
		item.model:Destroy()
		item.model = nil
	end
	return true
end

function ScrapService.releaseAllFor(player)
	for _, item in pairs(items) do
		if item.claimedBy == player then
			ScrapService.release(item)
		end
	end
end

-- One refill step for every built zone (called once per second).
function ScrapService.refill()
	for _, zone in ipairs(ZoneConfig.List) do
		if zone.Built and world.regions[zone.Id] then
			local target = math.floor(zone.MaxScrap * math.min(1.6, ScrapService.stormMultiplier))
			local missing = target - (zoneCounts[zone.Id] or 0)
			local rate = math.ceil(PerformanceConfig.SpawnPerSecond * ScrapService.stormMultiplier)
			for _ = 1, math.min(missing, rate) do
				if not ScrapService.spawn(zone.Id) then
					break
				end
			end
		end
	end
end

-- Recycles old unclaimed objects (keeps spots fresh) and trims zones above target.
function ScrapService.recycle()
	local now = os.clock()
	local over = {}
	for _, zone in ipairs(ZoneConfig.List) do
		if zone.Built then
			over[zone.Id] = (zoneCounts[zone.Id] or 0) - math.floor(zone.MaxScrap * math.min(1.6, ScrapService.stormMultiplier))
		end
	end
	for _, item in pairs(items) do
		if not item.claimedBy then
			if (over[item.zone] or 0) > 0 and item.def.StormOnly then
				over[item.zone] -= 1
				ScrapService.consume(item)
			elseif now - item.spawnedAt > DESPAWN_AFTER and ScrapConfig.rank(item.def) < 5 then
				ScrapService.consume(item)
			end
		end
	end
end

function ScrapService.start()
	-- Fill the yard right away so the first pull is instant.
	for _ = 1, 40 do
		ScrapService.refill()
	end
	task.spawn(function()
		local t = 0
		while true do
			task.wait(1)
			t += 1
			ScrapService.refill()
			if t % 15 == 0 then
				ScrapService.recycle()
			end
		end
	end)
end

function ScrapService.onPlayerRemoving(player)
	ScrapService.releaseAllFor(player)
end

return ScrapService
