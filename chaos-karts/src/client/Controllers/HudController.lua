--[[
	HudController - every on-screen element of a race (and the lobby / results panels).

	Race HUD: position ("1st" / 8), LAP 1/3, race timer, best lap, minimap (the track
	outline with a dot per kart - yours bigger), speedometer, the drift charge bar (blue /
	orange / purple segments), the item slot placeholder (Stage 3), WRONG WAY, the FINAL LAP
	banner, the 3-2-1-GO lights, lap popups, event warnings, the DNF countdown and the
	spectate bar. Lobby: queue status, READY button, portal hint. Results: placings, times,
	best laps and your coins / XP. Toasts for notifications and announcements.
	tick() refreshes everything (RenderStepped; the harness calls it directly).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local KartPhysics = require(Shared.KartPhysics)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Registry = require(Shared.Events.Registry)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local KartController = require(script.Parent.KartController)
local RemoteKarts = require(script.Parent.RemoteKarts)
local SpectateController = require(script.Parent.SpectateController)

local HudController = {}

HudController.onMenu = nil -- set by MenuController

local C = Ui.Colors
local gui
local el = {}
local mapInfo
local banners = {}
local toasts = {}
local resultsShownFor = nil
local DRIFT = {}
for i, c in ipairs(GameConfig.Effects.DriftColors) do
	DRIFT[i] = Color3.fromRGB(c[1], c[2], c[3])
end

-- Text helpers (unit-testable) ---------------------------------------------------------

function HudController.positionText(place)
	return Format.ordinal(place or 1)
end

function HudController.lapText(lap, laps)
	return string.format("LAP %d/%d", math.clamp(lap or 1, 1, laps), laps)
end

function HudController.lobbyText(state)
	if not state.worldReady then
		return "Building Chaos City..."
	end
	if state.phase == "Racing" or state.phase == "Countdown" then
		return "A race is on - you're queued for the next one"
	end
	if state.phase == "Results" then
		return "Results!"
	end
	local text = string.format("%d/%d queued", state.queued or 0, state.players or 0)
	if state.autoStartIn then
		text ..= string.format(" - starting in %ds", state.autoStartIn)
	end
	return text
end

-- Build ----------------------------------------------------------------------------------

local function label(parent, name, text, props)
	props = props or {}
	props.Name = name
	props.Parent = parent
	return Ui.label(text, props)
end

local function title(parent, name, text, props)
	props = props or {}
	props.Name = name
	props.Parent = parent
	local l = Ui.title(text, props)
	Ui.new("UIStroke", { Thickness = 2.5, Color = C.Black, Transparency = 0.1, Parent = l })
	return l
end

local function buildMinimap(parent)
	local frame = Ui.panel({ Name = "Minimap", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(220, 220), BackgroundTransparency = 0.25, Parent = parent }, 14)
	local data = ClientState.mapData()
	local main = data.main
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, s in ipairs(main.samples) do
		minX, maxX = math.min(minX, s.pos.X), math.max(maxX, s.pos.X)
		minZ, maxZ = math.min(minZ, s.pos.Z), math.max(maxZ, s.pos.Z)
	end
	local span = math.max(maxX - minX, maxZ - minZ)
	mapInfo = { minX = minX, minZ = minZ, span = span, cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2 }
	local outline = Ui.new("Frame", { Name = "Outline", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = frame })
	local step = math.max(1, math.floor(main.n / 160))
	for i = 1, main.n, step do
		local s = main.samples[i]
		local u, v = HudController.mapPoint(s.pos)
		local dot = Ui.new("Frame", { Name = "T", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(u, v), Size = UDim2.fromOffset(5, 5), BackgroundColor3 = if s.pos.Y > 20 then C.Accent elseif s.pos.Y < -5 then C.Sea else C.Cream, BackgroundTransparency = 0.15, Parent = outline })
		Ui.corner(dot, 3)
	end
	local cp = data.checkpoints[1].cframe.Position
	local fu, fv = HudController.mapPoint(cp)
	Ui.new("Frame", { Name = "FinishMark", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(fu, fv), Size = UDim2.fromOffset(12, 4), BackgroundColor3 = C.Pink, Parent = outline })
	el.mapDots = Ui.new("Frame", { Name = "Dots", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = frame })
	return frame
end

-- World (x, z) -> minimap (u, v) in 0..1 (x east = right, z south = down).
function HudController.mapPoint(pos)
	local m = mapInfo
	local u = 0.5 + (pos.X - m.cx) / m.span * 0.9
	local v = 0.5 + (pos.Z - m.cz) / m.span * 0.9
	return u, v
end

local function buildRace()
	local race = Ui.new("Frame", { Name = "Race", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	el.race = race
	-- position + lap + timer (top-left)
	local box = Ui.new("Frame", { Name = "Standing", Position = UDim2.fromOffset(16, 70), Size = UDim2.fromOffset(260, 200), BackgroundTransparency = 1, Parent = race })
	el.place = title(box, "Place", "1st", { Size = UDim2.fromOffset(170, 84), TextSize = 78, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent })
	el.of = title(box, "Of", "/8", { Position = UDim2.fromOffset(150, 30), Size = UDim2.fromOffset(100, 44), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Cream })
	el.lap = title(box, "Lap", "LAP 1/3", { Position = UDim2.fromOffset(2, 86), Size = UDim2.fromOffset(240, 34), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Line })
	el.timer = title(box, "Timer", "0:00.000", { Position = UDim2.fromOffset(2, 122), Size = UDim2.fromOffset(240, 28), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
	el.best = label(box, "Best", "BEST --:--.---", { Position = UDim2.fromOffset(2, 152), Size = UDim2.fromOffset(240, 22), TextSize = 17, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim })
	-- item slot placeholder (Stage 3)
	local item = Ui.panel({ Name = "ItemSlot", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(86, 86), BackgroundTransparency = 0.2, Parent = race }, 16)
	label(item, "Label", "ITEM\nStage 3", { Size = UDim2.fromScale(1, 1), TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = C.Dim })
	el.item = item
	-- minimap
	el.minimap = buildMinimap(race)
	-- speedometer (bottom-right)
	local speedo = Ui.panel({ Name = "Speedo", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(190, 92), BackgroundTransparency = 0.25, Parent = race }, 16)
	el.speed = title(speedo, "Value", "0", { Position = UDim2.fromOffset(10, 2), Size = UDim2.fromOffset(120, 60), TextSize = 54, TextXAlignment = Enum.TextXAlignment.Right })
	label(speedo, "Unit", "km/h", { Position = UDim2.fromOffset(134, 26), Size = UDim2.fromOffset(52, 30), TextSize = 16, Font = Ui.Fonts.Bold, TextColor3 = C.Dim })
	local bar, fill = Ui.bar(speedo, { Position = UDim2.fromOffset(12, 66), Size = UDim2.new(1, -24, 0, 12) }, C.Line)
	bar.Name = "SpeedBar"
	el.speedFill = fill
	-- drift charge (bottom-centre)
	local drift = Ui.new("Frame", { Name = "Drift", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(300, 26), BackgroundTransparency = 1, Visible = false, Parent = race })
	el.drift = drift
	el.driftSegs = {}
	for i = 1, 3 do
		local seg, segFill = Ui.bar(drift, { Position = UDim2.new((i - 1) / 3, 3, 0, 0), Size = UDim2.new(1 / 3, -6, 1, 0) }, DRIFT[i])
		seg.Name = "Seg" .. i
		el.driftSegs[i] = segFill
	end
	el.driftLabel = title(drift, "Label", "DRIFT", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(300, 26), TextSize = 22 })
	-- centre messages
	el.wrong = title(race, "WrongWay", "WRONG WAY!", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(600, 80), TextSize = 64, TextColor3 = C.Red, Visible = false })
	el.final = title(race, "FinalLap", "FINAL LAP!", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(700, 90), TextSize = 76, TextColor3 = C.Pink, Visible = false })
	el.popup = title(race, "Popup", "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(700, 60), TextSize = 40, TextColor3 = C.Accent, Visible = false })
	el.countdown = title(race, "Countdown", "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(500, 160), TextSize = 150, TextColor3 = C.Accent, Visible = false })
	local lights = Ui.new("Frame", { Name = "Lights", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.fromOffset(300, 60), BackgroundTransparency = 1, Visible = false, Parent = race })
	el.lights = lights
	el.lightDots = {}
	for i = 1, 5 do
		local d = Ui.new("Frame", { Name = "Light" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((i - 0.5) / 5, 0, 0.5, 0), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Color3.fromRGB(60, 20, 20), Parent = lights })
		Ui.corner(d, 23)
		Ui.stroke(d, C.Black, 3, 0)
		el.lightDots[i] = d
	end
	el.event = title(race, "EventBanner", "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(700, 40), TextSize = 30, TextColor3 = C.Accent, Visible = false })
	el.dnf = title(race, "DnfTimer", "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(500, 30), TextSize = 24, TextColor3 = C.Warm, Visible = false })
	el.finish = title(race, "Finish", "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(800, 100), TextSize = 80, TextColor3 = C.Accent, Visible = false })
	-- spectate bar
	local spec = Ui.panel({ Name = "Spectate", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(440, 64), Visible = false, Parent = race }, 14)
	el.spectate = spec
	el.specName = title(spec, "Who", "SPECTATING", { Position = UDim2.fromOffset(60, 0), Size = UDim2.new(1, -120, 1, 0), TextSize = 22 })
	local prev = Ui.button("<", { Name = "Prev", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(48, 48), TextSize = 26 }, C.PanelLighter)
	prev.Parent = spec
	prev.Activated:Connect(function()
		SpectateController.cycle(-1)
	end)
	local nxt = Ui.button(">", { Name = "Next", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(48, 48), TextSize = 26 }, C.PanelLighter)
	nxt.Parent = spec
	nxt.Activated:Connect(function()
		SpectateController.cycle(1)
	end)
end

local function buildLobby()
	local lobby = Ui.panel({ Name = "Lobby", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(520, 136), BackgroundTransparency = 0.1, Parent = gui }, 18)
	el.lobby = lobby
	title(lobby, "Title", "CHAOS KARTS", { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -170, 0, 40), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent })
	el.lobbyStatus = label(lobby, "Status", "", { Position = UDim2.fromOffset(18, 50), Size = UDim2.new(1, -180, 0, 26), TextSize = 18, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left })
	label(lobby, "Hint", "Walk into the RACE PORTAL or press READY. Up to 12 racers - bots fill the grid.", { Position = UDim2.fromOffset(18, 80), Size = UDim2.new(1, -180, 0, 44), TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Dim })
	local ready = Ui.button("READY", { Name = "Ready", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(140, 70), TextSize = 26 }, C.Green)
	ready.Parent = lobby
	ready.Activated:Connect(function()
		Net.event("SetReady"):FireServer(not ClientState.queued())
	end)
	el.ready = ready
end

local function buildResults()
	local panel = Ui.panel({ Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 560), Visible = false, Parent = gui }, 18)
	el.results = panel
	el.resultsTitle = title(panel, "Title", "RESULTS", { Size = UDim2.new(1, 0, 0, 56), TextSize = 40, TextColor3 = C.Accent })
	local body = Ui.new("Frame", { Name = "Body", Position = UDim2.fromOffset(18, 60), Size = UDim2.new(1, -36, 1, -150), BackgroundTransparency = 1, Parent = panel })
	Ui.list(body, 3)
	el.resultsBody = body
	el.resultsYou = title(panel, "You", "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -44), Size = UDim2.new(1, -30, 0, 36), TextSize = 22, TextColor3 = C.Green })
	el.resultsTimer = label(panel, "Timer", "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, 0, 0, 24), TextSize = 15, TextColor3 = C.Dim })
end

local function buildToasts()
	local holder = Ui.new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(620, 200), BackgroundTransparency = 1, Parent = gui })
	Ui.list(holder, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	el.toasts = holder
	local menu = Ui.button("MENU", { Name = "Menu", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(96, 44), TextSize = 18 }, C.Pink)
	menu.Parent = gui
	menu.Activated:Connect(function()
		if HudController.onMenu then
			HudController.onMenu()
		end
	end)
	el.menu = menu
end

function HudController.toast(text, kind)
	local color = if kind == "good" then C.Green elseif kind == "error" or kind == "warn" then C.Red elseif kind == "gold" then C.Accent else C.Line
	local t = Ui.panel({ Name = "Toast", Size = UDim2.fromOffset(600, 40), BackgroundTransparency = 0.1, LayoutOrder = #toasts + 1, Parent = el.toasts }, 10)
	label(t, "Text", tostring(text), { Size = UDim2.fromScale(1, 1), TextSize = 17, Font = Ui.Fonts.Bold, TextColor3 = color, TextWrapped = true })
	table.insert(toasts, { frame = t, until_ = os.clock() + 4 })
	while #toasts > 4 do
		table.remove(toasts, 1).frame:Destroy()
	end
	return t
end

local function banner(name, seconds)
	banners[name] = os.clock() + seconds
end

-- Results ----------------------------------------------------------------------------------

function HudController.showResults(summary)
	if not summary or not el.results then
		return
	end
	resultsShownFor = summary
	Ui.clear(el.resultsBody)
	local mine = "p" .. tostring(Players.LocalPlayer.UserId)
	for i, row in ipairs(summary.rows or {}) do
		local f = Ui.new("Frame", { Name = "Line", LayoutOrder = i, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = if row.id == mine then C.PanelLighter else C.PanelLight, Parent = el.resultsBody })
		Ui.corner(f, 8)
		label(f, "Place", Format.ordinal(row.place), { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(56, 30), TextSize = 18, Font = Ui.Fonts.Title, TextColor3 = if row.place == 1 then C.Accent elseif row.place <= 3 then C.Line else C.Text, TextXAlignment = Enum.TextXAlignment.Left })
		label(f, "Who", row.name .. (if row.kind == "bot" then "  (bot)" else ""), { Position = UDim2.fromOffset(66, 0), Size = UDim2.new(1, -330, 1, 0), TextSize = 16, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left })
		label(f, "Time", if row.dnf then "DNF" else Format.raceTime(row.time), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 0), Size = UDim2.fromOffset(120, 30), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right })
		label(f, "Best", "best " .. Format.raceTime(row.best), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(130, 30), TextSize = 14, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Right })
	end
	local you = summary.you
	if you then
		el.resultsTitle.Text = if you.dnf then "DID NOT FINISH" elseif you.place == 1 then "YOU WIN!" else Format.ordinal(you.place) .. " PLACE!"
		local level = if you.levelAfter and you.levelBefore and you.levelAfter > you.levelBefore then string.format("   LEVEL UP! %d", you.levelAfter) else ""
		el.resultsYou.Text = string.format("+%d coins   +%d XP%s%s", you.coins or 0, you.xp or 0, if you.newBest then "   NEW BEST LAP!" else "", level)
	else
		el.resultsTitle.Text = "RESULTS"
		el.resultsYou.Text = ""
	end
	el.results.Visible = true
end

function HudController.resultsShown()
	return el.results and el.results.Visible
end

-- Tick -------------------------------------------------------------------------------------

local function updateMapDots()
	local list = {}
	local mine = KartController.state()
	for _, p in ipairs(RemoteKarts.positions()) do
		table.insert(list, { id = p.id, pos = p.pos })
	end
	if mine then
		table.insert(list, { id = "me", pos = mine.pos, me = true })
	end
	local seen = {}
	for _, k in ipairs(list) do
		seen[k.id] = true
		local dot = el.mapDots:FindFirstChild(k.id)
		if not dot then
			local info = ClientState.racerById(k.id)
			local c = info and info.color
			dot = Ui.new("Frame", { Name = k.id, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(if k.me then 14 else 9, if k.me then 14 else 9), BackgroundColor3 = if k.me then C.Accent elseif c then Color3.fromRGB(c[1], c[2], c[3]) else C.Text, ZIndex = if k.me then 3 else 2, Parent = el.mapDots })
			Ui.corner(dot, 7)
			if k.me then
				Ui.stroke(dot, C.Black, 2, 0)
			end
		end
		local u, v = HudController.mapPoint(k.pos)
		dot.Position = UDim2.fromScale(u, v)
	end
	for _, d in ipairs(el.mapDots:GetChildren()) do
		if not seen[d.Name] then
			d:Destroy()
		end
	end
	return #list
end

function HudController.tick()
	local race = ClientState.race
	local phase = race.phase
	local now = ClientState.serverNow()
	local player = Players.LocalPlayer
	local inRace = ClientState.inRace()
	local spectating = ClientState.spectating()
	el.lobby.Visible = phase == "Lobby" or (not inRace and not spectating and phase ~= "Results")
	el.lobbyStatus.Text = HudController.lobbyText(race)
	local queued = ClientState.queued()
	el.ready.Text = if queued then "UNREADY" else "READY"
	Ui.setButtonColor(el.ready, if queued then C.PanelLighter else C.Green)
	el.race.Visible = inRace or spectating
	if not el.race.Visible then
		if phase ~= "Results" then
			el.results.Visible = false
		end
		return
	end
	local laps = race.laps or GameConfig.Race.Laps
	local field = 0
	for _, r in ipairs(race.racers or {}) do
		if not r.left then
			field += 1
		end
	end
	local place = player:GetAttribute("CK_Place") or (ClientState.myRacer() and ClientState.myRacer().place) or 1
	el.place.Text = HudController.positionText(place)
	el.of.Text = "/" .. field
	el.lap.Text = HudController.lapText(player:GetAttribute("CK_Lap") or 1, laps)
	local elapsed = if race.goAt then math.max(0, now - race.goAt) else 0
	el.timer.Text = Format.raceTime(elapsed)
	el.best.Text = "BEST " .. Format.raceTime(HudController.bestLap)
	local s = KartController.state()
	local speed = if s then KartPhysics.speed(s) else 0
	el.speed.Text = tostring(math.floor(speed + 0.5))
	el.speedFill.Size = UDim2.fromScale(math.clamp(speed / (KartStats.TopSpeed * KartStats.BoostTopMul), 0, 1), 1)
	el.speedFill.BackgroundColor3 = if s and s.boostT > 0 then C.Orange else C.Line
	-- drift charge
	local drifting = s ~= nil and s.drift ~= 0
	el.drift.Visible = drifting
	if drifting then
		local levels = KartStats.DriftChargeLevels
		for i = 1, 3 do
			local lo = if i == 1 then 0 else levels[i - 1]
			local f = math.clamp((s.driftT - lo) / (levels[i] - lo), 0, 1)
			el.driftSegs[i].Size = UDim2.fromScale(f, 1)
		end
		el.driftLabel.Text = if s.driftLevel >= 3 then "ULTRA TURBO!" elseif s.driftLevel == 2 then "SUPER TURBO" elseif s.driftLevel == 1 then "TURBO" else "DRIFT"
		el.driftLabel.TextColor3 = if s.driftLevel >= 1 then DRIFT[s.driftLevel] else C.Text
	end
	el.wrong.Visible = player:GetAttribute("CK_WrongWay") == true
	el.wrong.TextTransparency = if math.floor(os.clock() * 3) % 2 == 0 then 0 else 0.4
	el.final.Visible = (banners.final or 0) > os.clock()
	el.popup.Visible = (banners.popup or 0) > os.clock()
	el.finish.Visible = player:GetAttribute("CK_Finished") == true
	-- countdown + lights (from the server's goAt)
	local toGo = if race.goAt then race.goAt - now else -1
	local countdownTime = GameConfig.Race.CountdownTime
	el.lights.Visible = phase == "Countdown" or (toGo > -1 and toGo < countdownTime + 0.5)
	el.countdown.Visible = toGo <= countdownTime and toGo > -1
	if toGo > 0 and toGo <= countdownTime then
		el.countdown.Text = tostring(math.ceil(toGo))
		el.countdown.TextColor3 = C.Accent
	elseif toGo <= 0 and toGo > -1 then
		el.countdown.Text = "GO!"
		el.countdown.TextColor3 = C.Green
	end
	local lit = HudController.litLights(toGo)
	for i, d in ipairs(el.lightDots) do
		d.BackgroundColor3 = if toGo <= 0 then C.Green elseif i <= lit then C.Red else Color3.fromRGB(60, 20, 20)
	end
	-- event warning
	el.event.Visible = (banners.event or 0) > os.clock()
	-- DNF countdown
	el.dnf.Visible = race.dnfAt ~= nil and now < race.dnfAt
	if el.dnf.Visible then
		el.dnf.Text = string.format("Race ends in %ds", math.ceil(race.dnfAt - now))
	end
	-- spectating
	el.spectate.Visible = spectating
	el.item.Visible = inRace
	if spectating then
		local target = SpectateController.target()
		el.specName.Text = if target then string.format("SPECTATING  %s  (%s)", target.name, Format.ordinal(target.place or 1)) else "SPECTATING"
	end
	HudController.dotCount = updateMapDots()
	for i = #toasts, 1, -1 do
		if os.clock() > toasts[i].until_ then
			table.remove(toasts, i).frame:Destroy()
		end
	end
end

-- How many of the 5 start lights are lit `toGo` seconds before GO (all out at GO).
function HudController.litLights(toGo)
	local countdownTime = GameConfig.Race.CountdownTime
	if toGo <= 0 or toGo > countdownTime then
		return 0
	end
	return math.clamp(math.floor((countdownTime - toGo) / countdownTime * 5) + 1, 1, 5)
end

-- The gantry's 5 start lights follow the same countdown.
function HudController.worldLights()
	local root = workspace:FindFirstChild("ChaosKartsWorld")
	local deco = root and root:FindFirstChild("Track") and root.Track:FindFirstChild("Deco")
	if not deco then
		return 0
	end
	local race = ClientState.race
	local toGo = if race.goAt then race.goAt - ClientState.serverNow() else -1
	local lit = HudController.litLights(toGo)
	for i = 1, 5 do
		local light = deco:FindFirstChild("StartLight" .. i)
		if light then
			local on = (toGo <= 0 and toGo > -3) or i <= lit
			light.Color = if toGo <= 0 and toGo > -3 then Color3.fromRGB(80, 255, 120) elseif on then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(60, 20, 20)
			local pl = light:FindFirstChildOfClass("PointLight")
			if pl then
				pl.Brightness = if on then 3 else 0
				pl.Color = light.Color
			end
		end
	end
	return lit
end

function HudController.init()
	gui = Ui.screen("KartHUD", 3)
	buildRace()
	buildLobby()
	buildResults()
	buildToasts()
	ClientState.Notified:Connect(HudController.toast)
	ClientState.Announced:Connect(function(text)
		HudController.toast(text, "gold")
	end)
	ClientState.ResultsReceived:Connect(HudController.showResults)
	ClientState.RaceChanged:Connect(function(state, before)
		if state.phase == "Countdown" and before ~= "Countdown" then
			HudController.bestLap = nil
			el.results.Visible = false
			resultsShownFor = nil
		end
		if state.phase == "Results" and state.results and not resultsShownFor then
			HudController.showResults(state.results)
		end
		if state.phase == "Lobby" then
			el.results.Visible = false
			resultsShownFor = nil
		end
	end)
	ClientState.RaceEvent:Connect(function(kind, info)
		info = info or {}
		if kind == "lap" then
			HudController.bestLap = info.best
			el.popup.Text = string.format("LAP %d/%d   %s", info.lap or 1, GameConfig.Race.Laps, Format.raceTime(info.lapTime))
			banner("popup", 2.5)
			if info.final then
				banner("final", 3.5)
				el.final.Size = UDim2.fromOffset(900, 110)
				TweenService:Create(el.final, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(700, 90) }):Play()
			end
		elseif kind == "finish" then
			HudController.bestLap = info.best
			el.finish.Text = string.format("FINISHED %s!", Format.ordinal(info.place or 1))
		elseif kind == "skip" then
			el.popup.Text = "MISSED A CHECKPOINT - turn back!"
			banner("popup", 2.5)
		end
	end)
	ClientState.EventStarted:Connect(function(payload)
		local def = Registry.def(payload.id)
		local zone = ClientState.mapData().zoneById[payload.zone]
		if def then
			el.event.Text = string.format("!! %s - %s !!", string.upper(def.name), zone and string.upper(zone.name) or "")
			banner("event", math.max(2, (payload.serverStartTime or 0) - ClientState.serverNow() + 1.5))
		end
	end)
end

return HudController
