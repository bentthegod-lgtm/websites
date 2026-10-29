--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned schema: migrate() runs on the raw saved table FIRST, then missing fields are
	  filled from defaultProfile() (reconcile) and every value is validated / clamped.
	* Autosave every GameConfig.AutosaveInterval (every profile, so the session lock stays
	  fresh), save on leave, and in parallel on BindToClose.
	* Session lock (data.Lock): a server only writes a profile it holds the lock for, so a
	  quick rejoin on another server waits for the old server's leave save instead of
	  loading stale data, and a stale server can't overwrite newer progress.
	* A failed load never overwrites saved data: the player plays on an in-memory profile
	  that is never written (persistent = false) and is told progress isn't saving.
	* Until a profile exists, getProfile returns nil: pickups, deposits, purchases and
	  rewards all check it first, so nothing is granted before data is initialised.
	* Studio play-tests use separate stores (suffix "_Studio"), so free Studio test grants
	  never reach live data.
	The carried (not yet deposited) loot is part of the profile, so a disconnect never
	loses a stack.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local LootConfig = require(Shared.Config.LootConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Economy = require(Shared.Economy)

local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local DataService = {}

local services
local profiles = {}
local store
local pendingSend = {}
local sessionRng = Random.new()

local LOCK_STALE = GameConfig.AutosaveInterval * 3
local LOAD_ATTEMPTS = 6

local function defaultSettings()
	return {
		Master = 1,
		Music = 0.6,
		Effects = 1,
		Ambient = 0.8,
		UI = 0.8,
		CameraShake = true,
		ReducedEffects = false,
		ShowOthers = true,
		AutoDeposit = true,
	}
end
DataService.defaultSettings = defaultSettings

local function emptyCarried()
	return { Items = {}, Value = 0, Slots = 0, Count = 0 }
end
DataService.emptyCarried = emptyCarried

local function defaultProfile()
	return {
		Version = GameConfig.SchemaVersion,
		Cash = 0,
		Tokens = 0,
		TotalEarned = 0,
		EarnedSinceRebirth = 0,
		BestDeposit = 0,
		Upgrades = {},
		Perks = {},
		HighestDepth = 1,
		CurrentDepth = 1,
		Rebirths = 0,
		Carried = emptyCarried(),
		Stats = {},
		Book = {},
		Achievements = {},
		Daily = { Day = 0, List = {} },
		Tutorial = { Step = 1, Done = false },
		Settings = defaultSettings(),
		Cosmetics = { Owned = {}, Theme = "Classic", Trail = "None", DepositFx = "Standard" },
		BoostUntil = 0,
		Codes = {},
		Receipts = {},
		FirstJoin = os.time(),
	}
end
DataService.defaultProfile = defaultProfile

-- Upgrades older profiles. Add a step whenever SchemaVersion goes up. Runs on the raw saved
-- table BEFORE defaults are filled in (otherwise a missing Version would already read as
-- current and every step would be skipped). A brand-new profile needs no steps.
local function migrate(data)
	data.Version = tonumber(data.Version) or (if data.Cash == nil then GameConfig.SchemaVersion else 1)
	-- (no migrations yet: version 1 is the first released schema)
	data.Version = GameConfig.SchemaVersion
	return data
end

local function num(v, default, min, max)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	if min then
		v = math.max(min, v)
	end
	if max then
		v = math.min(max, v)
	end
	return v
end

local OPEN_TABLES = { Upgrades = true, Perks = true, Stats = true, Book = true, Achievements = true, Codes = true, Receipts = true }

-- Fills missing fields and clamps everything to legal values (never trusts saved data).
local function reconcile(data)
	local defaults = defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	data.Lock = nil
	migrate(data)
	for key, value in pairs(defaults) do
		if type(data[key]) ~= type(value) then
			data[key] = value
		elseif type(value) == "table" and not OPEN_TABLES[key] then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	for _, field in ipairs({ "Cash", "Tokens", "TotalEarned", "EarnedSinceRebirth", "BestDeposit", "Rebirths", "BoostUntil" }) do
		data[field] = math.floor(num(data[field], 0, 0))
	end
	for k, level in pairs(data.Upgrades) do
		local def = UpgradeConfig.ByKey[k]
		data.Upgrades[k] = if def then math.floor(num(level, 0, 0, def.Max)) else nil
	end
	for k, level in pairs(data.Perks) do
		local def = UpgradeConfig.PerkByKey[k]
		data.Perks[k] = if def then math.floor(num(level, 0, 0, def.Max)) else nil
	end
	data.HighestDepth = math.floor(num(data.HighestDepth, 1, 1, DepthConfig.Count))
	data.CurrentDepth = math.floor(num(data.CurrentDepth, 1, 1, data.HighestDepth))
	-- Carried loot: only known items, counts recomputed from the item list.
	local carried = data.Carried
	local items, count, slots = {}, 0, 0
	local stats = Economy.stats(data)
	if type(carried.Items) == "table" then
		for id, n in pairs(carried.Items) do
			local def = LootConfig.ById[id]
			n = math.floor(num(n, 0, 0, 10000))
			if def and n > 0 then
				items[id] = n
				count += n
				slots += n * Economy.slotsFor(def, stats)
			end
		end
	end
	data.Carried = { Items = items, Count = count, Slots = slots, Value = if count > 0 then math.floor(num(carried.Value, 0, 0)) else 0 }
	for id, entry in pairs(data.Book) do
		if not LootConfig.ById[id] or type(entry) ~= "table" then
			data.Book[id] = nil
		else
			entry.n = math.floor(num(entry.n, 1, 1))
		end
	end
	for k, v in pairs(data.Stats) do
		if type(k) ~= "string" or type(v) ~= "number" or v ~= v then
			data.Stats[k] = nil
		else
			data.Stats[k] = math.max(0, v)
		end
	end
	data.Tutorial.Step = math.floor(num(data.Tutorial.Step, 1, 1))
	if type(data.Cosmetics.Owned) ~= "table" then
		data.Cosmetics.Owned = {}
	end
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		if not catalog[data.Cosmetics[kind]] then
			data.Cosmetics[kind] = defaults.Cosmetics[kind]
		end
	end
	if type(data.Daily.List) ~= "table" then
		data.Daily = { Day = 0, List = {} }
	end
	for key, value in pairs(defaultSettings()) do
		if type(data.Settings[key]) ~= type(value) then
			data.Settings[key] = value
		elseif type(value) == "number" then
			data.Settings[key] = num(data.Settings[key], value, 0, 1)
		end
	end
	return data
end
DataService.reconcile = reconcile

function DataService.init(registry)
	services = registry
	store = nil
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName .. STORE_SUFFIX)
	end)
	if ok then
		store = result
	else
		warn("[Vault] DataStore unavailable, progress will not persist: " .. tostring(result))
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

