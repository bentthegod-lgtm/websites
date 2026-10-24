--[[
	EffectsController - the juice: flying cash numbers, rarity reveals, confetti, camera
	punch, slap bursts, knockback, welcome / offline-earnings cards and goal toasts.
	Driven by the server's Popup / SlapFx / Knockback remotes (via ClientState).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local Format = require(Shared.Format)
local BlobbyConfig = require(Shared.Config.BlobbyConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local GameConfig = require(Shared.Config.GameConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local HudController = require(script.Parent.HudController)

local EffectsController = {}

local player = Players.LocalPlayer
local C = Ui.Colors
local gui
local CONFETTI = { C.Accent, C.Pink, C.Blue, C.Good, C.Purple, C.Orange, C.Cyan }

---------------------------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------------------------

function EffectsController.cameraPunch(strength)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local base = 70
	camera.FieldOfView = base - (strength or 6)
	TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
end

function EffectsController.confetti(count)
	for _ = 1, count or 40 do
		local piece = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.random(), 0, -0.05, 0),
			Size = UDim2.new(0, math.random(8, 14), 0, math.random(12, 20)),
			BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)],
			Rotation = math.random(0, 360),
			ZIndex = 20,
			Parent = gui,
		})
		local duration = 1.6 + math.random() * 1.4
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.3, 0, 1.08, 0),
			Rotation = piece.Rotation + math.random(-540, 540),
		}):Play()
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

-- Floating "+$123" text at a world position (on a tiny invisible local part).
function EffectsController.worldText(position, text, color, size)
	local anchor = Instance.new("Part")
	anchor.Name = "FloatingText"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, size or 160, 0, 50)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Parent = anchor
	local label = Ui.label(text, { Font = Ui.Fonts.Title, Size = UDim2.fromScale(1, 1), TextScaled = true, TextColor3 = color or C.Good, StrokeThickness = 3, Parent = billboard })
	TweenService:Create(billboard, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

-- Big centre banner with an optional subtitle; returns the frame.
function EffectsController.banner(title, subtitle, color, duration)
	local frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0, 640, 0, 150),
		BackgroundTransparency = 1,
		ZIndex = 15,
		Parent = gui,
	})
	local rays = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 420, 0, 420),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		ZIndex = 14,
		Parent = frame,
	})
	Ui.corner(rays, 210)
	Ui.label(title, { Font = Ui.Fonts.Title, Size = UDim2.new(1, 0, 0, 80), TextScaled = true, TextColor3 = Ui.lighten(color, 0.25), StrokeThickness = 4, ZIndex = 16, Parent = frame })
	if subtitle then
		Ui.label(subtitle, { Position = UDim2.new(0, 0, 0, 84), Size = UDim2.new(1, 0, 0, 42), TextScaled = true, StrokeThickness = 3, ZIndex = 16, Parent = frame })
	end
	Ui.pop(frame, 0.3)
	TweenService:Create(rays, TweenInfo.new(duration or 2.5), { Rotation = 180, BackgroundTransparency = 1 }):Play()
	task.delay(duration or 2.5, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
	return frame
end

-- Modal card with an OK button (welcome, offline earnings).
function EffectsController.card(title, lines, color, buttonText)
	local card = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 520, 0, 120 + #lines * 34),
		ZIndex = 18,
		Parent = gui,
	})
	Ui.gradient(card, Color3.fromRGB(60, 44, 104), Color3.fromRGB(34, 24, 62))
	Ui.label(title, { Font = Ui.Fonts.Title, Position = UDim2.new(0, 10, 0, 10), Size = UDim2.new(1, -20, 0, 44), TextScaled = true, TextColor3 = color, StrokeThickness = 3, ZIndex = 19, Parent = card })
	for i, text in ipairs(lines) do
		Ui.label(text, { Position = UDim2.new(0, 16, 0, 26 + i * 34), Size = UDim2.new(1, -32, 0, 30), TextScaled = true, ZIndex = 19, Parent = card })
	end
	local ok = Ui.button(buttonText or "AWESOME!", C.Good, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0, 220, 0, 46), ZIndex = 19, Parent = card })
	ok.Activated:Connect(function()
		card:Destroy()
	end)
	Ui.pop(card, 0.5)
	return card
end

local function rarityColor(rarity)
	local tier = RarityConfig.Tiers[rarity]
	return if tier then Ui.rgb(tier.Color) else C.Text
end

local function blobbyTitle(speciesId, mutation)
	local species = BlobbyConfig.ById[speciesId]
	local name = if species then species.Name else tostring(speciesId)
	return (if mutation then string.upper(mutation) .. " " else "") .. name
end

---------------------------------------------------------------------------------------------
-- Popups from the server
---------------------------------------------------------------------------------------------

local handlers = {}

function handlers.Cash(data)
	if typeof(data.position) == "Vector3" then
		EffectsController.worldText(data.position, "+" .. Format.cash(data.amount), C.Good)
	else
		EffectsController.banner("+" .. Format.cash(data.amount), "Cash added!", C.Good, 2)
		EffectsController.confetti(30)
	end
	HudController.bumpCash()
end

