--[[
	WorldController - client-side world presentation:
	  * idle animation of every Blobby (Bob motor: bounce, wobble, spin, hop, sway, float;
	    frantic wiggling while carried), spinning propellers / halos, Rainbow mutation hue
	  * which prompt you see: your own Blobbies show Sell, other people's show Steal
	  * your own laser door: collision is switched off locally so only you walk through
	    (the server keeps it solid for everyone else)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WorldController = {}

local player = Players.LocalPlayer
local tracked = {} -- [model] = entry

local function updatePrompts(model)
	local mine = model:GetAttribute("OwnerId") == player.UserId
	local state = model:GetAttribute("State")
	for _, prompt in ipairs(model:GetDescendants()) do
		if prompt:IsA("ProximityPrompt") then
			if prompt.Name == "StealPrompt" then
				prompt.Enabled = not mine and state == "Placed"
			elseif prompt.Name == "SellPrompt" then
				prompt.Enabled = mine and state == "Placed"
			elseif prompt.Name == "BuyPrompt" then
				prompt.Enabled = state == "Carpet"
			end
		end
	end
end
WorldController.updatePrompts = updatePrompts

local function track(model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	local root = model:FindFirstChild("Root")
	local motor = root and root:FindFirstChild("Bob")
	if not motor then
		return
	end
	local entry = {
		model = model,
		root = root,
		motor = motor,
		style = model:GetAttribute("Bob") or "Bounce",
		phase = model:GetAttribute("Phase") or 0,
		spinners = {},
		rainbow = {},
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "Spinner" then
			table.insert(entry.spinners, d)
		elseif d:IsA("BasePart") and d:GetAttribute("Rainbow") then
			table.insert(entry.rainbow, d)
		end
	end
	tracked[model] = entry
	updatePrompts(model)
	model:GetAttributeChangedSignal("State"):Connect(function()
		updatePrompts(model)
	end)
	model:GetAttributeChangedSignal("OwnerId"):Connect(function()
		updatePrompts(model)
	end)
end

local function untrack(model)
	tracked[model] = nil
end

-- Bob transform for a style at time t.
function WorldController.bobTransform(style, t, carried)
	if carried then
		return CFrame.new(0, math.abs(math.sin(t * 9)) * 0.3, 0) * CFrame.Angles(0, 0, math.sin(t * 14) * 0.3)
	end
	if style == "Bounce" then
		return CFrame.new(0, math.abs(math.sin(t * 3.2)) * 0.5, 0)
	elseif style == "Wobble" then
		return CFrame.Angles(0, 0, math.sin(t * 3) * 0.14) * CFrame.new(0, math.abs(math.sin(t * 6)) * 0.1, 0)
	elseif style == "Spin" then
		return CFrame.new(0, math.sin(t * 2) * 0.15 + 0.15, 0) * CFrame.Angles(0, t * 1.6, 0)
	elseif style == "Hop" then
		local s = math.sin(t * 4)
		return CFrame.new(0, if s > 0 then s * 0.9 else 0, 0)
	elseif style == "Sway" then
		return CFrame.Angles(math.sin(t * 1.3) * 0.06, 0, math.sin(t * 1.6) * 0.18)
	elseif style == "Float" then
		return CFrame.new(0, 0.6 + math.sin(t * 2) * 0.35, 0) * CFrame.Angles(0, math.sin(t * 0.7) * 0.3, 0)
	end
	return CFrame.new()
end

function WorldController.step()
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local t = os.clock()
	for model, entry in pairs(tracked) do
		if not model.Parent then
			tracked[model] = nil
		elseif not camPos or (entry.root.CFrame.Position - camPos).Magnitude < 160 then
			local tt = t + entry.phase
			local carried = model:GetAttribute("State") == "Carried"
			entry.motor.Transform = WorldController.bobTransform(entry.style, tt, carried)
			for _, spinner in ipairs(entry.spinners) do
				spinner.Transform = CFrame.Angles(0, tt * (spinner:GetAttribute("Speed") or 2), 0)
			end
			for _, part in ipairs(entry.rainbow) do
				part.Color = Color3.fromHSV((tt * 0.25) % 1, 0.75, 1)
			end
		end
	end
end

-- Keep my own laser door passable for me.
function WorldController.updateDoors()
	local worldFolder = workspace:FindFirstChild("SnatchWorld")
	local plots = worldFolder and worldFolder:FindFirstChild("Plots")
	if not plots then
		return
	end
	for _, plot in ipairs(plots:GetChildren()) do
		local blocker = plot:FindFirstChild("LaserBlocker")
		if blocker and blocker:GetAttribute("OwnerId") == player.UserId and blocker.CanCollide then
			blocker.CanCollide = false
		end
	end
end

function WorldController.init()
	for _, model in ipairs(CollectionService:GetTagged("Blobby")) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("Blobby"):Connect(function(model)
		-- Parts may still be streaming in; wait a frame.
		task.defer(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal("Blobby"):Connect(untrack)
	RunService.RenderStepped:Connect(WorldController.step)
	task.spawn(function()
		while true do
			WorldController.updateDoors()
			task.wait(0.2)
		end
	end)
end

WorldController.track = track

return WorldController