-- True once the profile's final save has started (player leaving / server shutting down).
function DataService.isLeaving(player)
	local entry = profiles[player]
	return entry ~= nil and (entry.leaving == true or entry.released == true)
end

function DataService.markDirty(player)
	local entry = profiles[player]
	if entry then
		entry.dirty = true
	end
end

function DataService.loadedPlayers()
	local list = {}
	for player, entry in pairs(profiles) do
		if not entry.leaving and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- The player's stats right now (upgrades, perks, rebirths, an active boost, VIP pass).
function DataService.stats(player)
	local data = DataService.getProfile(player)
	if not data then
		return Economy.stats(nil)
	end
	local state = { Upgrades = data.Upgrades, Perks = data.Perks, Rebirths = data.Rebirths, BoostUntil = data.BoostUntil, Vip = services.ShopService and services.ShopService.ownsPass(player, "VIP") or false }
	return Economy.stats(state, os.time())
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
		for _, name in ipairs({ "Cash", "Depth" }) do
			local value = Instance.new("NumberValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	stats.Cash.Value = math.floor(data.Cash)
	stats.Depth.Value = data.HighestDepth
end

local function validAmount(amount)
	return type(amount) == "number" and amount == amount and amount ~= math.huge and amount ~= -math.huge
end

-- Cash. `earned` counts toward TotalEarned (deposits, rewards) - not refunds.
function DataService.addCash(player, amount, earned)
	local data = DataService.getProfile(player)
	if not data or not validAmount(amount) then
		return false
	end
	amount = math.floor(amount)
	data.Cash = math.max(0, data.Cash + amount)
	if earned and amount > 0 then
		data.TotalEarned += amount
		data.EarnedSinceRebirth += amount
		DataService.bump(player, "Earned", amount)
	end
	DataService.markDirty(player)
	return true
end

-- Atomic spend: the full price is taken or nothing is.
function DataService.spendCash(player, amount)
	local data = DataService.getProfile(player)
	if not data or not validAmount(amount) or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	DataService.markDirty(player)
	return true
end

function DataService.addTokens(player, amount)
	local data = DataService.getProfile(player)
	if not data or not validAmount(amount) or amount <= 0 then
		return false
	end
	data.Tokens += math.floor(amount)
	DataService.markDirty(player)
	return true
end

function DataService.spendTokens(player, amount)
	local data = DataService.getProfile(player)
	if not data or not validAmount(amount) or amount < 0 or data.Tokens < amount then
		return false
	end
	data.Tokens -= amount
	DataService.markDirty(player)
	return true
end

-- Bumps a progress counter and lets quests / achievements / dailies react.
function DataService.bump(player, key, n)
	local data = DataService.getProfile(player)
	if not data then
		return
	end
	data.Stats[key] = (data.Stats[key] or 0) + (n or 1)
	DataService.markDirty(player)
	if services.QuestService then
		services.QuestService.onStat(player, key, n or 1)
	end
end

function DataService.setStat(player, key, value)
	local data = DataService.getProfile(player)
	if not data then
		return
	end
	if (data.Stats[key] or 0) ~= value then
		data.Stats[key] = value
		DataService.markDirty(player)
		if services.QuestService then
			services.QuestService.onStat(player, key)
		end
	end
end

function DataService.snapshot(player)
	local entry = profiles[player]
	if not entry then
		return nil
	end
	local data = entry.data
	local quest = services.QuestService
	local upgrades = services.UpgradeService
	return {
		cash = data.Cash,
		tokens = data.Tokens,
		totalEarned = data.TotalEarned,
		earnedSinceRebirth = data.EarnedSinceRebirth,
		bestDeposit = data.BestDeposit,
		upgrades = data.Upgrades,
		perks = data.Perks,
		highestDepth = data.HighestDepth,
		currentDepth = data.CurrentDepth,
		rebirths = data.Rebirths,
		boostUntil = data.BoostUntil,
		stats = data.Stats,
		book = data.Book,
		achievements = data.Achievements,
		daily = quest and quest.dailyView(player) or nil,
		tutorial = data.Tutorial,
		settings = data.Settings,
		cosmetics = data.Cosmetics,
		owned = services.ShopService and services.ShopService.ownedList(player) or {},
		vip = services.ShopService and services.ShopService.ownsPass(player, "VIP") or false,
		rebirth = upgrades and upgrades.rebirthPreview(player) or nil,
		serverTime = os.time(),
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

function DataService.sendProfileNow(player)
	local snap = DataService.snapshot(player)
	if snap then
		services.Remotes.Profile:FireClient(player, snap)
	end
	DataService.updateLeaderstats(player)
	return snap
end

local function key(player)
	return "player_" .. player.UserId
end

local function newSession()
	local ok, jobId = pcall(function()
		return game.JobId
	end)
	return string.format("%s:%d:%d", if ok then tostring(jobId) else "", os.time(), sessionRng:NextInteger(1, 2 ^ 30))
end

-- Services told once a profile is ready (in this order).
local HOOKS = { "UpgradeService", "ShopService", "QuestService", "LootService", "PlayerService", "ElevatorService", "LeaderboardService" }

function DataService.load(player)
	local data
	local persistent = false
	local session = newSession()
	if store then
		for attempt = 1, LOAD_ATTEMPTS do
			local locked = false
			local ok, result = pcall(function()
				return store:UpdateAsync(key(player), function(old)
					locked = false
					local lock = type(old) == "table" and old.Lock
					-- Another server still holds the profile (its leave save is in flight): wait.
					-- After the last attempt the lock is taken over; the other server's writes are then refused.
					if type(lock) == "table" and lock.Session ~= session and os.time() - (tonumber(lock.At) or 0) < LOCK_STALE and attempt < LOAD_ATTEMPTS then
						locked = true
						return nil
					end
					local value = if type(old) == "table" then old else {}
					value.Lock = { Session = session, At = os.time() }
					return value
				end)
			end)
			if ok and not locked then
				data = result
				persistent = true
				break
			end
			if not ok then
				warn(string.format("[Vault] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
			end
			if attempt < LOAD_ATTEMPTS then
				task.wait(math.min(1.5 * attempt, 5))
			end
			if not player.Parent then
				return
			end
		end
	end
	if not player.Parent then
		if persistent then
			profiles[player] = { data = reconcile(data), persistent = true, dirty = false, session = session, leaving = true }
			DataService.save(player)
			DataService.release(player)
		end
		return
	end
	profiles[player] = { data = reconcile(data), persistent = persistent, dirty = false, session = session }
	for _, name in ipairs(HOOKS) do
		local service = services[name]
		if service and service.onProfileLoaded then
			local ok, err = pcall(service.onProfileLoaded, player)
			if not ok then
				warn("[Vault] " .. name .. ".onProfileLoaded failed: " .. tostring(err))
			end
		end
	end
	DataService.sendProfileNow(player)
	if not persistent then
		services.Remotes.Notify:FireClient(player, "Progress saving is unavailable here (Studio without API access, or DataStores offline).", "warn")
	end
end

function DataService.save(player)
	local entry = profiles[player]
	if not entry then
		return false
	end
	if not entry.persistent or not store then
		return false
	end
	if entry.released then
		return true
	end
	local data = entry.data
	local ok, err, lost
	local attempts = if entry.leaving then 3 else 1
	for attempt = 1, attempts do
		ok, err = pcall(function()
			store:UpdateAsync(key(player), function(old)
				lost = false
				local lock = type(old) == "table" and old.Lock
				if type(lock) ~= "table" or lock.Session ~= entry.session then
					lost = not (entry.leaving and lock == nil)
					return nil
				end
				data.Lock = if entry.leaving then nil else { Session = entry.session, At = os.time() }
				return data
			end)
		end)
		if ok then
			break
		end
		warn("[Vault] Profile save failed for " .. player.Name .. ": " .. tostring(err))
		if attempt < attempts then
			task.wait(1)
		end
	end
	data.Lock = nil
	if ok and lost then
		warn("[Vault] Profile for " .. player.Name .. " is locked by another server; not saving")
		entry.persistent = false
		return false
	end
	if ok and entry.leaving then
		entry.released = true
	end
	entry.dirty = not ok
	return ok
end

function DataService.release(player)
	profiles[player] = nil
	pendingSend[player] = nil
end

-- Every service with per-player state cleans up first (claims released, pulls dropped,
-- elevator rides cancelled), then the final save runs.
local LEAVE_HOOKS = { "ElevatorService", "LootService", "DepositService", "UpgradeService", "QuestService", "ShopService", "PlayerService", "LeaderboardService" }

function DataService.onPlayerRemoving(player)
	local entry = profiles[player]
	if entry then
		entry.leaving = true
	end
	for _, name in ipairs(LEAVE_HOOKS) do
		local service = services[name]
		if service and service.onPlayerRemoving then
			local ok, err = pcall(service.onPlayerRemoving, player)
			if not ok then
				warn("[Vault] " .. name .. ".onPlayerRemoving failed: " .. tostring(err))
			end
		end
	end
	DataService.save(player)
	DataService.release(player)
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		DataService.load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.load, player)
	end
	Players.PlayerRemoving:Connect(DataService.onPlayerRemoving)
	game:BindToClose(function()
		local pending = 0
		for player, entry in pairs(profiles) do
			entry.leaving = true
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			-- Everyone is saved (not just dirty profiles) so the session lock stays fresh.
			for player in pairs(profiles) do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
