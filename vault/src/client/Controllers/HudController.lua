--[[
	HudController - the always-on screen.

	Top left   Cash and Vault Tokens (counting up), boost timer when a Value Boost runs.
	Top centre the depth chip (code, name) and the next depth's requirement with progress.
	Left       menu buttons (Upgrades, Depths, Book, Achievements, Daily, Stats, Boards,
	           Shop, Settings) with their keyboard shortcut.
	Bottom     the carried panel: items, slots / capacity bar, value; it turns red and
	           pulses "STACK FULL - DEPOSIT" when full, and an arrow on the floor plus a
	           marker over the machine point at the nearest deposit machine.
	Right      deposit summary card (items, value, multiplier, payout, NEW RECORD!).
	Mobile     a large PICKUP button (hold to keep collecting).
	Also: toasts (Notify), popups (achievement, discovery, rare find, depth unlocked,
	daily done, rebirth, stack full) and global announcements.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local DepthConfig = require(Shared.Config.DepthConfig)
local LootConfig = require(Shared.Config.LootConfig)
local Format = require(Shared.Format)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local InputController = require(script.Parent.InputController)
local DepositController = require(script.Parent.DepositController)
local Ui = require(script.Parent.Ui)

local C = Ui.Colors
local HudController = {}

local gui
local cashLabel, tokenLabel, boostLabel
local shownCash, shownTokens = 0, 0
local depthCode, depthName, nextLabel, nextFill
local carryPanel, carryCount, carryValue, carryFill, fullBanner
local summary, summaryLines
local toastHolder, popupHolder, announceLabel
local arrow, marker
local pickupButton

local MENU = {
	{ "Upgrades", "UPGRADES", "U" },
	{ "Depths", "DEPTHS", "G" },
	{ "Book", "BOOK", "B" },
	{ "Achievements", "AWARDS", "J" },
	{ "Daily", "DAILY", "" },
	{ "Stats", "STATS", "K" },
	{ "Leaderboards", "BOARDS", "L" },
	{ "Shop", "SHOP", "P" },
	{ "Settings", "SETTINGS", "O" },
}

-- Currency ---------------------------------------------------------------------------------

local function currencyChip(y, color, icon)
	local chip = Ui.panel({ Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(230, 44), BackgroundTransparency = 0.1, Parent = gui }, 10)
	local badge = Ui.new("Frame", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = color, Parent = chip })
	Ui.corner(badge, 15)
	Ui.title(icon, { Size = UDim2.fromScale(1, 1), TextSize = 16, TextColor3 = C.Black, Parent = badge })
	return Ui.title("0", { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -54, 1, 0), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, Parent = chip })
end

local function pop(label)
	local scale = label:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = label })
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 1 }):Play()
end

-- Toasts and popups ------------------------------------------------------------------------

local KIND_COLORS = { good = C.Green, error = C.Red, warn = C.Accent, info = C.Blue }

