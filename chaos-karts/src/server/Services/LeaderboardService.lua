--[[
	LeaderboardService - two global boards (OrderedDataStore): Most Wins, and the fastest
	lap on Chaos City (stored in milliseconds, sorted ascending). Shown on the lobby boards
	and in the menu. Writes are batched (each player at most every WriteInterval and on
	leave, only when the value changed); the boards refresh every Refresh seconds.
	Everything is pcall'd: an outage just leaves the board as it was.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)

local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local LeaderboardService = {}

local services
local world
local stores = {}
local lastWrite = {}
local written = {}
local names = {}
local rows = { Wins = {}, BestLap = {} }
local ASCENDING = { BestLap = true }

function LeaderboardService.init(registry)
	services = registry
	for key, name in pairs(GameConfig.Leaderboard.Stores) do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(name .. STORE_SUFFIX)
		end)
		stores[key] = if ok then result else nil
	end
end

function LeaderboardService.setWorld(newWorld)
	world = newWorld
end

local function write(player)
	local data = services.DataService.getProfile(player)
	if not data or not services.DataService.isPersistent(player) then
		return
	end
	lastWrite[player] = os.clock()
	written[player] = written[player] or {}
	for key, store in pairs(stores) do
		local value
		if key == "BestLap" then
			local best = data.BestLaps[GameConfig.Race.Map]
			value = if best then math.floor(best * 1000 + 0.5) else 0
		else
			value = math.floor(data.Stats.Wins or 0)
		end
		if value > 0 and written[player][key] ~= value then
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				written[player][key] = value
			end
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
	for key, store in pairs(stores) do
		local ok, page = pcall(function()
			return store:GetSortedAsync(ASCENDING[key] == true, GameConfig.Leaderboard.Rows):GetCurrentPage()
		end)
		if ok and page then
			local list = {}
			for i, entry in ipairs(page) do
				local userId = tonumber(entry.key) or 0
				list[i] = { userId = userId, name = nameOf(userId), value = entry.value }
			end
			rows[key] = list
		end
	end
	local boardRows = world and world.lobby and world.lobby.boardRows
	if boardRows then
		for key, labels in pairs(boardRows) do
			for i, label in ipairs(labels) do
				local entry = rows[key] and rows[key][i]
				local shown = if entry and key == "BestLap" then Format.raceTime(entry.value / 1000) elseif entry then Format.short(entry.value) else nil
				label.Text = if entry then string.format("%d. %s  %s", i, entry.name, shown) else string.format("%d. ---", i)
			end
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
