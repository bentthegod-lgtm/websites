--[[
	PlayerService - characters, the depth each player is on, and per-player presentation
	attributes other clients read (carried stack, theme, trail, VIP tag).

	* Spawning: once the profile is loaded, every new character is placed in the elevator
	  cabin of the player's current depth (CurrentDepth), so a respawn never strands anyone
	  on a floor they can't use.
	* Death rule: carried loot is KEPT through a respawn (the vault has no hazards, so dying
	  is only ever a reset / fall; losing a stack to it would feel arbitrary). It is stored
	  in the profile, so it also survives a disconnect.
	* Walk speed follows the Movement Speed upgrade and is re-applied on every spawn.
	* Walking down: the depths are joined by tunnels, so a player who walks onto the next
	  (unlocked) depth's rim has it recorded as their current depth, like an elevator ride.
	* Safety: twice a second every character must be inside one of the world's safe volumes
	  (rims, pools, tunnels - VaultBuilder's safe zones). Anyone outside them (fell through
	  the map, glitched into rock, or got past a locked door onto a depth they haven't
	  unlocked) is put back in the elevator on their current depth's rim.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local LootConfig = require(Shared.Config.LootConfig)

local PlayerService = {}

local services
local world
local connections = {}
local safetyClock = 0
PlayerService.Rescues = 0

function PlayerService.init(registry)
	services = registry
end

function PlayerService.setWorld(newWorld)
	world = newWorld
end

function PlayerService.root(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil
end

-- The depth the player's character is on right now (by height band), or their saved depth.
function PlayerService.depthOf(player)
	local root = PlayerService.root(player)
	if root then
		return DepthConfig.depthAtY(root.CFrame.Position.Y, GameConfig.DepthSpacing)
	end
	local data = services.DataService.getProfile(player)
	return data and data.CurrentDepth or 1
end

function PlayerService.playersOnDepth(depth)
	local list = {}
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		if PlayerService.root(player) and PlayerService.depthOf(player) == depth then
			table.insert(list, player)
		end
	end
	return list
end

function PlayerService.applyStats(player)
	local _, humanoid = PlayerService.root(player)
	if humanoid then
		humanoid.WalkSpeed = services.DataService.stats(player).WalkSpeed
	end
end

-- Presentation attributes read by every client's StackController / effects.
function PlayerService.updateAttributes(player)
	local data = services.DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	local parts = {}
	local byCategory = {}
	for id, n in pairs(data.Carried.Items) do
		local def = LootConfig.ById[id]
		if def then
			byCategory[def.Category] = (byCategory[def.Category] or 0) + n
		end
	end
	for _, category in ipairs(LootConfig.CategoryOrder) do
		if byCategory[category] then
			table.insert(parts, category .. "=" .. byCategory[category])
		end
	end
	player:SetAttribute("V_Stack", table.concat(parts, ";"))
	player:SetAttribute("V_Count", data.Carried.Count)
	player:SetAttribute("V_Capacity", services.DataService.stats(player).Capacity)
	player:SetAttribute("V_Theme", data.Cosmetics.Theme)
	player:SetAttribute("V_Trail", data.Cosmetics.Trail)
	player:SetAttribute("V_Vip", services.ShopService and services.ShopService.ownsPass(player, "VIP") or false)
	player:SetAttribute("V_Depth", data.CurrentDepth)
end

function PlayerService.place(player, depth)
	local character = player.Character
	local record = world and world.depths[depth]
	if character and record and character.PrimaryPart then
		character:PivotTo(record.elevator.arrival)
	end
end

local function onCharacter(player, character)
	local data = services.DataService.getProfile(player)
	if not data then
		return -- placed by onProfileLoaded once the profile exists
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or player.Character ~= character then
		return
	end
	task.defer(function()
		if player.Character == character and character.Parent then
			PlayerService.place(player, data.CurrentDepth)
			PlayerService.applyStats(player)
		end
	end)
end

function PlayerService.onProfileLoaded(player)
	connections[player] = player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	PlayerService.updateAttributes(player)
end

function PlayerService.onPlayerRemoving(player)
	if connections[player] then
		connections[player]:Disconnect()
		connections[player] = nil
	end
end


local function inSafeZone(position)
	for _, record in ipairs(world.depths) do
		for _, zone in ipairs(record.safeZones or {}) do
			local lo, hi = zone[1], zone[2]
			if position.X >= lo.X - 2 and position.X <= hi.X + 2 and position.Y >= lo.Y - 2 and position.Y <= hi.Y + 8 and position.Z >= lo.Z - 2 and position.Z <= hi.Z + 2 then
				return true
			end
		end
	end
	return false
end
PlayerService.inSafeZone = inSafeZone

-- Puts a player back on their current depth's rim (out of bounds / locked depth).
function PlayerService.rescue(player, reason)
	local data = services.DataService.getProfile(player)
	if not data then
		return
	end
	PlayerService.Rescues += 1
	services.ElevatorService.cancel(player)
	PlayerService.place(player, data.CurrentDepth)
	services.Remotes.Notify:FireClient(player, reason or "You were returned to the rim.", "info")
end

-- Twice a second: out-of-bounds rescue and depth tracking for players who walk down.
function PlayerService.step(dt)
	safetyClock += dt
	if safetyClock < 0.5 or not world then
		return
	end
	safetyClock = 0
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		local root = PlayerService.root(player)
		local data = services.DataService.getProfile(player)
		if root and data and not services.ElevatorService.isRiding(player) then
			local pos = root.CFrame.Position
			local depth = DepthConfig.depthAtY(pos.Y, GameConfig.DepthSpacing)
			if not inSafeZone(pos) then
				PlayerService.rescue(player, "Out of bounds - you were returned to the rim.")
			elseif depth > data.HighestDepth then
				PlayerService.rescue(player, DepthConfig.get(depth).Name .. " is locked. Unlock it at the elevator panel first.")
			elseif depth ~= data.CurrentDepth then
				data.CurrentDepth = depth
				services.DataService.markDirty(player)
				PlayerService.updateAttributes(player)
				if depth > 1 then
					services.DataService.bump(player, "Visit:" .. depth, 1)
					services.QuestService.tutorialEvent(player, "TravelDeep")
				end
				services.DataService.sendProfile(player)
			end
		end
	end
end

function PlayerService.start()
	local remotes = services.Remotes
	local lastState = {}
	remotes.RequestState.OnServerEvent:Connect(function(player)
		local t = os.clock()
		if lastState[player] and t - lastState[player] < 2 then
			return
		end
		lastState[player] = t
		if services.DataService.getProfile(player) then
			services.DataService.sendProfileNow(player)
			services.LootService.sendInventory(player)
			services.Remotes.Leaderboard:FireClient(player, services.LeaderboardService.rows())
		end
	end)
	remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		local data = services.DataService.getProfile(player)
		if not data or type(settings) ~= "table" then
			return
		end
		for key, default in pairs(services.DataService.defaultSettings()) do
			local v = settings[key]
			if type(v) == type(default) then
				if type(v) == "number" then
					if v == v then
						data.Settings[key] = math.clamp(v, 0, 1)
					end
				else
					data.Settings[key] = v
				end
			end
		end
		services.DataService.markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastState[player] = nil
	end)
end

return PlayerService