function handlers.AutoCash(data)
	HudController.bumpCash()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		EffectsController.worldText(head.CFrame.Position + Vector3.new(0, 2, 0), "+" .. Format.cash(data.amount), C.Good, 120)
	end
end

function handlers.Bought(data)
	local tierIndex = table.find(RarityConfig.Order, data.rarity) or 1
	if typeof(data.position) == "Vector3" then
		EffectsController.worldText(data.position + Vector3.new(0, 4, 0), "-" .. Format.cash(data.price), C.Danger, 140)
	end
	if tierIndex >= 4 or data.mutation then
		EffectsController.banner(string.upper(data.rarity) .. "!", (if data.mutation then string.upper(data.mutation) .. " " else "") .. data.name .. " is walking to your base", rarityColor(data.rarity), 2.6)
		EffectsController.cameraPunch(8)
		EffectsController.confetti(30 + tierIndex * 8)
	else
		HudController.toast("Bought " .. data.name .. "! It's walking to your base.", "good")
	end
end

function handlers.Discovered(data)
	local species = BlobbyConfig.ById[data.species]
	local profile = ClientState.profile
	local count = profile and profile.discoveredCount and (profile.discoveredCount + 1) or nil
	HudController.toast("NEW in your Index: " .. (if species then species.Name else "?") .. (if count then string.format(" (%d/%d)", count, #BlobbyConfig.List) else ""), "gold")
end

function handlers.Reveal(data)
	local color = rarityColor(data.rarity)
	if data.mutation and MutationConfig.Types[data.mutation] then
		color = Ui.rgb(MutationConfig.Types[data.mutation].Color)
	end
	local source = if data.source == "crate" then "MYTHIC CRATE" elseif data.source == "daily" then "DAILY REWARD" else "GIFT"
	EffectsController.banner(string.upper(data.rarity) .. "!", source .. ": " .. blobbyTitle(data.species, data.mutation), color, 3.2)
	EffectsController.cameraPunch(10)
	EffectsController.confetti(70)
	AudioController.play("Reward")
end

function handlers.Stolen(data)
	EffectsController.banner("STOLEN!", data.name, rarityColor(data.rarity), 3)
	EffectsController.cameraPunch(12)
	EffectsController.confetti(80)
end

function handlers.Rebirth(data)
	EffectsController.banner("REBIRTH " .. data.rebirths .. "!", "Cash x" .. tostring(data.mult) .. " forever + 1 pedestal", C.Accent, 3.5)
	EffectsController.cameraPunch(14)
	EffectsController.confetti(120)
end

function handlers.Goal(data)
	HudController.toast("GOAL DONE: " .. data.text .. "  +" .. Format.cash(data.reward), "gold")
	EffectsController.confetti(18)
end

function handlers.Daily(data)
	EffectsController.banner("DAY " .. data.day .. " REWARD", tostring(data.text), C.Blue, 2.8)
	EffectsController.confetti(50)
end

function handlers.Code(data)
	HudController.toast("Code " .. data.code .. " redeemed: " .. tostring(data.text), "good")
	EffectsController.confetti(30)
end

function handlers.Locked(data)
	HudController.toast("LASER DOOR LOCKED for " .. data.duration .. "s!", "good")
end

function handlers.Offline(data)
	local hours = math.floor(data.seconds / 3600)
	local minutes = math.floor((data.seconds % 3600) / 60)
	local away = if hours > 0 then string.format("%dh %dm", hours, minutes) else string.format("%dm", minutes)
	local lines = {
		"You were away for " .. away .. (if data.capped then " (max " .. GameConfig.OfflineCapHours .. "h)" else ""),
		"Your Blobbies earned " .. Format.cash(data.amount) .. "!",
	}
	EffectsController.card("WELCOME BACK!", lines, C.Good, "COLLECT")
	EffectsController.confetti(40)
end

function handlers.Welcome()
	EffectsController.card("SNATCH A BLOBBY!", {
		"Buy Blobbies on the red carpet (walk up, press E).",
		"They earn cash: step on the green pad to collect.",
		"Steal from other bases - hold E on their Blobby!",
		"Thieves? SLAP them (F)! Lock your laser door (L).",
	}, C.Accent, "LET'S GO!")
end

function EffectsController.slapFx(from, to, hit)
	if typeof(to) ~= "Vector3" then
		return
	end
	if hit then
		EffectsController.worldText(to + Vector3.new(0, 1, 0), "SLAP!", Color3.fromRGB(255, 240, 90), 200)
		AudioController.play("Slap", to)
	else
		AudioController.play("Click", from)
	end
end

function EffectsController.knockback(velocity)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or typeof(velocity) ~= "Vector3" then
		return
	end
	root.AssemblyLinearVelocity = velocity
	if humanoid then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		end)
	end
	EffectsController.cameraPunch(10)
end

function EffectsController.init()
	gui = Ui.screen("SnatchEffects", player:WaitForChild("PlayerGui"), 10)
	Ui.autoScale(gui)
	ClientState.Popup:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler and type(data) == "table" then
			handler(data)
		end
	end)
	ClientState.SlapFx:Connect(EffectsController.slapFx)
	ClientState.Knockback:Connect(EffectsController.knockback)
end

EffectsController.handlers = handlers

return EffectsController
