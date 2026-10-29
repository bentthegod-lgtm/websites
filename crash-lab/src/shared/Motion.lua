--[[
	Motion - pure maths for the moving targets (CourseConfig.Targets[*].Motion).

	position(def, t) is where the target is at time t; velocity(def, t) is its exact time
	derivative. The server moves the anchored target parts with CFrame AND sets their
	AssemblyLinearVelocity to velocity(), so the physics solver treats them as genuinely
	moving: contacts push the dummy with the target's real speed instead of the target
	teleport-shoving (and flinging) it every frame.
]]

local Motion = {}

local TAU = math.pi * 2

function Motion.position(def, t)
	local motion = def.Motion
	if not motion then
		return def.Position
	end
	local phase = math.sin(t / motion.Period * TAU)
	local offset = phase * motion.Amplitude
	if motion.Kind == "Swing" then
		-- Pendulum: a slight lift at the ends of the swing.
		return def.Position + Vector3.new(offset, phase * phase * 3, 0)
	end
	return def.Position + Vector3.new(offset, 0, 0)
end

function Motion.velocity(def, t)
	local motion = def.Motion
	if not motion then
		return Vector3.new(0, 0, 0)
	end
	local w = TAU / motion.Period
	local phase = math.sin(t * w)
	local dphase = math.cos(t * w) * w
	local vx = dphase * motion.Amplitude
	if motion.Kind == "Swing" then
		return Vector3.new(vx, 2 * phase * dphase * 3, 0)
	end
	return Vector3.new(vx, 0, 0)
end

return Motion
