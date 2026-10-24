--[[
	LeaderboardService - global "highest income per second" board in the world, backed by
	an OrderedDataStore (all calls pcall'd, refreshed every GameConfig.LeaderboardRefresh s).
	When the OrderedDataStore is unavailable (Studio without API access) the board shows the
	players in this server instead.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)

local LeaderboardService = {}

local services
local world
local store
local posted = {} -- [userId] = last value written
local names = {} -- [userId] = name cache

function LeaderboardService.init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LeaderboardStoreName)
	end)
	if ok and result then
		store = result
	end
end

function LeaderboardService.setWorld(w)
	world = w
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
	names[userId] = if ok and name then name else ("Player " .. userId)
	return names[userId]
end

-- entries: { { name, value } } sorted high to low
function LeaderboardService.render(entries, title)
	local board = world and world.leaderboard
	if not board then
		return
	end
	board.title.Text = title
	for i, row in ipairs(board.rows) do
		local entry = entries[i]
		row.Text = if entry then string.format("%d. %s  -  %s", i, entry.name, Format.perSecond(entry.value)) else ""
	end
end

local function localEntries()
	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService.getProfile(player)
		if data then
			table.insert(entries, { name = player.DisplayName, value = data.BestIncome })
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	return entries
end

function LeaderboardService.refresh()
	if not store then
		LeaderboardService.render(localEntries(), "TOP EARNERS (this server)")
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService.getProfile(player)
		if data and data.BestIncome > (posted[player.UserId] or 0) then
			local value = math.floor(data.BestIncome)
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				posted[player.UserId] = value
			end
		end
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		LeaderboardService.render(localEntries(), "TOP EARNERS (this server)")
		return
	end
	local entries = {}
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if okPage and page then
		for _, item in ipairs(page) do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, { name = nameFor(userId), value = item.value })
			end
		end
	end
	LeaderboardService.render(entries, "TOP EARNERS ($/s)")
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			LeaderboardService.refresh()
			task.wait(GameConfig.LeaderboardRefresh)
		end
	end)
end

return LeaderboardService
