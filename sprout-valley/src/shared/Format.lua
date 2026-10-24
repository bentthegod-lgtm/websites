--[[
	Number / time formatting shared by server messages and client UI.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1,234"; 1234567 -> "1.23M"
function Format.coins(n)
	n = math.floor(tonumber(n) or 0)
	if math.abs(n) < 100000 then
		local s = tostring(math.abs(n))
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if out:sub(1, 1) == "," then
			out = out:sub(2)
		end
		return (if n < 0 then "-" else "") .. out
	end
	local index = 1
	local v = math.abs(n)
	while v >= 1000 and index < #SUFFIXES do
		v /= 1000
		index += 1
	end
	local text = if v >= 100 then string.format("%d", math.floor(v)) else string.format("%.2f", math.floor(v * 100) / 100)
	if string.find(text, ".", 1, true) then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return (if n < 0 then "-" else "") .. text .. SUFFIXES[index]
end

-- seconds -> "4m 05s", "1h 12m", "35s"
function Format.duration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 3600 then
		return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
	elseif seconds >= 60 then
		return string.format("%dm %02ds", seconds // 60, seconds % 60)
	end
	return string.format("%ds", seconds)
end

-- seconds -> "4:05"
function Format.clock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Format.kg(kg)
	kg = tonumber(kg) or 0
	if kg >= 100 then
		return string.format("%dkg", math.floor(kg))
	end
	return string.format("%.2fkg", kg)
end

function Format.percent(p)
	return string.format("%d%%", math.floor((tonumber(p) or 0) * 100 + 0.5))
end

return Format
