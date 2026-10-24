--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults: missing fields are filled from defaultProfile() (reconcile), and
	  migrate() upgrades older SchemaVersions.
	* Autosave every GameConfig.AutosaveInterval, save on leave and on BindToClose.
	* Profile snapshots for the client are coalesced (at most ~10 per second per player).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local CropConfig = require(Shared.Config.CropConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local GearConfig = require(Shared.Config.GearConfig)
local Economy = require(Shared.Economy)

local DataService = {}

local services
local profiles = {}
local store
local pendingSend = {}

local function defaultProfile()
	local seeds = table.clone(GameConfig.StartingSeeds)
	local gear = table.clone(GameConfig.StartingGear)
	return {
		Version = GameConfig.SchemaVersion,
		Coins = GameConfig.StartingCoins,
		TotalEarned = 0,
		Seeds = seeds,
		Gear = gear,
		Tokens = { GrowthSkip = 0 },
		Backpack = {},
		NextItemId = 1,
		Plot = { Rows = 0, Plants = {}, Sprinklers = {}, Updated = 0 },
		Daily = { LastDay = 0, Streak = 0 },
		Codes = {},
		Settings = { AcceptGifts = true, Music = true },
		Stats = { Harvests = 0, Planted = 0, Mutations = 0, Sold = 0, BestFruit = 0, Gifts = 0 },
		Receipts = {},
		FirstJoin = os.time(),
	}
end
DataService.defaultProfile = defaultProfile

-- Upgrades older profiles. Add a step here whenever SchemaVersion goes up.
local function migrate(data)
	data.Version = data.Version or 1
	-- (no migrations yet: version 1 is the first released schema)
	data.Version = GameConfig.SchemaVersion
	return data
end

local function reconcile(data)
	local defaults = defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	for key, value in pairs(defaults) do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and key ~= "Seeds" and key ~= "Gear" then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	-- Drop anything that no longer exists in config (renamed / removed crops).
	for crop in pairs(data.Seeds) do
		if not CropConfig.ById[crop] then
			data.Seeds[crop] = nil
		end
	end
	local kept = {}
	for _, item in ipairs(data.Backpack) do
		if type(item) == "table" and CropConfig.ById[item.c] then
			table.insert(kept, item)
		end
	end
	data.Backpack = kept
	for key, plant in pairs(data.Plot.Plants) do
		if type(plant) ~= "table" or not CropConfig.ById[plant.c] then
			data.Plot.Plants[key] = nil
		end
	end
	return migrate(data)
end
DataService.reconcile = reconcile

function DataService.init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[SproutValley] DataStore unavailable, progress will not persist: " .. tostring(result))
	end
end

function DataService.getProfile(player)
	local entry = profiles[player]
	return entry and entry.data
end

function DataService.isPersistent(player)
	local entry = profiles[player]
	return entry ~= nil and entry.persistent
end

function DataService.markDirty(player)
	local entry = profiles[player]
	if entry then
		entry.dirty = true
	end
end

function DataService.loadedPlayers()
	local list = {}
	for player in pairs(profiles) do
		table.insert(list, player)
	end
	return list
end

function DataService.updateLeaderstats(player)
	local data = DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, name in ipairs({ "Coins", "Earned" }) do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	stats.Coins.Value = math.floor(data.Coins)
	stats.Earned.Value = math.floor(data.TotalEarned)
end

function DataService.backpackCapacity(player)
	local owns = services.ShopService and services.ShopService.owns(player, "BigBackpack")
	return if owns then GameConfig.BackpackPass else GameConfig.BackpackBase
end

local function itemView(item)
	local crop = CropConfig.ById[item.c]
	return {
		id = item.id,
		crop = item.c,
		kg = item.kg,
		mutations = item.m,
		variant = item.v,
		favorite = item.f == true,
		value = Economy.fruitValue(crop, item.kg, item.m, item.v, MutationConfig),
	}
end

function DataService.snapshot(player)
	local entry = profiles[player]
	if not entry then
		return nil
	end
	local data = entry.data
	local backpack = {}
	for _, item in ipairs(data.Backpack) do
		table.insert(backpack, itemView(item))
	end
	local plotInfo = services.PlotService and services.PlotService.plotInfo(player) or {}
	return {
		coins = data.Coins,
		totalEarned = data.TotalEarned,
		seeds = data.Seeds,
		gear = data.Gear,
		tokens = data.Tokens,
		backpack = backpack,
		capacity = DataService.backpackCapacity(player),
		plot = plotInfo,
		passes = services.ShopService and services.ShopService.passesFor(player) or {},
		sellMultiplier = services.SellService and services.SellService.multiplier(player) or 1,
		friends = services.SellService and services.SellService.friendCount(player) or 0,
		daily = services.RewardsService and services.RewardsService.dailyView(player) or nil,
		goals = services.RewardsService and services.RewardsService.goalsView(player) or {},
		settings = data.Settings,
		stats = data.Stats,
		persistent = entry.persistent,
	}
end

function DataService.sendProfile(player)
	if pendingSend[player] then
		return
	end
	pendingSend[player] = true
	task.defer(function()
		pendingSend[player] = nil
		if not player.Parent or not profiles[player] then
			return
		end
		local snap = DataService.snapshot(player)
		if snap then
			services.Remotes.Profile:FireClient(player, snap)
		end
		DataService.updateLeaderstats(player)
	end)
end

-- Immediate (non-deferred) send, used right after loading and by tests.
function DataService.sendProfileNow(player)
	local snap = DataService.snapshot(player)
	if snap then
		services.Remotes.Profile:FireClient(player, snap)
	end
	DataService.updateLeaderstats(player)
	return snap
end

function DataService.addCoins(player, amount, earned)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount then
		return false
	end
	data.Coins = math.max(0, math.floor(data.Coins + amount))
	if earned and amount > 0 then
		data.TotalEarned += math.floor(amount)
	end
	DataService.markDirty(player)
	return true
end

function DataService.spendCoins(player, amount)
	local data = DataService.getProfile(player)
	if not data or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	DataService.markDirty(player)
	return true
end

function DataService.grantBundle(player, bundle)
	local data = DataService.getProfile(player)
	if not data or type(bundle) ~= "table" then
		return {}
	end
	local lines = {}
	if bundle.Coins then
		DataService.addCoins(player, bundle.Coins, false)
		table.insert(lines, string.format("%d Coins", bundle.Coins))
	end
	for crop, n in pairs(bundle.Seeds or {}) do
		if CropConfig.ById[crop] then
			data.Seeds[crop] = (data.Seeds[crop] or 0) + n
			table.insert(lines, string.format("%dx %s seed", n, CropConfig.ById[crop].Name))
		end
	end
	for gear, n in pairs(bundle.Gear or {}) do
		local def = GearConfig.Gear[gear]
		if def then
			data.Gear[gear] = (data.Gear[gear] or 0) + n
			table.insert(lines, string.format("%dx %s", n, def.Name))
		end
	end
	DataService.markDirty(player)
	return lines
end

local function key(player)
	return "player_" .. player.UserId
end

function DataService.load(player)
	local data
	local persistent = false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(key(player))
			end)
			if ok then
				data = result
				persistent = true
				break
			end
			warn(string.format("[SproutValley] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
			task.wait(1.5 * attempt)
		end
	end
	if not player.Parent then
		return
	end
	profiles[player] = { data = reconcile(data), persistent = persistent, dirty = false }
	for _, name in ipairs({ "ShopService", "PlotService", "RewardsService", "SellService", "PlayerService", "StockService" }) do
		local service = services[name]
		if service and service.onProfileLoaded then
			local ok, err = pcall(service.onProfileLoaded, player)
			if not ok then
				warn("[SproutValley] " .. name .. ".onProfileLoaded failed: " .. tostring(err))
			end
		end
	end
	DataService.sendProfileNow(player)
	if not persistent then
		services.Remotes.Notify:FireClient(player, "Progress saving is unavailable here (Studio or DataStore offline).", "warn")
	end
end

function DataService.save(player)
	local entry = profiles[player]
	if not entry then
		return false
	end
	if services.PlotService then
		services.PlotService.flush(player)
	end
	if not entry.persistent or not store then
		return false
	end
	local data = entry.data
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[SproutValley] Profile save failed for " .. player.Name .. ": " .. tostring(err))
	end
	entry.dirty = not ok
	return ok
end

function DataService.release(player)
	profiles[player] = nil
	pendingSend[player] = nil
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		DataService.load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		for _, name in ipairs({ "PlotService", "StockService", "SellService", "RewardsService", "ShopService", "PlayerService" }) do
			local service = services[name]
			if service and service.onPlayerRemoving then
				pcall(service.onPlayerRemoving, player)
			end
		end
		DataService.release(player)
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			-- Everyone is saved (not just dirty profiles) so growth timestamps stay fresh.
			for player in pairs(profiles) do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
