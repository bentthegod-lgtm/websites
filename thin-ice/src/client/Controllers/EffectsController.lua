--[[
	EffectsController - atmosphere, dread and feedback (all client-side, all cosmetic):
	  * falling snow around the camera, scaled by graphics quality, Reduced Effects and
	    whiteouts
	  * presence (shared/Presence): frost creeping in at the screen edges and a dark
	    vignette as the Antlered closes in (within ~30 studs); now and then its outline
	    shows through the fog when it's 55-120 studs away
	  * the Antlered's idle: its head tilts slowly, and snaps into a cocked listening pose
	    when it stops to listen (the server moves the body; the client poses the head)
	  * ambient scares (never in a round's first minute; off with Scare effects): the ice
	    groaning under you, a scream-like gust far away, footprints appearing ahead in the
	    snow, a huge shadow passing under the ice
	  * the catch scare (13+, no gore): a black blink, its blind face lunging at you, a cold
	    flash, frost cracks and a jolt. Scare effects off (or Reduced Effects) = a gentle fade.
	  * chip / deliver bursts, the all-cores flash, snowball arcs, breath puffs on everyone
	    in the cold, the sled's departure lights, camera shake near cracking ice
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local Models = require(Shared.Models)
local Presence = require(Shared.Presence)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local AudioController = require(script.Parent.AudioController)

local EffectsController = {}

local L = GameConfig.Lake
local gui, vignette, frost
local snowPart, snow
local shake = 0
local shakeOffset = nil -- the rotation added to the camera this frame (taken off next frame)
local rng = Random.new()
local clock = 0
local headCache = setmetatable({}, { __mode = "k" }) -- monster model -> { parts, offsets }
local highlight
local silhouetteUntil, nextSilhouetteAt = 0, 0
local nextScareAt, lastScareKind = nil, nil
local breathScanAt = -math.huge

function EffectsController.dread(distance)
	return Presence.vignette(distance)
end

local function quality()
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" and level > 0 then
		return math.clamp(level / 10, 0.3, 1)
	end
	return 1
end

local function buildSnow()
	snowPart = Instance.new("Part")
	snowPart.Name = "TI_Snow"
	snowPart.Anchored = true
	snowPart.CanCollide = false
	snowPart.CanQuery = false
	snowPart.CanTouch = false
	snowPart.Transparency = 1
	snowPart.Size = Vector3.new(90, 1, 90)
	snowPart.Parent = workspace
	snow = Instance.new("ParticleEmitter")
	snow.Name = "Snow"
	snow.Color = ColorSequence.new(Color3.fromRGB(240, 246, 255))
	snow.LightEmission = 0.4
	snow.Size = NumberSequence.new(0.18)
	snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	snow.Lifetime = NumberRange.new(5, 7)
	snow.Speed = NumberRange.new(4, 7)
	snow.SpreadAngle = Vector2.new(20, 20)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Rate = 160
	snow.Parent = snowPart
end

-- Snow particles per second: heavier in a whiteout, scaled down by quality / Reduced Effects.
function EffectsController.snowRate(gust, reduced, q)
	local rate = if gust then 650 else 160
	rate *= math.clamp(q or 1, 0.3, 1)
	if reduced then
		rate *= 0.35
	end
	return math.floor(rate)
end

-- A short-lived particle burst at a world position.
local function burst(position, color, count, speed, size)
	local holder = Instance.new("Part")
	holder.Name = "TI_Burst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(position)
	holder.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	task.delay(1.6, function()
		holder:Destroy()
	end)
	return holder
end
EffectsController.burst = burst

local function flash(color, from, time)
	local f = Ui.new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = from, ZIndex = 40, Parent = gui })
	TweenService:Create(f, TweenInfo.new(time), { BackgroundTransparency = 1 }):Play()
	task.delay(time, function()
		f:Destroy()
	end)
	return f
end

--[[
	The catch scare. full = Scare effects on and Reduced Effects off: a black blink, then
	its face lunges at the camera over ~0.6 s with frost cracks across the screen, a cold
	flash, and a hard jolt. Otherwise: a gentle blue fade. Returns the overlay.
]]
function EffectsController.scare(full)
	local overlay = Ui.new("Frame", { Name = "Scare", Size = UDim2.fromScale(1, 1), BackgroundColor3 = if full then Color3.fromRGB(2, 4, 10) else Color3.fromRGB(120, 170, 230), BackgroundTransparency = if full then 0 else 0.4, ZIndex = 50, Parent = gui })
	if full then
		local view = Ui.new("ViewportFrame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(110, 130, 165), LightColor = Color3.fromRGB(220, 235, 255), LightDirection = Vector3.new(0, -0.4, -1), ZIndex = 51, Parent = overlay })
		local monster = Models.monster(CFrame.new(), nil)
		monster.Parent = view
		local camera = Instance.new("Camera")
		camera.FieldOfView = 46
		local face = (Models.MonsterNeck * CFrame.new(0, 1.2, -2.2)).Position
		camera.CFrame = CFrame.lookAt(face + Vector3.new(0, 0.4, -11), face)
		camera.Parent = view
		view.CurrentCamera = camera
		-- frost cracks across the "lens"
		for i = 1, 6 do
			local crack = Ui.new("Frame", { Name = "Crack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.cos(i) * 0.18, 0.5 + math.sin(i * 1.7) * 0.2), Size = UDim2.new(0.35, 0, 0, 3), Rotation = i * 37, BackgroundColor3 = Color3.fromRGB(235, 248, 255), BackgroundTransparency = 0.15, ZIndex = 52, Parent = overlay })
			crack.Visible = false
			task.delay(0.35, function()
				crack.Visible = true
			end)
		end
		-- the lunge: dolly the camera in, then the cold flash takes over
		local start = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - start) / 0.6, 0, 1)
			local eased = t * t
			camera.CFrame = CFrame.lookAt(face + Vector3.new(0, 0.4, -11 + eased * 8.6), face)
			if t >= 1 or not overlay.Parent then
				conn:Disconnect()
			end
		end)
		overlay.BackgroundTransparency = 0
		task.delay(0.08, function()
			if overlay.Parent then
				overlay.BackgroundColor3 = Color3.fromRGB(10, 18, 34)
			end
		end)
		task.delay(0.6, function()
			if overlay.Parent then
				flash(Color3.fromRGB(235, 246, 255), 0, 0.9)
			end
		end)
		shake = math.max(shake, 1.3)
		TweenService:Create(overlay, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.75), { BackgroundTransparency = 1 }):Play()
		task.delay(1.25, function()
			overlay:Destroy()
		end)
	else
		TweenService:Create(overlay, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
		task.delay(1.4, function()
			overlay:Destroy()
		end)
	end
	return overlay
end

function EffectsController.throwArc(from, to)
	local ball = Instance.new("Part")
	ball.Name = "Snowball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.9, 0.9, 0.9)
	ball.Color = Color3.fromRGB(245, 248, 255)
	ball.Material = Enum.Material.Snow
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = CFrame.new(from + Vector3.new(0, 2, 0))
	ball.Parent = workspace
	local start = os.clock()
	local duration = 0.9
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		local p = from:Lerp(to, t) + Vector3.new(0, 2 + math.sin(t * math.pi) * 10, 0)
		ball.CFrame = CFrame.new(p)
		if t >= 1 then
			conn:Disconnect()
			ball:Destroy()
			burst(to + Vector3.new(0, 0.5, 0), Color3.fromRGB(245, 248, 255), 14, 10, 0.4)
		end
	end)
	return ball
