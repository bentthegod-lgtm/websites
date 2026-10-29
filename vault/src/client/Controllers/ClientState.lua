--[[
	ClientState - the client's copy of server state plus signals other controllers listen
	to. Only the server's snapshots are trusted for display; the client never decides
	values, capacity, prices or rewards (Economy.stats here only mirrors the server's maths
	for showing upgrade effects and the collection radius ring).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Economy = require(Shared.Economy)
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)

local ClientState = {}

ClientState.profile = nil
ClientState.inventory = { count = 0, slots = 0, capacity = Economy.Base.Capacity, value = 0, items = {} }
ClientState.settings = nil
ClientState.leaderboard = {}
ClientState.riding = nil -- elevator ride in progress { to, duration, startedAt }
ClientState.serverOffset = 0 -- server os.time() - client os.time()

ClientState.ProfileChanged = Signal.new()
ClientState.InventoryChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.Notified = Signal.new() -- (text, kind)
ClientState.Announced = Signal.new() -- (text, color)
ClientState.PopupRequested = Signal.new() -- (kind, data)
ClientState.LeaderboardChanged = Signal.new()
ClientState.Collected = Signal.new() -- (userId, lootId, itemId, position, value)
ClientState.Deposited = Signal.new() -- (userId, summary)
ClientState.ElevatorEvent = Signal.new() -- (phase, data)
ClientState.RareEvent = Signal.new() -- (phase, data)
ClientState.DepthChanged = Signal.new() -- (depth) the local character moved to another floor

function ClientState.player()
	return Players.LocalPlayer
end

function ClientState.root()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- The depth the local character is on (by height band), or the saved one.
function ClientState.depth()
	local root = ClientState.root()
	if root then
		return DepthConfig.depthAtY(root.CFrame.Position.Y, GameConfig.DepthSpacing)
	end
	return ClientState.profile and ClientState.profile.currentDepth or 1
end

function ClientState.serverTime()
	return os.time() + ClientState.serverOffset
end

-- Mirror of the server's stats for display.
function ClientState.stats()
	local p = ClientState.profile
	if not p then
		return Economy.stats(nil)
	end
	return Economy.stats({ Upgrades = p.upgrades, Perks = p.perks, Rebirths = p.rebirths, BoostUntil = p.boostUntil, Vip = p.vip }, ClientState.serverTime())
end

function ClientState.isFull()
	local inv = ClientState.inventory
	return inv.slots >= inv.capacity and inv.capacity > 0
end

function ClientState.setting(key)
	local s = ClientState.settings or (ClientState.profile and ClientState.profile.settings)
	if s == nil then
		return nil
	end
	return s[key]
end

function ClientState.applySettings(changes)
	ClientState.settings = ClientState.settings or {}
	for k, v in pairs(changes) do
		ClientState.settings[k] = v
	end
	ClientState.SettingsChanged:Fire(ClientState.settings)
end

function ClientState.saveSettings()
	if ClientState.settings then
		Net.event("SaveSettings"):FireServer(ClientState.settings)
	end
end

function ClientState.init()
	local function on(name, fn)
		Net.event(name).OnClientEvent:Connect(fn)
	end
	on("Profile", function(snapshot)
		local first = ClientState.profile == nil
		ClientState.profile = snapshot
		if snapshot.serverTime then
			ClientState.serverOffset = snapshot.serverTime - os.time()
		end
		if first or not ClientState.settings then
			ClientState.settings = table.clone(snapshot.settings or {})
			ClientState.SettingsChanged:Fire(ClientState.settings)
		end
		ClientState.ProfileChanged:Fire(snapshot)
	end)
	on("Inventory", function(view)
		ClientState.inventory = view or ClientState.inventory
		ClientState.InventoryChanged:Fire(ClientState.inventory)
	end)
	on("Notify", function(text, kind)
		ClientState.Notified:Fire(text, kind)
	end)
	on("Announce", function(text, color)
		ClientState.Announced:Fire(text, color)
	end)
	on("Popup", function(kind, data)
		ClientState.PopupRequested:Fire(kind, data or {})
	end)
	on("Leaderboard", function(rows)
		ClientState.leaderboard = rows or ClientState.leaderboard
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
	on("Collected", function(userId, lootId, itemId, position, value)
		ClientState.Collected:Fire(userId, lootId, itemId, position, value)
	end)
	on("Deposited", function(userId, summary)
		ClientState.Deposited:Fire(userId, summary or {})
	end)
	on("Elevator", function(phase, data)
		data = data or {}
		if phase == "Depart" then
			ClientState.riding = { to = data.to, from = data.from, duration = data.duration, startedAt = os.clock() }
		else
			ClientState.riding = nil
		end
		ClientState.ElevatorEvent:Fire(phase, data)
	end)
	on("RareEvent", function(phase, data)
		ClientState.RareEvent:Fire(phase, data or {})
	end)
end

return ClientState
