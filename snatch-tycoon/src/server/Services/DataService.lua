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
	* Session lock: the stored profile carries Lock = { JobId, Time }. Loading takes the
	  lock with UpdateAsync (waiting while another live server holds it, stealing it once
	  it is older than SESSION_LOCK_STALE), every save refreshes it and the save on leave
	  clears it. A save that finds another server's lock is cancelled, so a fast server
	  hop can never overwrite newer data with an older copy.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Signal)

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player, data, info { persistent, firstJoin, offlineSeconds })
DataService.Releasing = Signal.new() -- (player, data)

local services
local profiles = {}
local store
local releasing = {} -- [userId] = true while that user's leave-save is in flight
local departed = setmetatable({}, { __mode = "k" }) -- players that fired PlayerRemoving

local SESSION_LOCK_STALE = 180 -- seconds; a lock this old belongs to a dead server
local LOCK_WAITS = 6 -- tries (2 s apart) while another server still holds the lock

-- Identifies this server in session locks. Studio has no JobId, so every Studio session
-- shares one id (and Studio never waits on a lock).
local SERVER_ID = (function()
	local ok, id = pcall(function()
		return game.JobId
	end)
	return if ok and type(id) == "string" and id ~= "" then id else "studio"
end)()
DataService.SERVER_ID = SERVER_ID

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

-- Is `lock` (a stored Lock field) held by another, still-live server?
function DataService.lockedByOther(lock, now)
	return type(lock) == "table" and lock.JobId ~= SERVER_ID and now - (tonumber(lock.Time) or 0) < SESSION_LOCK_STALE
end

-- Clears our lock without touching the rest (used when the player left mid-load).
local function clearLock(storeKey)
	pcall(function()
		store:UpdateAsync(storeKey, function(old)
			if type(old) ~= "table" or type(old.Lock) ~= "table" or old.Lock.JobId ~= SERVER_ID then
				return nil
			end
			old.Lock = nil
			return old
		end)
	end)
end

function DataService.load(player)
	if profiles[player] then
		return profiles[player].data
	end
	local data
	local persistent = false
	local isNew = false
	-- Rejoining the same server: wait for the previous session's leave-save to land.
	local waited = 0
	while releasing[player.UserId] and waited < 15 do
		waited += task.wait(0.25) or 0.25
	end
	if store then
		local failures, lockWaits = 0, 0
		while true do
			local locked = false
			local ok, result = pcall(function()
				local loaded
				store:UpdateAsync(key(player), function(old)
					local now = os.time()
					locked = type(old) == "table" and DataService.lockedByOther(old.Lock, now) and not RunService:IsStudio()
					if locked then
						return nil -- leave it alone, another server still owns this profile
					end
					isNew = old == nil
					loaded = if type(old) == "table" then old else {}
					loaded.Lock = { JobId = SERVER_ID, Time = now }
					return loaded
				end)
				return loaded
			end)
			if ok and not locked then
				data = result
				persistent = true
				break
			elseif ok then
				lockWaits += 1
				if lockWaits >= LOCK_WAITS then
					warn("[SnatchTycoon] Profile of " .. player.Name .. " is still locked by another server")
					if player.Parent then
						player:Kick("Your data is still being saved by another server. Please rejoin in a minute.")
					end
					return nil
				end
				task.wait(2)
			else
				failures += 1
				warn(string.format("[SnatchTycoon] Profile load failed for %s (attempt %d): %s", player.Name, failures, tostring(result)))
				if failures >= 3 then
					break
				end
				task.wait(1.5 * failures)
			end
			if not player.Parent or departed[player] then
				break
			end
		end
	end
	if not player.Parent or departed[player] then
		if persistent then
			clearLock(key(player))
		end
		return nil
	end
	local firstJoin = isNew or data == nil
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

-- final = true clears the session lock (the player is leaving / the server is closing).
function DataService.save(player, final)
	local entry = profiles[player]
	if not entry or not entry.persistent or not store then
		return false
	end
	local data = entry.data
	data.LastSeen = os.time()
	local lost = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function(old)
			lost = type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= SERVER_ID
			if lost then
				return nil -- another server took over this profile; never overwrite its data
			end
			-- entry.released: a save still in flight when the player left must not re-lock.
			data.Lock = if final or entry.released then nil else { JobId = SERVER_ID, Time = os.time() }
			return data
		end)
	end)
	if not ok then
		warn("[SnatchTycoon] Profile save failed for " .. player.Name .. ": " .. tostring(err))
	elseif lost then
		warn("[SnatchTycoon] Session lock for " .. player.Name .. " was taken by another server; saving stopped")
		entry.persistent = false
		ok = false
	end
	entry.dirty = not ok
	return ok
end

function DataService.release(player)
	local entry = profiles[player]
	if not entry then
		return
	end
	local userId = player.UserId
	releasing[userId] = true
	entry.released = true
	DataService.Releasing:Fire(player, entry.data)
	DataService.save(player, true)
	profiles[player] = nil
	releasing[userId] = nil
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		DataService.load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		departed[player] = true
		DataService.release(player)
	end)
	game:BindToClose(function()
		-- Release everyone in parallel (clears the session locks); PlayerRemoving then finds
		-- nothing left to do. Roblox gives BindToClose about 30 s.
		local pending = 0
		for _, player in ipairs(DataService.loadedPlayers()) do
			pending += 1
			task.spawn(function()
				DataService.release(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			-- Every persistent profile saves (not only dirty ones) so its session lock stays
			-- fresh. Iterate a copy: saves yield while players join and leave.
			for _, player in ipairs(DataService.loadedPlayers()) do
				local entry = profiles[player]
				if entry and entry.persistent then
					DataService.save(player)
				end
			end
		end
	end)
end

return DataService