end

---------------------------------------------------------------------------------------------
-- The Antlered's head (client-side pose on top of the server-moved body)
---------------------------------------------------------------------------------------------

function EffectsController.poseHead(model, t)
	local head = model:FindFirstChild("Head")
	local root = model.PrimaryPart
	if not head or not root then
		return nil
	end
	local cache = headCache[model]
	if not cache then
		cache = { parts = {}, offsets = {} }
		local neck = root.CFrame * Models.MonsterNeck
		for _, d in ipairs(head:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(cache.parts, d)
				table.insert(cache.offsets, neck:ToObjectSpace(d.CFrame))
			end
		end
		headCache[model] = cache
	end
	local roll, pitch = Presence.headPose(t, model:GetAttribute("TI_State"))
	local neck = root.CFrame * Models.MonsterNeck * CFrame.Angles(pitch, 0, roll)
	for i, p in ipairs(cache.parts) do
		p.CFrame = neck * cache.offsets[i]
	end
	return roll, pitch
end

---------------------------------------------------------------------------------------------
-- Ambient scares
---------------------------------------------------------------------------------------------

local function footprints(root)
	local look = root.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, 1)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local start = root.Position + dir * 30
	local folder = Instance.new("Folder")
	folder.Name = "TI_Footprints"
	folder.Parent = workspace
	for i = 1, 8 do
		task.delay(i * 0.45, function()
			-- prints walking TOWARD you, one by one, out of nowhere
			local p = start - dir * (i * 2.6) + side * (if i % 2 == 0 then 0.9 else -0.9)
			local mark = Instance.new("Part")
			mark.Name = "Print"
			mark.Anchored = true
			mark.CanCollide = false
			mark.CanQuery = false
			mark.CanTouch = false
			mark.Size = Vector3.new(1.1, 0.06, 2.4)
			mark.Color = Color3.fromRGB(40, 60, 90)
			mark.Material = Enum.Material.SmoothPlastic
			mark.Transparency = 0.35
			mark.CFrame = CFrame.lookAt(Vector3.new(p.X, L.IceTop + 0.04, p.Z), Vector3.new(p.X, L.IceTop + 0.04, p.Z) - dir)
			mark.Parent = folder
			TweenService:Create(mark, TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 3), { Transparency = 1 }):Play()
		end)
	end
	task.delay(12, function()
		folder:Destroy()
	end)
	return folder
