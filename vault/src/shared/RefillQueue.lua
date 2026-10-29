--[[
	RefillQueue - when collected slots come back. Every slot on a depth uses the same delay,
	so a plain FIFO is already in due order: push(item, due), popDue(now, max) returns up to
	max items whose time has come (spreading big refills over several frames).
]]

local RefillQueue = {}
RefillQueue.__index = RefillQueue

function RefillQueue.new()
	return setmetatable({ items = {}, dues = {}, head = 1, tail = 0 }, RefillQueue)
end

function RefillQueue:push(item, due)
	self.tail += 1
	self.items[self.tail] = item
	self.dues[self.tail] = due
end

function RefillQueue:size()
	return self.tail - self.head + 1
end

function RefillQueue:clear()
	self.items, self.dues, self.head, self.tail = {}, {}, 1, 0
end

function RefillQueue:popDue(now, max)
	local out = {}
	while self.head <= self.tail and #out < (max or math.huge) and self.dues[self.head] <= now do
		table.insert(out, self.items[self.head])
		self.items[self.head], self.dues[self.head] = nil, nil
		self.head += 1
	end
	return out
end

return RefillQueue
