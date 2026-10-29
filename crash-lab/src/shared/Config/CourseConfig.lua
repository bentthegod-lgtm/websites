--[[
	CourseConfig - every facility's course layout (shared by the world builders and the
	server's objective checks) and the facility progression framework.

	Coordinates are LOCAL to each facility: the launch line is Z = 0, the course runs
	toward +Z, X = 0 is the centre line. Each course has an Origin (its world offset); the
	facilities are built far apart (4,000 studs) so they never interact, and the server
	measures every run in its own course's local space.

	The top-level Rings / Targets / LandingZones / Objectives / DistanceGoals are the
	Industrial Crash Lab's (the hub course); CourseConfig.Courses holds all four. Ids are
	unique across facilities, so RingById / TargetById / ZoneById / ObjectiveById cover
	every course.
]]

local CourseConfig = {}

-- Rings: pass through the disc (centre, radius) - checked on the server from the
-- dummy's sampled path, so the dummy must really cross the ring's plane inside it.
CourseConfig.Rings = {
	{ Id = "RingLow", Name = "Low Ring", Position = Vector3.new(0, 20, 105), Radius = 10, Color = { 80, 220, 120 } },
	{ Id = "RingHigh", Name = "High Ring", Position = Vector3.new(0, 58, 255), Radius = 13, Color = { 255, 196, 40 } },
	{ Id = "RingSky", Name = "Sky Ring", Position = Vector3.new(0, 105, 375), Radius = 15, Color = { 255, 90, 200 } },
}

-- Targets: touched by the dummy (server Touched + speed check).
CourseConfig.Targets = {
	{ Id = "SwingTarget", Name = "Swinging Target", Position = Vector3.new(0, 16, 205), Radius = 7, Points = 150, Motion = { Kind = "Swing", Axis = "X", Amplitude = 32, Period = 6 } },
	{ Id = "SlideTarget", Name = "Sliding Target", Position = Vector3.new(0, 9, 320), Radius = 7, Points = 190, Motion = { Kind = "Slide", Axis = "X", Amplitude = 44, Period = 8 } },
	{ Id = "Gong", Name = "Far Gong", Position = Vector3.new(0, 30, 505), Radius = 13, Points = 300, Motion = nil },
}

-- Landing zones: the dummy's final resting point must be inside the circle.
CourseConfig.LandingZones = {
	{ Id = "GreenZone", Name = "Green Zone", Position = Vector3.new(0, 0, 150), Radius = 15, Points = 140, Color = { 80, 220, 120 } },
	{ Id = "Bullseye", Name = "Bullseye", Position = Vector3.new(0, 0, 425), Radius = 12, Points = 380, Color = { 235, 70, 60 } },
}

-- Distance markers (signs + floor lines every 50 studs; these three are objectives).
CourseConfig.MarkerEvery = 50
CourseConfig.DistanceGoals = { 100, 250, 400 }

