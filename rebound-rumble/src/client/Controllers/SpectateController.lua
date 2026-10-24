--[[
	SpectateController - eliminated players (and lobby players during a round) can watch
	the action. By default the camera follows whoever the ball is hunting; the arrows /
	D-pad (or on-screen buttons) cycle through the players still alive.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local SpectateController = {
	active = false,
	followBall = true,
	index = 1,
}

local player = Players.LocalPlayer
local C = Ui.Colors
local bar, nameLabel, toggleButton, followButton

local function aliveList()
	local list = {}
	for _, c in ipairs(ClientState.roster) do
		if c.alive and c.id ~= ClientState.myId() then
			table.insert(list, c)
		end
	end
	return list
end

local function canSpectate()
	return ClientState.matchState == "Playing" and ClientState.status() ~= "Arena"
end

local function resetCamera()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

local function watch(entry)
	local camera = workspace.CurrentCamera
	local model = entry and ClientState.modelFor(entry.id)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
		nameLabel.Text = string.format("WATCHING  %s%s  (%d kills)%s", entry.name, if entry.isBot then " [BOT]" else "", entry.kills or 0, if SpectateController.followBall then "  - following the ball" else "")
	end
end

function SpectateController.refresh()
	local allowed = canSpectate()
	bar.Visible = allowed
	if not allowed then
		if SpectateController.active then
			SpectateController.active = false
			resetCamera()
		end
		return
	end
	toggleButton.Text = if SpectateController.active then "STOP WATCHING" else "SPECTATE"
	followButton.Text = if SpectateController.followBall then "FOLLOW BALL: ON" else "FOLLOW BALL: OFF"
	nameLabel.Visible = SpectateController.active
	if not SpectateController.active then
		return
	end
	local list = aliveList()
	if #list == 0 then
		nameLabel.Text = "Nobody left to watch"
		return
	end
	local entry
	if SpectateController.followBall then
		entry = ClientState.entry(ClientState.ball and ClientState.ball.t)
		if entry and not entry.alive then
			entry = nil
		end
	end
	if not entry then
		SpectateController.index = ((SpectateController.index - 1) % #list) + 1
		entry = list[SpectateController.index]
	end
	watch(entry)
end

function SpectateController.cycle(delta)
	SpectateController.followBall = false
	SpectateController.index += delta
	SpectateController.refresh()
end

function SpectateController.setActive(on)
	SpectateController.active = on and canSpectate()
	if not SpectateController.active then
		resetCamera()
	end
	SpectateController.refresh()
end

function SpectateController.init()
	local gui = Ui.screen("RR_Spectate", player:WaitForChild("PlayerGui"), 3)
	bar = Ui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60), Size = UDim2.fromOffset(560, 92), BackgroundTransparency = 0.25, Visible = false, Parent = gui })
	Ui.stroke(bar, C.Accent2, 0.3, 2)
	nameLabel = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 18, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 24), Parent = bar })
	local prev = Ui.button("<", { Position = UDim2.fromOffset(10, 40), Size = UDim2.fromOffset(60, 42), TextSize = 24, Parent = bar })
	toggleButton = Ui.button("SPECTATE", { Position = UDim2.fromOffset(80, 40), Size = UDim2.fromOffset(190, 42), Parent = bar }, C.Accent)
	followButton = Ui.button("FOLLOW BALL: ON", { Position = UDim2.fromOffset(280, 40), Size = UDim2.fromOffset(200, 42), TextSize = 15, Parent = bar })
	local nextButton = Ui.button(">", { Position = UDim2.fromOffset(490, 40), Size = UDim2.fromOffset(60, 42), TextSize = 24, Parent = bar })
	prev.Activated:Connect(function()
		SpectateController.cycle(-1)
	end)
	nextButton.Activated:Connect(function()
		SpectateController.cycle(1)
	end)
	toggleButton.Activated:Connect(function()
		SpectateController.setActive(not SpectateController.active)
	end)
	followButton.Activated:Connect(function()
		SpectateController.followBall = not SpectateController.followBall
		SpectateController.refresh()
	end)
	ContextActionService:BindAction("RR_SpectateCycle", function(_, state, input)
		if state ~= Enum.UserInputState.Begin or not SpectateController.active then
			return Enum.ContextActionResult.Pass
		end
		local left = input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft
		SpectateController.cycle(if left then -1 else 1)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)

	ClientState.MatchChanged:Connect(SpectateController.refresh)
	ClientState.RosterChanged:Connect(SpectateController.refresh)
	ClientState.BallEvent:Connect(function(kind)
		if kind == "target" and SpectateController.active and SpectateController.followBall then
			SpectateController.refresh()
		end
	end)
	player:GetAttributeChangedSignal("RR_Status"):Connect(function()
		-- Auto-spectate right after being eliminated.
		if ClientState.status() == "Out" and canSpectate() then
			task.delay(1.5, function()
				SpectateController.setActive(true)
			end)
		end
		SpectateController.refresh()
	end)
	player.CharacterAdded:Connect(function()
		if SpectateController.active then
			task.defer(SpectateController.refresh)
		end
	end)
	SpectateController.refresh()
end

return SpectateController
