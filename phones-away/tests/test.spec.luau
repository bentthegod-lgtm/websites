local load = require("./loader")
local TestPaper = load("TestPaper")
local Rng = load("Rng")
local Seating = load("Seating")
local GameConfig = load("Config/GameConfig")
local Bank = load("server/Data/QuestionBank")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Test: " .. name, fn = fn })
end

local cfg = GameConfig.Test

test("question bank: 150+ well-formed questions over 5 subjects and 3 tiers", function()
	assert(#Bank.Questions >= 150, "only " .. #Bank.Questions .. " questions")
	local subjects, tiers, seen = {}, {}, {}
	for i, q in ipairs(Bank.Questions) do
		assert(q.Id == i and type(q.Q) == "string" and #q.A == 4, "bad question " .. i)
		assert(q.Correct >= 1 and q.Correct <= 4, "bad answer " .. i)
		assert(table.find(Bank.Subjects, q.Subject), "unknown subject " .. tostring(q.Subject))
		assert(q.Tier >= 1 and q.Tier <= 3)
		local opts = {}
		for _, a in ipairs(q.A) do
			assert(not opts[a], "duplicate option in " .. q.Q)
			opts[a] = true
		end
		assert(not seen[q.Q .. q.A[1]], "duplicate question " .. q.Q)
		seen[q.Q .. q.A[1]] = true
		subjects[q.Subject] = (subjects[q.Subject] or 0) + 1
		tiers[q.Tier] = (tiers[q.Tier] or 0) + 1
	end
	for _, s in ipairs(Bank.Subjects) do
		assert((subjects[s] or 0) >= 25, s .. " has " .. tostring(subjects[s]))
	end
	for tier = 1, 3 do
		assert((tiers[tier] or 0) >= 30, "tier " .. tier)
	end
end)

test("pick: 3 easy / 4 medium / 3 hard, no repeats, spread over subjects", function()
	for seed = 1, 100 do
		local picked = TestPaper.pick(Bank, cfg, Rng.new(seed))
		assert(#picked == 10, "picked " .. #picked)
		local tiers, used, subjects = {}, {}, {}
		for _, i in ipairs(picked) do
			assert(not used[i], "repeat")
			used[i] = true
			local q = Bank.Questions[i]
			tiers[q.Tier] = (tiers[q.Tier] or 0) + 1
			subjects[q.Subject] = (subjects[q.Subject] or 0) + 1
		end
		assert(tiers[1] == 3 and tiers[2] == 4 and tiers[3] == 3)
		for _, n in pairs(subjects) do
			assert(n <= 3, "subject spread " .. n)
		end
	end
end)

test("versions A and B: same questions, shuffled order and options, answers map correctly", function()
	local t = TestPaper.build(Bank, cfg, Rng.new(7))
	local a, b = t.versions.A, t.versions.B
	assert(#a.order == 10 and #b.order == 10)
	local sameOrder, sameOptions = true, true
	local setA, setB = {}, {}
	for slot = 1, 10 do
		setA[a.order[slot]] = true
		setB[b.order[slot]] = true
		if a.order[slot] ~= b.order[slot] then
			sameOrder = false
		end
	end
	for k in pairs(setA) do
		assert(setB[k], "versions have different questions")
	end
	for slot = 1, 10 do
		local q = Bank.Questions[a.order[slot]]
		local displayed = TestPaper.correctOption(Bank, a, slot)
		local view = TestPaper.clientView(Bank, a, 200)
		assert(view.questions[slot].options[displayed] == q.A[q.Correct], "correct option mapped wrong")
		local perm = a.perms[slot]
		if perm[1] ~= 1 or perm[2] ~= 2 or perm[3] ~= 3 then
			sameOptions = false
		end
	end
	assert(not sameOrder, "version B has the same order as A")
	assert(not sameOptions, "options never shuffled")
end)

test("client view never contains the answer key", function()
	local t = TestPaper.build(Bank, cfg, Rng.new(9))
	local view = TestPaper.clientView(Bank, t.versions.A, 200)
	local function scan(v, path)
		if type(v) == "table" then
			for k, x in pairs(v) do
				local key = string.lower(tostring(k))
				assert(key ~= "correct" and key ~= "answer" and key ~= "answers" and key ~= "perms" and key ~= "order", "leak at " .. path .. "." .. tostring(k))
				scan(x, path .. "." .. tostring(k))
			end
		end
	end
	scan(view, "view")
	assert(view.version == "A" and #view.questions == 10)
	for _, q in ipairs(view.questions) do
		assert(#q.options == 4 and type(q.text) == "string")
	end
end)

test("friends share a version, other groups alternate", function()
	local students = {
		{ id = 1, friends = { [2] = true } },
		{ id = 2, friends = { [1] = true } },
		{ id = 3, friends = {} },
		{ id = 4, friends = {} },
	}
	local v = TestPaper.assignVersions(Seating.groups(students))
	assert(v[1] == v[2], "friends on different versions")
	assert(v[3] ~= v[4], "neighbouring groups on the same version")
end)

test("answer validation: slots and options must be real integers in range", function()
	local t = TestPaper.build(Bank, cfg, Rng.new(3))
	local a = t.versions.A
	assert(TestPaper.validAnswer(a, 1, 4))
	assert(not TestPaper.validAnswer(a, 0, 1) and not TestPaper.validAnswer(a, 11, 1))
	assert(not TestPaper.validAnswer(a, 1, 5) and not TestPaper.validAnswer(a, 1, 0))
	assert(not TestPaper.validAnswer(a, 1.5, 1) and not TestPaper.validAnswer(a, 0 / 0, 1))
	assert(not TestPaper.validAnswer(a, "1", 1) and not TestPaper.validAnswer(a, 1, {}))
end)

test("grading: percent, letter grades A+ .. F, rewards, ghost and ripped", function()
	local t = TestPaper.build(Bank, cfg, Rng.new(4))
	local a = t.versions.A
	local all = {}
	for slot = 1, 10 do
		all[slot] = TestPaper.correctOption(Bank, a, slot)
	end
	local c, n, pct = TestPaper.grade(Bank, a, all)
	assert(c == 10 and n == 10 and pct == 100)
	local seven = table.clone(all)
	for slot = 1, 3 do
		seven[slot] = (seven[slot] % 4) + 1
	end
	local c7, _, p7 = TestPaper.grade(Bank, a, seven)
	assert(c7 == 7 and p7 == 70)
	assert(TestPaper.letter(100, cfg.Grades) == "A+")
	assert(TestPaper.letter(90, cfg.Grades) == "A")
	assert(TestPaper.letter(85, cfg.Grades) == "B")
	assert(TestPaper.letter(70, cfg.Grades) == "C")
	assert(TestPaper.letter(60, cfg.Grades) == "D")
	assert(TestPaper.letter(59, cfg.Grades) == "F")
	local top = TestPaper.reward(100, cfg, { ghost = true, multiplier = 2 })
	assert(top.letter == "A+" and top.aplus == cfg.APlusBonus and top.ghost == cfg.GhostBonus)
	assert(top.total == (cfg.Grades[1].Clout + cfg.APlusBonus + cfg.GhostBonus) * 2)
	local mid = TestPaper.reward(70, cfg)
	assert(mid.letter == "C" and mid.aplus == 0 and mid.ghost == 0)
	local ripped = TestPaper.reward(100, cfg, { ripped = true, ghost = true })
	assert(ripped.letter == "F" and ripped.total == 0)
	assert(TestPaper.grade(Bank, a, {}) == 0)
end)

test("reveal order: unrevealed only, unanswered first", function()
	local t = TestPaper.build(Bank, cfg, Rng.new(5))
	local a = t.versions.A
	local order = TestPaper.revealOrder(a, { [1] = 2, [2] = 3 }, { [3] = 1, [4] = 2 }, nil)
	assert(#order == 8, "revealed slots offered again")
	assert(order[#order] == 4 and order[#order - 1] == 3, "answered slots should come last")
	for _, slot in ipairs(order) do
		assert(slot ~= 1 and slot ~= 2)
	end
end)

return cases