end

local function underIceShadow(root)
	local shadow = Instance.new("Part")
	shadow.Name = "TI_UnderIce"
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CastShadow = false
	shadow.Size = Vector3.new(7, 0.3, 20)
	shadow.Color = Color3.fromRGB(6, 10, 18)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.45
	local a = rng:NextNumber() * math.pi * 2
	local across = Vector3.new(math.cos(a), 0, math.sin(a))
	local from = root.Position - across * 40
	local to = root.Position + across * 40
	local y = L.IceTop - 1.1
	shadow.CFrame = CFrame.lookAt(Vector3.new(from.X, y, from.Z), Vector3.new(to.X, y, to.Z))
	shadow.Parent = workspace
	TweenService:Create(shadow, TweenInfo.new(3.2, Enum.EasingStyle.Sine), { CFrame = CFrame.lookAt(Vector3.new(to.X, y, to.Z), Vector3.new(to.X, y, to.Z) + across) }):Play()
	task.delay(3.4, function()
		shadow:Destroy()
	end)
	return shadow
end

-- Plays one ambient scare (returns what was made, for tests).
function EffectsController.ambientScare(kind)
	local root = ClientState.root()
	if not root then
		return nil
	end
	local reduced = ClientState.setting("ReducedEffects") == true
	lastScareKind = kind
	if kind == "IceGroan" then
		AudioController.play("IceGroan", root.Position - Vector3.new(0, 3, 0))
		shake = math.max(shake, 0.35)
		return "groan"
	elseif kind == "DistantScream" then
		local a = rng:NextNumber() * math.pi * 2
		AudioController.play("WindHowl", root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 160)
		return "howl"
	elseif kind == "Footprints" then
		return if reduced then nil else footprints(root)
	elseif kind == "UnderIceShadow" then
		AudioController.play("ShadowSwell", root.Position - Vector3.new(0, 4, 0))
		return if reduced then nil else underIceShadow(root)
	end
	return nil
end

