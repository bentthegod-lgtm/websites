--[[
	Vehicles/Registry - every kart body. One module per vehicle in this folder. Vehicles are
	PURELY COSMETIC: they all use KartStats (identical physics) and KartStats.Hitbox. A
	vehicle module holds Id, Name, Rarity, Stage, Unlock, Colors and Build(builder) - and
	nothing that touches physics (unit-tested).

	Stage 1 ships 2 placeholder karts; Stage 2 adds the rest of the 25 (PLANNED below).
]]

local Registry = {}

Registry.ORDER = { "Sparkplug", "BubblegumBumper" }

-- The full Stage 2 line-up (25 total). Names are original.
Registry.PLANNED = {
	"Sparkplug",
	"BubblegumBumper",
	"Toastmobile",
	"Burger Buggy",
	"Rubber Duckster",
	"Neon Noodle",
	"Banana Boat",
	"Rocket Couch",
	"Shopping Cart GT",
	"Taco Truckette",
	"Pizza Slicer",
	"Jelly Jet",
	"Lava Lamp Racer",
	"Moonwalker",
	"Disco Ball",
	"Pickle Pod",
	"Robo Roller",
	"Hover Hamster",
	"Sushi Speeder",
	"Cactus Cruiser",
	"Thunder Teapot",
	"Space Waffle",
	"Snail Rocket",
	"Gummy Bear Bus",
	"Chaos Crown",
}

local modules = {}
for _, id in ipairs(Registry.ORDER) do
	local def = require(script.Parent[id])
	assert(def.Id == id, "vehicle id mismatch: " .. id)
	modules[id] = def
end

Registry.DEFAULT = "Sparkplug"

function Registry.get(id)
	return modules[id] or modules[Registry.DEFAULT]
end

function Registry.exists(id)
	return type(id) == "string" and modules[id] ~= nil
end

function Registry.all()
	local list = {}
	for _, id in ipairs(Registry.ORDER) do
		table.insert(list, modules[id])
	end
	return list
end

return Registry
