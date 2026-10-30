--[[
	InputController - keyboard / gamepad / touch.
	  E / X (gamepad)        interact: grab loot, levers, valves, revive (ProximityPrompts;
	                         on touch you tap the prompt)
	  Q / L1                 Grapple Hook (pass): aims where the camera / mouse points
	  F / DPad-up            Rescue Flare (if you have one, during a round)
	  M / Select             menu (shop, upgrades, daily, codes, board, stats, settings)
	Touch gets on-screen GRAPPLE / FLARE / MENU / SHOP buttons from the HUD (same functions).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.ClientState)

local InputController = {}

InputController.menuToggle = nil -- set by MenuController

-- Where the grapple aims: the mouse hit on desktop, the screen centre otherwise.
function InputController.aimTarget()
	local camera = workspace.CurrentCamera
	local root = ClientState.root()
	if not camera or not root then
		return nil
	end
	local origin, direction
	local ok, mouse = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(mouse) == "Vector2" and UserInputService.MouseEnabled then
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		origin, direction = ray.Origin, ray.Direction
	else
		origin, direction = camera.CFrame.Position, camera.CFrame.LookVector
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }
	local reach = GameConfig.Grapple.Range + (origin - root.CFrame.Position).Magnitude
	local hit = workspace:Raycast(origin, direction.Unit * reach, params)
	if hit and (hit.Position - root.CFrame.Position).Magnitude <= GameConfig.Grapple.Range then
		return hit.Position
	end
	return nil
end

function InputController.grapple()
	local me = ClientState.me()
	if not me.grapple then
		ClientState.Notified:Fire("The Grapple Hook is a game pass - see the Shop.", "info")
		return false
	end
	if me.grappleReady and ClientState.serverNow() < me.grappleReady then
		ClientState.Notified:Fire(string.format("Grapple recharging (%ds)", math.ceil(me.grappleReady - ClientState.serverNow())), "info")
		return false
	end
	local target = InputController.aimTarget()
	if not target then
		ClientState.Notified:Fire("Nothing to hook within 40 studs.", "info")
		return false
	end
	Net.event("Grapple"):FireServer(target)
	return true
end

function InputController.flare()
	if not ClientState.inRound() then
		return false
	end
	Net.event("UseFlare"):FireServer()
	return true
end

-- Returns true if the key did something (also used by the harness).
function InputController.handle(keyCode, began)
	if not began then
		return false
	end
	if keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.ButtonL1 then
		InputController.grapple()
		return true
	elseif keyCode == Enum.KeyCode.F or keyCode == Enum.KeyCode.DPadUp then
		return InputController.flare()
	elseif keyCode == Enum.KeyCode.M or keyCode == Enum.KeyCode.ButtonSelect then
		if InputController.menuToggle then
			InputController.menuToggle()
		end
		return true
	end
	return false
end

function InputController.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		InputController.handle(input.KeyCode, true)
	end)
end

return InputController
