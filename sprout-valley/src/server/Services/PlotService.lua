--[[
	PlotService - garden plots: ownership, planting, real-time growth (online ticks +
	offline catch-up from saved timestamps), harvesting, gear, plot expansion, Growth Skip,
	the trowel, and the crop models in the world.

	Every action comes from the TileAction / MovePlant / ExpandPlot remotes and is validated:
	types, integer tile index in range, the tile is unlocked, the player is near the tile,
	inventory counts, and a token-bucket rate limit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local CropConfig = require(Shared.Config.CropConfig)
local GearConfig = require(Shared.Config.GearConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Economy = require(Shared.Economy)
local Growth = require(Shared.Growth)
local Format = require(Shared.Format)
local CropModels = require(Shared.CropModels)

local VillageBuilder = require(script.Parent.VillageBuilder)
local RateLimit = require(script.Parent.RateLimit)

local PlotService = {}

local PLOT = GameConfig.Plot
local TILE_COUNT = PLOT.Cols * PLOT.Rows

local services
local plots = {}
local ownerPlot = {} -- [player] = plot
local wateredAt = {} -- [player] = { [index] = os.clock() }
local pendingSkip = {} -- [player] = tile index to ripen when a Growth Skip purchase lands
local limiter = RateLimit.new(10, 24)
local rng = Random.new()

function PlotService.init(registry)
	services = registry
end

function PlotService.setVillage(village)
	plots = village.plots
end

local function key(index)
	return tostring(index)
end

local function profileOf(player)
	return services.DataService.getProfile(player)
end

local function validIndex(index)
	return type(index) == "number" and index == index and index % 1 == 0 and index >= 1 and index <= TILE_COUNT
end

function PlotService.plotOf(player)
	return ownerPlot[player]
end

function PlotService.plots()
	return plots
end

function PlotService.unlockedRows(player)
	local profile = profileOf(player)
	if not profile then
		return 0
	end
	return Economy.unlockedRows(profile.Plot.Rows, services.ShopService.owns(player, "VIP"), PLOT)
end

function PlotService.isUnlocked(player, index)
	local _, row = Growth.toColRow(index, PLOT.Cols)
	return row <= PlotService.unlockedRows(player)
end

function PlotService.tileCFrame(plot, index)
	local p = VillageBuilder.tileLocal(index)
	return plot.cf * CFrame.new(p.X, p.Y, p.Z)
end

local function growthRate(player, profile, index, now)
	local rate = services.WeatherService.growthMultiplier()
	rate *= Growth.sprinklerMultiplier(index, profile.Plot.Sprinklers, now, GearConfig, PLOT.Cols)
	if services.ShopService.owns(player, "AutoWater") then
		rate *= ShopConfig.AutoWaterGrowth
	end
	return rate
end

function PlotService.plotInfo(player)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	if not profile then
		return {}
	end
	local vip = services.ShopService.owns(player, "VIP")
	local canExpand = Economy.canExpand(profile.Plot.Rows, vip, PLOT)
	local sprinklers = {}
	local now = os.time()
	for _, s in ipairs(profile.Plot.Sprinklers) do
		if s.e > now then
			table.insert(sprinklers, { index = s.i, kind = s.k, secondsLeft = s.e - now })
		end
	end
	local planted = 0
	for _ in pairs(profile.Plot.Plants) do
		planted += 1
	end
	return {
		id = plot and plot.id,
		rows = PlotService.unlockedRows(player),
		maxRows = PLOT.Rows,
		cols = PLOT.Cols,
		purchased = profile.Plot.Rows,
		expandCost = if canExpand then Economy.expansionCost(profile.Plot.Rows, PLOT) else nil,
		sprinklers = sprinklers,
		planted = planted,
	}
end

---------------------------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------------------------

local function signature(plant, stage)
	return string.format("%d|%s|%s|%s", stage, table.concat(plant.m or {}, ","), plant.v or "", if plant.lu then "L" else "")
end

local function setAttributes(model, plant, crop, rate)
	model:SetAttribute("Progress", math.floor(Growth.progress(plant, crop) * 100) / 100)
	model:SetAttribute("Remaining", math.ceil(Growth.remaining(plant, crop, rate)))
	model:SetAttribute("Rate", math.floor(rate * 100) / 100)
end

function PlotService.render(plot, index, plant, rate)
	local existing = plot.models[index]
	if existing then
		existing.model:Destroy()
		plot.models[index] = nil
	end
	if not plant then
		return nil
	end
	local crop = CropConfig.ById[plant.c]
	local stage = Growth.stage(plant, crop)
	local model = CropModels.build(crop, stage, PlotService.tileCFrame(plot, index), {
		mutations = plant.m,
		variant = plant.v,
		lucky = plant.lu,
		seed = plot.id * 1000 + index,
	})
	model:SetAttribute("PlotId", plot.id)
	model:SetAttribute("TileIndex", index)
	model:SetAttribute("Crop", crop.Id)
	model:SetAttribute("Stage", stage)
	model:SetAttribute("Mutations", table.concat(plant.m or {}, ","))
	model:SetAttribute("Variant", plant.v or "")
	model:SetAttribute("Lucky", plant.lu == true)
	model:SetAttribute("Harvests", plant.h or 0)
	setAttributes(model, plant, crop, rate or 1)
	model.Parent = plot.crops
	plot.models[index] = { model = model, sig = signature(plant, stage) }
	return model
end

local function buildSprinkler(plot, s)
	local def = GearConfig.Gear[s.k]
	local cf = PlotService.tileCFrame(plot, s.i)
	local m = Instance.new("Model")
	m.Name = s.k
	local color = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
	local function p(props)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do
			part[k] = v
		end
		part.Parent = m
		return part
	end
	p({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.2, 1.2), CFrame = cf * CFrame.new(1.3, 0.15, 1.3) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(190, 190, 200), Material = Enum.Material.Metal })
	p({ Name = "Pole", Size = Vector3.new(0.2, 2.2, 0.2), CFrame = cf * CFrame.new(1.3, 1.2, 1.3), Color = Color3.fromRGB(170, 170, 180), Material = Enum.Material.Metal })
	local head = p({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = cf * CFrame.new(1.3, 2.4, 1.3), Color = color, Material = Enum.Material.SmoothPlastic })
	local reach = (def.Radius * 2 + 1) * PLOT.TileSize
	local ring = p({ Name = "Area", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, reach, reach), CFrame = cf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = color, Material = Enum.Material.Neon, Transparency = 0.85 })
	ring.CastShadow = false
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(Color3.fromRGB(190, 230, 255))
	spray.Rate = 25
	spray.Lifetime = NumberRange.new(0.7, 1.1)
	spray.Speed = NumberRange.new(4, 7)
	spray.SpreadAngle = Vector2.new(70, 70)
	spray.Acceleration = Vector3.new(0, -14, 0)
	spray.Size = NumberSequence.new(0.22)
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = head
	m:SetAttribute("Expires", s.e)
	m:SetAttribute("TileIndex", s.i)
	m.Parent = plot.extras
	return m
end

function PlotService.renderSprinklers(plot, profile)
	for _, m in ipairs(plot.sprinklerModels) do
		m:Destroy()
	end
	plot.sprinklerModels = {}
	if not profile then
		return
	end
	for _, s in ipairs(profile.Plot.Sprinklers) do
		table.insert(plot.sprinklerModels, buildSprinkler(plot, s))
	end
end

local function setSign(plot, text)
	for _, label in ipairs(plot.signLabels) do
		label.Text = text
	end
end

function PlotService.refreshTiles(player)
	local plot = ownerPlot[player]
	if not plot then
		return
	end
	local rows = PlotService.unlockedRows(player)
	for index, tile in pairs(plot.tiles) do
		local _, row = Growth.toColRow(index, PLOT.Cols)
		VillageBuilder.setTileLocked(tile, row > rows)
	end
	services.DataService.sendProfile(player)
end

---------------------------------------------------------------------------------------------
-- Ownership
---------------------------------------------------------------------------------------------

function PlotService.assign(player)
	if ownerPlot[player] then
		return ownerPlot[player]
	end
	local profile = profileOf(player)
	if not profile then
		return nil
	end
	local plot
	for _, p in ipairs(plots) do
		if not p.owner then
			plot = p
			break
		end
	end
	if not plot then
		services.Remotes.Notify:FireClient(player, "Every plot is taken! You can still visit gardens.", "warn")
		return nil
	end
	plot.owner = player
	ownerPlot[player] = plot
	player:SetAttribute("SV_Plot", plot.id)
	setSign(plot, player.DisplayName .. "'s Garden")

	-- Offline growth since the last save.
	local now = os.time()
	local updated = profile.Plot.Updated or 0
	local ripened = 0
	if updated > 0 and now > updated then
		local rate = if services.ShopService.owns(player, "AutoWater") then ShopConfig.AutoWaterGrowth else 1
		for _, plant in pairs(profile.Plot.Plants) do
			local crop = CropConfig.ById[plant.c]
			local wasRipe = Growth.isRipe(plant, crop)
			Growth.offline(plant, crop, now - updated, rate, GameConfig.OfflineGrowthCap)
			if not wasRipe and Growth.isRipe(plant, crop) then
				ripened += 1
			end
		end
	end
	profile.Plot.Updated = now
	profile.Plot.Sprinklers = Growth.pruneSprinklers(profile.Plot.Sprinklers, now)

	PlotService.refreshTiles(player)
	for k, plant in pairs(profile.Plot.Plants) do
		local index = tonumber(k)
		if index and validIndex(index) then
			PlotService.render(plot, index, plant, growthRate(player, profile, index, now))
		end
	end
	PlotService.renderSprinklers(plot, profile)
	if ripened > 0 then
		services.Remotes.Notify:FireClient(player, string.format("Welcome back! %d plant%s ripened while you were away.", ripened, if ripened == 1 then "" else "s"), "good")
	end
	return plot
end

function PlotService.release(player)
	local plot = ownerPlot[player]
	ownerPlot[player] = nil
	wateredAt[player] = nil
	pendingSkip[player] = nil
	limiter:forget(player)
	if not plot then
		return
	end
	for index in pairs(plot.models) do
		PlotService.render(plot, index, nil)
	end
	PlotService.renderSprinklers(plot, nil)
	for _, tile in pairs(plot.tiles) do
		VillageBuilder.setTileLocked(tile, true)
	end
	setSign(plot, "Empty Plot")
	plot.owner = nil
end

function PlotService.onProfileLoaded(player)
	PlotService.assign(player)
end

function PlotService.onPlayerRemoving(player)
	PlotService.release(player)
end

-- Called by DataService before every save: growth is integrated up to now.
function PlotService.flush(player)
	local profile = profileOf(player)
	if profile and ownerPlot[player] then
		profile.Plot.Updated = os.time()
	end
end

---------------------------------------------------------------------------------------------
-- Growth tick
---------------------------------------------------------------------------------------------

function PlotService.tick(dt)
	local now = os.time()
	for player, plot in pairs(ownerPlot) do
		local profile = profileOf(player)
		if profile then
			local before = #profile.Plot.Sprinklers
			profile.Plot.Sprinklers = Growth.pruneSprinklers(profile.Plot.Sprinklers, now)
			if #profile.Plot.Sprinklers ~= before then
				PlotService.renderSprinklers(plot, profile)
			end
			for k, plant in pairs(profile.Plot.Plants) do
				local index = tonumber(k)
				local crop = CropConfig.ById[plant.c]
				if index and crop then
					local rate = growthRate(player, profile, index, now)
					local wasRipe = Growth.isRipe(plant, crop)
					Growth.advance(plant, crop, dt * rate)
					local stage = Growth.stage(plant, crop)
					local entry = plot.models[index]
					if not entry or entry.sig ~= signature(plant, stage) then
						PlotService.render(plot, index, plant, rate)
					else
						setAttributes(entry.model, plant, crop, rate)
					end
					if not wasRipe and Growth.isRipe(plant, crop) then
						services.Remotes.Effect:FireClient(player, "Ripe", { index = index, crop = crop.Id })
					end
				end
			end
			profile.Plot.Updated = now
		end
	end
end

-- fn(player, plot, index, plant, crop) for every plant at the Full stage or later.
function PlotService.forEachMature(fn)
	for player, plot in pairs(ownerPlot) do
		local profile = profileOf(player)
		if profile then
			for k, plant in pairs(profile.Plot.Plants) do
				local crop = CropConfig.ById[plant.c]
				local index = tonumber(k)
				if crop and index and Growth.stage(plant, crop) >= 3 then
					fn(player, plot, index, plant, crop)
				end
			end
		end
	end
end

function PlotService.addMutation(player, index, name)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	local plant = profile and profile.Plot.Plants[key(index)]
	if not plant or not plot then
		return false
	end
	plant.m = plant.m or {}
	if not Economy.addMutation(plant.m, name, MutationConfig) then
		return false
	end
	PlotService.render(plot, index, plant)
	local final = plant.m[#plant.m]
	services.Remotes.Effect:FireAllClients("Mutation", { position = PlotService.tileCFrame(plot, index).Position, mutation = final, owner = player.UserId })
	return true
end

function PlotService.setVariant(player, index, variant)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	local plant = profile and profile.Plot.Plants[key(index)]
	if not plant or not plot or plant.v then
		return false
	end
	plant.v = variant
	PlotService.render(plot, index, plant)
	services.Remotes.Effect:FireAllClients("Mutation", { position = PlotService.tileCFrame(plot, index).Position, mutation = variant, owner = player.UserId })
	return true
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------

local function notify(player, text, kind)
	services.Remotes.Notify:FireClient(player, text, kind or "info")
end

local function nearTile(player, plot, index)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.CFrame.Position - PlotService.tileCFrame(plot, index).Position).Magnitude <= GameConfig.InteractRange
end

local function luckyPass(player)
	return services.ShopService.owns(player, "LuckyGardener")
end

function PlotService.plant(player, index, cropId)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	local crop = type(cropId) == "string" and CropConfig.ById[cropId]
	if not profile or not plot or not crop then
		return false
	end
	if profile.Plot.Plants[key(index)] then
		return false
	end
	if (profile.Seeds[crop.Id] or 0) <= 0 then
		notify(player, "You have no " .. crop.Name .. " seeds. Buy some at the Seed Shop!", "warn")
		return false
	end
	profile.Seeds[crop.Id] -= 1
	if profile.Seeds[crop.Id] <= 0 then
		profile.Seeds[crop.Id] = nil
	end
	local plant = { c = crop.Id, g = 0, m = {}, h = 0, v = Economy.rollVariant(rng, luckyPass(player), MutationConfig) }
	profile.Plot.Plants[key(index)] = plant
	profile.Stats.Planted += 1
	services.DataService.markDirty(player)
	PlotService.render(plot, index, plant, growthRate(player, profile, index, os.time()))
	services.Remotes.Effect:FireClient(player, "Plant", { position = PlotService.tileCFrame(plot, index).Position, crop = crop.Id, variant = plant.v })
	if plant.v then
		notify(player, string.format("Lucky! Your %s sprouted %s!", crop.Name, plant.v), "good")
	end
	services.RewardsService.event(player, "Plant", 1)
	services.DataService.sendProfile(player)
	return true
end

local function describe(item, crop, huge)
	local parts = {}
	if huge then
		table.insert(parts, "HUGE")
	end
	if item.v then
		table.insert(parts, item.v)
	end
	for _, m in ipairs(item.m) do
		table.insert(parts, m)
	end
	table.insert(parts, crop.Name)
	return table.concat(parts, " ")
end

function PlotService.harvest(player, index)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	local plant = profile and profile.Plot.Plants[key(index)]
	if not plant or not plot then
		return false
	end
	local crop = CropConfig.ById[plant.c]
	if not Growth.isRipe(plant, crop) then
		return false
	end
	if #profile.Backpack >= services.DataService.backpackCapacity(player) then
		notify(player, "Your backpack is full! Sell at the Sell Stand.", "warn")
		services.Remotes.Effect:FireClient(player, "BackpackFull", {})
		return false
	end
	local kg, huge = Economy.rollWeight(crop, rng, GameConfig.HugeChance)
	local item = { id = profile.NextItemId, c = crop.Id, kg = kg, m = table.clone(plant.m or {}), v = plant.v }
	profile.NextItemId += 1
	table.insert(profile.Backpack, item)
	local value = Economy.fruitValue(crop, kg, item.m, item.v, MutationConfig)
	local stats = profile.Stats
	stats.Harvests += 1
	local mutated = #item.m > 0 or item.v ~= nil
	if mutated then
		stats.Mutations += 1
	end
	stats.BestFruit = math.max(stats.BestFruit, value)

	local position = PlotService.tileCFrame(plot, index).Position
	if Growth.harvest(plant, crop) then
		plant.v = Economy.rollVariant(rng, luckyPass(player), MutationConfig)
		PlotService.render(plot, index, plant, growthRate(player, profile, index, os.time()))
	else
		profile.Plot.Plants[key(index)] = nil
		PlotService.render(plot, index, nil)
	end
	services.DataService.markDirty(player)
	services.Remotes.Effect:FireClient(player, "Harvest", {
		position = position,
		crop = crop.Id,
		kg = kg,
		value = value,
		huge = huge,
		mutations = item.m,
		variant = item.v,
	})
	services.RewardsService.event(player, "Harvest", 1)
	if mutated then
		services.RewardsService.event(player, "Mutation", 1)
	end

	local rank = RarityConfig.Tiers[crop.Rarity].Rank
	if rank >= RarityConfig.AnnounceHarvestRank or (huge and rank >= 3) or value >= crop.Value * GameConfig.AnnounceValueMultiple then
		services.Remotes.Announce:FireAllClients(
			string.format("%s harvested a %s (%s) worth %s Coins!", player.DisplayName, describe(item, crop, huge), Format.kg(kg), Format.coins(value)),
			RarityConfig.Tiers[crop.Rarity].Color
		)
	end
	services.DataService.sendProfile(player)
	return true, item
end

local function useGear(player, plot, profile, index, gearId)
	local def = GearConfig.Gear[gearId]
	if not def or gearId == "Trowel" then
		return false
	end
	if (profile.Gear[gearId] or 0) <= 0 then
		notify(player, "You're out of " .. def.Name .. ". Restock at the Gear Shop!", "warn")
		return false
	end
	local plant = profile.Plot.Plants[key(index)]
	local crop = plant and CropConfig.ById[plant.c]
	local position = PlotService.tileCFrame(plot, index).Position

	if gearId == "WateringCan" then
		if not plant then
			return false
		end
		if Growth.isRipe(plant, crop) then
			return PlotService.harvest(player, index)
		end
		wateredAt[player] = wateredAt[player] or {}
		local last = wateredAt[player][index]
		if last and os.clock() - last < def.Cooldown then
			notify(player, "That plant was just watered. Give it a moment!", "info")
			return false
		end
		wateredAt[player][index] = os.clock()
		profile.Gear[gearId] -= 1
		Growth.advance(plant, crop, Growth.waterAdvance(crop, def))
		PlotService.render(plot, index, plant, growthRate(player, profile, index, os.time()))
		services.Remotes.Effect:FireAllClients("Water", { position = position })
		if Growth.stage(plant, crop) >= 3 and rng:NextNumber() < def.WetChance then
			PlotService.addMutation(player, index, "Wet")
		end
		services.RewardsService.event(player, "Water", 1)
	elseif def.Radius then
		local now = os.time()
		profile.Plot.Sprinklers = Growth.pruneSprinklers(profile.Plot.Sprinklers, now)
		if #profile.Plot.Sprinklers >= GearConfig.MaxSprinklers then
			notify(player, string.format("You can only run %d sprinklers at once.", GearConfig.MaxSprinklers), "warn")
			return false
		end
		for _, s in ipairs(profile.Plot.Sprinklers) do
			if s.i == index then
				notify(player, "There's already a sprinkler on that tile.", "info")
				return false
			end
		end
		profile.Gear[gearId] -= 1
		table.insert(profile.Plot.Sprinklers, { i = index, k = gearId, e = now + def.Duration })
		PlotService.renderSprinklers(plot, profile)
		services.Remotes.Effect:FireAllClients("Sprinkler", { position = position })
		notify(player, string.format("%s placed! %s growth for %s.", def.Name, string.format("%.1fx", def.Growth), Format.duration(def.Duration)), "good")
	elseif gearId == "LuckyFertilizer" then
		if not plant or plant.lu then
			notify(player, if plant then "This plant is already fertilized." else "Use Lucky Fertilizer on a plant.", "info")
			return false
		end
		profile.Gear[gearId] -= 1
		plant.lu = true
		PlotService.render(plot, index, plant)
		services.Remotes.Effect:FireAllClients("Lucky", { position = position })
	else
		return false
	end
	if profile.Gear[gearId] <= 0 then
		profile.Gear[gearId] = nil
	end
	services.DataService.markDirty(player)
	services.DataService.sendProfile(player)
	return true
end

function PlotService.useSkip(player, index)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	local plant = profile and profile.Plot.Plants[key(index)]
	if not plant or not plot then
		return false
	end
	local crop = CropConfig.ById[plant.c]
	if Growth.isRipe(plant, crop) then
		notify(player, "That plant is already ripe!", "info")
		return false
	end
	if (profile.Tokens.GrowthSkip or 0) <= 0 then
		pendingSkip[player] = index
		services.ShopService.buy(player, "GrowthSkip")
		return false
	end
	profile.Tokens.GrowthSkip -= 1
	plant.g = crop.GrowTime
	PlotService.render(plot, index, plant)
	services.DataService.markDirty(player)
	services.Remotes.Effect:FireAllClients("Skip", { position = PlotService.tileCFrame(plot, index).Position })
	notify(player, crop.Name .. " is ripe! Tap it to harvest.", "good")
	services.DataService.sendProfile(player)
	return true
end

-- A Growth Skip purchase landed: use it on the plant the player picked, if still valid.
function PlotService.applyPendingSkip(player)
	local index = pendingSkip[player]
	pendingSkip[player] = nil
	if index and PlotService.useSkip(player, index) then
		return true
	end
	notify(player, "Growth Skip saved! Pick the Growth Skip tool and tap a growing plant.", "good")
	return false
end

function PlotService.move(player, from, to)
	local profile = profileOf(player)
	local plot = ownerPlot[player]
	if not profile or not plot or from == to then
		return false
	end
	if (profile.Gear.Trowel or 0) <= 0 then
		notify(player, "You need a Trowel from the Gear Shop.", "warn")
		return false
	end
	local plants = profile.Plot.Plants
	local plant = plants[key(from)]
	if not plant or plants[key(to)] then
		return false
	end
	plants[key(to)] = plant
	plants[key(from)] = nil
	PlotService.render(plot, from, nil)
	PlotService.render(plot, to, plant, growthRate(player, profile, to, os.time()))
	services.DataService.markDirty(player)
	services.Remotes.Effect:FireClient(player, "Plant", { position = PlotService.tileCFrame(plot, to).Position, crop = plant.c })
	return true
end

function PlotService.expand(player)
	local profile = profileOf(player)
	if not profile or not ownerPlot[player] then
		return false
	end
	local vip = services.ShopService.owns(player, "VIP")
	if not Economy.canExpand(profile.Plot.Rows, vip, PLOT) then
		notify(player, "Your garden is already as big as it gets!", "info")
		return false
	end
	local cost = Economy.expansionCost(profile.Plot.Rows, PLOT)
	if not services.DataService.spendCoins(player, cost) then
		notify(player, string.format("You need %s Coins to expand.", Format.coins(cost)), "warn")
		return false
	end
	profile.Plot.Rows += 1
	PlotService.refreshTiles(player)
	services.Remotes.Effect:FireClient(player, "Expand", { rows = PlotService.unlockedRows(player) })
	notify(player, string.format("Garden expanded! +%d tiles.", PLOT.Cols), "good")
	services.DataService.sendProfile(player)
	return true
end

function PlotService.handleTileAction(player, index, toolKind, toolId)
	if not validIndex(index) or type(toolKind) ~= "string" then
		return false
	end
	if toolId ~= nil and (type(toolId) ~= "string" or #toolId > 32) then
		return false
	end
	if not limiter:allow(player) then
		return false
	end
	local plot = ownerPlot[player]
	local profile = profileOf(player)
	if not plot or not profile then
		return false
	end
	if not PlotService.isUnlocked(player, index) then
		notify(player, "Expand your garden to use this tile!", "info")
		return false
	end
	if not nearTile(player, plot, index) then
		notify(player, "Walk closer to your garden.", "info")
		return false
	end
	local plant = profile.Plot.Plants[key(index)]
	if toolKind == "skip" then
		return PlotService.useSkip(player, index)
	elseif toolKind == "gear" then
		return useGear(player, plot, profile, index, toolId)
	elseif plant and Growth.isRipe(plant, CropConfig.ById[plant.c]) then
		return PlotService.harvest(player, index)
	elseif not plant and toolKind == "seed" then
		return PlotService.plant(player, index, toolId)
	end
	return false
end

function PlotService.start()
	local remotes = services.Remotes
	remotes.TileAction.OnServerEvent:Connect(function(player, index, toolKind, toolId)
		PlotService.handleTileAction(player, index, toolKind, toolId)
	end)
	remotes.MovePlant.OnServerEvent:Connect(function(player, from, to)
		if not validIndex(from) or not validIndex(to) or not limiter:allow(player) then
			return
		end
		local plot = ownerPlot[player]
		if not plot or not PlotService.isUnlocked(player, from) or not PlotService.isUnlocked(player, to) then
			return
		end
		if nearTile(player, plot, from) and nearTile(player, plot, to) then
			PlotService.move(player, from, to)
		end
	end)
	local expandLimiter = RateLimit.new(1, 2)
	remotes.ExpandPlot.OnServerEvent:Connect(function(player)
		if expandLimiter:allow(player) then
			PlotService.expand(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		expandLimiter:forget(player)
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local ok, err = pcall(PlotService.tick, math.min(now - last, 5))
			if not ok then
				warn("[SproutValley] growth tick failed: " .. tostring(err))
			end
			last = now
		end
	end)
end

return PlotService
