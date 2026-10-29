--[[
	DoorMath - how an exit vault door's leaf swings (shared by the client, which animates
	it, and the harness, which checks the tunnel is blocked until it opens).
	The leaf model's pivot is its HingeAxis part, so rotating the pivot about its own
	vertical axis swings the whole leaf. alpha 0 = closed, 1 = open (100 degrees, into the
	pool side so it never blocks the tunnel).
]]

local DoorMath = {}

DoorMath.OpenAngle = math.rad(-100)

function DoorMath.pivot(hinge, alpha)
	return hinge * CFrame.Angles(0, DoorMath.OpenAngle * alpha, 0)
end

return DoorMath
