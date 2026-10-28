--[[
	CourseConfig - the Industrial Crash Lab course layout (shared by the world builder and
	the server's objective checks) and the facility progression framework.

	Coordinates: the launch line is Z = 0, the course runs toward +Z, X = 0 is the centre
	line. Launch pads sit on the line; each pad aims down the course (players can nudge
	the aim left / right).
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
	Panel = { Name = "Breakaway Panel", Strength = 2, Points = 80, BreakSpeed = 55, Color = { 120, 190, 230 }, Material = "Glass", Debris = 5, Sound = "PanelShatter" },
	Tower = { Name = "Test Structure", Strength = 1, Points = 30, BreakSpeed = 30, Color = { 230, 120, 50 }, Material = "Plastic", Debris = 3, Sound = "BoxCrunch" },
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
CourseConfig.ObjectiveById = {}
for _, o in ipairs(CourseConfig.Objectives) do
	CourseConfig.ObjectiveById[o.Id] = o
end
CourseConfig.RingById, CourseConfig.TargetById, CourseConfig.ZoneById = {}, {}, {}
for _, r in ipairs(CourseConfig.Rings) do
	CourseConfig.RingById[r.Id] = r
end
for _, t in ipairs(CourseConfig.Targets) do
	CourseConfig.TargetById[t.Id] = t
end
for _, z in ipairs(CourseConfig.LandingZones) do
	CourseConfig.ZoneById[z.Id] = z
end

-- Facilities. Only the Industrial Crash Lab is built in this release. The others unlock
-- through real progression (checked and saved by the server) and show as
-- "under construction" until their courses ship - the gate never pretends otherwise.
CourseConfig.StartFacility = "IndustrialLab"
CourseConfig.Facilities = {
	{ Id = "IndustrialLab", Name = "Industrial Crash Lab", Built = true, Requirement = nil, Text = "The main test arena." },
	{ Id = "HighAltitude", Name = "High-Altitude Launch Facility", Built = false, Requirement = { Stat = "BestDistance", Value = 400, Machine = "AirCannon" }, Text = "Reach 400 studs and own the Air Cannon." },
	{ Id = "Destruction", Name = "Destruction Testing Zone", Built = false, Requirement = { Stat = "Destroyed", Value = 150 }, Text = "Break 150 props." },
	{ Id = "GravityLab", Name = "Experimental Gravity Lab", Built = false, Requirement = { Stat = "Prestige", Value = 1 }, Text = "Earn Lab Certification once (prestige)." },
	{ Id = "SpaceLaunch", Name = "Space Launch Facility", Built = false, Requirement = { Stat = "Prestige", Value = 3 }, Text = "Earn Lab Certification three times." },
}
CourseConfig.FacilityById = {}
for _, f in ipairs(CourseConfig.Facilities) do
	CourseConfig.FacilityById[f.Id] = f
end

return CourseConfig
