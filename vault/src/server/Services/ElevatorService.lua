--[[
	ElevatorService - rides between depths.

	The cabin doesn't physically travel (moving a crowd of players through a 900-stud shaft
	reliably is not worth the risk); instead the ride is a short, validated transition:
	  1. The client asks Travel(depth) from inside or next to its depth's cabin.
	  2. The server checks the depth is unlocked and not the current one, the player is at
	     the cabin, and isn't already riding; then sends "Depart" with the ride time
	     (1.4 s + 0.35 s per floor, capped) - the rider's client closes the doors, plays the
	     motor, counts floors and flashes shaft lights past the window.
	  3. When the time is up the server moves the character into the destination cabin and
	     sends "Arrive" - doors open on the new floor.
	A rider who dies, leaves or rebirths mid-ride has the ride cancelled.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)

local ElevatorService = {}

local services
local world
local riding = {} -- [player] = { to, token }
local lastRide = {}
local tokenCounter = 0

function ElevatorService.init(registry)
	services = registry
end

function ElevatorService.setWorld(newWorld)
	world = newWorld
end

function ElevatorService.rideTime(from, to)
	return math.min(3.6, 1.4 + 0.35 * math.abs(to - from))
end

function ElevatorService.isRiding(player)
	return riding[player] ~= nil
end

-- The depth a rider is heading to (its pool fills while they ride), or nil.
function ElevatorService.rideTarget(player)
	return riding[player] and riding[player].to
end

function ElevatorService.cancel(player)
	if riding[player] then
		riding[player] = nil
		if player.Parent then
			services.Remotes.Elevator:FireClient(player, "Cancel", {})
		end
	end
end

local function arrive(player, ride)
	if riding[player] ~= ride then
		return -- cancelled
	end
	riding[player] = nil
	local root = services.PlayerService.root(player)
	local data = services.DataService.getProfile(player)
	if not root or not data or not player.Parent then
		return
	end
	data.CurrentDepth = ride.to
	services.DataService.markDirty(player)
	services.PlayerService.place(player, ride.to)
	services.PlayerService.updateAttributes(player)
	services.DataService.bump(player, "Visit:" .. ride.to, 1)
	if ride.to >= 2 then
		services.QuestService.tutorialEvent(player, "TravelDeep")
	end
	local def = DepthConfig.get(ride.to)
	services.Remotes.Elevator:FireClient(player, "Arrive", { depth = ride.to, code = def.Code, name = def.Name })
	services.DataService.sendProfile(player)
end

-- Returns (true, rideTime) or (false, reason).
function ElevatorService.travel(player, depth)
	local data = services.DataService.getProfile(player)
	if not data or type(depth) ~= "number" or depth ~= depth then
		return false, "Invalid floor."
	end
	depth = math.floor(depth)
	local def = DepthConfig.get(depth)
	if not def then
		return false, "Invalid floor."
	end
	if depth > data.HighestDepth then
		return false, def.Code .. " is locked. Unlock it at the floor panel first."
	end
	if riding[player] then
		return false, "Already riding."
	end
	local root = services.PlayerService.root(player)
	if not root then
		return false, "No character."
	end
	local from = services.PlayerService.depthOf(player)
	if from == depth then
		return false, "You're already on " .. def.Code .. "."
	end
	local cabin = world.depths[from].elevator
	if (root.CFrame.Position - cabin.cframe.Position).Magnitude > GameConfig.ElevatorRange then
		return false, "Step into the elevator first."
	end
	local now = os.clock()
	if lastRide[player] and now - lastRide[player] < 1.5 then
		return false, "The elevator is resetting."
	end
	lastRide[player] = now
	tokenCounter += 1
	local ride = { to = depth, from = from, token = tokenCounter }
	riding[player] = ride
	-- Start filling the destination's pool now, round the doors the rider will step out of.
	services.LootService.activate(depth, false, world.depths[depth].elevator.arrival.Position)
	local duration = ElevatorService.rideTime(from, depth)
	services.Remotes.Elevator:FireClient(player, "Depart", { from = from, to = depth, duration = duration, code = def.Code, name = def.Name })
	task.delay(duration, arrive, player, ride)
	return true, duration
end

function ElevatorService.onProfileLoaded(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			ElevatorService.cancel(player)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		local h = character:WaitForChild("Humanoid", 10)
		if h then
			h.Died:Connect(function()
				ElevatorService.cancel(player)
			end)
		end
	end)
end

function ElevatorService.onPlayerRemoving(player)
	riding[player] = nil
	lastRide[player] = nil
end

function ElevatorService.start()
	services.Remotes.Travel.OnServerEvent:Connect(function(player, depth)
		local ok, message = ElevatorService.travel(player, depth)
		if not ok then
			services.Remotes.Notify:FireClient(player, message, "error")
		end
	end)
end

return ElevatorService
