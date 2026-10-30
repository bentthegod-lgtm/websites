--[[
	RoundService - the round loop, and the one Heartbeat step that drives everything else.

	  Lobby      players ready up and vote a difficulty. When everyone is ready (or
	             ReadyTimeout after the first ready) the countdown starts.
	  Countdown  Round.Countdown seconds; cancelled if nobody is ready any more.
	  Preparing  a new lake is generated from a fresh seed and built a few tiles per frame
	             (LakeBuilder job - never a long freeze). Everyone is gathered on the dock.
	  Running    survive, chip out the cores, carry them to the beacon. The Antlered wakes
	             after the difficulty's grace period. Ends early if nobody is left standing.
	  Sled       every core is in: the sled leaves in Round.SledWait seconds. Reach it to
	             escape; thaw frozen friends first if you can.
	  Results    rewards are paid, everyone gets their card, the lake is cleared.

	A round ALWAYS ends: on success (sled), when everyone is frozen / lost, when the time
	limit runs out, or when every participant has left.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local LakeGen = require(Shared.LakeGen)
local RateLimit = require(script.Parent.RateLimit)

local RoundService = {}

local services
local world
local LakeBuilder
local R = GameConfig.Round
local L = GameConfig.Lake

local phase = "Lobby"
local phaseEndsAt = 0
local ready = {}
local votes = {}
local firstReadyAt = nil
local run = nil
local job = nil
local roundCounter = 0
local broadcastTimer = 0
local teamTimer = 0
local voteLimit = RateLimit.new(4, 6)
local seedRng = Random.new()

RoundService.lastSummary = nil

function RoundService.init(registry)
	services = registry
	LakeBuilder = require(script.Parent.Parent.World.LakeBuilder)
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

function RoundService.job()
	return job
end

local function flat(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function lobbyPlayers()
	local list = {}
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		table.insert(list, player)
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

-- Most votes wins; ties go to the easier difficulty. No votes = Normal.
function RoundService.tally()
	local counts = {}
	for _, name in ipairs(GameConfig.DifficultyOrder) do
		counts[name] = 0
	end
	local any = false
	for _, choice in pairs(votes) do
		counts[choice] += 1
		any = true
	end
	if not any then
		return "Normal", counts
	end
	local best, bestN = nil, -1
	for _, name in ipairs(GameConfig.DifficultyOrder) do
		if counts[name] > bestN then
			best, bestN = name, counts[name]
		end
	end
	return best, counts
end

function RoundService.state()
	local now = os.clock()
	local _, counts = RoundService.tally()
	local readyIds = {}
	local n = 0
	for player in pairs(ready) do
		readyIds[tostring(player.UserId)] = true
		n += 1
	end
	local state = {
		phase = phase,
		timeLeft = math.max(0, math.ceil(phaseEndsAt - now)),
		ready = n,
		players = #lobbyPlayers(),
		readyIds = readyIds,
		votes = counts,
		round = roundCounter,
		autoStartIn = if firstReadyAt and phase == "Lobby" then math.max(0, math.ceil(firstReadyAt + R.ReadyTimeout - now)) else nil,
		gust = services.WeatherService and services.WeatherService.gusting() or false,
	}
	if run then
		state.difficulty = run.difficulty
		state.delivered = run.delivered or 0
		state.total = run.total or 0
		state.timeLeft = math.max(0, math.ceil((if phase == "Sled" then run.sledLeavesAt elseif phase == "Running" then run.endsAt else phaseEndsAt) - now))
		state.building = if job and not job.done then math.floor(100 * (job.index - 1) / #run.layout.order) else nil
		local mine = {}
		for player in pairs(run.players) do
			mine[tostring(player.UserId)] = true
		end
		state.participants = mine
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
		table.insert(rows, {
			userId = player.UserId,
			name = player.DisplayName,
			state = if rec.inWater and rec.state == "Active" then "Water" else rec.state,
			warmth = math.floor((rec.warmth or 0) + 0.5),
			carrying = rec.carrying ~= nil,
			vip = player:GetAttribute("TI_VIP") == true,
		})
	end
	table.sort(rows, function(a, b)
		return a.userId < b.userId
	end)
	return rows
end

local function setPhase(name, duration)
	phase = name
	phaseEndsAt = os.clock() + (duration or 0)
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

function RoundService.vote(player, difficulty)
	if type(difficulty) ~= "string" or not GameConfig.Difficulties[difficulty] then
		return false
	end
	if phase ~= "Lobby" and phase ~= "Countdown" then
		return false
	end
	votes[player] = difficulty
	RoundService.sendState()
	return true
end

---------------------------------------------------------------------------------------------
-- Round start / end
---------------------------------------------------------------------------------------------

local function gatherPoint(i, count)
	local spread = math.min(18, (count - 1) * 3)
	local x = -spread / 2 + (if count > 1 then (i - 1) * spread / (count - 1) else 0)
	return CFrame.new(x, GameConfig.Lobby.GroundTop + 3.5, L.ShoreZ - 5)
end

local function beginPreparing()
	local difficulty = RoundService.tally()
	roundCounter += 1
	local seed = seedRng:NextInteger(1, 2 ^ 30)
	local layout = LakeGen.generate(seed, difficulty)
	local folder = Instance.new("Folder")
	folder.Name = "Round" .. roundCounter
	folder.Parent = world.lakeFolder
	run = {
		id = roundCounter,
		seed = seed,
		difficulty = difficulty,
		diff = GameConfig.Difficulties[difficulty],
		layout = layout,
		folder = folder,
		players = {},
		delivered = 0,
		total = #layout.cores,
		buildStarted = os.clock(),
	}
	for _, player in ipairs(lobbyPlayers()) do
		if #RoundService.participantList() < GameConfig.MaxPlayers then
			run.players[player] = true
		end
	end
	job = LakeBuilder.new(layout, folder)
	ready, votes, firstReadyAt = {}, {}, nil
	setPhase("Preparing", 0)
	services.Remotes.Announce:FireAllClients(difficulty:upper() .. " - the ice is forming...", GameConfig.Difficulties[difficulty].Color)
end

function RoundService.participantList()
	local list = {}
	if run then
		for player in pairs(run.players) do
			table.insert(list, player)
		end
	end
	return list
end

local function beginRunning()
	local now = os.clock()
	run.buildTime = now - run.buildStarted
	run.startAt = now
	run.endsAt = now + run.diff.TimeLimit
	run.wakeAt = now + run.diff.Grace
	-- Drop anyone who left while the lake was forming.
	for player in pairs(run.players) do
		if not player.Parent then
			run.players[player] = nil
		end
	end
	local list = RoundService.participantList()
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	for i, player in ipairs(list) do
		services.SurvivalService.moveTo(player, gatherPoint(i, #list))
	end
	services.SurvivalService.startRun(run)
	services.IceService.startRun(run)
	services.ObjectiveService.startRun(run)
	services.MonsterService.startRun(run)
	services.WeatherService.startRun(run)
	setPhase("Running", run.diff.TimeLimit)
	services.Remotes.Announce:FireAllClients(string.format("Find %d frozen cores. Walk softly...", run.total), { 230, 240, 255 })
	for _, player in ipairs(list) do
		services.Remotes.Notify:FireClient(player, "Hold C to sneak (quiet), Shift to sprint (loud). Thin ice is dark - it cracks fast.", "info")
	end
end

function RoundService.allCoresIn()
	if phase ~= "Running" then
		return
	end
	run.sledLeavesAt = os.clock() + R.SledWait
	setPhase("Sled", R.SledWait)
	services.Remotes.Announce:FireAllClients("ALL CORES IN! Get to the sled - it leaves soon!", { 255, 220, 120 })
end

local function finish(outcome, reason)
	if not run then
		return
	end
	local now = os.clock()
	local thisRun = run
	services.WeatherService.stopRun()
	local team = RoundService.team()
	local summaries = {}
	for player, rec in pairs(thisRun.players) do
		if type(rec) == "table" and rec.state ~= "Left" and player.Parent then
			local escaped = rec.state == "Escaped"
			local summary = {
				escaped = escaped,
				cores = rec.cores or 0,
				rescues = rec.rescues or 0,
				survived = rec.state ~= "Lost",
				difficulty = thisRun.difficulty,
				vip = services.ShopService.ownsPass(player, "VIP"),
			}
			local reward, newLevel = services.RewardService.grantRound(player, summary)
			local result = {
				outcome = if escaped then "Escaped" elseif outcome == "Success" then "LeftBehind" else "Failed",
				reason = reason,
				difficulty = thisRun.difficulty,
				delivered = thisRun.delivered,
				total = thisRun.total,
				time = math.floor(now - (thisRun.startAt or now)),
				coins = reward.coins,
				xp = reward.xp,
				lines = reward.lines,
				level = newLevel,
				team = team,
			}
			summaries[player] = result
			services.Remotes.Results:FireClient(player, result)
		end
	end
	RoundService.lastSummary = { outcome = outcome, reason = reason, players = summaries }
	services.Remotes.Announce:FireAllClients(reason, if outcome == "Success" then { 140, 255, 170 } else { 255, 140, 140 })
	setPhase("Results", R.ResultsTime)
end

local function cleanup()
	services.SurvivalService.stopRun()
	services.ObjectiveService.stopRun()
	services.MonsterService.stopRun()
	services.IceService.stopRun()
	services.WeatherService.stopRun()
	if run and run.folder then
		run.folder:Destroy()
	end
	if run then
		for player in pairs(run.players) do
			if player.Parent and world then
				services.SurvivalService.moveTo(player, world.spawnCFrame)
			end
		end
	end
	run, job = nil, nil
	setPhase("Lobby", 0)
end

-- Abort without results (everyone left).
local function abort()
	services.WeatherService.stopRun()
	cleanup()
end

local function checkRunning(now)
	local active, frozen, escaped, present = 0, 0, 0, 0
	for _, rec in pairs(run.players) do
		if type(rec) == "table" then
			if rec.state ~= "Left" then
				present += 1
			end
			if rec.state == "Active" then
				active += 1
			elseif rec.state == "Frozen" then
				frozen += 1
			elseif rec.state == "Escaped" then
				escaped += 1
			end
		end
	end
	if present == 0 then
		abort()
		return
	end
	if phase == "Sled" then
		if active == 0 then
			if escaped > 0 then
				finish("Success", "The sled made it out! You escaped the lake.")
			else
				finish("Fail", "Everyone froze on the ice.")
			end
		elseif now >= run.sledLeavesAt then
			finish(if escaped > 0 then "Success" else "Fail", if escaped > 0 then "The sled left - those aboard escaped!" else "The sled left without anyone...")
		end
		return
	end
	if active == 0 then
		finish("Fail", "Everyone froze on the ice.")
	elseif now >= run.endsAt then
		finish("Fail", "The night got too cold. The ice won this time.")
	end
end

-- Anyone not playing this round is kept off the lake (it isn't theirs - or doesn't exist).
local function guardShore()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and root.Position.Z > L.ShoreZ + 1 then
			local rec = services.SurvivalService.record(player)
			if not rec or (rec.state ~= "Active" and rec.state ~= "Frozen") then
				services.SurvivalService.moveTo(player, world.spawnCFrame)
				services.Remotes.Notify:FireClient(player, if run then "This round is underway - you'll play the next one!" else "The ice isn't safe yet - ready up to play.", "info")
			end
		end
	end
end

function RoundService.step(dt)
	local now = os.clock()
	if phase == "Lobby" then
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
		if next(ready) == nil then
			setPhase("Lobby", 0)
		elseif now >= phaseEndsAt then
			beginPreparing()
		end
	elseif phase == "Preparing" then
		if job:step(L.TilesPerStep) then
			beginRunning()
		end
	elseif phase == "Running" or phase == "Sled" then
		services.SurvivalService.step(dt)
		services.IceService.step(dt)
		services.ObjectiveService.step(dt)
		services.MonsterService.step(dt)
		services.WeatherService.step(dt)
		if phase == "Sled" and world then
			for player, rec in pairs(run.players) do
				local root = rootOf(player)
				if type(rec) == "table" and rec.state == "Active" and root and flat(root.Position, world.sled.position) <= R.SledRadius then
					services.SurvivalService.escape(player)
					services.Remotes.Notify:FireClient(player, "You're on the sled! Safe!", "good")
				end
			end
		end
		if run then
			checkRunning(now)
		end
	elseif phase == "Results" then
		if now >= phaseEndsAt then
			cleanup()
		end
	end
	if world then
		guardShore()
	end
	broadcastTimer += dt
	if broadcastTimer >= 1 then
		broadcastTimer = 0
		RoundService.sendState()
	end
	if run and (phase == "Running" or phase == "Sled") then
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
	voteLimit:forget(player)
	if next(ready) == nil then
		firstReadyAt = nil
	end
	if run and run.players[player] then
		if services.ObjectiveService then
			services.ObjectiveService.drop(player)
		end
		if type(run.players[player]) == "table" then
			services.SurvivalService.release(player)
		else
			run.players[player] = nil -- left while the lake was forming
		end
	end
end

-- A participant's character respawned mid-round (reset): they are lost for this round.
function RoundService.onCharacterAdded(player)
	local rec = run and run.players[player]
	if type(rec) == "table" and (rec.state == "Active" or rec.state == "Frozen") then
		services.ObjectiveService.drop(player)
		services.SurvivalService.release(player)
		rec.state = "Lost"
		player:SetAttribute("TI_State", "Lost")
	end
end

function RoundService.start()
	local remotes = services.Remotes
	remotes.SetReady.OnServerEvent:Connect(function(player, value)
		if voteLimit:allow(player) then
			RoundService.setReady(player, value == true)
		end
	end)
	remotes.Vote.OnServerEvent:Connect(function(player, difficulty)
		if voteLimit:allow(player) then
			RoundService.vote(player, difficulty)
		end
	end)
end

return RoundService