-- Destructible props. Strength: the dummy class needed to break it (1 = any dummy at
-- impact speed; 2+ needs a heavier Payload class, lighter dummies bounce off).
CourseConfig.DestructibleKinds = {
	Cardboard = { Name = "Cardboard Box", Strength = 1, Points = 20, BreakSpeed = 25, Color = { 196, 150, 96 }, Material = "Cardboard", Debris = 4, Sound = "BoxCrunch" },
	Plastic = { Name = "Plastic Test Target", Strength = 1, Points = 35, BreakSpeed = 30, Color = { 250, 250, 245 }, Material = "Plastic", Debris = 3, Sound = "PlasticPop" },
	Wood = { Name = "Wooden Barrier", Strength = 1, Points = 45, BreakSpeed = 45, Color = { 168, 118, 70 }, Material = "Wood", Debris = 5, Sound = "WoodSnap" },
	Panel = { Name = "Breakaway Panel", Strength = 2, Points = 80, BreakSpeed = 55, Color = { 120, 190, 230 }, Material = "Glass", Transparency = 0.35, Debris = 5, Sound = "PanelShatter" },
	Tower = { Name = "Test Structure", Strength = 1, Points = 30, BreakSpeed = 30, Color = { 230, 120, 50 }, Material = "Plastic", Debris = 3, Sound = "BoxCrunch" },
	-- Destruction Testing Zone.
	Brick = { Name = "Brick Block", Strength = 1, Points = 25, BreakSpeed = 40, Color = { 170, 84, 62 }, Material = "Brick", Debris = 3, Sound = "BrickCrumble" },
	Crate = { Name = "Shipping Crate", Strength = 1, Points = 30, BreakSpeed = 32, Color = { 186, 136, 82 }, Material = "WoodPlanks", Debris = 4, Sound = "WoodSnap" },
	Glass = { Name = "Glass Pane", Strength = 1, Points = 40, BreakSpeed = 35, Color = { 170, 220, 235 }, Material = "Glass", Transparency = 0.45, Debris = 4, Sound = "PanelShatter" },
	Barrel = { Name = "Oil Drum", Strength = 1, Points = 30, BreakSpeed = 35, Color = { 210, 90, 40 }, Material = "Metal", Shape = "Cylinder", Debris = 3, Sound = "BarrelClang" },
}

-- Objectives. MinReach = roughly how far down the course (studs) a launch must be able to
-- go for the objective to be offered as the featured one.
CourseConfig.Objectives = {
	{ Id = "RingLow", Kind = "Ring", Name = "Pass through the Low Ring", Points = 120, MinReach = 90 },
	{ Id = "GreenZone", Kind = "Land", Name = "Land in the Green Zone", Points = 140, MinReach = 120 },
	{ Id = "Reach100", Kind = "Distance", Value = 100, Name = "Reach the 100 marker", Points = 80, MinReach = 80 },
	{ Id = "MultiTarget", Kind = "Multi", Value = 3, Name = "Hit 3 targets or props in one run", Points = 160, MinReach = 100 },
	{ Id = "SwingTarget", Kind = "Target", Name = "Hit the Swinging Target", Points = 150, MinReach = 170 },
	{ Id = "BreakBarrier", Kind = "Break", Group = "Fence", Name = "Smash a wooden barrier", Points = 100, MinReach = 150 },
	{ Id = "Reach250", Kind = "Distance", Value = 250, Name = "Reach the 250 marker", Points = 150, MinReach = 220 },
	{ Id = "RingHigh", Kind = "Ring", Name = "Thread the High Ring", Points = 250, MinReach = 230 },
	{ Id = "BreakWall", Kind = "Break", Group = "PanelWall", Name = "Break through the panel wall", Points = 220, MinReach = 270 },
	{ Id = "SlideTarget", Kind = "Target", Name = "Hit the Sliding Target", Points = 190, MinReach = 290 },
	{ Id = "RingSky", Kind = "Ring", Name = "Fly through the Sky Ring", Points = 450, MinReach = 340 },
	{ Id = "Reach400", Kind = "Distance", Value = 400, Name = "Reach the 400 marker", Points = 260, MinReach = 370 },
	{ Id = "Bullseye", Kind = "Land", Name = "Land on the Bullseye", Points = 380, MinReach = 390 },
	{ Id = "Gong", Kind = "Target", Name = "Ring the Far Gong", Points = 300, MinReach = 460 },
}
---------------------------------------------------------------------------------------------
-- Courses. Each entry is one facility's course in its own local space (see the header).
--   Origin        world offset of the local frame
--   Arena         FloorY (height reference for scoring), Length, HalfWidth, Ceiling, KillY
--                 (out of bounds below), LaunchZ, PlayerFloorY (players below this are put
--                 back on the deck)
--   PadCount      launch pads on the facility's deck
--   Run           overrides of GameConfig.Run (MaxDuration, MaxFloatTime ...)
--   Tuning        scoring overrides: DistancePoints, HeightPoints, SpeedHeadroom,
--                 FreeFall { PerStud, Max, Min }, Combo { Window, PerStep, MaxStep, Cap }
--   Wind          server gusts per run (deterministic per run seed, capped; see Hazards)
--   Gravity       low-gravity / flip volumes (server VectorForce on that dummy only)
--   ReachFactor   how much further than flat ground a launch goes here (featured picks)
---------------------------------------------------------------------------------------------

