--[[
	Mover - walks anchored Blobby roots along waypoints with a little hop.
	Driven by Heartbeat on the server (Mover.step), and steppable directly in tests.
]]

local RunService = game:GetService("RunService")

local Mover = {}

local walkers = {} -- [root] = { points, index, speed, onDone, travelled, finalCFrame }

-- points: array of Vector3 feet positions. finalCFrame (optional) is applied on arrival.
function Mover.walk(root, points, speed, onDone, finalCFrame)
	walkers[root] = {
		points = points,
		index = 1,
		speed = speed,
		onDone = onDone,
		travelled = 0,
		finalCFrame = finalCFrame,
	}
end

function Mover.cancel(root)
	walkers[root] = nil
end

function Mover.isMoving(root)
	return walkers[root] ~= nil
end

function Mover.count()
	local n = 0
	for _ in pairs(walkers) do
		n += 1
	end
	return n
end

function Mover.step(dt)
	for root, w in pairs(walkers) do
		if not root.Parent then
			walkers[root] = nil
			continue
		end
		local remaining = w.speed * dt
		local pos = root:GetAttribute("MoverPos") or root.CFrame.Position
		local facing = root.CFrame.LookVector
		while remaining > 0 and w.index <= #w.points do
			local target = w.points[w.index]
			local delta = target - pos
			local dist = delta.Magnitude
			if dist < 1e-3 then
				w.index += 1
			elseif dist <= remaining then
				pos = target
				remaining -= dist
				w.travelled += dist
				facing = Vector3.new(delta.X, 0, delta.Z)
				w.index += 1
			else
				pos += delta.Unit * remaining
				w.travelled += remaining
				facing = Vector3.new(delta.X, 0, delta.Z)
				remaining = 0
			end
		end
		if w.index > #w.points then
			walkers[root] = nil
			root:SetAttribute("MoverPos", nil)
			root.CFrame = w.finalCFrame or CFrame.lookAt(pos, pos + (if facing.Magnitude > 1e-3 then facing.Unit else Vector3.new(0, 0, -1)))
			if w.onDone then
				task.spawn(w.onDone)
			end
		else
			root:SetAttribute("MoverPos", pos)
			local hop = math.abs(math.sin(w.travelled * 1.4)) * 0.45
			local dir = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.new(0, 0, -1)
			local shown = pos + Vector3.new(0, hop, 0)
			root.CFrame = CFrame.lookAt(shown, shown + dir)
		end
	end
end

function Mover.start()
	RunService.Heartbeat:Connect(Mover.step)
end

return Mover
