--[[
	LeaderboardService - two global boards (OrderedDataStore): best run score and farthest
	flight. Writes are batched (each player at most every GameConfig.LeaderboardWriteInterval
	and on leave, only when the value changed); boards refresh every
	GameConfig.LeaderboardRefresh. Everything is pcall'd; failures just leave the board.
	Friends: clients highlight friends' rows locally (the board data is the same for all).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
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
local rows = { score = {}, distance = {} }

function LeaderboardService.init(registry)
	services = registry
	for k, name in pairs({ score = GameConfig.LeaderboardScoreStore, distance = GameConfig.LeaderboardDistanceStore }) do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(name .. STORE_SUFFIX)
		end)
		stores[k] = if ok then store else nil
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
	for k, value in pairs({ score = data.Stats.BestScore or 0, distance = data.Stats.BestDistance or 0 }) do
		local store = stores[k]
		value = math.floor(value)
		if store and value > 0 and written[player][k] ~= value then
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				written[player][k] = value
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
	for k, store in pairs(stores) do
		local ok, page = pcall(function()
			return store:GetSortedAsync(false, 10):GetCurrentPage()
		end)
		if ok and page then
			local list = {}
			for i, entry in ipairs(page) do
				local userId = tonumber(entry.key) or 0
				list[i] = { userId = userId, name = nameOf(userId), value = entry.value }
			end
			rows[k] = list
		end
	end
	if world and world.boards then
		for k, board in pairs(world.boards) do
			for i, label in ipairs(board.rows) do
				local entry = rows[k][i]
				label.Text = if entry then string.format("%d. %s  -  %s", i, entry.name, Format.short(entry.value)) else string.format("%d. ---", i)
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
				if not lastWrite[player] or os.clock() - lastWrite[player] >= GameConfig.LeaderboardWriteInterval then
					write(player)
				end
			end
			LeaderboardService.refresh()
			task.wait(GameConfig.LeaderboardRefresh)
		end
	end)
end

return LeaderboardService
