--[[
	LeaderboardService - global "Total Coins Earned" board (OrderedDataStore).

	Every RefreshInterval seconds: write each online player's TotalEarned, read the top 10,
	resolve names (cached) and update the board in the plaza + send rows to clients. Every
	DataStore call is pcall'd; if the store is unavailable the board shows this server's
	players instead.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)

local LeaderboardService = {}

local REFRESH = 60

local services
local board
local store
local names = {}
local rows = {}

function LeaderboardService.init(registry)
	services = registry
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

local function nameFor(userId)
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and name then name else ("Gardener " .. tostring(userId))
	return names[userId]
end

local function localRows()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = services.DataService.getProfile(player)
		if profile then
			table.insert(list, { name = player.DisplayName, value = profile.TotalEarned, userId = player.UserId })
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

function LeaderboardService.render(list)
	rows = list
	if board then
		for i, label in ipairs(board.rows) do
			local row = list[i]
			label.Text = if row then string.format("%d.  %s   %s", i, row.name, Format.coins(row.value)) else string.format("%d.  ---", i)
		end
	end
	services.Remotes.Leaderboard:FireAllClients(rows)
end

function LeaderboardService.sendTo(player)
	services.Remotes.Leaderboard:FireClient(player, rows)
end

function LeaderboardService.refresh()
	if not store then
		LeaderboardService.render(localRows())
		return false
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = services.DataService.getProfile(player)
		if profile and profile.TotalEarned > 0 then
			pcall(function()
				store:SetAsync(tostring(player.UserId), math.floor(profile.TotalEarned))
			end)
		end
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		LeaderboardService.render(localRows())
		return false
	end
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage then
		LeaderboardService.render(localRows())
		return false
	end
	local list = {}
	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(list, { name = nameFor(userId), value = entry.value, userId = userId })
		end
	end
	LeaderboardService.render(list)
	return true
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			local ok, err = pcall(LeaderboardService.refresh)
			if not ok then
				warn("[SproutValley] leaderboard refresh failed: " .. tostring(err))
			end
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
