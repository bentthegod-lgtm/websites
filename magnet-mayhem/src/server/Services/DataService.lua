--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults: missing fields are filled from defaultProfile() (reconcile), and
	  migrate() upgrades older SchemaVersions. Saved values are validated on load.
	* Autosave every GameConfig.AutosaveInterval, save on leave and on BindToClose.
	* Session lock (data.Lock): a server only writes a profile it holds the lock for, so a
	  quick rejoin on another server waits for the old server's leave save instead of
	  loading stale data, and a stale server can't overwrite newer progress.
	* `loaded` is only true once a profile exists for the player; purchases and other
	  important actions check DataService.getProfile first.
	* Studio play-tests use separate stores (suffix "_Studio"), so free Studio test grants
	  never reach live data.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local GameConfig = require(Shared.Config.GameConfig)
local ScrapConfig = require(Shared.Config.ScrapConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MagnetConfig = require(Shared.Config.MagnetConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

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
		CameraMode = "Third",
		Sensitivity = 1,
		Master = 1,
		Music = 0.6,
		Effects = 1,
		Ambient = 0.8,
		UI = 0.8,
		ReducedEffects = false,
		Particles = "High",
	}
end
DataService.defaultSettings = defaultSettings

local function defaultProfile()
	return {
		Version = GameConfig.SchemaVersion,
		Coins = EconomyConfig.StartingCoins,
		TotalEarned = 0,
		RunEarned = 0,
		TotalScrapValue = 0,
		RareFinds = 0,
		Upgrades = {},
		Tier = 1,
		Zones = { [ZoneConfig.StartZone] = true },
		Carried = {},
		Codex = {},
		Achievements = {},
		Quest = { Index = 1 },
		Stats = {},
		Daily = { Day = 0, List = {} },
		Prestige = { Cores = 0, Count = 0 },
		Tutorial = { Step = 1, Done = false },
		Settings = defaultSettings(),
		Cosmetics = { Owned = { Default = true, None = true }, Skin = "Default", Trail = "None" },
		Codes = {},
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

local function num(v, default, min, max)
	v = tonumber(v)
	if v == nil or v ~= v then
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

-- Fills missing fields and clamps everything to legal values (never trusts saved data blindly).
local function reconcile(data)
	local defaults = defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	for key, value in pairs(defaults) do
		if type(data[key]) ~= type(value) then
			data[key] = value
		elseif type(value) == "table" and key ~= "Upgrades" and key ~= "Zones" and key ~= "Codex" and key ~= "Carried" then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	data.Coins = num(data.Coins, 0, 0)
	data.TotalEarned = num(data.TotalEarned, 0, 0)
	data.RunEarned = num(data.RunEarned, 0, 0)
	data.TotalScrapValue = num(data.TotalScrapValue, 0, 0)
	data.RareFinds = num(data.RareFinds, 0, 0)
	data.Tier = math.floor(num(data.Tier, 1, 1, #MagnetConfig.Tiers))
	for key, level in pairs(data.Upgrades) do
		local def = EconomyConfig.ByKey[key]
		if def then
			data.Upgrades[key] = math.floor(num(level, 0, 0, def.Max))
		else
			data.Upgrades[key] = nil
		end
	end
	for zoneId in pairs(data.Zones) do
		if not ZoneConfig.ById[zoneId] then
			data.Zones[zoneId] = nil
		end
	end
	data.Zones[ZoneConfig.StartZone] = true
	local carried = {}
	for _, item in ipairs(data.Carried) do
		if type(item) == "table" and ScrapConfig.ById[item.id] then
			table.insert(carried, { id = item.id, v = math.floor(num(item.v, ScrapConfig.ById[item.id].Value, 0)) })
		end
	end
	data.Carried = carried
	for id, entry in pairs(data.Codex) do
		if not ScrapConfig.ById[id] or type(entry) ~= "table" then
			data.Codex[id] = nil
		end
	end
	data.Prestige.Cores = math.floor(num(data.Prestige.Cores, 0, 0))
	if not MagnetConfig.Skins[data.Cosmetics.Skin] then
		data.Cosmetics.Skin = "Default"
	end
	if not MagnetConfig.Trails[data.Cosmetics.Trail] then
		data.Cosmetics.Trail = "None"
	end
	return migrate(data)
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
		warn("[MagnetMayhem] DataStore unavailable, progress will not persist: " .. tostring(result))
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
		for _, name in ipairs({ "Coins", "Tier" }) do
			local value = Instance.new("NumberValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	stats.Coins.Value = math.floor(data.Coins)
	stats.Tier.Value = data.Tier
end

-- Coins. `earned` counts toward TotalEarned / RunEarned (sales, quests) - not refunds.
function DataService.addCoins(player, amount, earned)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount == math.huge then
		return false
	end
	amount = math.floor(amount)
	data.Coins = math.max(0, data.Coins + amount)
	if earned and amount > 0 then
		data.TotalEarned += amount
		data.RunEarned += amount
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

-- Sets a "level" stat (Tier, Zone, Discover) to an absolute value.
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

function DataService.carriedTotals(data)
	local mass, value = 0, 0
	for _, item in ipairs(data.Carried) do
		local def = ScrapConfig.ById[item.id]
		mass += def.Mass
		value += item.v
	end
	return mass, value
end

function DataService.snapshot(player)
	local entry = profiles[player]
	if not entry then
		return nil
	end
	local data = entry.data
	local mass, value = DataService.carriedTotals(data)
	local codex = {}
	for id, e in pairs(data.Codex) do
		codex[id] = { n = e.n or 0, best = e.best or 0 }
	end
	return {
		coins = data.Coins,
		totalEarned = data.TotalEarned,
		runEarned = data.RunEarned,
		totalScrapValue = data.TotalScrapValue,
		rareFinds = data.RareFinds,
		upgrades = data.Upgrades,
		tier = data.Tier,
		zones = data.Zones,
		carriedMass = mass,
		carriedValue = value,
		carriedCount = #data.Carried,
		stats = services.UpgradeService and services.UpgradeService.statsFor(player) or nil,
		codex = codex,
		achievements = data.Achievements,
		quest = services.QuestService and services.QuestService.questView(player) or nil,
		daily = services.QuestService and services.QuestService.dailyView(player) or nil,
		tutorial = data.Tutorial,
		prestige = data.Prestige,
		prestigePreview = services.UpgradeService and services.UpgradeService.prestigePreview(player) or nil,
		settings = data.Settings,
		cosmetics = data.Cosmetics,
		passes = services.ShopService and services.ShopService.passesFor(player) or {},
		counters = data.Stats,
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

local HOOKS = { "UpgradeService", "ShopService", "QuestService", "PlayerService", "MagnetService", "ZoneService", "LeaderboardService" }

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
				warn(string.format("[MagnetMayhem] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
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
				warn("[MagnetMayhem] " .. name .. ".onProfileLoaded failed: " .. tostring(err))
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
		warn("[MagnetMayhem] Profile save failed for " .. player.Name .. ": " .. tostring(err))
		if attempt < attempts then
			task.wait(1)
		end
	end
	if ok and lost then
		warn("[MagnetMayhem] Profile for " .. player.Name .. " is locked by another server; not saving")
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

local LEAVE_HOOKS = { "MagnetService", "ScrapService", "EconomyService", "UpgradeService", "QuestService", "ShopService", "PlayerService", "ZoneService", "EventService", "LeaderboardService" }

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
		-- Services clean up first (in-flight pulls are released, never awarded), then save.
		for _, name in ipairs(LEAVE_HOOKS) do
			local service = services[name]
			if service and service.onPlayerRemoving then
				local ok, err = pcall(service.onPlayerRemoving, player)
				if not ok then
					warn("[MagnetMayhem] " .. name .. ".onPlayerRemoving failed: " .. tostring(err))
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
