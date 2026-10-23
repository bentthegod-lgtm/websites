--[[
	JumpscareController - what you see when the Listener catches you.

	A local copy of the creature lunges into your face, lit red from below, while the camera
	locks and shakes, the screen strobes red and the jumpscare cue plays. Then it cuts to
	black and fades back into the downed / death view. "Reduce flicker" swaps the strobe for
	a single flash; "Camera shake" off keeps the view steady.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local Settings = require(script.Parent.Settings)
local CameraController = require(script.Parent.CameraController)

local JumpscareController = {}

local player = Players.LocalPlayer
local overlay, caption
local playing = false

local LUNGE_TIME = 0.16
local HOLD_TIME = 1.25

-- Builds an anchored, local-only copy of the creature for the scare.
local function makeFigure()
	local source = ClientState.monster()
	if not source then
		return nil
	end
	local ok, figure = pcall(function()
		source.Archivable = true
		return source:Clone()
	end)
	if not ok or not figure then
		return nil
	end
	for _, d in ipairs(figure:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("Sound") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	local head = figure:FindFirstChild("Head")
	if not head then
		figure:Destroy()
		return nil
	end
	local mouth = figure:FindFirstChild("Mouth")
	if mouth then
		mouth.Color = Color3.fromRGB(200, 20, 10)
		mouth.Material = Enum.Material.Neon
	end
	local red = Instance.new("PointLight")
	red.Color = Color3.fromRGB(255, 40, 20)
	red.Brightness = 6
	red.Range = 14
	red.Parent = head
	return figure, head
end

local function finish(figure, connection)
	connection:Disconnect()
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0
	if figure then
		figure:Destroy()
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	CameraController.locked = false
	CameraController.refresh()
	caption.Text = if ClientState.status() == "Dead" then "YOU WERE HEARD" else ""
	caption.TextTransparency = 0
	task.wait(0.9)
	TweenService:Create(overlay, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(caption, TweenInfo.new(1.4), { TextTransparency = 1 }):Play()
	task.wait(1.4)
	playing = false
end

function JumpscareController.play()
	if playing then
		return
	end
	playing = true
	local camera = Workspace.CurrentCamera
	local startCF = camera.CFrame
	local figure, head = makeFigure()
	local headOffset
	if figure then
		figure.Parent = camera
		headOffset = figure:GetPivot():ToObjectSpace(head.CFrame)
	end

	CameraController.locked = true
	camera.CameraType = Enum.CameraType.Scriptable
	AudioUtil.cue2D(AudioAssets.Jumpscare, "SFX")

	local strobe = not Settings.get("ReduceFlicker")
	local shake = if Settings.get("CameraShake") then 1 else 0.15
	if not strobe then
		overlay.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
		overlay.BackgroundTransparency = 0.45
		TweenService:Create(overlay, TweenInfo.new(HOLD_TIME), { BackgroundTransparency = 1 }):Play()
	end

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t >= HOLD_TIME then
			task.spawn(finish, figure, connection)
			return
		end
		local n = os.clock() * 35
		local violence = shake * (if t < 0.5 then 1 else 0.6)
		camera.CFrame = startCF * CFrame.Angles(math.noise(n, 1) * 0.06 * violence, math.noise(n, 2) * 0.06 * violence, math.noise(n, 3) * 0.04 * violence)
		if figure then
			local k = math.clamp(t / LUNGE_TIME, 0, 1)
			local eased = 1 - (1 - k) ^ 3
			local distance = 3.6 + (1.15 - 3.6) * eased
			local twitch = CFrame.Angles(math.noise(n, 4) * 0.3, math.noise(n, 5) * 0.25, math.noise(n, 6) * 0.45)
			local headCF = startCF * CFrame.new(math.noise(n, 7) * 0.08, -0.2, -distance) * CFrame.Angles(0, math.pi, 0) * twitch
			figure:PivotTo(headCF * headOffset:Inverse())
		end
		if strobe then
			local on = math.floor(t * 18) % 2 == 0 and t < 0.7
			overlay.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
			overlay.BackgroundTransparency = if on then 0.35 else 1
		end
	end)
end

function JumpscareController.init()
	local gui = Ui.screen("DeadAirJumpscare", player:WaitForChild("PlayerGui"), 60)
	overlay = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	caption = Ui.new("TextLabel", {
		Text = "",
		Font = Ui.Fonts.Title,
		TextSize = 44,
		TextColor3 = Ui.Colors.Danger,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 60),
		Parent = gui,
	})
	ClientState.MonsterCue:Connect(function(cue)
		if cue == "Caught" then
			JumpscareController.play()
		elseif cue == "Spotted" then
			-- It has seen you: a sting only you hear.
			AudioUtil.cue2D(AudioAssets.SpottedSting, "SFX")
		end
	end)
end

return JumpscareController
