--[[
	MovementController - everything that moves YOUR character on the client (the server
	owns the rules; your client owns your character's physics):

	* LURCH: the server sends the ship's old and new pivot. If you are aboard and up, your
	  character is moved by the same delta (upright, turned with the ship's yaw), so you stay
	  where you were on the deck. Then the camera shakes.
	* Slide: above SlideTilt degrees a gentle force pulls you downhill toward the bow
	  (VectorForce on your root), times your Grip upgrade.
	* Speed: walking speed follows the loot you carry (heavy items slow you); Swim Speed and
	  Climb Speed upgrades multiply it while swimming / climbing a ladder.
	* Knockback from hazards, and the Grapple Hook pull once the server says GrappleOk.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local LurchMath = require(Shared.LurchMath)
local LootMath = require(Shared.LootMath)

local ClientState = require(script.Parent.ClientState)

local MovementController = {}

MovementController.shake = nil -- set by EffectsController: fn(strength, seconds)
local force, attachment
local grapple = nil

local function shipInfo()
	local ship = ClientState.ship()
	if not ship or not ship.PrimaryPart then
		return nil
	end
	return ship, ship:GetPivot(), ship:GetAttribute("Length") or 200, ship:GetAttribute("Beam") or 50, ship:GetAttribute("Height") or 80
end

-- Lurches already applied (the server's sequence number) and ones waiting for the
-- replicated ship to arrive at their new pivot.
local lastSeq = nil
local pending = {}
local PENDING_MAX = 0.5

local function samePivot(a, b)
	return (a.Position - b.Position).Magnitude < 0.05 and a.LookVector:Dot(b.LookVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end

-- Moves my character by the lurch delta. Everything comes from the remote (both pivots and
-- the ship's box), never from the replicated model, so the delta is exact whichever arrived
-- first. Only an Alive, unanchored character moves: downed bodies (anchored) are carried by
-- the server, the escaped are anchored in the boat, everyone else isn't playing.
local function applyLurch(oldPivot, newPivot, info)
	local root = ClientState.root()
	local me = ClientState.me()
	if not root or me.state ~= "Alive" or root.Anchored then
		return nil
	end
	local length, beam, height = info and info.length, info and info.beam, info and info.height
	if type(length) ~= "number" or type(beam) ~= "number" or type(height) ~= "number" then
		local ship, _, l, b, h = shipInfo()
		if not ship then
			return nil
		end
		length, beam, height = l, b, h
	end
	if not LurchMath.onShip(oldPivot, root.CFrame.Position, length, beam, height) then
		return nil
	end
	local moved = LurchMath.relocate(oldPivot, newPivot, root.CFrame, 0.15)
	local character = root.Parent
	if character and character.PrimaryPart == root then
		character:PivotTo(moved)
	else
		root.CFrame = moved
	end
	root.AssemblyLinearVelocity = Vector3.zero
	return moved
end

local function flushPending(force)
	while pending[1] do
		local p = pending[1]
		local ship = ClientState.ship()
		local pivot = ship and ship.PrimaryPart and ship:GetPivot()
		if not force and pivot and samePivot(pivot, p.old) and os.clock() < p.untilAt then
			return -- the ship hasn't moved here yet: keep standing on it where it is
		end
		table.remove(pending, 1)
		applyLurch(p.old, p.new, p.info)
	end
end

-- Moves my character with the ship. Returns the new root CFrame (or nil if not moved now).
function MovementController.onLurch(oldPivot, newPivot, info)
	if typeof(oldPivot) ~= "CFrame" or typeof(newPivot) ~= "CFrame" then
		return nil
	end
	local seq = type(info) == "table" and info.seq or nil
	if type(seq) == "number" then
		if lastSeq and seq <= lastSeq then
			return nil -- already applied: never move twice for one lurch
		end
		lastSeq = seq
	end
	if MovementController.shake then
		local k = (type(info) == "table" and info.tilt or 5) / 25
		MovementController.shake(GameConfig.Sinking.ShakeStrength * (0.6 + k), 0.9)
	end
	flushPending(true) -- an older lurch still waiting goes first
	-- If the remote beat the ship's replicated CFrame, wait (briefly) for the ship to move so
	-- the character isn't put over a deck that is still drawn at the old pivot.
	local ship = ClientState.ship()
	local pivot = ship and ship.PrimaryPart and ship:GetPivot()
	if pivot and not samePivot(pivot, newPivot) and samePivot(pivot, oldPivot) then
		table.insert(pending, { old = oldPivot, new = newPivot, info = info, untilAt = os.clock() + PENDING_MAX })
		return nil
	end
	return applyLurch(oldPivot, newPivot, info)
end

local function ensureForce(root)
	if force and force.Parent and attachment and attachment.Parent == root then
		return force
	end
	attachment = Instance.new("Attachment")
	attachment.Name = "LL_Slide"
	attachment.Parent = root
	force = Instance.new("VectorForce")
	force.Name = "LL_SlideForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = root
	return force
end

-- The slide acceleration I should feel right now (world vector).
function MovementController.slideNow()
	local root = ClientState.root()
	local humanoid = ClientState.humanoid()
	local me = ClientState.me()
	if not root or not humanoid or me.state ~= "Alive" or not ClientState.inRound() then
		return Vector3.zero
	end
	local okFloor, floor = pcall(function()
		return humanoid.FloorMaterial
	end)
	if okFloor and floor == Enum.Material.Air then
		return Vector3.zero
	end
	local ship, pivot, length, beam, height = shipInfo()
	if not ship or not LurchMath.onShip(pivot, root.CFrame.Position, length, beam, height) then
		return Vector3.zero
	end
	local tilt = workspace:GetAttribute("LL_Tilt") or 0
	return LurchMath.slide(pivot, tilt, ship:GetAttribute("MaxTilt") or 25, me.grip)
end

-- WalkSpeed I should have right now (loot weight, swim / climb upgrades, downed).
function MovementController.speedNow()
	local humanoid = ClientState.humanoid()
	local me = ClientState.me()
	if me.state == "Downed" then
		return 0
	end
	local base = LootMath.walkSpeed(me.carried)
	if humanoid then
		local ok, state = pcall(function()
			return humanoid:GetState()
		end)
		if ok and state == Enum.HumanoidStateType.Swimming then
			return base * me.swim
		elseif ok and state == Enum.HumanoidStateType.Climbing then
			return base * me.climb
		end
	end
	return base
end

function MovementController.step(dt)
	if pending[1] then
		flushPending(false)
	end
	local root = ClientState.root()
	local humanoid = ClientState.humanoid()
	if not root or not humanoid then
		return
	end
	local speed = MovementController.speedNow()
	if math.abs(humanoid.WalkSpeed - speed) > 0.05 then
		humanoid.WalkSpeed = speed
	end
	local slide = MovementController.slideNow()
	local f = ensureForce(root)
	local mass = 0
	pcall(function()
		mass = root.AssemblyMass
	end)
	f.Force = slide * (if mass > 0 then mass else 10)
	if grapple then
		grapple.t += dt
		local offset = grapple.target - root.CFrame.Position
		if offset.Magnitude < 3 or grapple.t > grapple.maxTime then
			grapple = nil
			if MovementController.rope then
				MovementController.rope(nil)
			end
		else
			root.AssemblyLinearVelocity = offset.Unit * GameConfig.Grapple.PullSpeed
		end
	end
end

function MovementController.knockback(v)
	local root = ClientState.root()
	if root and typeof(v) == "Vector3" then
		root.AssemblyLinearVelocity += v
		if MovementController.shake then
			MovementController.shake(0.6, 0.4)
		end
	end
end

function MovementController.startGrapple(target)
	local root = ClientState.root()
	if not root or typeof(target) ~= "Vector3" then
		return false
	end
	local dist = (target - root.CFrame.Position).Magnitude
	grapple = { target = target, t = 0, maxTime = dist / GameConfig.Grapple.PullSpeed + 0.4 }
	if MovementController.rope then
		MovementController.rope(target)
	end
	return true
end

function MovementController.grappling()
	return grapple ~= nil
end

function MovementController.init()
	ClientState.Lurched:Connect(MovementController.onLurch)
	ClientState.Knocked:Connect(MovementController.knockback)
	ClientState.GrappleOk:Connect(MovementController.startGrapple)
	RunService.Heartbeat:Connect(MovementController.step)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		force, attachment, grapple = nil, nil, nil
		table.clear(pending)
	end)
end

return MovementController
