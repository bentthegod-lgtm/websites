--[[
	EffectsController - everything that moves or sparkles on the client. Purely visual:
	none of it feeds back into gameplay.

	* Machine animations (from the server's MachineFx events), per machine type:
	    Standard   the catapult arm cocks back while charging, then whips forward
	    Spring     the barrel tilts to the launch angle, the coil compresses and the piston
	               draws back, then snaps forward
	    AirCannon  the barrel tilts up, the warning beacon flashes, the gauge needle climbs,
	               then a muzzle blast and recoil
	* Impact bursts by tier, prop-break dust, ring flashes, target hits, launch effects
	  (cosmetic Standard / Confetti / Fireworks), record celebrations.
	* Ambient motion: arena fans spin, deck warning lights pulse while anything charges.
	Budgets: at most PerformanceConfig.ClientImpactFx bursts at once; reduced-effects mode
	cuts particle counts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local EffectsController = {}

local player = Players.LocalPlayer
local anims = {} -- [padIndex] = { phase, t0, duration, elevation, machineId }
local rigCache = {} -- [model] = { mover, restPivot, coils = { {part, cf} }, ... }
local activeBursts = 0
local facility

local function reduced()
	return ClientState.setting("ReducedEffects") == true
end

-- Pads are numbered across every facility; each slot sits in its facility's LaunchDeck.
local slots = {}
local function machineModel(padIndex)
	local slot = slots[padIndex]
	if not slot or not slot.Parent then
		facility = facility or workspace:FindFirstChild("CrashLabFacility")
		slot = facility and facility:FindFirstChild("PadMachine" .. padIndex, true)
		slots[padIndex] = slot
	end
	return slot and slot:FindFirstChildWhichIsA("Model")
end

local function rigFor(model)
	local rig = rigCache[model]
	if rig then
		return rig
	end
	-- Machines are rebuilt on every claim / machine change: drop rigs of destroyed models.
	for old in pairs(rigCache) do
		if not old.Parent then
			rigCache[old] = nil
		end
	end
	local mover = model:FindFirstChild("Arm") or model:FindFirstChild("Barrel")
	rig = { mover = mover, restPivot = mover and mover:GetPivot(), coils = {}, extras = {} }
	if mover then
		for _, d in ipairs(mover:GetChildren()) do
			if d:IsA("BasePart") and (string.find(d.Name, "^Coil") or d.Name == "Piston") then
				table.insert(rig.coils, { part = d, cf = mover:GetPivot():ToObjectSpace(d.CFrame), piston = d.Name == "Piston" })
			end
		end
	end
	for _, name in ipairs({ "Beacon", "Needle", "Tank" }) do
		rig.extras[name] = model:FindFirstChild(name)
	end
	rig.needleCF = rig.extras.Needle and rig.extras.Needle.CFrame
	rigCache[model] = rig
	return rig
end

-- Angle (radians, about the pivot's X axis) of the moving part for a phase / time.
-- Exposed for tests. Negative = front end up.
function EffectsController.moverAngle(machineId, phase, t, duration, elevation)
	local rest = ({ Standard = -20, Spring = -30, AirCannon = -45 })[machineId] or -20
	local aim = -(elevation or 45)
	if machineId == "Standard" then
		if phase == "Charge" then
			return math.rad(rest + (15 - rest) * math.clamp(t / duration, 0, 1))
		elseif phase == "Fire" then
			if t < 0.15 then
				return math.rad(15 + (-105 - 15) * (t / 0.15))
			end
			return math.rad(-105 + (rest + 105) * math.clamp((t - 0.15) / 0.9, 0, 1))
		end
		return math.rad(rest)
	end
	if phase == "Charge" then
		return math.rad(rest + (aim - rest) * math.clamp(t / math.min(duration, 0.6), 0, 1))
	elseif phase == "Fire" then
		local recoil = if t < 0.12 then 4 * (1 - t / 0.12) else 0
		local back = math.clamp((t - 0.4) / 1.2, 0, 1)
		return math.rad(aim + recoil + (rest - aim) * back)
	end
	return math.rad(rest)
end

local function animate(padIndex, anim, now)
	local model = machineModel(padIndex)
	if not model or model:GetAttribute("Machine") ~= anim.machineId then
		return
	end
	local rig = rigFor(model)
	if not rig.mover then
		return
	end
	local t = now - anim.t0
	local angle = EffectsController.moverAngle(anim.machineId, anim.phase, t, anim.duration, anim.elevation)
	local rest = ({ Standard = -20, Spring = -30, AirCannon = -45 })[anim.machineId] or -20
	-- restPivot already includes the rest rotation; apply the difference.
	local pivot = rig.restPivot * CFrame.Angles(angle - math.rad(rest), 0, 0)
	rig.mover:PivotTo(pivot)
	if anim.machineId == "Spring" then
		local squeeze = if anim.phase == "Charge" then math.clamp(t / anim.duration, 0, 1) elseif anim.phase == "Fire" then math.max(0, 1 - t / 0.08) else 0
		for i, c in ipairs(rig.coils) do
			local offset = if c.piston then -2.4 * squeeze else -squeeze * 0.28 * i
			c.part.CFrame = pivot * CFrame.new(0, 0, offset) * c.cf
		end
	elseif anim.machineId == "AirCannon" then
		local beacon = rig.extras.Beacon
		local light = beacon and beacon:FindFirstChildOfClass("PointLight")
		local on = anim.phase == "Charge" and math.floor(t * 6) % 2 == 0
		if light then
			-- Kept modest so the neon + light stay under the bloom threshold most of the time.
			light.Brightness = if on then 2.5 else 0
		end
		if beacon then
			beacon.Color = if on then Color3.fromRGB(255, 60, 30) else Color3.fromRGB(120, 40, 30)
		end
		if rig.extras.Needle and rig.needleCF then
			local pressure = if anim.phase == "Charge" then math.clamp(t / anim.duration, 0, 1) elseif anim.phase == "Fire" then math.max(0, 1 - t) else 0
			rig.extras.Needle.CFrame = rig.needleCF * CFrame.new(0, -0.2, 0) * CFrame.Angles(-pressure * math.rad(240), 0, 0) * CFrame.new(0, 0.2, 0)
		end
		if anim.phase == "Charge" and math.floor(t * 2) ~= math.floor((t - 1 / 60) * 2) then
			AudioController.play("AirWarning", model:GetPivot().Position)
		end
	end
end

-- Particles -------------------------------------------------------------------------------

local function emitter(props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Speed = props.speed or NumberRange.new(10, 25)
	e.Lifetime = props.lifetime or NumberRange.new(0.4, 0.9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = props.size or NumberSequence.new(0.6, 0)
	e.Color = props.color or ColorSequence.new(Color3.fromRGB(255, 230, 150))
	e.LightEmission = props.light or 0.3
	e.Drag = props.drag or 2
	e.Acceleration = props.accel or Vector3.new(0, -30, 0)
	e.Transparency = NumberSequence.new(0.1, 1)
	return e
end

function EffectsController.burst(position, count, props)
	if not position or activeBursts >= PerformanceConfig.ClientImpactFx then
		return false
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return false
	end
	activeBursts += 1
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = terrain
	local e = emitter(props or {})
	e.Parent = a
	local n = math.max(1, math.floor(count * (if reduced() then PerformanceConfig.ReducedParticles else 1)))
	e:Emit(n)
	task.delay(1.5, function()
		a:Destroy()
		activeBursts -= 1
	end)
	return true
end

-- A low, spreading dust puff where the dummy hits the floor (bigger for harder landings).
local DUST_COUNT = { Light = 8, Medium = 14, Heavy = 22, Massive = 30 }
function EffectsController.dust(position, tier)
	return EffectsController.burst(Vector3.new(position.X, 0.6, position.Z), DUST_COUNT[tier] or 10, {
		color = ColorSequence.new(Color3.fromRGB(196, 186, 170)),
		size = NumberSequence.new(1.2, 3.2),
		speed = NumberRange.new(6, 16),
		lifetime = NumberRange.new(0.6, 1.2),
		accel = Vector3.new(0, 3, 0),
		drag = 4,
		light = 0,
	})
end

local TIER_FX = {
	Light = { 6, { size = NumberSequence.new(0.4, 0), color = ColorSequence.new(Color3.fromRGB(230, 230, 230)) } },
	Medium = { 12, { size = NumberSequence.new(0.7, 0) } },
	Heavy = { 22, { size = NumberSequence.new(1, 0), speed = NumberRange.new(20, 40), color = ColorSequence.new(Color3.fromRGB(255, 200, 80)) } },
	Massive = { 36, { size = NumberSequence.new(1.4, 0), speed = NumberRange.new(30, 60), color = ColorSequence.new(Color3.fromRGB(255, 140, 50)), light = 0.6 } },
}

local LAUNCH_FX = {
	Standard = { 14, { color = ColorSequence.new(Color3.fromRGB(220, 220, 220)), size = NumberSequence.new(1.6, 0), speed = NumberRange.new(4, 10), accel = Vector3.new(0, 4, 0), light = 0 } },
	Confetti = { 40, { color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 60)) }), size = NumberSequence.new(0.5, 0.3), speed = NumberRange.new(20, 40), lifetime = NumberRange.new(1, 1.6) } },
	Fireworks = { 50, { color = ColorSequence.new(Color3.fromRGB(255, 120, 220), Color3.fromRGB(120, 200, 255)), size = NumberSequence.new(0.8, 0), speed = NumberRange.new(40, 70), light = 1, lifetime = NumberRange.new(0.8, 1.4) } },
}

local function onMachineFx(padIndex, machineId, phase, data)
	anims[padIndex] = { phase = phase, t0 = os.clock(), duration = data.time or 1, elevation = data.elevation or 45, machineId = machineId }
	local model = machineModel(padIndex)
	local position = model and model:GetPivot().Position
	local Machine = require(Shared.Config.MachineConfig).ById[machineId]
	if phase == "Charge" and Machine then
		AudioController.play(Machine.Sound.Charge, position)
		if machineId == "AirCannon" then
			AudioController.play("AirHiss", position)
		end
	elseif phase == "Fire" and Machine then
		AudioController.play(Machine.Sound.Fire, position, true)
		local fx = LAUNCH_FX[data.fx or "Standard"] or LAUNCH_FX.Standard
		if position then
			EffectsController.burst(position + Vector3.new(0, 6, 4), fx[1], fx[2])
		end
	end
end

local function onRunEvent(userId, kind, data)
	local mine = userId == player.UserId
	if kind == "Impact" then
		AudioController.impact(data.tier, if mine then nil else data.position, data.soft, data.metal)
		local fx = TIER_FX[data.tier]
		if fx then
			EffectsController.burst(data.position, fx[1], fx[2])
		end
		if data.floor and data.position then
			EffectsController.dust(data.position, data.tier)
		end
	elseif kind == "Prop" then
		local def = CourseConfig.DestructibleKinds[data.kind]
		AudioController.play(def and def.Sound or "BoxCrunch", data.position)
		EffectsController.burst(data.position, 18, { color = ColorSequence.new(if def then Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3]) else Color3.new(1, 1, 1)), size = NumberSequence.new(0.9, 0) })
	elseif kind == "Ring" then
		AudioController.play("RingPass", data.position, true)
		EffectsController.burst(data.position, 30, { color = ColorSequence.new(Color3.fromRGB(120, 255, 160)), light = 1, speed = NumberRange.new(15, 30) })
	elseif kind == "Target" then
		AudioController.play(if data.id == "Gong" then "GongHit" else "ImpactMetal", data.position, true)
		EffectsController.burst(data.position, 24, { color = ColorSequence.new(Color3.fromRGB(255, 90, 70)), light = 0.5 })
	elseif kind == "Marker" and mine then
		AudioController.play("Countdown", nil, true)
	elseif kind == "Wind" and mine then
		AudioController.play("WindGust", nil, true)
		EffectsController.burst(data.position, 10, { color = ColorSequence.new(Color3.fromRGB(235, 245, 255)), size = NumberSequence.new(1.4, 0), speed = NumberRange.new(20, 40), lifetime = NumberRange.new(0.4, 0.8) })
	elseif kind == "Gravity" or kind == "Flip" then
		AudioController.play("GravityShift", if mine then nil else data.position, true)
		EffectsController.burst(data.position, 22, { color = ColorSequence.new(Color3.fromRGB(80, 240, 255), Color3.fromRGB(190, 110, 255)), light = 1, speed = NumberRange.new(6, 16), accel = Vector3.new(0, 8, 0) })
	elseif kind == "Bounce" then
		AudioController.play("BounceField", data.position, true)
		EffectsController.burst(data.position, 26, { color = ColorSequence.new(Color3.fromRGB(190, 110, 255)), light = 1, speed = NumberRange.new(20, 34), accel = Vector3.new(0, 20, 0) })
	end
