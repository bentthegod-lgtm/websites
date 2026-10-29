--[[
	HudController - the always-on HUD.

	Top-left: coins (abbreviated, exact on hover), selected machine, run status and the
	current objective (featured objective or the next tutorial step / goal). Bottom-left:
	menu buttons with an "upgrade available" badge. Right: toasts (notifications) and
	popups (achievements, challenges, machine unlocks, records, facilities, prestige).
	Top-centre: announcements. (The live flight readout, combos and popups during your own
	run live in JuiceController.)
	Duel invites / status appear above the launch panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
local Economy = require(Shared.Economy)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local MachineConfig = require(Shared.Config.MachineConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local HudController = {}

local C = Ui.Colors
local player = Players.LocalPlayer
local gui
local refs = {}
local toastList, popupHolder, announceHolder

local function upgradeAvailable(p)
	for _, def in ipairs(UpgradeConfig.List) do
		local price = Economy.cost(def.Key, p.upgrades[def.Key] or 0)
		if price and p.coins >= price then
			return true
		end
	end
	return false
end

-- The next goal shown under the coins.
function HudController.nextGoal(p)
	if not p then
		return "Loading lab data..."
	end
	if p.tutorial and not p.tutorial.Done then
		local step = QuestConfig.Tutorial[p.tutorial.Step]
		if step then
			return "TUTORIAL: " .. step.Text
		end
	end
	if not ClientState.myPad() then
		return "Walk onto a glowing green launch pad and press E"
	end
	if p.featured then
		return "FEATURED: " .. p.featured.name
	end
	return "Launch, crash, upgrade!"
end

function HudController.toast(text, kind)
	local color = if kind == "good" then C.Green elseif kind == "error" then C.Red elseif kind == "warn" then C.Accent else C.Text
	local t = Ui.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Panel, Parent = toastList }, 8)
	Ui.padding(t, 10, 6)
	Ui.label(text, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 14, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Parent = t })
	if kind == "error" then
		AudioController.play("Denied", nil, true)
	end
	local items = {}
	for _, child in ipairs(toastList:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	if #items > 4 then
		items[1]:Destroy()
	end
	task.delay(4, function()
		if t.Parent then
			t:Destroy()
		end
	end)
end

local POPUP_TEXT = {
	Achievement = function(d)
		return "ACHIEVEMENT: " .. d.name, d.text .. (if d.reward and d.reward > 0 then string.format("  (+%d coins)", d.reward) else "") .. (if d.cosmetic then "  -  unlocked " .. d.cosmetic else ""), "Achievement"
	end,
	Challenge = function(d)
		return "DAILY CHALLENGE DONE", string.format("%s  (+%d coins)", d.text, d.reward), "ChallengeDone"
	end,
	Machine = function(d)
		return "NEW MACHINE", d.name .. " unlocked!", "MachineUnlock"
	end,
	Facility = function(d)
		return "FACILITY ACCESS", d.name .. (if d.built then " unlocked! Travel there from the Facilities menu (M) or the hub's transit gate." else " - access granted. Under construction: opens in a future update."), "MachineUnlock"
	end,
	FacilityReady = function(d)
		return "NEW FACILITY AVAILABLE", string.format("%s - unlock it for %s coins in the Facilities menu (M).", d.name, Format.short(d.cost or 0)), "ObjectiveDone"
	end,
	Arrived = function(d)
		return string.upper(d.name), "Claim a launch pad here. HUB TRANSIT kiosk (behind the deck) takes you back.", "TransitWhoosh"
	end,
	Prestige = function(d)
		return "LAB CERTIFIED", string.format("+%d Lab Credits (total %d)", d.credits, d.total), "NewRecord"
	end,
	TutorialDone = function()
		return "TUTORIAL COMPLETE", "You're a certified crash tester. Keep launching!", "ObjectiveDone"
	end,
}

function HudController.popup(kind, data)
	local maker = POPUP_TEXT[kind]
	if not maker then
		return
	end
	local title, body, sound = maker(data or {})
	local p = Ui.panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(340, 72), BackgroundColor3 = C.PanelLight, Parent = popupHolder }, 10)
	Ui.stroke(p, C.Accent, 2, 0)
	Ui.title(title, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 24), TextSize = 17, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = p })
	Ui.label(body, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 38), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = p })
	AudioController.play(sound, nil, true)
	local scale = Ui.new("UIScale", { Scale = 0.85, Parent = p })
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(4.5, function()
		if p.Parent then
			p:Destroy()
		end
	end)
