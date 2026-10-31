--[[
	BUBBLEGUM BUMPER - a rounded fairground bumper car with a big rubber ring, a pole spark
	antenna and a tail fin. COSMETIC ONLY: KartStats physics and the shared hitbox.
]]

return {
	Id = "BubblegumBumper",
	Name = "Bubblegum Bumper",
	Rarity = "Rare",
	Stage = 1,
	Unlock = "default",
	Colors = { Body = { 255, 120, 200 }, Trim = { 120, 230, 255 }, Accent = { 255, 255, 120 }, Seat = { 70, 40, 110 }, Metal = { 200, 200, 210 } },
	Build = function(b)
		local c = b.colors
		b:box("Floor", Vector3.new(4.8, 0.5, 7.4), CFrame.new(0, -0.55, 0), c.Seat)
		b:ball("Shell", Vector3.new(5.2, 2.4, 7.6), CFrame.new(0, 0.3, 0.2), c.Body)
		b:box("Ring", Vector3.new(5.6, 0.7, 8.2), CFrame.new(0, -0.35, 0.1), c.Trim)
		b:box("Cockpit", Vector3.new(3, 1.2, 2.8), CFrame.new(0, 1.2, 0.8), c.Seat)
		b:box("Seat", Vector3.new(2.4, 1.6, 0.6), CFrame.new(0, 1.6, 2.2), c.Seat)
		b:box("Dash", Vector3.new(3, 0.9, 0.8), CFrame.new(0, 1.3, -0.9), c.Body)
		b:cylinder("Wheel", 1.4, 0.25, CFrame.new(0, 1.9, -0.6) * CFrame.Angles(math.rad(55), 0, 0) * CFrame.Angles(0, 0, math.rad(90)), c.Seat)
		b:box("Pole", Vector3.new(0.25, 4.5, 0.25), CFrame.new(0, 3.6, 3.2), c.Metal, "Metal")
		b:ball("PoleTip", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 5.9, 3.2), c.Accent, "Neon")
		b:wedge("Fin", Vector3.new(0.4, 1.6, 2), CFrame.new(0, 1.6, 3.4), c.Trim)
		for _, side in ipairs({ -1, 1 }) do
			b:ball("Headlight", Vector3.new(0.8, 0.8, 0.5), CFrame.new(side * 1.5, 0.7, -3.5), c.Accent, "Neon")
			b:box("Spot", Vector3.new(0.4, 0.6, 1.6), CFrame.new(side * 2.55, 0.6, 1), c.Accent)
		end
		b:wheels({ radius = 0.95, width = 0.9, front = -2.8, rear = 2.8, track = 2.3, rearWidth = 0.9 })
		b:driver(CFrame.new(0, 1.3, 1.2))
	end,
}
