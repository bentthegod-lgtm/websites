--[[
	KartService - kart replication and validation.

	Each racing client simulates its own kart (KartPhysics, client-predicted) and sends
	KartState(pos, vel, yaw, flags, seq) ~20 times a second. The server:
	  * rate-limits it and checks every argument (Vector3s finite and in range, numbers);
	  * SPEED SANITY: every move spends from a travel budget that refills at
	    KartStats.MaxLegalSpeed (with slack, more right after a KartEffect launch); an
	    impossible move is rejected and the client is teleported back (KartCorrect) to the
	    last accepted state. Until the client is back near that spot, further updates are
	    ignored;
	  * during the countdown, karts must stay on their grid slot;
	  * the Ghost flag is set / cleared by the server's ghost window, never the client's;
	  * feeds every accepted move to RaceService (checkpoints in order, wrong way, kill plane).
	Then it rebroadcasts every kart (players and bots) as one Karts snapshot ~15 times a
	second, stamped with the server time; clients buffer ~100 ms and interpolate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local KartPhysics = require(Shared.KartPhysics)
local Net = require(Shared.Net)
local RateLimit = require(script.Parent.RateLimit)

local KartService = {}

local services
local limit = RateLimit.new(GameConfig.Net.StateRateLimit, 12)
local broadcastAcc = 0
KartService.rejected = 0
KartService.accepted = 0

local function now()
	return workspace:GetServerTimeNow()
end

function KartService.init(registry)
	services = registry
end

-- Server-side placement (grid, respawn): the next client update is measured from here.
function KartService.place(racer, cf, ghost)
	racer.kart = { pos = cf.Position, vel = Vector3.new(), yaw = KartPhysics.yawOf(cf.LookVector), flags = 0, at = now() }
	racer.placedAt = now()
	racer.placedPos = cf.Position
	racer.awaitingSnap = racer.kind == "player"
	racer.correction = nil
	racer.moveBudget = nil
	if ghost and ghost > 0 then
		racer.ghostUntil = now() + ghost
	end
end

function KartService.correct(racer, reason)
	KartService.rejected += 1
	racer.strikes += 1
	local k = racer.kart
	local cf = CFrame.new(k.pos) * CFrame.Angles(0, k.yaw, 0)
	racer.correction = { pos = k.pos, at = now() }
	racer.moveBudget = nil
	if racer.player and racer.player.Parent then
		services.Remotes.KartCorrect:FireClient(racer.player, cf, k.vel, reason)
	end
end

--[[
	Validates one client update. Returns true if accepted, false + reason otherwise.
	(Called by the remote handler; the harness calls the handler through the stub remote.)
]]
function KartService.onState(player, pos, vel, yaw, flags, seq)
	if not limit:allow(player) then
		return false, "rate"
	end
	pos = Net.vector(pos, 50000)
	vel = Net.vector(vel, 2000)
	yaw = Net.number(yaw, -1e6, 1e6)
	flags = Net.number(flags, 0, 65535)
	seq = Net.number(seq, 0, 1e12)
	if not (pos and vel and yaw and flags and seq) then
		return false, "args"
	end
	local race = services.RaceService.race()
	local racer = services.RaceService.racerOf(player)
	if not race or not racer or racer.left then
		return false, "not racing"
	end
	local phase = services.RaceService.phase()
	if phase ~= "Countdown" and phase ~= "Racing" then
		return false, "phase"
	end
	if racer.lastSeq and seq <= racer.lastSeq then
		return false, "old"
	end
	local k = racer.kart
	-- after a correction / placement, wait for the client to come back to that spot
	local anchor = racer.correction and racer.correction.pos or (racer.awaitingSnap and k.pos)
	if anchor then
		if (pos - anchor).Magnitude > GameConfig.AntiCheat.FlatSlack then
			return false, "awaiting snap"
		end
		racer.correction = nil
		racer.awaitingSnap = false
		k.at = now()
	end
	local t = now()
	local budget = nil
	if phase == "Countdown" then
		-- held on the grid slot (measured from the slot, not the last update, so a client
		-- can't creep forward a little per update)
		if (pos - (racer.placedPos or k.pos)).Magnitude > 3 then
			KartService.correct(racer, "grid")
			return false, "grid"
		end
	else
		--[[
			A travel budget instead of a per-update allowance: it refills at the legal speed
			(with slack) over real elapsed time and every move spends from it. A flat slack per
			update would let a client gain FlatSlack studs with every packet it sends (40 a
			second = hundreds of studs/s). The budget banks up to MaxDt seconds of travel, so a
			burst of queued updates after a short lag spike is still accepted.
		]]
		local AC = GameConfig.AntiCheat
		local elapsed = math.max(0, t - (k.at or t))
		local dt = math.clamp(elapsed, 1 / 60, AC.MaxDt)
		local legal = KartStats.MaxLegalSpeed
		if t < (racer.effectUntil or 0) then
			legal += 90
		end
		local rate = legal * AC.SpeedSlack
		budget = math.min((racer.moveBudget or AC.FlatSlack) + rate * elapsed, rate * AC.MaxDt + AC.FlatSlack)
		local d = pos - k.pos
		local horizontal = Vector3.new(d.X, 0, d.Z).Magnitude
		local vertical = math.abs(d.Y)
		if horizontal > budget or vertical > rate * dt + AC.FlatSlack + AC.VerticalSlack or vel.Magnitude > legal * 1.5 then
			KartService.correct(racer, "speed")
			return false, "speed"
		end
		budget -= horizontal
	end
	-- the ghost bit is the server's call (other clients skip bumps against ghosts)
	flags = math.floor(flags)
	local ghost = t < (racer.ghostUntil or 0)
	if KartPhysics.hasFlag(flags, KartPhysics.Flags.Ghost) ~= ghost then
		flags += if ghost then KartPhysics.Flags.Ghost else -KartPhysics.Flags.Ghost
	end
	local from = k.pos
	local prevAt = k.at
	racer.moveBudget = budget
	racer.kart = { pos = pos, vel = vel, yaw = yaw, flags = flags, at = t }
	racer.lastSeq = seq
	KartService.accepted += 1
	services.RaceService.onMoved(racer, from, pos, vel, t - (prevAt or t))
	return true
end

function KartService.snapshot()
	local list = {}
	for _, r in ipairs(services.RaceService.racers()) do
		if not r.left then
			local k = r.kart
			table.insert(list, {
				id = r.id,
				p = k.pos,
				v = k.vel,
				y = k.yaw,
				f = k.flags,
				pl = r.place,
				lap = r.progress.lap,
				g = now() < (r.ghostUntil or 0),
			})
		end
	end
	return { t = now(), k = list }
end

function KartService.step(dt)
	broadcastAcc += dt
	local interval = 1 / GameConfig.Net.BroadcastRate
	if broadcastAcc >= interval then
		broadcastAcc %= interval
		services.Remotes.Karts:FireAllClients(KartService.snapshot())
	end
end

function KartService.onPlayerRemoving(player)
	limit:forget(player)
end

function KartService.start()
	services.Remotes.KartState.OnServerEvent:Connect(function(player, pos, vel, yaw, flags, seq)
		KartService.onState(player, pos, vel, yaw, flags, seq)
	end)
end

return KartService
