--[[
	ObjectiveChain - pure progression logic for one run's objective chain.
	ObjectiveService owns the Roblox side (stations, prompts, doors) and asks this module
	whether an action is valid and what changes when a step completes.
]]

local ObjectiveChain = {}
ObjectiveChain.__index = ObjectiveChain

function ObjectiveChain.new(chainDef, countOverrides)
	local self = setmetatable({}, ObjectiveChain)
	self.def = chainDef
	self.steps = {}
	for i, step in ipairs(chainDef.Steps) do
		local copy = table.clone(step)
		if countOverrides and countOverrides[step.Id] then
			copy.Count = countOverrides[step.Id]
		end
		self.steps[i] = copy
	end
	self.index = 1
	self.progress = {}
	self.completed = {}
	return self
end

function ObjectiveChain:current()
	return self.steps[self.index]
end

function ObjectiveChain:isComplete()
	return self.index > #self.steps
end

function ObjectiveChain:isCurrent(stepId)
	local step = self:current()
	return step ~= nil and step.Id == stepId
end

-- Marks the current step complete if it matches. Returns the completed step or nil.
function ObjectiveChain:complete(stepId)
	local step = self:current()
	if not step or step.Id ~= stepId then
		return nil
	end
	self.completed[step.Id] = true
	self.index += 1
	return step
end

-- Adds progress to a counted step (deposit/collect). Returns completedStep?, newProgress.
function ObjectiveChain:addProgress(stepId, amount)
	local step = self:current()
	if not step or step.Id ~= stepId then
		return nil, self.progress[stepId] or 0
	end
	local value = (self.progress[stepId] or 0) + (amount or 1)
	self.progress[stepId] = value
	if value >= (step.Count or 1) then
		return self:complete(stepId), value
	end
	return nil, value
end

function ObjectiveChain:getProgress(stepId)
	return self.progress[stepId] or 0
end

function ObjectiveChain:describe(step)
	step = step or self:current()
	if not step then
		return "Escape complete"
	end
	local text = step.Text
	if string.find(text, "%%d") then
		text = string.format(text, self:getProgress(step.Id), step.Count or 1)
	end
	return text
end

-- Snapshot for clients.
function ObjectiveChain:snapshot()
	local list = {}
	for i, step in ipairs(self.steps) do
		table.insert(list, {
			id = step.Id,
			text = self:describe(step),
			done = self.completed[step.Id] == true,
			current = i == self.index,
		})
	end
	return { title = self.def.Title, steps = list, index = self.index, total = #self.steps }
end

-- Checks a chain definition for mistakes (used by tests and on server start).
function ObjectiveChain.validateDef(chainDef, itemConfig)
	local validTypes = { collect = true, unlock = true, deposit = true, activate = true, hold = true, extract = true }
	local seen = {}
	local hasExtract = false
	for i, step in ipairs(chainDef.Steps) do
		if not step.Id or seen[step.Id] then
			return false, "step " .. i .. " has a missing or duplicate Id"
		end
		seen[step.Id] = true
		if not validTypes[step.Type] then
			return false, "step " .. step.Id .. " has unknown type " .. tostring(step.Type)
		end
		if (step.Type == "collect" or step.Type == "deposit" or step.Type == "unlock") and not itemConfig[step.Item] then
			return false, "step " .. step.Id .. " references unknown item " .. tostring(step.Item)
		end
		if (step.Type == "deposit" or step.Type == "activate" or step.Type == "hold" or step.Type == "extract") and not step.Station then
			return false, "step " .. step.Id .. " needs a Station"
		end
		if step.Type == "extract" then
			hasExtract = true
			if i ~= #chainDef.Steps then
				return false, "extract must be the final step"
			end
		end
	end
	if not hasExtract then
		return false, "chain has no extract step"
	end
	return true
end

return ObjectiveChain
