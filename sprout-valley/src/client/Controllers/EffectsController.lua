--[[
	EffectsController - the "juice": floating harvest numbers, particle bursts, coins
	flying into the wallet, camera punches, lightning bolts, popups for crates / daily
	rewards / goals, sounds, plus ambient animation (windmill, clouds, prismatic text).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local CropConfig = require(Shared.Config.CropConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)
local HudController = require(script.Parent.HudController)

local EffectsController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local fxFolder
local punch = 0

local function fxPart(position, size)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size or Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(position)
	p.Parent = fxFolder
	return p
end

function EffectsController.burst(position, colors, count, speed)
	local holder = fxPart(position)
	local e = Instance.new("ParticleEmitter")
	local keys = {}
	for i, c in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	e.Color = ColorSequence.new(keys)
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(speed or 8, (speed or 8) * 1.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -18, 0)
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = holder
	e:Emit(count or 20)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

function EffectsController.floatText(position, lines)
	local holder = fxPart(position + Vector3.new(0, 3, 0))
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 30 * #lines)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 150
	bb.Adornee = holder
	bb.Parent = holder
	for i, line in ipairs(lines) do
		local label = Ui.title(line.text, {
			Position = UDim2.new(0, 0, (i - 1) / #lines, 0),
			Size = UDim2.new(1, 0, 1 / #lines, 0),
			TextScaled = true,
			TextColor3 = line.color or C.White,
			Parent = bb,
		})
		Ui.textStroke(label, C.Shadow, 2)
		if line.prismatic then
			Ui.prismatic(label)
		end
	end
	TweenService:Create(holder, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = holder.CFrame + Vector3.new(0, 4, 0) }):Play()
	task.delay(1.6, function()
		holder:Destroy()
	end)
end

function EffectsController.cameraPunch(amount)
	punch = math.max(punch, amount)
end

-- Big centre-screen popup (crate results, daily reward, goal complete...).
function EffectsController.popup(title, lines, color)
	color = color or C.Gold
	local frame = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(420, 70 + 26 * #lines), ZIndex = 50, Parent = gui })
	Ui.stroke(frame, color, 4)
	local t = Ui.title(title, { Size = UDim2.new(1, 0, 0, 50), TextSize = 34, TextColor3 = color, ZIndex = 51, Parent = frame })
	Ui.textStroke(t, C.Shadow, 2)
	for i, line in ipairs(lines) do
		Ui.title(line, { Position = UDim2.fromOffset(0, 46 + (i - 1) * 26), Size = UDim2.new(1, 0, 0, 26), TextSize = 20, ZIndex = 51, Parent = frame })
	end
	local scale = Ui.new("UIScale", { Scale = 0.3, Parent = frame })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.8, function()
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
		task.wait(0.25)
		frame:Destroy()
	end)
end

-- Coins fly from the screen centre into the wallet pill.
function EffectsController.coinShower(amount)
	local hud = HudController.gui()
	if not hud then
		return
	end
	local scale = Ui.scaleOf(hud)
	local target = HudController.coinTarget() / scale
	local camera = workspace.CurrentCamera
	local centre = (if camera then camera.ViewportSize * 0.5 else Vector2.new(500, 300)) / scale
	local n = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 3), 4, 16)
	for i = 1, n do
		local start = centre + Vector2.new(math.random(-120, 120), math.random(-60, 60))
		local coin = Ui.coinIcon(hud, 26, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(start.X, start.Y), ZIndex = 60 })
		task.delay(i * 0.03, function()
			local tween = TweenService:Create(coin, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(target.X, target.Y) })
			tween:Play()
			tween.Completed:Connect(function()
				coin:Destroy()
			end)
		end)
	end
	local label = Ui.title("+" .. Format.coins(amount), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X, centre.Y - 40), Size = UDim2.fromOffset(400, 70), TextSize = 56, TextColor3 = C.Gold, ZIndex = 61, Parent = hud })
	Ui.textStroke(label, Color3.fromRGB(150, 90, 10), 3)
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(centre.X, centre.Y - 110), TextTransparency = 1 }):Play()
	task.delay(1.3, function()
		label:Destroy()
	end)
end

