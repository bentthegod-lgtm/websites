--[[
	Minimal synchronous signal used by client controllers
	(profile updates, popups, settings changes).
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(handler)
	local handlers = self.handlers
	table.insert(handlers, handler)
	return {
		Disconnect = function()
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...)
	-- Copy so handlers may disconnect while firing.
	for _, handler in ipairs(table.clone(self.handlers)) do
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[CrashLab] Signal handler error: " .. tostring(err))
		end
	end
end

return Signal
