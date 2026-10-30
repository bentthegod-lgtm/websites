--[[
	LeaderboardService - "Most escapes" global board (OrderedDataStore) on the lobby sign
	and in the menu. Writes are batched (each player at most every WriteInterval and on
	leave, only when the value changed); the board refreshes every Refresh seconds.
	Everything is pcall'd: a DataStore outage just leaves the board as it was.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)

local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local LeaderboardService = {}

local services
local world
local store
local lastWrite = {}
local written = {}
local names = {}
local rows = {}

function LeaderboardService.init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LeaderboardStoreName .. STORE_SUFFIX)
	end)
	store = if ok then result else nil
end

function LeaderboardService.setWorld(newWorld)
	world = newWorld
end

local function write(player)
	local data = services.DataService.getProfile(player)
	if not data or not store or not services.DataService.isPersistent(player) then
		return
	end
	lastWrite[player] = os.clock()
	local value = math.floor(data.Stats.Escapes or 0)
	if value > 0 and written[player] ~= value then
		local ok = pcall(function()
			store:SetAsync(tostring(player.UserId), value)
		end)
		if ok then
			written[player] = value
		end
	end
end

local function nameOf(userId)
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and name then name else ("Player " .. userId)
	return names[userId]
end

function LeaderboardService.refresh()
	if store then
		local ok, page = pcall(function()
			return store:GetSortedAsync(false, 10):GetCurrentPage()
		end)
		if ok and page then
			local list = {}
			for i, entry in ipairs(page) do
				local userId = tonumber(entry.key) or 0
				list[i] = { userId = userId, name = nameOf(userId), value = entry.value }
			end
			rows = list
		end
	end
	if world and world.boardRows then
		for i, label in ipairs(world.boardRows) do
			local entry = rows[i]
			label.Text = if entry then string.format("%d. %s  -  %s", i, entry.name, Format.short(entry.value)) else string.format("%d. ---", i)
		end
	end
	services.Remotes.Leaderboard:FireAllClients(rows)
end

function LeaderboardService.rows()
	return rows
end

function LeaderboardService.onPlayerRemoving(player)
	write(player)
	lastWrite[player] = nil
	written[player] = nil
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				if not lastWrite[player] or os.clock() - lastWrite[player] >= GameConfig.Leaderboard.WriteInterval then
					write(player)
				end
			end
			LeaderboardService.refresh()
			task.wait(GameConfig.Leaderboard.Refresh)
		end
	end)
end

return LeaderboardService
