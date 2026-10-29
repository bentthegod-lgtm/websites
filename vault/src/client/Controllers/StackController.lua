--[[
	StackController - the carried loot stack on every character, drawn on each client.

	The server publishes what a player carries as attributes (V_Stack = "Cash=12;Gold=3",
	V_Theme); this controller turns that into pieces with StackLayout. Pieces are light,
	massless, non-colliding models welded to the HumanoidRootPart, so they follow the
	character with no per-frame work. When the layout changes, pieces that stay move to
	their new spot with a short tween (the weld's C0), new pieces drop in from above, and
	removed pieces shrink away; a mode change (bundle -> stack -> tower -> crate) is
	therefore visible but never pops.

	Budgets: your own stack draws up to StackPiecesOwn pieces, other players' up to
	StackPiecesOthers, and only within OthersStackRange (and only if Show Others is on).
	A crate stack also shows a small "x123" counter.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local StackLayout = require(Shared.StackLayout)
local LootModels = require(Shared.LootModels)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local StackController = {}

local stacks = {} -- [player] = { folder, pieces = { [i] = { key, root, weld } }, crate, signature, counter }
local rangeClock = 0

local function parseStack(text)
	local counts = {}
	for category, n in string.gmatch(text or "", "(%a+)=(%d+)") do
		counts[category] = tonumber(n)
	end
	return counts
end
StackController.parseStack = parseStack

-- Wraps a built model so one invisible root part carries the whole piece.
local function weldModel(model, hrp, c0)
	local root = Instance.new("Part")
	root.Name = "PieceRoot"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CFrame = CFrame.new()
	root.Parent = model
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CastShadow = false
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = root
			wc.Part1 = p
			wc.Parent = p
		end
	end
	root.CFrame = hrp.CFrame * c0
	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = root
	weld.C0 = c0
	weld.Parent = root
	return root, weld
end

local function clear(entry)
	if entry.folder then
		entry.folder:Destroy()
	end
	entry.folder = nil
	entry.pieces = {}
	entry.crate = nil
	entry.counter = nil
	entry.signature = nil
end

local function pieceCFrame(p)
	return CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, p.yaw, 0)
end

local function rebuild(player, entry)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local text = player:GetAttribute("V_Stack") or ""
	local theme = player:GetAttribute("V_Theme") or "Classic"
	local isMe = player == Players.LocalPlayer
	local visible = isMe or (entry.inRange and ClientState.setting("ShowOthers") ~= false)
	if not hrp or text == "" or not visible then
		clear(entry)
		return
	end
	local budget = if isMe then PerformanceConfig.StackPiecesOwn else PerformanceConfig.StackPiecesOthers
	if ClientState.setting("ReducedEffects") then
		budget = math.max(6, math.floor(budget * 0.5))
	end
	local signature = text .. "|" .. theme .. "|" .. budget .. "|" .. tostring(hrp)
	if signature == entry.signature then
		return
	end
	local themeChanged = entry.theme ~= theme or entry.hrp ~= hrp
	if themeChanged then
		clear(entry)
	end
	entry.signature, entry.theme, entry.hrp = signature, theme, hrp
	if not entry.folder then
		entry.folder = Instance.new("Model")
		entry.folder.Name = "CarriedStack"
		entry.folder.Parent = character
	end
	local layout = StackLayout.layout(parseStack(text), budget)
	local quick = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- Pieces: reuse by index when the category matches, otherwise replace.
	local old = entry.pieces
	entry.pieces = {}
	for i, p in ipairs(layout.pieces) do
		local key = p.category .. "@" .. p.scale
		local c0 = pieceCFrame(p)
		local existing = old[i]
		if existing and existing.key == key then
			TweenService:Create(existing.weld, quick, { C0 = c0 }):Play()
			entry.pieces[i] = existing
			old[i] = nil
		else
			local model = LootModels.piece(p.category, theme, CFrame.new(), true, p.scale)
			model.Parent = entry.folder
			local root, weld = weldModel(model, hrp, c0 * CFrame.new(0, 1.2, 0))
			TweenService:Create(weld, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = c0 }):Play()
			entry.pieces[i] = { key = key, root = root, weld = weld, model = model }
		end
	end
	for _, leftover in pairs(old) do
		local model = leftover.model
		TweenService:Create(leftover.weld, quick, { C0 = leftover.weld.C0 * CFrame.new(0, -0.6, 0) }):Play()
		task.delay(0.18, function()
			model:Destroy()
		end)
	end
	-- Crate for the largest stacks.
	if layout.crate and not entry.crate then
		local crate = LootModels.crate(theme, CFrame.new(), true)
		crate.Parent = entry.folder
		local _, weld = weldModel(crate, hrp, CFrame.new(0, StackLayout.CrateY + 1.5, 0))
		TweenService:Create(weld, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = CFrame.new(0, StackLayout.CrateY, 0) }):Play()
		entry.crate = crate
		local gui = Ui.new("BillboardGui", { Size = UDim2.fromOffset(90, 26), StudsOffset = Vector3.new(0, 2.2, 0), LightInfluence = 0, AlwaysOnTop = false, Adornee = crate:FindFirstChild("PieceRoot"), Parent = crate })
		entry.counter = Ui.label("", { Size = UDim2.fromScale(1, 1), Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = Ui.Colors.Accent, TextStrokeTransparency = 0.3, Parent = gui })
	elseif not layout.crate and entry.crate then
		entry.crate:Destroy()
		entry.crate = nil
		entry.counter = nil
	end
	if entry.counter then
		entry.counter.Text = "x" .. layout.count
	end
end

local function track(player)
	local entry = { pieces = {}, inRange = player == Players.LocalPlayer }
	stacks[player] = entry
	local function refresh()
		rebuild(player, entry)
	end
	entry.connections = {
		player:GetAttributeChangedSignal("V_Stack"):Connect(refresh),
		player:GetAttributeChangedSignal("V_Theme"):Connect(refresh),
		player.CharacterAdded:Connect(function(character)
			clear(entry)
			character:WaitForChild("HumanoidRootPart", 10)
			refresh()
		end),
	}
	refresh()
end

local function untrack(player)
	local entry = stacks[player]
	if entry then
		for _, c in ipairs(entry.connections) do
			c:Disconnect()
		end
		clear(entry)
		stacks[player] = nil
	end
end

-- Distance culling for other players' stacks (a few times a second).
local function updateRange()
	local root = ClientState.root()
	for player, entry in pairs(stacks) do
		if player ~= Players.LocalPlayer then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local inRange = root ~= nil and hrp ~= nil and (hrp.Position - root.Position).Magnitude <= PerformanceConfig.OthersStackRange
			if inRange ~= entry.inRange then
				entry.inRange = inRange
				rebuild(player, entry)
			end
		end
	end
end

function StackController.refreshAll()
	for player, entry in pairs(stacks) do
		entry.signature = nil
		rebuild(player, entry)
	end
end

function StackController.init()
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	-- Only the two settings stacks use (a volume slider drag fires this on every mouse move).
	local lastShow, lastReduced
	ClientState.SettingsChanged:Connect(function()
		local show, reduced = ClientState.setting("ShowOthers"), ClientState.setting("ReducedEffects")
		if show ~= lastShow or reduced ~= lastReduced then
			lastShow, lastReduced = show, reduced
			StackController.refreshAll()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		rangeClock += dt
		if rangeClock >= 0.5 then
			rangeClock = 0
			updateRange()
		end
	end)
end

return StackController
