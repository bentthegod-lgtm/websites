--[[
	TeacherController - makes the teacher (and the principal) feel alive on the client:

	  * smooths the server's position / heading (attributes X, Z, Heading on the model),
	  * procedural joint animation per Pose (Write, Pause, Glance, Lecture, Walk, Quiz, Point,
	    Distracted, Panic, Door, Nap, Arms) by setting Motor6D.Transform,
	  * a floor vision cone that shows where she is looking (tinted by YOUR suspicion),
	  * the "?" / "!" over her head (your own suspicion, from the server),
	  * a "..." thought bubble when she pauses writing (she's about to glance back!),
	  * the wall clock hands.

	All of this is visual. What she can actually see is decided by the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local Clock = require(Shared.Clock)

local ClientState = require(script.Parent.ClientState)

local TeacherController = {}

local player = Players.LocalPlayer
local rigs = {} -- [model] = { smooth = {x,z,h}, cone, mark, bubble }
local coneFolder
local lastMark = ""

local function angles(x, y, z)
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Joint poses: { RootJoint, Neck, LeftShoulder, RightShoulder, LeftHip, RightHip } as
-- functions of time t -> CFrame.
local POSES = {}

function POSES.Write(t)
	local scribble = math.sin(t * 9) * 6
	return { Neck = angles(8, 0, 0), RightShoulder = angles(150 + scribble, 0, -10), LeftShoulder = angles(10, 0, 8) }
end

function POSES.Pause()
	return { Neck = angles(-4, 20, 0), RightShoulder = angles(140, 0, -10), LeftShoulder = angles(10, 0, 8) }
end

function POSES.Glance(t)
	return { Neck = angles(0, 25 + math.sin(t * 2) * 5, 0), RightShoulder = angles(90, 0, -10), LeftShoulder = angles(5, 0, 6) }
end

function POSES.Lecture(t)
	local gesture = math.sin(t * 2.2)
	return {
		RightShoulder = angles(40 + gesture * 25, 0, -15),
		LeftShoulder = angles(25 - gesture * 15, 0, 15),
		Neck = angles(0, math.sin(t * 0.9) * 10, 0),
	}
end

function POSES.Walk(t)
	local s = math.sin(t * 7.5)
	return {
		LeftHip = angles(s * 28, 0, 0),
		RightHip = angles(-s * 28, 0, 0),
		LeftShoulder = angles(-s * 22, 0, 4),
		RightShoulder = angles(s * 22, 0, -4),
		RootJoint = CFrame.new(0, math.abs(s) * 0.12, 0),
		Neck = angles(0, math.sin(t * 1.3) * 25, 0), -- scanning desks
	}
end

function POSES.Quiz()
	return { RightShoulder = angles(60, 0, -40), LeftShoulder = angles(60, 0, 40), Neck = angles(-5, 0, 0) }
end

function POSES.Arms(t)
	return { RightShoulder = angles(55, 0, -50), LeftShoulder = angles(55, 0, 50), Neck = angles(0, math.sin(t * 0.6) * 20, 0) }
end

function POSES.Point(t)
	return { RightShoulder = angles(95, 0, 0), LeftShoulder = angles(15, 0, 20), Neck = angles(-6, 0, 0), RootJoint = CFrame.new(0, 0, -0.1) * angles(-5 + math.sin(t * 12) * 1.5, 0, 0) }
end

function POSES.Distracted(t)
	return { Neck = angles(0, math.sin(t * 3) * 8, 0), RightShoulder = angles(20, 0, -30), LeftShoulder = angles(20, 0, 30), RootJoint = angles(-4, 0, 0) }
end

function POSES.Panic(t)
	local s = math.sin(t * 10)
	return {
		RightShoulder = angles(160 + s * 15, 0, -20),
		LeftShoulder = angles(160 - s * 15, 0, 20),
		LeftHip = angles(s * 20, 0, 0),
		RightHip = angles(-s * 20, 0, 0),
		Neck = angles(0, s * 30, 0),
	}
end

function POSES.Door()
	return { RootJoint = angles(-8, 0, 0), Neck = angles(10, 0, 0), RightShoulder = angles(70, 0, 0), LeftShoulder = angles(5, 0, 5) }
end

function POSES.Nap(t)
	return { Neck = angles(28 + math.sin(t * 1.2) * 4, 0, 10), RightShoulder = angles(5, 0, -4), LeftShoulder = angles(5, 0, 4), RootJoint = angles(math.sin(t * 1.2) * 2, 0, 0) }
end

local JOINTS = { "RootJoint", "Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip" }

local function findJoints(model)
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and table.find(JOINTS, d.Name) then
			joints[d.Name] = d
		end
	end
	return joints
end

local function makeWedge(name, color)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Material = Enum.Material.Neon
	w.Color = color
	w.Transparency = 0.85
	w.Parent = coneFolder
	return w
end

local function markGui(model)
	local head = model:FindFirstChild("Head")
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PA_Mark"
	gui.Size = UDim2.fromOffset(80, 80)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local bubble = Instance.new("TextLabel")
	bubble.Name = "Bubble"
	bubble.BackgroundColor3 = Color3.new(1, 1, 1)
	bubble.BackgroundTransparency = 0.1
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.fromScale(0.5, 1)
	bubble.Size = UDim2.fromOffset(56, 30)
	bubble.Font = Enum.Font.FredokaOne
	bubble.TextSize = 24
	bubble.Text = "..."
	bubble.TextColor3 = Color3.fromRGB(40, 40, 60)
	bubble.Visible = false
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = bubble
	gui.Parent = player:FindFirstChildOfClass("PlayerGui") or head
	return gui
end

local function track(model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not root then
		return
	end
	local role = model:GetAttribute("Role") or "Teacher"
	rigs[model] = {
		root = root,
		joints = findJoints(model),
		smooth = { x = model:GetAttribute("X") or root.Position.X, z = model:GetAttribute("Z") or root.Position.Z, h = model:GetAttribute("Heading") or 0 },
		coneA = makeWedge(role .. "ConeA", Color3.fromRGB(120, 255, 160)),
		coneB = makeWedge(role .. "ConeB", Color3.fromRGB(120, 255, 160)),
		gui = markGui(model),
		role = role,
	}
end

local function lerpAngle(a, b, alpha)
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * alpha
end

local function coneColor()
	local s = ClientState.suspicion
	if s >= TeacherConfig.Suspicion.Alert then
		return Color3.fromRGB(255, 70, 70)
	elseif s >= TeacherConfig.Suspicion.Question then
		return Color3.fromRGB(255, 210, 60)
	end
	return Color3.fromRGB(120, 255, 160)
end

local function updateCone(rig, x, z, h, model)
	local fov = math.rad(model:GetAttribute("Fov") or TeacherConfig.Sight.FovDegrees)
	local range = (model:GetAttribute("Range") or TeacherConfig.Sight.Range) * 0.55
	local sight = model:GetAttribute("Sight") or 0
	local visible = sight > 0.05 and ClientState.roundState == "Class"
	local halfWidth = math.tan(fov) * range
	local origin = Vector3.new(x, 0.08, z)
	local forward = Vector3.new(math.sin(h), 0, math.cos(h))
	local right = forward:Cross(Vector3.new(0, 1, 0))
	local color = coneColor()
	-- Two right-angle wedges mirrored around the gaze line make the triangle. A wedge's
	-- right angle sits at local (-Y/2, +Z/2): map it to the far end of the gaze line, its
	-- local +Z to "forward" and its local +Y to one side.
	for i, wedge in ipairs({ rig.coneA, rig.coneB }) do
		local side = if i == 1 then 1 else -1
		local vY = right * side
		local vZ = forward
		local vX = vY:Cross(vZ)
		local pos = origin + forward * (range / 2) + vY * (halfWidth / 2)
		wedge.Size = Vector3.new(0.05, halfWidth, range)
		wedge.CFrame = CFrame.fromMatrix(pos, vX, vY, vZ)
		wedge.Color = color
		wedge.Transparency = if visible then 0.82 - math.min(0.25, sight * 0.2) else 1
	end
end

local function animate(rig, model, t)
	local pose = model:GetAttribute("Pose") or "Write"
	local fn = POSES[pose] or POSES.Lecture
	local targets = fn(t)
	rig.current = rig.current or {}
	for _, name in ipairs(JOINTS) do
		local joint = rig.joints[name]
		if joint then
			local goal = targets[name] or CFrame.new()
			local cur = (rig.current[name] or CFrame.new()):Lerp(goal, 0.25)
			rig.current[name] = cur
			joint.Transform = cur
		end
	end
end

local function updateClock()
	local school = workspace:FindFirstChild("School")
	local room = school and school:FindFirstChild("Classroom")
	local clock = room and room:FindFirstChild("WallClock")
	if not clock then
		return
	end
	local face = clock:FindFirstChild("Center")
	local hour, minute = clock:FindFirstChild("HourHand"), clock:FindFirstChild("MinuteHand")
	if not face or not hour or not minute then
		return
	end
	local start = workspace:GetAttribute("PA_ClassStart") or 0
	local duration = workspace:GetAttribute("PA_ClassDuration") or GameConfig.ClassSeconds
	local t = if ClientState.roundState == "Class" then math.clamp(Clock.now() - start, 0, duration) else 0
	local minutes = GameConfig.SchoolClockStart + (GameConfig.SchoolClockEnd - GameConfig.SchoolClockStart) * (t / duration)
	local center = face.CFrame * CFrame.new(0, 0, -0.04)
	local minuteAngle = (minutes % 60) / 60 * math.pi * 2
	local hourAngle = ((minutes / 60) % 12) / 12 * math.pi * 2
	minute.CFrame = center * CFrame.Angles(0, 0, -minuteAngle) * CFrame.new(0, minute.Size.Y / 2, 0)
	hour.CFrame = center * CFrame.Angles(0, 0, -hourAngle) * CFrame.new(0, hour.Size.Y / 2, 0)
end

function TeacherController.step(dt)
	local t = os.clock()
	local alpha = 1 - math.exp(-10 * dt)
	for model, rig in pairs(rigs) do
		if not model.Parent then
			if rig.gui then
				rig.gui:Destroy()
			end
			rig.coneA:Destroy()
			rig.coneB:Destroy()
			rigs[model] = nil
		else
			local tx, tz, th = model:GetAttribute("X"), model:GetAttribute("Z"), model:GetAttribute("Heading")
			if tx and tz and th then
				local s = rig.smooth
				-- Snap on big jumps (teleport to the hallway etc.)
				if math.abs(tx - s.x) + math.abs(tz - s.z) > 12 then
					s.x, s.z, s.h = tx, tz, th
				end
				s.x += (tx - s.x) * alpha
				s.z += (tz - s.z) * alpha
				s.h = lerpAngle(s.h, th, alpha)
				local y = model:GetAttribute("LegH") or 2.6
				rig.root.CFrame = CFrame.new(s.x, y, s.z) * CFrame.Angles(0, s.h + math.pi, 0)
				updateCone(rig, s.x, s.z, s.h, model)
			end
			animate(rig, model, t)
			if rig.gui then
				local mark = rig.gui:FindFirstChild("Mark")
				local bubble = rig.gui:FindFirstChild("Bubble")
				local inClass = ClientState.roundState == "Class" and ClientState.status() == "Seated"
				local m = if inClass and rig.role == "Teacher" then ClientState.mark else ""
				mark.Text = m
				mark.TextColor3 = if m == "!" then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 215, 60)
				mark.Rotation = if m ~= "" then math.sin(t * 14) * (if m == "!" then 10 else 4) else 0
				bubble.Visible = inClass and m == "" and model:GetAttribute("Warn") == true
				if rig.role == "Teacher" and m ~= lastMark then
					if m == "?" then
						AudioUtil.play(AudioAssets.Suspicious)
					elseif m == "!" then
						AudioUtil.play(AudioAssets.Alert)
					end
					lastMark = m
				end
			end
		end
	end
	updateClock()
end

function TeacherController.init()
	coneFolder = Instance.new("Folder")
	coneFolder.Name = "PA_VisionCones"
	coneFolder.Parent = workspace
	task.spawn(function()
		local school = workspace:WaitForChild("School", 30)
		local npcs = school and school:WaitForChild("NPCs", 30)
		if not npcs then
			return
		end
		for _, model in ipairs(npcs:GetChildren()) do
			track(model)
		end
		npcs.ChildAdded:Connect(function(model)
			task.wait(0.2)
			track(model)
		end)
	end)
	RunService.RenderStepped:Connect(TeacherController.step)
end

TeacherController._rigs = rigs
TeacherController._poses = POSES

return TeacherController