local function stepScares(now, root)
	local me = ClientState.me()
	local onIce = root and root.Position.Z > L.ShoreZ + 8 and me.state == "Active"
	if not ClientState.inRound() then
		nextScareAt = nil -- (scheduled afresh from the next round's start)
		return
	end
	if ClientState.setting("ScareEffects") == false or ClientState.setting("ReducedEffects") == true or not onIce then
		return
	end
	local roundStart = ClientState.roundStartedAt
	if not nextScareAt then
		nextScareAt = Presence.nextScareAt(math.max(now, (roundStart or now) + GameConfig.Presence.ScareGraceTime), rng)
	end
	if now >= nextScareAt and Presence.scareAllowed(now, roundStart, nil) then
		EffectsController.ambientScare(Presence.pickScare(rng, lastScareKind))
		nextScareAt = Presence.nextScareAt(now, rng)
	end
end

---------------------------------------------------------------------------------------------
-- Breath puffs and the sled's lights
---------------------------------------------------------------------------------------------

local function breathFor(character)
	local head = character:FindFirstChild("Head")
	if not head or head:FindFirstChild("TI_Breath") then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "TI_Breath"
	a.Position = Vector3.new(0, -0.15, -0.65)
	a.Parent = head
	local e = Instance.new("ParticleEmitter")
	e.Name = "Breath"
	e.Color = ColorSequence.new(Color3.fromRGB(235, 244, 255))
	e.LightEmission = 0.2
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.9) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.2)
	e.Speed = NumberRange.new(0.8, 1.4)
	e.SpreadAngle = Vector2.new(15, 15)
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = 1.2
	e.Parent = a
end

local function stepBreath(now)
	if now - breathScanAt < 1 then
		return
	end
	breathScanAt = now
	local reduced = ClientState.setting("ReducedEffects") == true
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			breathFor(character)
			local head = character:FindFirstChild("Head")
			local att = head and head:FindFirstChild("TI_Breath")
			local e = att and att:FindFirstChild("Breath")
			local root = character:FindFirstChild("HumanoidRootPart")
			if e and root then
				local warm = player:GetAttribute("TI_NearFire") == true
				local onIce = root.Position.Z > L.ShoreZ
				e.Rate = if warm or reduced then 0 elseif onIce then 1.6 else 0.7
			end
		end
	end
end

local function stepSled(now)
	local round = ClientState.round
	local worldFolder = workspace:FindFirstChild("ThinIceWorld")
	local sled = worldFolder and worldFolder:FindFirstChild("Lobby") and worldFolder.Lobby:FindFirstChild("Sled")
	if not sled then
		return
	end
	local leaving = round.phase == "Sled"
	local left = round.timeLeft or 60
	local period = if left <= 10 then 0.25 elseif left <= 25 then 0.5 else 1
	local on = leaving and (math.floor(now / period) % 2 == 0)
	for i = 1, 3 do
		local bulb = sled:FindFirstChild("SledLight" .. i)
		if bulb then
			bulb.Transparency = if on or not leaving then 0 else 0.7
			local glow = bulb:FindFirstChild("SledGlow")
			if glow then
				glow.Brightness = if leaving and on then 3 else 0.6
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------------------------

function EffectsController.step(dt)
	dt = dt or 1 / 60
	clock += dt
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local gust = workspace:GetAttribute("TI_Gust") == true
	local reduced = ClientState.setting("ReducedEffects") == true
	if snowPart and camera then
		snowPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 25, 0))
		snow.Rate = EffectsController.snowRate(gust, reduced, quality())
	end
	local root = ClientState.root()
	local info = ClientState.monsterInfo()
	-- (presence cues only for players out in the round: none at camp in the lobby)
	local inRound = ClientState.inRound()
	local cues = Presence.cues(info and inRound and info.distance, info and info.state, info and info.huntingMe)
	-- Frost at the edges + a dark vignette as it closes in.
	if vignette then
		vignette.BackgroundTransparency = 1 - cues.vignette * 0.5
	end
	if frost then
		frost.BackgroundTransparency = 1 - cues.vignette * 0.7
	end
	-- Its head, and a glimpse of it through the fog now and then.
	if info then
		EffectsController.poseHead(info.model, clock)
		if not highlight or highlight.Parent ~= info.model then
			if highlight then
				highlight:Destroy()
			end
			highlight = Instance.new("Highlight")
			highlight.Name = "TI_Silhouette"
			highlight.FillColor = Color3.fromRGB(10, 16, 28)
			highlight.OutlineColor = Color3.fromRGB(170, 210, 240)
			highlight.FillTransparency = 0.6
			highlight.OutlineTransparency = 0.55
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Enabled = false
			highlight.Parent = info.model
		end
		if cues.silhouette and now >= nextSilhouetteAt and ClientState.setting("ScareEffects") ~= false and not reduced then
			silhouetteUntil = now + 1.3
			nextSilhouetteAt = now + GameConfig.Presence.SilhouetteGap + rng:NextNumber() * 15
		end
		highlight.Enabled = now < silhouetteUntil and cues.silhouette and not reduced
	end
	stepScares(now, root)
	stepBreath(now)
	stepSled(now)
	-- (Camera shake runs in its own render steps: EffectsController.applyShake / undoShake.)
	if shake > 0 then
		shake = math.max(0, shake - dt * 2.5)
	end
	return cues.vignette, cues
