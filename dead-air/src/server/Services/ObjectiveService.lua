--[[
	ObjectiveService - runs the chosen ObjectiveChain in the world.

	* Places objective items (with spares), supplies, lore notes and the optional black box
	  in reachable ordinary rooms (never behind a lock - MazeGen guarantees connectivity).
	* Locks special rooms according to the chain (keycard / power / override).
	* Creates station prompts and validates every interaction server-side: correct step,
	  correct item in the player's inventory, distance, rate limit and (for held actions)
	  real hold time.
	* Runs the extraction: the elevator call triggers a loud repeating alarm the Listener
	  will hear, then the car opens and players who board it escape.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local ObjectiveConfig = require(Shared.Config.ObjectiveConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local LoreConfig = require(Shared.Config.LoreConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local ObjectiveChain = require(Shared.ObjectiveChain)
local MazeGen = require(Shared.MazeGen)
local AudioUtil = require(Shared.AudioUtil)
local Signal = require(Shared.Signal)

local ObjectiveService = {}
ObjectiveService.StepCompleted = Signal.new() -- (step, player)

local services
local run -- current run record

local STATION_LABELS = {
	FuseBox = "Fuse Box",
	Breaker = "Main Breaker",
	Generator = "Generator",
	Terminal = "Security Terminal",
	ExitPanel = "Elevator Call Panel",
}

function ObjectiveService.init(registry)
	services = registry
	services.ItemService.PickedUp:Connect(function(player, kind)
		ObjectiveService.onPickup(player, kind)
	end)
	services.DoorService.LockedInteract:Connect(function(player, door)
		ObjectiveService.onLockedDoor(player, door)
	end)
end

function ObjectiveService.chain()
	return run and run.chain
end

function ObjectiveService.extraction()
	return run and run.extraction
end

function ObjectiveService.broadcast()
	if not run then
		return
	end
	local snapshot = run.chain:snapshot()
	local ex = run.extraction
	if ex then
		snapshot.extraction = { phase = ex.phase, endsAt = ex.endsAt and (ex.endsAt - os.clock()) or nil }
	end
	snapshot.powered = run.map.powered
	services.Remotes.Objective:FireAllClients(snapshot)
end

---------------------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------------------

local function placeItems(map, rng, kind, count, used)
	local cells = MazeGen.pickItemCells(map.layout, rng, count, used, 2)
	for _, cell in ipairs(cells) do
		used[cell.index] = true
		local spot = rng:pick(map.itemSpots[cell.index]) or (map:cellCenter(cell.index) + Vector3.new(6, 0.3, 6))
		services.ItemService.spawn(kind, spot)
	end
	return #cells
end

local function stationPrompt(station)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = STATION_LABELS[station.name] or station.name
	prompt.ActionText = "Inspect"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = station.part
	station.prompt = prompt
	return prompt
end

local function updatePrompts()
	local step = run.chain:current()
	for name, station in pairs(run.map.stations) do
		local prompt = station.prompt
		if prompt then
			prompt.HoldDuration = 0
			prompt.ActionText = "Inspect"
			prompt.Enabled = true
			if step and step.Station == name then
				if step.Type == "deposit" then
					prompt.ActionText = "Insert " .. ItemConfig[step.Item].DisplayName
				elseif step.Type == "activate" then
					prompt.ActionText = "Activate"
				elseif step.Type == "hold" then
					prompt.ActionText = if name == "Generator" then "Crank" else "Run override"
					prompt.HoldDuration = step.Duration
				elseif step.Type == "extract" then
					local ex = run.extraction
					prompt.ActionText = "Call elevator"
					prompt.Enabled = ex == nil
				end
			end
		end
	end
end

function ObjectiveService.begin(map, chainDef, rng, difficulty, overrides)
	ObjectiveService.stop()
	run = {
		map = map,
		def = chainDef,
		rng = rng,
		difficulty = difficulty,
		chain = ObjectiveChain.new(chainDef, overrides),
		holds = {},
		extraction = nil,
		escapedCount = 0,
		alive = true,
	}

	-- Locks
	for room, reason in pairs(chainDef.Locks) do
		local door = services.DoorService.findSpecial(room)
		if door then
			services.DoorService.lock(door, reason)
		else
			warn("[DeadAir] No door for special room " .. room)
		end
	end

	-- Objective items
	local used = {}
	for _, step in ipairs(run.chain.steps) do
		if step.Type == "collect" then
			placeItems(map, rng, step.Item, step.Count or 1, used)
		elseif step.Type == "deposit" then
			placeItems(map, rng, step.Item, (step.Count or 1) + difficulty.ItemSpares, used)
		end
	end

	-- Batteries, then throwables spread across the facility (a separate pass so the
	-- lures are spaced out on their own rather than squeezed between objective items).
	local supplyUsed = {}
	for _ = 1, difficulty.Supplies do
		local kind = rng:weighted(ObjectiveConfig.Supplies)
		placeItems(map, rng, kind, 1, supplyUsed)
	end
	local throwUsed = {}
	for _ = 1, difficulty.Throwables do
		local kind = rng:weighted(ObjectiveConfig.Throwables)
		placeItems(map, rng, kind, 1, throwUsed)
	end

	-- Lore notes, preferring rooms with signs of a struggle.
	local notes = rng:shuffle(table.clone(LoreConfig))
	local noteCells = {}
	for index, cell in ipairs(map.layout.cells) do
		if cell.struggle then
			table.insert(noteCells, index)
		end
	end
	local extra = MazeGen.pickItemCells(map.layout, rng, ObjectiveConfig.LoreNotesPerRun, {}, 1)
	for _, cell in ipairs(extra) do
		table.insert(noteCells, cell.index)
	end
	for i = 1, math.min(ObjectiveConfig.LoreNotesPerRun, #noteCells) do
		local index = noteCells[i]
		local center = map:cellCenter(index)
		services.ItemService.spawnNote(notes[i], center + Vector3.new(rng:range(-3, 3), 0, rng:range(-3, 3)))
	end

	-- Optional black box: deepest dead end that is not a special room.
	if rng:chance(ObjectiveConfig.BlackBoxChance) then
		local best, bestDist = nil, -1
		for index, cell in ipairs(map.layout.cells) do
			if not cell.special and cell.kind ~= "Start" and MazeGen.degree(cell) == 1 and cell.distance > bestDist then
				best, bestDist = index, cell.distance
			end
		end
		if best then
			local spot = map.itemSpots[best][1] or map:cellCenter(best)
			services.ItemService.spawn("BlackBox", spot)
		end
	end

	-- Stations
	for _, station in pairs(map.stations) do
		local prompt = stationPrompt(station)
		prompt.PromptButtonHoldBegan:Connect(function(player)
			ObjectiveService.onHoldBegan(station, player)
		end)
		prompt.PromptButtonHoldEnded:Connect(function(player)
			ObjectiveService.onHoldEnded(station, player)
		end)
		prompt.Triggered:Connect(function(player)
			ObjectiveService.onStation(station, player)
		end)
	end
	updatePrompts()
	ObjectiveService.broadcast()
end

function ObjectiveService.stop()
	if run then
		run.alive = false
		if run.alarmSound then
			run.alarmSound:Destroy()
		end
		if run.generatorSound then
			run.generatorSound:Destroy()
		end
	end
	run = nil
end

---------------------------------------------------------------------------------------------
-- Step completion
---------------------------------------------------------------------------------------------

local function applyEffects(step)
	for _, effect in ipairs(step.Effects or {}) do
		if effect == "PowerOn" then
			run.map:setPower(true)
			services.Remotes.Notify:FireAllClients("Power restored. Everything down here heard that.", "danger")
			local terminal = run.map.stations.Terminal
			if terminal and terminal.labels then
				terminal.labels[2].Text = "OVERRIDE\nREADY"
			end
		elseif effect == "GeneratorRunning" then
			local generator = run.map.stations.Generator
			if generator then
				run.generatorSound = AudioUtil.make(AudioAssets.GeneratorLoop, generator.part, "SFX")
				if run.generatorSound then
					run.generatorSound:Play()
				end
				local thisRun = run
				task.spawn(function()
					-- A running generator keeps producing noise the Listener can hear.
					while thisRun.alive do
						task.wait(6)
						if thisRun.alive then
							services.NoiseService:emit("GeneratorRun", generator.position, { silentAudio = true })
						end
					end
				end)
			end
		end
	end
	for _, room in ipairs(step.Unlocks or {}) do
		local door = services.DoorService.findSpecial(room)
		if door then
			services.DoorService.unlock(door, true)
		end
	end
	if step.Id == "override" then
		local terminal = run.map.stations.Terminal
		if terminal and terminal.labels then
			terminal.labels[2].Text = "EXIT\nUNSEALED"
		end
		services.Remotes.Notify:FireAllClients("Exit unsealed. Find the service elevator.", "info")
	end
end

local function completeStep(step, player)
	applyEffects(step)
	if player then
		local state = services.PlayerService.get(player)
		if state and state.roundStats then
			state.roundStats.objectives += 1
		end
	end
	ObjectiveService.StepCompleted:Fire(step, player)
	updatePrompts()
	ObjectiveService.broadcast()
end

function ObjectiveService.onPickup(player, kind)
	if not run then
		return
	end
	local step = run.chain:current()
	if step and step.Type == "collect" and step.Item == kind then
		local done = run.chain:addProgress(step.Id, 1)
		if done then
			services.Remotes.Notify:FireAllClients(player.DisplayName .. " found the " .. ItemConfig[kind].DisplayName, "info")
			completeStep(done, player)
		else
			ObjectiveService.broadcast()
		end
	end
end

function ObjectiveService.onLockedDoor(player, door)
	if not run then
		return
	end
	local reason = door.lockReason
	local step = run.chain:current()
	if ItemConfig[reason] then
		if services.ItemService.has(player, reason) == 0 then
			services.Remotes.Notify:FireClient(player, "Locked. Requires a " .. ItemConfig[reason].DisplayName .. ".", "warn")
			return
		end
		if step and step.Type == "unlock" and step.Room == door.special then
			services.NoiseService:emit("KeycardSwipe", door.panel.Position, { source = player })
			local done = run.chain:complete(step.Id)
			if done then
				services.DoorService.unlock(door, true)
				completeStep(done, player)
			end
		else
			services.DoorService.unlock(door, true)
		end
	elseif reason == "Power" then
		services.Remotes.Notify:FireClient(player, "The door has no power.", "warn")
	elseif reason == "Override" then
		services.Remotes.Notify:FireClient(player, "Sealed. The override is in the security room.", "warn")
	end
end

---------------------------------------------------------------------------------------------
-- Stations
---------------------------------------------------------------------------------------------

local function noiseFor(step, player, position)
	if step.Noise then
		local crouched = services.PlayerService:isCrouching(player)
		services.NoiseService:emit(step.Noise, position, {
			source = player,
			multiplier = if crouched and step.Type ~= "activate" then 0.75 else 1,
		})
	end
end

function ObjectiveService.onHoldBegan(station, player)
	if not run then
		return
	end
	local step = run.chain:current()
	if not step or step.Type ~= "hold" or step.Station ~= station.name then
		return
	end
	if not services.PlayerService:canInteract(player, station.position) then
		return
	end
	local key = station.name .. ":" .. player.UserId
	local token = {}
	run.holds[key] = { began = os.clock(), token = token }
	local thisRun = run
	task.spawn(function()
		-- Repeated noise while the action is held (cranking, terminal beeps).
		while thisRun.alive and thisRun.holds[key] and thisRun.holds[key].token == token do
			noiseFor(step, player, station.position)
			task.wait(step.NoiseInterval or 1.5)
		end
	end)
end

function ObjectiveService.onHoldEnded(station, player)
	if run then
		run.holds[station.name .. ":" .. player.UserId] = nil
	end
end

function ObjectiveService.onStation(station, player)
	if not run then
		return
	end
	local step = run.chain:current()
	local key = station.name .. ":" .. player.UserId
	local hold = run.holds[key]
	run.holds[key] = nil
	if not services.PlayerService:canInteract(player, station.position) then
		return
	end
	if not step or step.Station ~= station.name then
		local hint = "Nothing to do here yet."
		if station.name == "Terminal" and not run.map.powered then
			hint = "The terminal has no power."
		elseif station.name == "ExitPanel" then
			hint = "The elevator is offline."
		end
		services.Remotes.Notify:FireClient(player, hint, "warn")
		return
	end

	if step.Type == "deposit" then
		if not services.ItemService.take(player, step.Item, 1) then
			services.Remotes.Notify:FireClient(player, "You need a " .. ItemConfig[step.Item].DisplayName .. ".", "warn")
			return
		end
		noiseFor(step, player, station.position)
		local done, progress = run.chain:addProgress(step.Id, 1)
		if station.slots and station.slots[progress] then
			local slot = station.slots[progress]
			slot.Color = Color3.fromRGB(255, 150, 60)
			slot.Material = Enum.Material.Neon
		end
		if station.gaugeLabel then
			station.gaugeLabel.Text = string.format("FUEL %d%%", math.floor(progress / (step.Count or 1) * 100))
		end
		if done then
			completeStep(done, player)
		else
			ObjectiveService.broadcast()
		end
	elseif step.Type == "activate" then
		noiseFor(step, player, station.position)
		if station.lever and station.leverDown then
			TweenService:Create(station.lever, TweenInfo.new(0.25, Enum.EasingStyle.Back), { CFrame = station.leverDown }):Play()
		end
		local done = run.chain:complete(step.Id)
		if done then
			completeStep(done, player)
		end
	elseif step.Type == "hold" then
		-- Enforce the hold duration on the server.
		if not hold or os.clock() - hold.began < step.Duration * 0.85 then
			return
		end
		local done = run.chain:complete(step.Id)
		if done then
			completeStep(done, player)
		end
	elseif step.Type == "extract" then
		ObjectiveService.startExtraction(player, station)
	end
end

---------------------------------------------------------------------------------------------
-- Extraction
---------------------------------------------------------------------------------------------

local function insideZone(zone, position)
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y + 2 and math.abs(localPos.Z) <= half.Z
end

function ObjectiveService.playersInElevator()
	local list = {}
	if not run or not run.map.elevator then
		return list
	end
	local zone = run.map.elevator.zone
	for _, state in ipairs(services.PlayerService.inRound()) do
		if state.status == "Alive" and state.root and state.root.Parent and not state.hiddenIn and insideZone(zone, state.root.Position) then
			table.insert(list, state.player)
		end
	end
	return list
end

local function setElevatorDoors(open)
	local e = run.map.elevator
	local info = TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(e.left, info, { CFrame = if open then e.leftOpen else e.leftClosed }):Play()
	TweenService:Create(e.right, info, { CFrame = if open then e.rightOpen else e.rightClosed }):Play()
	e.left.CanCollide = not open
	e.right.CanCollide = not open
	e.carLight.Material = if open then Enum.Material.Neon else Enum.Material.SmoothPlastic
	e.carLight.Color = if open then Color3.fromRGB(255, 240, 210) else Color3.fromRGB(70, 68, 60)
	local light = e.carLight:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = open
	end
end

function ObjectiveService.startExtraction(player, station)
	if run.extraction then
		return
	end
	local elevator = run.map.elevator
	local thisRun = run
	local ex = { phase = "Calling", endsAt = os.clock() + run.difficulty.ExtractionTime }
	run.extraction = ex
	updatePrompts()
	elevator.beaconLight.Enabled = true
	elevator.beacon.Material = Enum.Material.Neon
	elevator.beacon.Color = Color3.fromRGB(255, 50, 30)
	elevator.button.Color = Color3.fromRGB(255, 60, 40)
	services.NoiseService:emit("ElevatorCall", station.position, { source = player })
	services.Remotes.Notify:FireAllClients("The elevator is coming. The alarm can't be silenced. SURVIVE.", "danger")
	run.alarmSound = AudioUtil.make(AudioAssets.Alarm, elevator.beacon, "SFX")
	if run.alarmSound then
		run.alarmSound:Play()
	end
	ObjectiveService.broadcast()

	task.spawn(function()
		-- Phase 1: the alarm draws the Listener to the exit.
		while thisRun.alive and os.clock() < ex.endsAt do
			services.NoiseService:emit("Alarm", elevator.beacon.Position, { silentAudio = true })
			task.wait(ObjectiveConfig.Extraction.AlarmInterval)
		end
		if not thisRun.alive then
			return
		end
		if thisRun.alarmSound then
			thisRun.alarmSound:Stop()
		end

		-- Phase 2: boarding.
		ex.phase = "Boarding"
		ex.endsAt = os.clock() + ObjectiveConfig.Extraction.BoardingTime
		setElevatorDoors(true)
		services.NoiseService:emit("HeavyDoor", elevator.zone.Position, {})
		services.Remotes.Notify:FireAllClients("The doors are open. GET IN.", "danger")
		ObjectiveService.broadcast()
		local allAboardSince
		while thisRun.alive and os.clock() < ex.endsAt do
			task.wait(0.25)
			local inside = ObjectiveService.playersInElevator()
			local alive = services.PlayerService.countStatus("Alive")
			if #inside > 0 and #inside >= alive then
				allAboardSince = allAboardSince or os.clock()
				if os.clock() - allAboardSince >= ObjectiveConfig.Extraction.AllAboardDelay then
					break
				end
			else
				allAboardSince = nil
			end
		end
		if not thisRun.alive then
			return
		end

		-- Phase 3: departure. Whoever is inside escapes.
		setElevatorDoors(false)
		task.wait(2.3)
		if not thisRun.alive then
			return
		end
		local escaped = ObjectiveService.playersInElevator()
		for _, p in ipairs(escaped) do
			services.PlayerService.markEscaped(p)
			thisRun.escapedCount += 1
		end
		if #escaped > 0 then
			services.Remotes.Notify:FireAllClients(#escaped .. " escaped in the elevator.", "info")
		end
		elevator.beaconLight.Enabled = false
		elevator.beacon.Material = Enum.Material.SmoothPlastic
		elevator.button.Color = Color3.fromRGB(120, 30, 30)
		-- Anyone left behind can call it again.
		thisRun.extraction = nil
		if services.PlayerService.countStatus("Alive") > 0 then
			services.Remotes.Notify:FireAllClients("The elevator can be called again.", "warn")
		end
		updatePrompts()
		ObjectiveService.broadcast()
	end)
end

function ObjectiveService.completedSteps()
	if not run then
		return 0
	end
	return run.chain.index - 1
end

return ObjectiveService
