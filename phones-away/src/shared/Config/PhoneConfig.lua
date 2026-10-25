--[[
	Phone apps (tiny minigames) and their server-side validation limits.

	The client only ever sends "phone up / down", which app is open and minigame inputs.
	Every reward below is computed on the server, rate limited and capped per class.
]]

return {
	RaiseSeconds = 0.25, -- phone coming out of the desk (visible, not earning yet)

	Apps = {
		{ Id = "Feed", Name = "Scroll Feed", Color = { 255, 90, 150 }, Hint = "Tap LIKE on posts. Every tap makes a little noise." },
		{ Id = "Text", Name = "Text Bestie", Color = { 90, 200, 255 }, Hint = "Reply with the word your bestie asks for. Fast!" },
		{ Id = "Game", Name = "Tap Dash", Color = { 255, 210, 70 }, Hint = "Tap when the marker is in the green zone." },
		{ Id = "Selfie", Name = "Selfie", Color = { 200, 120, 255 }, Hint = "Huge Clout. The FLASH is very risky." },
	},
	AppOrder = { "Feed", "Text", "Game", "Selfie" },

	Feed = {
		LikeClout = 1.5,
		ScrollGap = 0.25, -- min seconds between scrolls
		LikeRate = 5, -- likes per second allowed (burst 5)
		Taps = 1,
		ViralChance = 0.08, -- a viral post pays x4
		ViralMultiplier = 4,
		Posts = {
			{ Kind = "cat", Caption = "my cat learned to open the fridge" },
			{ Kind = "meme", Caption = "me pretending to read the textbook" },
			{ Kind = "food", Caption = "cafeteria pizza tier list (all S)" },
			{ Kind = "dance", Caption = "new dance trend just dropped" },
			{ Kind = "sports", Caption = "UNREAL buzzer beater" },
			{ Kind = "art", Caption = "drew my teacher as a superhero" },
			{ Kind = "dog", Caption = "dog sees snow for the first time" },
			{ Kind = "music", Caption = "this song lives in my head now" },
			{ Kind = "fail", Caption = "tried a backflip. the floor won." },
			{ Kind = "news", Caption = "school lunch is tacos tomorrow?!" },
		},
	},

	Text = {
		BaseClout = 6,
		SpeedBonus = 6, -- full bonus for an instant answer, linear to 0 at Timeout
		Timeout = 8,
		MinSecondsPerChar = 0.04, -- faster than this is not a human
		Taps = 3,
		Words = {
			"bruh", "lol", "omw", "brb", "same", "fr", "slay", "nope", "yesss", "help",
			"lunch", "pizza", "rizz", "mood", "vibes", "chill", "noway", "wait", "ok", "goat",
		},
		Asks = {
			"quick say '%s' if ur bored",
			"reply '%s' if she's looking",
			"type '%s' rn its urgent",
			"say '%s' for good luck",
			"'%s'? yes or yes",
		},
	},

	Game = {
		Period = 1.25, -- seconds for the marker to cross the bar once
		PerfectZone = 0.07, -- half-width around the centre
		GoodZone = 0.17,
		PerfectClout = 4,
		GoodClout = 2,
		ComboStep = 0.15, -- +15% per combo, capped
		ComboCap = 2,
		TapGap = 0.3,
		LatencyWindow = 0.4, -- a claimed tap time may be this far in the past
		Taps = 1,
	},

	Selfie = {
		Clout = 22,
		Cooldown = 9,
		Taps = 1,
	},

	-- Passive Clout while the phone is out (multiplied by the phone model's rate).
	PassivePerSecond = 0.8,

	-- Per-class caps (base Clout, before multipliers): nobody can farm a broken client.
	Caps = {
		Feed = 260,
		Text = 300,
		Game = 300,
		Selfie = 200,
		Passive = 220,
		Total = 900,
	},
	-- Hard plausibility limit on actions of any kind.
	ActionsPerSecond = 8,

	Quiz = {
		{ Q = "7 x 8 = ?", A = { "54", "56", "64" }, Correct = 2 },
		{ Q = "Capital of France?", A = { "Paris", "Rome", "Madrid" }, Correct = 1 },
		{ Q = "How many sides does a hexagon have?", A = { "5", "8", "6" }, Correct = 3 },
		{ Q = "H2O is...", A = { "Water", "Salt", "Gold" }, Correct = 1 },
		{ Q = "12 / 4 = ?", A = { "3", "4", "6" }, Correct = 1 },
		{ Q = "Which is a planet?", A = { "Pluto-ish", "Mars", "The Moon" }, Correct = 2 },
		{ Q = "Past tense of 'run'?", A = { "runned", "ran", "running" }, Correct = 2 },
		{ Q = "A triangle's angles add up to...", A = { "180", "90", "360" }, Correct = 1 },
		{ Q = "Biggest ocean?", A = { "Atlantic", "Indian", "Pacific" }, Correct = 3 },
		{ Q = "15 + 27 = ?", A = { "42", "32", "41" }, Correct = 1 },
		{ Q = "Plants make food using...", A = { "Wi-Fi", "Sunlight", "Glue" }, Correct = 2 },
		{ Q = "Opposite of 'ancient'?", A = { "Old", "Modern", "Dusty" }, Correct = 2 },
	},
}