function HudController.toast(text, kind)
	local color = KIND_COLORS[kind or "info"] or C.Text
	local frame = Ui.panel({ Size = UDim2.fromOffset(420, 38), BackgroundTransparency = 0.12, LayoutOrder = -math.floor(os.clock() * 100) }, 10)
	Ui.new("Frame", { Size = UDim2.new(0, 4, 1, -12), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = color, Parent = frame })
	Ui.label(text, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	frame.Parent = toastHolder
	if kind == "error" then
		AudioController.play("NoFunds", { volume = 0.6 })
	end
	local items = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	if #items > 4 then
		table.sort(items, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		items[1]:Destroy()
	end
	task.delay(3.2, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

-- A bigger card for milestones (queued so two never overlap).
local popupQueue = {}
local popupBusy = false

local function showNextPopup()
	if popupBusy or #popupQueue == 0 then
		return
	end
	popupBusy = true
	local p = table.remove(popupQueue, 1)
	local card = Ui.new("CanvasGroup", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.fromOffset(440, 96), BackgroundColor3 = C.Panel, GroupTransparency = 1, Parent = popupHolder })
	Ui.corner(card, 12)
	Ui.stroke(card, p.color, 2, 0)
	local textX = 16
	if p.item then
		Ui.lootIcon(card, p.item, 80, { Position = UDim2.fromOffset(8, 8), silhouette = false })
		textX = 96
	end
	Ui.title(p.title, { Position = UDim2.fromOffset(textX, 10), Size = UDim2.new(1, -textX - 12, 0, 28), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = p.color, Parent = card })
	Ui.label(p.text, { Position = UDim2.fromOffset(textX, 42), Size = UDim2.new(1, -textX - 12, 0, 46), TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
	if p.sound then
		AudioController.play(p.sound)
	end
	TweenService:Create(card, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	task.delay(p.duration or 3, function()
		TweenService:Create(card, TweenInfo.new(0.35), { GroupTransparency = 1 }):Play()
		task.delay(0.4, function()
			card:Destroy()
			popupBusy = false
			showNextPopup()
		end)
	end)
end

function HudController.popup(p)
	table.insert(popupQueue, p)
	showNextPopup()
end

local lastFullPopup = 0
local function onPopup(kind, data)
	if kind == "Achievement" then
		HudController.popup({ title = "ACHIEVEMENT: " .. string.upper(data.name or ""), text = (data.text or "") .. (if (data.tokens or 0) > 0 then "  +" .. data.tokens .. " Vault Tokens" else ""), color = C.Accent, sound = "Achievement" })
	elseif kind == "Discovery" then
		local rarity = LootConfig.Rarities[data.rarity]
		HudController.popup({ title = "NEW: " .. string.upper(data.name or ""), text = string.format("%s - added to your Collection Book (%d / %d).", data.rarity or "", data.count or 0, data.total or 0), color = if rarity then Ui.rgb(rarity.Color) else C.Text, item = data.id, duration = 2.4 })
	elseif kind == "RareFind" then
		local rarity = LootConfig.Rarities[data.rarity]
		HudController.popup({ title = "RARE FIND!", text = string.format("You found the %s (%s)! +%d Vault Tokens", data.name or "", data.rarity or "", data.tokens or 0), color = if rarity then Ui.rgb(rarity.Color) else C.Purple, item = data.id, sound = "RareDiscovery", duration = 4 })
	elseif kind == "DepthUnlocked" then
		HudController.popup({ title = (data.code or "") .. " UNLOCKED", text = (data.name or "") .. " is open. Take the elevator down - its loot is worth far more.", color = C.Green, sound = "FloorUnlock", duration = 4 })
	elseif kind == "Daily" then
		HudController.popup({ title = "DAILY CHALLENGE DONE", text = string.format("%s  +$%s  +%d Tokens", data.text or "", Format.short(data.cash or 0), data.tokens or 0), color = C.Blue, sound = "Achievement" })
	elseif kind == "TutorialDone" then
		HudController.popup({ title = "YOU'RE A VAULT RUNNER", text = "Collect, deposit, upgrade, go deeper. Every depth hides better loot.", color = C.Accent, sound = "Achievement", duration = 4 })
	elseif kind == "Rebirth" then
		HudController.popup({ title = "REBIRTH " .. (data.count or 1), text = string.format("Loot is now worth x%s forever. +%d Vault Tokens.", Format.stat(data.bonus or 1), data.tokens or 0), color = C.Purple, sound = "FloorUnlock", duration = 5 })
	elseif kind == "StackFull" then
		if os.clock() - lastFullPopup > 3 then
			lastFullPopup = os.clock()
			HudController.toast("Your stack is full - deposit it at a Deposit Machine.", "warn")
			if not data.localOnly then
				AudioController.play("StackFull")
			end
		end
	end
end

local function announce(text, color)
	announceLabel.Text = text
	announceLabel.TextColor3 = if type(color) == "table" then Ui.rgb(color) elseif typeof(color) == "Color3" then color else C.Accent
	announceLabel.Visible = true
	announceLabel.TextTransparency = 0
	local token = os.clock()
	announceLabel:SetAttribute("Token", token)
	task.delay(4.5, function()
		if announceLabel:GetAttribute("Token") == token then
			TweenService:Create(announceLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

-- Deposit summary --------------------------------------------------------------------------

local function showSummary(data)
	Ui.clear(summaryLines)
	local function line(text, color, size, order)
		Ui.label(text, { Size = UDim2.new(1, 0, 0, size + 6), TextSize = size, Font = Ui.Fonts.Bold, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = summaryLines })
	end
	line("DEPOSITED", C.Dim, 14, 1)
	line(string.format("%d items  -  $%s", data.count or 0, Format.short(data.value or 0)), C.Text, 16, 2)
	if (data.multiplier or 1) > 1.0001 then
		line(string.format("Deposit bonus  x%s", Format.stat(data.multiplier)), C.Blue, 15, 3)
	end
	line("+$" .. Format.short(data.payout or 0), C.Green, 30, 4)
	if data.record then
		line("NEW RECORD DEPOSIT!", C.Accent, 16, 5)
	end
	summary.Visible = true
	summary.GroupTransparency = 1
	TweenService:Create(summary, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	local token = os.clock()
	summary:SetAttribute("Token", token)
	task.delay(3.6, function()
		if summary:GetAttribute("Token") == token then
			TweenService:Create(summary, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		end
	end)
end

-- Updates ----------------------------------------------------------------------------------

local function refreshProfile()
	local p = ClientState.profile
	if not p then
		return
	end
	local depth = ClientState.depth()
	local def = DepthConfig.get(depth)
	depthCode.Text = def.Code
	depthCode.Parent.BackgroundColor3 = Ui.rgb(def.Palette.Accent)
	depthName.Text = string.upper(def.Name)
	local nextDef = DepthConfig.get(p.highestDepth + 1)
	if nextDef then
		local need = "$" .. Format.short(nextDef.UnlockCash) .. (if nextDef.UnlockTokens > 0 then " + " .. nextDef.UnlockTokens .. " Tokens" else "")
		nextLabel.Text = string.format("NEXT: %s %s  -  %s", nextDef.Code, string.upper(nextDef.Name), need)
		local cashPart = if nextDef.UnlockCash > 0 then math.clamp(p.cash / nextDef.UnlockCash, 0, 1) else 1
		local tokenPart = if nextDef.UnlockTokens > 0 then math.clamp(p.tokens / nextDef.UnlockTokens, 0, 1) else 1
		local progress = math.min(cashPart, tokenPart)
		nextFill.Size = UDim2.fromScale(progress, 1)
		nextFill.BackgroundColor3 = if progress >= 1 then C.Green else C.Accent
	else
		nextLabel.Text = "DEEPEST VAULT REACHED  -  ANCIENT VAULT: COMING SOON"
		nextFill.Size = UDim2.fromScale(1, 1)
	end
end

local function refreshInventory()
	local inv = ClientState.inventory
	local full = ClientState.isFull()
	carryCount.Text = string.format("CARRYING %d   |   %d / %d SLOTS", inv.count or 0, inv.slots or 0, inv.capacity or 0)
	carryValue.Text = "$" .. Format.short(inv.value or 0)
	local fraction = if (inv.capacity or 0) > 0 then math.clamp(inv.slots / inv.capacity, 0, 1) else 0
	TweenService:Create(carryFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(fraction, 1) }):Play()
	carryFill.BackgroundColor3 = if full then C.Red elseif fraction > 0.75 then C.Accent else C.Green
	fullBanner.Visible = full
end

local function step(dt)
	local p = ClientState.profile
	if p then
		local k = math.min(1, dt * 8)
		shownCash = if math.abs(p.cash - shownCash) < 1 then p.cash else shownCash + (p.cash - shownCash) * k
		shownTokens = p.tokens
		cashLabel.Text = "$" .. Format.short(shownCash)
		tokenLabel.Text = Format.exact(shownTokens)
		local boostLeft = (p.boostUntil or 0) - ClientState.serverTime()
		boostLabel.Visible = boostLeft > 0
		if boostLeft > 0 then
			boostLabel.Text = "VALUE BOOST +25%  " .. Format.clock(boostLeft)
		end
	end
	if fullBanner.Visible then
		fullBanner.TextTransparency = 0.25 + 0.25 * math.sin(os.clock() * 6)
	end
	-- Deposit arrow when full.
	local root = ClientState.root()
	local machine = root and ClientState.isFull() and DepositController.nearest(root.Position)
	if machine and machine.chute and not ClientState.riding then
		local target = machine.chute.Position
		local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if flat.Magnitude > 6 then
			local dir = flat.Unit
			local base = root.Position + dir * 4.5 - Vector3.new(0, 2.6, 0)
			arrow.CFrame = CFrame.lookAt(base, base + dir) * CFrame.new(0, 0, -0.4 * math.sin(os.clock() * 5))
			arrow.Transparency = 0.15
		else
			arrow.Transparency = 1
		end
		marker.Adornee = machine.chute
		marker.Enabled = true
	else
		arrow.Transparency = 1
		marker.Enabled = false
	end
end

function HudController.init()
	gui = Ui.screen("VaultHud", 5)
	cashLabel = currencyChip(16, C.Green, "$")
	tokenLabel = currencyChip(66, C.Accent, "T")
	boostLabel = Ui.label("", { Position = UDim2.fromOffset(16, 116), Size = UDim2.fromOffset(230, 22), Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = C.Purple, TextXAlignment = Enum.TextXAlignment.Left, Visible = false, Parent = gui })

	-- Depth chip.
	local depthPanel = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(440, 66), BackgroundTransparency = 0.1, Parent = gui }, 12)
	local codeChip = Ui.new("Frame", { Size = UDim2.fromOffset(58, 40), Position = UDim2.fromOffset(8, 6), BackgroundColor3 = C.Accent, Parent = depthPanel })
	Ui.corner(codeChip, 8)
	depthCode = Ui.title("B1", { Size = UDim2.fromScale(1, 1), TextSize = 22, TextColor3 = C.Black, Parent = codeChip })
	depthName = Ui.title("CASH VAULT", { Position = UDim2.fromOffset(76, 6), Size = UDim2.new(1, -86, 0, 26), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Parent = depthPanel })
	nextLabel = Ui.label("", { Position = UDim2.fromOffset(76, 30), Size = UDim2.new(1, -86, 0, 16), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = depthPanel })
	local _, fill = Ui.bar(depthPanel, { Position = UDim2.new(0, 8, 1, -14), Size = UDim2.new(1, -16, 0, 7) }, C.Accent)
	nextFill = fill

	-- Menu buttons.
	local menu = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 30), Size = UDim2.fromOffset(120, #MENU * 40), BackgroundTransparency = 1, Parent = gui })
	Ui.list(menu, 4)
	for i, entry in ipairs(MENU) do
		local b = Ui.button(entry[2], { Size = UDim2.fromOffset(120, 36), TextSize = 14, LayoutOrder = i }, C.PanelLight)
		b.Parent = menu
		if entry[3] ~= "" and not UserInputService.TouchEnabled then
			Ui.label(entry[3], { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(16, 16), TextSize = 11, TextColor3 = C.Dim, Parent = b })
		end
		b.Activated:Connect(function()
			Ui.toggleWindow(entry[1])
		end)
	end

	-- Carried panel.
	carryPanel = Ui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(460, 64), BackgroundTransparency = 0.08, Parent = gui }, 12)
	carryCount = Ui.label("", { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -140, 0, 24), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = carryPanel })
	carryValue = Ui.title("$0", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 4), Size = UDim2.fromOffset(130, 28), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Green, Parent = carryPanel })
	local _, cfill = Ui.bar(carryPanel, { Position = UDim2.new(0, 14, 1, -24), Size = UDim2.new(1, -28, 0, 12) }, C.Green)
	carryFill = cfill
	fullBanner = Ui.title("STACK FULL  -  DEPOSIT", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(460, 30), TextSize = 24, TextColor3 = C.Red, TextStrokeTransparency = 0.4, Visible = false, Parent = carryPanel })

	-- Deposit summary.
	summary = Ui.new("CanvasGroup", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.45, 0), Size = UDim2.fromOffset(260, 170), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.05, Visible = false, Parent = gui })
	Ui.corner(summary, 12)
	Ui.stroke(summary, C.Green, 2, 0.2)
	summaryLines = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = summary })
	Ui.padding(summaryLines, 14, 10)
	Ui.list(summaryLines, 2)

	-- Toasts, popups, announcements.
	toastHolder = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128), Size = UDim2.fromOffset(420, 200), BackgroundTransparency = 1, Parent = gui })
	Ui.list(toastHolder, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	popupHolder = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	announceLabel = Ui.title("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(800, 26), TextSize = 18, TextStrokeTransparency = 0.4, Visible = false, Parent = gui })

	-- Mobile pickup button.
	pickupButton = Ui.button("PICKUP", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -150), Size = UDim2.fromOffset(110, 110), TextSize = 20, Visible = UserInputService.TouchEnabled, Parent = gui }, C.Accent)
	Ui.corner(pickupButton, 55)
	pickupButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.setHeld("touch", true)
		end
	end)
	pickupButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.setHeld("touch", false)
		end
	end)

	-- World pointer to the deposit machine.
	arrow = Instance.new("WedgePart")
	arrow.Name = "DepositArrow"
	arrow.Size = Vector3.new(1.6, 0.2, 2.4)
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.CastShadow = false
	arrow.Material = Enum.Material.Neon
	arrow.Color = Color3.fromRGB(255, 90, 70)
	arrow.Transparency = 1
	arrow.Parent = Workspace.CurrentCamera
	marker = Ui.new("BillboardGui", { Size = UDim2.fromOffset(160, 40), StudsOffset = Vector3.new(0, 6, 0), AlwaysOnTop = true, LightInfluence = 0, Enabled = false, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	Ui.title("DEPOSIT HERE", { Size = UDim2.fromScale(1, 1), TextSize = 20, TextColor3 = C.Green, TextStrokeTransparency = 0.3, Parent = marker })

	ClientState.ProfileChanged:Connect(function(p)
		if math.abs((p.tokens or 0) - shownTokens) > 0 then
			pop(tokenLabel)
		end
		refreshProfile()
	end)
	ClientState.DepthChanged:Connect(refreshProfile)
	ClientState.InventoryChanged:Connect(refreshInventory)
	ClientState.Notified:Connect(HudController.toast)
	ClientState.PopupRequested:Connect(onPopup)
	ClientState.Announced:Connect(announce)
	ClientState.Deposited:Connect(function(userId, data)
		if userId == Players.LocalPlayer.UserId then
			showSummary(data)
			pop(cashLabel)
		end
	end)
	ClientState.RareEvent:Connect(function(phase, data)
		if phase == "Spawn" then
			local def = DepthConfig.get(data.depth)
			announce(string.format("RARE LOOT: the %s has appeared in %s %s!", data.name or "treasure", def and def.Code or "", def and def.Name or ""), LootConfig.Rarities[data.rarity] and LootConfig.Rarities[data.rarity].Color or C.Purple)
		end
	end)
	refreshInventory()
	RunService.RenderStepped:Connect(step)
end

return HudController