local function lightning(position)
	local top = position + Vector3.new(math.random(-6, 6), 90, math.random(-6, 6))
	local points = { top }
	for i = 1, 6 do
		local t = i / 7
		local p = top:Lerp(position, t) + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
		table.insert(points, p)
	end
	table.insert(points, position)
	local parts = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(255, 250, 190)
		seg.Size = Vector3.new(0.6, 0.6, (b - a).Magnitude)
		seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		seg.Parent = fxFolder
		table.insert(parts, seg)
	end
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 6
	light.Color = Color3.fromRGB(255, 250, 200)
	light.Parent = parts[#parts]
	local grade = Lighting:FindFirstChild("SV_Grade")
	if grade then
		grade.Brightness = 0.42
		TweenService:Create(grade, TweenInfo.new(0.4), { Brightness = 0.02 }):Play()
	end
	EffectsController.burst(position, { Color3.fromRGB(255, 240, 90), C.White }, 40, 14)
	EffectsController.cameraPunch(0.6)
	Audio.play("Thunder", 0.2)
	task.delay(0.25, function()
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

local function mutationColor(name)
	local def = MutationConfig.Mutations[name] or MutationConfig.Variants[name]
	return if def then Ui.rgb(def.Color) else C.White
end

local handlers = {}

function handlers.Harvest(data)
	local crop = CropConfig.ById[data.crop]
	if not crop then
		return
	end
	local rank = RarityConfig.Tiers[crop.Rarity].Rank
	local lines = {
		{ text = string.format("+%s %s", (if data.huge then "HUGE " else "") .. crop.Name, Format.kg(data.kg)), color = Ui.rarityColor(crop.Rarity), prismatic = crop.Rarity == "Prismatic" },
		{ text = Format.coins(data.value) .. " Coins", color = C.Gold },
	}
	local tags = {}
	if data.variant then
		table.insert(tags, data.variant)
	end
	for _, m in ipairs(data.mutations or {}) do
		table.insert(tags, m)
	end
	if #tags > 0 then
		table.insert(lines, 2, { text = table.concat(tags, " + "), color = mutationColor(tags[1]) })
	end
	EffectsController.floatText(data.position, lines)
	EffectsController.burst(data.position + Vector3.new(0, 1, 0), { Ui.rgb(crop.Model.Fruit), C.White }, 14 + rank * 3, 7)
	Audio.play("Harvest", 0.15)
	if rank >= 5 or data.huge or #tags > 0 then
		EffectsController.cameraPunch(0.25 + rank * 0.05)
	end
end

function handlers.Plant(data)
	EffectsController.burst(data.position, { Color3.fromRGB(140, 100, 60), Color3.fromRGB(110, 190, 80) }, 10, 5)
	Audio.play("Plant", 0.2)
end

function handlers.Sell(data)
	EffectsController.coinShower(data.amount)
	EffectsController.cameraPunch(0.35)
	Audio.play("Sell")
end

function handlers.Coins(data)
	EffectsController.coinShower(data.amount)
	Audio.play("Purchase")
end

function handlers.Mutation(data)
	local color = mutationColor(data.mutation)
	EffectsController.burst(data.position + Vector3.new(0, 1.5, 0), { color, C.White }, 26, 6)
	if data.owner == player.UserId then
		EffectsController.floatText(data.position, { { text = tostring(data.mutation) .. "!", color = color } })
		Audio.play("Mutation")
	end
end

function handlers.Lightning(data)
	lightning(data.position)
end

function handlers.Water(data)
	EffectsController.burst(data.position + Vector3.new(0, 2, 0), { Color3.fromRGB(120, 190, 255), C.White }, 18, 4)
	Audio.play("Water")
end

function handlers.Sprinkler(data)
	EffectsController.burst(data.position + Vector3.new(0, 2, 0), { Color3.fromRGB(120, 190, 255), C.White }, 24, 6)
end

function handlers.Lucky(data)
	EffectsController.burst(data.position + Vector3.new(0, 1, 0), { Color3.fromRGB(120, 255, 120), C.Gold }, 24, 5)
end

function handlers.Skip(data)
	EffectsController.burst(data.position + Vector3.new(0, 1, 0), { C.Purple, C.Gold, C.White }, 40, 9)
	EffectsController.cameraPunch(0.3)
end

function handlers.Ripe(data)
	local crop = CropConfig.ById[data.crop]
	if crop and RarityConfig.Tiers[crop.Rarity].Rank >= 4 then
		ClientState.Notified:Fire("Your " .. crop.Name .. " is ripe!", "good")
	end
end

function handlers.Purchase()
	Audio.play("Purchase", 0.1)
end

function handlers.Restock()
	ClientState.Notified:Fire("The Seed Shop just restocked!", "good")
	Audio.play("Restock")
end

function handlers.Crate(data)
	local names = {}
	for _, id in ipairs(data.crops or {}) do
		local crop = CropConfig.ById[id]
		if crop then
			table.insert(names, crop.Name .. "  (" .. crop.Rarity .. ")")
		end
	end
	EffectsController.popup("SEED CRATE!", names, C.Orange)
	EffectsController.cameraPunch(0.4)
	Audio.play("RareAnnounce")
end

function handlers.Daily(data)
	EffectsController.popup("DAY " .. tostring(data.streak) .. " REWARD", data.lines or {}, C.Purple)
	Audio.play("Daily")
end

function handlers.Code(data)
	EffectsController.popup("CODE REDEEMED", data.lines or {}, C.Purple)
end

function handlers.Goal(data)
	EffectsController.popup("GOAL COMPLETE!", { data.text, "+" .. Format.coins(data.reward) .. " Coins" }, C.Green)
end

function handlers.Gift(data)
	EffectsController.popup("A GIFT!", { tostring(data.from) .. " sent you a fruit" }, C.Pink)
end

function handlers.Expand()
	EffectsController.popup("GARDEN EXPANDED", { "+6 soil tiles to plant on" }, C.Orange)
	Audio.play("Expand")
end

function handlers.BackpackFull()
	EffectsController.cameraPunch(0.2)
end

function handlers.WeatherStart()
	Audio.play("WeatherStart")
end

function EffectsController.handle(kind, data)
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(handler, data)
		if not ok then
			warn("[SproutValley] effect " .. tostring(kind) .. " failed: " .. tostring(err))
		end
	end
end

local function animateWorld(dt, t)
	local village = workspace:FindFirstChild("Village")
	if not village then
		return
	end
	local decor = village:FindFirstChild("Decor")
	local windmill = decor and decor:FindFirstChild("Windmill")
	local blades = windmill and windmill:FindFirstChild("Blades")
	if blades and blades.PrimaryPart then
		local hub = blades.PrimaryPart
		local axis = hub.CFrame
		local spin = CFrame.fromAxisAngle(axis.XVector, dt * 0.6)
		for _, p in ipairs(blades:GetChildren()) do
			if p:IsA("BasePart") and p ~= hub then
				local rel = p.CFrame - axis.Position
				p.CFrame = (spin * rel) + axis.Position
			end
		end
	end
	local clouds = village:FindFirstChild("Clouds")
	if clouds then
		for _, cloud in ipairs(clouds:GetChildren()) do
			for _, puff in ipairs(cloud:GetChildren()) do
				if puff:IsA("BasePart") then
					local cf = puff.CFrame + Vector3.new(dt * 2, 0, 0)
					if cf.Position.X > 220 then
						cf = cf - Vector3.new(460, 0, 0)
					end
					puff.CFrame = cf
				end
			end
		end
	end
	for i = #(Ui.prismaticGradients or {}), 1, -1 do
		local g = Ui.prismaticGradients[i]
		if g.Parent then
			g.Offset = Vector2.new(math.sin(t * 1.5) * 0.5, 0)
		else
			table.remove(Ui.prismaticGradients, i)
		end
	end
end

function EffectsController.init()
	gui = Ui.screen("SproutFX", 8)
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "SproutFX"
	fxFolder.Parent = workspace
	Ui.clickHandler = function()
		Audio.play("UiClick", 0.1)
	end
	ClientState.EffectFired:Connect(EffectsController.handle)
	ClientState.Announced:Connect(function()
		Audio.play("RareAnnounce")
	end)
	ClientState.ProfileChanged:Connect(function(profile)
		Audio.loop("Music", profile and profile.settings and profile.settings.Music ~= false)
	end)
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		animateWorld(dt, t)
		local camera = workspace.CurrentCamera
		if camera and punch > 0.001 then
			local shake = punch * 0.6
			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * shake * 4), math.rad((math.random() - 0.5) * shake * 4), 0)
			punch *= math.exp(-dt * 9)
		end
	end)
end

return EffectsController
