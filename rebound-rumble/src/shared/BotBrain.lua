--[[
	BotBrain - pure decision logic for bots. Bots play by exactly the same server rules as
	players: they "press" parry at a chosen distance and the same ParryJudge decides. Their
	skill only changes WHEN they press (inside the window, too early, or not at all).
]]

local BallMath = require(script.Parent.BallMath)

local BotBrain = {}

function BotBrain.chance(skill, speed, botCfg, ballCfg)
	local penalty = botCfg.SpeedPenalty * math.max(0, speed - ballCfg.BaseSpeed) / 100
	return math.clamp(skill - penalty, botCfg.MinChance, botCfg.MaxChance)
end

--[[
	Called once each time the ball starts chasing this bot (and again after a Freeze etc.).
	Returns a plan { pressAt: number? (distance in studs at which to press), success: bool }.
	pressAt == nil means the bot freezes up and never presses.
]]
function BotBrain.plan(skill, speed, rng, cfg)
	local range = BallMath.parryRange(speed, cfg.Parry)
	local success = rng:chance(BotBrain.chance(skill, speed, cfg.Bots, cfg.Ball))
	if success then
		local fraction = rng:range(cfg.Bots.ReactMin, cfg.Bots.ReactMax)
		-- Never plan to press inside the hit radius.
		return { pressAt = math.max(cfg.Ball.HitRadius + 1.5, range * fraction), success = true }
	end
	if rng:chance(0.5) then
		-- Panics and presses too early: a whiff, then the long cooldown.
		return { pressAt = range * rng:range(1.35, 2.2), success = false }
	end
	return { pressAt = nil, success = false }
end

-- Whether a bot following `plan` should press now at the given distance.
function BotBrain.shouldPress(plan, distance)
	return plan ~= nil and plan.pressAt ~= nil and not plan.pressed and distance <= plan.pressAt
end

-- Bots aim at a random opponent, with a mild preference for whoever last hit the ball
-- at them ("revenge") so rallies happen.
function BotBrain.chooseAim(selfId, candidates, lastDeflector, rng)
	local pool = {}
	for _, c in ipairs(candidates) do
		if c.id ~= selfId then
			table.insert(pool, c)
			if c.id == lastDeflector then
				table.insert(pool, c)
			end
		end
	end
	return rng:pick(pool)
end

return BotBrain
