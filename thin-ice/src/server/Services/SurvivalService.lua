--[[
	SurvivalService - everything about a player out on the lake, server-side:

	  * movement mode (Walk / Sneak / Sprint) requested by the client, limited by stamina,
	    applied as the Humanoid's WalkSpeed; a windowed speed check snaps back anyone who
	    moves faster than their mode allows (speed exploits, teleports)
	  * warmth: drains on the ice (faster in water and in gusts), recovers by fires and on
	    the shore; at zero you freeze
	  * footsteps: each step is a noise the Antlered can hear (sneak = almost silent)
	  * falling through: standing on open water puts you in it (cold!) until you haul
	    yourself onto the nearest ice a moment later
	  * frozen: locked in an ice block with a hold-to-thaw prompt for friends; a Thermos
	    Flask thaws you once after a few seconds; frozen too long = lost for the run
	  * snowballs: thrown at a spot on the lake to make a loud lure there (refill at drifts)

	Per-player values the HUD needs travel as attributes (TI_Warmth, TI_Stamina, TI_State,
	TI_Snowballs, TI_Mode, TI_Carrying, TI_InWater, TI_FrozenAt).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local IceMath = require(Shared.IceMath)
local IcePath = require(Shared.IcePath)
local LakeGen = require(Shared.LakeGen)
local Models = require(Shared.Models)
local RateLimit = require(script.Parent.RateLimit)

local SurvivalService = {}

local services
local world
local run
local records = {}
local requested = {} -- player -> the move mode they last asked for (kept across rounds)
local modeLimit = RateLimit.new(8, 12)
local throwLimit = RateLimit.new(3, 4)

local W = GameConfig.Warmth
local S = GameConfig.Stamina
local SB = GameConfig.Snowball
local L = GameConfig.Lake
local CHECK_WINDOW = 0.5

local MODES = { Walk = true, Sneak = true, Sprint = true }

function SurvivalService.init(registry)
	services = registry
end

function SurvivalService.setWorld(newWorld)
	world = newWorld
end

local function flat(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

function SurvivalService.record(player)
	return records[player]
end

function SurvivalService.records()
	return records
end

local function setAttr(player, name, value)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function publish(rec)
	local p = rec.player
	setAttr(p, "TI_Warmth", math.floor(rec.warmth + 0.5))
	setAttr(p, "TI_Stamina", math.floor(rec.stamina + 0.5))
	setAttr(p, "TI_State", rec.state)
	setAttr(p, "TI_Snowballs", rec.snowballs)
	setAttr(p, "TI_Mode", rec.effective)
	setAttr(p, "TI_Carrying", rec.carrying ~= nil)
	setAttr(p, "TI_InWater", rec.inWater)
	setAttr(p, "TI_FrozenAt", rec.frozenServerAt or 0)
end

local function clearAttrs(player)
	for _, name in ipairs({ "TI_Warmth", "TI_Stamina", "TI_State", "TI_Snowballs", "TI_Mode", "TI_Carrying", "TI_InWater", "TI_FrozenAt" }) do
		player:SetAttribute(name, nil)
	end
end

-- Server-side move: keeps the speed check from flagging our own teleports.
function SurvivalService.moveTo(player, cframe)
	local root = rootOf(player)
	if not root then
		return
	end
	local character = player.Character
	if character.PrimaryPart then
		character:PivotTo(cframe)
	else
		root.CFrame = cframe
	end
	local rec = records[player]
	if rec then
		local pos = cframe.Position
		rec.lastPos = pos
		rec.checkPos = pos
		rec.checkAt = os.clock()
		rec.windowMax = 0
		-- The client owns its character: positions it sent before it got this move are still
		-- in flight. Until it shows up at the destination (or the grace runs out) those stale
		-- positions are ignored, so they can't drop you back in the hole or trip the speed check.
		rec.teleportTo = pos
		rec.teleportUntil = os.clock() + GameConfig.Move.TeleportGrace
	end
end

--[[
	Nearest safe spot on the ice to a world position (climbing out, being frozen in the
	water, dropping a core): a plain ice tile's centre - never a hole or a rock, and
	preferably not the middle of a brazier, a core's ice block, a snow drift or someone's
	frozen block, nor a cut-off island you couldn't walk back from.
]]
function SurvivalService.nearestIce(position)
	if not run then
		return nil
	end
	local connected = IcePath.shoreConnected(run.layout.tiles)
	local taken = {}
	for _, rec in pairs(records) do
		if rec.block and rec.block.Parent then
			local p = rec.block:GetPivot().Position
			local c, r = LakeGen.worldToCell(p.X, p.Z)
			if c then
				taken[LakeGen.key(c, r)] = true
			end
		end
	end
	local best, bestD = nil, math.huge
	for _, tile in ipairs(run.layout.order) do
		if LakeGen.walkable(tile) then
			local x, z = LakeGen.cellToWorld(tile.c, tile.r)
			local k = LakeGen.key(tile.c, tile.r)
			local d = math.sqrt((x - position.X) ^ 2 + (z - position.Z) ^ 2)
			if tile.type == "brazier" or tile.core or tile.drift or taken[k] then
				d += L.TileSize * 2
			end
			if not connected[k] then
				d += L.TileSize * 8
			end
			if d < bestD then
				best, bestD = tile, d
			end
		end
	end
	if not best then
		return Vector3.new(position.X, L.IceTop + 3, L.ShoreZ - 4)
	end
	local x, z = LakeGen.cellToWorld(best.c, best.r)
	return Vector3.new(x, L.IceTop + 3, z), best
end

-- Called by RoundService when the round starts.
function SurvivalService.startRun(newRun)
	run = newRun
	records = {}
	for player in pairs(run.players) do
		local root = rootOf(player)
		local pos = if root then root.Position else Vector3.new()
		local rec = {
			player = player,
			state = "Active",
			warmth = W.Max,
			stamina = S.Max,
			exhausted = false,
			sinceSprint = 99,
			mode = requested[player] or "Walk",
			effective = "Walk",
			spawnPending = root == nil, -- no character at the start (respawning): not a reset
			moving = false,
			speed = 0,
			lastPos = pos,
			checkPos = pos,
			checkAt = os.clock(),
			windowMax = 0,
			violations = 0,
			inWater = false,
			waterSince = 0,
			carrying = nil,
			frozenAt = nil,
			flaskUsed = false,
			snowballs = SB.Start,
			lastThrow = -math.huge,
			lastRefill = -math.huge,
			stepTimer = 0,
			cores = 0,
			rescues = 0,
			thrown = 0,
			freezes = 0,
		}
		records[player] = rec
		run.players[player] = rec
		publish(rec)
	end
end

function SurvivalService.stopRun()
	for player, rec in pairs(records) do
		if rec.block then
			rec.block:Destroy()
			rec.block = nil
		end
		local root, humanoid = rootOf(player)
		if root then
			root.Anchored = false
		end
		if humanoid then
			humanoid.WalkSpeed = GameConfig.Move.Walk
		end
		clearAttrs(player)
	end
	records = {}
	run = nil
end

function SurvivalService.setMode(player, mode)
	local rec = records[player]
	if type(mode) ~= "string" or not MODES[mode] then
		return false
	end
	requested[player] = mode
	if rec then
		rec.mode = mode
	end
	return true
end

local function fireNear(position)
	if world then
		for _, fire in ipairs(world.fires) do
			if flat(fire, position) <= W.FireRadius then
				return true
			end
		end
	end
	if run then
		for _, b in ipairs(run.layout.braziers) do
			local x, z = LakeGen.cellToWorld(b.c, b.r)
			if flat(Vector3.new(x, 0, z), position) <= W.FireRadius then
				return true
			end
		end
	end
	return false
end
SurvivalService.fireNear = fireNear

---------------------------------------------------------------------------------------------
-- Freezing and thawing
---------------------------------------------------------------------------------------------

function SurvivalService.freeze(player, cause)
	local rec = records[player]
	if not rec or rec.state ~= "Active" then
		return false
	end
	local root, humanoid = rootOf(player)
	if services.ObjectiveService then
		services.ObjectiveService.drop(player)
	end
	if rec.inWater and root then
		SurvivalService.moveTo(player, CFrame.new((SurvivalService.nearestIce(root.Position))))
		rec.inWater = false
	end
	rec.state = "Frozen"
	rec.frozenAt = os.clock()
	rec.frozenServerAt = workspace:GetServerTimeNow()
	rec.warmth = 0
	rec.freezes += 1
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	if root then
		root.Anchored = true
		local base = CFrame.new(root.Position.X, L.IceTop, root.Position.Z)
		local block = Models.iceBlock(base, run and run.folder or workspace)
		block.Name = "Frozen_" .. player.Name
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ThawPrompt"
		prompt.ActionText = "Thaw"
		prompt.ObjectText = player.DisplayName
		prompt.HoldDuration = W.ThawHold
		prompt.MaxActivationDistance = W.ThawDistance
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = block:FindFirstChild("Block")
		prompt.Triggered:Connect(function(rescuer)
			SurvivalService.tryThaw(rescuer, player)
		end)
		rec.block = block
		rec.prompt = prompt
	end
	publish(rec)
	if cause == "monster" then
		services.Remotes.MonsterCue:FireClient(player, "Caught")
	end
	local text = if cause == "monster" then player.DisplayName .. " was caught by the Antlered!" else player.DisplayName .. " froze solid!"
	for other in pairs(records) do
		if other ~= player then
			services.Remotes.Notify:FireClient(other, text .. " Hold E by their ice block to thaw them.", "warn")
		end
	end
	services.Remotes.Notify:FireClient(player, "You're frozen! A friend can thaw you" .. (if (services.DataService.getProfile(player) or { Boosts = { Flask = 0 } }).Boosts.Flask > 0 and not rec.flaskUsed then " - or your Thermos Flask will in a few seconds." else "."), "error")
	return true
end

function SurvivalService.thaw(player, rescuer)
	local rec = records[player]
	if not rec or rec.state ~= "Frozen" then
		return false
	end
	if rec.block then
		rec.block:Destroy()
		rec.block = nil
		rec.prompt = nil
	end
	local root, humanoid = rootOf(player)
	rec.state = "Active"
	rec.frozenAt = nil
	rec.frozenServerAt = nil
	rec.warmth = W.ThawTo
	rec.exhausted = false
	rec.stamina = math.max(rec.stamina, S.RecoverTo)
	if root then
		root.Anchored = false
		local pos = root.Position
		local rescuerRoot = rescuer and rootOf(rescuer)
		if rescuerRoot then
			-- Stand up right beside the friend who thawed you.
			local side = rescuerRoot.CFrame.RightVector
			side = Vector3.new(side.X, 0, side.Z)
			side = if side.Magnitude > 0.1 then side.Unit else Vector3.new(1, 0, 0)
			pos = rescuerRoot.Position + side * 3
			-- Not into a rock or a hole beside them: then right where they stand.
			local c, r = LakeGen.worldToCell(pos.X, pos.Z)
			if c and run and not LakeGen.walkable(run.layout.tiles[LakeGen.key(c, r)]) then
				pos = rescuerRoot.Position
			end
		end
		SurvivalService.moveTo(player, CFrame.new(pos.X, math.max(pos.Y, L.IceTop + 3), pos.Z))
	end
	if humanoid then
		humanoid.WalkSpeed = IceMath.speed("Walk", false, false)
	end
	publish(rec)
	if services.NoiseService and root then
		services.NoiseService.emit("Thaw", root.Position, player)
	end
	if rescuer then
		local rr = records[rescuer]
		if rr then
			rr.rescues += 1
		end
		services.DataService.bump(rescuer, "Rescues", 1)
		services.Remotes.Notify:FireClient(rescuer, "You thawed " .. player.DisplayName .. "!", "good")
		services.Remotes.Notify:FireClient(player, rescuer.DisplayName .. " thawed you! Stay warm.", "good")
	end
	return true
end

function SurvivalService.tryThaw(rescuer, target)
	local rr, tr = records[rescuer], records[target]
	if not rr or not tr or rescuer == target or rr.state ~= "Active" or rr.inWater or tr.state ~= "Frozen" then
		return false
	end
	local a, b = rootOf(rescuer), rootOf(target)
	if not a or not b or flat(a.Position, b.Position) > W.ThawDistance + 2 then
		return false
	end
	return SurvivalService.thaw(target, rescuer)
end

local function lose(rec)
	local player = rec.player
	if rec.block then
		rec.block:Destroy()
		rec.block = nil
	end
	rec.state = "Lost"
	local root, humanoid = rootOf(player)
	if root then
		root.Anchored = false
	end
	if humanoid then
		humanoid.WalkSpeed = GameConfig.Move.Walk
	end
	if world then
		SurvivalService.moveTo(player, world.spawnCFrame)
	end
	publish(rec)
	services.Remotes.Notify:FireClient(player, "You were lost to the ice. Cheer your team on from the shore!", "error")
end

-- Escaped on the sled: safe, done for this round.
function SurvivalService.escape(player)
	local rec = records[player]
	if not rec or rec.state ~= "Active" then
		return false
	end
	rec.state = "Escaped"
	publish(rec)
	return true
end

-- The player left (or reset) mid-round.
function SurvivalService.release(player)
	local rec = records[player]
	if not rec then
		return
	end
	if rec.block then
		rec.block:Destroy()
		rec.block = nil
	end
	rec.state = "Left"
	if player.Parent then
		clearAttrs(player)
	end
end

---------------------------------------------------------------------------------------------
-- Snowballs
---------------------------------------------------------------------------------------------

function SurvivalService.throw(player, direction)
	local rec = records[player]
	if not rec or rec.state ~= "Active" or rec.inWater or not throwLimit:allow(player) then
		return false, "no"
	end
	if typeof(direction) ~= "Vector3" then
		return false, "bad direction"
	end
	local dir = Vector3.new(direction.X, 0, direction.Z)
	local mag = dir.Magnitude
	if mag ~= mag or mag < 1e-3 or mag == math.huge then
		return false, "bad direction"
	end
	local now = os.clock()
	if rec.snowballs <= 0 then
		services.Remotes.Notify:FireClient(player, "No snowballs - scoop more from a snow drift.", "error")
		return false, "empty"
	end
	if now - rec.lastThrow < SB.Cooldown then
		return false, "cooldown"
	end
	local root = rootOf(player)
	if not root then
		return false, "no character"
	end
	dir = dir / mag
	local from = root.Position
	local land = from + dir * SB.Range
	local b = world and world.lakeBounds
	if b then
		land = Vector3.new(math.clamp(land.X, b.minX + 2, b.maxX - 2), L.IceTop, math.clamp(land.Z, b.minZ + 2, b.maxZ - 2))
	end
	rec.snowballs -= 1
	rec.lastThrow = now
	rec.thrown += 1
	services.Remotes.WorldSound:FireAllClients("Throw", from, land)
	services.NoiseService.emit("Snowball", land, nil)
	services.DataService.bump(player, "Snowballs", 1)
	publish(rec)
	return true, land
end

---------------------------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------------------------

local function stepActive(rec, root, humanoid, dt, now)
	local player = rec.player
	local pos = root.Position
	-- Right after a server move: positions far from the destination are stale (sent before
	-- the client got the move) and must not drop you back into the hole you just left.
	local settling = rec.teleportTo ~= nil and now < rec.teleportUntil
	local stale = settling and flat(pos, rec.teleportTo) > 3
	if not settling then
		rec.teleportTo = nil
	end
	local onShore = pos.Z < L.ShoreZ
	local c, r = LakeGen.worldToCell(pos.X, pos.Z)
	local tile = c and run.layout.tiles[LakeGen.key(c, r)]

	-- Water: falling in, and hauling yourself out.
	local overWater = tile ~= nil and tile.type == "water"
	if overWater and not rec.inWater and not stale then
		rec.inWater = true
		rec.waterSince = now
		services.NoiseService.emit("Splash", pos, player)
		services.Remotes.Notify:FireClient(player, "You fell through! Get out before you freeze!", "error")
		if services.ObjectiveService then
			services.ObjectiveService.drop(player)
		end
	elseif rec.inWater and not stale and (not overWater or now - rec.waterSince >= W.ClimbOutTime) then
		rec.inWater = false
		if overWater then
			SurvivalService.moveTo(player, CFrame.new((SurvivalService.nearestIce(pos))))
			pos = root.Position
		end
	end

	-- Moving? (smoothed flat speed - robust to the odd jittery frame)
	local moved = flat(pos, rec.lastPos)
	local instant = if dt > 0 then moved / dt else 0
	rec.speed = rec.speed * 0.6 + instant * 0.4
	rec.moving = rec.speed > 2
	rec.lastPos = pos

	-- Stamina and the effective mode.
	local effective
	rec.stamina, rec.exhausted, rec.sinceSprint, effective = IceMath.stepStamina(rec.stamina, rec.exhausted, rec.sinceSprint, rec.mode, rec.moving, dt)
	rec.effective = effective
	local allowed = IceMath.speed(effective, rec.carrying ~= nil, rec.inWater)
	if humanoid then
		humanoid.WalkSpeed = allowed
	end

	-- Speed check over a short window (network updates arrive in bursts).
	rec.windowMax = math.max(rec.windowMax, IceMath.speed(rec.mode, false, false))
	if settling then
		-- (no verdicts while settling; the window restarts from wherever they really are)
		rec.checkPos = pos
		rec.checkAt = now
		rec.windowMax = 0
	elseif now - rec.checkAt >= CHECK_WINDOW then
		local window = now - rec.checkAt
		if flat(pos, rec.checkPos) > IceMath.maxStep(rec.windowMax, window) then
			rec.violations += 1
			SurvivalService.moveTo(player, CFrame.new(rec.checkPos.X, math.max(rec.checkPos.Y, L.IceTop + 3), rec.checkPos.Z))
			pos = rec.checkPos
		else
			rec.checkPos = pos
			rec.checkAt = now
			rec.windowMax = 0
		end
	end

	-- Warmth.
	rec.warmth = IceMath.stepWarmth(rec.warmth, {
		onShore = onShore,
		inWater = rec.inWater,
		nearFire = fireNear(pos),
		gust = services.WeatherService and services.WeatherService.gusting(),
		drainScale = run.diff.WarmthDrain,
	}, dt)

	-- Footsteps (on the ice only - the shore is snow, and it never leaves the ice).
	local gait = IceMath.gait(effective, rec.moving)
	if gait and not onShore and not rec.inWater then
		rec.stepTimer += dt
		if rec.stepTimer >= GameConfig.Noise.StepInterval[gait] then
			rec.stepTimer = 0
			services.NoiseService.emit(gait, pos, player)
		end
	else
		rec.stepTimer = 0
	end

	-- Snow drifts refill snowballs.
	if rec.snowballs < SB.Max and now - rec.lastRefill >= SB.DriftRefillCooldown then
		for _, d in ipairs(run.layout.drifts) do
			local x, z = LakeGen.cellToWorld(d.c, d.r)
			if flat(Vector3.new(x, 0, z), pos) <= 6 then
				rec.snowballs = SB.Max
				rec.lastRefill = now
				services.Remotes.Notify:FireClient(player, "Snowballs refilled!", "good")
				break
			end
		end
	end

	if rec.warmth <= 0 then
		SurvivalService.freeze(player, "cold")
	end
end

local function stepFrozen(rec, now)
	local player = rec.player
	local elapsed = now - (rec.frozenAt or now)
	if not rec.flaskUsed and elapsed >= W.FlaskDelay then
		local profile = services.DataService.getProfile(player)
		if profile and profile.Boosts.Flask > 0 then
			profile.Boosts.Flask -= 1
			rec.flaskUsed = true
			services.DataService.markDirty(player)
			SurvivalService.thaw(player, nil)
			services.Remotes.Notify:FireClient(player, "Your Thermos Flask thawed you! (" .. profile.Boosts.Flask .. " left)", "good")
			services.DataService.sendProfile(player)
			return
		end
	end
	if elapsed >= W.FrozenLostAfter then
		lose(rec)
	end
end

function SurvivalService.step(dt)
	if not run then
		return
	end
	local now = os.clock()
	for player, rec in pairs(records) do
		if rec.state == "Active" then
			local root, humanoid = rootOf(player)
			if root then
				stepActive(rec, root, humanoid, dt, now)
			end
		elseif rec.state == "Frozen" then
			stepFrozen(rec, now)
		end
		if rec.state ~= "Left" then
			publish(rec)
		end
	end
end

function SurvivalService.onPlayerRemoving(player)
	requested[player] = nil
	modeLimit:forget(player)
	throwLimit:forget(player)
end

function SurvivalService.start()
	local remotes = services.Remotes
	remotes.SetMoveMode.OnServerEvent:Connect(function(player, mode)
		if modeLimit:allow(player) then
			SurvivalService.setMode(player, mode)
		end
	end)
	remotes.Throw.OnServerEvent:Connect(function(player, direction)
		SurvivalService.throw(player, direction)
	end)
end

return SurvivalService
