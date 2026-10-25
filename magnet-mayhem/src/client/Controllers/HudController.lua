--[[
	HudController - the main HUD. Built once; updated in place (no rebuilding).

	Top-left: coins (abbreviated, exact on hover) and Magnet Cores.
	Bottom-centre: scrap capacity bar, magnet status, tier, pulse cooldown.
	Top-centre: current objective (tutorial step or starter quest) and event countdown.
	Right: menu buttons. Bottom-right on touch screens: MAGNET (hold), PULSE, SPRINT.
	Also: zone name toast when you change zones, and "next upgrade" progress.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Format = require(Shared.Format)
local Economy = require(Shared.Economy)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MagnetConfig = require(Shared.Config.MagnetConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)

local HudController = {}

local C = Ui.Colors
local player = Players.LocalPlayer
local refs = {}
local shownCoins = 0
local targetCoins = 0

-- Cheapest thing worth saving for (an upgrade or the next tier), for the progress bar.
function HudController.nextGoal(profile)
	if not profile then
		return nil
	end
	local best
	for _, def in ipairs(EconomyConfig.Upgrades) do
		local price = Economy.upgradePrice(def.Key, profile.upgrades[def.Key] or 0)
		if price and (not best or price < best.price) then
			best = { name = def.Name, price = price }
		end
	end
	local tier = MagnetConfig.Tiers[profile.tier + 1]
	if tier and (not best or tier.Price <= best.price * 3) and tier.Price > profile.coins then
		best = { name = tier.Name .. " magnet", price = tier.Price }
	end
	return best
end

local function objectiveText(profile)
	if not profile then
		return "Loading...", ""
	end
	local tut = profile.tutorial
	if tut and not tut.Done then
		local step = QuestConfig.Tutorial[tut.Step]
		if step then
			return step.Text, step.Hint
		end
	end
	local q = profile.quest
	if q and not q.done then
		return string.format("QUEST %d/%d: %s", q.index, q.total, string.upper(q.text)), string.format("%s / %s   -   reward %s coins", Format.short(q.progress), Format.short(q.target), Format.short(q.reward))
	end
	return "KEEP COLLECTING", "Check your daily objectives in the menu."
end

function HudController.render(profile)
	if not refs.coins or not profile then
		return
	end
	targetCoins = profile.coins
	refs.cores.Text = if profile.prestige.Cores > 0 then string.format("%d Magnet Cores", profile.prestige.Cores) else ""
	local stats = profile.stats
	local capacity = stats and stats.MaximumScrapCapacity or 1
	local ratio = math.clamp(profile.carriedMass / capacity, 0, 1)
	TweenService:Create(refs.capFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(ratio, 1) }):Play()
	refs.capFill.BackgroundColor3 = if ratio >= 1 then C.Red elseif ratio > 0.8 then C.AccentDark else C.Accent
	refs.capText.Text = string.format("SCRAP %s / %s   -   worth %s", Format.short(profile.carriedMass), Format.short(capacity), Format.short(profile.carriedValue))
	refs.full.Visible = ratio >= 1
	local tier = MagnetConfig.Tiers[profile.tier]
	refs.tier.Text = string.format("T%d  %s   -   STR %s   RANGE %s", profile.tier, string.upper(tier.Name), Format.stat(stats and stats.MagnetStrength or 1), Format.stat(stats and stats.AttractionRange or 0))
	local title, hint = objectiveText(profile)
	refs.objective.Text = title
	refs.hint.Text = hint
	local goal = HudController.nextGoal(profile)
	if goal then
		refs.goalText.Text = string.format("NEXT: %s  (%s / %s)", goal.name, Format.short(math.min(profile.coins, goal.price)), Format.short(goal.price))
		refs.goalFill.Size = UDim2.fromScale(math.clamp(profile.coins / goal.price, 0, 1), 1)
	else
		refs.goalText.Text = "EVERYTHING MAXED - TIME TO PRESTIGE?"
		refs.goalFill.Size = UDim2.fromScale(1, 1)
	end
	if not profile.persistent then
		refs.saveWarning.Visible = true
	end
end

local function setMagnetStatus(on)
	if not refs.status then
		return
	end
	refs.status.Text = if on then "MAGNET ON" else "MAGNET OFF  -  hold LMB / MAGNET"
	refs.status.TextColor3 = if on then C.Accent else C.Dim
	if refs.magnetButton then
		Ui.setButtonColor(refs.magnetButton, if on then C.Green else C.Accent)
	end
end

local function build()
	local gui = Ui.screen("MagnetHUD", 5)
	refs.gui = gui
	-- Coins.
	local coinPanel = Ui.panel({ Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(230, 64), BackgroundTransparency = 0.12, Parent = gui })
	local coinIcon = Ui.new("Frame", { Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = C.Accent, Parent = coinPanel })
	Ui.corner(coinIcon, 18)
	Ui.title("$", { Size = UDim2.fromScale(1, 1), TextColor3 = C.Black, TextSize = 22, Parent = coinIcon })
	refs.coins = Ui.title("0", { Position = UDim2.fromOffset(58, 6), Size = UDim2.new(1, -66, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 28, Parent = coinPanel })
	refs.cores = Ui.label("", { Position = UDim2.fromOffset(58, 38), Size = UDim2.new(1, -66, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = C.Accent, Parent = coinPanel })
	refs.coinExact = Ui.label("", { Position = UDim2.fromOffset(16, 82), Size = UDim2.fromOffset(230, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = C.Dim, Visible = false, Parent = gui })
	coinPanel.MouseEnter:Connect(function()
		refs.coinExact.Visible = true
	end)
	coinPanel.MouseLeave:Connect(function()
		refs.coinExact.Visible = false
	end)
	refs.saveWarning = Ui.label("Progress is not being saved on this server", { Position = UDim2.fromOffset(16, 100), Size = UDim2.fromOffset(320, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = C.Red, Visible = false, Parent = gui })

	-- Objective (top centre).
	local objective = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(560, 64), BackgroundTransparency = 1, Parent = gui })
	refs.objective = Ui.title("", { Size = UDim2.new(1, 0, 0, 30), TextSize = 24, TextColor3 = C.Text, Parent = objective })
	Ui.new("UIStroke", { Thickness = 2, Color = C.Black, Transparency = 0.3, Parent = refs.objective })
	refs.hint = Ui.label("", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = C.Dim, Parent = objective })
	Ui.new("UIStroke", { Thickness = 1.5, Color = C.Black, Transparency = 0.4, Parent = refs.hint })
	refs.event = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 82), Size = UDim2.fromOffset(340, 34), BackgroundColor3 = Color3.fromRGB(60, 30, 100), Visible = false, Parent = gui })
	refs.eventText = Ui.title("", { Size = UDim2.fromScale(1, 1), TextSize = 16, TextColor3 = Color3.fromRGB(220, 200, 255), Parent = refs.event })

	-- Bottom centre: capacity and magnet.
	local bottom = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(520, 96), BackgroundTransparency = 1, Parent = gui })
	refs.status = Ui.title("MAGNET OFF", { Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = C.Dim, Parent = bottom })
	Ui.new("UIStroke", { Thickness = 1.5, Color = C.Black, Transparency = 0.4, Parent = refs.status })
	local capBack
	capBack, refs.capFill = Ui.bar(bottom, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 22) }, C.Accent)
	Ui.stroke(capBack, C.Line, 1, 0.3)
	refs.capText = Ui.title("", { Size = UDim2.fromScale(1, 1), TextSize = 13, ZIndex = 3, Parent = capBack })
	Ui.new("UIStroke", { Thickness = 1.2, Color = C.Black, Transparency = 0.3, Parent = refs.capText })
	refs.full = Ui.title("FULL! SELL AT THE SHREDDER", { Position = UDim2.fromOffset(0, -26), Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextColor3 = C.Red, Visible = false, Parent = bottom })
	refs.tier = Ui.label("", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = C.Text, Parent = bottom })
	local goalBack
	goalBack, refs.goalFill = Ui.bar(bottom, { Position = UDim2.new(0.15, 0, 0, 72), Size = UDim2.new(0.7, 0, 0, 14) }, C.Green)
	refs.goalText = Ui.label("", { Size = UDim2.fromScale(1, 1), TextSize = 11, Font = Ui.Fonts.Bold, ZIndex = 3, Parent = goalBack })
	refs.pulse = Ui.label("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(150, 22), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, Font = Ui.Fonts.Bold, Parent = bottom })

	-- Zone toast.
	refs.zone = Ui.title("", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(600, 60), TextSize = 46, TextColor3 = C.Text, TextTransparency = 1, Parent = gui })
	refs.zoneStroke = Ui.new("UIStroke", { Thickness = 2, Color = C.Black, Transparency = 1, Parent = refs.zone })

	-- Menu buttons (right side).
	local menu = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.45, 0), Size = UDim2.fromOffset(120, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(menu, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right)
	refs.menuButtons = {}
	for i, tab in ipairs({ "Upgrades", "Codex", "Quests", "Zones", "Shop", "Settings" }) do
		local b = Ui.button(string.upper(tab), { Size = UDim2.fromOffset(120, 38), TextSize = 14, LayoutOrder = i }, if i == 1 then C.Accent else C.PanelLight)
		b.Parent = menu
		refs.menuButtons[tab] = b
	end
	local sellButton = Ui.button("SELL", { Size = UDim2.fromOffset(120, 38), TextSize = 14, LayoutOrder = 10 }, C.Green)
	sellButton.Parent = menu
	sellButton.Activated:Connect(function()
		require(Shared.Net).event("Sell"):FireServer()
	end)

	-- Touch controls.
	if UserInputService.TouchEnabled then
		local touch = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -170, 1, -30), Size = UDim2.fromOffset(260, 220), BackgroundTransparency = 1, Parent = gui })
		-- Keep the cluster left of Roblox's Jump button. The Jump button is sized in real
		-- pixels (70 px at (1,-95) on small screens, 120 px at (1,-170) otherwise) while this
		-- layout is shrunk by the UIScale, so the offset is converted per screen size. Where
		-- that would run into the bottom-centre bar (narrow / 4:3 screens), lift it above.
		local uiScale = gui:FindFirstChildOfClass("UIScale")
		local function placeTouch()
			local size = Ui.viewportSize()
			local jumpLeft = if math.min(size.X, size.Y) <= 500 then 95 else 170
			local scale = if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
			local right = jumpLeft + 12
			local bottom = 30
			if size.X - right - 210 * scale < size.X / 2 + 270 * scale then
				bottom = 146 -- above the capacity bar and its FULL label
			end
			touch.Position = UDim2.new(1, -math.ceil(right / scale), 1, -bottom)
		end
		placeTouch()
		if uiScale then
			uiScale:GetPropertyChangedSignal("Scale"):Connect(placeTouch)
		end
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeTouch)
		end
		local magnet = Ui.button("MAGNET", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(120, 120), TextSize = 20 }, C.Accent)
		Ui.corner(magnet, 60)
		magnet.Parent = touch
		magnet.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				InputController.setMagnet("touch", true)
			end
		end)
		magnet.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				InputController.setMagnet("touch", false)
			end
		end)
		refs.magnetButton = magnet
		local pulse = Ui.button("PULSE", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -132, 1, -10), Size = UDim2.fromOffset(78, 78), TextSize = 15 }, C.Blue)
		Ui.corner(pulse, 39)
		pulse.Parent = touch
		pulse.Activated:Connect(InputController.pulse)
		local sprint = Ui.button("SPRINT", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -132), Size = UDim2.fromOffset(78, 50), TextSize = 13 }, C.PanelLighter)
		sprint.Parent = touch
		sprint.Activated:Connect(InputController.toggleSprint)
	end