end

--[[
	Camera shake as a temporary offset. The default camera scripts read the camera's own
	CFrame to work out where you are looking, so a jolt written straight into it would be
	kept: the view would drift and stay tilted after the scare. Instead the offset is
	added after the camera scripts run and taken off again before they run next frame.
]]
function EffectsController.undoShake()
	local camera = workspace.CurrentCamera
	if shakeOffset and camera then
		camera.CFrame = camera.CFrame * shakeOffset:Inverse()
	end
	shakeOffset = nil
end

function EffectsController.applyShake()
	local camera = workspace.CurrentCamera
	if shake > 0 and camera and ClientState.setting("CameraShake") ~= false then
		local s = shake * 0.4
		shakeOffset = CFrame.Angles(rng:NextNumber(-s, s) * 0.05, rng:NextNumber(-s, s) * 0.05, 0)
		camera.CFrame = camera.CFrame * shakeOffset
	end
end

function EffectsController.init()
	gui = Ui.screen("IceFx", 20)
	gui.IgnoreGuiInset = true
	vignette = Ui.new("Frame", { Name = "Dread", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 4, 14), BackgroundTransparency = 1, Parent = gui })
	Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, 0.85), NumberSequenceKeypoint.new(0.65, 0.85), NumberSequenceKeypoint.new(1, 0) }), Parent = vignette })
	-- Frost creeping in from the top and bottom edges (a second gradient, rotated).
	frost = Ui.new("Frame", { Name = "Frost", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 232, 255), BackgroundTransparency = 1, Parent = gui })
	Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.22, 0.95), NumberSequenceKeypoint.new(0.78, 0.95), NumberSequenceKeypoint.new(1, 0.1) }), Parent = frost })
	buildSnow()
	ClientState.MonsterCue:Connect(function(kind)
		if kind == "Caught" then
			local full = ClientState.setting("ScareEffects") ~= false and ClientState.setting("ReducedEffects") ~= true
			EffectsController.scare(full)
		end
	end)
	ClientState.WorldSound:Connect(function(category, position, extra)
		if typeof(position) ~= "Vector3" then
			return
		end
		if category == "Throw" and typeof(extra) == "Vector3" then
			EffectsController.throwArc(position, extra)
		elseif category == "Crack" or category == "Break" then
			local root = ClientState.root()
			if root and (root.Position - position).Magnitude < 14 then
				shake = math.max(shake, if category == "Break" then 0.9 else 0.4)
			end
			if category == "Break" then
				burst(position + Vector3.new(0, 0.5, 0), Color3.fromRGB(200, 230, 255), 24, 16, 0.6)
			end
		elseif category == "Chip" then
			burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(190, 235, 255), 22, 18, 0.45)
		elseif category == "Deliver" then
			burst(position + Vector3.new(0, 13, 0), Color3.fromRGB(120, 230, 255), 50, 26, 0.8)
		elseif category == "Splash" then
			burst(position, Color3.fromRGB(120, 160, 210), 30, 14, 0.5)
		end
	end)
	ClientState.Announced:Connect(function(text)
		if string.find(text, "ALL CORES", 1, true) then
			flash(Color3.fromRGB(150, 235, 255), 0.55, 1.2)
			shake = math.max(shake, 0.5)
		end
	end)
	RunService.RenderStepped:Connect(EffectsController.step)
	RunService:BindToRenderStep("TI_ShakeUndo", Enum.RenderPriority.First.Value, EffectsController.undoShake)
	RunService:BindToRenderStep("TI_Shake", Enum.RenderPriority.Camera.Value + 1, EffectsController.applyShake)
end

return EffectsController
