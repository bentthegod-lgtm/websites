--[[
	CrashService - the crash simulation. One run per player, owned by the server.

	start(): spawns a ragdoll dummy (DummyModel) at the machine's launch point, puts every
	body part in the "CL_Dummy" collision group (dummies never collide with players or with
	other players' dummies), makes the SERVER the network owner (clients can't move it),
	and gives every body part the launch velocity + spin computed by LaunchService.

	step() (Heartbeat): samples the dummy's root at GameConfig.Run.SampleRate into the
	Scoring run tracker (impossible jumps are rejected there), checks rings (path crosses
	the ring's disc) and distance goals, and ends the run when the dummy settles, gets
	stuck, leaves the arena / falls out of the world, the rig breaks, or the time limit
	is hit.

	contact(): every body part's Touched goes here. Contacts are classified (floor /
	obstacle / target / prop / soft pad), turned into impacts by the tracker (debounced,
	capped, tiered by the dummy's own speed) and may break props (CourseService).

	finish(): landing zones + objectives are evaluated from what the server saw, then
	ScoringService pays out once. Cleanup is always scheduled, whatever ended the run.
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local GameConfig = require(Shared.Config.GameConfig)
local CourseConfig = require(Shared.Config.CourseConfig)
local ScoringConfig = require(Shared.Config.ScoringConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local DummyModel = require(Shared.DummyModel)
local Scoring = require(Shared.Scoring)

local CrashService = {}

local services
local world
local runs = {} -- [player] = run
local RUN = GameConfig.Run
local ARENA = GameConfig.Arena

CrashService.Groups = { Dummy = "CL_Dummy", Player = "CL_Player", Debris = "CL_Debris" }

function CrashService.init(registry)
	services = registry
	pcall(function()
		for _, name in pairs(CrashService.Groups) do
			PhysicsService:RegisterCollisionGroup(name)
		end
		local G = CrashService.Groups
		PhysicsService:CollisionGroupSetCollidable(G.Dummy, G.Dummy, false)
		PhysicsService:CollisionGroupSetCollidable(G.Dummy, G.Player, false)
		PhysicsService:CollisionGroupSetCollidable(G.Debris, G.Dummy, false)
		PhysicsService:CollisionGroupSetCollidable(G.Debris, G.Player, false)
	end)
end

function CrashService.setWorld(newWorld)
	world = newWorld
end

function CrashService.isRunning(player)
	return runs[player] ~= nil and not runs[player].ended
end

function CrashService.runOf(player)
	return runs[player]
end

function CrashService.activeCount()
	local n = 0
	for _, run in pairs(runs) do
		if not run.ended then
			n += 1
		end
	end
	return n
end

local function attachTrail(root, trailId)
	local def = CosmeticConfig.Trails[trailId]
	if not def or (not def.Color and not def.Rainbow) then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 0.7, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, -0.7, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.8
	trail.LightEmission = 0.4
	trail.WidthScale = NumberSequence.new(1, 0.2)
	if def.Rainbow then
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(70, 220, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 140, 255)),
		})
	else
		trail.Color = ColorSequence.new(Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3]))
	end
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = root
end

-- Spin is given in launch space (X = right, Y = up, Z = forward).
local function spinToWorld(direction, spin)
	local forward = Vector3.new(direction.X, 0, direction.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, 1)
	local up = Vector3.new(0, 1, 0)
	local right = forward:Cross(up)
	return right * spin.X + up * spin.Y + forward * spin.Z
end

