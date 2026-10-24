--[[
	BallService - the authoritative energy ball.

	The server simulates the ball (BallMath), records its path for lag compensation and
	decides every parry (ParryJudge). Clients only render it: they receive BallSync
	snapshots at GameConfig.Ball.SyncRate and predict between them with the same BallMath.

	Phases:
	  "charging"  - hovering over the centre pad before the first target
	  "chasing"   - homing at targetId
	  "pending"   - reached the target; waiting HitGrace seconds for in-flight parries
	  "respawn"   - after an elimination, back to the centre for a moment
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)
local BallMath = require(Shared.BallMath)
local ParryJudge = require(Shared.ParryJudge)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local BallService = {}

local services
local ball
local highlight
local rng
local syncAccumulator = 0
local B, P = GameConfig.Ball, GameConfig.Parry

function BallService.init(registry)
	services = registry
	rng = Rng.new(os.time())
end

function BallService.current()
	return ball
end

function BallService.targetId()
	return ball and ball.targetId
end

local function snapshot()
	if not ball then
		return { active = false }
	end
	return {
		active = true,
		p = ball.state.pos,
		d = ball.state.dir,
		s = ball.state.speed,
		c = ball.state.curve,
		t = ball.targetId,
		ph = ball.phase,
		st = Clock.now(),
		slow = if ball.slowUntil > Clock.now() then ball.slowFactor else 1,
		by = ball.lastDeflector,
		trail = ball.trail,
	}
end

function BallService.syncTo(player)
	services.Remotes.BallSync:FireClient(player, snapshot())
end

local function broadcast()
	services.Remotes.BallSync:FireAllClients(snapshot())
end

local function setHighlight(c)
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if c and c.model and c.model.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "RR_TargetHighlight"
		highlight.FillColor = Color3.fromRGB(255, 40, 40)
		highlight.FillTransparency = 0.55
		highlight.OutlineColor = Color3.fromRGB(255, 220, 220)
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = c.model
	end
end

local function setTarget(c)
	ball.targetId = c and c.id
	ball.targetSince = Clock.now()
	setHighlight(c)
	services.Remotes.BallEvent:FireAllClients("target", { id = ball.targetId, speed = ball.state.speed })
	if c and c.isBot then
		services.BotService.onTargeted(c, ball.state.speed)
	end
	broadcast()
end

local function randomTarget(exceptId)
	local pool = {}
	for _, c in ipairs(services.MatchService.alive()) do
		if c.id ~= exceptId and services.MatchService.positionOf(c) then
			table.insert(pool, c)
		end
	end
	return rng:pick(pool)
end

local function resetToCenter(phase, delay)
	ball.state.pos = ball.home
	ball.state.dir = Vector3.new(0, -1, 0)
	ball.state.speed = B.BaseSpeed
	ball.state.curve = 0
	ball.phase = phase
	ball.timer = delay
	ball.lastDeflector = nil
	ball.trail = nil
	ball.slowUntil = 0
	BallMath.clearHistory(ball.history)
	setTarget(nil)
end

function BallService.begin(arena)
	local home = arena.center + Vector3.new(0, B.SpawnHeight, 0)
	ball = {
		home = home,
		state = { pos = home, dir = Vector3.new(0, -1, 0), speed = B.BaseSpeed, curve = 0 },
		history = BallMath.newHistory(),
		phase = "charging",
		timer = B.SpawnPause,
		targetId = nil,
		lastDeflector = nil,
		slowUntil = 0,
		slowFactor = 1,
		deflects = 0,
	}
	syncAccumulator = 0
	services.Remotes.BallEvent:FireAllClients("spawn", { pos = home })
	broadcast()
end

function BallService.stop()
	ball = nil
	setHighlight(nil)
	services.Remotes.BallEvent:FireAllClients("clear", {})
	broadcast()
end

local function launchAt(c)
	local pos = services.MatchService.positionOf(c)
	ball.phase = "chasing"
	if pos then
		local offset = pos - ball.state.pos
		if offset.Magnitude > 1e-3 then
			ball.state.dir = offset.Unit
		end
	end
	setTarget(c)
end

local function resolveHit()
	local victim = services.MatchService.get(ball.targetId)
	if not victim or not victim.alive then
		local nextTarget = randomTarget(nil)
		if nextTarget then
			launchAt(nextTarget)
		end
		return
	end
	if victim.shieldReady then
		-- Shield: absorbs this miss once per round. No kill credit, speed kept.
		victim.shieldReady = false
		ball.lastDeflector = nil
		ball.trail = nil
		local pos = services.MatchService.positionOf(victim)
		services.Remotes.Fx:FireAllClients("ShieldPop", { id = victim.id, pos = pos })
		services.Remotes.KillFeed:FireAllClients({ victim = victim.name, cause = "shield" })
		local nextTarget = randomTarget(victim.id)
		if nextTarget then
			ball.phase = "chasing"
			ball.state.dir = Vector3.new(0, 1, 0)
			ball.state.curve = B.CurveDelay
			setTarget(nextTarget)
		end
		return
	end
	local speed = ball.state.speed
	local killer = ball.lastDeflector
	resetToCenter("respawn", B.RespawnDelay)
	services.MatchService.eliminate(victim, killer, "ball", { speed = speed })
end

-- Main simulation step (Heartbeat on the server, called manually by the harness).
function BallService.step(dt)
	if not ball then
		return
	end
	local now = Clock.now()
	local s = ball.state
	if ball.phase == "charging" or ball.phase == "respawn" then
		ball.timer -= dt
		BallMath.record(ball.history, now, s.pos, B.HistorySeconds)
		if ball.timer <= 0 then
			local target = randomTarget(nil)
			if target then
				launchAt(target)
			end
		end
	elseif ball.phase == "chasing" then
		local target = services.MatchService.get(ball.targetId)
		local pos = target and target.alive and services.MatchService.positionOf(target)
		if not pos then
			local nextTarget = randomTarget(ball.targetId)
			if nextTarget then
				setTarget(nextTarget)
			else
				ball.phase = "charging"
				ball.timer = 1
			end
			return
		end
		local elapsed = now - services.MatchService.roundStartedAt()
		if elapsed > B.OvertimeAfter then
			s.speed = math.min(B.MaxSpeed, s.speed + B.OvertimeAccel * dt)
		end
		local slow = if now < ball.slowUntil then ball.slowFactor else 1
		local _, distance = BallMath.step(s, pos, dt, B, slow)
		BallMath.record(ball.history, now, s.pos, B.HistorySeconds)
		ball.distance = distance
		if distance <= B.HitRadius then
			ball.phase = "pending"
			ball.hitAt = now
			ball.timer = P.HitGrace
		end
	elseif ball.phase == "pending" then
		BallMath.record(ball.history, now, s.pos, B.HistorySeconds)
		ball.timer -= dt
		if ball.timer <= 0 then
			resolveHit()
		end
	end
	syncAccumulator += dt
	if ball and syncAccumulator >= 1 / B.SyncRate then
		syncAccumulator = 0
		broadcast()
	end
end

-- Distance from the ball to a contestant (nil if unknown).
function BallService.distanceTo(c)
	local pos = services.MatchService.positionOf(c)
	if not ball or not pos then
		return nil
	end
	return (ball.state.pos - pos).Magnitude
end

local function deflect(c, aim)
	local origin = services.MatchService.positionOf(c)
	local candidates = {}
	for _, other in ipairs(services.MatchService.alive()) do
		local pos = other ~= c and services.MatchService.positionOf(other)
		if pos then
			table.insert(candidates, { id = other.id, pos = pos })
		end
	end
	local targetId = BallMath.pickTarget(origin, aim, candidates, P.AimConeDot)
	if not targetId then
		return false
	end
	local s = ball.state
	s.speed = BallMath.deflectSpeed(s.speed, B)
	local flat = Vector3.new(aim.X, math.clamp(aim.Y, -0.2, 0.6), aim.Z)
	s.dir = if flat.Magnitude > 1e-3 then (flat.Unit + Vector3.new(0, 0.15, 0)).Unit else Vector3.new(0, 1, 0)
	s.curve = B.CurveDelay
	-- Start the return flight just in front of the parrying player.
	s.pos = origin + s.dir * (B.HitRadius + 1.5) + Vector3.new(0, 1, 0)
	ball.phase = "chasing"
	ball.hitAt = nil
	ball.lastDeflector = c.id
	ball.trail = c.cosmetics and c.cosmetics.Trail
	ball.deflects += 1
	c.parries += 1
	BallMath.record(ball.history, Clock.now(), s.pos, B.HistorySeconds)
	services.Remotes.BallEvent:FireAllClients("deflect", { by = c.id, to = targetId, speed = s.speed, trail = ball.trail, pos = s.pos })
	if c.player then
		services.RewardService.track(c.player, "Parries", 1)
		local profile = services.DataService.getProfile(c.player)
		if profile and s.speed > profile.Stats.BestSpeed then
			profile.Stats.BestSpeed = math.floor(s.speed)
		end
	end
	setTarget(services.MatchService.get(targetId))
	return true
end

--[[
	A parry press by contestant c. clientTime is the server-synchronised time of the press
	(bots pass Clock.now()). Returns the ParryJudge result plus `cooldown` seconds.
]]
function BallService.tryParry(c, clientTime, aim)
	if not c or not c.alive or not ball then
		return { ok = false, reason = "inactive", cooldown = 0 }
	end
	local now = Clock.now()
	local okAttempt, why = ParryJudge.canAttempt(c.parryMemo, now, P)
	if not okAttempt then
		return { ok = false, reason = why, cooldown = math.max(0, (c.parryMemo.readyAt or now) - now) }
	end
	local pos = services.MatchService.positionOf(c)
	if not pos then
		return { ok = false, reason = "inactive", cooldown = 0 }
	end
	local isTarget = ball.targetId == c.id and (ball.phase == "chasing" or ball.phase == "pending")
	local result = ParryJudge.judge({
		now = now,
		clientTime = clientTime,
		history = ball.history,
		playerPos = pos,
		isTarget = isTarget,
		speed = ball.state.speed,
		hitTime = if ball.phase == "pending" then ball.hitAt else nil,
	}, P)
	if result.ok and not deflect(c, aim) then
		result.ok = false
		result.reason = "no_target"
	end
	ParryJudge.applyCooldown(c.parryMemo, now, result.ok, P)
	result.cooldown = c.parryMemo.readyAt - now
	services.Remotes.Fx:FireAllClients("Swing", { id = c.id, ok = result.ok, item = c.cosmetics and c.cosmetics.ParryFx, aim = aim })
	return result
end

function BallService.freeze(c, factor, duration)
	if not ball or ball.targetId ~= c.id or ball.phase ~= "chasing" then
		return false
	end
	ball.slowUntil = Clock.now() + duration
	ball.slowFactor = factor
	services.Remotes.Fx:FireAllClients("Freeze", { id = c.id, duration = duration, pos = ball.state.pos })
	broadcast()
	return true
end

local function validAim(aim)
	if typeof(aim) ~= "Vector3" then
		return nil
	end
	local m = aim.Magnitude
	if m ~= m or m < 0.1 or m > 10 or math.abs(aim.X) == math.huge or math.abs(aim.Y) == math.huge or math.abs(aim.Z) == math.huge then
		return nil
	end
	return aim.Unit
end

BallService.validAim = validAim

function BallService.start()
	services.Remotes.Parry.OnServerEvent:Connect(function(player, clientTime, aim)
		local direction = validAim(aim)
		if not direction then
			return
		end
		if type(clientTime) ~= "number" then
			clientTime = nil
		end
		local c = services.MatchService.forPlayer(player)
		if not c or not c.alive then
			services.Remotes.ParryResult:FireClient(player, false, "inactive", 0)
			return
		end
		local result = BallService.tryParry(c, clientTime, direction)
		services.Remotes.ParryResult:FireClient(player, result.ok, result.reason, result.cooldown)
	end)
end

return BallService
