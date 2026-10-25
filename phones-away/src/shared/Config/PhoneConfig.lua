--[[
	The phone's answer scanner (the cheat) and its server-side limits.

	Flow (all timed by the SERVER):
	  1. phone fully out -> SNAP: AimSeconds of holding the camera over your test,
	  2. shutter: a click (noise) and a screen flash (glow) the teacher can notice,
	  3. the scanner app "processes" (Scanner upgrade seconds); the phone must STAY OUT,
	     hiding it cancels the scan,
	  4. the server reveals N correct answers (Phone upgrade) to that player only.
	The client sends only Phone(up/down), PhoneAction("snap" | "watch" | "peek") and test
	answers. Nothing else can make the server send an answer.
]]

return {
	RaiseSeconds = 0.25, -- phone coming out of the desk (visible, not usable yet)

	Snap = {
		AimSeconds = 0.6, -- lining up the camera over the paper
		ShutterNoise = 0.9, -- noise units (x Silent Shutter upgrade)
		FlashSeconds = 0.3,
		FlashMultiplier = 2.5, -- glow x this while the screenshot flashes (x Dim Screen)
		FlashInstant = 0.22, -- instant suspicion if she SEES the flash
		ScanTapNoise = 0.15, -- the app "beeps" now and then while processing
	},

	Watch = {
		Visibility = 0.3, -- a wrist glance is much less visible than a phone
		Noise = 0.1,
	},

	-- Hard plausibility limit on phone actions of any kind.
	ActionsPerSecond = 6,
}
