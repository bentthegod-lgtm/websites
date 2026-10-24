--[[
	RoundService - the game loop.

	Lobby -> (everyone ready, countdown) -> Starting (generate facility) -> Playing
	-> Results -> Lobby.

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
local ready = {}
local padReady = {} -- players currently standing on the lobby ready pad
local lastRecord = "No descents yet."
local difficultyName = DifficultyConfig.Default
local hostUserId
local streak = 0
local runCounter = 0
local currentRun
local countdownEndsAt

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
-- Party / state broadcast
---------------------------------------------------------------------------------------------

local function ensureHost()
	if hostUserId and Players:GetPlayerByUserId(hostUserId) then
		return
	end
	local first = Players:GetPlayers()[1]
	hostUserId = first and first.UserId
end

function RoundService.broadcastParty()
	ensureHost()
	local members = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = services.DataService.getProfile(player)
		table.insert(members, {
			userId = player.UserId,
			name = player.DisplayName,
			ready = ready[player] == true or padReady[player] == true,
			status = player:GetAttribute("DA_Status") or "Lobby",
			level = profile and services.DataService.levelFor(profile.Xp) or 1,
			host = player.UserId == hostUserId,
		})
	end
	RoundService.updateLobbyBoards(members)
	services.Remotes.Party:FireAllClients({
		members = members,
		difficulty = difficultyName,
		pressure = math.min(streak, DifficultyConfig.Pressure.MaxStacks),
		countdown = countdownEndsAt and math.max(0, countdownEndsAt - os.clock()) or nil,
		state = state,
	})
end

-- Physical boards in the lobby mirror the party state.
function RoundService.updateLobbyBoards(members)
	if not lobby then
		return
	end
	local readyCount = 0
	for _, m in ipairs(members) do
		if m.ready then
			readyCount += 1
		end
	end
	local text
	if state == "Lobby" and countdownEndsAt then
		text = string.format("DESCENDING IN %d\nAll %d staff ready.", math.ceil(math.max(0, countdownEndsAt - os.clock())), #members)
	elseif state == "Lobby" then
		text = string.format("%d / %d READY\nStand on the pad or press READY.\nDifficulty: %s", readyCount, #members, difficultyName)
	elseif state == "Results" then
		text = "Run complete.\nDebriefing..."
	else
		text = "RUN IN PROGRESS\nNew arrivals join the next descent."
	end
	lobby:setStatus(text)
	lobby:setRecord(lastRecord)
	lobby.beacon.Color = if state == "Lobby" and not countdownEndsAt then Color3.fromRGB(80, 20, 16) else Color3.fromRGB(255, 70, 40)
end

-- Tracks who is standing on the ready pad. Returns true when that changed.
local function updatePad()
	if not lobby then
		return false
	end
	local changed = false
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local s = services.PlayerService.get(player)
		local on = root ~= nil and s ~= nil and not s.inRound and lobby:isOnPad(root.Position)
		if (padReady[player] == true) ~= on then
			padReady[player] = on or nil
			changed = true
		end
	end
	return changed
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

local function participants()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local s = services.PlayerService.get(player)
		if s then
			table.insert(list, player)
		end
	end
	return list
end

local function startRun()
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
	services.ObjectiveService.begin(map, chainDef, rng, difficulty, overrides)

	-- Spawn everyone in parallel, and wait for all characters before the end-of-run check
	-- can run (otherwise a slow load would look like "nobody alive").
	local pending = 0
	for i, player in ipairs(participants()) do
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
			end
			pending -= 1
		end)
	end
	table.clear(ready)
	table.clear(padReady)
	local waitStarted = os.clock()
	while pending > 0 and os.clock() - waitStarted < 15 do
		task.wait(0.1)
	end
	task.wait(0.5)

	setState("Playing", currentRun.publicInfo)
	services.Remotes.Notify:FireAllClients(chainDef.Steps[1].Text, "objective")

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
		table.insert(results.players, {
			name = s.player.DisplayName,
			userId = s.player.UserId,
			status = s.status,
			cause = s.deathCause,
			items = summary.items,
			revives = summary.revives,
		})
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

	setState("Results", { outcome = results.outcome })
	for _, player in ipairs(Players:GetPlayers()) do
		local personal = table.clone(results)
		personal.xp = breakdowns[player]
		services.Remotes.Results:FireClient(player, personal)
		services.DataService.sendProfile(player)
	end

	task.wait(14)
	cleanupRun()
	currentRun = nil
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(services.PlayerService.sendToLobby, player, lobby.spawnCFrame)
	end
	task.wait(1)
	setState("Lobby", {})
end

local function allReady()
	local players = Players:GetPlayers()
	if #players == 0 then
		return false
	end
	for _, player in ipairs(players) do
		if not ready[player] and not padReady[player] then
			return false
		end
	end
	return true
end

local function loop()
	while true do
		if state == "Lobby" then
			if updatePad() then
				RoundService.broadcastParty()
			end
			if allReady() then
				countdownEndsAt = os.clock() + 5
				RoundService.broadcastParty()
				local cancelled = false
				while os.clock() < countdownEndsAt do
					task.wait(0.25)
					if updatePad() then
						RoundService.broadcastParty()
					end
					RoundService.updateLobbyBoards({})
					if not allReady() then
						cancelled = true
						break
					end
				end
				countdownEndsAt = nil
				if cancelled then
					RoundService.broadcastParty()
				else
					local ok, err = pcall(startRun)
					if not ok then
						warn("[DeadAir] Failed to start run: " .. tostring(err))
						cleanupRun()
						currentRun = nil
						setState("Lobby", { error = "Run failed to start." })
					end
				end
			end
			task.wait(0.25)
		elseif state == "Playing" then
			task.wait(0.5)
			if currentRun and runIsOver() then
				finishRun()
			end
		else
			task.wait(0.25)
		end
	end
end

function RoundService.start()
	lobby = LobbyBuilder.build()
	lobby:wirePracticeLocker(services.PlayerService)
	local remotes = services.Remotes

	remotes.SetReady.OnServerEvent:Connect(function(player, value)
		if type(value) ~= "boolean" or state ~= "Lobby" then
			return
		end
		ready[player] = value or nil
		RoundService.broadcastParty()
	end)
	remotes.SetDifficulty.OnServerEvent:Connect(function(player, name)
		if state ~= "Lobby" or player.UserId ~= hostUserId or type(name) ~= "string" then
			return
		end
		if DifficultyConfig.Presets[name] then
			difficultyName = name
			RoundService.broadcastParty()
		end
	end)
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
		ensureHost()
		task.spawn(function()
			-- Wait for PlayerService to register the player before spawning.
			local tries = 0
			while not services.PlayerService.get(player) and tries < 50 do
				task.wait(0.1)
				tries += 1
			end
			services.PlayerService.sendToLobby(player, lobby.spawnCFrame)
			if state ~= "Lobby" then
				services.PlayerService.setSpectating(player)
				services.Remotes.Notify:FireClient(player, "A run is in progress. You'll join the next one.", "info")
			end
			sendStateTo(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		padReady[player] = nil
		if lobby and lobby.releasePractice then
			lobby.releasePractice(player)
		end
		lastRequest[player] = nil
		if player.UserId == hostUserId then
			hostUserId = nil
		end
		task.defer(RoundService.broadcastParty)
	end)

	task.spawn(loop)
end

return RoundService
