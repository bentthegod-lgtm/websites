--[[
	Pure weather scheduling helpers.
]]

local WeatherLogic = {}

-- Weighted pick of an event key. `exclude` (optional) avoids repeating the last event.
function WeatherLogic.pick(weatherConfig, rng, exclude)
	local total = 0
	for _, key in ipairs(weatherConfig.Order) do
		if key ~= exclude then
			total += weatherConfig.Events[key].Weight
		end
	end
	local r = rng:NextNumber() * total
	for _, key in ipairs(weatherConfig.Order) do
		if key ~= exclude then
			r -= weatherConfig.Events[key].Weight
			if r < 0 then
				return key
			end
		end
	end
	return weatherConfig.Order[1]
end

function WeatherLogic.gap(weatherConfig, rng)
	return rng:NextInteger(weatherConfig.MinGap, weatherConfig.MaxGap)
end

return WeatherLogic
