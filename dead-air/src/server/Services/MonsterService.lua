--[[
	MonsterService - runs THE LISTENER in the world.

	Perception -> MonsterBrain -> movement:
	  * Hearing: registered as a NoiseService listener; receives approximate positions only.
	  * Sight: field-of-view + range (shorter in dark cells, longer toward flashlights) with
	    raycast line of sight that respects walls, doors and props. Hidden players are never
	    visible. Awareness builds over time instead of instant detection.
	  * Movement: PathfindingService paths, re-computed on a throttle (never every frame),
	    direct pursuit when the target is in clear view, door bursting, speed ramps.
	  * Recovery: stuck detection -> repath -> new search -> (last resort) relocate to a
	    patrol point no player can see. It never teleports onto or near players.
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MonsterConfig = require(Shared.Config.MonsterConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local MonsterBrain = require(Shared.MonsterBrain)
local AudioUtil = require(Shared.AudioUtil)
local MonsterModel = require(script.Parent.MonsterModel)

local MonsterService = {}

local services
local monster -- active record or nil
local heartbeatConnection

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

function MonsterService.init(registry)
	services = registry
end

function MonsterService.model()
	return monster and monster.model
end

function MonsterService.state()
	return monster and monster.brain.state
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function playerByUserId(userId)
	return Players:GetPlayerByUserId(userId)
end

---------------------------------------------------------------------------------------------
-- Sight
---------------------------------------------------------------------------------------------

local function sightExclude()
	local list = { monster.model }
	if monster.map and monster.map.itemsFolder then
		table.insert(list, monster.map.itemsFolder)
	end
	return list
end

-- Returns visible:boolean, distance:number for a player state.
local function visibility(state)
	if not monster or not state.root or not state.root.Parent or state.hiddenIn then
		return false, math.huge
	end
	if state.status ~= "Alive" and state.status ~= "Downed" then
		return false, math.huge
	end
	local sight = MonsterConfig.Sight
	local eye = monster.head.Position
	local targetHead = state.character:FindFirstChild("Head")
	local targetPos = state.root.Position
	local distance = (targetPos - eye).Magnitude

	local cell = monster.map:cellAt(targetPos)
	local lit = cell ~= nil and monster.map:isLit(cell)
	local range = sight.Range * monster.mods.sight * (if lit then 1 else sight.DarkRangeMultiplier)
	if state.flashlightOn then
		range += sight.FlashlightRangeBonus
	end
	if distance > range then
		return false, distance
	end

	if distance > sight.CloseRange then
		local forward = flat(monster.root.CFrame.LookVector)
		local toTarget = flat(targetPos - eye)
		if toTarget.Magnitude > 0.01 and forward.Magnitude > 0.01 then
			local cos = forward.Unit:Dot(toTarget.Unit)
			if cos < math.cos(math.rad(sight.FieldOfView / 2)) then
				-- A lit flashlight pointed its way is noticed even outside its view cone.
				if not state.flashlightOn then
					return false, distance
				end
			end
		end
	end

	losParams.FilterDescendantsInstances = sightExclude()
	for _, point in ipairs({ targetHead and targetHead.Position, targetPos }) do
		if point then
			local result = Workspace:Raycast(eye, point - eye, losParams)
			if not result or result.Instance:IsDescendantOf(state.character) then
				return true, distance, lit
			end
		end
	end
	return false, distance
end

function MonsterService.canSee(player)
	if not monster or not monster.active then
		return false
	end
	local state = services.PlayerService.get(player)
	if not state then
		return false
	end
	local hidden = state.hiddenIn
	state.hiddenIn = nil
	local visible = visibility(state)
	state.hiddenIn = hidden
	return visible
end

local function sightGain(state, distance, lit)
	local sight = MonsterConfig.Sight
	local range = sight.Range * monster.mods.sight
	local closeness = math.clamp(1 - distance / range, 0.05, 1) ^ 0.8
	local gain = sight.GainPerSecond * closeness * monster.mods.sight
	local speed = flat(state.root.AssemblyLinearVelocity).Magnitude
	if state.crouch then
		gain *= sight.CrouchMultiplier
	end
	if state.sprinting then
		gain *= sight.SprintMultiplier
	elseif speed < 1 then
		gain *= sight.StillMultiplier
	end
	if state.flashlightOn then
		gain *= sight.FlashlightMultiplier
	end
	if not lit then
		gain *= 0.7
	end
	if distance <= sight.CloseRange then
		gain = math.max(gain, 1.2)
	end
	return gain
end

---------------------------------------------------------------------------------------------
-- Brain provider
---------------------------------------------------------------------------------------------

local function makeProvider()
	return {
		patrolPoint = function(from)
			local map = monster.map
			local rng = monster.rng
			if rng:chance(MonsterConfig.Patrol.HeatBias) then
				local hot = services.NoiseService.hotCell(rng)
				if hot then
					return map:cellCenter(hot) + Vector3.new(rng:range(-3, 3), 3, rng:range(-3, 3))
				end
			end
			local options = {}
			for _, p in ipairs(map.patrolPoints) do
				local d = (flat(p) - flat(from)).Magnitude
				if d > 20 and d < MonsterConfig.Patrol.MaxPointDistance then
					table.insert(options, p)
				end
			end
			return rng:pick(options) or rng:pick(map.patrolPoints)
		end,

		searchPoints = function(center, radius, count)
			local map = monster.map
			local rng = monster.rng
			local candidates = {}
			for _, p in ipairs(map.patrolPoints) do
				local d = (flat(p) - flat(center)).Magnitude
				if d <= radius then
					table.insert(candidates, { position = p, score = d + rng:range(0, 14) })
				end
			end
			for _, locker in ipairs(services.HidingService.spots()) do
				local d = (flat(locker.frontPosition) - flat(center)).Magnitude
				if d <= radius then
					-- Hiding spots close to the evidence are prioritised.
					local bias = if d <= MonsterConfig.Search.HidingEvidenceRadius then -20 else rng:range(0, 18)
					table.insert(candidates, {
						position = locker.frontPosition + Vector3.new(0, 3, 0),
						hidingSpotId = locker.id,
						score = d + bias,
					})
				end
			end
			table.sort(candidates, function(a, b)
				return a.score < b.score
			end)
			local points = { { position = center } }
			for i = 1, math.min(count, #candidates) do
				table.insert(points, candidates[i])
			end
			return points
		end,

		sawHidingEntry = function(id)
			return services.HidingService.sawEntry(id)
		end,
	}
end

---------------------------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------------------------

local function groundGoal(goal)
	return Vector3.new(goal.X, 3, goal.Z)
end

local function computePath(goal)
	if monster.computing then
		return
	end
	monster.computing = true
	monster.lastCompute = os.clock()
	local record = monster
	task.spawn(function()
		local start = record.root.Position
		local ok = pcall(function()
			record.path:ComputeAsync(start, goal)
		end)
		if record ~= monster then
			return
		end
		record.computing = false
		if ok and record.path.Status == Enum.PathStatus.Success then
			record.waypoints = record.path:GetWaypoints()
			record.wpIndex = math.min(2, #record.waypoints)
			record.pathGoal = goal
			record.fallbackTried = false
		else
			-- Retry once toward the centre of the goal's cell (goal may be inside a prop).
			local cell = record.map:cellAt(goal)
			if cell and not record.fallbackTried then
				record.fallbackTried = true
				local center = groundGoal(record.map:cellCenter(cell))
				record.pathGoal = goal
				record.computing = true
				local ok2 = pcall(function()
					record.path:ComputeAsync(start, center)
				end)
				record.computing = false
				if ok2 and record.path.Status == Enum.PathStatus.Success then
					record.waypoints = record.path:GetWaypoints()
					record.wpIndex = math.min(2, #record.waypoints)
					return
				end
			end
			record.waypoints = nil
			record.pathFailed = true
			record.fallbackTried = false
		end
	end)
end

local function clearLine(from, to)
	losParams.FilterDescendantsInstances = sightExclude()
	local direction = to - from
	local result = Workspace:Raycast(from, direction, losParams)
	if result then
		local character = result.Instance:FindFirstAncestorOfClass("Model")
		if character and Players:GetPlayerFromCharacter(character) then
			return true
		end
		return false
	end
	-- Also check at knee height so low props do not snag a direct chase.
	local low = Workspace:Raycast(from - Vector3.new(0, 4, 0), direction, losParams)
	return low == nil or (low.Instance:FindFirstAncestorOfClass("Model") ~= nil and Players:GetPlayerFromCharacter(low.Instance:FindFirstAncestorOfClass("Model")) ~= nil)
end

local function followGoal(goal, chasing, direct, now)
	local root = monster.root
	local humanoid = monster.humanoid
	local pos = root.Position
	goal = groundGoal(goal)

	if direct and (flat(goal) - flat(pos)).Magnitude <= MonsterConfig.Chase.DirectRange and clearLine(pos, goal + Vector3.new(0, 1, 0)) then
		monster.waypoints = nil
		humanoid:MoveTo(goal)
		return
	end

	local needRepath = monster.waypoints == nil
		or monster.pathGoal == nil
		or (flat(monster.pathGoal) - flat(goal)).Magnitude > MonsterConfig.Chase.RepathDistance
	local interval = if chasing then MonsterConfig.Chase.RepathInterval else 3
	if not needRepath and now - (monster.lastCompute or 0) > interval and chasing then
		needRepath = true
	end
	if needRepath and now - (monster.lastCompute or 0) >= MonsterConfig.Path.ComputeCooldown then
		computePath(goal)
	end

	local waypoints = monster.waypoints
	if waypoints and monster.wpIndex <= #waypoints then
		local wp = waypoints[monster.wpIndex]
		if (flat(wp.Position) - flat(pos)).Magnitude < MonsterConfig.Path.ReachDistance then
			monster.wpIndex += 1
			wp = waypoints[monster.wpIndex]
		end
		if wp then
			humanoid:MoveTo(wp.Position)
		else
			humanoid:MoveTo(goal)
		end
	end
end

local function stopMoving()
	monster.humanoid:MoveTo(monster.root.Position)
end

local function faceToward(target)
	local root = monster.root
	local pos = root.Position
	local look = flat(target - pos)
	if look.Magnitude < 0.5 then
		return
	end
	local goalCF = CFrame.lookAt(pos, pos + look)
	root.CFrame = root.CFrame:Lerp(goalCF, 0.25)
end

local function anyPlayerNear(position, radius)
	for _, state in ipairs(services.PlayerService.inRound()) do
		if state.root and state.root.Parent and (state.root.Position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function anyPlayerCanSeePoint(point)
	losParams.FilterDescendantsInstances = sightExclude()
	for _, state in ipairs(services.PlayerService.inRound()) do
		local head = state.character and state.character:FindFirstChild("Head")
		if head and state.status == "Alive" then
			local result = Workspace:Raycast(head.Position, point - head.Position, losParams)
			if not result then
				return true
			end
		end
	end
	return false
end

-- Last-resort unstick: move to a patrol point far from everyone and out of sight.
local function relocate()
	local rng = monster.rng
	local options = {}
	for _, p in ipairs(monster.map.patrolPoints) do
		if not anyPlayerNear(p, 60) and not anyPlayerCanSeePoint(p + Vector3.new(0, 3, 0)) then
			table.insert(options, p)
		end
	end
	local target = rng:pick(options)
	if not target then
		return false
	end
	monster.model:PivotTo(CFrame.new(groundGoal(target) + Vector3.new(0, 3, 0)))
	monster.waypoints = nil
	monster.stuck.repaths = 0
	return true
end

local function checkStuck(intent, now)
	local stuck = monster.stuck
	if now - stuck.lastCheck < MonsterConfig.Stuck.CheckInterval then
		return
	end
	local pos = monster.root.Position
	local moved = (flat(pos) - flat(stuck.lastPos)).Magnitude
	stuck.lastCheck = now
	stuck.lastPos = pos
	if not intent.goal or intent.speed <= 0 or monster.doorPauseUntil > now then
		stuck.repaths = 0
		return
	end
	if moved >= MonsterConfig.Stuck.MinProgress then
		stuck.repaths = 0
		return
	end
	stuck.repaths += 1
	monster.waypoints = nil
	monster.pathGoal = nil
	if stuck.repaths == MonsterConfig.Stuck.MaxRepaths then
		monster.brain:forceSearch(pos, now)
	elseif stuck.repaths >= MonsterConfig.Stuck.MaxRepaths * 2 then
		if not relocate() then
			stuck.repaths = MonsterConfig.Stuck.MaxRepaths
		end
	end
end

local function handleDoors(now)
	if monster.doorPauseUntil > now then
		return true
	end
	local pos = monster.root.Position
	local forward = flat(monster.root.CFrame.LookVector)
	for _, door in ipairs(services.DoorService.closedNear(pos, MonsterConfig.Stuck.DoorReach)) do
		local toDoor = flat(door.panel.Position - pos)
		local ahead = toDoor.Magnitude < 3.5 or (toDoor.Magnitude > 0.01 and forward.Unit:Dot(toDoor.Unit) > 0.3)
		if ahead then
			services.DoorService.monsterForce(door)
			monster.doorPauseUntil = now + MonsterConfig.Stuck.DoorPause
			stopMoving()
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------

local function playSound(name)
	-- Cues restart from the top each time and fade out after their configured length.
	local cue = monster.sounds[name]
	if cue then
		cue:Play()
	end
end

local function doAttack(intent)
	if monster.attacking then
		return
	end
	local target = intent.targetId and playerByUserId(intent.targetId)
	if not target then
		monster.brain:attackResolved(false, os.clock())
		return
	end
	monster.attacking = true
	playSound("Screech")
	services.Remotes.MonsterCue:FireClient(target, "AttackWindup", {})
	local record = monster
	task.delay(MonsterConfig.Chase.AttackWindup, function()
		if record ~= monster then
			return
		end
		local state = services.PlayerService.get(target)
		local hit = false
		if state and state.status == "Alive" and state.root and state.root.Parent then
			local reach = (state.root.Position - record.root.Position).Magnitude
			local visible = visibility(state)
			if reach <= MonsterConfig.Chase.AttackReach and visible then
				local result = services.PlayerService.catch(target)
				hit = result ~= nil
				if hit then
					playSound("Attack")
					services.Remotes.MonsterCue:FireClient(target, "Caught", { result = result })
					services.Remotes.MonsterCue:FireAllClients("Kill", { position = state.root.Position, userId = target.UserId })
				end
			end
		end
		record.attacking = false
		record.brain:attackResolved(hit, os.clock())
	end)
end

local function doCheckHiding(intent)
	if monster.checking then
		return
	end
	local locker = services.HidingService.get(intent.hidingSpotId)
	if not locker then
		monster.brain:hidingResolved(false, nil, nil, os.clock())
		return
	end
	monster.checking = true
	stopMoving()
	local record = monster
	task.delay(0.6, function()
		if record ~= monster then
			return
		end
		local occupant = services.HidingService.check(intent.hidingSpotId, record.rng)
		if occupant then
			services.Remotes.MonsterCue:FireClient(occupant, "FoundHiding", {})
			local state = services.PlayerService.get(occupant)
			record.brain:hidingResolved(true, occupant.UserId, state and state.root and state.root.Position or locker.frontPosition, os.clock())
			record.checking = false
		else
			task.wait(MonsterConfig.Search.HidingCheckDuration)
			if record == monster then
				record.checking = false
				record.brain:hidingResolved(false, nil, nil, os.clock())
			end
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------------------------

local function buildChaseContext()
	local brain = monster.brain
	if brain.state ~= MonsterBrain.States.Chase or not brain.targetId then
		return nil
	end
	local player = playerByUserId(brain.targetId)
	local state = player and services.PlayerService.get(player)
	if not state or not state.inRound or state.status ~= "Alive" or not state.root or not state.root.Parent then
		return { valid = false }
	end
	local visible = visibility(state)
	return {
		valid = true,
		visible = visible,
		position = state.root.Position,
		velocity = flat(state.root.AssemblyLinearVelocity),
		-- Horizontal distance: the Listener's head is far above a player's, so 3D distance
		-- would never fall inside attack range.
		distance = (flat(state.root.Position) - flat(monster.root.Position)).Magnitude,
	}
end

local function tick(dt, now)
	local brain = monster.brain

	-- Sight
	local observations = {}
	for _, state in ipairs(services.PlayerService.inRound()) do
		if state.status == "Alive" and state.root and state.root.Parent then
			local visible, _, lit = visibility(state)
			local distance = (flat(state.root.Position) - flat(monster.root.Position)).Magnitude
			table.insert(observations, {
				id = state.player.UserId,
				position = state.root.Position,
				velocity = flat(state.root.AssemblyLinearVelocity),
				gain = if visible then sightGain(state, distance, lit) else 0,
				distance = distance,
			})
		end
	end
	brain:perceive(observations, dt, now)

	local ctx = {
		position = monster.root.Position,
		pathFailed = monster.pathFailed,
		target = buildChaseContext(),
	}
	monster.pathFailed = false
	local intent = brain:update(now, ctx)

	-- State change cues
	if brain.state ~= monster.lastState then
		if brain.state == MonsterBrain.States.Chase and monster.lastState ~= MonsterBrain.States.Attack then
			playSound("Screech")
			monster.nextRoar = now + monster.rng:range(2.6, 3.4)
			local target = brain.targetId and playerByUserId(brain.targetId)
			services.Remotes.MonsterCue:FireAllClients("ChaseStart", { targetUserId = brain.targetId, position = monster.root.Position })
			if target then
				services.Remotes.MonsterCue:FireClient(target, "Spotted", {})
			end
		elseif monster.lastState == MonsterBrain.States.Chase and brain.state == MonsterBrain.States.Lost then
			services.Remotes.MonsterCue:FireAllClients("ChaseLost", {})
		end
		monster.lastState = brain.state
		monster.model:SetAttribute("State", brain.state)
	end
	monster.model:SetAttribute("Listening", intent.listening == true)
	monster.model:SetAttribute("Rush", intent.rush == true)
	monster.model:SetAttribute("TargetUserId", if brain.state == MonsterBrain.States.Chase then brain.targetId else nil)

	-- Speed
	local desired = intent.speed or 0
	local current = monster.humanoid.WalkSpeed
	local accel = MonsterConfig.Acceleration * dt
	if intent.chasing then
		current = desired -- chase ramp is shaped by the brain
	elseif current < desired then
		current = math.min(desired, current + accel)
	else
		current = math.max(desired, current - accel * 2)
	end
	monster.humanoid.WalkSpeed = math.max(current, 0.01)

	-- Actions / movement
	if intent.action == "attack" then
		doAttack(intent)
		local target = intent.targetId and playerByUserId(intent.targetId)
		local state = target and services.PlayerService.get(target)
		if state and state.root then
			-- Lunge through the wind-up.
			monster.humanoid.WalkSpeed = MonsterConfig.Speeds.Chase * monster.mods.speed
			monster.humanoid:MoveTo(state.root.Position)
		end
	elseif intent.action == "checkHiding" then
		doCheckHiding(intent)
		local locker = services.HidingService.get(intent.hidingSpotId)
		if locker then
			faceToward(locker.promptPart.Position)
		end
	elseif not handleDoors(now) then
		if intent.goal and intent.speed > 0 then
			followGoal(intent.goal, intent.chasing == true, intent.direct == true, now)
		else
			stopMoving()
			if intent.face then
				faceToward(intent.face)
			end
		end
	end

	checkStuck(intent, now)

	-- Keeps roaring for the whole chase, alternating two roars, so you always hear it coming.
	if brain.state == MonsterBrain.States.Chase and now >= (monster.nextRoar or 0) then
		monster.nextRoar = now + monster.rng:range(3, 4.5)
		monster.roarToggle = not monster.roarToggle
		playSound(if monster.roarToggle then "ChaseRoar" else "Screech")
	end

	-- Occasional distant vocalisation while hunting quietly.
	if (brain.state == "Patrol" or brain.state == "Search") and now >= monster.nextVocal then
		monster.nextVocal = now + monster.rng:range(25, 60)
		playSound("Vocal")
	end
	if intent.listening and not monster.wasListening then
		playSound("Listen")
	end
	monster.wasListening = intent.listening == true
end

---------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------

function MonsterService.spawn(map, mods, rng)
	MonsterService.despawn()
	local model, root, humanoid, head = MonsterModel.build(map.monsterSpawn)
	model.Parent = Workspace
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local sounds = {
		Vocal = AudioUtil.cue(AudioAssets.MonsterVocal, head, "SFX"),
		Screech = AudioUtil.cue(AudioAssets.MonsterScreech, head, "SFX"),
		ChaseRoar = AudioUtil.cue(AudioAssets.MonsterChaseRoar, head, "SFX"),
		Listen = AudioUtil.cue(AudioAssets.MonsterListen, head, "SFX"),
		Attack = AudioUtil.cue(AudioAssets.MonsterAttack, head, "SFX"),
	}
	local breath = AudioUtil.make(AudioAssets.MonsterBreath, head, "SFX")
	if breath then
		breath:Play()
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = MonsterConfig.Path.AgentRadius,
		AgentHeight = MonsterConfig.Path.AgentHeight,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = MonsterConfig.Path.WaypointSpacing,
		Costs = { Door = 1.5 },
	})

	monster = {
		model = model,
		root = root,
		humanoid = humanoid,
		head = head,
		map = map,
		mods = mods,
		rng = rng,
		path = path,
		sounds = sounds,
		stuck = { lastCheck = os.clock(), lastPos = root.Position, repaths = 0 },
		doorPauseUntil = 0,
		nextVocal = os.clock() + 20,
		active = true,
	}
	monster.brain = MonsterBrain.new(MonsterConfig, rng, makeProvider(), mods)

	monster.unlisten = services.NoiseService.addListener({
		getEar = function()
			if monster and monster.active and monster.head.Parent then
				return monster.head.Position
			end
			return nil
		end,
		hearingMultiplier = function()
			return monster.mods.hearing * (if map.powered then 1.1 else 1)
		end,
		exclude = function()
			local list = { monster.model }
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Character then
					table.insert(list, player.Character)
				end
			end
			if map.itemsFolder then
				table.insert(list, map.itemsFolder)
			end
			return list
		end,
		onHear = function(stimulus)
			if monster and monster.active then
				monster.brain:hear(stimulus, os.clock())
			end
		end,
	})

	local accumulator = 0
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if not monster or not monster.active then
			return
		end
		accumulator += dt
		if accumulator < MonsterConfig.TickRate then
			return
		end
		local step = accumulator
		accumulator = 0
		local ok, err = pcall(tick, step, os.clock())
		if not ok then
			warn("[DeadAir] Monster tick error: " .. tostring(err))
		end
	end)

	services.Remotes.MonsterCue:FireAllClients("Arrived", { position = root.Position })
	return monster
end

function MonsterService.despawn()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if monster then
		monster.active = false
		if monster.unlisten then
			monster.unlisten()
		end
		if monster.model then
			monster.model:Destroy()
		end
		monster = nil
	end
end

-- Lets objectives draw the Listener (e.g. the elevator alarm) via normal noise; this helper
-- exists for debugging from the command bar: require(...).debugState()
function MonsterService.debugState()
	if not monster then
		return "no monster"
	end
	local lines = { "state=" .. monster.brain.state }
	for _, h in ipairs(monster.brain.history) do
		table.insert(lines, string.format("%.1f %s -> %s (%s)", h.at, h.from, h.to, tostring(h.reason)))
	end
	return table.concat(lines, "\n")
end

return MonsterService
