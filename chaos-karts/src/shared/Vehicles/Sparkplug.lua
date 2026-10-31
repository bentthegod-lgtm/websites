--[[
	SPARKPLUG - the starter kart: a classic low go-kart with a nose cone, side pods, a rear
	wing and twin exhausts. COSMETIC ONLY: like every vehicle it drives with KartStats and
	the shared hitbox (a test fails if a vehicle module contains any physics key).
]]

return {
	Id = "Sparkplug",
	Name = "Sparkplug",
	Rarity = "Common",
	Stage = 1,
	Unlock = "default",
	Colors = { Body = { 232, 56, 60 }, Trim = { 250, 250, 250 }, Accent = { 255, 205, 50 }, Seat = { 30, 30, 36 }, Metal = { 170, 175, 186 } },
	Build = function(b)
		local c = b.colors
		-- floor pan and tub
		b:box("Floor", Vector3.new(4.6, 0.5, 7.6), CFrame.new(0, -0.55, 0), c.Seat)
		b:box("Tub", Vector3.new(4.2, 1.3, 4.4), CFrame.new(0, 0.2, 0.6), c.Body)
		b:box("Nose", Vector3.new(3.2, 0.9, 2.8), CFrame.new(0, -0.05, -3.3), c.Body)
		b:wedge("NoseCone", Vector3.new(3.2, 0.9, 1.6), CFrame.new(0, -0.05, -5.4) * CFrame.Angles(0, math.pi, 0), c.Body)
		b:box("Stripe", Vector3.new(0.7, 0.05, 6.4), CFrame.new(0, 0.88, -1.4), c.Trim)
		b:box("FrontBumper", Vector3.new(5, 0.5, 0.6), CFrame.new(0, -0.35, -5.9), c.Metal, "Metal")
		-- side pods with number plates
		for _, side in ipairs({ -1, 1 }) do
			b:box("SidePod", Vector3.new(0.9, 1, 3.6), CFrame.new(side * 2.45, -0.05, 0.4), c.Body)
			b:box("PodStripe", Vector3.new(0.95, 0.25, 3.6), CFrame.new(side * 2.47, 0.3, 0.4), c.Accent, "Neon")
		end
		-- seat, steering wheel, roll bar
		b:box("Seat", Vector3.new(2.2, 0.6, 1.8), CFrame.new(0, 0.3, 1.6), c.Seat)
		b:box("SeatBack", Vector3.new(2.2, 2, 0.5), CFrame.new(0, 1.1, 2.55) * CFrame.Angles(math.rad(-12), 0, 0), c.Seat)
		b:box("Column", Vector3.new(0.3, 0.3, 1.6), CFrame.new(0, 0.9, -0.9) * CFrame.Angles(math.rad(35), 0, 0), c.Metal, "Metal")
		b:cylinder("Wheel", 1.5, 0.25, CFrame.new(0, 1.35, -0.35) * CFrame.Angles(math.rad(60), 0, 0) * CFrame.Angles(0, 0, math.rad(90)), c.Seat)
		b:box("RollBar", Vector3.new(3, 0.35, 0.35), CFrame.new(0, 2.6, 2.75), c.Metal, "Metal")
		for _, side in ipairs({ -1, 1 }) do
			b:box("RollPost", Vector3.new(0.35, 2, 0.35), CFrame.new(side * 1.4, 1.6, 2.75), c.Metal, "Metal")
		end
		-- engine, exhausts, rear wing
		b:box("Engine", Vector3.new(2.6, 1.2, 1.6), CFrame.new(0, 0.1, 3.6), c.Metal, "DiamondPlate")
		for _, side in ipairs({ -1, 1 }) do
			b:cylinder("Exhaust", 1.6, 0.45, CFrame.new(side * 0.8, 0.5, 4.5) * CFrame.Angles(0, math.rad(90), 0), c.Metal, "Metal")
			b:box("WingPost", Vector3.new(0.25, 1.4, 0.4), CFrame.new(side * 1.5, 1.2, 4.1), c.Seat)
		end
		b:box("Wing", Vector3.new(4.8, 0.25, 1.3), CFrame.new(0, 2, 4.2) * CFrame.Angles(math.rad(-8), 0, 0), c.Body)
		b:box("WingTrim", Vector3.new(4.9, 0.3, 0.2), CFrame.new(0, 2.05, 3.6), c.Accent, "Neon")
		b:wheels({ radius = 1.15, width = 1, front = -3.2, rear = 3.1, track = 2.55, rearWidth = 1.3 })
		b:driver(CFrame.new(0, 0.6, 1.4))
	end,
}
