--[[
	Teacher AI tuning: senses (sight cone + hearing), suspicion thresholds, lesson phases and
	random class events. Read by the pure Detection / TeacherBrain / Lesson modules.
]]

return {
	Names = {
		Teacher = "Ms. Bellweather",
		Substitute = "Mr. Dozely (Sub)",
		Principal = "Principal Granite",
	},

	-- Suspicion is 0..1 per student. "?" and "!" are shown over the teacher's head.
	Suspicion = {
		Question = 0.3,
		Alert = 0.7,
		Catch = 1.0,
		DecayPerSecond = 0.1,
		DecayDelay = 1.0, -- seconds without new evidence before it starts to drop
		FocusAt = 0.4, -- above this the teacher drifts her gaze toward that student
	},

	Sight = {
		FovDegrees = 36, -- half-angle of the cone
		EdgeSoftness = 10, -- degrees over which the cone edge fades out
		Range = 62,
		Rate = 0.24, -- suspicion per second for a fully visible phone (x1.6 right next to her)
		NearBonus = 0.6, -- extra share at distance 0 (falls off to 0 at Range)
		LingerVisibility = 0.3, -- a just-hidden phone still glows a little
		RaiseVisibility = 0.6, -- phone coming up
		FlashMultiplier = 5, -- selfie flash
		FlashInstant = 0.4, -- instant suspicion if she SEES the flash
		DeskCheckRange = 8,
		DeskCheckRate = 1.3, -- walking the rows: checking desks up close (ignores most cover)
	},

	Hearing = {
		Range = 40,
		Rate = 0.3, -- per unit of noise per second
		MinNoise = 0.08, -- quieter than this is not heard at all
		FlashNoise = 0.6, -- the shutter "click"
		NoiseDecay = 2.5, -- noise units lost per second
		NoisePerTap = 0.22,
		MaxNoise = 1.4,
	},

	Turn = {
		Lecture = 34, -- degrees per second
		Walk = 70,
		Glance = 120,
		Distract = 160,
		Caught = 240,
	},

	WalkSpeed = 6.5,
	LectureSweep = 42, -- degrees either side of straight ahead
	LecturePace = 7, -- studs either side of the lecture spot

	-- Writing on the board: occasional over-the-shoulder glances, telegraphed by a pause
	-- (the marker squeak stops).
	Board = { GlanceEvery = { 7, 12 }, GlanceChance = 0.55, WarnSeconds = 0.9, GlanceSeconds = 1.3, GlanceSight = 0.75 },

	-- Phase defaults (multipliers on sight / hearing).
	Phases = {
		Board = { Label = "WRITING ON THE BOARD", Risk = "SAFE", Color = { 90, 230, 120 }, Sight = 0, Hearing = 0.5, Duration = { 14, 22 } },
		Lecture = { Label = "LECTURING", Risk = "RISKY", Color = { 255, 205, 70 }, Sight = 1, Hearing = 1, Duration = { 14, 20 } },
		Walk = { Label = "WALKING THE ROWS", Risk = "VERY RISKY", Color = { 255, 80, 80 }, Sight = 1.25, Hearing = 1.2, Duration = { 16, 22 } },
		Quiz = { Label = "BONUS QUESTION!", Risk = "PHONES = WRONG", Color = { 190, 120, 255 }, Sight = 1, Hearing = 1, Duration = { 10, 10 } },
		FireDrill = { Label = "FIRE DRILL!", Risk = "CHAOS", Color = { 255, 120, 40 }, Sight = 0.45, Hearing = 0.2, Duration = { 16, 16 }, Clout = 1.5 },
		LunchCheck = { Label = "LUNCH BELL?! (she's checking the hall)", Risk = "SAFE-ISH", Color = { 120, 200, 255 }, Sight = 0.2, Hearing = 0.4, Duration = { 12, 12 }, Clout = 1.25 },
	},

	-- Random class events (one per class, or none). Weights.
	Events = {
		None = { Weight = 38 },
		Substitute = { Weight = 15, Label = "SUBSTITUTE TEACHER", Text = "Ms. Bellweather is out. Mr. Dozely is subbing... and he looks SLEEPY.", Detection = 0.55, TurnScale = 0.7, NapEvery = { 14, 22 }, NapSeconds = 6 },
		Principal = { Weight = 20, Label = "THE PRINCIPAL WALKED IN", Text = "Principal Granite is watching. DOUBLE detection!", Detection = 2, Seconds = 24, Window = { 0.3, 0.65 } },
		FireDrill = { Weight = 12, Label = "FIRE DRILL", Text = "Total chaos! Perfect time to screenshot your test...", Window = { 0.3, 0.7 } },
		LunchBell = { Weight = 15, Label = "EARLY LUNCH BELL", Text = "The bell rang early! She's checking the hallway...", Window = { 0.4, 0.75 } },
	},
	EventOrder = { "None", "Substitute", "Principal", "FireDrill", "LunchBell" },

	-- The quiz always happens around the middle of class.
	QuizWindow = { 0.42, 0.58 },
	FirstPhase = "Board",
	FirstPhaseSeconds = 16,
	MinWalks = 2,
}
