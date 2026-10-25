--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults + migration (SchemaVersion in GameConfig).
	* Autosave every GameConfig.AutosaveInterval, save on leave and on BindToClose.
	* Session lock (data.Lock): a server only writes a profile it holds the lock for, so a
	  quick rejoin on another server waits for the old server's leave save instead of
	  loading stale data, and a stale server can't overwrite newer progress.
	* leaderstats: Wins, Streak, Coins.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)
-- Studio play-tests use separate stores, so free test grants never reach live data.
local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Economy = require(Shared.Economy)

local DataService = {}

local services
local profiles = {}
local store

-- A lock older than this belongs to a server that crashed (autosave refreshes it).
local LOCK_STALE = GameConfig.AutosaveInterval * 3
local LOAD_ATTEMPTS = 6

-- Per-player cleanup that must run before the (yielding) leave save. MatchService goes
-- first: eliminating a leaver can end the round and pay rewards (which read ShopService's
-- pass cache and RewardService's session), and that progress belongs in the leave save.
local REMOVING_ORDER = { "MatchService", "AbilityService", "CosmeticService", "RewardService", "ShopService" }

local SETTINGS_SCHEMA = {
	Music = { 0, 1, 0.5 },
	Sfx = { 0, 1, 1 },
	Shake = { false, true, true },
	AutoReady = { false, true, true },
}

local function defaultCosmetics()
	local owned, equipped = {}, {}
	for _, category in ipairs(CosmeticConfig.Categories) do
		owned[category] = {}
	end
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Default then
			owned[item.Category][item.Id] = true
			equipped[item.Category] = item.Id
		end
	end
	return owned, equipped
end

function DataService.defaultProfile()
	local owned, equipped = defaultCosmetics()
	local abilities = {}
	for _, id in ipairs(AbilityConfig.DefaultOwned) do
		abilities[id] = true
	end
	local settings = {}
	for key, spec in pairs(SETTINGS_SCHEMA) do
		settings[key] = spec[3]
	end
	return {
		Version = GameConfig.SchemaVersion,
		Coins = ProgressionConfig.StartingCoins,
		Stats = { Wins = 0, PracticeWins = 0, Kills = 0, Deaths = 0, Rounds = 0, Parries = 0, CratesOpened = 0, BestSpeed = 0 },
		WinStreak = 0,
		BestStreak = 0,
		Abilities = abilities,
		Loadout = { AbilityConfig.DefaultOwned[1] },
		Owned = owned,
		Equipped = equipped,
		PremiumSpins = 0,
		Pity = 0,
		Daily = { Last = 0, Streak = 0 },
		Codes = {},
		Receipts = {}, -- processed Robux PurchaseIds -> os.time(); a purchase is granted once
		Settings = settings,
	}
end

-- Older profile versions -> current.
function DataService.migrate(data)
	local version = data.Version or 1
	if version < 2 then
		-- v1 stored a single equipped weapon id as a string and abilities as a list.
		if type(data.Equipped) == "string" then
			data.Equipped = { ParryFx = data.Equipped }
		end
		if type(data.Abilities) == "table" and data.Abilities[1] ~= nil then
			local set = {}
			for _, id in ipairs(data.Abilities) do
				set[id] = true
			end
			data.Abilities = set
		end
	end
	return data
end

-- Fills any fields missing from an older/partial profile (two levels deep).
function DataService.reconcile(data)
	local defaults = DataService.defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	data = DataService.migrate(data)
	for key, value in pairs(defaults) do
		if data[key] == nil or type(data[key]) ~= type(value) then
			data[key] = value
		elseif type(value) == "table" then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				elseif type(v) == "table" and type(data[key][k]) == "table" then
					for k2, v2 in pairs(v) do
						if data[key][k][k2] == nil then
							data[key][k][k2] = v2
						end
					end
				end
			end
		end
	end
	-- Loadout must only contain owned abilities.
	local clean = {}
	for _, id in ipairs(data.Loadout) do
		if data.Abilities[id] and AbilityConfig.Abilities[id] and not table.find(clean, id) then
			table.insert(clean, id)
		end
	end
	if #clean == 0 then
		clean = { AbilityConfig.DefaultOwned[1] }
	end
	data.Loadout = clean
	data.Version = GameConfig.SchemaVersion
	return data
end

function DataService.init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName .. STORE_SUFFIX)
	end)
	if ok then
		store = result
	else
		warn("[ReboundRumble] DataStore unavailable, progress will not persist: " .. tostring(result))
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

function DataService.addCoins(player, amount)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount then
		return false
	end
	data.Coins = math.max(0, math.floor(data.Coins + amount))
	DataService.markDirty(player)
	DataService.updateLeaderstats(player)
	return true
end

function DataService.spendCoins(player, amount)
	local data = DataService.getProfile(player)
	if not data or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	DataService.markDirty(player)
	DataService.updateLeaderstats(player)
	return true
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
		for _, name in ipairs({ "Wins", "Streak", "Coins" }) do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	stats.Wins.Value = data.Stats.Wins
	stats.Streak.Value = data.WinStreak
	stats.Coins.Value = data.Coins
end

