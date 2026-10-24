--[[
	The 20 Blobby species. All original creatures.

	Price and Income are the base values (before mutations, rebirths and passes).
	The look is built procedurally by BlobbyModels from:
	  Shape        Round | Tall | Flat | Spiky | Pear | Cube | Noodle | Dumpling
	  Eyes         Googly | Sleepy | Cyclops | Tiny | Angry | Shades | Stalks
	  Hat          None | Top | Crown | Propeller | Wizard | Chef | Party | Halo | Viking | Beanie
	  Accessories  Bowtie | Mustache | Tongue | Cape | Monocle | Antenna | Tail | Arms | Wings
	  Bob          Bounce | Wobble | Spin | Hop | Sway | Float   (client-side idle animation)
	Colors are RGB arrays: Body, Accent (hats, details), Belly (optional lighter patch).
]]

local Species = {
	-- Common
	{
		Id = "Wobbleton", Name = "Wobbleton", Rarity = "Common", Price = 25, Income = 1,
		Shape = "Round", Eyes = "Googly", Hat = "None", Accessories = { "Arms" }, Bob = "Wobble",
		Body = { 120, 200, 255 }, Accent = { 255, 255, 255 }, Belly = { 200, 236, 255 },
		Flavor = "Wobbles when happy. Is always happy.",
	},
	{
		Id = "Snorkpuff", Name = "Snorkpuff", Rarity = "Common", Price = 40, Income = 2,
		Shape = "Pear", Eyes = "Tiny", Hat = "Beanie", Accessories = { "Tongue" }, Bob = "Bounce",
		Body = { 255, 150, 190 }, Accent = { 90, 120, 255 }, Belly = { 255, 205, 225 },
		Flavor = "Snorts glitter when it sneezes.",
	},
	{
		Id = "Gloopsy", Name = "Gloopsy", Rarity = "Common", Price = 60, Income = 3,
		Shape = "Flat", Eyes = "Stalks", Hat = "None", Accessories = {}, Bob = "Sway",
		Body = { 150, 230, 90 }, Accent = { 90, 160, 50 },
		Flavor = "Mostly puddle. Somewhat friend.",
	},
	{
		Id = "Bonkus", Name = "Bonkus", Rarity = "Common", Price = 85, Income = 4,
		Shape = "Cube", Eyes = "Angry", Hat = "Propeller", Accessories = {}, Bob = "Hop",
		Body = { 255, 160, 70 }, Accent = { 255, 70, 70 },
		Flavor = "Bonks things. Has never once said sorry.",
	},
	-- Uncommon
	{
		Id = "TaterTumble", Name = "Tater Tumble", Rarity = "Uncommon", Price = 180, Income = 7,
		Shape = "Tall", Eyes = "Sleepy", Hat = "Top", Accessories = { "Mustache" }, Bob = "Wobble",
		Body = { 196, 146, 94 }, Accent = { 40, 36, 44 }, Belly = { 222, 186, 140 },
		Flavor = "A very distinguished potato.",
	},
	{
		Id = "Fizzlewick", Name = "Fizzlewick", Rarity = "Uncommon", Price = 260, Income = 10,
		Shape = "Spiky", Eyes = "Googly", Hat = "Party", Accessories = { "Antenna" }, Bob = "Bounce",
		Body = { 255, 226, 80 }, Accent = { 255, 90, 160 },
		Flavor = "Fizzes like soda when shaken. Please don't.",
	},
	{
		Id = "MumboJello", Name = "Mumbo Jello", Rarity = "Uncommon", Price = 360, Income = 14,
		Shape = "Cube", Eyes = "Cyclops", Hat = "None", Accessories = { "Arms" }, Bob = "Wobble", Jelly = true,
		Body = { 255, 80, 96 }, Accent = { 255, 220, 230 },
		Flavor = "There is a grape stuck inside. It is fine.",
	},
	-- Rare
	{
		Id = "SpikelordPip", Name = "Spikelord Pip", Rarity = "Rare", Price = 1100, Income = 35,
		Shape = "Spiky", Eyes = "Angry", Hat = "Viking", Accessories = { "Cape" }, Bob = "Hop",
		Body = { 110, 92, 222 }, Accent = { 220, 220, 230 },
		Flavor = "Ruler of a kingdom of three pebbles.",
	},
	{
		Id = "NoodleNanny", Name = "Noodle Nanny", Rarity = "Rare", Price = 1500, Income = 46,
		Shape = "Noodle", Eyes = "Sleepy", Hat = "Chef", Accessories = { "Tail" }, Bob = "Sway",
		Body = { 255, 230, 160 }, Accent = { 255, 255, 255 },
		Flavor = "Tucks the other Blobbies in at night.",
	},
	{
		Id = "CaptainSquish", Name = "Captain Squish", Rarity = "Rare", Price = 2100, Income = 62,
		Shape = "Round", Eyes = "Shades", Hat = "Top", Accessories = { "Bowtie" }, Bob = "Bounce",
		Body = { 60, 204, 182 }, Accent = { 30, 40, 80 }, Belly = { 170, 245, 230 },
		Flavor = "Captain of a ship that is also a bathtub.",
	},
	-- Epic
	{
		Id = "DiscoDumpling", Name = "Disco Dumpling", Rarity = "Epic", Price = 8500, Income = 230,
		Shape = "Dumpling", Eyes = "Shades", Hat = "Party", Accessories = { "Bowtie" }, Bob = "Spin",
		Body = { 250, 244, 232 }, Accent = { 186, 96, 255 },
		Flavor = "Steamed, glazed, and ready to boogie.",
	},
	{
		Id = "Wizzlebop", Name = "Wizzlebop the Wise", Rarity = "Epic", Price = 12000, Income = 310,
		Shape = "Tall", Eyes = "Sleepy", Hat = "Wizard", Accessories = { "Mustache" }, Bob = "Float",
		Body = { 96, 76, 210 }, Accent = { 255, 220, 90 }, Belly = { 150, 136, 240 },
		Flavor = "Knows one spell. It makes toast.",
	},
	{
		Id = "SirPancake", Name = "Sir Pancake III", Rarity = "Epic", Price = 16000, Income = 400,
		Shape = "Flat", Eyes = "Googly", Hat = "Crown", Accessories = { "Monocle" }, Bob = "Hop",
		Body = { 236, 182, 96 }, Accent = { 255, 215, 60 }, Belly = { 160, 90, 40 },
		Flavor = "Heir to the Syrup Throne.",
	},
	-- Legendary
	{
		Id = "Gigachonk", Name = "Gigachonk", Rarity = "Legendary", Price = 65000, Income = 1400,
		Shape = "Round", Eyes = "Angry", Hat = "Viking", Accessories = { "Arms" }, Bob = "Bounce",
		Body = { 64, 156, 76 }, Accent = { 200, 200, 210 }, Belly = { 140, 210, 130 },
		Flavor = "Absolute unit. Eats pedestals for breakfast (it doesn't).",
	},
	{
		Id = "BubblegumBaron", Name = "Bubblegum Baron", Rarity = "Legendary", Price = 90000, Income = 1900,
		Shape = "Pear", Eyes = "Cyclops", Hat = "Top", Accessories = { "Cape" }, Bob = "Float",
		Body = { 255, 96, 204 }, Accent = { 40, 30, 60 }, Belly = { 255, 180, 235 },
		Flavor = "Owns 40% of the world's chewed gum.",
	},
	{
		Id = "LordWigglesworth", Name = "Lord Wigglesworth", Rarity = "Legendary", Price = 125000, Income = 2500,
		Shape = "Noodle", Eyes = "Googly", Hat = "Crown", Accessories = { "Cape" }, Bob = "Sway",
		Body = { 255, 112, 64 }, Accent = { 255, 215, 60 },
		Flavor = "Has wiggled with kings.",
	},
	-- Mythic
	{
		Id = "CosmoBlorbo", Name = "Cosmo Blorbo", Rarity = "Mythic", Price = 550000, Income = 10500,
		Shape = "Round", Eyes = "Cyclops", Hat = "Halo", Accessories = { "Antenna", "Arms" }, Bob = "Float",
		Body = { 44, 34, 96 }, Accent = { 120, 220, 255 }, Belly = { 90, 70, 170 }, NeonAccent = true,
		Flavor = "Fell from space. Refuses to go back.",
	},
	{
		Id = "GrandGloobini", Name = "The Grand Gloobini", Rarity = "Mythic", Price = 900000, Income = 16000,
		Shape = "Tall", Eyes = "Stalks", Hat = "Wizard", Accessories = { "Wings" }, Bob = "Spin",
		Body = { 206, 44, 146 }, Accent = { 60, 230, 210 }, Belly = { 240, 140, 200 }, NeonAccent = true,
		Flavor = "Pulls a smaller Gloobini out of its hat. Every time.",
	},
	-- Secret
	{
		Id = "Blorbzilla", Name = "Blorbzilla", Rarity = "Secret", Price = 5500000, Income = 100000,
		Shape = "Spiky", Eyes = "Angry", Hat = "Crown", Accessories = { "Tail", "Arms" }, Bob = "Hop",
		Body = { 40, 42, 52 }, Accent = { 255, 60, 60 }, NeonAccent = true,
		Flavor = "Stomps cities. Very small cities. Made of blocks.",
	},
	{
		Id = "VoidNoodle", Name = "Void Noodle Supreme", Rarity = "Secret", Price = 9000000, Income = 155000,
		Shape = "Noodle", Eyes = "Tiny", Hat = "Halo", Accessories = { "Wings" }, Bob = "Float",
		Body = { 18, 14, 30 }, Accent = { 190, 90, 255 }, NeonAccent = true,
		Flavor = "Nobody knows where it ends. Not even it.",
	},
}

local byId = {}
local byRarity = {}
for index, species in ipairs(Species) do
	species.Index = index
	byId[species.Id] = species
	byRarity[species.Rarity] = byRarity[species.Rarity] or {}
	table.insert(byRarity[species.Rarity], species)
end

return {
	List = Species,
	ById = byId,
	ByRarity = byRarity,
}