function CrashService.start(player, pad, machine, launch, stats, featuredId)
	if runs[player] and not runs[player].ended then
		return false
	end
	local data = services.DataService.getProfile(player)
	if not data then
		return false
	end
	local rig = services.PadService.rig(pad.index)
	local offset = if rig then rig.launchOffset else CFrame.new(0, machine.LaunchHeight, 4)
	local spawnCF = pad.cframe * offset
	local model, parts = DummyModel.build(data.Cosmetics.Skin, spawnCF, { ragdoll = true, physics = stats.Dummy })
	model.Name = "Dummy_" .. player.UserId
	model:SetAttribute("Owner", player.UserId)
	local body = DummyModel.bodyParts(model)
	for _, p in ipairs(body) do
		p.CollisionGroup = CrashService.Groups.Dummy
	end
	attachTrail(parts.Root, data.Cosmetics.Trail)
	model.Parent = world.dummyFolder
	-- Server owns the physics: clients can't teleport or fling their own dummy.
	for _, p in ipairs(body) do
		pcall(function()
			p:SetNetworkOwner(nil)
		end)
		p.AssemblyLinearVelocity = launch.Velocity
	end
	pcall(function()
		parts.Root.AssemblyAngularVelocity = spinToWorld(launch.Direction, launch.Spin)
	end)
	local now = os.clock()
	local origin = Vector3.new(pad.cframe.Position.X, ARENA.FloorY, pad.cframe.Position.Z)
	local forward = Vector3.new(0, 0, 1) -- distance is measured straight down the course
	local run = {
		player = player,
		pad = pad,
		machine = machine,
		launch = launch,
		stats = stats,
		featuredId = featuredId,
		model = model,
		root = parts.Root,
		body = body,
		startedAt = now,
		nextSample = now,
		lastSample = spawnCF.Position,
		tracker = Scoring.Run.new(origin, forward, { floorY = ARENA.FloorY, impactCap = stats.ImpactCap, startTime = now, maxSpeed = ScoringConfig.MaxLaunchSpeed }),
		brokenGroups = {},
		connections = {},
		ended = false,
		eventsSent = 0,
	}
	run.tracker.last = spawnCF.Position
	runs[player] = run
	for _, p in ipairs(body) do
		table.insert(run.connections, p.Touched:Connect(function(other)
			local speed = 0
			local ok, v = pcall(function()
				return p.AssemblyLinearVelocity.Magnitude
			end)
			if ok then
				speed = v
			end
			CrashService.contact(run, other, speed, p.Position)
		end))
	end
	services.Remotes.RunStarted:FireAllClients(player.UserId, pad.index, model, featuredId)
	return true
end

local function event(run, kind, data)
	-- Throttle per run so a pinball run can't flood remotes.
	if run.eventsSent > 60 then
		return
	end
	run.eventsSent += 1
	services.Remotes.RunEvent:FireAllClients(run.player.UserId, kind, data)
end

-- Classifies a contact. `speed` is the touching body part's speed (studs/s) measured on
-- the server; the client never reports contacts.
function CrashService.contact(run, other, speed, position)
	if run.ended or not other or not other.Parent then
		return
	end
	if other:IsDescendantOf(world.dummyFolder) or other:IsDescendantOf(world.debrisFolder) then
		return
	end
	local t = os.clock()
	local tracker = run.tracker
	position = position or run.root.Position
	local targetId = other:GetAttribute("CL_Target")
	local propId = other:GetAttribute("CL_Prop")
	if targetId then
		local def = CourseConfig.TargetById[targetId]
		if def and speed >= ScoringConfig.Impact.MinSpeed and tracker:award("Target", targetId, def.Points) then
			event(run, "Target", { id = targetId, position = position })
		end
		local tier = tracker:impact("Target:" .. targetId, speed, t)
		if tier then
			event(run, "Impact", { tier = tier, position = position, metal = true })
		end
		return
	end
	if propId then
		local outcome, prop = services.CourseService.hitProp(propId, speed, run.stats.Dummy.Break)
		if outcome == "broken" then
			local kind = CourseConfig.DestructibleKinds[prop.kind]
			if tracker:award("Prop", propId, kind.Points) then
				run.brokenGroups[prop.group or "?"] = true
			end
		end
		local tier = tracker:impact("Prop:" .. propId, speed, t)
		if tier and outcome ~= "broken" then
			event(run, "Impact", { tier = tier, position = position })
		end
		return
	end
	if other:GetAttribute("CL_Floor") then
		local tier = tracker:impact("Floor", speed, t, "Floor")
		if tier then
			event(run, "Impact", { tier = tier, position = position, floor = true })
		end
		return
	end
	local key = other:GetAttribute("CL_Key")
	if key then
		local tier = tracker:impact(key, speed, t)
		if tier then
			event(run, "Impact", { tier = tier, position = position, soft = other:GetAttribute("CL_Soft") == true, metal = not other:GetAttribute("CL_Soft") })
		end
	end
