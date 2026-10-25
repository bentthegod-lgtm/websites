--[[
	ZoneService - zone unlocks and the gate.

	* unlock() checks the zone exists and is built, the previous zone is unlocked, the
	  magnet is strong enough and the price can be paid - then saves it in profile.Zones.
	* The gate barrier is solid for everyone on the server; each client turns it
	  non-solid locally once its own profile has the zone (so friends can't sneak in).
	* enforce(): anyone standing inside a zone they haven't unlocked is moved back to the
	  gate (catches exploits and prestige resets). Scrap in a locked zone can't be
	  collected anyway (MagnetService checks profile.Zones).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Format = require(Shared.Format)

local ZoneService = {}

local services
local world
local lastRequest = {}

function ZoneService.init(registry)
	services = registry
end

function ZoneService.setWorld(newWorld)
	world = newWorld
end

function ZoneService.unlockedCount(data)
	local n = 0
	for _ in pairs(data.Zones) do
		n += 1
	end
	return n
end

-- Returns ok, message.
function ZoneService.unlock(player, zoneId)
	local data = services.DataService.getProfile(player)
	local zone = ZoneConfig.ById[zoneId]
	if not data then
		return false, "Your data is still loading."
	end
	if not zone or not zone.Unlock then
		return false, "Unknown zone."
	end
	if not zone.Built then
		return false, zone.Name .. " is coming in a future update."
	end
	if data.Zones[zoneId] then
		return false, zone.Name .. " is already unlocked."
	end
	local previous = ZoneConfig.List[zone.Order - 1]
	if previous and not data.Zones[previous.Id] then
		return false, "Unlock " .. previous.Name .. " first."
	end
	local stats = services.UpgradeService.statsFor(player)
	if stats.MagnetStrength < zone.Unlock.Strength then
		return false, string.format("%s needs magnet strength %d (you have %s).", zone.Name, zone.Unlock.Strength, Format.stat(stats.MagnetStrength))
	end
	if not services.DataService.spendCoins(player, zone.Unlock.Coins) then
		return false, string.format("%s costs %s coins.", zone.Name, Format.short(zone.Unlock.Coins))
	end
	data.Zones[zoneId] = true
	services.DataService.setStat(player, "Zone", ZoneService.unlockedCount(data))
	services.Analytics.funnel(player, "FirstZone")
	services.Remotes.Popup:FireClient(player, "Zone", { zone = zoneId, name = zone.Name })
	services.Remotes.Announce:FireAllClients(string.format("%s unlocked %s!", player.DisplayName, zone.Name), { 150, 190, 255 })
	services.DataService.sendProfile(player)
	return true, zone.Name .. " unlocked! Head through the gate."
end

function ZoneService.enforce(player)
	local data = services.DataService.getProfile(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not data or not root then
		return
	end
	local zoneId = ZoneConfig.zoneAt(root.Position.X, root.Position.Z)
	if zoneId and not data.Zones[zoneId] then
		root.CFrame = CFrame.new(world.gate.outside)
		services.Remotes.Notify:FireClient(player, "That zone is locked - unlock it at the gate.", "warn")
	end
end

function ZoneService.onPlayerRemoving(player)
	lastRequest[player] = nil
end

function ZoneService.start()
	services.Remotes.UnlockZone.OnServerEvent:Connect(function(player, zoneId)
		local t = os.clock()
		if type(zoneId) ~= "string" or #zoneId > 32 or (lastRequest[player] and t - lastRequest[player] < 0.5) then
			return
		end
		lastRequest[player] = t
		local ok, message = ZoneService.unlock(player, zoneId)
		services.Remotes.Notify:FireClient(player, message, if ok then "good" else "error")
	end)
	world.gate.prompt.Triggered:Connect(function(player)
		local data = services.DataService.getProfile(player)
		if data and data.Zones[world.gate.zoneId] then
			services.Remotes.Notify:FireClient(player, "The gate is open for you - walk through!", "info")
			return
		end
		services.Remotes.Popup:FireClient(player, "GateMenu", { zone = world.gate.zoneId })
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				ZoneService.enforce(player)
			end
		end
	end)
end

return ZoneService