end

-- Ambient motion --------------------------------------------------------------------------

local fans
local function findFans()
	facility = facility or workspace:FindFirstChild("CrashLabFacility")
	local arena = facility and facility:FindFirstChild("Arena")
	if not arena then
		return {}
	end
	local list, byId = {}, {}
	for _, d in ipairs(arena:GetChildren()) do
		local id = d:GetAttribute("Fan")
		if id and d.Name == "FanHub" then
			byId[id] = { hub = d, base = d.CFrame, blades = {}, angle = 0 }
			table.insert(list, byId[id])
		end
	end
	for _, d in ipairs(arena:GetChildren()) do
		local id = d:GetAttribute("Fan")
		if id and d.Name == "FanBlade" and byId[id] then
			table.insert(byId[id].blades, { part = d, offset = byId[id].base:ToObjectSpace(d.CFrame) })
		end
	end
	return list
end

function EffectsController.stepMachines(now)
	for padIndex, anim in pairs(anims) do
		animate(padIndex, anim, now)
		if anim.phase ~= "Charge" and now - anim.t0 > 2 then
			anims[padIndex] = nil
		end
	end
end

function EffectsController.step(dt)
	local now = os.clock()
	EffectsController.stepMachines(now)
	fans = fans or findFans()
	for _, fan in ipairs(fans) do
		fan.angle += dt * 4
		local cf = fan.base * CFrame.Angles(fan.angle, 0, 0)
		for _, b in ipairs(fan.blades) do
			b.part.CFrame = cf * b.offset
		end
	end
	facility = facility or workspace:FindFirstChild("CrashLabFacility")
	local deck = facility and facility:FindFirstChild("LaunchDeck")
	local lights = deck and deck:FindFirstChild("DeckLights")
	local anyCharging = false
	for _, anim in pairs(anims) do
		if anim.phase == "Charge" then
			anyCharging = true
		end
	end
	if lights then
		lights.Color = if anyCharging and math.floor(now * 4) % 2 == 0 then Color3.fromRGB(255, 60, 40) else Color3.fromRGB(120, 30, 25)
	end
end

function EffectsController.init()
	ClientState.MachineFx:Connect(onMachineFx)
	ClientState.RunEvent:Connect(onRunEvent)
	ClientState.Results:Connect(function(r)
		if r.records and r.records.BestScore then
			local root = ClientState.root()
			if root then
				EffectsController.burst(root.Position + Vector3.new(0, 4, 0), 40, LAUNCH_FX.Confetti[2])
			end
		end
	end)
	RunService.RenderStepped:Connect(EffectsController.step)
end

return EffectsController
