--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults: migrate() runs on the raw saved table first, then missing fields
	  are filled from defaultProfile() (reconcile) and every value is validated.
	* Autosave every GameConfig.AutosaveInterval, save on leave and on BindToClose.
	* Session lock (data.Lock): a server only writes a profile it holds the lock for, so a
	  quick rejoin on another server waits for the old server's leave save instead of
	  loading stale data, and a stale server can't overwrite newer progress.
	* Until a profile exists for the player, getProfile returns nil: rounds, purchases
	  and rewards all check it first, so nothing is granted before data is initialised.
	* Studio play-tests use separate stores (suffix "_Studio"), so free Studio test grants
	  never reach live data.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Progress = require(Shared.Progress)

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
		ScareEffects = true, -- the catch scare (flash + close-up); off = a gentle fade
		CameraShake = true,
		ReducedEffects = false,
		ToggleSneak = true,
	}
end
DataService.defaultSettings = defaultSettings

local function defaultProfile()
	return {
		Version = GameConfig.SchemaVersion,
		Coins = 0,
		Xp = 0,
		Stats = {},
		Cosmetics = { Owned = {}, Outfit = CosmeticConfig.Defaults.Outfit, Lantern = CosmeticConfig.Defaults.Lantern },
		Boosts = { Flask = 0 },
		Daily = { LastDay = 0, Streak = 0 },
		Goals = { Day = 0, Progress = {}, Done = {} },
		Settings = defaultSettings(),
		Codes = {},
		Receipts = {},
		FirstJoin = os.time(),
	}
end
DataService.defaultProfile = defaultProfile

-- Upgrades older profiles. Add a step here whenever SchemaVersion goes up. Runs on the raw
-- saved table BEFORE defaults are filled in (otherwise a missing Version would already be
-- the current one and every step would be skipped). A brand-new profile needs no steps.
local function migrate(data)
	data.Version = tonumber(data.Version) or (if data.Coins == nil then GameConfig.SchemaVersion else 1)
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

local OPEN_TABLES = { Stats = true, Codes = true, Receipts = true }

-- Fills missing fields and clamps everything to legal values (never trusts saved data blindly).
local function reconcile(data)
	local defaults = defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	migrate(data)
	for key, value in pairs(defaults) do
		if type(data[key]) ~= type(value) then
			data[key] = value
		elseif type(value) == "table" and not OPEN_TABLES[key] then
			for k, v in pairs(value) do
				if type(data[key][k]) ~= type(v) then
					data[key][k] = v
				end
			end
		end
	end
	data.Coins = math.floor(num(data.Coins, 0, 0))
	data.Xp = math.floor(num(data.Xp, 0, 0))
	for k, v in pairs(data.Stats) do
		if type(k) ~= "string" or type(v) ~= "number" or v ~= v then
			data.Stats[k] = nil
		else
			data.Stats[k] = math.max(0, v)
		end
	end
	-- Receipts are PurchaseId -> grant time; anything else would break trimming (sorted by time).
	for k, v in pairs(data.Receipts) do
		if type(k) ~= "string" or type(v) ~= "number" or v ~= v then
			data.Receipts[k] = nil
		end
	end
	for k in pairs(data.Cosmetics.Owned) do
		local kind, id = string.match(tostring(k), "^(%a+):(%w+)$")
		local catalog = kind and CosmeticConfig.Kinds[kind]
		if not catalog or not catalog[id] then
			data.Cosmetics.Owned[k] = nil
		end
	end
	for kind, catalog in pairs(CosmeticConfig.Kinds) do
		if not catalog[data.Cosmetics[kind]] then
			data.Cosmetics[kind] = defaults.Cosmetics[kind]
		end
	end
	data.Boosts.Flask = math.floor(num(data.Boosts.Flask, 0, 0, 999))
	data.Daily.LastDay = math.floor(num(data.Daily.LastDay, 0, 0))
	data.Daily.Streak = math.floor(num(data.Daily.Streak, 0, 0, 10000))
	data.Goals.Day = math.floor(num(data.Goals.Day, 0, 0))
	for k, v in pairs(defaultSettings()) do
		if type(data.Settings[k]) ~= type(v) then
			data.Settings[k] = v
		end
	end
	for k in pairs(data.Settings) do
		if defaults.Settings[k] == nil then
			data.Settings[k] = nil
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
		warn("[ThinIce] DataStore unavailable, progress will not persist: " .. tostring(result))
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

