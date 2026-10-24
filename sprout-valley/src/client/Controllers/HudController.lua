--[[
	HudController - always-on HUD: Coins / backpack pills, Seed Shop restock countdown,
	weather chip, travel buttons (Garden / Seeds / Gear / Sell), side menu (Shop, Rewards,
	Bag, Invite), session goals tracker, garden expansion button, toasts and server-wide
	announcement banners.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local WeatherConfig = require(Shared.Config.WeatherConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local HudController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local coinsLabel, bagLabel, restockLabel, weatherLabel, weatherPill, expandButton, rewardsDot
local goalsFrame, toastHolder, bannerHolder
local coinPill
local displayedCoins = 0

local function pill(parent, props, color)
	local frame = Ui.new("Frame", props)
	frame.BackgroundColor3 = color or C.Cream
	Ui.corner(frame, 14)
	Ui.stroke(frame, C.Brown, 2.5)
	frame.Parent = parent
	return frame
end

local function sideButton(text, color, order, parent)
	local button = Ui.button(text, { Size = UDim2.fromOffset(84, 64), TextSize = 17, LayoutOrder = order, Parent = parent }, color)
	button.TextWrapped = true
	return button
end

function HudController.coinTarget()
	if coinPill then
		return coinPill.AbsolutePosition + coinPill.AbsoluteSize * 0.5
	end
	return Vector2.new(0, 0)
end

function HudController.gui()
	return gui
end

---------------------------------------------------------------------------------------------
-- Toasts and banners
---------------------------------------------------------------------------------------------

local KIND_COLORS = {
	good = C.Green,
	warn = C.Orange,
	info = C.Sky,
	danger = C.Red,
}

function HudController.notify(text, kind)
	if not toastHolder then
		return
	end
	local color = KIND_COLORS[kind or "info"] or C.Sky
	local toast = Ui.label(text, {
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Cream,
		Font = Ui.Fonts.Bold,
		TextSize = 17,
		TextColor3 = C.Brown,
		TextWrapped = false,
		LayoutOrder = math.floor(os.clock() * 100),
		Parent = toastHolder,
	})
	Ui.corner(toast, 12)
	Ui.stroke(toast, color, 3)
	Ui.padding(toast, 14, 7)
	local items = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(items, child)
		end
	end
	if #items > 4 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		items[1]:Destroy()
	end
	task.delay(3.5, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.wait(0.35)
			toast:Destroy()
		end
	end)
end

function HudController.announce(text, color)
	if not bannerHolder then
		return
	end
	local c = if type(color) == "table" then Ui.rgb(color) else C.Gold
	local banner = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
		Size = UDim2.fromOffset(680, 54),
		BackgroundColor3 = c,
		Parent = bannerHolder,
	})
	Ui.corner(banner, 16)
	Ui.stroke(banner, c:Lerp(Color3.new(0, 0, 0), 0.5), 3)
	Ui.gradient(banner, Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
	local label = Ui.title(text, {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextScaled = true,
		TextColor3 = C.White,
		Parent = banner,
	})
	Ui.textStroke(label, c:Lerp(Color3.new(0, 0, 0), 0.65), 2)
	Ui.new("UITextSizeConstraint", { MaxTextSize = 24, Parent = label })
	for _, other in ipairs(bannerHolder:GetChildren()) do
		if other ~= banner and other:IsA("Frame") then
			TweenService:Create(other, TweenInfo.new(0.25), { Position = other.Position + UDim2.fromOffset(0, 60) }):Play()
		end
	end
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 0) }):Play()
	task.delay(6, function()
		if banner.Parent then
			TweenService:Create(banner, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			task.wait(0.4)
			banner:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function invite()
	local ok, canSend = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canSend then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	else
		HudController.notify("Invites aren't available right now.", "info")
	end
end

local function build()
	gui = Ui.screen("SproutHUD", 2)

	-- Travel buttons (top left)
	local travel = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(440, 46), BackgroundTransparency = 1, Parent = gui })
	Ui.list(travel, 8, Enum.FillDirection.Horizontal)
	for i, dest in ipairs({ { "Garden", "GARDEN", C.Green }, { "Seeds", "SEEDS", Color3.fromRGB(150, 205, 70) }, { "Gear", "GEAR", C.Sky }, { "Sell", "SELL", C.Orange } }) do
		local b = Ui.button(dest[2], { Size = UDim2.fromOffset(100, 44), TextSize = 18, LayoutOrder = i, Parent = travel }, dest[3])
		b.Activated:Connect(function()
			Net.event("Travel"):FireServer(dest[1])
		end)
	end

	-- Coins + backpack (top centre)
	local top = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(360, 48), BackgroundTransparency = 1, Parent = gui })
	coinPill = pill(top, { Size = UDim2.fromOffset(215, 48) }, C.Cream)
	Ui.coinIcon(coinPill, 30, { Position = UDim2.fromOffset(10, 9) })
	coinsLabel = Ui.title("0", { Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -56, 1, 0), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 140, 20), Parent = coinPill })
	local bagPill = pill(top, { Position = UDim2.fromOffset(225, 0), Size = UDim2.fromOffset(135, 48) }, C.Cream)
	bagLabel = Ui.title("Bag 0/60", { Size = UDim2.fromScale(1, 1), TextSize = 20, Parent = bagPill })

	-- Restock + weather (top right)
	local right = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(250, 96), BackgroundTransparency = 1, Parent = gui })
	local restockPill = pill(right, { Size = UDim2.fromOffset(250, 44) }, Color3.fromRGB(235, 250, 220))
	restockLabel = Ui.title("Seeds restock 5:00", { Size = UDim2.fromScale(1, 1), TextSize = 19, TextColor3 = C.GreenDark, Parent = restockPill })
	weatherPill = pill(right, { Position = UDim2.fromOffset(0, 50), Size = UDim2.fromOffset(250, 44) }, Color3.fromRGB(225, 240, 255))
	weatherLabel = Ui.title("Clear skies", { Size = UDim2.fromScale(1, 1), TextSize = 18, TextColor3 = Color3.fromRGB(60, 110, 170), Parent = weatherPill })

	-- Side menu (left)
	local side = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(84, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(side, 10)
	local shop = sideButton("SHOP", C.Pink, 1, side)
	shop.Activated:Connect(function()
		Ui.toggleWindow("Store")
	end)
	local rewards = sideButton("REWARDS", C.Purple, 2, side)
	rewards.Activated:Connect(function()
		Ui.toggleWindow("Rewards")
	end)
	rewardsDot = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.Red, Visible = false, ZIndex = 5, Parent = rewards })
	Ui.corner(rewardsDot, 9)
	Ui.stroke(rewardsDot, C.White, 2)
	local bag = sideButton("BAG", C.BrownLight, 3, side)
	bag.Activated:Connect(function()
		Ui.toggleWindow("Backpack")
	end)
	local inviteButton = sideButton("INVITE", C.Sky, 4, side)
	inviteButton.Activated:Connect(invite)

	-- Goals (right middle)
	goalsFrame = Ui.panel({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 10), Size = UDim2.fromOffset(250, 40), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.1, Parent = gui })
	Ui.padding(goalsFrame, 10, 8)
	Ui.list(goalsFrame, 6)

	-- Expand (bottom right)
	expandButton = Ui.button("EXPAND GARDEN", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -110), Size = UDim2.fromOffset(240, 52), TextSize = 18, Visible = false, Parent = gui }, C.Orange)
	expandButton.Activated:Connect(function()
		Net.event("ExpandPlot"):FireServer()
	end)

	toastHolder = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118), Size = UDim2.fromOffset(700, 200), BackgroundTransparency = 1, Parent = gui })
	Ui.list(toastHolder, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	bannerHolder = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(700, 200), BackgroundTransparency = 1, ClipsDescendants = false, Parent = gui })
