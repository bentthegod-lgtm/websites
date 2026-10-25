--[[
	Number / time formatting shared by server messages and the UI.
]]

local Format = {}

function Format.number(n)
	n = math.floor(tonumber(n) or 0)
	local negative = n < 0
	local s = tostring(math.abs(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (if negative then "-" else "") .. formatted
end

function Format.short(n)
	n = tonumber(n) or 0
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return Format.number(n)
end

function Format.clock(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

return Format
