--[[
	BlobbyService - owned Blobbies: placement on pedestals, income, collecting, selling,
	queued deliveries and ownership transfer (stealing).

	Every owned Blobby is a profile entry Blobbies[uid] = { Species, Mutation, Slot } plus a
	runtime record with its model. Record states:
	  Walking    on its way to the pedestal (bought, delivered or gifted)
	  Placed     on the pedestal, earning, stealable / sellable
	  Carried    over a thief's head (earns nothing)
	  Returning  dropped, running back home
	The model's "State" attribute mirrors this so clients can show the right prompt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local BlobbyConfig = require(Shared.Config.BlobbyConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local BlobbyModels = require(Shared.BlobbyModels)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Layout = require(Shared.Layout)

local Mover = require(script.Parent.Mover)

local BlobbyService = {}

local services
local world
local records = {} -- [uid] = record
local owned = {} -- [player] = { [uid] = record }
local padDebounce = {}
local autoCollected = {} -- [player] = amount since the last auto-collect popup

local EMPTY_RING = Color3.fromRGB(90, 90, 100)

function BlobbyService.init(registry)
	services = registry
end

function BlobbyService.records(player)
	return owned[player] or {}
end

function BlobbyService.get(uid)
	return records[uid]
end

function BlobbyService.incomeOf(entry)
	local species = BlobbyConfig.ById[entry.Species]
	if not species then
		return 0
	end
	return Economy.blobbyIncome(species, entry.Mutation and MutationConfig.Types[entry.Mutation])
end

function BlobbyService.priceOf(speciesId, mutation)
	local species = BlobbyConfig.ById[speciesId]
	return Economy.blobbyPrice(species, mutation and MutationConfig.Types[mutation])
end

function BlobbyService.stateOf(player, uid)
	local rec = owned[player] and owned[player][uid]
	return rec and rec.state or "Placed"
end

function BlobbyService.baseIncome(player)
	local total = 0
	for _, rec in pairs(owned[player] or {}) do
		if rec.state == "Placed" then
			total += rec.income
		end
	end
	return total
end

function BlobbyService.displayName(rec)
	return (if rec.mutation then rec.mutation .. " " else "") .. rec.species.Name
end

function BlobbyService.freeSlot(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local used = {}
	for _, entry in pairs(data.Blobbies) do
		used[entry.Slot] = true
	end
	for slot = 1, services.PlayerService.slots(player) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Models
---------------------------------------------------------------------------------------------

local function pedestalOf(rec)
	local plot = services.PlotService.plotOf(rec.owner)
	return plot and plot.pedestals[rec.slot]
end

local function setState(rec, state)
	rec.state = state
	if rec.built and rec.built.model then
		rec.built.model:SetAttribute("State", state)
	end
end

local function refreshPedestal(rec)
	local pedestal = pedestalOf(rec)
	if pedestal then
		local tier = RarityConfig.Tiers[rec.species.Rarity]
		pedestal.ring.Color = if rec.state == "Carried" then Color3.fromRGB(255, 40, 40) else BlobbyModels.rgb(tier.Color)
		if rec.state == "Carried" then
			pedestal.cashLabel.Text = "STOLEN!"
			pedestal.cashLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
		elseif rec.state == "Returning" then
			pedestal.cashLabel.Text = "RUNNING HOME!"
			pedestal.cashLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
		else
			pedestal.cashLabel.Text = if rec.pending >= 1 then Format.cash(rec.pending) else ""
			pedestal.cashLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
		end
	end
end

function BlobbyService.refresh(rec)
	refreshPedestal(rec)
end

function BlobbyService.cancelMove(rec)
	if rec.built then
		Mover.cancel(rec.built.root)
	end
end

local function buildModel(rec, cframe)
	local tier = RarityConfig.Tiers[rec.species.Rarity]
	local built = BlobbyModels.build(rec.species, cframe, {
		rarity = tier,
		mutation = rec.mutation,
		mutationDef = rec.mutationDef,
		phase = (rec.uidNumber or 0) * 0.37,
	})
	rec.built = built
	local model = built.model
	model:SetAttribute("OwnerId", rec.owner.UserId)
	model:SetAttribute("Uid", rec.uid)
	model:SetAttribute("State", rec.state)
	rec.labels = BlobbyModels.nameplate(built, {
		name = rec.species.Name,
		rarity = rec.species.Rarity,
		rarityColor = tier.Color,
		mutation = rec.mutation,
		mutationColor = rec.mutationDef and rec.mutationDef.Color,
		value = Format.perSecond(rec.income),
	})

	local steal = Instance.new("ProximityPrompt")
	steal.Name = "StealPrompt"
	steal.ActionText = "Steal"
	steal.ObjectText = BlobbyService.displayName(rec)
	steal.HoldDuration = GameConfig.Steal.HoldDuration
	steal.MaxActivationDistance = GameConfig.Steal.PromptDistance
	steal.RequiresLineOfSight = false
	steal.Parent = built.promptAttachment
	steal.Triggered:Connect(function(player)
		services.StealService.tryGrab(player, rec)
	end)
	steal.PromptButtonHoldBegan:Connect(function(player)
		services.StealService.attempt(player, rec)
	end)

	local sell = Instance.new("ProximityPrompt")
	sell.Name = "SellPrompt"
	sell.ActionText = "Sell " .. Format.cash(Economy.sellValue(BlobbyService.priceOf(rec.species.Id, rec.mutation), GameConfig.SellRefund))
	sell.ObjectText = BlobbyService.displayName(rec)
	sell.HoldDuration = 0.8
	sell.MaxActivationDistance = GameConfig.Steal.PromptDistance
	sell.RequiresLineOfSight = false
	sell.Parent = built.promptAttachment
	sell.Triggered:Connect(function(player)
		if player == rec.owner then
			BlobbyService.sell(player, rec.uid)
		end
	end)
	rec.stealPrompt = steal
	rec.sellPrompt = sell

	model.Parent = world.blobbies
	return built
end

local function lanePoints(rec, from)
	local plot = services.PlotService.plotOf(rec.owner)
	local pedestal = plot.pedestals[rec.slot]
	local cf = plot.cframe
	local lx, lz = Layout.pedestalLocal(rec.slot, GameConfig.Plot)
	local points = {}
	local index = services.PlotService.plotIndexOf(rec.owner)
	if not services.PlotService.insidePlot(index, from) then
		table.insert(points, (plot.doorstep * CFrame.new(0, 0.3, 0)).Position)
		table.insert(points, plot.entrance.Position)
		table.insert(points, (cf * CFrame.new(0, 1, lz - 4.75)).Position)
	end
	table.insert(points, (cf * CFrame.new(lx, 1, lz - 4.75)).Position)
	table.insert(points, pedestal.standCFrame.Position)
	return points, pedestal.standCFrame
end

local function arrive(rec)
	if not records[rec.uid] then
		return
	end
	setState(rec, "Placed")
	refreshPedestal(rec)
	services.Remotes.Sfx:FireClient(rec.owner, "BlobbySqueak")
	services.PlayerService.sendProfile(rec.owner)
end

-- Walks a record's model from `from` to its pedestal (state Walking/Returning).
function BlobbyService.walkHome(rec, from, speed, state)
	setState(rec, state or "Walking")
	local root = rec.built.root
	root.Anchored = true
	root.CFrame = CFrame.new(from)
	local points, final = lanePoints(rec, from)
	Mover.walk(root, points, speed or GameConfig.WalkHomeSpeed, function()
		arrive(rec)
	end, final)
end

local function newRecord(player, uid, entry)
	local species = BlobbyConfig.ById[entry.Species]
	local mutationDef = entry.Mutation and MutationConfig.Types[entry.Mutation]
	local rec = {
		uid = uid,
		uidNumber = tonumber(string.match(uid, "%d+")) or 0,
		owner = player,
		species = species,
		mutation = if mutationDef then entry.Mutation else nil,
		mutationDef = mutationDef,
		slot = entry.Slot,
		state = "Placed",
		pending = 0,
		income = Economy.blobbyIncome(species, mutationDef),
	}
	records[uid] = rec
	owned[player] = owned[player] or {}
	owned[player][uid] = rec
	return rec
end

---------------------------------------------------------------------------------------------
-- Adding / removing
---------------------------------------------------------------------------------------------

--[[
	Gives `player` a Blobby. opts = { from = Vector3? (walks in from there), source = string }
	Returns uid, slot - or nil when the base is full (then it is queued for later).
]]
function BlobbyService.add(player, speciesId, mutation, opts)
	opts = opts or {}
	local data = services.DataService.getProfile(player)
	local species = BlobbyConfig.ById[speciesId]
	if not data or not species then
		return nil
	end
	if mutation and not MutationConfig.Types[mutation] then
		mutation = nil
	end
	local firstTime = not data.Discovered[speciesId]
	data.Discovered[speciesId] = true
	local slot = BlobbyService.freeSlot(player)
	if not slot or not services.PlotService.plotOf(player) then
		table.insert(data.Queued, { Species = speciesId, Mutation = mutation })
		services.DataService.markDirty(player)
		services.Remotes.Notify:FireClient(player, species.Name .. " is waiting for a free pedestal (sell one or rebirth for more slots).", "info")
		services.PlayerService.sendProfile(player)
		return nil
	end
	local uid = "b" .. data.NextUid
	data.NextUid += 1
	local entry = { Species = speciesId, Mutation = mutation, Slot = slot }
	data.Blobbies[uid] = entry
	services.DataService.markDirty(player)
	local rec = newRecord(player, uid, entry)
	local plot = services.PlotService.plotOf(player)
	local stand = plot.pedestals[slot].standCFrame
	buildModel(rec, if opts.from then CFrame.new(opts.from) else stand)
	if opts.from then
		BlobbyService.walkHome(rec, opts.from, opts.speed)
	else
		setState(rec, "Placed")
		refreshPedestal(rec)
	end
	if firstTime then
		services.Remotes.Popup:FireClient(player, "Discovered", { species = speciesId, mutation = mutation })
	end
	services.PlayerService.sendProfile(player)
	return uid, slot
end

-- Removes a Blobby from its owner (profile + runtime). Returns the record.
function BlobbyService.remove(uid)
	local rec = records[uid]
	if not rec then
		return nil
	end
	records[uid] = nil
	if owned[rec.owner] then
		owned[rec.owner][uid] = nil
	end
	local data = services.DataService.getProfile(rec.owner)
	if data then
		data.Blobbies[uid] = nil
		services.DataService.markDirty(rec.owner)
	end
	local pedestal = pedestalOf(rec)
	if pedestal then
		pedestal.ring.Color = EMPTY_RING
		pedestal.cashLabel.Text = ""
	end
	if rec.built then
		Mover.cancel(rec.built.root)
		rec.built.model:Destroy()
		rec.built = nil
	end
	return rec
end

-- Places queued Blobbies into any free pedestals (they walk in from the doorstep).
function BlobbyService.flushQueue(player)
	local data = services.DataService.getProfile(player)
	local plot = services.PlotService.plotOf(player)
	if not data or not plot then
		return
	end
	while #data.Queued > 0 and BlobbyService.freeSlot(player) do
		local entry = table.remove(data.Queued, 1)
		if BlobbyConfig.ById[entry.Species] then
			BlobbyService.add(player, entry.Species, entry.Mutation, { from = (plot.doorstep * CFrame.new(0, 0.3, 0)).Position })
		end
	end
end

function BlobbyService.sell(player, uid)
	local rec = records[uid]
	if not rec or rec.owner ~= player or rec.state ~= "Placed" then
		return false
	end
	local value = Economy.sellValue(BlobbyService.priceOf(rec.species.Id, rec.mutation), GameConfig.SellRefund)
	local position = rec.built.root.Position
	local pending = math.floor(rec.pending)
	BlobbyService.remove(uid)
	services.PlayerService.addCash(player, value + pending)
	local data = services.DataService.getProfile(player)
	data.Stats.Sold += 1
	services.RewardService.recordGoal(player, "Sell", 1)
	services.Remotes.Popup:FireClient(player, "Cash", { amount = value + pending, position = position })
	services.Remotes.Sfx:FireClient(player, "CollectCash")
	BlobbyService.flushQueue(player)
	services.PlayerService.sendProfile(player)
	return true
end

---------------------------------------------------------------------------------------------
-- Income
---------------------------------------------------------------------------------------------

function BlobbyService.collect(player, slot)
	local data = services.DataService.getProfile(player)
	if not data then
		return 0
	end
	for _, rec in pairs(owned[player] or {}) do
		if rec.slot == slot then
			local amount = math.floor(rec.pending)
			if amount < 1 then
				return 0
			end
			rec.pending -= amount
			services.PlayerService.addCash(player, amount)
			data.Stats.Collected += amount
			services.RewardService.recordGoal(player, "Collect", amount)
			local pedestal = pedestalOf(rec)
			if pedestal then
				pedestal.cashLabel.Text = ""
				services.Remotes.Popup:FireClient(player, "Cash", { amount = amount, position = pedestal.pad.Position })
			end
			services.Remotes.Sfx:FireClient(player, "CollectCash")
			return amount
		end
	end
	return 0
end

-- Moves every pending amount into cash without effects (leaving, rebirth).
function BlobbyService.collectAllSilently(player)
	local total = 0
	for _, rec in pairs(owned[player] or {}) do
		total += math.floor(rec.pending)
		rec.pending = 0
	end
	if total > 0 then
		services.PlayerService.addCash(player, total)
	end
	return total
end

function BlobbyService.tick(dt)
	for player, list in pairs(owned) do
		if player.Parent and services.DataService.getProfile(player) then
			local mult = services.PlayerService.multiplier(player)
			local auto = services.ShopService.owns(player, "AutoCollect")
			local autoTotal = 0
			for _, rec in pairs(list) do
				if rec.state == "Placed" then
					rec.pending += rec.income * mult * dt
					if auto then
						local amount = math.floor(rec.pending)
						if amount >= 1 then
							rec.pending -= amount
							autoTotal += amount
						end
					end
					local pedestal = pedestalOf(rec)
					if pedestal then
						pedestal.cashLabel.Text = if rec.pending >= 1 then Format.cash(rec.pending) else ""
					end
				end
			end
			if autoTotal > 0 then
				services.PlayerService.addCash(player, autoTotal)
				local data = services.DataService.getProfile(player)
				data.Stats.Collected += autoTotal
				services.RewardService.recordGoal(player, "Collect", autoTotal)
				autoCollected[player] = (autoCollected[player] or 0) + autoTotal
			end
		end
	end
end

-- Auto-collect shows one "+$X" popup every few seconds instead of every tick.
local function flushAutoPopups()
	for player, amount in pairs(autoCollected) do
		if player.Parent and amount > 0 then
			services.Remotes.Popup:FireClient(player, "AutoCash", { amount = amount })
		end
		autoCollected[player] = nil
	end
end

---------------------------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------------------------

-- Builds models for every saved Blobby, repairing bad slots.
function BlobbyService.spawnSaved(player)
	local data = services.DataService.getProfile(player)
	if not data or not services.PlotService.plotOf(player) then
		return
	end
	local slots = services.PlayerService.slots(player)
	local used = {}
	local misplaced = {}
	for uid, entry in pairs(data.Blobbies) do
		if not BlobbyConfig.ById[entry.Species] then
			data.Blobbies[uid] = nil
		elseif type(entry.Slot) ~= "number" or entry.Slot < 1 or entry.Slot > slots or entry.Slot % 1 ~= 0 or used[entry.Slot] then
			table.insert(misplaced, uid)
		else
			used[entry.Slot] = true
		end
	end
	for _, uid in ipairs(misplaced) do
		local entry = data.Blobbies[uid]
		local slot
		for s = 1, slots do
			if not used[s] then
				slot = s
				break
			end
		end
		if slot then
			entry.Slot = slot
			used[slot] = true
		else
			-- No room (e.g. a slot pass is no longer owned): keep it safe in the queue.
			data.Blobbies[uid] = nil
			table.insert(data.Queued, { Species = entry.Species, Mutation = entry.Mutation })
		end
	end
	for uid, entry in pairs(data.Blobbies) do
		local rec = newRecord(player, uid, entry)
		buildModel(rec, services.PlotService.plotOf(player).pedestals[entry.Slot].standCFrame)
		setState(rec, "Placed")
		refreshPedestal(rec)
	end
	BlobbyService.flushQueue(player)
end

function BlobbyService.despawn(player)
	services.StealService.onVictimLeaving(player)
	BlobbyService.collectAllSilently(player)
	for uid, rec in pairs(owned[player] or {}) do
		records[uid] = nil
		local pedestal = pedestalOf(rec)
		if pedestal then
			pedestal.ring.Color = EMPTY_RING
			pedestal.cashLabel.Text = ""
		end
		if rec.built then
			Mover.cancel(rec.built.root)
			rec.built.model:Destroy()
		end
	end
	owned[player] = nil
	autoCollected[player] = nil
end

-- Rebirth: every owned Blobby is released (queued deliveries are kept).
function BlobbyService.clearAll(player)
	local list = {}
	for uid in pairs(owned[player] or {}) do
		table.insert(list, uid)
	end
	for _, uid in ipairs(list) do
		BlobbyService.remove(uid)
	end
	local data = services.DataService.getProfile(player)
	if data then
		data.Blobbies = {}
	end
end

-- Moves a stolen Blobby to its new owner. Returns the new uid (or nil if queued).
function BlobbyService.transfer(rec, newOwner, from)
	local victim = rec.owner
	-- The victim keeps whatever cash it had made for them.
	local pending = math.floor(rec.pending)
	if pending > 0 then
		services.PlayerService.addCash(victim, pending)
	end
	BlobbyService.remove(rec.uid)
	services.PlayerService.sendProfile(victim)
	local uid = BlobbyService.add(newOwner, rec.species.Id, rec.mutation, { from = from, source = "steal" })
	BlobbyService.flushQueue(victim)
	return uid
end

function BlobbyService.setWorld(w)
	world = w
	for plotIndex, plot in ipairs(w.plots) do
		for slot, pedestal in ipairs(plot.pedestals) do
			pedestal.pad.CanTouch = true
			pedestal.pad.Touched:Connect(function(hit)
				local character = hit.Parent
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player or services.PlotService.plotIndexOf(player) ~= plotIndex then
					return
				end
				local key = plotIndex * 100 + slot
				local now = os.clock()
				if padDebounce[key] and now - padDebounce[key] < 0.4 then
					return
				end
				padDebounce[key] = now
				BlobbyService.collect(player, slot)
			end)
		end
	end
end

function BlobbyService.start()
	services.DataService.ProfileLoaded:Connect(function(player)
		BlobbyService.spawnSaved(player)
	end)
	services.DataService.Releasing:Connect(function(player)
		BlobbyService.despawn(player)
	end)
	Mover.start()
	task.spawn(function()
		while true do
			task.wait(4)
			flushAutoPopups()
		end
	end)
end

return BlobbyService
