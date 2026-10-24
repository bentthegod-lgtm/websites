--[[
	Number and time formatting (pure, unit tested).
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.short(n)
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	if n == math.huge then
		return "inf"
	end
	local negative = n < 0
	n = math.abs(n)
	local text
	if n < 1000 then
		text = tostring(math.floor(n))
	else
		local index = 1
		while n >= 1000 and index < #SUFFIXES do
			n /= 1000
			index += 1
		end
		-- Two decimals below 10, one below 100, none above: "1.25K", "12.5K", "125K".
		local decimals = if n < 10 then 2 elseif n < 100 then 1 else 0
		local factor = 10 ^ decimals
		n = math.floor(n * factor + 1e-6) / factor
		text = string.format("%." .. decimals .. "f", n)
		if decimals > 0 then
			text = string.gsub(text, "0+$", "")
			text = string.gsub(text, "%.$", "")
		end
		text ..= SUFFIXES[index]
	end
	return if negative then "-" .. text else text
end

function Format.cash(n)
	return "$" .. Format.short(n)
end

function Format.perSecond(n)
	return "$" .. Format.short(n) .. "/s"
end

function Format.commas(n)
	local s = tostring(math.floor(math.abs(n or 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return if (n or 0) < 0 then "-" .. out else out
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.time(seconds)
	seconds = math.max(0, math.floor((seconds or 0) + 0.5))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

return Format
