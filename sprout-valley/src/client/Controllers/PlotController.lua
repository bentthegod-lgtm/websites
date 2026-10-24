--[[
	PlotController - pointing at and acting on garden tiles.

	* Mouse: hover shows a highlight + info tooltip; click acts; hold and drag over ripe
	  crops to harvest a whole row.
	* Touch: tap a tile (or drag a finger across ripe crops).
	* Gamepad: aim with the screen centre, R2 acts.

	The client only sends intent (TileAction / MovePlant); the server validates everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)
local CropConfig = require(Shared.Config.CropConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local Format = require(Shared.Format)
local Growth = require(Shared.Growth)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local PlotController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local selection, tooltip, tipTitle, tipLine, tipChips
local hovered -- { plotId, index, tile, model }
local dragging = false
local lastDragIndex
local moveFrom -- trowel: tile index picked up

local function findTarget(instance)
	local node = instance
	while node and node ~= workspace do
		local plotId = node:GetAttribute("PlotId")
		local index = node:GetAttribute("TileIndex")
		if plotId and index then
			return plotId, index
		end
		node = node.Parent
	end
	return nil
end

local function plotFolder(plotId)
	local village = workspace:FindFirstChild("Village")
	local plots = village and village:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. tostring(plotId))
end

local function tileAndModel(plotId, index)
	local f = plotFolder(plotId)
	if not f then
		return nil, nil
	end
	local tile
	local tiles = f:FindFirstChild("Tiles")
	if tiles then
		for _, t in ipairs(tiles:GetChildren()) do
			if t:GetAttribute("TileIndex") == index then
				tile = t
				break
			end
		end
	end
	local model
	local crops = f:FindFirstChild("Crops")
	if crops then
		for _, m in ipairs(crops:GetChildren()) do
			if m:GetAttribute("TileIndex") == index then
				model = m
				break
			end
		end
	end
	return tile, model
end

local function screenRay(position)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	return workspace:Raycast(ray.Origin, ray.Direction * 400, params)
end

local function pointerPosition()
	local last = UserInputService:GetLastInputType()
	local size = Ui.viewportSize()
	if last and last.Name:sub(1, 7) == "Gamepad" and size then
		return size * 0.5
	end
	return UserInputService:GetMouseLocation()
end

local function targetAt(position)
	if not position then
		return nil
	end
	local result = screenRay(position)
	if not result then
		return nil
	end
	local plotId, index = findTarget(result.Instance)
	if not plotId then
		return nil
	end
	local tile, model = tileAndModel(plotId, index)
	return { plotId = plotId, index = index, tile = tile, model = model }
end

---------------------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------------------

local function buildTooltip()
	local playerGui = player:WaitForChild("PlayerGui")
	selection = Ui.new("SelectionBox", {
		Name = "SproutTileHighlight",
		LineThickness = 0.08,
		Color3 = C.Gold,
		SurfaceTransparency = 0.85,
		SurfaceColor3 = C.Gold,
		Parent = playerGui,
	})
	tooltip = Ui.new("BillboardGui", {
		Name = "SproutTooltip",
		Size = UDim2.fromOffset(230, 92),
		StudsOffset = Vector3.new(0, 4.5, 0),
		AlwaysOnTop = true,
		Enabled = false,
		MaxDistance = 120,
		Parent = playerGui,
	})
	local card = Ui.panel({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.05, Parent = tooltip }, 12)
	Ui.padding(card, 8, 6)
	tipTitle = Ui.title("", { Size = UDim2.new(1, 0, 0, 24), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	tipLine = Ui.label("", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 20), TextSize = 14, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	tipChips = Ui.new("Frame", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = card })
	Ui.list(tipChips, 4, Enum.FillDirection.Horizontal)
end

local lastTipKey
local function updateTooltip(target)
	if not target or not target.tile then
		tooltip.Enabled = false
		selection.Adornee = nil
		lastTipKey = nil
		return
	end
	selection.Adornee = target.tile
	tooltip.Adornee = target.tile
	tooltip.Enabled = true
	local mine = target.plotId == ClientState.myPlotId()
	local model = target.model
	if model then
		local crop = CropConfig.ById[model:GetAttribute("Crop")]
		local progress = model:GetAttribute("Progress") or 0
		local remaining = model:GetAttribute("Remaining") or 0
		local rate = model:GetAttribute("Rate") or 1
		tipTitle.Text = crop and crop.Name or "?"
		tipTitle.TextColor3 = if crop then Ui.rarityColor(crop.Rarity):Lerp(C.Brown, 0.35) else C.Brown
		if progress >= 1 then
			tipLine.Text = if mine then "RIPE! Tap to harvest" else "Ripe and ready"
			tipLine.TextColor3 = C.GreenDark
		else
			local stage = Growth.StageNames[model:GetAttribute("Stage") or 1] or ""
			tipLine.Text = string.format("%s  %s  -  %s left%s", stage, Format.percent(progress), Format.duration(remaining), if rate > 1.01 then string.format("  (x%.2g)", rate) else "")
			tipLine.TextColor3 = C.Brown
		end
		local key = (model:GetAttribute("Mutations") or "") .. "|" .. (model:GetAttribute("Variant") or "") .. tostring(model:GetAttribute("Lucky"))
		if key ~= lastTipKey then
			lastTipKey = key
			Ui.clear(tipChips)
			local variant = model:GetAttribute("Variant") or ""
			if variant ~= "" and MutationConfig.Variants[variant] then
				Ui.chip(tipChips, variant, Ui.rgb(MutationConfig.Variants[variant].Color), 0)
			end
			for i, name in ipairs(string.split(model:GetAttribute("Mutations") or "", ",")) do
				local def = MutationConfig.Mutations[name]
				if def then
					Ui.chip(tipChips, name, Ui.rgb(def.Color), i)
				end
			end
			if model:GetAttribute("Lucky") then
				Ui.chip(tipChips, "Lucky", C.Green, 99)
			end
		end
	else
		lastTipKey = nil
		Ui.clear(tipChips)
		local locked = target.tile:GetAttribute("Locked")
		if mine then
			tipTitle.Text = if locked then "Locked tile" else "Empty soil"
			local tool = ClientState.tool
			if locked then
				tipLine.Text = "Expand your garden to unlock"
			elseif tool.kind == "seed" then
				local crop = CropConfig.ById[tool.id]
				tipLine.Text = "Tap to plant " .. (crop and crop.Name or "")
			else
				tipLine.Text = "Pick a seed from your hotbar"
			end
		else
			tipTitle.Text = if locked then "Grass" else "Soil"
			tipLine.Text = "Someone else's garden"
		end
		tipTitle.TextColor3 = C.Brown
		tipLine.TextColor3 = C.Dim
	end
	if moveFrom and mine then
		tipLine.Text = if model then "Pick an EMPTY tile" else "Tap to move the plant here"
	end
	selection.Color3 = if mine then C.Gold else C.Sky
	selection.SurfaceColor3 = selection.Color3
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------

local function pop(part)
	if not part then
		return
	end
	local size = part.Size
	part.Size = size * Vector3.new(1.08, 1, 1.08)
	TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size }):Play()
