--[[
	WeatherService - whiteouts. Every minute or two a blizzard sweeps the lake for 15-20 s:
	visibility drops hard, anyone out on the ice chills faster, and the wind drowns out
	sound so the Antlered hears far less - but it also moves faster (Weather.WhiteoutSpeed).
	A risky window: run for it, or hunker down by a brazier.

	The state is a Workspace attribute (TI_Gust) so clients can close the fog and thicken
	the snow; TI_GustEnds (server time) lets them show how long it lasts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)

local WeatherService = {}

local services
local W = GameConfig.Weather
local state = { active = false, gust = false, nextAt = math.huge, endsAt = 0 }
local rng = Random.new()

function WeatherService.init(registry)
	services = registry
end

local function set(gust, duration)
	state.gust = gust
	workspace:SetAttribute("TI_Gust", gust)
	workspace:SetAttribute("TI_GustEnds", if gust then workspace:GetServerTimeNow() + (duration or 0) else 0)
end

function WeatherService.startRun()
	state.active = true
	state.nextAt = os.clock() + rng:NextNumber(W.CalmMin, W.CalmMax)
	set(false)
end

function WeatherService.stopRun()
	state.active = false
	state.nextAt = math.huge
	set(false)
end

function WeatherService.gusting()
	return state.gust
end

-- No new whiteout once the sled is waiting, or when it would still be raging as the time
-- limit runs out (the last dash and the results shouldn't happen blind).
function WeatherService.canStart(now)
	local rs = services and services.RoundService
	if not rs then
		return true
	end
	if rs.phase() == "Sled" then
		return false
	end
	local run = rs.run()
	return not (run and run.endsAt and run.endsAt - now < W.WhiteoutMax + 5)
end

-- Starts a gust right now (tests, or a future "storm" event).
function WeatherService.forceGust()
	state.nextAt = os.clock()
end

function WeatherService.step()
	if not state.active then
		return
	end
	local now = os.clock()
	if not state.gust and now >= state.nextAt and WeatherService.canStart(now) then
		local duration = rng:NextNumber(W.WhiteoutMin, W.WhiteoutMax)
		set(true, duration)
		state.endsAt = now + duration
		services.Remotes.Announce:FireAllClients("WHITEOUT! It can barely hear you... but it's moving faster.", { 190, 220, 255 })
	elseif state.gust and now >= state.endsAt then
		set(false)
		state.nextAt = now + rng:NextNumber(W.CalmMin, W.CalmMax)
		services.Remotes.Notify:FireAllClients("The whiteout passes. It can hear everything again.", "warn")
	end
end

return WeatherService