end

function HudController.announce(text, color)
	local label = Ui.title(text, { Size = UDim2.new(1, 0, 0, 30), TextSize = 22, TextColor3 = if color then Color3.fromRGB(color[1], color[2], color[3]) else C.Accent, TextStrokeTransparency = 0.5, Parent = announceHolder })
	task.delay(4, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.7, function()
				label:Destroy()
			end)
		end
	end)
end

-- Floating flight call-outs ("HEAVY IMPACT", "RING!") during your own run.
function HudController.callout(text, color)
	local label = Ui.title(text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.2, 0.36), Size = UDim2.fromOffset(400, 40), TextSize = 30, TextColor3 = color or C.Accent, TextStrokeTransparency = 0.3, Parent = gui })
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad), { Position = label.Position - UDim2.fromOffset(0, 60), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.1, function()
		label:Destroy()
	end)
end

function HudController.render()
	local p = ClientState.profile
	if not p or not gui then
		return
	end
	refs.coins.Text = Format.short(p.coins)
	refs.coinsExact.Text = Format.exact(p.coins) .. " coins"
	local machine = MachineConfig.ById[p.selected]
	refs.machine.Text = (machine and machine.Name or "?") .. (if p.prestige.Credits > 0 then string.format("   -   %d Lab Credits", p.prestige.Credits) else "")
	refs.goal.Text = HudController.nextGoal(p)
	refs.badge.Visible = upgradeAvailable(p)
	refs.saving.Visible = p.persistent == false
end

function HudController.tick()
	local LaunchController = require(script.Parent.LaunchController)
	local pad = ClientState.myPad()
	local status = if pad then LaunchController.status() else "NoPad"
	refs.status.Text = ({ NoPad = "No pad claimed", Ready = "READY TO LAUNCH", Charging = "CHARGING...", Cooldown = "COOLING DOWN", Flight = "DUMMY IN FLIGHT" })[status] or status
	refs.status.TextColor3 = if status == "Ready" then C.Green elseif status == "Charging" then C.Red else C.Dim
	local duel = ClientState.duel
	refs.duel.Visible = duel ~= nil or refs.invite.Visible
	if duel then
		refs.duelText.Text = string.format("DUEL vs %s  -  you: %s  them: %s  -  %ds", duel.opponent, if duel.myScore then Format.short(duel.myScore) else "next run", if duel.theirScore then Format.short(duel.theirScore) else "waiting", math.floor(duel.endsIn or 0))
	end
end