end

function PlotController.act(target, fromDrag)
	if not target then
		return
	end
	if target.plotId ~= ClientState.myPlotId() then
		return
	end
	local tool = ClientState.tool
	local ripe = target.model and (target.model:GetAttribute("Progress") or 0) >= 1
	if fromDrag then
		-- Dragging only ever harvests (or plants seeds along a row).
		if ripe or (tool.kind == "seed" and not target.model) then
			Net.event("TileAction"):FireServer(target.index, tool.kind, tool.id)
		end
		return
	end
	if tool.kind == "gear" and tool.id == "Trowel" then
		if not moveFrom then
			if target.model then
				moveFrom = target.index
				ClientState.Notified:Fire("Trowel: now tap an empty tile to move it there.", "info")
			end
		else
			if not target.model then
				Net.event("MovePlant"):FireServer(moveFrom, target.index)
			end
			moveFrom = nil
		end
		return
	end
	moveFrom = nil
	Net.event("TileAction"):FireServer(target.index, tool.kind, tool.id)
	pop(target.tile)
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function PlotController.init()
	buildTooltip()
	ClientState.ToolChanged:Connect(function()
		moveFrom = nil
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if isPointer(input) then
			local target = targetAt(Vector2.new(input.Position.X, input.Position.Y))
			hovered = target
			PlotController.act(target, false)
			dragging = true
			lastDragIndex = target and target.index
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			local size = Ui.viewportSize()
			if size then
				PlotController.act(targetAt(size * 0.5), false)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local target = targetAt(Vector2.new(input.Position.X, input.Position.Y))
			if target and target.index ~= lastDragIndex then
				lastDragIndex = target.index
				PlotController.act(target, true)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then
			dragging = false
			lastDragIndex = nil
		end
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.05 then
			return
		end
		accumulator = 0
		if not UserInputService.TouchEnabled or UserInputService.MouseEnabled then
			hovered = targetAt(pointerPosition())
		elseif hovered and hovered.plotId then
			-- Touch: keep the last tapped tile's tooltip fresh.
			local tile, model = tileAndModel(hovered.plotId, hovered.index)
			hovered.tile, hovered.model = tile, model
		end
		updateTooltip(hovered)
	end)
end

return PlotController
