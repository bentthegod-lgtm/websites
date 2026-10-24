--[[
	DataService - player profiles in a DataStore, with a safe in-memory fallback when
	DataStores are unavailable (Studio without API access, outages).

	* Versioned defaults: missing fields are filled from defaultProfile() on load
	  (reconcile), and `migrate` upgrades older schema versions.
	* If a load fails after retries the profile is marked non-persistent and is NEVER
	  saved, so a DataStore hiccup can't wipe someone's real data.
	* Autosave every GameConfig.AutosaveInterval, save on leave and on BindToClose.
	* Releasing fires (synchronously) right before a leaving player's profile is saved,
	  so other services can write their last state (pending cash, LastSeen) into it.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Signal)

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player, data, info { persistent, firstJoin, offlineSeconds })
DataService.Releasing = Signal.new() -- (player, data)

local services
local profiles = {}
local store

function DataService.defaultProfile()
	return {
		Version = GameConfig.SchemaVersion,
		Cash = GameConfig.StartCash,
		TotalEarned = 0,
		Rebirths = 0,
		Blobbies = {}, -- [uid] = { Species = id, Mutation = key?, Slot = n }
		NextUid = 1,
		Queued = {}, -- Blobbies waiting for a free pedestal: { { Species, Mutation } }
		Discovered = {}, -- [speciesId] = true
		BestIncome = 0,
		Daily = { LastDay = 0, Streak = 0 },
		Codes = {}, -- [CODE] = true
		Receipts = {}, -- [purchaseId] = os.time()
		LastSeen = 0,
		Stats = { Bought = 0, Stolen = 0, Defended = 0, Robbed = 0, Sold = 0, Collected = 0, Slaps = 0 },
		Settings = { Music = true, Sfx = true },
		LockTokens = 0, -- paid "Lock Base Now" uses that couldn't be applied yet
	}
end

local function migrate(data)
	-- Version 1 is the first released schema. Future upgrades go here, e.g.
	-- if data.Version < 2 then ... end
	return data
end

-- Fills any fields missing from an older/partial profile (one level deep for tables).
function DataService.reconcile(data)
	local defaults = DataService.defaultProfile()
	if type(data) ~= "table" then
		return defaults
	end
	data = migrate(data)
	for key, value in pairs(defaults) do
		if data[key] == nil or type(data[key]) ~= type(value) then
			data[key] = value
		elseif type(value) == "table" then
			for k, v in pairs(value) do
				if data[key][k] == nil then
					data[key][k] = v
				end
			end
		end
	end
	-- Sanity: cash must be a finite non-negative number.
	if data.Cash ~= data.Cash or data.Cash == math.huge or data.Cash < 0 then
		data.Cash = 0
	end
	data.Version = GameConfig.SchemaVersion
	return data
end

function DataService.init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok and result then
		store = result
	else
		warn("[SnatchTycoon] DataStore unavailable, progress will not persist: " .. tostring(result))
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

local function key(player)
	return "player_" .. player.UserId
end

function DataService.load(player)
	if profiles[player] then
		return profiles[player].data
	end
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
			warn(string.format("[SnatchTycoon] Profile load failed for %s (attempt %d): %s", player.Name, attempt, tostring(result)))
			task.wait(1.5 * attempt)
		end
	end
	if not player.Parent then
		return nil
	end
	local firstJoin = data == nil
	data = DataService.reconcile(data)
	local now = os.time()
	local offlineSeconds = if data.LastSeen > 0 then math.max(0, now - data.LastSeen) else 0
	data.LastSeen = now
	profiles[player] = { data = data, persistent = persistent, dirty = false }
	DataService.ProfileLoaded:Fire(player, data, { persistent = persistent, firstJoin = firstJoin, offlineSeconds = offlineSeconds })
	if not persistent then
		services.Remotes.Notify:FireClient(player, "Saving is off (Studio or DataStore offline). Progress won't be kept.", "warn")
	end
	return data
end

function DataService.save(player)
	local entry = profiles[player]
	if not entry or not entry.persistent or not store then
		return false
	end
	local data = entry.data
	data.LastSeen = os.time()
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[SnatchTycoon] Profile save failed for " .. player.Name .. ": " .. tostring(err))
	end
	entry.dirty = not ok
	return ok
end

function DataService.release(player)
	local entry = profiles[player]
	if not entry then
		return
	end
	DataService.Releasing:Fire(player, entry.data)
	DataService.save(player)
	profiles[player] = nil
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		DataService.load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.release(player)
	end)
	game:BindToClose(function()
		for player, entry in pairs(profiles) do
			DataService.Releasing:Fire(player, entry.data)
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
