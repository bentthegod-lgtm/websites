--[[
	CrashService - the crash simulation. One run per player, owned by the server.

	start(): spawns a ragdoll dummy (DummyModel) at the machine's launch point, puts every
	body part in the "CL_Dummy" collision group (dummies never collide with players or with
	other players' dummies), makes the SERVER the network owner (clients can't move it),
	and gives every body part the launch velocity + spin computed by LaunchService.

	Every run belongs to the facility of its pad and is measured in that course's LOCAL
	space (position - course origin), against that course's rings, zones, objectives,
	bounds, run limits and scoring tuning (CourseConfig.Courses).

	step() (Heartbeat): samples the dummy's root at GameConfig.Run.SampleRate into the
	Scoring run tracker (impossible jumps are rejected there), checks rings (path crosses
	the ring's disc) and distance goals, applies the facility hazards, and ends the run
	when the dummy settles, gets stuck, leaves the arena / falls out of the world, the rig
	breaks, drifts too long in low gravity, or the time limit is hit.

	Hazards (server-side, per run, never global):
	  * Wind (High-Altitude): every Wind.Period a gust changes the dummy's velocity; gusts
	    are deterministic per run seed (Hazards.gust) and the run's total is capped.
	  * Gravity volumes (Gravity Lab): inside a volume, each body part of THAT dummy gets a
	    VectorForce of mass * g * (1 - Scale) upward; outside it is zero, and the forces are
	    removed when the run ends. workspace.Gravity is never touched.
	  * Bounce fields / flip panels (Gravity Lab), destruction combos (Destruction Zone).

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
local Hazards = require(Shared.Hazards)

local CrashService = {}

local services
local world
local runs = {} -- [player] = run
local RUN = GameConfig.Run

-- PlayerWall: invisible walls that keep players on a facility's deck but let dummies and
-- debris fly through (High-Altitude mesa edge).
CrashService.Groups = { Dummy = "CL_Dummy", Player = "CL_Player", Debris = "CL_Debris", PlayerWall = "CL_PlayerWall" }

function CrashService.init(registry)
	services = registry
	-- Each step on its own: a group that already exists (saved in the place file) must not
	-- stop the collidable rules from being set.
	for _, name in pairs(CrashService.Groups) do
		local ok, registered = pcall(function()
			return PhysicsService:IsCollisionGroupRegistered(name)
		end)
		if not (ok and registered) then
			pcall(function()
				PhysicsService:RegisterCollisionGroup(name)
			end)
		end
	end
	local G = CrashService.Groups
	for _, pair in ipairs({ { G.Dummy, G.Dummy }, { G.Dummy, G.Player }, { G.Debris, G.Dummy }, { G.Debris, G.Player }, { G.PlayerWall, G.Dummy }, { G.PlayerWall, G.Debris } }) do
		local ok, err = pcall(function()
			PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
		end)
		if not ok then
			warn("[CrashLab] collision rule " .. pair[1] .. "/" .. pair[2] .. " failed: " .. tostring(err))
		end
	end
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

local function partMass(p)
	local ok, m = pcall(function()
		return p:GetMass()
	end)
	if ok and type(m) == "number" and m > 0 then
		return m
	end
	local props = p.CustomPhysicalProperties
	return p.Size.X * p.Size.Y * p.Size.Z * (if props then props.Density else 0.7)
end

-- Gravity Lab: one VectorForce per body part (zero until the dummy enters a volume).
local function addGravityForces(run)
	run.gravity = { forces = {}, scale = 1, volume = nil, floatTime = 0, lastT = run.startedAt }
	for _, p in ipairs(run.body) do
		local a = Instance.new("Attachment")
		a.Name = "CL_GravityAttachment"
		a.Parent = p
		local f = Instance.new("VectorForce")
		f.Name = "CL_Gravity"
		f.Attachment0 = a
		f.RelativeTo = Enum.ActuatorRelativeTo.World
		f.ApplyAtCenterOfMass = true
		f.Force = Vector3.new(0, 0, 0)
		f.Parent = p
		run.gravity.forces[p] = { force = f, attachment = a, mass = partMass(p) }
	end
end

local function setGravityScale(run, scale)
	local g = run.gravity
	g.scale = scale
	local gravity = workspace.Gravity
	for _, entry in pairs(g.forces) do
		entry.force.Force = if scale == 1 then Vector3.new(0, 0, 0) else Vector3.new(0, Hazards.liftForce(entry.mass, gravity, scale), 0)
	end
end

local function removeGravityForces(run)
	if not run.gravity then
		return
	end
	for _, entry in pairs(run.gravity.forces) do
		entry.force:Destroy()
		entry.attachment:Destroy()
	end
	table.clear(run.gravity.forces)
	run.gravity.scale = 1
end

function CrashService.start(player, pad, machine, launch, stats, featuredId)
	if runs[player] and not runs[player].ended then
		return false
	end
	local data = services.DataService.getProfile(player)
	if not data then
		return false
	end
	local facilityId = pad.facility or CourseConfig.StartFacility
	local course = CourseConfig.Courses[facilityId]
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
	-- Every body part is its own assembly (ball sockets aren't rigid), so each one gets the
	-- spin plus the matching tangential velocity (v + w x r): the whole dummy tumbles as one
	-- body instead of the torso spinning alone and yanking the limbs.
	local omega = spinToWorld(launch.Direction, launch.Spin)
	local centre = parts.Root.CFrame.Position
	for _, p in ipairs(body) do
		pcall(function()
			p:SetNetworkOwner(nil)
		end)
		p.AssemblyLinearVelocity = launch.Velocity + omega:Cross(p.CFrame.Position - centre)
		pcall(function()
			p.AssemblyAngularVelocity = omega
		end)
	end
	local now = os.clock()
	-- Everything about the run is measured in the course's local space.
	local padLocal = pad.cframe.Position - course.Origin
	local origin = Vector3.new(padLocal.X, course.Arena.FloorY, padLocal.Z)
	local forward = Vector3.new(0, 0, 1) -- distance is measured straight down the course
	local tuning = course.Tuning or {}
	local run = {
		player = player,
		facility = facilityId,
		course = course,
		origin = course.Origin,
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
		tracker = Scoring.Run.new(origin, forward, {
			floorY = course.Arena.FloorY,
			impactCap = stats.ImpactCap,
			startTime = now,
			maxSpeed = ScoringConfig.MaxLaunchSpeed * (tuning.SpeedHeadroom or 1),
			tuning = tuning,
			limits = CourseConfig.limits(course, RUN),
		}),
		brokenGroups = {},
		bounces = 0,
		flipped = false,
		connections = {},
		lastSpeed = {}, -- [part] = speed at the previous Heartbeat (pre-contact)
		ended = false,
		eventsSent = 0,
	}
	run.tracker.last = spawnCF.Position - course.Origin
	if course.Wind then
		run.wind = { seed = Hazards.runSeed(player.UserId, data.Stats.Launches), index = 0, total = Vector3.new(0, 0, 0), nextAt = now + course.Wind.Period, gusts = {} }
	end
	if course.Gravity then
		addGravityForces(run)
	end
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
			-- Touched fires after the solver has already resolved the contact, so the part's
			-- current velocity is the post-impact one (a dead stop against a wall reads ~0).
			-- The speed it had at the previous Heartbeat is the impact speed.
			speed = math.max(speed, run.lastSpeed[p] or 0)
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
				local chain = tracker:breakChain(t)
				if chain >= 2 then
					event(run, "Combo", { chain = chain, position = position })
				end
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
		local course = run.course
		local boost = other:GetAttribute("CL_Bounce")
		if type(boost) == "number" and course.Bounce and run.bounces < course.Bounce.Max and t - (run.lastBounce or -math.huge) > 0.4 then
			-- Bounce field: launch the whole dummy upward (never faster than the field's boost).
			run.bounces += 1
			run.lastBounce = t
			for _, p in ipairs(run.body) do
				local v = p.AssemblyLinearVelocity
				p.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, boost), v.Z)
			end
			event(run, "Bounce", { position = position })
		end
		if other:GetAttribute("CL_Flip") and course.Gravity then
			-- Ceiling flip panel: the flip column lets go of this dummy for a while.
			run.flipped = true
			run.flipOffUntil = t + (course.Gravity.FlipOff or 3)
			event(run, "Flip", { position = position })
		end
		local tier = tracker:impact(key, speed, t)
		if tier then
			event(run, "Impact", { tier = tier, position = position, soft = other:GetAttribute("CL_Soft") == true, metal = not other:GetAttribute("CL_Soft") })
		end
	end
end

-- `p` is in the course's local space.
local function outOfBounds(course, p)
	local A = course.Arena
	return p.Y < A.KillY or p.Y > A.Ceiling or math.abs(p.X) > A.HalfWidth + 40 or p.Z > A.Length + 30 or p.Z < A.LaunchZ - 40
end
CrashService.outOfBounds = outOfBounds

local function rigBroken(run)
	for _, p in ipairs(run.body) do
		if not p.Parent then
			return true
		end
	end
	return false
end

-- Wind gust (High-Altitude): deterministic per run seed, capped per gust and in total.
local function applyWind(run, position, now)
	local wind = run.course.Wind
	local state = run.wind
	if not wind or not state or now < state.nextAt then
		return
	end
	state.nextAt = now + wind.Period
	if position.Z < wind.StartZ then
		return
	end
	state.index += 1
	local gust = Hazards.capGust(state.total, Hazards.gust(state.seed, state.index, wind), wind.MaxTotal)
	state.total += gust
	table.insert(state.gusts, gust)
	for _, p in ipairs(run.body) do
		p.AssemblyLinearVelocity += gust
	end
	if gust.Magnitude > wind.MaxGust * 0.5 then
		event(run, "Wind", { position = run.root.Position, gust = gust })
	end
end

-- Gravity volumes (Gravity Lab). Returns true when the dummy has drifted in low gravity
-- for longer than the course allows.
local function applyGravity(run, position, now)
	local g = run.gravity
	if not g then
		return false
	end
	local flipOff = run.flipOffUntil ~= nil and now < run.flipOffUntil
	local volume = Hazards.volumeAt(run.course.Gravity.Volumes, position, flipOff)
	local scale = if volume then volume.Scale else 1
	if scale ~= g.scale then
		setGravityScale(run, scale)
		if volume then
			event(run, "Gravity", { name = volume.Name, scale = scale, position = run.root.Position })
		end
	end
	g.volume = volume
	local dt = math.max(0, now - g.lastT)
	g.lastT = now
	if volume and scale < 0.5 then
		g.floatTime += dt
	else
		g.floatTime = 0
	end
	return g.floatTime >= (run.tracker.limits.MaxFloatTime or math.huge)
end

local function sampleRun(run, now)
	local course = run.course
	-- Local course space: the facility origin is subtracted from every sample.
	local position = run.root.Position - run.origin
	local previous = run.tracker.last
	local result = run.tracker:sample(position, now)
	if result == "ok" then
		for _, ring in ipairs(course.Rings) do
			if not run.tracker:has("Ring", ring.Id) and Scoring.crossesRing(previous, position, ring.Position, ring.Radius) then
				run.tracker:award("Ring", ring.Id, 30)
				event(run, "Ring", { id = ring.Id, position = ring.Position + run.origin })
			end
		end
		for _, goal in ipairs(course.DistanceGoals) do
			if run.tracker.distance >= goal and not run.tracker:has("Distance", goal) then
				run.tracker:award("Distance", goal, 0)
				event(run, "Marker", { distance = goal })
			end
		end
		applyWind(run, position, now)
	end
	local drifted = applyGravity(run, position, now)
	return position, drifted
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
				local position, drifted = sampleRun(run, now)
				if outOfBounds(run.course, position) then
					reason = "outOfBounds"
				elseif drifted then
					reason = "drifted"
				elseif run.tracker.voided then
					reason = "voided"
				else
					reason = run.tracker:status(now)
				end
			end
			if reason then
				CrashService.finish(run, reason)
			else
				for _, p in ipairs(run.body) do
					local ok, v = pcall(function()
						return p.AssemblyLinearVelocity.Magnitude
					end)
					run.lastSpeed[p] = if ok then v else nil
				end
			end
		end
	end
end

-- Objectives completed this run (server data only).
function CrashService.evaluate(run, finalPosition, landed)
	local tracker = run.tracker
	local course = run.course
	if landed then
		for _, zone in ipairs(course.LandingZones) do
			if Scoring.insideZone(finalPosition, zone.Position, zone.Radius) then
				tracker:award("Zone", zone.Id, zone.Points)
			end
		end
	end
	-- Facility bonuses (0 where the course has none).
	local freeFall = tracker:freeFallPoints()
	if freeFall > 0 then
		tracker:award("FreeFall", math.floor(tracker.freeFall), freeFall)
	end
	if tracker.comboPoints > 0 then
		tracker:award("Combo", tracker.comboBest, tracker.comboPoints)
	end
	local done = {}
	for _, o in ipairs(course.Objectives) do
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
		elseif o.Kind == "Props" then
			ok = tracker:count("Prop") >= o.Value
		elseif o.Kind == "Combo" then
			ok = tracker.comboBest >= o.Value
		elseif o.Kind == "FreeFall" then
			ok = tracker.freeFall >= o.Value
		elseif o.Kind == "Hit" then
			ok = (tracker.perObject[o.Key] or 0) > 0
		elseif o.Kind == "Bounce" then
			ok = run.bounces >= o.Value
		elseif o.Kind == "Flip" then
			ok = run.flipped
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
	table.clear(run.lastSpeed)
	removeGravityForces(run)
	local player = run.player
	local model = run.model
	-- Cleanup is scheduled BEFORE the payout, so an error in reward code can never leave
	-- the dummy in the arena.
	task.delay(RUN.CleanupDelay, function()
		if model then
			model:Destroy()
		end
		if runs[player] == run then
			runs[player] = nil
		end
		if player.Parent then
			-- A machine unlocked mid-launch is selected now that the pad is free.
			services.UpgradeService.applyPending(player)
			services.PadService.broadcast()
		end
	end)
	local finalPosition = if run.root.Parent then run.root.Position - run.origin else run.tracker.last
	local landed = reason == "settled" or reason == "stuck"
	local paid = reason ~= "left" and reason ~= "cancelled"
	if paid then
		local ok, err = pcall(function()
			local objectives = CrashService.evaluate(run, finalPosition, landed)
			services.ScoringService.finish(run, objectives, reason)
		end)
		if not ok then
			warn("[CrashLab] run payout failed for " .. player.Name .. ": " .. tostring(err))
			-- The owner's client waits for RunEnded before it allows another launch.
			services.Remotes.RunEnded:FireAllClients(player.UserId, { score = 0, distance = 0, name = player.DisplayName })
		end
	end
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