-- True once the profile's final save has started (player leaving or server shutting down):
-- later writes may never reach the DataStore.
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

function DataService.updateLeaderstats(player)
	local data = DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, name in ipairs({ "Level", "Escapes" }) do
			local value = Instance.new("NumberValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	stats.Level.Value = Progress.levelFor(data.Xp)
	stats.Escapes.Value = math.floor(data.Stats.Escapes or 0)
end

-- Coins. `earned` counts toward the Earned stat (runs, goals, dailies) - not refunds.
function DataService.addCoins(player, amount, earned)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge then
		return false
	end
	amount = math.floor(amount)
	data.Coins = math.max(0, data.Coins + amount)
	if earned and amount > 0 then
		DataService.bump(player, "Earned", amount)
	end
	DataService.markDirty(player)
	return true
end

-- Atomic spend: either the full price is taken or nothing is.
function DataService.spendCoins(player, amount)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	DataService.markDirty(player)
	return true
end

-- Bumps a progress counter and lets daily goals react.
function DataService.bump(player, key, n)
	local data = DataService.getProfile(player)
	if not data then
		return
	end
	data.Stats[key] = (data.Stats[key] or 0) + (n or 1)
	DataService.markDirty(player)
	if services.RewardService then
		services.RewardService.onStat(player, key, n or 1)
	end
end

-- Records only go up. Returns true if this is a new record.
function DataService.record(player, key, value)
	local data = DataService.getProfile(player)
	if not data or type(value) ~= "number" or value ~= value then
		return false
	end
	if value > (data.Stats[key] or 0) then
		data.Stats[key] = value
		DataService.markDirty(player)
		return true
	end
	return false
end

function DataService.setStat(player, key, value)
	local data = DataService.getProfile(player)
	if not data then
		return
	end
	if (data.Stats[key] or 0) ~= value then
		data.Stats[key] = value
		DataService.markDirty(player)
	end
end

function DataService.snapshot(player)
	local entry = profiles[player]
	if not entry then
		return nil
	end
	local data = entry.data
	local level = Progress.levelFor(data.Xp)
	local shop = services.ShopService
	local reward = services.RewardService
	return {
		coins = data.Coins,
		xp = data.Xp,
		level = level,
		levelXp = Progress.xpFor(level),
		nextLevelXp = Progress.xpFor(level + 1),
		stats = data.Stats,
		cosmetics = { Outfit = data.Cosmetics.Outfit, Lantern = data.Cosmetics.Lantern },
		owned = shop and shop.ownedList(player) or {},
		vip = shop and shop.ownsPass(player, "VIP") or false,
		boosts = data.Boosts,
		daily = reward and reward.dailyView(player) or nil,
		goals = reward and reward.goalsView(player) or {},
		settings = data.Settings,
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

local HOOKS = { "ShopService", "RewardService", "PlayerService", "RoundService", "LeaderboardService" }

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
					-- Another server still holds the profile (leave save in flight): wait for it.
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
				warn(string.format("[ThinIce] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
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
				warn("[ThinIce] " .. name .. ".onProfileLoaded failed: " .. tostring(err))
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
		warn("[ThinIce] Profile save failed for " .. player.Name .. ": " .. tostring(err))
		if attempt < attempts then
			task.wait(1)
		end
	end
	if ok and lost then
		warn("[ThinIce] Profile for " .. player.Name .. " is locked by another server; not saving")
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

-- Round cleanup first (a carried core is dropped, the player leaves the run with no
-- reward), then everything else.
local LEAVE_HOOKS = { "RoundService", "ObjectiveService", "SurvivalService", "MonsterService", "RewardService", "ShopService", "PlayerService", "LeaderboardService" }

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		DataService.load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = profiles[player]
		if entry then
			entry.leaving = true
		end
		for _, name in ipairs(LEAVE_HOOKS) do
			local service = services[name]
			if service and service.onPlayerRemoving then
				local ok, err = pcall(service.onPlayerRemoving, player)
				if not ok then
					warn("[ThinIce] " .. name .. ".onPlayerRemoving failed: " .. tostring(err))
				end
			end
		end
		DataService.save(player)
		DataService.release(player)
	end)
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
