--[[
	RaceService - the server-authoritative race flow.

	  Lobby      players walk onto the RACE PORTAL pad or press READY. The race starts when
	             everyone present is ready, or AutoStartAfter seconds after the first ready.
	  Countdown  up to 12 racers (players first, BOTS fill the grid to Bots.FillTo when
	             enabled) are placed on the grid; characters are parked out of sight; a grid
	             flyover, then the 3-2-1-GO lights (clients show them from goAt).
	  Racing     3 laps. Karts report their state (KartService validates it); bots drive on
	             the server. Checkpoints must be crossed in order (RaceMath), positions are
	             ranked live (lap, checkpoint, distance to the next checkpoint), wrong way is
	             detected, the final lap is announced. After the FIRST finisher a DNF timer
	             (30 s) runs; the race ends when every human has finished or it expires.
	  Results    placings, times, best laps; coins + XP into the profile; then the lobby.

	Late joiners spectate the running race and are queued for the next one. A racer who
	leaves is removed cleanly; a race with no humans left is aborted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local RaceMath = require(Shared.RaceMath)
local Format = require(Shared.Format)
local RateLimit = require(script.Parent.RateLimit)

local RaceService = {}

local R = GameConfig.Race
local services
local world
local phase = "Lobby"
local queue = {} -- [player] = os.clock() when readied
local queueOrder = {}
local firstReadyAt = nil
local race = nil
local resultsUntil = nil
local raceCounter = 0
local readyLimit = RateLimit.new(2, 4)
local respawnLimit = {}
RaceService.lastResults = nil

local function now()
	return workspace:GetServerTimeNow()
end
RaceService.now = now

function RaceService.init(registry)
	services = registry
end

function RaceService.setWorld(newWorld)
	world = newWorld
end

function RaceService.phase()
	return phase
end

function RaceService.race()
	return race
end

function RaceService.racers()
	return if race then race.racers else {}
end

function RaceService.racerOf(player)
	return race and race.byPlayer[player]
end

function RaceService.racerById(id)
	return race and race.byId[id]
end

function RaceService.isQueued(player)
	return queue[player] ~= nil
end

local function humans()
	local n = 0
	if race then
		for _, r in ipairs(race.racers) do
			if r.kind == "player" and not r.left then
				n += 1
			end
		end
	end
	return n
end
RaceService.humans = humans

-- The leader's current lap (for the Event Director's final-lap rules).
function RaceService.leaderLap()
	if not race then
		return 1
	end
	local lap = 1
	for _, r in ipairs(race.racers) do
		lap = math.max(lap, math.min(R.Laps, r.progress.lap))
	end
	return lap
end

-- Public race snapshot (RaceState remote).
function RaceService.state()
	local s = {
		phase = phase,
		map = R.Map,
		laps = R.Laps,
		queued = 0,
		players = #Players:GetPlayers(),
		queueIds = {},
		autoStartIn = nil,
		worldReady = world ~= nil and world.ready == true,
	}
	for _, player in ipairs(queueOrder) do
		if queue[player] then
			s.queued += 1
			s.queueIds[tostring(player.UserId)] = true
		end
	end
	if phase == "Lobby" and firstReadyAt then
		s.autoStartIn = math.max(0, math.ceil(R.AutoStartAfter - (os.clock() - firstReadyAt)))
	end
	if race then
		s.raceId = race.id
		s.goAt = race.goAt
		s.introAt = race.introAt
		s.dnfAt = race.dnfAt
		s.racers = {}
		for _, r in ipairs(race.racers) do
			table.insert(s.racers, {
				id = r.id,
				name = r.name,
				kind = r.kind,
				userId = r.userId,
				slot = r.slot,
				vehicle = r.vehicle,
				color = r.color,
				place = r.place,
				lap = r.progress.lap,
				finished = r.progress.finished,
				left = r.left == true,
			})
		end
	end
	if phase == "Results" then
		s.results = RaceService.lastResults
		s.resultsUntil = resultsUntil
	end
	return s
end

function RaceService.sendState(player)
	services.Remotes.RaceState:FireClient(player, RaceService.state())
end

function RaceService.broadcastState()
	services.Remotes.RaceState:FireAllClients(RaceService.state())
end

-- Lobby --------------------------------------------------------------------------------

function RaceService.setReady(player, ready)
	if not player.Parent then
		return false
	end
	if ready then
		if queue[player] then
			return true
		end
		local count = 0
		for _, p in ipairs(queueOrder) do
			if queue[p] then
				count += 1
			end
		end
		if count >= R.MaxRacers then
			services.Remotes.Notify:FireClient(player, "The grid is full - you're first in line for the next race.", "info")
			return false
		end
		queue[player] = os.clock()
		table.insert(queueOrder, player)
		if phase == "Lobby" and not firstReadyAt then
			firstReadyAt = os.clock()
		end
	else
		queue[player] = nil
		local i = table.find(queueOrder, player)
		if i then
			table.remove(queueOrder, i)
		end
	end
	player:SetAttribute("CK_Queued", queue[player] ~= nil)
	RaceService.broadcastState()
	return true
end

local function readyPlayers()
	local list = {}
	for _, p in ipairs(queueOrder) do
		if queue[p] and p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

local function characterRoot(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function park(player)
	local character = player.Character
	local root = characterRoot(player)
	if root and world and world.lobby then
		root.Anchored = true
		character:PivotTo(world.lobby.holdCFrame)
	end
end

local function unpark(player, index)
	local character = player.Character
	local root = characterRoot(player)
	if root and world and world.lobby then
		root.Anchored = false
		character:PivotTo(world.lobby.spawnCFrame * CFrame.new(((index or 1) % 6 - 3) * 5, 3, ((index or 1) // 6) * 5))
	end
end

-- Race ---------------------------------------------------------------------------------

local function newRacer(kind, slot, info)
	return {
		id = info.id,
		kind = kind,
		player = info.player,
		userId = info.userId,
		name = info.name,
		vehicle = info.vehicle,
		color = info.color,
		slot = slot,
		joinOrder = slot,
		progress = RaceMath.newProgress(),
		dist = 0,
		hint = nil,
		place = slot,
		kart = { pos = Vector3.new(), vel = Vector3.new(), yaw = 0, flags = 0, at = 0 },
		ghostUntil = 0,
		effectUntil = 0,
		wrongT = 0,
		wrongWay = false,
		lastRespawnAt = -math.huge,
		strikes = 0,
	}
end

function RaceService.begin(players)
	assert(world and world.data, "RaceService.begin before the world exists")
	raceCounter += 1
	local data = world.data
	local t = now()
	race = {
		id = raceCounter,
		data = data,
		gates = data.checkpoints,
		laps = R.Laps,
		introAt = t,
		goAt = t + R.IntroTime + R.CountdownTime,
		racers = {},
		byId = {},
		byPlayer = {},
		dnfAt = nil,
		finished = 0,
		rankAcc = 0,
	}
	local slot = 0
	for _, player in ipairs(players) do
		if slot >= R.MaxRacers then
			break
		end
		slot += 1
		local data2 = services.DataService.getProfile(player)
		local color = GameConfig.Bots.Colors[(slot - 1) % #GameConfig.Bots.Colors + 1]
		local racer = newRacer("player", slot, {
			id = "p" .. player.UserId,
			player = player,
			userId = player.UserId,
			name = player.DisplayName,
			vehicle = if data2 then data2.Vehicle else nil,
			color = color,
		})
		table.insert(race.racers, racer)
		race.byId[racer.id] = racer
		race.byPlayer[player] = racer
		queue[player] = nil
		player:SetAttribute("CK_Queued", false)
		player:SetAttribute("CK_InRace", true)
		park(player)
	end
	queueOrder = {}
	for p, at in pairs(queue) do
		if at then
			table.insert(queueOrder, p)
		end
	end
	firstReadyAt = nil
	if GameConfig.Bots.Enabled and services.BotService then
		local want = math.min(R.MaxRacers, GameConfig.Bots.FillTo) - slot
		for _ = 1, want do
			slot += 1
			local racer = services.BotService.makeRacer(race, slot)
			table.insert(race.racers, racer)
			race.byId[racer.id] = racer
		end
	end
	for _, racer in ipairs(race.racers) do
		local cf = data.grid[racer.slot]
		services.KartService.place(racer, cf, 0)
		local hit = data.main:project(cf.Position)
		racer.dist, racer.hint = hit.dist, hit.index
	end
	phase = "Countdown"
	if services.EventDirector then
		services.EventDirector.onRaceBegin(race)
	end
	RaceService.broadcastState()
	return race
end

function RaceService.tryStart()
	if phase ~= "Lobby" or not world or not world.ready then
		return false
	end
	local ready = readyPlayers()
	if #ready < R.MinToStart then
		return false
	end
	local present = #Players:GetPlayers()
	local allReady = #ready >= present
	local timedOut = firstReadyAt ~= nil and os.clock() - firstReadyAt >= R.AutoStartAfter
	if allReady or timedOut then
		RaceService.begin(ready)
		return true
	end
	return false
end

local function lastGateFrame(racer)
	local gates = race.gates
	local p = racer.progress
	if p.lap == 0 then
		return race.data.grid[racer.slot]
	end
	local index = if p.nextCp == 1 then #gates else p.nextCp - 1
	return gates[index].cframe * CFrame.new(0, KartStats.RideHeight + 0.5, 0)
end
RaceService.lastGateFrame = lastGateFrame

-- Respawn at the last checkpoint, facing the track, with a ghost window.
function RaceService.respawn(racer, reason)
	if not race or racer.left or racer.progress.finished then
		return false
	end
	local cf = lastGateFrame(racer)
	local ghost = KartStats.GhostTime
	racer.lastRespawnAt = now()
	racer.ghostUntil = now() + ghost
	racer.wrongT, racer.wrongWay = 0, false
	services.KartService.place(racer, cf, ghost)
	if racer.kind == "player" and racer.player.Parent then
		services.Remotes.KartRespawn:FireClient(racer.player, cf, ghost, reason or "respawn")
		racer.player:SetAttribute("CK_WrongWay", false)
	elseif racer.bot then
		services.BotService.respawned(racer, cf, ghost)
	end
	return true
end

function RaceService.requestRespawn(player, reason)
	if phase ~= "Racing" then
		return false
	end
	local racer = RaceService.racerOf(player)
	if not racer then
		return false
	end
	local t = os.clock()
	if respawnLimit[player] and t - respawnLimit[player] < GameConfig.AntiCheat.RespawnCooldown then
		return false
	end
	respawnLimit[player] = t
	return RaceService.respawn(racer, if type(reason) == "string" and #reason < 20 then reason else "button")
end

local function notify(racer, kind, info)
	if racer.kind == "player" and racer.player.Parent then
		services.Remotes.RaceEvent:FireClient(racer.player, kind, info)
	end
end

local function finish(racer, lapTime)
	race.finished += 1
	racer.finishPlace = race.finished
	racer.finishTime = racer.progress.finishTime
	local total = racer.finishTime - race.goAt
	notify(racer, "finish", { place = race.finished, time = total, lapTime = lapTime, best = racer.progress.best })
	if race.finished == 1 then
		race.dnfAt = now() + R.DnfTimer
		services.Remotes.Announce:FireAllClients(string.format("%s wins! %d s left to finish.", racer.name, R.DnfTimer), "gold")
		RaceService.broadcastState()
	end
	if racer.kind == "player" then
		racer.player:SetAttribute("CK_Finished", true)
	end
end

--[[
	A kart moved from `from` to `to` (an accepted client update or a bot step). Feeds the
	checkpoint gates in order, tracks distance for ranking and wrong-way, and handles the
	kill plane.
]]
function RaceService.onMoved(racer, from, to, vel, dt)
	if not race or racer.left then
		return
	end
	local data = race.data
	if phase == "Racing" and not racer.progress.finished then
		local event, lapTime = RaceMath.feed(racer.progress, race.gates, from, to, now(), race.laps)
		if event == "lap" then
			notify(racer, "lap", { lap = racer.progress.lap, lapTime = lapTime, best = racer.progress.best, final = racer.progress.lap == race.laps })
		elseif event == "finish" then
			finish(racer, lapTime)
		elseif event == "skip" then
			notify(racer, "skip", { next = racer.progress.nextCp })
		elseif event == "start" then
			notify(racer, "start", {})
		elseif event == "checkpoint" then
			notify(racer, "checkpoint", { next = racer.progress.nextCp })
		end
	end
	local hit = data.main:project(to, racer.hint)
	if hit then
		racer.dist, racer.hint = hit.dist, hit.index
		if phase == "Racing" and not racer.progress.finished then
			local wrong = RaceMath.wrongWay(vel or Vector3.new(), hit.flat)
			racer.wrongT = if wrong then racer.wrongT + (dt or 0.05) else 0
			local was = racer.wrongWay
			racer.wrongWay = racer.wrongT >= GameConfig.Respawn.WrongWayTime
			if racer.wrongWay ~= was and racer.kind == "player" then
				racer.player:SetAttribute("CK_WrongWay", racer.wrongWay)
				notify(racer, "wrongway", { on = racer.wrongWay })
			end
		end
	end
	if to.Y < data.killY and phase == "Racing" then
		RaceService.respawn(racer, "fell")
	end
end

local function rank()
	if not race then
		return
	end
	local list = {}
	for _, r in ipairs(race.racers) do
		if not r.left then
			table.insert(list, r)
		end
	end
	RaceMath.rank(list, race.gates, race.data.main.length)
	for _, r in ipairs(list) do
		if r.kind == "player" and r.player.Parent then
			r.player:SetAttribute("CK_Place", r.place)
			r.player:SetAttribute("CK_Lap", math.clamp(r.progress.lap, 1, race.laps))
		end
	end
	return list
end
RaceService.rank = rank

function RaceService.endRace(reason)
	if not race or phase == "Results" then
		return
	end
	local order = rank() or {}
	local rows = {}
	local field = #order
	for place, r in ipairs(order) do
		local dnf = not r.progress.finished
		table.insert(rows, {
			place = place,
			id = r.id,
			name = r.name,
			kind = r.kind,
			userId = r.userId,
			time = if dnf then nil else r.finishTime - race.goAt,
			best = r.progress.best,
			dnf = dnf,
			laps = math.max(0, r.progress.lap - 1),
		})
	end
	local summary = { rows = rows, laps = race.laps, map = R.Map, reason = reason, raceId = race.id }
	RaceService.lastResults = summary
	for _, row in ipairs(rows) do
		if row.kind == "player" then
			local racer = race.byId[row.id]
			local player = racer and racer.player
			if player and player.Parent then
				local pay = services.RewardService.grantRace(player, { place = row.place, field = field, dnf = row.dnf, time = row.time, bestLap = row.best, mapId = R.Map, laps = row.laps })
				row.coins, row.xp = pay.coins, pay.xp
				local mine = table.clone(summary)
				mine.you = { place = row.place, dnf = row.dnf, coins = pay.coins, xp = pay.xp, newBest = pay.newBest, levelBefore = pay.levelBefore, levelAfter = pay.levelAfter, time = row.time, best = row.best }
				services.Remotes.Results:FireClient(player, mine)
			end
		end
	end
	if services.EventDirector then
		services.EventDirector.onRaceEnd()
	end
	phase = "Results"
	resultsUntil = now() + R.ResultsTime
	local winner = rows[1]
	if winner then
		services.Remotes.Announce:FireAllClients(string.format("%s takes Chaos City in %s!", winner.name, Format.raceTime(winner.time)), "gold")
	end
	RaceService.broadcastState()
	return summary
end

function RaceService.backToLobby()
	if race then
		local i = 0
		for _, r in ipairs(race.racers) do
			if r.kind == "player" and r.player.Parent then
				i += 1
				unpark(r.player, i)
				r.player:SetAttribute("CK_InRace", false)
				r.player:SetAttribute("CK_Finished", false)
				r.player:SetAttribute("CK_WrongWay", false)
				r.player:SetAttribute("CK_Place", nil)
				r.player:SetAttribute("CK_Lap", nil)
			end
		end
	end
	if services.BotService then
		services.BotService.clear()
	end
	race = nil
	resultsUntil = nil
	phase = "Lobby"
	firstReadyAt = nil
	for _, p in ipairs(queueOrder) do
		if queue[p] then
			firstReadyAt = os.clock()
			break
		end
	end
	RaceService.broadcastState()
end

function RaceService.abort(reason)
	if services.EventDirector then
		services.EventDirector.onRaceEnd()
	end
	RaceService.lastResults = { rows = {}, aborted = true, reason = reason }
	RaceService.backToLobby()
end

local function checkEnd()
	if humans() == 0 then
		RaceService.abort("everyone left")
		return
	end
	local t = now()
	if race.dnfAt and t >= race.dnfAt then
		RaceService.endRace("dnf")
		return
	end
	local allDone = true
	for _, r in ipairs(race.racers) do
		if r.kind == "player" and not r.left and not r.progress.finished then
			allDone = false
		end
	end
	if allDone then
		RaceService.endRace("finished")
	elseif t - race.goAt > R.MaxRaceTime then
		RaceService.endRace("time")
	end
end

-- Portal pad: standing on it readies you up.
local function portalCheck()
	if not world or not world.lobby then
		return
	end
	local portal = world.lobby.portalPosition
	for _, player in ipairs(Players:GetPlayers()) do
		if not queue[player] then
			local root = characterRoot(player)
			if root and not root.Anchored then
				local d = root.CFrame.Position - portal
				if Vector3.new(d.X, 0, d.Z).Magnitude <= world.lobby.portalRadius and math.abs(d.Y) < 12 then
					RaceService.setReady(player, true)
					services.Remotes.Notify:FireClient(player, "You're in the queue! The race starts when everyone's ready.", "good")
				end
			end
		end
	end
end

local stateAcc = 0
function RaceService.step(dt)
	if phase == "Lobby" then
		portalCheck()
		RaceService.tryStart()
		stateAcc += dt
		if stateAcc >= 1 and firstReadyAt then
			stateAcc = 0
			RaceService.broadcastState()
		end
		return
	end
	if phase == "Results" then
		if now() >= (resultsUntil or 0) then
			RaceService.backToLobby()
		end
		return
	end
	-- Countdown / Racing
	if phase == "Countdown" and now() >= race.goAt then
		phase = "Racing"
		race.startedAt = race.goAt
		if services.EventDirector then
			services.EventDirector.onRaceStart(race)
		end
		RaceService.broadcastState()
	end
	if services.BotService then
		services.BotService.step(dt)
	end
	race.rankAcc += dt
	if race.rankAcc >= 0.1 then
		race.rankAcc = 0
		rank()
	end
	if phase == "Racing" then
		if services.EventDirector then
			services.EventDirector.step(dt)
		end
		if race then
			checkEnd()
		end
	end
	if race and services.KartService then
		services.KartService.step(dt)
	end
end

function RaceService.onPlayerAdded(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if RaceService.racerOf(player) then
				park(player)
			end
		end)
	end)
	if phase ~= "Lobby" and R.SpectatorsJoinNext then
		-- late joiner: spectate this race, race the next one
		RaceService.setReady(player, true)
		services.Remotes.Notify:FireClient(player, "A race is on - you're spectating and queued for the next one.", "info")
	end
	RaceService.sendState(player)
end

function RaceService.onPlayerRemoving(player)
	queue[player] = nil
	local i = table.find(queueOrder, player)
	if i then
		table.remove(queueOrder, i)
	end
	respawnLimit[player] = nil
	readyLimit:forget(player)
	local racer = race and race.byPlayer[player]
	if racer then
		racer.left = true
		race.byPlayer[player] = nil
		if phase == "Racing" or phase == "Countdown" then
			services.Remotes.Announce:FireAllClients(racer.name .. " left the race.", "info")
			if humans() == 0 then
				RaceService.abort("everyone left")
				return
			end
			rank()
		end
		RaceService.broadcastState()
	end
end

function RaceService.start()
	local remotes = services.Remotes
	remotes.SetReady.OnServerEvent:Connect(function(player, ready)
		if type(ready) ~= "boolean" or not readyLimit:allow(player) then
			return
		end
		RaceService.setReady(player, ready)
	end)
	remotes.Respawn.OnServerEvent:Connect(function(player, reason)
		RaceService.requestRespawn(player, reason)
	end)
	remotes.UseItem.OnServerEvent:Connect(function(player)
		-- Stage 3: power-ups. The key / button is wired; nothing happens yet.
		if readyLimit:allow(player) and RaceService.racerOf(player) then
			remotes.Notify:FireClient(player, "Power-ups arrive in Stage 3!", "info")
		end
	end)
	Players.PlayerAdded:Connect(RaceService.onPlayerAdded)
end

return RaceService