function HudController.build()
	gui = Ui.screen("CrashHUD", 2)
	-- Top-left status panel.
	local top = Ui.panel({ Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(380, 112), BackgroundTransparency = 0.12, Parent = gui }, 12)
	Ui.title("CRASH LAB", { Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(160, 20), TextSize = 16, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
	refs.coins = Ui.title("0", { Position = UDim2.fromOffset(14, 26), Size = UDim2.fromOffset(200, 36), TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
	refs.coinsExact = Ui.label("", { Position = UDim2.fromOffset(14, 26), Size = UDim2.fromOffset(200, 36), TextSize = 13, TextColor3 = C.Dim, Visible = false, TextXAlignment = Enum.TextXAlignment.Right, Parent = top })
	refs.coins.MouseEnter:Connect(function()
		refs.coinsExact.Visible = true
	end)
	refs.coins.MouseLeave:Connect(function()
		refs.coinsExact.Visible = false
	end)
	Ui.label("COINS", { Position = UDim2.fromOffset(220, 34), Size = UDim2.fromOffset(60, 20), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
	refs.status = Ui.label("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(170, 18), TextSize = 13, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Right, Parent = top })
	refs.machine = Ui.label("", { Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 0, 18), TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
	refs.goal = Ui.label("", { Position = UDim2.fromOffset(14, 82), Size = UDim2.new(1, -28, 0, 24), TextSize = 14, Font = Ui.Fonts.Bold, TextWrapped = true, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
	refs.saving = Ui.label("Saving unavailable here", { Position = UDim2.fromOffset(16, 132), Size = UDim2.fromOffset(300, 16), TextSize = 12, TextColor3 = C.Red, TextXAlignment = Enum.TextXAlignment.Left, Visible = false, Parent = gui })
	-- Menu buttons (bottom-left).
	local buttons = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(130, 290), BackgroundTransparency = 1, Parent = gui })
	Ui.list(buttons, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	local function menuButton(text, tab, order)
		local b = Ui.button(text, { Size = UDim2.fromOffset(130, 42), TextSize = 15, LayoutOrder = order }, C.PanelLight)
		b.Parent = buttons
		b.Activated:Connect(function()
			require(script.Parent.InputController).MenuRequested:Fire(tab)
		end)
		return b
	end
	local upgrades = menuButton("UPGRADES", "Upgrades", 1)
	Ui.setButtonColor(upgrades, C.Accent)
	refs.badge = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.Green, Visible = false, Parent = upgrades })
	Ui.corner(refs.badge, 8)
	menuButton("MACHINES", "Machines", 2)
	menuButton("LAB LOG", "LabLog", 3)
	menuButton("LOCKER", "Locker", 4)
	menuButton("MENU", "Settings", 5)
	-- Toasts / popups / announcements.
	toastList = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -240), Size = UDim2.fromOffset(340, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(toastList, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	popupHolder = Ui.new("Frame", { Position = UDim2.new(0, 0, 0, 16), Size = UDim2.new(1, 0, 0, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(popupHolder, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right)
	announceHolder = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(800, 100), BackgroundTransparency = 1, Parent = gui })
	Ui.list(announceHolder, 2, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	-- Duel bar (invite or active duel).
	refs.duel = Ui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -284), Size = UDim2.fromOffset(520, 40), Visible = false, Parent = gui }, 10)
	refs.duelText = Ui.label("", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 14, Font = Ui.Fonts.Bold, Parent = refs.duel })
	refs.invite = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = refs.duel })
	refs.inviteText = Ui.label("", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -200, 1, 0), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = refs.invite })
	local accept = Ui.button("ACCEPT", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.fromOffset(84, 30), TextSize = 13 }, C.Green)
	accept.Parent = refs.invite
	local decline = Ui.button("DECLINE", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(84, 30), TextSize = 13 }, C.PanelLighter)
	decline.Parent = refs.invite
	accept.Activated:Connect(function()
		Net.event("Duel"):FireServer("Accept")
		refs.invite.Visible = false
	end)
	decline.Activated:Connect(function()
		Net.event("Duel"):FireServer("Decline")
		refs.invite.Visible = false
	end)
end

function HudController.init()
	HudController.build()
	ClientState.ProfileChanged:Connect(HudController.render)
	ClientState.PadsChanged:Connect(HudController.render)
	ClientState.Notified:Connect(HudController.toast)
	ClientState.Announced:Connect(HudController.announce)
	ClientState.PopupRequested:Connect(function(kind, data)
		if kind == "DuelInvite" then
			refs.invite.Visible = true
			refs.duelText.Text = ""
			refs.inviteText.Text = data.from .. " challenges you to a crash duel!"
			task.delay(30, function()
				refs.invite.Visible = false
			end)
		elseif kind == "OpenMenu" then
			require(script.Parent.MenuController).open(data.tab)
		else
			HudController.popup(kind, data)
		end
	end)
	ClientState.DuelChanged:Connect(HudController.tick)
	ClientState.RunEvent:Connect(function(userId, kind, data)
		if userId ~= player.UserId then
			return
		end
		if kind == "Ring" then
			HudController.callout("RING!", C.Green)
		elseif kind == "Target" then
			HudController.callout("TARGET HIT!", C.Accent)
		elseif kind == "Marker" then
			HudController.callout(data.distance .. " STUDS!", C.Blue)
		elseif kind == "Impact" and (data.tier == "Heavy" or data.tier == "Massive") then
			HudController.callout(string.upper(data.tier) .. " IMPACT", C.Red)
		end
	end)
	task.spawn(function()
		while gui and gui.Parent do
			HudController.tick()
			task.wait(0.1)
		end
	end)
	HudController.render()
end

return HudController
