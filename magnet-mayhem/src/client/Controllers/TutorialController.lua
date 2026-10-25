--[[
	TutorialController - the guide arrow. The tutorial steps themselves live on the server
	(QuestConfig.Tutorial, advanced by real gameplay); this draws a glowing beam from your
	character to the current step's target (shredder, upgrade station, the yard) and a
	SKIP button. Replay is in Settings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Net = require(Shared.Net)
local QuestConfig = require(Shared.Config.QuestConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local TutorialController = {}

local player = Players.LocalPlayer
local TARGETS = {
	Shredder = Vector3.new(0, 1, -26),
	Station = Vector3.new(-31, 1, 20),
	Yard = Vector3.new(-60, 1, -70),
}
local beam, a0, a1, anchor, skip

local function ensureBeam()
	if beam then
		return
	end
	anchor = Instance.new("Part")
	anchor.Name = "MM_TutorialTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = workspace
	a1 = Instance.new("Attachment")
	a1.Parent = anchor
	a0 = Instance.new("Attachment")
	beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60))
	beam.Transparency = NumberSequence.new(0.2, 0.6)
	beam.TextureSpeed = 2
	beam.Parent = anchor
end

function TutorialController.render(profile)
	local tut = profile and profile.tutorial
	local step = tut and not tut.Done and QuestConfig.Tutorial[tut.Step]
	if skip then
		skip.Visible = step ~= nil and step ~= false
	end
	local target = step and step.Target and TARGETS[step.Target]
	local root = ClientState.root()
	if target and root then
		ensureBeam()
		anchor.Position = target
		a0.Parent = root
		beam.Enabled = true
	elseif beam then
		beam.Enabled = false
	end
end

function TutorialController.init()
	local gui = Ui.screen("MagnetTutorial", 6)
	skip = Ui.button("SKIP TUTORIAL", { Position = UDim2.fromOffset(16, 122), Size = UDim2.fromOffset(150, 28), TextSize = 12, Visible = false }, Ui.Colors.PanelLighter)
	skip.Parent = gui
	skip.Activated:Connect(function()
		Net.event("Tutorial"):FireServer("Skip")
	end)
	ClientState.ProfileChanged:Connect(TutorialController.render)
	player.CharacterAdded:Connect(function()
		task.defer(TutorialController.render, ClientState.profile)
	end)
end

return TutorialController
