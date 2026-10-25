--[[
	LeaderboardService - two global boards (OrderedDataStore): total scrap value sold and
	rare discoveries. Writes are batched (each player at most every
	GameConfig.LeaderboardWriteInterval, plus on leave); boards refresh every
	GameConfig.LeaderboardRefresh. Everything is pcall'd; failures just leave the board.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)

local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local LeaderboardService = {}

local services
local world
local stores = {}
local lastWrite = {}
local names = {}
local rows = { value = {}, rare = {} }

function LeaderboardService.init(registry)
	services = registry
	for key, name in pairs({ value = GameConfig.LeaderboardValueStore, rare = GameConfig.LeaderboardRareStore }) do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(name .. STORE_SUFFIX)
		end)
		stores[key] = if ok then store else nil
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
	for key, value in pairs({ value = data.TotalScrapValue, rare = data.RareFinds }) do
		local store = stores[key]
		if store then
			pcall(function()
				store:SetAsync(tostring(player.UserId), math.floor(value))
			end)
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
			return store:GetSortedAsync(false, 10):GetCurrentPage()
		end)
		if ok and page then
			local list = {}
			for i, entry in ipairs(page) do
				list[i] = { name = nameOf(tonumber(entry.key) or 0), value = entry.value }
			end
			rows[key] = list
		end
	end
	if world and world.boards then
		for key, board in pairs(world.boards) do
			for i, label in ipairs(board.rows) do
				local entry = rows[key][i]
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
