--[[
	Analytics - thin pcall wrapper around AnalyticsService. Onboarding funnel steps are
	logged once per player (remembered in profile.Stats), custom events as they happen.
	No personal data is sent: only step numbers, names and numeric values.
]]

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

local services

Analytics.Funnel = {
	FirstPickup = 1,
	FirstFullStack = 2,
	FirstDeposit = 3,
	FirstUpgrade = 4,
	TutorialDone = 5,
	FirstNewDepth = 6,
	FirstRare = 7,
	FirstRebirth = 8,
}

function Analytics.init(registry)
	services = registry
end

function Analytics.funnel(player, name)
	local step = Analytics.Funnel[name]
	local data = services and services.DataService.getProfile(player)
	if not step or not data then
		return
	end
	local flag = "Funnel:" .. name
	if data.Stats[flag] then
		return
	end
	data.Stats[flag] = os.time()
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

function Analytics.custom(player, name, value)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

return Analytics
