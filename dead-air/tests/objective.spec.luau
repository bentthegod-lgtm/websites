local ObjectiveChain = require("../src/shared/ObjectiveChain")
local ObjectiveConfig = require("../src/shared/Config/ObjectiveConfig")
local ItemConfig = require("../src/shared/Config/ItemConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Objectives: " .. name, fn = fn })
end

test("all configured chains are valid", function()
	for name, def in pairs(ObjectiveConfig.Chains) do
		local ok, reason = ObjectiveChain.validateDef(def, ItemConfig)
		assert(ok, name .. ": " .. tostring(reason))
	end
end)

test("steps only complete in order", function()
	local chain = ObjectiveChain.new(ObjectiveConfig.Chains.PowerGrid)
	assert(chain:complete("restore_power") == nil, "skipped ahead")
	assert(chain:complete("find_keycard"))
	assert(chain:isCurrent("unlock_power"))
end)

test("deposit progress completes at count and formats text", function()
	local chain = ObjectiveChain.new(ObjectiveConfig.Chains.PowerGrid)
	chain:complete("find_keycard")
	chain:complete("unlock_power")
	assert(chain:describe() == "Install replacement fuses (0/3)", chain:describe())
	chain:addProgress("install_fuses", 1)
	chain:addProgress("install_fuses", 1)
	assert(chain:isCurrent("install_fuses"))
	local done = chain:addProgress("install_fuses", 1)
	assert(done and done.Id == "install_fuses")
	assert(chain:isCurrent("restore_power"))
end)

test("count overrides apply", function()
	local chain = ObjectiveChain.new(ObjectiveConfig.Chains.PowerGrid, { install_fuses = 4 })
	chain:complete("find_keycard")
	chain:complete("unlock_power")
	for _ = 1, 3 do
		chain:addProgress("install_fuses", 1)
	end
	assert(chain:isCurrent("install_fuses"), "completed early")
end)

test("full chain completes", function()
	for _, def in pairs(ObjectiveConfig.Chains) do
		local chain = ObjectiveChain.new(def)
		while not chain:isComplete() do
			local step = chain:current()
			if step.Count then
				for _ = 1, step.Count do
					chain:addProgress(step.Id, 1)
				end
			else
				chain:complete(step.Id)
			end
		end
		assert(#chain:snapshot().steps == #def.Steps)
	end
end)

return cases
