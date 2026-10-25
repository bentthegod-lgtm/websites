--[[
	Minigames - the four phone apps, validated and scored on the server (pure).

	The client only sends inputs: like(postId), scroll(), text(reply), tap(claimedTime),
	selfie(). The server keeps the state (current post, the word your bestie asked for, the
	Tap Dash marker start time, selfie cooldown) and decides the reward. Every result returns
	the BASE Clout (before multipliers) and how many screen taps it made (noise).

	Caps: Minigames.grant() clamps base Clout to the per-app and total per-class caps.
]]

local Minigames = {}

function Minigames.newSession(cfg, rng, now)
	local s = {
		used = {},
		total = 0,
		combo = 0,
		postSeq = 0,
		selfieAt = -math.huge,
		lastScroll = -math.huge,
		lastTap = -math.huge,
		stats = { likes = 0, texts = 0, perfects = 0, selfies = 0 },
	}
	for app in pairs(cfg.Caps) do
		s.used[app] = 0
	end
	Minigames.nextPost(s, cfg, rng)
	Minigames.nextText(s, cfg, rng, now)
	Minigames.resetGame(s, now)
	return s
end

---------------------------------------------------------------------------------------------
-- Feed
---------------------------------------------------------------------------------------------

function Minigames.nextPost(s, cfg, rng)
	s.postSeq += 1
	local def = cfg.Feed.Posts[rng:integer(1, #cfg.Feed.Posts)]
	s.post = {
		id = s.postSeq,
		kind = def.Kind,
		caption = def.Caption,
		viral = rng:chance(cfg.Feed.ViralChance),
		likes = rng:integer(3, 900),
		liked = false,
	}
	return s.post
end

function Minigames.like(s, postId, cfg)
	local post = s.post
	if type(postId) ~= "number" or not post or post.id ~= postId or post.liked then
		return false, 0, 0
	end
	post.liked = true
	s.stats.likes += 1
	local base = cfg.Feed.LikeClout * (if post.viral then cfg.Feed.ViralMultiplier else 1)
	return true, base, cfg.Feed.Taps
end

function Minigames.scroll(s, now, cfg, rng)
	if now - s.lastScroll < cfg.Feed.ScrollGap then
		return false, 0
	end
	s.lastScroll = now
	Minigames.nextPost(s, cfg, rng)
	return true, cfg.Feed.Taps
end

---------------------------------------------------------------------------------------------
-- Text your friend
---------------------------------------------------------------------------------------------

function Minigames.nextText(s, cfg, rng, now)
	local words = cfg.Text.Words
	local word = words[rng:integer(1, #words)]
	-- Quick replies: the right word plus two different decoys, shuffled.
	local options = { word }
	while #options < 3 do
		local decoy = words[rng:integer(1, #words)]
		if not table.find(options, decoy) then
			table.insert(options, decoy)
		end
	end
	for i = #options, 2, -1 do
		local j = rng:integer(1, i)
		options[i], options[j] = options[j], options[i]
	end
	s.text = {
		word = word,
		prompt = string.format(cfg.Text.Asks[rng:integer(1, #cfg.Text.Asks)], word),
		options = options,
		issuedAt = now,
	}
	return s.text
end

function Minigames.normalize(text)
	if type(text) ~= "string" or #text > 24 then
		return nil
	end
	local cleaned = string.lower((string.gsub(text, "[%s%p]", "")))
	if cleaned == "" then
		return nil
	end
	return cleaned
end

-- Returns ok, base, taps, reason
function Minigames.submitText(s, reply, now, cfg, rng)
	local t = s.text
	local cleaned = Minigames.normalize(reply)
	if not t or not cleaned then
		return false, 0, 0, "invalid"
	end
	local elapsed = now - t.issuedAt
	local taps = cfg.Text.Taps
	if elapsed < #t.word * cfg.Text.MinSecondsPerChar then
		return false, 0, 0, "toofast"
	end
	if cleaned ~= t.word then
		-- Wrong word: your bestie is confused, new prompt, no Clout.
		Minigames.nextText(s, cfg, rng, now)
		return false, 0, taps, "wrong"
	end
	local speed = math.clamp(1 - elapsed / cfg.Text.Timeout, 0, 1)
	local base = cfg.Text.BaseClout + cfg.Text.SpeedBonus * speed
	s.stats.texts += 1
	Minigames.nextText(s, cfg, rng, now)
	return true, base, taps, if speed > 0.6 then "fast" else "ok"
end

---------------------------------------------------------------------------------------------
-- Tap Dash (timing game)
---------------------------------------------------------------------------------------------

function Minigames.resetGame(s, now)
	s.game = { start = now }
	s.combo = 0
end

-- Marker position 0..1 (ping-pong) at time t. The client draws the same function.
function Minigames.markerAt(game, t, period)
	local phase = ((t - game.start) / period) % 2
	return if phase <= 1 then phase else 2 - phase
end

-- Returns ok, base, taps, grade ("Perfect" | "Good" | "Miss")
function Minigames.tap(s, claimed, now, cfg)
	local g = cfg.Game
	if now - s.lastTap < g.TapGap then
		return false, 0, 0, "spam"
	end
	s.lastTap = now
	-- Trust the claimed press time only inside the latency window.
	local t = now
	if type(claimed) == "number" and claimed == claimed and claimed <= now + 0.05 and claimed >= now - g.LatencyWindow then
		t = claimed
	end
	local pos = Minigames.markerAt(s.game, t, g.Period)
	local off = math.abs(pos - 0.5)
	local grade, base
	if off <= g.PerfectZone then
		grade, base = "Perfect", g.PerfectClout
		s.stats.perfects += 1
	elseif off <= g.GoodZone then
		grade, base = "Good", g.GoodClout
	else
		s.combo = 0
		return true, 0, g.Taps, "Miss"
	end
	local mult = math.min(g.ComboCap, 1 + s.combo * g.ComboStep)
	s.combo += 1
	return true, base * mult, g.Taps, grade
end

---------------------------------------------------------------------------------------------
-- Selfie
---------------------------------------------------------------------------------------------

function Minigames.selfie(s, now, cfg)
	if now - s.selfieAt < cfg.Selfie.Cooldown then
		return false, 0, 0
	end
	s.selfieAt = now
	s.stats.selfies += 1
	return true, cfg.Selfie.Clout, cfg.Selfie.Taps
end

---------------------------------------------------------------------------------------------
-- Caps
---------------------------------------------------------------------------------------------

-- Clamps `base` to what's left of the app's and the class's cap. Returns the granted base.
function Minigames.grant(s, app, base, caps)
	if type(base) ~= "number" or base ~= base or base <= 0 then
		return 0
	end
	local appLeft = (caps[app] or 0) - (s.used[app] or 0)
	local totalLeft = caps.Total - s.total
	local granted = math.max(0, math.min(base, appLeft, totalLeft))
	s.used[app] = (s.used[app] or 0) + granted
	s.total += granted
	return granted
end

-- What the client needs to draw the apps (never includes anything it could cheat with
-- beyond what it already sees on screen).
function Minigames.view(s)
	return {
		post = s.post and { id = s.post.id, kind = s.post.kind, caption = s.post.caption, viral = s.post.viral, likes = s.post.likes, liked = s.post.liked },
		text = s.text and { prompt = s.text.prompt, options = s.text.options, issuedAt = s.text.issuedAt },
		game = s.game and { start = s.game.start },
		combo = s.combo,
		selfieAt = math.max(s.selfieAt, -1e9),
	}
end

return Minigames
