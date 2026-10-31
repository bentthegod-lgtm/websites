--[[
	Maid - a janitor for one event instance (or any temporary thing). Give it Instances,
	connections, functions or objects with :Destroy() / :clean(); clean() releases all of
	them exactly once, in reverse order. Every event instance owns one (server and client),
	and the Event Director cleans it on stop or on the hard timeout.
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ items = {}, cleaned = false }, Maid)
end

function Maid:give(item)
	if self.cleaned then
		-- too late: release it right away so nothing leaks
		Maid.release(item)
		return item
	end
	table.insert(self.items, item)
	return item
end

function Maid.release(item)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif type(item) == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.clean) == "function" then
			item:clean()
		end
	end
end

function Maid:count()
	return #self.items
end

function Maid:clean()
	if self.cleaned then
		return
	end
	self.cleaned = true
	for i = #self.items, 1, -1 do
		local ok, err = pcall(Maid.release, self.items[i])
		if not ok then
			warn("[ChaosKarts] Maid cleanup failed: " .. tostring(err))
		end
		self.items[i] = nil
	end
end

return Maid
