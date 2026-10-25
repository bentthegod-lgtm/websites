--[[
	LeaderboardService - global "Most Clout Ever" board in the hallway (OrderedDataStore of
	lifetime TotalClout). Every DataStore call is wrapped in pcall; Studio uses a separate
	"_Studio" store so free test grants never reach the live board. When the store is
	unavailable the board shows this server's players instead.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)

local LeaderboardService = {}

local services
local store
local board
local names = {}
local REFRESH = 60

function LeaderboardService.storeName()
	return GameConfig.LeaderboardStoreName .. (if RunService:IsStudio() then "_Studio" else "")
end

function LeaderboardService.init(registry)
	services = registry
	store = nil
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(LeaderboardService.storeName())
	end)
	if ok then
		store = result
	end
end

function LeaderboardService.setBoard(b)
	board = b
end

function LeaderboardService.submit(player)
	local profile = services.DataService.getProfile(player)
	if not store or not profile then
		return
	end
	local value = math.floor(profile.TotalClout)
	local userId = player.UserId
	task.spawn(function()
		pcall(function()
			store:SetAsync(tostring(userId), value)
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
	return "Student " .. tostring(userId)
end

local function localRows()
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = services.DataService.getProfile(player)
		if profile then
			table.insert(rows, { name = player.DisplayName, value = profile.TotalClout })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	for i, row in ipairs(rows) do
		row.rank = i
		row.text = Format.number(row.value) .. " Clout"
	end
	return rows
end

function LeaderboardService.refresh()
	if not board then
		return
	end
	if not store then
		board.setRows(localRows(), "global board offline - showing this server")
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		board.setRows(localRows(), "global board loading...")
		return
	end
	local okPage, entries = pcall(function()
		return pages:GetCurrentPage()
	end)
	local rows = {}
	if okPage and entries then
		for rank, entry in ipairs(entries) do
			local userId = tonumber(entry.key)
			table.insert(rows, { rank = rank, name = if userId then nameFor(userId) else "?", text = Format.number(entry.value) .. " Clout" })
		end
	end
	board.setRows(rows, if #rows == 0 then "No Clout yet - be the first!" else nil)
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
