--[[
	Number / time formatting for the HUD and messages.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }

-- 999 -> "999", 1234 -> "1.2K", 3456789 -> "3.46M"
function Format.short(n)
	n = tonumber(n) or 0
	local sign = if n < 0 then "-" else ""
	local v = math.abs(n)
	if v < 1000 then
		return sign .. tostring(math.floor(v))
	end
	local index = 1
	while v >= 1000 and index < #SUFFIXES do
		v /= 1000
		index += 1
	end
	local text
	if v >= 100 then
		text = tostring(math.floor(v))
	elseif v >= 10 then
		text = string.format("%.1f", math.floor(v * 10) / 10)
	else
		text = string.format("%.2f", math.floor(v * 100) / 100)
	end
	if string.find(text, ".", 1, true) then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return sign .. text .. SUFFIXES[index]
end

-- Exact value with thousands separators, for tooltips: 1234567 -> "1,234,567"
function Format.exact(n)
	n = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Format.clock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Stat value for upgrade cards: trims trailing zeros (2.50 -> 2.5).
function Format.stat(v)
	if math.abs(v - math.floor(v)) < 1e-6 then
		return tostring(math.floor(v))
	end
	local text = string.format("%.2f", v)
	return (text:gsub("0+$", ""):gsub("%.$", ""))
end

return Format
