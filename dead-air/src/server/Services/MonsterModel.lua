--[[
	MonsterModel - builds THE LISTENER from Parts.

	Silhouette: ~11 studs tall, emaciated, hunched forward, with arms long enough to drag
	near the floor and three-fingered hands. It has no eyes. Its narrow skull carries two
	tall membranous "ear fins" that fan open when it listens - the shape players learn to
	recognise at the end of a hallway. Skin is the same washed-out beige as the walls.

	The rig uses Motor6Ds so clients can animate it procedurally (MonsterAnimator) without
	any uploaded animation assets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MonsterConfig = require(Shared.Config.MonsterConfig)

local MonsterModel = {}

local function rgb(list)
	return Color3.fromRGB(list[1], list[2], list[3])
end

-- floorY: height of the floor the creature stands on (defaults to the facility floor, 0).
function MonsterModel.build(spawnCFrame, floorY)
	local skin = rgb(MonsterConfig.SkinColor)
	local finColor = rgb(MonsterConfig.FinColor)
	local model = Instance.new("Model")
	model.Name = "TheListener"

	local hipHeight = 6 -- root centre above the floor
	local base = spawnCFrame - spawnCFrame.Position + Vector3.new(spawnCFrame.X, floorY or 0, spawnCFrame.Z)
	local rootCF = base * CFrame.new(0, hipHeight, 0)

	local function part(name, size, cf, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = skin
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if props then
			for k, v in pairs(props) do
				p[k] = v
			end
		end
		p.Parent = model
		return p
	end

	local function joint(name, part0, part1, jointCF)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = part0.CFrame:Inverse() * jointCF
		m.C1 = part1.CFrame:Inverse() * jointCF
		m.Parent = part0
		return m
	end

	local function weld(part0, part1)
		local w = Instance.new("WeldConstraint")
		w.Part0 = part0
		w.Part1 = part1
		w.Parent = part1
	end

	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1.2), rootCF, {
		Transparency = 1,
		CanCollide = true,
		Massless = false,
		CastShadow = false,
	})

	-- Torso (hunched)
	local waistCF = rootCF * CFrame.new(0, 0.3, 0)
	local torsoCF = waistCF * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 1.5, 0)
	local torso = part("Torso", Vector3.new(1.25, 3.0, 0.7), torsoCF)
	joint("Waist", root, torso, waistCF)
	-- Visible ribs: thin darker bands
	for i = 1, 3 do
		local rib = part("Rib" .. i, Vector3.new(1.3, 0.08, 0.72), torsoCF * CFrame.new(0, 0.2 + i * 0.35, 0), { Color = skin:Lerp(Color3.new(0, 0, 0), 0.3) })
		weld(torso, rib)
	end
	local pelvis = part("Pelvis", Vector3.new(1.1, 0.7, 0.6), rootCF * CFrame.new(0, -0.1, 0))
	weld(root, pelvis)

	-- Neck & head
	local neckJointCF = torsoCF * CFrame.new(0, 1.5, 0)
	local neckCF = neckJointCF * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0.5, 0)
	local neck = part("Neck", Vector3.new(0.32, 1.0, 0.32), neckCF)
	joint("NeckJoint", torso, neck, neckJointCF)
	local headJointCF = neckCF * CFrame.new(0, 0.5, 0)
	local headCF = headJointCF * CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, 0.85, -0.15)
	local head = part("Head", Vector3.new(0.85, 1.8, 1.25), headCF)
	joint("HeadJoint", neck, head, headJointCF)
	-- The mouth: a long vertical slit where a face should be.
	local mouth = part("Mouth", Vector3.new(0.14, 1.15, 0.06), headCF * CFrame.new(0, -0.15, -0.63), {
		Color = Color3.fromRGB(18, 10, 10),
		CastShadow = false,
	})
	weld(head, mouth)
	-- Ear fins
	for _, side in ipairs({ -1, 1 }) do
		local finJointCF = headCF * CFrame.new(side * 0.42, 0.25, 0.1)
		local finCF = finJointCF * CFrame.Angles(0, 0, math.rad(-side * 18)) * CFrame.new(side * 0.05, 0.75, 0.1)
		local fin = part(if side < 0 then "FinL" else "FinR", Vector3.new(0.06, 2.1, 1.5), finCF, {
			Color = finColor,
			Transparency = 0.12,
			Material = Enum.Material.SmoothPlastic,
		})
		joint(if side < 0 then "FinLJoint" else "FinRJoint", head, fin, finJointCF)
	end

	-- Arms
	for _, side in ipairs({ -1, 1 }) do
		local suffix = if side < 0 then "L" else "R"
		local shoulderCF = torsoCF * CFrame.new(side * 0.8, 1.25, 0)
		local upperCF = shoulderCF * CFrame.Angles(0, 0, math.rad(side * 8)) * CFrame.new(0, -1.5, 0)
		local upper = part("UpperArm" .. suffix, Vector3.new(0.3, 3.0, 0.3), upperCF)
		joint("Shoulder" .. suffix, torso, upper, shoulderCF)
		local elbowCF = upperCF * CFrame.new(0, -1.5, 0)
		local foreCF = elbowCF * CFrame.Angles(math.rad(-10), 0, 0) * CFrame.new(0, -1.6, 0)
		local fore = part("Forearm" .. suffix, Vector3.new(0.24, 3.2, 0.24), foreCF)
		joint("Elbow" .. suffix, upper, fore, elbowCF)
		local wristCF = foreCF * CFrame.new(0, -1.6, 0)
		local handCF = wristCF * CFrame.new(0, -0.4, 0)
		local hand = part("Hand" .. suffix, Vector3.new(0.4, 0.8, 0.2), handCF)
		joint("Wrist" .. suffix, fore, hand, wristCF)
		for f = -1, 1 do
			local finger = part("Finger" .. suffix .. f, Vector3.new(0.07, 1.5, 0.07), handCF * CFrame.new(f * 0.14, -1.1, 0) * CFrame.Angles(math.rad(-8), 0, math.rad(f * 6)), {
				Color = skin:Lerp(Color3.new(0, 0, 0), 0.2),
			})
			weld(hand, finger)
		end
	end

	-- Legs (digitigrade-ish: knees bent back slightly)
	for _, side in ipairs({ -1, 1 }) do
		local suffix = if side < 0 then "L" else "R"
		local hipCF = rootCF * CFrame.new(side * 0.42, 0, 0)
		local thighCF = hipCF * CFrame.Angles(math.rad(10), 0, 0) * CFrame.new(0, -1.45, 0)
		local thigh = part("Thigh" .. suffix, Vector3.new(0.38, 2.9, 0.38), thighCF)
		joint("Hip" .. suffix, root, thigh, hipCF)
		local kneeCF = thighCF * CFrame.new(0, -1.45, 0)
		local shinCF = kneeCF * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, -1.4, 0)
		local shin = part("Shin" .. suffix, Vector3.new(0.3, 2.8, 0.3), shinCF)
		joint("Knee" .. suffix, thigh, shin, kneeCF)
		local ankleCF = shinCF * CFrame.new(0, -1.4, 0)
		local foot = part("Foot" .. suffix, Vector3.new(0.42, 0.22, 1.2), ankleCF * CFrame.Angles(math.rad(8), 0, 0) * CFrame.new(0, -0.1, -0.35))
		joint("Ankle" .. suffix, shin, foot, ankleCF)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight - root.Size.Y / 2
	humanoid.WalkSpeed = 8
	humanoid.AutoRotate = true
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.Parent = model
	for _, stateType in ipairs({
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Dead,
	}) do
		humanoid:SetStateEnabled(stateType, false)
	end

	model.PrimaryPart = root
	model:SetAttribute("State", "Patrol")
	return model, root, humanoid, head
end

return MonsterModel