end

function HudController.showZone(zoneId)
	local zone = ZoneConfig.ById[zoneId]
	if not zone or not refs.zone then
		return
	end
	refs.zone.Text = string.upper(zone.Name)
	refs.zone.TextTransparency = 0
	refs.zoneStroke.Transparency = 0.3
	task.delay(1.8, function()
		TweenService:Create(refs.zone, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		TweenService:Create(refs.zoneStroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	end)
end

function HudController.menuButton(tab)
	return refs.menuButtons and refs.menuButtons[tab]
end

local function tick()
	-- Smooth coin counter.
	if shownCoins ~= targetCoins then
		local diff = targetCoins - shownCoins
		shownCoins = if math.abs(diff) < 1 then targetCoins else shownCoins + diff * 0.25
		refs.coins.Text = Format.short(shownCoins)
		refs.coinExact.Text = Format.exact(targetCoins) .. " coins"
	end
	-- Pulse cooldown.
	local ready = player:GetAttribute("MM_PulseReady") or 0
	local left = ready - workspace:GetServerTimeNow()
	refs.pulse.Text = if left > 0 then string.format("PULSE %.0fs", math.ceil(left)) else "PULSE READY [R]"
	refs.pulse.TextColor3 = if left > 0 then C.Dim else C.Blue
	-- Event countdown.
	local event = ClientState.event
	if event and event.kind then
		refs.event.Visible = true
		refs.eventText.Text = string.format("%s  %s", event.name, Format.clock(event.endsAt - workspace:GetServerTimeNow()))
	else
		refs.event.Visible = false
	end
end

function HudController.init()
	build()
	ClientState.ProfileChanged:Connect(HudController.render)
	InputController.MagnetChanged:Connect(setMagnetStatus)
	ClientState.ZoneChanged:Connect(HudController.showZone)
	setMagnetStatus(false)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.05 then
			acc = 0
			tick()
		end
	end)
	if ClientState.profile then
		HudController.render(ClientState.profile)
	end
end

HudController.tick = tick

return HudController
