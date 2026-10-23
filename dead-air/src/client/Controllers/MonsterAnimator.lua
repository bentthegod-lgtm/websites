--[[
	MonsterAnimator - procedural animation for THE LISTENER (no animation assets needed).

	Reads the server-replicated State/Listening attributes and root velocity:
	  walk    long loping strides, arms dangling and swaying
	  listen  freezes, head tilts and twitches, ear fins fan wide open
	  chase   pitched forward, arms swept back, frantic stride
	  attack  arms thrown forward, fins flare
	Motor6D.Transform is set every frame on the client only, so it costs no network.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MonsterAnimator = {}

local rig -- { model, root, motors = {name = Motor6D}, phase, twitch... }

local function bind(model)
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	rig = {
		model = model,
		root = model:WaitForChild("HumanoidRootPart", 5),
		mouth = model:FindFirstChild("Mouth"),
		motors = motors,
		phase = 0,
		fin = 0,
		lean = 0,
		armBack = 0,
		armForward = 0,
		twitchUntil = 0,
		twitch = CFrame.new(),
		nextTwitch = os.clock() + 2,
	}
end

local function set(name, cf)
	local m = rig.motors[name]
	if m then
		m.Transform = cf
	end
end

local function approach(current, target, rate, dt)
	return current + (target - current) * math.min(1, rate * dt)
end

local function step(dt)
	if not rig or not rig.model.Parent or not rig.root then
		rig = nil
		return
	end
	local camera = Workspace.CurrentCamera
	if (rig.root.Position - camera.CFrame.Position).Magnitude > 160 then
		return
	end
	local model = rig.model
	local state = model:GetAttribute("State") or "Patrol"
	local listening = model:GetAttribute("Listening") == true
	local v = rig.root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local now = os.clock()

	local chasing = state == "Chase" or state == "Lost"
	local attacking = state == "Attack"
	rig.phase += dt * (speed * 0.42 + 0.2)
	local p = rig.phase
	local stride = math.clamp(speed / 14, 0, 1.25)

	rig.lean = approach(rig.lean, if chasing then -0.55 elseif attacking then -0.3 else 0, 6, dt)
	rig.armBack = approach(rig.armBack, if chasing then 1 else 0, 5, dt)
	rig.armForward = approach(rig.armForward, if attacking then 1 else 0, 12, dt)
	local finTarget = if attacking then 1.1 elseif listening or state == "Suspicion" or state == "Investigate" then 0.9 else 0.1
	rig.fin = approach(rig.fin, finTarget, 4, dt)

	-- Legs
	local swing = math.sin(p) * 0.75 * stride
	set("HipL", CFrame.Angles(swing, 0, 0))
	set("HipR", CFrame.Angles(-swing, 0, 0))
	set("KneeL", CFrame.Angles(-math.max(0, math.sin(p + 1.2)) * 1.1 * stride, 0, 0))
	set("KneeR", CFrame.Angles(-math.max(0, math.sin(p + 1.2 + math.pi)) * 1.1 * stride, 0, 0))

	-- Torso: lean + idle sway + bob
	local sway = math.sin(now * 0.9) * 0.05
	set("Waist", CFrame.new(0, math.abs(math.sin(p)) * 0.15 * stride, 0) * CFrame.Angles(rig.lean + sway * 0.5, math.sin(p) * 0.08 * stride, sway))

	-- Arms: dangle and swing, swept back in chase, thrown forward in attack
	local armSwing = -swing * 0.5
	for _, side in ipairs({ "L", "R" }) do
		local sign = if side == "L" then 1 else -1
		local a = armSwing * sign
		local back = rig.armBack * 0.9
		local forward = rig.armForward * -1.9
		set("Shoulder" .. side, CFrame.Angles(a + back + forward, 0, sign * (0.05 + rig.armBack * 0.25)))
		set("Elbow" .. side, CFrame.Angles(-0.2 - rig.armBack * 0.6 + math.sin(now * 3 + sign) * 0.05, 0, 0))
		set("Wrist" .. side, CFrame.Angles(math.sin(now * 2.3 + sign) * 0.15, 0, 0))
	end

	-- Head: twitches while listening, stretched forward while chasing
	if now >= rig.nextTwitch then
		rig.nextTwitch = now + (if listening then 0.4 + math.random() * 0.8 else 2 + math.random() * 4)
		rig.twitchUntil = now + 0.12
		rig.twitch = CFrame.Angles((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.9, (math.random() - 0.5) * 0.8)
	end
	local tilt = if listening then CFrame.Angles(0.25, 0, math.sin(now * 1.3) * 0.35) else CFrame.new()
	local headCF = tilt * (if now < rig.twitchUntil then rig.twitch else CFrame.new())
	if chasing then
		headCF = CFrame.Angles(-0.35, 0, 0) * headCF
	end
	set("NeckJoint", CFrame.Angles(rig.lean * 0.3, 0, 0))
	set("HeadJoint", headCF)

	-- Ear fins fan open
	local flutter = math.sin(now * 14) * 0.04 * rig.fin
	set("FinLJoint", CFrame.Angles(0, -rig.fin * 0.35, rig.fin * 0.8 + flutter))
	set("FinRJoint", CFrame.Angles(0, rig.fin * 0.35, -rig.fin * 0.8 - flutter))

	if rig.mouth then
		rig.mouth.Color = if chasing or attacking then Color3.fromRGB(70, 12, 10) else Color3.fromRGB(18, 10, 10)
	end
end

function MonsterAnimator.init()
	local existing = Workspace:FindFirstChild("TheListener")
	if existing then
		task.spawn(bind, existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "TheListener" and child:IsA("Model") then
			task.defer(bind, child)
		end
	end)
	RunService.Stepped:Connect(function(_, dt)
		if rig then
			step(dt)
		end
	end)
end

return MonsterAnimator
