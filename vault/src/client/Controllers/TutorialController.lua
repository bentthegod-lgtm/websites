--[[
	TutorialController - onboarding. A chip under the depth panel shows the current step
	("1/5  COLLECT CASH - walk up to loose cash and press E"), a marker floats over the
	thing to use (deposit machine, upgrade terminal, elevator), and a SKIP button ends it.
	Steps advance on the server when the real action happens (QuestConfig.Tutorial); the
	client only displays them. Replay from Settings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)
local QuestConfig = require(Shared.Config.QuestConfig)
local DepthConfig = require(Shared.Config.DepthConfig)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local C = Ui.Colors
local TutorialController = {}

local chip, stepLabel, textLabel
local marker
local localCollects = 0
local lastStep

local TARGETS = {
	Deposit = function(code)
		local folder = Workspace.Vault:FindFirstChild(code)
		for _, d in ipairs(folder and folder:GetDescendants() or {}) do
			if d:IsA("Model") and d:GetAttribute("MachineId") then
				return d:FindFirstChild("Screen", true)
			end
		end
		return nil
	end,
	Upgrade = function(code)
		local folder = Workspace.Vault:FindFirstChild(code)
		local terminal = folder and folder:FindFirstChild("UpgradeTerminal", true)
		return terminal and terminal:FindFirstChild("Screen", true)
	end,
	UnlockDepth = function(code)
		local folder = Workspace.Vault:FindFirstChild(code)
		local cabin = folder and folder:FindFirstChild("Elevator_" .. code, true)
		return cabin and cabin:FindFirstChild("FloorPanel", true)
	end,
}
TARGETS.TravelDeep = TARGETS.UnlockDepth

local function refresh()
	local p = ClientState.profile
	local t = p and p.tutorial
	if not t or t.Done or not QuestConfig.Tutorial[t.Step] then
		chip.Visible = false
		marker.Enabled = false
		return
	end
	local step = QuestConfig.Tutorial[t.Step]
	if lastStep ~= t.Step then
		lastStep = t.Step
		localCollects = 0
	end
	chip.Visible = true
	local progress = if step.Count then string.format("  (%d/%d)", math.min(localCollects, step.Count), step.Count) else ""
	stepLabel.Text = string.format("%d/%d  %s%s", t.Step, #QuestConfig.Tutorial, step.Title, progress)
	textLabel.Text = step.Text
	local finder = TARGETS[step.Event]
	local target = finder and finder(DepthConfig.get(ClientState.depth()).Code)
	if target then
		marker.Adornee = target
	end
	marker.Enabled = target ~= nil
end

function TutorialController.init()
	local gui = Ui.screen("VaultTutorial", 6)
	chip = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(470, 62), BackgroundTransparency = 0.05, Visible = false, Parent = gui }, 12)
	Ui.stroke(chip, C.Accent, 2, 0.1)
	stepLabel = Ui.title("", { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -110, 0, 24), TextSize = 17, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = chip })
	textLabel = Ui.label("", { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -110, 0, 26), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = chip })
	local skip = Ui.button("SKIP", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(80, 34), TextSize = 13 }, C.PanelLighter)
	skip.Parent = chip
	skip.Activated:Connect(function()
		Net.event("Tutorial"):FireServer("Skip")
		chip.Visible = false
		marker.Enabled = false
	end)
	marker = Ui.new("BillboardGui", { Size = UDim2.fromOffset(120, 50), StudsOffset = Vector3.new(0, 4, 0), AlwaysOnTop = true, LightInfluence = 0, Enabled = false, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	Ui.title("v  HERE  v", { Size = UDim2.fromScale(1, 1), TextSize = 22, TextColor3 = C.Accent, TextStrokeTransparency = 0.3, Parent = marker })
	ClientState.ProfileChanged:Connect(refresh)
	ClientState.DepthChanged:Connect(refresh)
	ClientState.Collected:Connect(function(userId)
		if userId == Players.LocalPlayer.UserId then
			localCollects += 1
			refresh()
		end
	end)
end

return TutorialController
