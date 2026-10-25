--[[
	EventService - timed server-wide events. Currently: the Magnetic Storm.

	During a storm ScrapService spawns more scrap (and rare Storm Shards), everything
	collected is worth EventConfig ValueMultiplier more, and players who collect at least
	ParticipationTarget objects get a reward when it ends. Rewards are based on what each
	player actually collected during the storm, so the economy can't be flooded.

	State is published to clients via the Event remote and workspace attributes
	(MM_Event, MM_EventEnds) for the countdown.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local EventConfig = require(Shared.Config.EventConfig)

local EventService = {}

local services
local current -- { kind, endsAt (server time), participants = { [player] = { count, value } } }
local nextAt
local rng = Random.new()

function EventService.init(registry)
	services = registry
end

function EventService.current()
	return current
end

function EventService.valueMultiplier()
	if current and current.kind == "MagneticStorm" then
		return EventConfig.MagneticStorm.ValueMultiplier
	end
	return nil
end

function EventService.onCollect(player, value)
	if not current then
		return
	end
	local p = current.participants[player]
	if not p then
		p = { count = 0, value = 0 }
		current.participants[player] = p
	end
	p.count += 1
	p.value += value
end

local function publish(target)
	local view = nil
	if current then
		view = { kind = current.kind, name = EventConfig[current.kind].Name, endsAt = current.endsAt, target = EventConfig[current.kind].ParticipationTarget }
	else
		view = { kind = nil, nextAt = nextAt }
	end
	if target then
		services.Remotes.Event:FireClient(target, view)
	else
		services.Remotes.Event:FireAllClients(view)
	end
end
EventService.publish = publish

function EventService.startStorm()
	local cfg = EventConfig.MagneticStorm
	current = { kind = "MagneticStorm", endsAt = workspace:GetServerTimeNow() + cfg.Duration, participants = {} }
	services.ScrapService.stormMultiplier = cfg.SpawnMultiplier
	services.ScrapService.stormShardChance = cfg.StormShardChance
	workspace:SetAttribute("MM_Event", "MagneticStorm")
	workspace:SetAttribute("MM_EventEnds", current.endsAt)
	services.Remotes.Announce:FireAllClients("A MAGNETIC STORM is rolling in! Scrap is raining down - collect " .. cfg.ParticipationTarget .. " pieces for a bonus!", { 170, 120, 255 })
	publish()
end

function EventService.endStorm()
	local cfg = EventConfig.MagneticStorm
	local finished = current
	current = nil
	services.ScrapService.stormMultiplier = 1
	services.ScrapService.stormShardChance = 0
	workspace:SetAttribute("MM_Event", nil)
	workspace:SetAttribute("MM_EventEnds", nil)
	nextAt = workspace:GetServerTimeNow() + rng:NextNumber(cfg.IntervalMin, cfg.IntervalMax)
	if finished then
		for player, p in pairs(finished.participants) do
			if player.Parent and p.count >= cfg.ParticipationTarget and services.DataService.getProfile(player) then
				local reward = math.max(cfg.RewardMin, math.floor(p.value * 0.5))
				services.DataService.addCoins(player, reward, true)
				services.DataService.bump(player, "Storm", 1)
				services.Remotes.Popup:FireClient(player, "StormReward", { reward = reward, count = p.count })
				services.DataService.sendProfile(player)
			end
		end
	end
	services.Remotes.Announce:FireAllClients("The Magnetic Storm has passed.", { 170, 120, 255 })
	publish()
end

function EventService.onPlayerRemoving(player)
	if current then
		current.participants[player] = nil
	end
end

function EventService.start()
	local cfg = EventConfig.MagneticStorm
	nextAt = workspace:GetServerTimeNow() + cfg.FirstDelay
	Players.PlayerAdded:Connect(function(player)
		publish(player)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local t = workspace:GetServerTimeNow()
			if current and t >= current.endsAt then
				EventService.endStorm()
			elseif not current and t >= nextAt then
				EventService.startStorm()
			end
		end
	end)
end

return EventService
