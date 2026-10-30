--[[
	ObstacleService - the co-op obstacles and the hazards on the ship.

	Bulkhead doors: two levers on the bow side. Two players holding BOTH levers at the same
	time open the door at once. When you're the only one still in the round (solo), holding
	one lever for SoloHold seconds opens it. Doors are shortcuts (ShipGen guarantees another
	route).
	Valve wheels: one per deck, usable once: the next lurch comes ValveDelay seconds later.
	Hazards (positions follow the ship through every lurch):
	  Steam      pipes burst on a telegraphed cycle (amber light + hiss, then a blast):
	             knockback and a little damage to anyone close.
	  Chandelier on BRACE one chandelier shows a warning shadow; on the lurch it drops:
	             damage + knockback underneath, then it lies there as debris.
	  Wires      sparking cables that only matter once flooded: a zap takes oxygen from
	             anyone underwater nearby.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Survival = require(Shared.Survival)

local ObstacleService = {}

local services
local run, ship
local bulkheads, valves, hazards = {}, {}, {}
local pendingDrops = {}
local rng = Random.new()

local OB = GameConfig.Obstacles
local HZ = GameConfig.Hazards
local rgb = Color3.fromRGB

function ObstacleService.init(registry)
	services = registry
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function alive(player)
	local rec = services.SurvivalService.record(player)
	return rec ~= nil and rec.state == "Alive"
end

local function aliveCount()
	local n = 0
	if run then
		for player in pairs(run.players) do
			if player.Parent and alive(player) then
				n += 1
			end
		end
	end
	return n
end

local function near(player, part, range)
	local root = rootOf(player)
	return root ~= nil and part ~= nil and (root.CFrame.Position - part.CFrame.Position).Magnitude <= range
end

local function world(localCF)
	return ship.model:GetPivot() * localCF
end

local function prompt(parent, action, object, hold, range)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.MaxActivationDistance = range or OB.PromptRange
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function teamNotify(text, kind)
	if not run then
		return
	end
	for player in pairs(run.players) do
		if player.Parent then
			services.Remotes.Notify:FireClient(player, text, kind)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Bulkheads
---------------------------------------------------------------------------------------------

function ObstacleService.openBulkhead(b, by)
	if b.open then
		return false
	end
	b.open = true
	b.openedAt = os.clock()
	b.door.CanCollide = false
	for _, lever in ipairs(b.levers) do
		lever.lamp.Color = rgb(80, 230, 120)
		lever.prompt.Enabled = false
		lever.handle.CFrame = world(lever.handleLocal * CFrame.Angles(math.rad(60), 0, 0))
	end
	services.Remotes.WorldSound:FireAllClients("Bulkhead", b.door.CFrame.Position)
	teamNotify(string.format("Bulkhead open%s - a shortcut aft!", if by then " (" .. by .. ")" else ""), "good")
	return true
end

local function holdBegan(b, i, player)
	if b.open or not alive(player) or not near(player, b.levers[i].handle, OB.LeverRange) then
		return
	end
	b.holders[i] = { player = player, since = os.clock() }
	b.levers[i].lamp.Color = rgb(255, 190, 60)
	services.Remotes.WorldSound:FireAllClients("Lever", b.levers[i].handle.CFrame.Position)
end

local function holdEnded(b, i, player)
	local h = b.holders[i]
	if h and h.player == player then
		b.holders[i] = nil
		if not b.open then
			b.levers[i].lamp.Color = rgb(220, 50, 46)
		end
	end
end

local function leverTriggered(b, i, player)
	if b.open or not alive(player) or not near(player, b.levers[i].handle, OB.LeverRange) then
		return false
	end
	if aliveCount() <= 1 then
		return ObstacleService.openBulkhead(b, player.DisplayName)
	end
	services.Remotes.Notify:FireClient(player, "This door needs TWO crew: one on each lever at the same time!", "warn")
	return false
end
ObstacleService.leverTriggered = leverTriggered
ObstacleService.holdBegan = holdBegan
ObstacleService.holdEnded = holdEnded

---------------------------------------------------------------------------------------------
-- Valves
---------------------------------------------------------------------------------------------

function ObstacleService.useValve(v, player)
	if v.used or not alive(player) or not near(player, v.wheel, OB.PromptRange + 2) then
		return false
	end
	v.used = true
	v.prompt.Enabled = false
	v.wheel.Color = rgb(70, 200, 110)
	v.wheel.CFrame = world(v.wheelLocal * CFrame.Angles(math.rad(90), 0, 0))
	services.ShipService.delayNextLurch(GameConfig.Sinking.ValveDelay)
	services.Remotes.WorldSound:FireAllClients("Valve", v.wheel.CFrame.Position)
	teamNotify(string.format("%s closed a valve! Next lurch delayed +%ds", player.DisplayName, GameConfig.Sinking.ValveDelay), "good")
	return true
end

---------------------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------------------

function ObstacleService.startRun(newRun, record)
	run, ship = newRun, record
	bulkheads, valves, hazards, pendingDrops = {}, {}, {}, {}
	for _, src in ipairs(record.bulkheads) do
		local b = { plan = src.plan, door = src.door, doorLocal = src.doorLocal, levers = {}, holders = {}, open = false }
		for i, lever in ipairs(src.levers) do
			local entry = { handle = lever.handle, lamp = lever.lamp, handleLocal = lever.handleLocal }
			entry.prompt = prompt(lever.handle, "Pull lever", "Bulkhead door", OB.SoloHold, OB.LeverRange)
			entry.prompt.PromptButtonHoldBegan:Connect(function(player)
				holdBegan(b, i, player)
			end)
			entry.prompt.PromptButtonHoldEnded:Connect(function(player)
				holdEnded(b, i, player)
			end)
			entry.prompt.Triggered:Connect(function(player)
				leverTriggered(b, i, player)
			end)
			b.levers[i] = entry
		end
		table.insert(bulkheads, b)
	end
	for _, src in ipairs(record.valves) do
		local v = { plan = src.plan, wheel = src.wheel, wheelLocal = src.wheelLocal, used = false }
		v.prompt = prompt(src.wheel, "Close valve", "Delays the next lurch", OB.ValveHold)
		v.prompt.Triggered:Connect(function(player)
			ObstacleService.useValve(v, player)
		end)
		table.insert(valves, v)
	end
	local start = os.clock()
	for _, src in ipairs(record.hazards) do
		local h = { plan = src.plan, kind = src.plan.kind, src = src, start = start, burstId = -1, hit = {} }
		if h.kind == "Chandelier" then
			h.dropped = false
		end
		table.insert(hazards, h)
	end
end

function ObstacleService.bulkheads()
	return bulkheads
end

function ObstacleService.valves()
	return valves
end

function ObstacleService.hazards()
	return hazards
end

-- World position of a hazard's floor point.
local function hazardPoint(h)
	local y = ship.plan.decks[h.plan.deck].y
	return world(CFrame.new(h.plan.x, y, h.plan.z)).Position
end
ObstacleService.hazardPoint = hazardPoint

local function playersNear(point, radius)
	local list = {}
	if not run then
		return list
	end
	for player in pairs(run.players) do
		local root = rootOf(player)
		if root and player.Parent and alive(player) and (root.CFrame.Position - point).Magnitude <= radius then
			table.insert(list, player)
		end
	end
	return list
end

local function pushFrom(point, player, strength)
	local root = rootOf(player)
	local d = root.CFrame.Position - point
	local flat = Vector3.new(d.X, 0, d.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
	return dir * strength + Vector3.new(0, strength * 0.4, 0)
end

---------------------------------------------------------------------------------------------
-- Lurch hooks: chandeliers
---------------------------------------------------------------------------------------------

function ObstacleService.onBrace()
	if not ship then
		return
	end
	local candidates = {}
	for _, h in ipairs(hazards) do
		if h.kind == "Chandelier" and not h.dropped and not h.warned then
			table.insert(candidates, h)
		end
	end
	for _ = 1, math.min(HZ.Chandelier.PerLurch, #candidates) do
		local i = rng:NextInteger(1, #candidates)
		local h = table.remove(candidates, i)
		h.warned = true
		h.src.shadow.Transparency = 0.35
		table.insert(pendingDrops, h)
	end
end

-- Players under a point given in ship-local space. On a lurch the server has already moved
-- the ship but the clients haven't moved their characters yet, so positions are read
-- against the OLD pivot.
local function playersNearLocal(localPoint, radius, pivot)
	local list = {}
	if not run then
		return list
	end
	for player in pairs(run.players) do
		local root = rootOf(player)
		if root and player.Parent and alive(player) then
			local p = pivot:PointToObjectSpace(root.CFrame.Position)
			if (p - localPoint).Magnitude <= radius then
				table.insert(list, player)
			end
		end
	end
	return list
end

function ObstacleService.dropChandelier(h, oldPivot)
	if h.dropped then
		return false
	end
	h.dropped = true
	h.warned = false
	h.src.shadow.Transparency = 1
	local point = hazardPoint(h)
	local model = h.src.model
	if model and model.PrimaryPart then
		local pivot = model:GetPivot()
		local fall = pivot.Position.Y - (point.Y + 0.4)
		model:PivotTo(pivot - Vector3.new(0, fall, 0))
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = d.Name == "Ring"
			end
		end
	end
	local pivot = oldPivot or ship.model:GetPivot()
	local localPoint = Vector3.new(h.plan.x, ship.plan.decks[h.plan.deck].y + 2, h.plan.z)
	for _, player in ipairs(playersNearLocal(localPoint, HZ.Chandelier.Radius + 1, pivot)) do
		local from = pivot:PointToWorldSpace(localPoint)
		services.SurvivalService.damage(player, HZ.Chandelier.Damage, pushFrom(from, player, HZ.Chandelier.Knockback))
	end
	services.Remotes.WorldSound:FireAllClients("ChandelierFall", point)
	return true
end

function ObstacleService.onLurch(_k, oldPivot)
	local drops = pendingDrops
	pendingDrops = {}
	for _, h in ipairs(drops) do
		ObstacleService.dropChandelier(h, oldPivot)
	end
	-- an open bulkhead door rides up into the ceiling; keep it there
	for _, b in ipairs(bulkheads) do
		if b.open then
			b.door.CFrame = world(b.doorLocal * CFrame.new(0, 7.4, 0))
		end
	end
end

---------------------------------------------------------------------------------------------
-- Per-frame
---------------------------------------------------------------------------------------------

local function stepSteam(h, now)
	local cfg = HZ.Steam
	local period = cfg.Period
	local t = (now - h.start + h.plan.phase * period) % period
	local cycle = math.floor((now - h.start + h.plan.phase * period) / period)
	local warnFrom = period - cfg.Warn - cfg.Burst
	local burstFrom = period - cfg.Burst
	local src = h.src
	if t >= warnFrom and t < burstFrom then
		if h.state ~= "Warn" then
			h.state = "Warn"
			src.warn.Color = rgb(255, 120, 30)
			services.Remotes.WorldSound:FireAllClients("SteamHiss", src.nozzle.CFrame.Position)
		end
	elseif t >= burstFrom then
		if h.state ~= "Burst" then
			h.state = "Burst"
			src.emitter.Rate = 70
			services.Remotes.WorldSound:FireAllClients("SteamBurst", src.nozzle.CFrame.Position)
		end
		if h.burstId ~= cycle then
			h.burstId = cycle
			h.hit = {}
		end
		local point = hazardPoint(h)
		for _, player in ipairs(playersNear(point, cfg.Radius)) do
			if not h.hit[player] then
				h.hit[player] = true
				services.SurvivalService.damage(player, cfg.Damage, pushFrom(point, player, cfg.Knockback))
			end
		end
	elseif h.state ~= "Idle" then
		h.state = "Idle"
		src.emitter.Rate = 0
		src.warn.Color = rgb(255, 170, 40)
	end
end

local function stepWires(h, now)
	local cfg = HZ.Wires
	local src = h.src
	local flooded = src.spark.CFrame.Position.Y < GameConfig.World.SeaLevel
	h.flooded = flooded
	if not flooded then
		return
	end
	if not h.nextZap or now >= h.nextZap then
		h.nextZap = now + cfg.Period
		pcall(function()
			src.emitter:Emit(24)
		end)
		services.Remotes.WorldSound:FireAllClients("Spark", src.spark.CFrame.Position)
		for _, player in ipairs(playersNear(src.spark.CFrame.Position, cfg.Radius)) do
			local head = player.Character and player.Character:FindFirstChild("Head")
			local y = if head then head.CFrame.Position.Y else rootOf(player).CFrame.Position.Y + 1.5
			if Survival.headUnderwater(y) then
				services.SurvivalService.zap(player)
			end
		end
	end
end

function ObstacleService.step()
	if not run or not ship then
		return
	end
	local now = os.clock()
	for _, b in ipairs(bulkheads) do
		if not b.open then
			-- both levers held at once by two different players who are still there
			for i = 1, 2 do
				local h = b.holders[i]
				if h and (not h.player.Parent or not alive(h.player) or not near(h.player, b.levers[i].handle, OB.LeverRange + 2)) then
					holdEnded(b, i, h.player)
				end
			end
			local a, c = b.holders[1], b.holders[2]
			if a and c and a.player ~= c.player then
				ObstacleService.openBulkhead(b, a.player.DisplayName .. " & " .. c.player.DisplayName)
			end
		elseif b.openedAt and now - b.openedAt <= 1.2 then
			local f = math.clamp((now - b.openedAt) / 1, 0, 1)
			b.door.CFrame = world(b.doorLocal * CFrame.new(0, 7.4 * f, 0))
		end
	end
	for _, h in ipairs(hazards) do
		if h.kind == "Steam" then
			stepSteam(h, now)
		elseif h.kind == "Wires" then
			stepWires(h, now)
		end
	end
end

function ObstacleService.release(player)
	for _, b in ipairs(bulkheads) do
		for i = 1, 2 do
			holdEnded(b, i, player)
		end
	end
end

function ObstacleService.stopRun()
	run, ship = nil, nil
	bulkheads, valves, hazards, pendingDrops = {}, {}, {}, {}
end

function ObstacleService.onPlayerRemoving(player)
	ObstacleService.release(player)
end

return ObstacleService
