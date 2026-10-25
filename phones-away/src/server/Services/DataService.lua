--[[
	DataService - player profiles in DataStoreService with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults: missing fields are filled from defaultProfile() (reconcile), and
	  migrate() upgrades older SchemaVersions.
	* Autosave every GameConfig.AutosaveInterval, save on leave and on BindToClose.
	* Session lock (data.Lock): a server only writes a profile it holds the lock for, so a
	  quick rejoin on another server waits for the old server's leave save instead of
	  loading stale data, and a stale server can't overwrite newer progress. (Same reviewed
	  approach as Sprout Valley's DataService.)
	* Studio play-tests use a separate store ("_Studio" suffix), so free Studio test grants
	  never reach live data.
	* Profile snapshots for the client are coalesced (one per frame per player).
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Economy = require(Shared.Economy)

local DataService = {}

local services
local profiles = {}
local store
local pendingSend = {}
local sessionRng = Random.new()

-- A lock older than this belongs to a server that crashed (autosave refreshes it).
local LOCK_STALE = GameConfig.AutosaveInterval * 3
local LOAD_ATTEMPTS = 6

function DataService.storeName()
	return GameConfig.DataStoreName .. (if RunService:IsStudio() then "_Studio" else "")
end

local function defaultProfile()
	local upgrades = {}
	for _, key in ipairs(UpgradeConfig.Order) do
		upgrades[key] = UpgradeConfig[key].Start
	end
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
	return {
		Version = GameConfig.SchemaVersion,
		Clout = 0,
		TotalClout = 0,
		Level = 1,
		XP = 0,
		Upgrades = upgrades,
		Owned = owned,
		Equipped = equipped,
		Tokens = { DetentionPass = 0, HallPass = 0, Peek = 0 },
		Daily = { Last = 0, Streak = 0 },
		Codes = {},
		Stats = { Classes = 0, Tests = 0, Caught = 0, CleanClasses = 0, QuizCorrect = 0, Planes = 0, Reports = 0, BestClass = 0, Revealed = 0, APlus = 0, Ghosts = 0 },
		Pity = 0,
		Settings = { Pet = false },
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
		elseif type(value) == "table" and type(data[key]) == "table" then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	-- Clamp upgrade tiers to what exists in config.
	for _, key in ipairs(UpgradeConfig.Order) do
		local def = UpgradeConfig[key]
		local tier = tonumber(data.Upgrades[key]) or def.Start
		data.Upgrades[key] = math.clamp(math.floor(tier), def.Start, Economy.maxTier(UpgradeConfig, key))
	end
	-- Drop cosmetics that no longer exist; make sure every category has a valid equip.
	for _, category in ipairs(CosmeticConfig.Categories) do
		data.Owned[category] = type(data.Owned[category]) == "table" and data.Owned[category] or {}
		for id in pairs(data.Owned[category]) do
			local found = false
			for _, item in ipairs(CosmeticConfig.Items) do
				if item.Category == category and item.Id == id then
					found = true
				end
			end
			if not found then
				data.Owned[category][id] = nil
			end
		end
		local equipped = data.Equipped[category]
		if not equipped or not data.Owned[category][equipped] then
			data.Equipped[category] = defaults.Equipped[category]
			data.Owned[category][defaults.Equipped[category]] = true
		end
	end
	return migrate(data)
end
DataService.reconcile = reconcile

function DataService.init(registry)
	services = registry
	store = nil
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DataService.storeName())
	end)
	if ok then
		store = result
	else
		warn("[PhonesAway] DataStore unavailable, progress will not persist: " .. tostring(result))
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
		local clout = Instance.new("IntValue")
		clout.Name = "Clout"
		clout.Parent = stats
		local rank = Instance.new("StringValue")
		rank.Name = "Rank"
		rank.Parent = stats
		stats.Parent = player
	end
	stats.Clout.Value = math.floor(data.Clout)
	stats.Rank.Value = Economy.rankFor(data.Level, ProgressionConfig.Ranks).Name
	player:SetAttribute("PA_Level", data.Level)
	player:SetAttribute("PA_Rank", stats.Rank.Value)
end

function DataService.snapshot(player)
	local entry = profiles[player]
	if not entry then
		return nil
	end
	local data = entry.data
	local passes = services.ShopService and services.ShopService.passesFor(player) or {}
	local rank = Economy.rankFor(data.Level, ProgressionConfig.Ranks)
	return {
		clout = data.Clout,
		totalClout = data.TotalClout,
		level = data.Level,
		xp = data.XP,
		xpNext = Economy.xpToNext(data.Level, ProgressionConfig.XP),
		rank = rank.Name,
		rankColor = rank.Color,
		upgrades = data.Upgrades,
		owned = data.Owned,
		equipped = data.Equipped,
		tokens = data.Tokens,
		stats = data.Stats,
		pity = data.Pity,
		settings = data.Settings,
		passes = passes,
		phone = Economy.phoneStats(data.Upgrades, passes, UpgradeConfig),
		multiplier = services.ShopService and services.ShopService.cloutMultiplier(player) or 1,
		daily = services.RewardService and services.RewardService.dailyView(player) or nil,
		goals = services.RewardService and services.RewardService.goalsView(player) or {},
		randomItemsAllowed = services.ShopService == nil or services.ShopService.randomItemsAllowed(player),
		bailCost = Economy.bailCost(data.Level, GameConfig),
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

--[[
	Adds Clout. `earned` = true counts toward TotalClout (leaderboard) and XP. Purchases and
	codes are not "earned". Returns the amount actually added.
]]
function DataService.addClout(player, amount, earned)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount == math.huge then
		return 0
	end
	local before = data.Clout
	data.Clout = math.max(0, math.floor((data.Clout + amount) * 100 + 0.5) / 100)
	local added = data.Clout - before
	if earned and added > 0 then
		data.TotalClout += added
		DataService.addXP(player, added * ProgressionConfig.XPPerClout)
	end
	DataService.markDirty(player)
	return added
end

function DataService.spendClout(player, amount)
	local data = DataService.getProfile(player)
	if not data or type(amount) ~= "number" or amount ~= amount or amount < 0 or data.Clout < amount then
		return false
	end
	data.Clout -= amount
	DataService.markDirty(player)
	return true
end

function DataService.addXP(player, amount)
	local data = DataService.getProfile(player)
	if not data then
		return 0
	end
	data.XPCarry = (data.XPCarry or 0) + amount
	local whole = math.floor(data.XPCarry)
	data.XPCarry -= whole
	local level, xp, gained = Economy.addXP(data.Level, data.XP, whole, ProgressionConfig.XP)
	data.Level, data.XP = level, xp
	if gained > 0 then
		data.Clout += ProgressionConfig.XP.LevelUpClout * gained
		local rank = Economy.rankFor(level, ProgressionConfig.Ranks)
		services.Remotes.Effect:FireClient(player, "LevelUp", { level = level, rank = rank.Name, color = rank.Color, clout = ProgressionConfig.XP.LevelUpClout * gained })
		if rank.MinLevel == level and level > 1 then
			services.Remotes.Announce:FireAllClients(string.format("%s is now a %s!", player.DisplayName, rank.Name), rank.Color)
		end
		if services.RoundService then
			services.RoundService.refreshTag(player)
		end
	end
	DataService.markDirty(player)
	return gained
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

function DataService.load(player)
	local data
	local persistent = false
	local session = newSession()
	if store then
		for attempt = 1, LOAD_ATTEMPTS do
			local locked = false
			local ok, result = pcall(function()
				return store:UpdateAsync(key(player), function(old)
					-- UpdateAsync may run this transform more than once: only the last call counts.
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
				warn(string.format("[PhonesAway] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
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
			profiles[player] = { data = reconcile(data), persistent = true, dirty = false, session = session, leaving = true }
			DataService.save(player)
			DataService.release(player)
		end
		return
	end
	profiles[player] = { data = reconcile(data), persistent = persistent, dirty = false, session = session }
	for _, name in ipairs({ "ShopService", "RewardService", "CosmeticService", "RoundService", "LeaderboardService" }) do
		local service = services[name]
		if service and service.onProfileLoaded then
			local ok, err = pcall(service.onProfileLoaded, player)
			if not ok then
				warn("[PhonesAway] " .. name .. ".onProfileLoaded failed: " .. tostring(err))
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
	if not entry.persistent or not store then
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
				lost = false -- the transform can be retried: only the last call counts
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
		warn("[PhonesAway] Profile save failed for " .. player.Name .. ": " .. tostring(err))
		if attempt < attempts then
			task.wait(1)
		end
	end
	if ok and lost then
		-- Another server took this profile over: stop writing (and stop granting purchases).
		warn("[PhonesAway] Profile for " .. player.Name .. " is locked by another server; not saving")
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
		-- Let every service bank / clean up first (RoundService banks Clout earned this
		-- class), then save and unlock.
		for _, name in ipairs({ "RoundService", "PhoneService", "TestService", "ClassmateService", "RewardService", "CosmeticService", "ShopService" }) do
			local service = services[name]
			if service and service.onPlayerRemoving then
				pcall(service.onPlayerRemoving, player)
			end
		end
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
			-- Everyone is saved (not just dirty profiles) so the session lock stays fresh.
			for player in pairs(profiles) do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
