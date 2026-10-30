--[[
	RoundService - the round loop, and the one Heartbeat step that drives everything else.

	  Lobby      on the harbour dock: everyone presses READY and votes a ship (UI buttons or
	             by standing on a vote pad). Votes only count for ships the voter has
	             unlocked; most votes wins, a tie goes to the easier ship. The countdown
	             starts when everyone is ready, or ReadyTimeout after the first ready.
	  Countdown  Round.Countdown seconds; cancelled if nobody is ready any more.
	  Preparing  the voted ship is built (or reused if it is the fresh one at the dock) a
	             few hundred parts per frame - never a long freeze.
	  Running    the crew spawns at the bow of the lowest deck. The ship LURCHES every
	             ~20 s; climb up and aft to the last lifeboat before it launches.
	  Launching  the lifeboat cinematic (timer ran out, or Full Crew aboard early).
	  Results    payouts and the results card, then everyone is back on the dock and a
	             fresh ship is moored.

	A round ALWAYS ends: the lifeboat launches on time (or early), launches empty when
	nobody is left alive or downed, or the round is aborted when every participant left.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Progress = require(Shared.Progress)
local RateLimit = require(script.Parent.RateLimit)

local RoundService = {}

local services
local world
local R = GameConfig.Round

local phase = "Lobby"
local phaseEndsAt = 0
local ready = {}
local votes = {}
local firstReadyAt = nil
local run = nil
local roundCounter = 0
local broadcastTimer = 0
local teamTimer = 0
local prepareFrames = 0
local voteLimit = RateLimit.new(4, 6)
local padNotice = {}

RoundService.lastSummary = nil

function RoundService.init(registry)
	services = registry
end

function RoundService.setWorld(newWorld)
	world = newWorld
end

function RoundService.phase()
	return phase
end

function RoundService.run()
	return run
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function lobbyPlayers()
	local list = services.DataService.loadedPlayers()
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

local function escapesOf(player)
	local data = services.DataService.getProfile(player)
	return data and data.Stats.Escapes or 0
end

function RoundService.tally()
	local list = {}
	for player, key in pairs(votes) do
		list[player] = { ship = key, escapes = escapesOf(player) }
	end
	return Progress.tally(list)
end

function RoundService.participantList()
	local list = {}
	if run then
		for player in pairs(run.players) do
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function RoundService.state()
	local now = os.clock()
	local winner, counts = RoundService.tally()
	local readyIds, voteIds = {}, {}
	local n = 0
	for player in pairs(ready) do
		readyIds[tostring(player.UserId)] = true
		n += 1
	end
	for player, key in pairs(votes) do
		voteIds[tostring(player.UserId)] = key
	end
	local state = {
		phase = phase,
		timeLeft = math.max(0, math.ceil(phaseEndsAt - now)),
		ready = n,
		players = #lobbyPlayers(),
		readyIds = readyIds,
		voteIds = voteIds,
		votes = counts,
		leading = winner,
		round = roundCounter,
		autoStartIn = if firstReadyAt and phase == "Lobby" then math.max(0, math.ceil(firstReadyAt + R.ReadyTimeout - now)) else nil,
	}
	if run then
		state.ship = run.shipKey
		state.participants = {}
		for player in pairs(run.players) do
			state.participants[tostring(player.UserId)] = true
		end
		if phase == "Running" and run.launchAt then
			state.timeLeft = math.max(0, math.ceil(run.launchAt - now))
		end
		local job = services.ShipService.building()
		state.building = if phase == "Preparing" and job then math.floor(job:progress() * 100) else nil
	end
	return state
end

function RoundService.sendState(player)
	if player then
		services.Remotes.RoundState:FireClient(player, RoundService.state())
	else
		services.Remotes.RoundState:FireAllClients(RoundService.state())
	end
end

function RoundService.team()
	local rows = {}
	if not run then
		return rows
	end
	for player, rec in pairs(run.players) do
		if type(rec) == "table" and player.Parent then
			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				state = rec.state,
				oxygen = if rec.max and rec.max > 0 then math.clamp(rec.oxygen / rec.max, 0, 1) else 1,
				aboard = rec.aboard == true,
				carried = #services.LootService.carried(player),
				vip = player:GetAttribute("LL_VIP") == true,
				revives = rec.revives or 0,
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.userId < b.userId
	end)
	return rows
end

local function setPhase(name, duration)
	phase = name
	phaseEndsAt = os.clock() + (duration or 0)
	workspace:SetAttribute("LL_Phase", name)
	RoundService.sendState()
end

---------------------------------------------------------------------------------------------
-- Lobby: ready + vote
---------------------------------------------------------------------------------------------

function RoundService.setReady(player, value)
	if phase ~= "Lobby" and phase ~= "Countdown" then
		return false
	end
	if not services.DataService.getProfile(player) then
		return false
	end
	if value then
		ready[player] = true
		firstReadyAt = firstReadyAt or os.clock()
	else
		ready[player] = nil
		if next(ready) == nil then
			firstReadyAt = nil
		end
	end
	RoundService.sendState()
	return true
end

function RoundService.vote(player, shipKey)
	if type(shipKey) ~= "string" or not GameConfig.Ships[shipKey] then
		return false, "unknown"
	end
	if phase ~= "Lobby" and phase ~= "Countdown" then
		return false, "phase"
	end
	if not services.DataService.getProfile(player) then
		return false, "loading"
	end
	if not Progress.shipUnlocked(shipKey, escapesOf(player)) then
		return false, "locked"
	end
	if votes[player] ~= shipKey then
		votes[player] = shipKey
		RoundService.sendState()
	end
	return true
end

local function updatePads()
	if not world or not world.votePads then
		return
	end
	local _, counts = RoundService.tally()
	for key, pad in pairs(world.votePads) do
		pad.count.Text = string.format("%d vote%s", counts[key] or 0, if counts[key] == 1 then "" else "s")
	end
end

local function checkPads()
	if not world or not world.votePads then
		return
	end
	for _, player in ipairs(lobbyPlayers()) do
		local root = rootOf(player)
		if root then
			for key, pad in pairs(world.votePads) do
				local d = root.CFrame.Position - pad.position
				if Vector3.new(d.X, 0, d.Z).Magnitude <= R.VotePadRadius and math.abs(d.Y) < 8 and votes[player] ~= key then
					local ok, why = RoundService.vote(player, key)
					if ok then
						services.Remotes.Notify:FireClient(player, "You voted for " .. GameConfig.Ships[key].Name .. ".", "info")
					elseif why == "locked" and (not padNotice[player] or os.clock() - padNotice[player] > 4) then
						padNotice[player] = os.clock()
						services.Remotes.Notify:FireClient(player, string.format("%s unlocks after %d escapes.", GameConfig.Ships[key].Name, GameConfig.Ships[key].UnlockEscapes), "warn")
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Round start / end
---------------------------------------------------------------------------------------------

local function beginPreparing()
	local shipKey = RoundService.tally()
	roundCounter += 1
	run = {
		id = roundCounter,
		shipKey = shipKey,
		def = GameConfig.Ships[shipKey],
		players = {},
	}
	for _, player in ipairs(lobbyPlayers()) do
		if #RoundService.participantList() < GameConfig.MaxPlayers then
			run.players[player] = true
		end
	end
	services.ShipService.request(shipKey)
	prepareFrames = 0
	ready, votes, firstReadyAt = {}, {}, nil
	updatePads()
	setPhase("Preparing", 0)
	services.Remotes.Announce:FireAllClients(string.format("%s - all aboard!", string.upper(run.def.Name)), run.def.Color)
end

local function beginRunning()
	local record = services.ShipService.record()
	for player in pairs(run.players) do
		if not player.Parent then
			run.players[player] = nil
		end
	end
	local list = RoundService.participantList()
	if #list == 0 then
		RoundService.abort()
		return
	end
	run.startAt = os.clock()
	services.SurvivalService.startRun(run)
	services.LootService.startRun(run, record)
	services.ObstacleService.startRun(run, record)
	services.ShipService.startRun(run)
	services.LifeboatService.startRun(run, record)
	for i, player in ipairs(list) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if rootOf(player) and humanoid and humanoid.Health > 0 then
			services.SurvivalService.moveTo(player, services.ShipService.spawnCFrame(i, #list))
		else
			-- still respawning (died on the dock during the countdown): board when the new
			-- character arrives instead of counting that respawn as leaving the round
			local rec = services.SurvivalService.record(player)
			if rec then
				rec.spawnSlot = { i, #list }
			end
		end
	end
	setPhase("Running", run.def.RoundTime)
	services.Remotes.Announce:FireAllClients("The ship is sinking! One boat. GO!", { 255, 120, 100 })
	for _, player in ipairs(list) do
		local data = services.DataService.getProfile(player)
		if data and not data.Tutorial.Done then
			services.Remotes.Notify:FireClient(player, GameConfig.TutorialHints[1], "info")
		end
	end
end

function RoundService.onLaunch()
	if phase == "Running" then
		setPhase("Launching", GameConfig.Lifeboat.CinematicTime)
	end
end

function RoundService.finish()
	if not run or phase == "Results" then
		return
	end
	local now = os.clock()
	local thisRun = run
	local team = RoundService.team()
	local escapedNames = {}
	for _, p in ipairs(thisRun.escaped or {}) do
		table.insert(escapedNames, p.DisplayName)
	end
	local summaries = {}
	for player, rec in pairs(thisRun.players) do
		if type(rec) == "table" and rec.state ~= "Left" and player.Parent then
			local escaped = rec.state == "Escaped"
			local items = services.LootService.take(player)
			local pay = services.RewardService.grantRound(player, {
				escaped = escaped,
				items = items,
				shipKey = thisRun.shipKey,
				fullCrew = thisRun.fullCrew == true,
				revives = rec.revives or 0,
			})
			local result = {
				outcome = if escaped then "Escaped" else "Lost",
				ship = thisRun.shipKey,
				items = if escaped then items else {},
				lostItems = if escaped then {} else items,
				banked = pay.banked,
				coins = pay.coins,
				lines = pay.lines,
				double = escaped and services.ShopService.ownsPass(player, "DoubleLoot"),
				fullCrew = thisRun.fullCrew == true,
				escapedNames = escapedNames,
				team = team,
				goals = services.RewardService.goalsView(player),
				time = math.floor(now - (thisRun.startAt or now)),
				lurches = (services.ShipService.lurchState() or {}).k or 0,
			}
			summaries[player] = result
			services.Remotes.Results:FireClient(player, result)
		end
	end
	RoundService.lastSummary = { ship = thisRun.shipKey, fullCrew = thisRun.fullCrew == true, players = summaries, escaped = #escapedNames }
	services.Remotes.WorldSound:FireAllClients(if #escapedNames > 0 then "Escape" else "LostAtSea", nil)
	setPhase("Results", R.ResultsTime)
end

local function cleanup()
	local list = RoundService.participantList()
	services.LifeboatService.stopRun()
	services.ObstacleService.stopRun()
	services.LootService.stopRun()
	services.SurvivalService.stopRun()
	services.ShipService.cleanup()
	for _, player in ipairs(list) do
		if player.Parent and world then
			services.SurvivalService.moveTo(player, world.spawnCFrame)
			services.PlayerService.applySpeed(player)
		end
	end
	run = nil
	setPhase("Lobby", 0)
end

-- Abort without results (everyone left).
function RoundService.abort()
	cleanup()
end

local function checkRunning()
	local c = services.SurvivalService.counts()
	if c.present == 0 then
		RoundService.abort()
	end
end

-- Anyone not playing this round is kept off the ship (it isn't theirs).
local function guardShip()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and services.ShipService.aboard(root.CFrame.Position) then
			local rec = services.SurvivalService.record(player)
			local playing = rec and (rec.state == "Alive" or rec.state == "Downed" or rec.state == "Escaped")
			if not playing and world then
				services.SurvivalService.moveTo(player, world.spawnCFrame)
				services.Remotes.Notify:FireClient(player, if run then "A round is underway - you'll sail on the next one!" else "Ready up and vote to board a ship!", "info")
			end
		end
	end
end

function RoundService.step(dt)
	local now = os.clock()
	services.ShipService.stepBuild()
	if phase == "Lobby" then
		checkPads()
		local list = lobbyPlayers()
		local readyCount, all = 0, #list > 0
		for _, player in ipairs(list) do
			if ready[player] then
				readyCount += 1
			else
				all = false
			end
		end
		if readyCount > 0 and (all or (firstReadyAt and now - firstReadyAt >= R.ReadyTimeout)) then
			setPhase("Countdown", R.Countdown)
			services.Remotes.WorldSound:FireAllClients("Countdown", nil)
		end
	elseif phase == "Countdown" then
		checkPads()
		if next(ready) == nil then
			setPhase("Lobby", 0)
		elseif now >= phaseEndsAt then
			beginPreparing()
		end
	elseif phase == "Preparing" then
		prepareFrames += 1
		if services.ShipService.ready(run.shipKey) then
			beginRunning()
		elseif prepareFrames > R.MaxPrepareFrames then
			warn("[LastLifeboat] ship took too long to build; aborting the round")
			RoundService.abort()
		end
	elseif phase == "Running" then
		services.ShipService.step(dt)
		services.SurvivalService.step(dt)
		services.ObstacleService.step(dt)
		services.LifeboatService.step(dt)
		if run and phase == "Running" then
			checkRunning()
		end
	elseif phase == "Launching" then
		services.LifeboatService.step(dt)
		if run and phase == "Launching" then
			checkRunning()
		end
	elseif phase == "Results" then
		if now >= phaseEndsAt then
			cleanup()
		end
	end
	if world then
		guardShip()
	end
	broadcastTimer += dt
	if broadcastTimer >= 1 then
		broadcastTimer = 0
		updatePads()
		RoundService.sendState()
	end
	if run and phase == "Running" then
		teamTimer += dt
		if teamTimer >= 0.5 then
			teamTimer = 0
			services.Remotes.Team:FireAllClients(RoundService.team())
		end
	end
end

function RoundService.onProfileLoaded(player)
	RoundService.sendState(player)
end

function RoundService.onPlayerRemoving(player)
	ready[player] = nil
	votes[player] = nil
	padNotice[player] = nil
	voteLimit:forget(player)
	if next(ready) == nil then
		firstReadyAt = nil
	end
	if run and run.players[player] then
		if type(run.players[player]) == "table" then
			services.LootService.clear(player)
			services.SurvivalService.release(player)
		else
			run.players[player] = nil -- left while the ship was being built
		end
	end
end

-- A participant's character died (reset, fell out of the world): out for this round.
function RoundService.onCharacterDied(player, character)
	local rec = services.SurvivalService.record(player)
	if player.Character == character and rec and (rec.state == "Alive" or rec.state == "Downed") then
		services.SurvivalService.out(player, "died")
	end
end

-- A participant respawned mid-round: they're out (spectating from the dock). One who had
-- no character when the round started boards now instead.
function RoundService.onCharacterAdded(player, character)
	local rec = services.SurvivalService.record(player)
	if rec and rec.spawnSlot and rec.state == "Alive" then
		local slot = rec.spawnSlot
		rec.spawnSlot = nil
		task.defer(function()
			if player.Character == character and run and phase == "Running" and services.ShipService.record() then
				services.SurvivalService.moveTo(player, services.ShipService.spawnCFrame(slot[1], slot[2]))
			end
		end)
		return
	end
	if rec and (rec.state == "Alive" or rec.state == "Downed") then
		services.SurvivalService.out(player, "respawned")
	end
end

function RoundService.start()
	local remotes = services.Remotes
	remotes.SetReady.OnServerEvent:Connect(function(player, value)
		if voteLimit:allow(player) then
			RoundService.setReady(player, value == true)
		end
	end)
	remotes.Vote.OnServerEvent:Connect(function(player, shipKey)
		if voteLimit:allow(player) then
			local ok, why = RoundService.vote(player, shipKey)
			if not ok and why == "locked" then
				local def = GameConfig.Ships[shipKey]
				remotes.Notify:FireClient(player, string.format("%s unlocks after %d escapes.", def.Name, def.UnlockEscapes), "warn")
			end
		end
	end)
	workspace:SetAttribute("LL_Phase", phase)
end

return RoundService
