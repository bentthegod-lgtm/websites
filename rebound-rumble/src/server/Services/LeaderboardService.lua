--[[
	LeaderboardService - global "Most Wins" board in the lobby (OrderedDataStore).
	Every DataStore call is wrapped in pcall; the board shows a friendly message when the
	store is unavailable (Studio without API access).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)

local LeaderboardService = {}

local _services
local store
local board -- { setRows = function(rows, message) }
local names = {}
local REFRESH = 60

function LeaderboardService.init(registry)
	_services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LeaderboardStoreName)
	end)
	if ok then
		store = result
	end
end

function LeaderboardService.setBoard(b)
	board = b
end

function LeaderboardService.submit(player, wins)
	if not store or type(wins) ~= "number" then
		return
	end
	task.spawn(function()
		pcall(function()
			store:SetAsync(tostring(player.UserId), math.floor(wins))
		end)
	end)
end

local function nameFor(userId)
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		names[userId] = name
		return name
	end
	return "Player " .. tostring(userId)
end

function LeaderboardService.refresh()
	if not board then
		return
	end
	if not store then
		board.setRows({}, "Leaderboard offline (enable API access)")
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		board.setRows({}, "Leaderboard loading...")
		return
	end
	local rows = {}
	local okPage, entries = pcall(function()
		return pages:GetCurrentPage()
	end)
	if okPage and entries then
		for rank, entry in ipairs(entries) do
			local userId = tonumber(entry.key)
			table.insert(rows, { rank = rank, name = if userId then nameFor(userId) else "?", wins = entry.value })
		end
	end
	board.setRows(rows, if #rows == 0 then "No wins yet - be the first!" else nil)
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			LeaderboardService.refresh()
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
