--[[
	TestService - the class test (every class period is a test).

	* At the start of class a test is built from the server-only QuestionBank (3 easy,
	  4 medium, 3 hard) in two shuffled versions, A and B. Friend groups share a version so
	  they can help each other; other groups alternate.
	* Clients only ever receive question text + options (TestPaper.clientView). The answer
	  key never leaves the server, except the specific answers a student EARNS through a
	  server-timed phone screenshot + scan, a smart-watch glance, or an Answer Key Peek.
	* Answers are submitted by (slot, option); the server validates the slot belongs to the
	  student's version, the class is still running and the rate limit.
	* Caught = the test is ripped up (answers and revealed answers wiped). Escaping detention
	  gives a fresh blank copy; staying in detention = F.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local TestPaper = require(Shared.TestPaper)
local Seating = require(Shared.Seating)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local QuestionBank = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("QuestionBank"))

local TestService = {}

local services
local rng = Rng.new(os.time() % 66667 + 13)
local test -- { questions, versions, startedAt }
local papers = {} -- [player] = { version, answers, revealed, ripped, peekUsed, cheated, tokens, at }

function TestService.init(registry)
	services = registry
end

function TestService.bank()
	return QuestionBank
end

function TestService.active()
	return test ~= nil
end

function TestService.paper(player)
	return papers[player]
end

function TestService.version(player)
	local paper = papers[player]
	return paper and test and test.versions[paper.version] or nil
end

function TestService.viewFor(player)
	local version = TestService.version(player)
	if not version then
		return nil
	end
	local view = TestPaper.clientView(QuestionBank, version, services.RoundService.round() and services.RoundService.round().duration or GameConfig.ClassSeconds)
	view.answers = table.clone(papers[player].answers)
	view.ripped = papers[player].ripped
	return view
end

local function send(player, kind, data)
	if player.Parent then
		services.Remotes.Test:FireClient(player, kind, data)
	end
end

--[[
	Starts a test for `students` = { { player, id, friends } } (same shape as Seating uses).
	opts (tests) = { seed }
]]
function TestService.begin(students, opts)
	opts = opts or {}
	local testRng = if opts.seed then Rng.new(opts.seed) else rng
	test = TestPaper.build(QuestionBank, GameConfig.Test, testRng)
	test.startedAt = Clock.now()
	papers = {}
	local letters = TestPaper.assignVersions(Seating.groups(students))
	for _, s in ipairs(students) do
		papers[s.player] = {
			version = letters[s.id] or "A",
			answers = {},
			revealed = {},
			ripped = false,
			peekUsed = false,
			cheated = false,
			tokens = GameConfig.Test.AnswerRate,
			at = Clock.now(),
		}
		s.player:SetAttribute("PA_Version", papers[s.player].version)
		send(s.player, "view", TestService.viewFor(s.player))
	end
	return test
end

function TestService.finish()
	for player in pairs(papers) do
		send(player, "clear", nil)
		if player.Parent then
			player:SetAttribute("PA_Version", "")
		end
	end
	test = nil
	papers = {}
end

-- A student clicks an answer. Returns true when accepted.
function TestService.answer(player, slot, option, now)
	now = now or Clock.now()
	local paper = papers[player]
	local version = TestService.version(player)
	if not paper or not version or paper.ripped or not services.RoundService.canAnswer(player) then
		return false
	end
	paper.tokens = math.min(GameConfig.Test.AnswerRate, paper.tokens + (now - paper.at) * GameConfig.Test.AnswerRate)
	paper.at = now
	if paper.tokens < 1 then
		return false
	end
	paper.tokens -= 1
	local s, o = TestPaper.validAnswer(version, slot, option)
	if not s then
		return false
	end
	paper.answers[s] = o
	send(player, "ack", { slot = s, option = o })
	return true
end

-- Slots that can still be revealed for this student.
function TestService.remaining(player)
	local paper = papers[player]
	local version = TestService.version(player)
	if not paper or not version or paper.ripped then
		return 0
	end
	local n = 0
	for slot = 1, #version.order do
		if not paper.revealed[slot] then
			n += 1
		end
	end
	return n
end

--[[
	Reveals up to `count` correct answers to this student only. `source` = "snap" | "watch"
	| "peek". Only PhoneService (after its server-side timers) and the Peek product call this.
	Returns { { slot, option } }.
]]
function TestService.reveal(player, count, source)
	local paper = papers[player]
	local version = TestService.version(player)
	if not paper or not version or paper.ripped or count <= 0 then
		return {}
	end
	local out = {}
	for _, slot in ipairs(TestPaper.revealOrder(version, paper.revealed, paper.answers, rng)) do
		if #out >= count then
			break
		end
		paper.revealed[slot] = TestPaper.correctOption(QuestionBank, version, slot)
		table.insert(out, { slot = slot, option = paper.revealed[slot] })
	end
	if source ~= "peek" and #out > 0 then
		paper.cheated = true
	end
	if #out > 0 then
		services.RewardService.track(player, "Revealed", #out)
		local profile = services.DataService.getProfile(player)
		if profile then
			profile.Stats.Revealed = (profile.Stats.Revealed or 0) + #out
		end
	end
	return out
end

-- Everything this student has revealed so far: { { slot, option } } (for their phone).
function TestService.revealedList(player)
	local paper = papers[player]
	local list = {}
	if paper then
		for slot, option in pairs(paper.revealed) do
			table.insert(list, { slot = slot, option = option })
		end
		table.sort(list, function(a, b)
			return a.slot < b.slot
		end)
	end
	return list
end

-- Answer Key Peek (developer product token): 1 answer, max once per test.
function TestService.usePeek(player)
	local paper = papers[player]
	local profile = services.DataService.getProfile(player)
	if not paper or not profile or not services.RoundService.canAnswer(player) or paper.ripped then
		return false, "You can only peek during a test."
	end
	if paper.peekUsed then
		return false, "You already peeked this test! (Your peek is saved.)"
	end
	if (profile.Tokens.Peek or 0) <= 0 then
		return false, "No Answer Key Peeks left."
	end
	local out = TestService.reveal(player, 1, "peek")
	if #out == 0 then
		return false, "Nothing left to peek at!"
	end
	profile.Tokens.Peek -= 1
	paper.peekUsed = true
	services.DataService.markDirty(player)
	services.Remotes.PhoneResult:FireClient(player, "reveal", { answers = out, source = "peek", all = TestService.revealedList(player) })
	services.DataService.sendProfile(player)
	return true
end

-- Caught: the test is ripped up.
function TestService.rip(player)
	local paper = papers[player]
	if not paper then
		return
	end
	paper.ripped = true
	paper.answers = {}
	paper.revealed = {}
	send(player, "ripped", nil)
end

-- Escaped detention: a fresh, blank copy of the same version.
function TestService.freshCopy(player)
	local paper = papers[player]
	if not paper then
		return
	end
	paper.ripped = false
	paper.answers = {}
	paper.revealed = {}
	send(player, "view", TestService.viewFor(player))
end

--[[
	Grades a student's test. opts = { multiplier, ghost }. Returns
	{ correct, total, percent, letter, base, aplus, ghost, total Clout, ripped, version }
]]
function TestService.grade(player, opts)
	opts = opts or {}
	local paper = papers[player]
	local version = TestService.version(player)
	if not paper or not version then
		return nil
	end
	local correct, total, percent = TestPaper.grade(QuestionBank, version, paper.answers)
	if paper.ripped then
		correct, percent = 0, 0
	end
	local reward = TestPaper.reward(percent, GameConfig.Test, { ripped = paper.ripped, ghost = opts.ghost, multiplier = opts.multiplier })
	return {
		correct = correct,
		count = total,
		percent = percent,
		letter = reward.letter,
		base = reward.base,
		aplus = reward.aplus,
		ghost = reward.ghost,
		clout = reward.total,
		ripped = paper.ripped,
		version = paper.version,
		cheated = paper.cheated,
	}
end

-- A bonus question (easy, not on the current test). Server-side only.
function TestService.bonusQuestion()
	local used = {}
	for _, index in ipairs(test and test.questions or {}) do
		used[index] = true
	end
	local pool = {}
	for i, q in ipairs(QuestionBank.Questions) do
		if q.Tier == 1 and not used[i] then
			table.insert(pool, q)
		end
	end
	return pool[rng:integer(1, #pool)]
end

function TestService.onPlayerRemoving(player)
	papers[player] = nil
end

function TestService.start()
	services.Remotes.Answer.OnServerEvent:Connect(function(player, slot, option)
		TestService.answer(player, slot, option)
	end)
end

return TestService