end

local function renderGoals(goals)
	Ui.clear(goalsFrame)
	Ui.title("GOALS", { Size = UDim2.new(1, 0, 0, 22), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.GreenDark, LayoutOrder = 0, Parent = goalsFrame })
	for i, goal in ipairs(goals or {}) do
		local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = i, Parent = goalsFrame })
		Ui.label(goal.text, { Size = UDim2.new(1, -60, 0, 18), TextSize = 14, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Ui.label("+" .. Format.coins(goal.reward), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(60, 18), TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = Color3.fromRGB(200, 140, 20), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
		local _, fill = Ui.bar(row, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 14) }, C.Green)
		fill.Size = UDim2.fromScale(math.clamp(goal.progress / math.max(goal.target, 1), 0, 1), 1)
	end
end

local function render(profile)
	if not profile then
		return
	end
	bagLabel.Text = string.format("Bag %d/%d", #profile.backpack, profile.capacity)
	bagLabel.TextColor3 = if #profile.backpack >= profile.capacity then C.Red else C.Brown
	renderGoals(profile.goals)
	rewardsDot.Visible = profile.daily ~= nil and profile.daily.canClaim == true
	local plot = profile.plot or {}
	if plot.id and plot.expandCost then
		expandButton.Visible = true
		expandButton.Text = string.format("EXPAND +%d TILES  (%s)", plot.cols or 6, Format.coins(plot.expandCost))
		expandButton.BackgroundColor3 = if profile.coins >= plot.expandCost then C.Orange else C.Dim
	else
		expandButton.Visible = false
	end
end

local function update()
	local profile = ClientState.profile
	if profile then
		-- Count up smoothly towards the real balance.
		local target = profile.coins
		local diff = target - displayedCoins
		if math.abs(diff) < 1 then
			displayedCoins = target
		else
			displayedCoins += diff * 0.2
		end
		coinsLabel.Text = Format.coins(displayedCoins)
	end
	local now = ClientState.serverNow()
	local nextRestock = workspace:GetAttribute("SV_NextRestock") or 0
	restockLabel.Text = "Seeds restock " .. Format.clock(math.max(0, nextRestock - now))
	local weather = workspace:GetAttribute("SV_Weather") or ""
	local def = WeatherConfig.Events[weather]
	if def then
		local ends = workspace:GetAttribute("SV_WeatherEnds") or 0
		weatherLabel.Text = string.format("%s  %s", def.Name, Format.clock(math.max(0, ends - now)))
		weatherPill.BackgroundColor3 = Ui.rgb(def.Color):Lerp(C.White, 0.55)
	else
		local nextWeather = workspace:GetAttribute("SV_NextWeather") or 0
		weatherLabel.Text = if nextWeather > now then "Clear skies  (weather in " .. Format.clock(nextWeather - now) .. ")" else "Clear skies"
		weatherPill.BackgroundColor3 = Color3.fromRGB(225, 240, 255)
	end
end

function HudController.init()
	build()
	ClientState.ProfileChanged:Connect(render)
	ClientState.Notified:Connect(HudController.notify)
	ClientState.Announced:Connect(HudController.announce)
	if ClientState.profile then
		render(ClientState.profile)
	end
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.05 then
			accumulator = 0
			update()
		end
	end)
	update()
end

return HudController