CourseConfig.Courses = {}

CourseConfig.Courses.IndustrialLab = {
	Id = "IndustrialLab",
	Origin = Vector3.new(0, 0, 0),
	Arena = { LaunchZ = 0, FloorY = 0, Length = 540, HalfWidth = 78, Ceiling = 320, KillY = -40 },
	PadCount = 6,
	Rings = CourseConfig.Rings,
	Targets = CourseConfig.Targets,
	LandingZones = CourseConfig.LandingZones,
	MarkerEvery = CourseConfig.MarkerEvery,
	DistanceGoals = CourseConfig.DistanceGoals,
	Objectives = CourseConfig.Objectives,
	ReachFactor = 1,
	Ambient = { "Ventilation", "Machinery", "ElectricHum", "Clank" },
}

CourseConfig.Courses.HighAltitude = {
	Id = "HighAltitude",
	-- The cliff-top deck is local Y = 0; the canyon floor is 200 studs below it.
	Origin = Vector3.new(4000, 300, 0),
	Arena = { LaunchZ = 0, FloorY = 0, CanyonFloorY = -200, Length = 640, HalfWidth = 90, Ceiling = 320, KillY = -235, PlayerFloorY = -25 },
	PadCount = 4,
	-- Rings hang from cables strung between the canyon walls (no posts).
	Rings = {
		{ Id = "HA_EagleRing", Name = "Eagle Ring", Position = Vector3.new(0, 40, 130), Radius = 14, Color = { 255, 210, 80 }, Floating = true },
		{ Id = "HA_CanyonRing", Name = "Canyon Ring", Position = Vector3.new(0, -55, 300), Radius = 16, Color = { 90, 200, 255 }, Floating = true },
		{ Id = "HA_DeepRing", Name = "Deep Ring", Position = Vector3.new(0, -125, 455), Radius = 18, Color = { 255, 110, 200 }, Floating = true },
	},
	Targets = {
		{ Id = "HA_CliffTarget", Name = "Cliff-Face Target", Position = Vector3.new(60, -35, 220), Radius = 8, Points = 200, Motion = nil, Mount = "Wall" },
		{ Id = "HA_CableTarget", Name = "Cable-Car Target", Position = Vector3.new(0, -70, 380), Radius = 8, Points = 260, Motion = { Kind = "Swing", Axis = "X", Amplitude = 30, Period = 7 }, Mount = "Cable" },
	},
	-- Landing ledges at three depths (Position.Y = the ledge's top surface).
	LandingZones = {
		{ Id = "HA_UpperLedge", Name = "Upper Ledge", Position = Vector3.new(0, -40, 160), Radius = 14, Points = 220, Color = { 80, 220, 120 } },
		{ Id = "HA_MidLedge", Name = "Middle Ledge", Position = Vector3.new(0, -95, 310), Radius = 15, Points = 320, Color = { 255, 196, 40 } },
		{ Id = "HA_DeepLedge", Name = "Deep Ledge", Position = Vector3.new(0, -150, 470), Radius = 16, Points = 450, Color = { 235, 70, 60 } },
	},
	-- Rope bridges across the canyon (obstacles; the middle one is an objective).
	Bridges = {
		{ Id = "HA_Bridge1", Z = 110, Y = -18 },
		{ Id = "HA_Bridge2", Z = 240, Y = -70 },
		{ Id = "HA_Bridge3", Z = 390, Y = -115 },
	},
	MarkerEvery = 50,
	DistanceGoals = { 150, 300, 450 },
	Objectives = {
		{ Id = "HA_Drop60", Kind = "FreeFall", Value = 60, Name = "Free-fall 60 studs", Points = 150, MinReach = 60 },
		{ Id = "HA_Reach150", Kind = "Distance", Value = 150, Name = "Reach the 150 marker", Points = 120, MinReach = 90 },
		{ Id = "HA_EagleRing", Kind = "Ring", Name = "Soar through the Eagle Ring", Points = 200, MinReach = 110 },
		{ Id = "HA_UpperLedge", Kind = "Land", Name = "Land on the Upper Ledge", Points = 220, MinReach = 120 },
		{ Id = "HA_Drop150", Kind = "FreeFall", Value = 150, Name = "Free-fall 150 studs", Points = 300, MinReach = 150 },
		{ Id = "HA_Bridge", Kind = "Hit", Key = "HA_Bridge2", Name = "Bounce off the middle rope bridge", Points = 160, MinReach = 200 },
		{ Id = "HA_CliffTarget", Kind = "Target", Name = "Hit the Cliff-Face Target", Points = 200, MinReach = 200 },
		{ Id = "HA_CanyonRing", Kind = "Ring", Name = "Dive through the Canyon Ring", Points = 300, MinReach = 260 },
		{ Id = "HA_MidLedge", Kind = "Land", Name = "Land on the Middle Ledge", Points = 320, MinReach = 280 },
		{ Id = "HA_Reach300", Kind = "Distance", Value = 300, Name = "Reach the 300 marker", Points = 220, MinReach = 280 },
		{ Id = "HA_CableTarget", Kind = "Target", Name = "Hit the Cable-Car Target", Points = 260, MinReach = 340 },
		{ Id = "HA_DeepRing", Kind = "Ring", Name = "Thread the Deep Ring", Points = 420, MinReach = 420 },
		{ Id = "HA_DeepLedge", Kind = "Land", Name = "Land on the Deep Ledge", Points = 450, MinReach = 440 },
		{ Id = "HA_Reach450", Kind = "Distance", Value = 450, Name = "Reach the 450 marker", Points = 350, MinReach = 440 },
	},
	Run = { MaxDuration = 24 },
	Tuning = {
		SpeedHeadroom = 1.35, -- long falls are fast: the anti-teleport check allows for it
		FreeFall = { PerStud = 0.8, Max = 240, Min = 15 }, -- "Free-Fall Bonus" for height lost
	},
	Wind = { StartZ = 20, Period = 0.7, MaxGust = 12, MaxTotal = 36, Vertical = 0.25 },
	ReachFactor = 1.5,
	Ambient = { "CanyonWind" },
}

CourseConfig.Courses.Destruction = {
	Id = "Destruction",
	Origin = Vector3.new(-4000, 0, 0),
	Arena = { LaunchZ = 0, FloorY = 0, Length = 520, HalfWidth = 75, Ceiling = 300, KillY = -40 },
	PadCount = 4,
	Rings = {
		{ Id = "DZ_CraneRing", Name = "Crane Ring", Position = Vector3.new(0, 48, 230), Radius = 13, Color = { 255, 170, 60 } },
	},
	Targets = {
		{ Id = "DZ_WreckingBall", Name = "Wrecking Ball", Position = Vector3.new(0, 24, 330), Radius = 7, Points = 260, Motion = { Kind = "Swing", Axis = "X", Amplitude = 28, Period = 5.5 }, Mount = "Crane" },
		{ Id = "DZ_Billboard", Name = "Demolition Billboard", Position = Vector3.new(0, 22, 480), Radius = 12, Points = 300, Motion = nil },
	},
	LandingZones = {
		{ Id = "DZ_RubblePit", Name = "Rubble Pit", Position = Vector3.new(0, 0, 200), Radius = 16, Points = 180, Color = { 255, 170, 60 } },
		{ Id = "DZ_Dumpster", Name = "Dumpster Drop", Position = Vector3.new(30, 0, 430), Radius = 10, Points = 360, Color = { 235, 70, 60 } },
	},
	MarkerEvery = 50,
	DistanceGoals = { 100, 250, 400 },
	Objectives = {
		{ Id = "DZ_Reach100", Kind = "Distance", Value = 100, Name = "Reach the 100 marker", Points = 80, MinReach = 80 },
		{ Id = "DZ_Props5", Kind = "Props", Value = 5, Name = "Smash 5 props in one run", Points = 140, MinReach = 90 },
		{ Id = "DZ_BrickWall", Kind = "Break", Group = "DZ_Wall1", Name = "Punch through the first brick wall", Points = 160, MinReach = 100 },
		{ Id = "DZ_Combo4", Kind = "Combo", Value = 4, Name = "Chain an x4 destruction combo", Points = 200, MinReach = 100 },
		{ Id = "DZ_Glass", Kind = "Break", Group = "DZ_Glass", Name = "Shatter the glass gallery", Points = 180, MinReach = 170 },
		{ Id = "DZ_RubblePit", Kind = "Land", Name = "Land in the Rubble Pit", Points = 180, MinReach = 190 },
		{ Id = "DZ_Combo8", Kind = "Combo", Value = 8, Name = "Chain an x8 destruction combo", Points = 400, MinReach = 200 },
		{ Id = "DZ_CraneRing", Kind = "Ring", Name = "Fly through the Crane Ring", Points = 250, MinReach = 220 },
		{ Id = "DZ_Barrels", Kind = "Break", Group = "DZ_Barrels", Name = "Topple a barrel stack", Points = 200, MinReach = 250 },
		{ Id = "DZ_Props15", Kind = "Props", Value = 15, Name = "Smash 15 props in one run", Points = 350, MinReach = 250 },
		{ Id = "DZ_WreckingBall", Kind = "Target", Name = "Hit the Wrecking Ball", Points = 260, MinReach = 300 },
		{ Id = "DZ_Reach400", Kind = "Distance", Value = 400, Name = "Reach the 400 marker", Points = 260, MinReach = 370 },
		{ Id = "DZ_Dumpster", Kind = "Land", Name = "Land in the Dumpster Drop", Points = 360, MinReach = 410 },
		{ Id = "DZ_Billboard", Kind = "Target", Name = "Smash the Demolition Billboard", Points = 300, MinReach = 460 },
	},
	Tuning = {
		-- Chained destruction: breaks within Window seconds of each other build a chain;
		-- each break from the 2nd on adds min(chain - 1, MaxStep) * PerStep, capped per run.
		Combo = { Window = 1.2, PerStep = 12, MaxStep = 8, Cap = 500 },
	},
	ReachFactor = 1,
	Ambient = { "DemolitionRumble", "Clank" },
}

CourseConfig.Courses.GravityLab = {
	Id = "GravityLab",
	Origin = Vector3.new(0, 0, 4000),
	Arena = { LaunchZ = 0, FloorY = 0, Length = 480, HalfWidth = 70, Ceiling = 175, KillY = -40, RoofY = 160 },
	PadCount = 4,
	Gravity = {
		-- Scale: fraction of normal gravity felt inside (the server adds an upward force of
		-- mass * g * (1 - Scale) to THAT dummy's parts only; workspace.Gravity never changes).
		-- Flip volumes pull upward until the dummy touches a ceiling flip panel.
		Volumes = {
			{ Id = "GL_LowG1", Name = "Low-G Field A", Center = Vector3.new(0, 45, 150), Size = Vector3.new(130, 90, 90), Scale = 0.3 },
			{ Id = "GL_Flip", Name = "Gravity Flip Column", Center = Vector3.new(0, 85, 250), Size = Vector3.new(60, 150, 40), Scale = -0.5, Flip = true },
			{ Id = "GL_LowG2", Name = "Low-G Field B", Center = Vector3.new(0, 65, 360), Size = Vector3.new(130, 130, 90), Scale = 0.2 },
		},
		FlipOff = 3, -- seconds the flip column ignores a dummy after it touched a flip panel
	},
	-- Bounce fields: touching one launches the dummy upward at Boost studs/s (capped per run).
	Bounce = {
		Boost = 85,
		Max = 6,
		Fields = {
			{ Id = "GL_Bounce1", Position = Vector3.new(-32, 0, 95), Size = Vector3.new(26, 1, 22) },
			{ Id = "GL_Bounce2", Position = Vector3.new(32, 0, 95), Size = Vector3.new(26, 1, 22) },
			{ Id = "GL_Bounce3", Position = Vector3.new(0, 0, 300), Size = Vector3.new(30, 1, 24) },
		},
	},
	-- Floating rings (no posts: they hang in the low-g fields).
	Rings = {
		{ Id = "GL_FloatRing1", Name = "Float Ring", Position = Vector3.new(0, 55, 130), Radius = 12, Color = { 80, 240, 255 }, Floating = true },
		{ Id = "GL_FloatRing2", Name = "Flip Ring", Position = Vector3.new(-14, 110, 250), Radius = 13, Color = { 190, 110, 255 }, Floating = true },
		{ Id = "GL_FloatRing3", Name = "Zero-G Ring", Position = Vector3.new(0, 95, 370), Radius = 15, Color = { 255, 90, 220 }, Floating = true },
	},
	Targets = {
		{ Id = "GL_Orbit", Name = "Orbiting Target", Position = Vector3.new(0, 35, 300), Radius = 7, Points = 240, Motion = { Kind = "Slide", Axis = "X", Amplitude = 40, Period = 6 } },
		{ Id = "GL_Core", Name = "Antimatter Core", Position = Vector3.new(0, 70, 440), Radius = 9, Points = 320, Motion = nil, Mount = "Float" },
	},
	LandingZones = {
		{ Id = "GL_Landing", Name = "Landing Pad", Position = Vector3.new(0, 0, 220), Radius = 14, Points = 200, Color = { 80, 240, 255 } },
		{ Id = "GL_Dock", Name = "Docking Bay", Position = Vector3.new(0, 0, 430), Radius = 12, Points = 380, Color = { 190, 110, 255 } },
	},
	MarkerEvery = 50,
	DistanceGoals = { 100, 250, 400 },
	Objectives = {
		{ Id = "GL_Reach100", Kind = "Distance", Value = 100, Name = "Reach the 100 marker", Points = 80, MinReach = 80 },
		{ Id = "GL_Bounce", Kind = "Bounce", Value = 1, Name = "Use a bounce field", Points = 140, MinReach = 80 },
		{ Id = "GL_FloatRing1", Kind = "Ring", Name = "Float through the Float Ring", Points = 150, MinReach = 100 },
		{ Id = "GL_Bounce3", Kind = "Bounce", Value = 3, Name = "Bounce 3 times in one run", Points = 300, MinReach = 150 },
		{ Id = "GL_Landing", Kind = "Land", Name = "Land on the Landing Pad", Points = 200, MinReach = 200 },
		{ Id = "GL_Flip", Kind = "Flip", Name = "Ride the flip column to the ceiling", Points = 260, MinReach = 230 },
		{ Id = "GL_FloatRing2", Kind = "Ring", Name = "Thread the Flip Ring", Points = 280, MinReach = 230 },
		{ Id = "GL_Orbit", Kind = "Target", Name = "Hit the Orbiting Target", Points = 240, MinReach = 280 },
		{ Id = "GL_Reach300", Kind = "Distance", Value = 300, Name = "Reach the 300 marker", Points = 220, MinReach = 280 },
		{ Id = "GL_FloatRing3", Kind = "Ring", Name = "Fly through the Zero-G Ring", Points = 400, MinReach = 350 },
		{ Id = "GL_Dock", Kind = "Land", Name = "Land in the Docking Bay", Points = 380, MinReach = 410 },
		{ Id = "GL_Core", Kind = "Target", Name = "Hit the Antimatter Core", Points = 320, MinReach = 420 },
	},
	-- Low gravity can keep a dummy drifting: a run ends after MaxFloatTime seconds in a
	-- row inside a low-g / flip volume (paid, not "landed"), and the whole run is shorter.
	Run = { MaxDuration = 18, MaxFloatTime = 7 },
	Tuning = {},
	ReachFactor = 1.3,
	Ambient = { "GravityHum", "ElectricHum" },
}

CourseConfig.ObjectiveById = {}
CourseConfig.RingById, CourseConfig.TargetById, CourseConfig.ZoneById = {}, {}, {}
CourseConfig.CourseOfObjective = {}
for id, course in pairs(CourseConfig.Courses) do
	for _, o in ipairs(course.Objectives) do
		assert(CourseConfig.ObjectiveById[o.Id] == nil, "duplicate objective id " .. o.Id)
		CourseConfig.ObjectiveById[o.Id] = o
		CourseConfig.CourseOfObjective[o.Id] = id
	end
	for _, r in ipairs(course.Rings) do
		CourseConfig.RingById[r.Id] = r
	end
	for _, t in ipairs(course.Targets) do
		CourseConfig.TargetById[t.Id] = t
	end
	for _, z in ipairs(course.LandingZones) do
		CourseConfig.ZoneById[z.Id] = z
	end
end

-- Facilities. Four are built; each new one unlocks through real progression (the
-- requirement, checked and saved by the server) AND a one-time coin price. Players travel
-- between them from the hub's transit gate / the Facilities menu, and back from each
-- facility's HUB TRANSIT kiosk. The Space Launch Facility is the only one still under
-- construction - the gate never pretends otherwise.
CourseConfig.StartFacility = "IndustrialLab"
CourseConfig.Facilities = {
	{ Id = "IndustrialLab", Name = "Industrial Crash Lab", Built = true, Requirement = nil, Cost = 0, Text = "The main test arena." },
	{ Id = "Destruction", Name = "Destruction Testing Zone", Built = true, Requirement = { Stat = "Destroyed", Value = 150 }, Cost = 6000, Text = "Break 150 props.", Blurb = "A demolition yard packed with brick walls, crate towers, glass and a wrecking ball. Chain breaks for combo points." },
	{ Id = "HighAltitude", Name = "High-Altitude Launch Facility", Built = true, Requirement = { Stat = "BestDistance", Value = 400, Machine = "AirCannon" }, Cost = 20000, Text = "Reach 400 studs and own the Air Cannon.", Blurb = "Launch off a cliff into a deep canyon: wind gusts, rope bridges, ledges at three depths and a Free-Fall Bonus." },
	{ Id = "GravityLab", Name = "Experimental Gravity Lab", Built = true, Requirement = { Stat = "Prestige", Value = 1 }, Cost = 30000, Text = "Earn Lab Certification once (prestige).", Blurb = "Low-gravity fields, bounce pads, a gravity-flip column and floating rings." },
	{ Id = "SpaceLaunch", Name = "Space Launch Facility", Built = false, Requirement = { Stat = "Prestige", Value = 3 }, Cost = 0, Text = "Earn Lab Certification three times." },
}
CourseConfig.FacilityById = {}
for _, f in ipairs(CourseConfig.Facilities) do
	CourseConfig.FacilityById[f.Id] = f
end

-- Which facility a world position belongs to (nearest course origin on the ground plane;
-- the facilities are 4,000 studs apart, so this is unambiguous). Returns the course.
function CourseConfig.facilityAt(position)
	local best, bestD = CourseConfig.Courses[CourseConfig.StartFacility], math.huge
	if typeof(position) ~= "Vector3" then
		return best
	end
	for _, course in pairs(CourseConfig.Courses) do
		local dx, dz = position.X - course.Origin.X, position.Z - course.Origin.Z
		local d = dx * dx + dz * dz
		if d < bestD then
			best, bestD = course, d
		end
	end
	return best
end

-- Run limits for a course (GameConfig.Run with the course's overrides).
function CourseConfig.limits(course, base)
	local limits = table.clone(base)
	for k, v in pairs((course and course.Run) or {}) do
		limits[k] = v
	end
	return limits
end

return CourseConfig
