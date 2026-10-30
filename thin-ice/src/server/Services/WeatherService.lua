--[[
	WeatherService - blizzard gusts. Every minute or so a gust sweeps the lake for a few
	seconds: it chills anyone out on the ice faster, but the wind also drowns out sound,
	so the Antlered hears far less. A risky window to cross the Thin Flats.

	The state is a Workspace attribute (TI_Gust) so clients can thicken the fog and snow.
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

local function set(gust)
	state.gust = gust
	workspace:SetAttribute("TI_Gust", gust)
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

-- Starts a gust right now (tests, or a future "storm" event).
function WeatherService.forceGust()
	state.nextAt = os.clock()
end

function WeatherService.step()
	if not state.active then
		return
	end
	local now = os.clock()
	if not state.gust and now >= state.nextAt then
		set(true)
		state.endsAt = now + W.GustTime
		services.Remotes.Announce:FireAllClients("BLIZZARD GUST! It can barely hear you - move now!", { 190, 220, 255 })
	elseif state.gust and now >= state.endsAt then
		set(false)
		state.nextAt = now + rng:NextNumber(W.CalmMin, W.CalmMax)
		services.Remotes.Notify:FireAllClients("The wind dies down. It can hear everything again.", "warn")
	end
end

return WeatherService