end

local function outOfBounds(p)
	return p.Y < ARENA.KillY or p.Y > ARENA.Ceiling or math.abs(p.X) > ARENA.HalfWidth + 40 or p.Z > ARENA.Length + 30 or p.Z < ARENA.LaunchZ - 40
end

local function rigBroken(run)
	for _, p in ipairs(run.body) do
		if not p.Parent then
			return true
		end
	end
	return false
end

local function sampleRun(run, now)
	local position = run.root.Position
	local previous = run.tracker.last
	local result = run.tracker:sample(position, now)
	if result == "ok" then
		for _, ring in ipairs(CourseConfig.Rings) do
			if not run.tracker:has("Ring", ring.Id) and Scoring.crossesRing(previous, position, ring.Position, ring.Radius) then
				run.tracker:award("Ring", ring.Id, 30)
				event(run, "Ring", { id = ring.Id, position = ring.Position })
			end
		end
		for _, goal in ipairs(CourseConfig.DistanceGoals) do
			if run.tracker.distance >= goal and not run.tracker:has("Distance", goal) then
				run.tracker:award("Distance", goal, 0)
				event(run, "Marker", { distance = goal })
			end
		end
	end
	return position
end

function CrashService.step()
	local now = os.clock()
	for player, run in pairs(runs) do
		if not run.ended then
			local reason
			if not player.Parent then
				reason = "left"
			elseif rigBroken(run) then
				reason = "broken"
			elseif now >= run.nextSample then
				run.nextSample = now + 1 / RUN.SampleRate
				local position = sampleRun(run, now)
				if outOfBounds(position) then
					reason = "outOfBounds"
				elseif run.tracker.voided then
					reason = "voided"
				else
					reason = run.tracker:status(now)
				end
			end
			if reason then
				CrashService.finish(run, reason)
			end
		end
	end
end

-- Objectives completed this run (server data only).
function CrashService.evaluate(run, finalPosition, landed)
	local tracker = run.tracker
	if landed then
		for _, zone in ipairs(CourseConfig.LandingZones) do
			if Scoring.insideZone(finalPosition, zone.Position, zone.Radius) then
				tracker:award("Zone", zone.Id, zone.Points)
			end
		end
	end
	local done = {}
	for _, o in ipairs(CourseConfig.Objectives) do
		local ok = false
		if o.Kind == "Ring" then
			ok = tracker:has("Ring", o.Id)
		elseif o.Kind == "Target" then
			ok = tracker:has("Target", o.Id)
		elseif o.Kind == "Land" then
			ok = tracker:has("Zone", o.Id)
		elseif o.Kind == "Distance" then
			ok = tracker.distance >= o.Value
		elseif o.Kind == "Break" then
			ok = run.brokenGroups[o.Group] == true
		elseif o.Kind == "Multi" then
			ok = tracker:count("Target") + tracker:count("Prop") >= o.Value
		end
		if ok and tracker:award("Objective", o.Id, o.Points) then
			table.insert(done, o.Id)
		end
	end
	return done
end

function CrashService.finish(run, reason)
	if run.ended then
		return
	end
	run.ended = true
	run.reason = reason
	for _, c in ipairs(run.connections) do
		c:Disconnect()
	end
	table.clear(run.connections)
	local finalPosition = if run.root.Parent then run.root.Position else run.tracker.last
	local landed = reason == "settled" or reason == "stuck"
	local paid = reason ~= "left" and reason ~= "cancelled"
	if paid then
		local objectives = CrashService.evaluate(run, finalPosition, landed)
		services.ScoringService.finish(run, objectives, reason)
	end
	local player = run.player
	local model = run.model
	task.delay(RUN.CleanupDelay, function()
		if model then
			model:Destroy()
		end
		if runs[player] == run then
			runs[player] = nil
		end
		if player.Parent then
			services.PadService.broadcast()
		end
	end)
end

function CrashService.cancel(player)
	local run = runs[player]
	if run and not run.ended then
		CrashService.finish(run, "cancelled")
	end
	if run and run.model then
		run.model:Destroy()
	end
	runs[player] = nil
end

function CrashService.onPlayerRemoving(player)
	CrashService.cancel(player)
end

return CrashService
