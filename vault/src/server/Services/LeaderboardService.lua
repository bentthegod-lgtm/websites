--[[
	LeaderboardService - four global boards (OrderedDataStore): total cash earned, deepest
	vault reached, total loot collected, best single deposit. Writes are batched (each
	player at most every LeaderboardWriteInterval, plus on leave); boards refresh every
	LeaderboardRefresh. Everything is pcall'd: a failure just leaves the board as it was.
	Only the display name and the number are shown.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local Format = require(Shared.Format)

local STORE_SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local LeaderboardService = {}

local services
local world
local stores = {}
local lastWrite = {}
local names = {}
local rows = {}

function LeaderboardService.init(registry)
	services = registry
	for _, lb in ipairs(GameConfig.Leaderboards) do
		rows[lb.Key] = {}
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(lb.Store .. STORE_SUFFIX)
		end)
		stores[lb.Key] = if ok then store else nil
	end
end

function LeaderboardService.setWorld(newWorld)
	world = newWorld
end

function LeaderboardService.values(data)
	return {
		Earned = data.TotalEarned,
		Depth = data.HighestDepth,
		Loot = data.Stats.Collect or 0,
		Deposit = data.BestDeposit,
	}
end

local function write(player)
	local data = services.DataService.getProfile(player)
	if not data or not services.DataService.isPersistent(player) then
		return
	end
	lastWrite[player] = os.clock()
	for key, value in pairs(LeaderboardService.values(data)) do
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

function LeaderboardService.format(key, value)
	if key == "Depth" then
		local def = DepthConfig.get(math.clamp(math.floor(value), 1, DepthConfig.Count))
		return def.Code .. " " .. def.Name
	end
	local lb
	for _, l in ipairs(GameConfig.Leaderboards) do
		if l.Key == key then
			lb = l
		end
	end
	return (if lb and lb.Money then "$" else "") .. Format.short(value)
end

function LeaderboardService.refresh()
	for key, store in pairs(stores) do
		local ok, page = pcall(function()
			return store:GetSortedAsync(false, 10):GetCurrentPage()
		end)
		if ok and page then
			local list = {}
			for i, entry in ipairs(page) do
				list[i] = { userId = tonumber(entry.key) or 0, name = nameOf(tonumber(entry.key) or 0), value = entry.value }
			end
			rows[key] = list
		end
	end
	if world and world.boards then
		for key, board in pairs(world.boards) do
			for i, label in ipairs(board.rows) do
				local entry = rows[key] and rows[key][i]
				label.Text = if entry then string.format("%d.  %s  -  %s", i, entry.name, LeaderboardService.format(key, entry.value)) else string.format("%d.  ---", i)
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
