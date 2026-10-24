--[[
	WeatherService - server-wide weather events every WeatherConfig.MinGap..MaxGap seconds.

	During an event, plants at the Full stage or later roll for the event's mutation every
	TickInterval seconds; Thunderstorm also strikes a random plant with lightning. Rain and
	Thunderstorm speed up growth. Weather totems (developer products) start an event now or
	queue it right after the current one.

	workspace attributes for clients: SV_Weather (event key or ""), SV_WeatherEnds,
	SV_NextWeather (unix seconds).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local WeatherConfig = require(Shared.Config.WeatherConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local Economy = require(Shared.Economy)
local WeatherLogic = require(Shared.WeatherLogic)

local WeatherService = {}

local services
local rng = Random.new()
local current -- { key, endsAt, nextTick, nextStrike }
local nextAt = 0
local lastKey
local queue = {}

function WeatherService.init(registry)
	services = registry
	nextAt = os.time() + WeatherConfig.FirstEventDelay
end

function WeatherService.current()
	return current
end

function WeatherService.growthMultiplier()
	if current then
		return WeatherConfig.Events[current.key].Growth or 1
	end
	return 1
end

local function publish()
	workspace:SetAttribute("SV_Weather", if current then current.key else "")
	workspace:SetAttribute("SV_WeatherEnds", if current then current.endsAt else 0)
	workspace:SetAttribute("SV_NextWeather", nextAt)
end

function WeatherService.start(key, buyer)
	local def = WeatherConfig.Events[key]
	if not def then
		return false
	end
	local now = os.time()
	current = {
		key = key,
		endsAt = now + def.Duration,
		nextTick = now + WeatherConfig.TickInterval,
		nextStrike = if def.StrikeInterval then now + def.StrikeInterval else nil,
	}
	lastKey = key
	publish()
	local text = if buyer
		then string.format("%s summoned %s! %s", buyer.DisplayName, def.Name, def.Blurb)
		else string.format("%s%s has begun! %s", if def.Rare then "WOW! " else "", def.Name, def.Blurb)
	services.Remotes.Announce:FireAllClients(text, def.Color)
	services.Remotes.Effect:FireAllClients("WeatherStart", { key = key })
	return true
end

function WeatherService.stop()
	if not current then
		return
	end
	local def = WeatherConfig.Events[current.key]
	current = nil
	nextAt = os.time() + (if #queue > 0 then 5 else WeatherLogic.gap(WeatherConfig, rng))
	publish()
	services.Remotes.Notify:FireAllClients(def.Name .. " has passed. Check your garden for mutations!", "info")
end

-- Weather totem purchase.
function WeatherService.request(key, buyer)
	if not WeatherConfig.Events[key] then
		return
	end
	if current then
		table.insert(queue, { key = key, buyer = buyer })
		services.Remotes.Announce:FireAllClients(
			string.format("%s summoned %s! It arrives right after the current weather.", buyer and buyer.DisplayName or "Someone", WeatherConfig.Events[key].Name),
			WeatherConfig.Events[key].Color
		)
	else
		WeatherService.start(key, buyer)
	end
end

-- One mutation roll for every eligible plant. `force` (tests) sets the chance to 1.
function WeatherService.mutationTick(force)
	if not current then
		return 0
	end
	local def = WeatherConfig.Events[current.key]
	local hits = {}
	services.PlotService.forEachMature(function(player, _, index, plant)
		local chance = Economy.mutationChance(def.TickChance, plant.lu, services.ShopService.owns(player, "LuckyGardener"), MutationConfig)
		if force or rng:NextNumber() < chance then
			table.insert(hits, { player = player, index = index })
		end
	end)
	local changed = 0
	for _, hit in ipairs(hits) do
		local ok
		if def.Variant then
			ok = services.PlotService.setVariant(hit.player, hit.index, def.Variant)
		else
			ok = services.PlotService.addMutation(hit.player, hit.index, def.Mutation)
		end
		if ok then
			changed += 1
		end
	end
	return changed
end

function WeatherService.strike()
	if not current then
		return nil
	end
	local def = WeatherConfig.Events[current.key]
	if not def.StrikeMutation then
		return nil
	end
	local candidates = {}
	services.PlotService.forEachMature(function(player, plot, index)
		table.insert(candidates, { player = player, plot = plot, index = index })
	end)
	if #candidates == 0 then
		return nil
	end
	local hit = candidates[rng:NextInteger(1, #candidates)]
	local position = services.PlotService.tileCFrame(hit.plot, hit.index).Position
	services.Remotes.Effect:FireAllClients("Lightning", { position = position })
	services.PlotService.addMutation(hit.player, hit.index, def.StrikeMutation)
	return hit
end

function WeatherService.update(now)
	if current then
		if now >= current.endsAt then
			WeatherService.stop()
			return
		end
		if now >= current.nextTick then
			current.nextTick = now + WeatherConfig.TickInterval
			WeatherService.mutationTick(false)
		end
		if current.nextStrike and now >= current.nextStrike then
			current.nextStrike = now + WeatherConfig.Events[current.key].StrikeInterval
			WeatherService.strike()
		end
	elseif #queue > 0 and now >= nextAt then
		local q = table.remove(queue, 1)
		WeatherService.start(q.key, if q.buyer and q.buyer.Parent then q.buyer else nil)
	elseif now >= nextAt then
		WeatherService.start(WeatherLogic.pick(WeatherConfig, rng, lastKey))
	end
end

function WeatherService.run()
	publish()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(WeatherService.update, os.time())
			if not ok then
				warn("[SproutValley] weather update failed: " .. tostring(err))
			end
		end
	end)
end

return WeatherService
