--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults + migration (SchemaVersion in GameConfig).
	* Autosave of dirty profiles, save on leave and on BindToClose.
	* leaderstats: Wins, Streak, Coins.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Economy = require(Shared.Economy)

local DataService = {}

local services
local profiles = {}
local store

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
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
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
			warn(string.format("[ReboundRumble] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
			task.wait(1.5 * attempt)
		end
	end
	if not player.Parent then
		return
	end
	profiles[player] = { data = DataService.reconcile(data), persistent = persistent, dirty = false }
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
	local data = entry.data
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[ReboundRumble] Profile save failed for " .. player.Name .. ": " .. tostring(err))
	end
	entry.dirty = not ok
	return ok
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
		DataService.save(player)
		profiles[player] = nil
		lastSettingsSave[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for player, entry in pairs(profiles) do
				if entry.dirty then
					DataService.save(player)
				end
			end
		end
	end)
end

return DataService
