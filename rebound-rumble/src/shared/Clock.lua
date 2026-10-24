--[[
	Shared clock. Uses workspace:GetServerTimeNow() so client parry timestamps and the
	server's ball history live on the same timeline. Tests can override it with Clock.set.
]]

local Clock = {}

local source

function Clock.now()
	if source then
		return source()
	end
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(value) == "number" then
		return value
	end
	return os.clock()
end

function Clock.set(fn)
	source = fn
end

return Clock
