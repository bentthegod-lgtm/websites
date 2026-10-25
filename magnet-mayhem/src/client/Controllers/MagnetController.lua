--[[
	MagnetController - everything you SEE the magnets do. Purely visual: the server has
	already decided what was claimed and what was awarded.

	* Flights: when the server claims an object (Attract), every client animates the real
	  world model locally - vibrate + lift during the wind-up, then accelerate along an arc
	  while spinning toward the puller. Collected: the object vanishes into the pile with a
	  spark and a sound. Released: it drops back where it was.
	* Piles: every player's pile is drawn from their MM_Pile attribute (stable slots from
	  PileLayout), with a compressed overflow cluster beyond the visual budget. All pile
	  parts are anchored, non-colliding and moved with one BulkMoveTo per frame.
	* Magnet glow / hum for active magnets, pulse shockwaves, and outlines on nearby scrap
	  (yellow = pullable, red = too heavy) while your magnet is on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local ScrapConfig = require(Shared.Config.ScrapConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local Attraction = require(Shared.Attraction)
local PileLayout = require(Shared.PileLayout)
local ScrapModels = require(Shared.ScrapModels)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local MagnetController = {}

local player = Players.LocalPlayer
local flights = {} -- [id] = flight
local flightCount = 0
local piles = {} -- [Player] = pile
local fxFolder
local rng = Random.new()
local otherAccumulator = 0
local outlines = {}

MagnetController.piles = piles
MagnetController.flights = flights

local function scrapFolder()
	local world = workspace:FindFirstChild("MagnetMayhemWorld")
	return world and world:FindFirstChild("Scrap")
end

local function rootOf(p)
	local character = p and p.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function reduced()
	return ClientState.setting("ReducedEffects") == true
end

local function particleScale()
	local q = ClientState.setting("Particles") or "High"
	return (PerformanceConfig.Particles[q] or 1) * (if reduced() then 0.5 else 1)
end

local function burst(position, color, count)
	local n = math.floor(count * particleScale())
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if n <= 0 or not terrain then
		return
	end
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = terrain
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.22, 0)
	e.LightEmission = 1
	e.Color = ColorSequence.new(color)
	e.Parent = a
	e:Emit(n)
	task.delay(0.8, function()
		a:Destroy()
	end)
end
MagnetController.burst = burst

-- Flights -------------------------------------------------------------------------------

local function startFlight(entry)
	local id, userId, duration, anticipation, pulse = entry[1], entry[2], entry[3], entry[4], entry[5]
	local folder = scrapFolder()
	local model = folder and folder:FindFirstChild(tostring(id))
	local puller = Players:GetPlayerByUserId(userId)
	if not model or not puller or flights[id] then
		return
	end
	local def = ScrapConfig.ById[model:GetAttribute("ScrapId")]
	if not def then
		return
	end
	local parts, offsets = ScrapModels.partsAndOffsets(model)
	local flight = {
		id = id,
		model = model,
		parts = parts,
		offsets = offsets,
		start = model:GetPivot(),
		t0 = os.clock(),
		duration = duration,
		anticipation = anticipation,
		puller = puller,
		def = def,
		pulse = pulse,
		animate = flightCount < PerformanceConfig.MaxVisualFlights,
		seed = rng:NextNumber(0, 100),
	}
	flights[id] = flight
	flightCount += 1
	if ScrapConfig.weightClass(def) == "Heavy" and flight.animate then
		AudioController.play("HeavyGroan", flight.start.Position, true)
		burst(flight.start.Position, Color3.fromRGB(255, 200, 120), 10)
	end
end

local function endFlight(id)
	if flights[id] then
		flights[id] = nil
		flightCount -= 1
	end
end

local function stepFlights()
	local now = os.clock()
	local moveParts, moveCFrames = {}, {}
	for id, f in pairs(flights) do
		if not f.model.Parent then
			endFlight(id)
		elseif f.animate then
			local t = now - f.t0
			local cf
			if t < f.anticipation then
				local amp, lift = Attraction.windup(t, f.anticipation, f.def)
				local n = t * 40 + f.seed
				cf = f.start * CFrame.new(math.noise(n, 1) * amp, lift + math.noise(n, 2) * amp, math.noise(n, 3) * amp)
			else
				local root = rootOf(f.puller)
				local target = if root then root.Position + Vector3.new(0, 3, 0) else f.start.Position
				local flightTime = math.max(0.05, f.duration - f.anticipation)
				local u = math.clamp((t - f.anticipation) / flightTime, 0, 1)
				local startPos = f.start.Position + Vector3.new(0, select(2, Attraction.windup(f.anticipation, f.anticipation, f.def)), 0)
				local distance = (target - startPos).Magnitude
				local along, lift, spin = Attraction.curve(u, distance, f.def)
				local pos = startPos:Lerp(target, along) + Vector3.new(0, lift, 0)
				local rot = f.start - f.start.Position
				cf = CFrame.new(pos) * rot * CFrame.Angles(spin * 0.7, spin, spin * 0.4)
				if u >= 1 then
					-- Arrived: hide locally until the server confirms (Collected) or releases.
					f.model.Parent = nil
					f.hidden = true
				end
			end
			if cf and not f.hidden then
				for i, part in ipairs(f.parts) do
					table.insert(moveParts, part)
					table.insert(moveCFrames, cf * f.offsets[i])
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Piles ---------------------------------------------------------------------------------

local function newPile(owner)
	local folder = Instance.new("Folder")
	folder.Name = "Pile_" .. owner.UserId
	folder.Parent = fxFolder
	local pile = { owner = owner, folder = folder, pieces = {}, ids = "", detached = {} }
	piles[owner] = pile
	return pile
end

local function destroyPiece(piece)
	if piece.model then
		piece.model:Destroy()
	end
end

-- Pieces leaving the pile (a sale) are kept briefly so the sell animation can use them.
local function detach(pile)
	for _, piece in ipairs(pile.pieces) do
		table.insert(pile.detached, piece)
	end
	pile.pieces = {}
	pile.detachedAt = os.clock()
end

local function pieceScale(def, isLocal)
	local s = math.clamp(1.7 / def.Size, 0.22, 0.62)
	return if isLocal then s else s * 0.9
end

local function syncPile(pile)
	local owner = pile.owner
	local isLocal = owner == player
	local raw = owner:GetAttribute("MM_Pile") or ""
	if raw == pile.ids then
		return
	end
	local ids = if raw == "" then {} else string.split(raw, ",")
	-- The visible prefix is stable; anything else means the pile was emptied (sale/prestige).
	if #ids < #pile.pieces or (pile.ids ~= "" and string.sub(raw, 1, #pile.ids) ~= pile.ids) then
		detach(pile)
	end
	pile.ids = raw
	local budget = if isLocal then PerformanceConfig.PileDetailedLocal else PerformanceConfig.PileDetailedOther
	for i = #pile.pieces + 1, math.min(#ids, budget) do
		local def = ScrapConfig.ById[ids[i]]
		if def then
			local scale = pieceScale(def, isLocal)
			local model = ScrapModels.build(def.Id, CFrame.new(0, -500, 0), scale)
			model.Parent = pile.folder
			local parts, offsets = ScrapModels.partsAndOffsets(model)
			table.insert(pile.pieces, { model = model, parts = parts, offsets = offsets, size = def.Size * scale, def = def, born = os.clock() })
		end
	end
end

local function updateCluster(pile, root, compaction)
	local drawnMass = 0
	for _, piece in ipairs(pile.pieces) do
		drawnMass += piece.def.Mass
	end
	local hidden = (pile.owner:GetAttribute("MM_PileMass") or 0) - drawnMass
	local size = PileLayout.clusterSize(hidden)
	if size <= 0 then
		if pile.cluster then
			pile.cluster:Destroy()
			pile.cluster = nil
		end
		return
	end
	if not pile.cluster then
		local cluster = Instance.new("Part")
		cluster.Name = "Cluster"
		cluster.Shape = Enum.PartType.Ball
		cluster.Material = Enum.Material.CorrodedMetal
		cluster.Color = Color3.fromRGB(120, 92, 70)
		cluster.Anchored = true
		cluster.CanCollide = false
		cluster.CanQuery = false
		cluster.CanTouch = false
		cluster.CastShadow = false
		cluster.Parent = pile.folder
		pile.cluster = cluster
	end
	if math.abs(pile.cluster.Size.X - size) > 0.05 then
		pile.cluster.Size = Vector3.new(size, size, size)
	end
	local top = PileLayout.topHeight(#pile.pieces, compaction)
	pile.cluster.CFrame = root.CFrame * CFrame.new(0, top + size * 0.5, 0.6) * CFrame.Angles(0, os.clock() * 0.4, 0)
end

local function placePile(pile, now, moveParts, moveCFrames)
	local root = rootOf(pile.owner)
	local isLocal = pile.owner == player
	local hide = not root
	if root and not isLocal then
		local camRoot = rootOf(player)
		if camRoot and (camRoot.Position - root.Position).Magnitude > PerformanceConfig.PileHideDistance then
			hide = true
		end
	end
	if isLocal and ClientState.setting("CameraMode") == "First" then
		hide = true
	end
	pile.folder.Parent = if hide then nil else fxFolder
	if hide then
		return
	end
	local compaction = pile.owner:GetAttribute("MM_Compaction") or 1
	local base = CFrame.new(root.Position) * CFrame.Angles(0, select(2, root.CFrame:ToOrientation()), 0)
	for i, piece in ipairs(pile.pieces) do
		local x, y, z, yaw = PileLayout.slot(i, now, piece.size, compaction)
		-- New pieces pop in with a little settle bounce.
		local age = now - piece.born
		local settle = if age < 0.25 then (1 - age / 0.25) * 0.8 else 0
		local cf = base * CFrame.new(x, y + settle, z) * CFrame.Angles(0.3 * math.sin(i), yaw, 0.2 * math.cos(i * 1.7))
		for j, part in ipairs(piece.parts) do
			table.insert(moveParts, part)
			table.insert(moveCFrames, cf * piece.offsets[j])
		end
	end
	updateCluster(pile, root, compaction)
end

local function stepPiles(dt)
	local now = os.clock()
	otherAccumulator += dt
	local updateOthers = otherAccumulator >= 1 / PerformanceConfig.PileOtherUpdateHz
	if updateOthers then
		otherAccumulator = 0
	end
	local moveParts, moveCFrames = {}, {}
	for owner, pile in pairs(piles) do
		if not owner.Parent then
			pile.folder:Destroy()
			piles[owner] = nil
		else
			syncPile(pile)
			if owner == player or updateOthers then
				placePile(pile, now, moveParts, moveCFrames)
			end
			if pile.detachedAt and now - pile.detachedAt > 1.2 then
				for _, piece in ipairs(pile.detached) do
					destroyPiece(piece)
				end
				pile.detached = {}
				pile.detachedAt = nil
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Takes the pieces of a pile for the sell animation (current or just-detached ones).
function MagnetController.takePieces(owner)
	local pile = piles[owner]
	if not pile then
		return {}
	end
	local out = {}
	for _, piece in ipairs(pile.detached) do
		table.insert(out, piece)
	end
	pile.detached = {}
	pile.detachedAt = nil
	if #out == 0 then
		out = pile.pieces
		pile.pieces = {}
		pile.ids = owner:GetAttribute("MM_Pile") or ""
	end
	if pile.cluster then
		table.insert(out, { model = pile.cluster, single = true })
		pile.cluster = nil
	end
	return out
end

-- Magnet glow / hum ---------------------------------------------------------------------

local hums = {}
local function stepGlow(now)
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local rig = character and character:FindFirstChild("MagnetRig")
		if rig then
			local active = p:GetAttribute("MM_Active") == true
			local core = rig:FindFirstChild("Core")
			local glowScale = rig:GetAttribute("GlowScale") or 1
			if core then
				local light = core:FindFirstChild("CoreGlow")
				local pulse = 0.5 + 0.5 * math.sin(now * 9)
				if light then
					light.Brightness = if active then (1.2 + pulse * 0.8) * glowScale else 0.25
				end
				core.Transparency = if active then 0.05 else 0.35
			end
			local ring = rig:FindFirstChild("Ring")
			if ring then
				ring.Transparency = if active then 0.35 + 0.2 * math.sin(now * 6) else 0.75
			end
			local wasActive = rig:GetAttribute("WasActive") == true
			if active ~= wasActive then
				rig:SetAttribute("WasActive", active)
				local head = rig:FindFirstChild("MagnetHead")
				if active and head then
					AudioController.play("MagnetSwitch", if p == player then nil else head.Position, true)
					AudioController.play("MagnetCharge", if p == player then nil else head.Position, true)
					hums[p] = AudioController.loop("MagnetHum", head)
					if hums[p] then
						hums[p].RollOffMaxDistance = 40
					end
					burst(head.Position, Color3.fromRGB(255, 200, 90), 8)
				elseif hums[p] then
					hums[p]:Destroy()
					hums[p] = nil
				end
			end
		elseif hums[p] then
			hums[p]:Destroy()
			hums[p] = nil
		end
	end
end

local function shockwave(userId, radius)
	local p = Players:GetPlayerByUserId(userId)
	local root = rootOf(p)
	if not root then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "Pulse"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.ForceField
	ring.Color = Color3.fromRGB(120, 190, 255)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = fxFolder
	local time = if reduced() then 0.25 else 0.45
	TweenService:Create(ring, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 }):Play()
	task.delay(time + 0.05, function()
		ring:Destroy()
	end)
	AudioController.play("PulseWave", if p == player then nil else root.Position, true)
	if p == player then
		require(script.Parent.CameraController).punch(0.6)
	end
end

-- Outlines on nearby scrap while your magnet is on --------------------------------------

local function stepOutlines()
	local root = rootOf(player)
	local active = player:GetAttribute("MM_Active") == true
	local profile = ClientState.profile
	local stats = profile and profile.stats
	local folder = scrapFolder()
	local used = 0
	if active and root and stats and folder then
		local range = stats.AttractionRange * 1.15
		local list = {}
		for _, model in ipairs(folder:GetChildren()) do
			local pivot = model:IsA("Model") and model.PrimaryPart
			if pivot and not flights[tonumber(model.Name)] then
				local d = (pivot.Position - root.Position).Magnitude
				if d <= range then
					table.insert(list, { model = model, d = d })
				end
			end
		end
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
		for i = 1, math.min(#list, 14) do
			local entry = list[i]
			local def = ScrapConfig.ById[entry.model:GetAttribute("ScrapId")]
			used += 1
			local box = outlines[used]
			if not box then
				box = Instance.new("SelectionBox")
				box.Name = "Target"
				box.LineThickness = 0.035
				box.SurfaceTransparency = 1
				box.Parent = fxFolder
				outlines[used] = box
			end
			local pullable = def and Attraction.canPull(def, stats)
			box.Color3 = if pullable then Color3.fromRGB(255, 205, 80) else Color3.fromRGB(240, 70, 60)
			box.Adornee = entry.model.PrimaryPart
			box.Visible = true
		end
	end
	for i = used + 1, #outlines do
		outlines[i].Visible = false
		outlines[i].Adornee = nil
	end
end

-- Init ----------------------------------------------------------------------------------

local function onCollected(batch)
	for _, entry in ipairs(batch) do
		local id, userId, scrapId = entry[1], entry[2], entry[3]
		local f = flights[id]
		endFlight(id)
		local def = ScrapConfig.ById[scrapId]
		local owner = Players:GetPlayerByUserId(userId)
		local root = rootOf(owner)
		if def and root then
			local isLocal = owner == player
			local rank = ScrapConfig.rank(def)
			local color = if rank >= 3 then Color3.fromRGB(table.unpack(ScrapConfig.Rarities[def.Rarity].Color)) else Color3.fromRGB(255, 210, 120)
			burst(root.Position + Vector3.new(0, 3, 0), color, if rank >= 3 then 22 else 6)
			if isLocal or (rootOf(player) and (rootOf(player).Position - root.Position).Magnitude < 60) then
				AudioController.collect(def.Audio, root.Position, isLocal)
			end
			if isLocal and ScrapConfig.weightClass(def) == "Heavy" then
				require(script.Parent.CameraController).punch(if rank >= 5 then 1.4 else 0.8)
			end
		end
		if f and f.model and f.model.Parent == nil then
			f.model:Destroy()
		end
	end
end

local function onReleased(ids)
	for _, id in ipairs(ids) do
		local f = flights[id]
		if f then
			endFlight(id)
			local folder = scrapFolder()
			if f.model and folder then
				f.model.Parent = folder
				f.model:PivotTo(f.start)
			end
		end
	end
end

function MagnetController.init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "MM_ClientFX"
	fxFolder.Parent = workspace
	ClientState.Attracted:Connect(function(batch, pulses)
		for _, entry in ipairs(batch) do
			startFlight(entry)
		end
		for _, pulse in ipairs(pulses) do
			shockwave(pulse[1], pulse[2])
		end
	end)
	ClientState.Collected:Connect(onCollected)
	ClientState.Released:Connect(onReleased)
	local function track(p)
		if not piles[p] then
			newPile(p)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	local outlineTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		stepFlights()
		stepPiles(dt)
		stepGlow(os.clock())
		outlineTimer += dt
		if outlineTimer > 0.2 then
			outlineTimer = 0
			stepOutlines()
		end
	end)
end

-- Exposed for tests / other controllers.
MagnetController.step = function(dt)
	stepFlights()
	stepPiles(dt or 1 / 60)
	stepGlow(os.clock())
	stepOutlines()
end

return MagnetController
