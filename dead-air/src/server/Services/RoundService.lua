--[[
	RoundService - the game loop.

	A party (from a lobby elevator, see PartyService) -> Starting (generate facility) ->
	Playing -> Results -> back to the lobby. Only the party's players take part; anyone
	else stays in the lobby. On a reserved run server the party arrives by teleport and is
	teleported back to a public lobby afterwards.

	A run does not end on a timer. It ends when no player is left standing in the facility:
	everyone has escaped, died, or is downed with nobody left to revive them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MapConfig = require(Shared.Config.MapConfig)
local DifficultyConfig = require(Shared.Config.DifficultyConfig)
local ObjectiveConfig = require(Shared.Config.ObjectiveConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local MazeGen = require(Shared.MazeGen)
local ObjectiveChain = require(Shared.ObjectiveChain)
local Rng = require(Shared.Rng)
local MapBuilder = require(script.Parent.MapBuilder)
local LobbyBuilder = require(script.Parent.LobbyBuilder)

local RoundService = {}

local services
local lobby
local state = "Lobby"
local lastRecord = "No descents yet."
local difficultyName = DifficultyConfig.Default
local streak = 0
local runCounter = 0
local currentRun

function RoundService.init(registry)
	services = registry
	-- Validate chain definitions once at startup so mistakes surface immediately.
	for name, def in pairs(ObjectiveConfig.Chains) do
		local ok, reason = ObjectiveChain.validateDef(def, ItemConfig)
		if not ok then
			error("[DeadAir] Invalid objective chain " .. name .. ": " .. reason)
		end
	end
end

function RoundService.state()
	return state
end

-- Current difficulty preset with server "pressure" (consecutive escapes) applied.
function RoundService.difficulty()
	local preset = DifficultyConfig.Presets[difficultyName] or DifficultyConfig.Presets.Normal
	local stacks = math.min(streak, DifficultyConfig.Pressure.MaxStacks)
	local pressure = 1 + stacks * DifficultyConfig.Pressure.PerEscape
	local result = table.clone(preset)
	result.Name = difficultyName
	result.Pressure = stacks
	result.MonsterSpeed = preset.MonsterSpeed * pressure
	result.Hearing = preset.Hearing * pressure
	result.Sight = preset.Sight * pressure
	return result
end

local function monsterMods(difficulty)
	return {
		speed = difficulty.MonsterSpeed,
		hearing = difficulty.Hearing,
		sight = difficulty.Sight,
		searchTime = difficulty.SearchTime,
		recoverTime = difficulty.RecoverTime,
	}
end

---------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------

function RoundService.isBusy()
	return currentRun ~= nil or state ~= "Lobby"
end

-- Players taking part in the current run (nil when no run is in progress).
function RoundService.currentParty()
	return currentRun and currentRun.party
end

function RoundService.pressure()
	return math.min(streak, DifficultyConfig.Pressure.MaxStacks)
end

-- Kept for callers that refresh lobby/HUD party state.
function RoundService.broadcastParty()
	services.PartyService.broadcast()
end

local function updateRecordBoard()
	if lobby then
		lobby:setRecord(lastRecord)
	end
end

local function setState(newState, data)
	state = newState
	services.Remotes.RoundState:FireAllClients(newState, data or {})
	RoundService.broadcastParty()
end

local function sendStateTo(player)
	local data = {}
	if currentRun then
		data = currentRun.publicInfo
	end
	services.Remotes.RoundState:FireClient(player, state, data)
	services.DataService.sendProfile(player)
	services.ObjectiveService.broadcast()
	RoundService.broadcastParty()
end

---------------------------------------------------------------------------------------------
-- Run lifecycle
---------------------------------------------------------------------------------------------

local function cleanupRun()
	services.MonsterService.despawn()
	services.HorrorEventService.stop()
	services.ObjectiveService.stop()
	services.ItemService.clear()
	services.DoorService.clear()
	services.HidingService.clear()
	services.NoiseService.setMap(nil)
	if currentRun and currentRun.map then
		currentRun.map:destroy()
	end
end

local function startRun(party)
	runCounter += 1
	local seed = (os.time() * 1000 + runCounter * 7919) % 2147483646 + 1
	local rng = Rng.new(seed)
	local difficulty = RoundService.difficulty()

	setState("Starting", { seed = seed })

	local chainWeights = {}
	for name, def in pairs(ObjectiveConfig.Chains) do
		chainWeights[name] = def.Weight
	end
	local chainName = rng:weighted(chainWeights)
	local chainDef = ObjectiveConfig.Chains[chainName]

	local overrides = {}
	local fuseCount = 3
	for _, step in ipairs(chainDef.Steps) do
		if step.Type == "deposit" and step.Item == "Fuse" then
			fuseCount = rng:integer(3, 4)
			overrides[step.Id] = fuseCount
		end
	end

	local layout = MazeGen.generate(MapConfig, rng)
	local runLabel = string.format("RUN %05d", seed % 100000)
	local ok, mapOrErr = pcall(MapBuilder.build, layout, chainDef, rng, { fuseCount = fuseCount, runLabel = runLabel })
	if not ok then
		warn("[DeadAir] Map build failed: " .. tostring(mapOrErr))
		setState("Lobby", { error = "The facility failed to load. Try again." })
		return
	end
	local map = mapOrErr

	currentRun = {
		party = party,
		seed = seed,
		map = map,
		chainName = chainName,
		chainDef = chainDef,
		difficulty = difficulty,
		startedAt = os.clock(),
		alive = true,
		publicInfo = {
			seed = seed,
			title = chainDef.Title,
			difficulty = difficulty.Name,
			pressure = difficulty.Pressure,
			runLabel = runLabel,
		},
	}

	services.ItemService.setFolder(map.itemsFolder)
	services.NoiseService.setMap(map)
	services.DoorService.createFromMap(map)
	services.HidingService.createFromMap(map)
	services.ItemService.setupContainers(map)
	services.ObjectiveService.begin(map, chainDef, rng, difficulty, overrides)

	-- Spawn everyone in parallel, and wait for all characters before the end-of-run check
	-- can run (otherwise a slow load would look like "nobody alive").
	local pending = 0
	for i, player in ipairs(party) do
		local spawn = map.startSpawns[((i - 1) % #map.startSpawns) + 1]
		pending += 1
		task.spawn(function()
			if lobby.releasePractice then
				lobby.releasePractice(player)
			end
			local ok, spawned = pcall(services.PlayerService.prepareForRound, player, spawn)
			if ok and spawned then
				-- Everyone starts with one lure, so nobody is defenceless.
				services.ItemService.give(player, ObjectiveConfig.StartingItem)
				-- Robux boosts the player switched on for this run.
				local boosts = services.ShopService.consumeForRun(player)
				if #boosts > 0 then
					services.PlayerService.applyBoosts(player, boosts)
					services.Remotes.Notify:FireClient(player, "Boosts active: " .. table.concat(boosts, ", "), "info")
				end
			end
			pending -= 1
		end)
	end
	local waitStarted = os.clock()
	while pending > 0 and os.clock() - waitStarted < 15 do
		task.wait(0.1)
	end
	task.wait(0.5)

	setState("Playing", currentRun.publicInfo)
	for _, player in ipairs(party) do
		services.Remotes.Notify:FireClient(player, chainDef.Steps[1].Text, "objective")
	end

	local runRecord = currentRun
	task.delay(difficulty.MonsterSpawnDelay, function()
		if runRecord.alive and currentRun == runRecord then
			services.MonsterService.spawn(map, monsterMods(difficulty), Rng.new(seed + 1))
			services.Remotes.Notify:FireAllClients("Something else is down here now.", "danger")
		end
	end)
	services.HorrorEventService.start(map, Rng.new(seed + 2))
end

local function runIsOver()
	local alive = services.PlayerService.countStatus("Alive")
	if alive > 0 then
		return false
	end
	for _, s in ipairs(services.PlayerService.inRound()) do
		if s.status == "Downed" and s.selfReviveAt then
			return false -- an Adrenaline Shot is about to get them back up
		end
	end
	-- Nobody standing: downed players cannot be revived.
	for _, s in ipairs(services.PlayerService.inRound()) do
		if s.status == "Downed" then
			services.PlayerService.kill(s.player, "Abandoned")
		end
	end
	return true
end

local function finishRun()
	local run = currentRun
	run.alive = false
	local results = { players = {}, title = run.chainDef.Title, seed = run.seed, difficulty = run.difficulty.Name }
	local escapedAny = false
	local teamSteps = services.ObjectiveService.completedSteps()
	local breakdowns = {}
	for _, s in ipairs(services.PlayerService.inRound()) do
		local escaped = s.status == "Escaped"
		escapedAny = escapedAny or escaped
		local survived = os.clock() - (s.aliveSince or run.startedAt)
		local summary = {
			escaped = escaped,
			died = s.status == "Dead",
			objectives = s.roundStats and s.roundStats.objectives or 0,
			items = s.roundStats and s.roundStats.items or 0,
			revives = s.roundStats and s.roundStats.revives or 0,
			lore = s.roundStats and s.roundStats.lore or 0,
			blackBox = s.roundStats and s.roundStats.blackBox or false,
			survivedSeconds = survived,
			xpMultiplier = run.difficulty.XpMultiplier,
			teamSteps = teamSteps,
		}
		breakdowns[s.player] = services.DataService.awardRun(s.player, summary)
		-- Score for bragging rights between friends.
		local score = math.floor((if escaped then 500 else 0) + summary.objectives * 120 + summary.items * 25 + summary.revives * 100 + summary.lore * 40 + math.min(survived, 900) * 0.5)
		table.insert(results.players, {
			name = s.player.DisplayName,
			userId = s.player.UserId,
			status = s.status,
			cause = s.deathCause,
			items = summary.items,
			revives = summary.revives,
			score = score,
		})
	end
	table.sort(results.players, function(a, b)
		return a.score > b.score
	end)
	if #results.players > 1 then
		results.mvp = results.players[1].name
	end
	results.outcome = if escapedAny then "Escaped" else "Failed"
	results.stepsCompleted = teamSteps
	results.totalSteps = #run.chainDef.Steps
	if escapedAny then
		streak += 1
	else
		streak = 0
	end
	results.pressureNext = math.min(streak, DifficultyConfig.Pressure.MaxStacks)
	local escapedCount = 0
	for _, p in ipairs(results.players) do
		if p.status == "Escaped" then
			escapedCount += 1
		end
	end
	lastRecord = string.format(
		"LAST RUN: %s\n%s - %s\n%d of %d escaped - objectives %d/%d\nEscape streak: %d",
		if escapedAny then "ESCAPED" else "SIGNAL LOST",
		run.chainDef.Title,
		run.difficulty.Name,
		escapedCount,
		#results.players,
		math.min(teamSteps, #run.chainDef.Steps),
		#run.chainDef.Steps,
		streak
	)

	updateRecordBoard()
	setState("Results", { outcome = results.outcome })
	local party = {}
	for _, player in ipairs(run.party) do
		if player.Parent then
			table.insert(party, player)
			local personal = table.clone(results)
			personal.xp = breakdowns[player]
			services.Remotes.Results:FireClient(player, personal)
			services.DataService.sendProfile(player)
		end
	end

	task.wait(14)
	cleanupRun()
	currentRun = nil
	-- A private run server sends its party back to a public lobby; otherwise (Studio or a
	-- failed teleport) everyone returns to this server's lobby.
	if not (services.PartyService.isRunServer() and services.PartyService.returnToLobby(party)) then
		for _, player in ipairs(party) do
			task.spawn(services.PlayerService.sendToLobby, player, lobby.spawnCFrame)
		end
	end
	task.wait(1)
	setState("Lobby", {})
end

-- Starts a run for a party (called by PartyService). Runs in the background.
function RoundService.startRun(party, difficulty)
	if RoundService.isBusy() then
		return false
	end
	difficultyName = if DifficultyConfig.Presets[difficulty] then difficulty else DifficultyConfig.Default
	state = "Starting"
	task.spawn(function()
		local ok, err = pcall(startRun, party)
		if not ok then
			warn("[DeadAir] Failed to start run: " .. tostring(err))
			cleanupRun()
			currentRun = nil
			for _, player in ipairs(party) do
				if player.Parent then
					task.spawn(services.PlayerService.sendToLobby, player, lobby.spawnCFrame)
				end
			end
			setState("Lobby", { error = "Run failed to start." })
		end
	end)
	return true
end

-- Reserved run server: wait for the teleported party, then start their run.
local function runServerFlow()
	local expected, difficulty = nil, DifficultyConfig.Default
	local started = os.clock()
	while os.clock() - started < 25 do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = player:GetJoinData().TeleportData
			if type(data) == "table" and type(data.party) == "table" then
				expected = data.party
				difficulty = data.difficulty
			end
		end
		local present = 0
		for _, userId in ipairs(expected or {}) do
			local player = Players:GetPlayerByUserId(userId)
			if player and services.PlayerService.get(player) and player.Character then
				present += 1
			end
		end
		if expected and present >= #expected then
			break
		end
	end
	local party = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if services.PlayerService.get(player) then
			table.insert(party, player)
		end
	end
	if #party > 0 then
		RoundService.startRun(party, difficulty)
	end
end

local function loop()
	while true do
		task.wait(0.5)
		if state == "Playing" and currentRun and runIsOver() then
			finishRun()
		end
	end
end

function RoundService.start()
	lobby = LobbyBuilder.build()
	lobby:wirePracticeLocker(services.PlayerService)
	local remotes = services.Remotes

	local lastRequest = {}
	remotes.RequestState.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 2 then
			return
		end
		lastRequest[player] = now
		sendStateTo(player)
	end)
	remotes.ExitHide.OnServerEvent:Connect(function(player)
		services.HidingService.exitRemote(player)
	end)

	services.ItemService.LoreRead:Connect(function(player, noteId)
		local s = services.PlayerService.get(player)
		if s and s.roundStats then
			s.roundStats.lore += 1
		end
		if services.DataService.addLore(player, noteId) then
			services.Remotes.Notify:FireClient(player, "New evidence logged", "info")
		end
	end)
	services.PlayerService.StatusChanged:Connect(function()
		RoundService.broadcastParty()
	end)

	local function onPlayerAdded(player)
		task.spawn(function()
			-- Wait for PlayerService to register the player before spawning.
			local tries = 0
			while not services.PlayerService.get(player) and tries < 50 do
				task.wait(0.1)
				tries += 1
			end
			services.PlayerService.sendToLobby(player, lobby.spawnCFrame)
			if RoundService.isBusy() and not services.PartyService.isRunServer() then
				services.Remotes.Notify:FireClient(player, "The elevators are in use. Wait in the lobby for the next descent.", "info")
			end
			sendStateTo(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if lobby and lobby.releasePractice then
			lobby.releasePractice(player)
		end
		lastRequest[player] = nil
	end)

	services.PartyService.start(lobby)
	updateRecordBoard()
	task.spawn(loop)
	if services.PartyService.isRunServer() then
		task.spawn(runServerFlow)
	end
end

return RoundService
