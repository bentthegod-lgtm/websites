local load = require("./loader")
local Minigames = load("Minigames")
local Rng = load("Rng")
local PhoneConfig = load("Config/PhoneConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Minigames: " .. name, fn = fn })
end

local function session(seed)
	return Minigames.newSession(PhoneConfig, Rng.new(seed or 1), 100)
end

test("feed: like the current post once; stale or repeated likes are rejected", function()
	local s = session()
	local id = s.post.id
	local ok, base, taps = Minigames.like(s, id, PhoneConfig)
	assert(ok and base >= PhoneConfig.Feed.LikeClout and taps == 1)
	assert(not Minigames.like(s, id, PhoneConfig), "liked twice")
	assert(not Minigames.like(s, id + 5, PhoneConfig), "liked a post that isn't on screen")
	assert(not Minigames.like(s, "1", PhoneConfig))
	assert(Minigames.scroll(s, 101, PhoneConfig, Rng.new(2)))
	assert(not Minigames.scroll(s, 101.1, PhoneConfig, Rng.new(2)), "scroll spam allowed")
	assert(s.post.id == id + 1)
	assert(Minigames.like(s, s.post.id, PhoneConfig))
end)

test("text: right word pays (faster = more), wrong word and bots don't", function()
	local s = session(3)
	local rng = Rng.new(4)
	local word = s.text.word
	assert(table.find(s.text.options, word), "quick replies miss the answer")
	assert(#s.text.options == 3)
	local ok, _, _, reason = Minigames.submitText(s, word, 100.0, PhoneConfig, rng)
	assert(not ok and reason == "toofast", "instant reply accepted")
	local ok2, fast = Minigames.submitText(s, "  " .. string.upper(word) .. "!", 101, PhoneConfig, rng)
	assert(ok2 and fast > PhoneConfig.Text.BaseClout, "normalised answer rejected")
	local word2 = s.text.word
	local _, slow = Minigames.submitText(s, word2, 101 + PhoneConfig.Text.Timeout + 1, PhoneConfig, rng)
	assert(slow == PhoneConfig.Text.BaseClout, "slow answer got a speed bonus")
	local okWrong, baseWrong, _, why = Minigames.submitText(s, "definitelynotaword", 120, PhoneConfig, rng)
	assert(not okWrong and baseWrong == 0 and why == "wrong")
	assert(not Minigames.submitText(s, string.rep("a", 50), 130, PhoneConfig, rng))
	assert(not Minigames.submitText(s, 42, 130, PhoneConfig, rng))
end)

test("tap dash: centre = perfect, edge = miss, combo grows and is capped", function()
	local s = session(5)
	local g = PhoneConfig.Game
	local start = s.game.start
	-- marker at 0.5 after half a period
	local perfectT = start + g.Period * 0.5
	local ok, base, _, grade = Minigames.tap(s, perfectT, perfectT + 0.05, PhoneConfig)
	assert(ok and grade == "Perfect" and base == g.PerfectClout, grade)
	local t2 = perfectT + g.Period * 2 -- same position, one full ping-pong later
	local _, base2, _, grade2 = Minigames.tap(s, t2, t2, PhoneConfig)
	assert(grade2 == "Perfect" and base2 > base, "combo did not grow")
	local missT = start + g.Period * 4 + 0.01
	local _, base3, _, grade3 = Minigames.tap(s, missT, missT, PhoneConfig)
	assert(grade3 == "Miss" and base3 == 0 and s.combo == 0)
	local _, _, _, spam = Minigames.tap(s, missT + 0.01, missT + 0.01, PhoneConfig)
	assert(spam == "spam")
	-- A claimed time far in the past is ignored (server time is used instead).
	local t4 = missT + 1
	local okLate = Minigames.tap(s, t4 - 10, t4, PhoneConfig)
	assert(okLate)
	s.combo = 100
	local t5 = start + g.Period * 10.5
	local _, capped = Minigames.tap(s, t5, t5, PhoneConfig)
	assert(capped == g.PerfectClout * g.ComboCap, "combo not capped: " .. capped)
end)

test("selfie cooldown", function()
	local s = session(6)
	assert(Minigames.selfie(s, 10, PhoneConfig))
	assert(not Minigames.selfie(s, 12, PhoneConfig))
	assert(Minigames.selfie(s, 10 + PhoneConfig.Selfie.Cooldown, PhoneConfig))
end)

test("per-app and per-class caps clamp rewards", function()
	local s = session(7)
	local caps = PhoneConfig.Caps
	local got = 0
	for _ = 1, 1000 do
		got += Minigames.grant(s, "Feed", 5, caps)
	end
	assert(got == caps.Feed, "feed cap " .. got)
	local more = 0
	for _, app in ipairs({ "Text", "Game", "Selfie", "Passive" }) do
		for _ = 1, 1000 do
			more += Minigames.grant(s, app, 7, caps)
		end
	end
	assert(got + more == caps.Total, "total cap " .. (got + more))
	assert(Minigames.grant(s, "Text", 0 / 0, caps) == 0)
	assert(Minigames.grant(s, "Text", -5, caps) == 0)
end)

test("client view never leaks more than the screen shows", function()
	local s = session(8)
	local v = Minigames.view(s)
	assert(v.post and v.text and v.game)
	assert(v.text.word == nil, "the answer is in the view (options are fine, the key isn't)")
end)

return cases
