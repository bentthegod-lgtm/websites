--[[
	TutorialController - a small banner with the current tutorial step (advanced only by
	real server events: claiming a pad, launching, a run finishing, buying an upgrade,
	completing an objective), an arrow toward the nearest free pad for the first step,
	and SKIP. Replay lives in Settings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
local QuestConfig = require(Shared.Config.QuestConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local TutorialController = {}

local C = Ui.Colors
local gui, banner, text, stepLabel
local beam

local function freePad()
	local root = ClientState.root()
	if not root then
		return nil
	end
	local facility = workspace:FindFirstChild("CrashLabFacility")
	local deck = facility and facility:FindFirstChild("LaunchDeck")
	if not deck then
		return nil
	end
	local best, bestDist
	for _, pad in ipairs(ClientState.pads) do
		if not pad.userId then
			local part = deck:FindFirstChild("Pad" .. pad.index)
			if part then
				local d = (part.Position - root.Position).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = part, d
				end
			end
		end
	end
	return best
end

local function setBeam(target)
	local root = ClientState.root()
	if not target or not root then
		if beam then
			beam.Enabled = false
		end
		return
	end
	if not beam then
		local a0 = Instance.new("Attachment")
		a0.Name = "TutorialA0"
		local a1 = Instance.new("Attachment")
		a1.Name = "TutorialA1"
		beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 1.2
		beam.Width1 = 1.2
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(C.Accent)
		beam.Transparency = NumberSequence.new(0.3, 0.8)
		beam.TextureSpeed = 1
	end
	beam.Attachment0.Parent = root
	beam.Attachment1.Parent = target
	beam.Attachment1.Position = Vector3.new(0, 1, 0)
	beam.Parent = root
	beam.Enabled = true
end

function TutorialController.render()
	local p = ClientState.profile
	local tut = p and p.tutorial
	local step = tut and not tut.Done and QuestConfig.Tutorial[tut.Step]
	banner.Visible = step ~= nil and step ~= false
	if step then
		stepLabel.Text = string.format("STEP %d / %d", tut.Step, #QuestConfig.Tutorial)
		text.Text = step.Text
	end
	setBeam(if step and step.Event == "ClaimPad" and not ClientState.myPad() then freePad() else nil)
end

function TutorialController.init()
	gui = Ui.screen("CrashTutorial", 4)
	banner = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(560, 40), BackgroundColor3 = C.PanelLight, Visible = false, Parent = gui }, 10)
	Ui.stroke(banner, C.Accent, 2, 0)
	stepLabel = Ui.title("", { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(90, 40), TextSize = 13, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = banner })
	text = Ui.label("", { Position = UDim2.fromOffset(104, 0), Size = UDim2.new(1, -184, 1, 0), TextSize = 14, Font = Ui.Fonts.Bold, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = banner })
	local skip = Ui.button("SKIP", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(64, 28), TextSize = 12 }, C.PanelLighter)
	skip.Parent = banner
	skip.Activated:Connect(function()
		Net.event("Tutorial"):FireServer("Skip")
	end)
	ClientState.ProfileChanged:Connect(TutorialController.render)
	ClientState.PadsChanged:Connect(TutorialController.render)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.defer(TutorialController.render)
	end)
end

return TutorialController
