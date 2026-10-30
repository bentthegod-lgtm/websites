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

-- Moves my character with the ship. Returns the new root CFrame (or nil if not moved).
function MovementController.onLurch(oldPivot, newPivot, info)
	local root = ClientState.root()
	local me = ClientState.me()
	local moved = nil
	if root and (me.state == "Alive" or me.state == "Lobby" or me.state == "Escaped") and not root.Anchored then
		local ship, _, length, beam, height = shipInfo()
		if ship and LurchMath.onShip(oldPivot, root.CFrame.Position, length, beam, height) then
			moved = LurchMath.relocate(oldPivot, newPivot, root.CFrame, 0.15)
			local character = root.Parent
			if character and character.PrimaryPart == root then
				character:PivotTo(moved)
			else
				root.CFrame = moved
			end
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	if MovementController.shake then
		local k = (info and info.tilt or 5) / 25
		MovementController.shake(GameConfig.Sinking.ShakeStrength * (0.6 + k), 0.9)
	end
	return moved
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
	end)
end

return MovementController
