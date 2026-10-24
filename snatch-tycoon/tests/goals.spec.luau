local H = require("./helpers")
local Goals = require("../src/shared/Goals")
local RewardConfig = require("../src/shared/Config/RewardConfig")
local cases, test = H.suite("Goals")
local pool = RewardConfig.Goals

test("starts with three goals from the top of the pool", function()
	local s = Goals.new(pool, 3)
	H.eq(#s.active, 3)
	H.eq(s.active[1].pool, 1)
	H.eq(s.nextIndex, 4)
end)

test("progress completes a goal and pulls the next one", function()
	local s = Goals.new(pool, 3)
	local done = Goals.record(s, pool, "Buy", 1)
	H.eq(#done, 1)
	H.eq(done[1].goal.Id, "buy1")
	H.eq(s.active[1].pool, 4, "slot refilled with the next pool goal")
	H.eq(#Goals.record(s, pool, "Buy", 0 / 0), 0, "NaN ignored")
	H.eq(#Goals.record(s, pool, "Buy", -5), 0, "negative ignored")
	done = Goals.record(s, pool, "Collect", 300)
	H.eq(#done, 1)
end)

test("pool loops with bigger targets", function()
	local s = Goals.new(pool, 3)
	for _ = 1, #pool do
		-- complete whatever is in slot 1
		local entry = s.active[1]
		Goals.record(s, pool, pool[entry.pool].Stat, entry.target)
	end
	assert(s.cycle >= 1, "should have looped")
	local looped
	for _, e in ipairs(s.active) do
		if e.cycle >= 1 then
			looped = e
		end
	end
	assert(looped and looped.target > pool[looped.pool].Target, "looped targets should grow")
end)

test("describe fills in the target", function()
	local s = Goals.new(pool, 3)
	H.eq(Goals.describe(pool[2], s.active[2], function(n)
		return "$" .. n
	end), "Collect $$250 from your pedestals")
	H.eq(Goals.describe(pool[1], s.active[1]), "Buy a Blobby from the carpet")
end)

return cases
