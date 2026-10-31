local Loader = require("./loader")
local VehicleRegistry = Loader.shared("Vehicles/Registry")
local VehicleModels = Loader.shared("VehicleModels")
local KartStats = Loader.shared("Config/KartStats")
local GameConfig = Loader.shared("Config/GameConfig")
local ShopConfig = Loader.shared("Config/ShopConfig")

-- Anything that smells like physics. A vehicle may only be cosmetic.
local FORBIDDEN = {}
for _, k in ipairs(KartStats.physicsKeys()) do
	FORBIDDEN[string.lower(k)] = true
end
for _, k in ipairs({ "speed", "accel", "acceleration", "handling", "weight", "mass", "grip", "turn", "turnrate", "drift", "boost", "stats", "physics", "hitbox", "radius", "size", "topspeed", "friction", "power", "maxspeed" }) do
	FORBIDDEN[k] = true
end

local function scan(t, path, seen)
	seen = seen or {}
	if seen[t] then
		return
	end
	seen[t] = true
	for k, v in pairs(t) do
		if type(k) == "string" then
			assert(not FORBIDDEN[string.lower(k)], path .. "." .. k .. " is a physics field - vehicles are cosmetic only")
		end
		if type(v) == "table" then
			scan(v, path .. "." .. tostring(k), seen)
		end
	end
end

return {
	{
		name = "Vehicles: every vehicle definition has NO physics overrides (identical physics for everyone)",
		fn = function()
			local all = VehicleRegistry.all()
			assert(#all >= 2, "Stage 1 needs at least 2 placeholder karts")
			for _, def in ipairs(all) do
				scan(def, def.Id)
				assert(type(def.Build) == "function" and type(def.Colors) == "table" and def.Name, def.Id .. " shape")
			end
			-- the shop can't sell physics either
			for _, list in ipairs({ ShopConfig.Products, ShopConfig.Passes }) do
				for _, item in ipairs(list) do
					scan(item, "Shop." .. item.Key)
				end
			end
			assert(#VehicleRegistry.PLANNED == GameConfig.ContentTargets.Vehicles, "the planned line-up isn't 25")
		end,
	},
	{
		name = "Vehicles: every model uses the same invisible chassis hitbox; cosmetics are welded, massless, non-colliding",
		fn = function()
			local hb = KartStats.Hitbox
			for _, def in ipairs(VehicleRegistry.all()) do
				local model, rig = VehicleModels.build(def.Id, { label = "Test" })
				local chassis = model.PrimaryPart
				assert(chassis and chassis.Name == "Chassis", def.Id .. " has no chassis")
				assert((chassis.Size - Loader.roblox.Vector3.new(hb.X, hb.Y, hb.Z)).Magnitude < 1e-4, def.Id .. " hitbox differs")
				assert(chassis.Anchored and not chassis.CanCollide and chassis.Transparency == 1, def.Id .. " chassis flags")
				local n = 0
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d ~= chassis then
						n += 1
						assert(not d.Anchored and not d.CanCollide and d.Massless, def.Id .. "." .. d.Name .. " is not cosmetic")
						assert(d:FindFirstChildOfClass("WeldConstraint") or d:FindFirstChildOfClass("Weld"), def.Id .. "." .. d.Name .. " is not welded")
					end
				end
				assert(n >= 20 and n <= 80, def.Id .. " part count " .. n)
				assert(#rig.wheels == 4 and #rig.sparks == 2 and rig.exhaust, def.Id .. " rig")
				VehicleModels.animate(rig, { speed = 50, steer = 1, drift = 1, squash = 0.2, dt = 1 / 60 })
				model:Destroy()
			end
		end,
	},
}
