--[[
	TestPaper - pure logic for the class test (picking questions, A/B versions, client
	views without answers, grading, letter grades and rewards). The answer key itself lives
	in the server-only QuestionBank; this module just receives it as `bank`.

	A test:
	  { questions = { bankIndex... } (the picked set), versions = { A = version, B = version } }
	A version (one per letter, every student gets one):
	  { letter = "A", order = { bankIndex per slot }, perms = { [slot] = { displayed -> original } } }
	Students answer by SLOT (1..N on their own paper) and DISPLAYED option (1..4).
]]

local TestPaper = {}

TestPaper.Letters = { "A", "B" }

local function shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng:integer(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

--[[
	Picks `cfg.Mix` = { [tier] = count } questions, spread over subjects (no subject more
	than ceil(total / subjects) + 1 times when avoidable). Returns bank indices.
]]
function TestPaper.pick(bank, cfg, rng)
	local byTier = {}
	for i, q in ipairs(bank.Questions) do
		byTier[q.Tier] = byTier[q.Tier] or {}
		table.insert(byTier[q.Tier], i)
	end
	local total = 0
	for _, n in pairs(cfg.Mix) do
		total += n
	end
	local perSubject = math.ceil(total / #bank.Subjects) + 1
	local used, subjectCount, picked = {}, {}, {}
	for tier = 1, 3 do
		local want = cfg.Mix[tier] or 0
		local pool = shuffle(table.clone(byTier[tier] or {}), rng)
		-- First pass respects the subject spread; second pass fills any gap.
		for pass = 1, 2 do
			for _, index in ipairs(pool) do
				if want <= 0 then
					break
				end
				local subject = bank.Questions[index].Subject
				if not used[index] and (pass == 2 or (subjectCount[subject] or 0) < perSubject) then
					used[index] = true
					subjectCount[subject] = (subjectCount[subject] or 0) + 1
					table.insert(picked, index)
					want -= 1
				end
			end
		end
	end
	return picked
end

-- One shuffled version: question order and option order.
function TestPaper.makeVersion(letter, picked, rng)
	local order = shuffle(table.clone(picked), rng)
	local perms = {}
	for slot = 1, #order do
		perms[slot] = shuffle({ 1, 2, 3, 4 }, rng)
	end
	return { letter = letter, order = order, perms = perms }
end

function TestPaper.build(bank, cfg, rng)
	local picked = TestPaper.pick(bank, cfg, rng)
	local versions = {}
	for _, letter in ipairs(TestPaper.Letters) do
		versions[letter] = TestPaper.makeVersion(letter, picked, rng)
	end
	return { questions = picked, versions = versions }
end

-- The displayed option index that is correct for `slot` on this version.
function TestPaper.correctOption(bank, version, slot)
	local index = version.order[slot]
	local q = index and bank.Questions[index]
	if not q then
		return nil
	end
	return table.find(version.perms[slot], q.Correct)
end

-- What the client is allowed to see: text + options in the version's order. NO answers.
function TestPaper.clientView(bank, version, seconds)
	local questions = {}
	for slot, index in ipairs(version.order) do
		local q = bank.Questions[index]
		local options = {}
		for displayed, original in ipairs(version.perms[slot]) do
			options[displayed] = q.A[original]
		end
		questions[slot] = { slot = slot, subject = q.Subject, tier = q.Tier, text = q.Q, options = options }
	end
	return { version = version.letter, questions = questions, seconds = seconds }
end

--[[
	Assigns versions so friends (Seating.groups) share one, and groups alternate A / B.
	groups = { { { id = ... }, ... }, ... }  -> { [id] = letter }
]]
function TestPaper.assignVersions(groups)
	local out = {}
	for i, group in ipairs(groups) do
		local letter = TestPaper.Letters[((i - 1) % #TestPaper.Letters) + 1]
		for _, member in ipairs(group) do
			out[member.id] = letter
		end
	end
	return out
end

-- Validates an answer submission. Returns slot, option or nil.
function TestPaper.validAnswer(version, slot, option)
	if type(slot) ~= "number" or type(option) ~= "number" then
		return nil
	end
	if slot ~= slot or option ~= option or slot % 1 ~= 0 or option % 1 ~= 0 then
		return nil
	end
	if slot < 1 or slot > #version.order or option < 1 or option > 4 then
		return nil
	end
	return slot, option
end

-- answers = { [slot] = displayed option }. Returns correct, total, percent.
function TestPaper.grade(bank, version, answers)
	local correct = 0
	local total = #version.order
	for slot = 1, total do
		if answers[slot] ~= nil and answers[slot] == TestPaper.correctOption(bank, version, slot) then
			correct += 1
		end
	end
	return correct, total, if total > 0 then math.floor(correct / total * 100 + 0.5) else 0
end

-- Letter from a percentage, using cfg.Grades = { { Letter, Min, Clout } } (highest first).
function TestPaper.letter(percent, grades)
	for _, g in ipairs(grades) do
		if percent >= g.Min then
			return g.Letter, g
		end
	end
	return grades[#grades].Letter, grades[#grades]
end

--[[
	Clout for a graded test. opts = { ripped, ghost, multiplier }
	Returns { letter, base, aplus, ghost, total }
]]
function TestPaper.reward(percent, cfg, opts)
	opts = opts or {}
	if opts.ripped then
		return { letter = "F", base = 0, aplus = 0, ghost = 0, total = 0, ripped = true }
	end
	local letter, g = TestPaper.letter(percent, cfg.Grades)
	local aplus = if letter == "A+" then cfg.APlusBonus else 0
	local ghost = if opts.ghost then cfg.GhostBonus else 0
	local base = g.Clout
	local m = opts.multiplier or 1
	return { letter = letter, base = base, aplus = aplus, ghost = ghost, total = math.floor((base + aplus + ghost) * m + 0.5) }
end

--[[
	Which slots to reveal next: unrevealed slots, unanswered first, then in paper order.
	revealed = { [slot] = true }, answers = { [slot] = option }
]]
function TestPaper.revealOrder(version, revealed, answers, rng)
	local unanswered, answered = {}, {}
	for slot = 1, #version.order do
		if not revealed[slot] then
			table.insert(if answers[slot] == nil then unanswered else answered, slot)
		end
	end
	if rng then
		shuffle(unanswered, rng)
		shuffle(answered, rng)
	end
	for _, slot in ipairs(answered) do
		table.insert(unanswered, slot)
	end
	return unanswered
end

return TestPaper