function DataService.sendProfile(player)
	local entry = profiles[player]
	if not entry or not player.Parent then
		return
	end
	local data = entry.data
	local passes = services.ShopService and services.ShopService.passesFor(player) or {}
	local daily = Economy.daily(data.Daily, os.time(), ProgressionConfig.DailyRewards)
	services.Remotes.Profile:FireClient(player, {
		coins = data.Coins,
		stats = data.Stats,
		winStreak = data.WinStreak,
		bestStreak = data.BestStreak,
		abilities = data.Abilities,
		loadout = data.Loadout,
		maxSlots = if passes.ExtraSlot then AbilityConfig.MaxSlotsWithPass else AbilityConfig.MaxSlots,
		owned = data.Owned,
		equipped = data.Equipped,
		premiumSpins = data.PremiumSpins,
		pity = data.Pity,
		daily = { claimable = daily.claimable, streak = if daily.claimable then daily.streak else data.Daily.Streak, amount = daily.amount, nextIn = daily.nextIn },
		passes = passes,
		multiplier = services.ShopService and services.ShopService.coinMultiplier(player) or 1,
		settings = data.Settings,
		persistent = entry.persistent,
	})
end

local function key(player)
	return "player_" .. player.UserId
end

local function newSession()
	local ok, jobId = pcall(function()
		return game.JobId
	end)
	return string.format("%s:%d:%d", if ok then tostring(jobId) else "", os.time(), math.random(1, 2 ^ 30))
end

function DataService.load(player)
	local data
	local persistent = false
	local session = newSession()
	if store then
		for attempt = 1, LOAD_ATTEMPTS do
			local locked = false
			local ok, result = pcall(function()
				return store:UpdateAsync(key(player), function(old)
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
				warn(string.format("[ReboundRumble] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
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
			-- Left while loading: give the lock back so their next join isn't delayed.
			profiles[player] = { data = DataService.reconcile(data), persistent = true, dirty = false, session = session, leaving = true }
			DataService.save(player)
			DataService.release(player)
		end
		return
	end
	profiles[player] = { data = DataService.reconcile(data), persistent = persistent, dirty = false, session = session }
	if services.ShopService then
		services.ShopService.refreshPasses(player)
	end
	DataService.updateLeaderstats(player)
	DataService.sendProfile(player)
	if not persistent then
		services.Remotes.Notify:FireClient(player, "Progress saving unavailable (Studio or DataStore offline).", "warn")
	end
	if services.LeaderboardService then
		services.LeaderboardService.submit(player, profiles[player].data.Stats.Wins)
	end
end

function DataService.save(player)
	local entry = profiles[player]
	if not entry or not entry.persistent or not store then
		return false
	end
	if entry.released then
		return true -- the leave save already wrote and unlocked this profile
	end
	local data = entry.data
	local ok, err, lost
	-- The leave / shutdown save is the last chance to persist, so it retries.
	local attempts = if entry.leaving then 3 else 1
	for attempt = 1, attempts do
		lost = false
		ok, err = pcall(function()
			store:UpdateAsync(key(player), function(old)
				local lock = type(old) == "table" and old.Lock
				if type(lock) ~= "table" or lock.Session ~= entry.session then
					-- No lock: our own leave save already released it. Otherwise another server owns it.
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
		warn("[ReboundRumble] Profile save failed for " .. player.Name .. ": " .. tostring(err))
		if attempt < attempts then
			task.wait(1)
		end
	end
	if ok and lost then
		-- Another server took this profile over: stop writing (and stop granting purchases).
		warn("[ReboundRumble] Profile for " .. player.Name .. " is locked by another server; not saving")
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
end

local function sanitizeSettings(incoming)
	if type(incoming) ~= "table" then
		return nil
	end
	local clean = {}
	for k, spec in pairs(SETTINGS_SCHEMA) do
		local v = incoming[k]
		if type(spec[1]) == "boolean" then
			if type(v) == "boolean" then
				clean[k] = v
			end
		elseif type(v) == "number" and v == v then
			clean[k] = math.clamp(v, spec[1], spec[2])
		end
	end
	return clean
end

function DataService.start()
	local remotes = services.Remotes
	local lastSettingsSave = {}
	remotes.SaveSettings.OnServerEvent:Connect(function(player, incoming)
		local data = DataService.getProfile(player)
		local now = os.clock()
		if not data or (lastSettingsSave[player] and now - lastSettingsSave[player] < 1) then
			return
		end
		lastSettingsSave[player] = now
		local clean = sanitizeSettings(incoming)
		if clean then
			for k, v in pairs(clean) do
				data.Settings[k] = v
			end
			DataService.markDirty(player)
		end
	end)

	Players.PlayerAdded:Connect(DataService.load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = profiles[player]
		if entry then
			entry.leaving = true
		end
		-- Cleanup that doesn't need the save runs first (and any progress it records, such as
		-- a round that ends because this player left, makes it into the leave save).
		lastSettingsSave[player] = nil
		for _, name in ipairs(REMOVING_ORDER) do
			local service = services[name]
			if service and service.onPlayerRemoving then
				local ok, err = pcall(service.onPlayerRemoving, player)
				if not ok then
					warn("[ReboundRumble] " .. name .. ".onPlayerRemoving failed: " .. tostring(err))
				end
			end
		end
		-- Then save (retries) and unlock.
		DataService.save(player)
		DataService.release(player)
	end)
	game:BindToClose(function()
		-- Save everyone in parallel (sequential saves can run past the shutdown limit).
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
			-- Every profile is saved (not just dirty ones) so the session lock stays fresh.
			for player in pairs(profiles) do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
