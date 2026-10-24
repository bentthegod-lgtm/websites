--[[
	Audio slots. NO asset IDs are invented here.

	The rbxassetid:// entries are reused from the DEAD AIR project, where they were found in
	Roblox's licensed partner libraries (free to use in experiences). Every slot with
	Id = "" is skipped by the code until you add a sound you own or that the Creator Store
	marks as usable (e.g. "rbxassetid://123456789"). See README -> Audio.
]]

return {
	Harvest = { Id = "rbxassetid://9116173869", Volume = 0.5, Pitch = 1.25 }, -- reused "Pickup"
	UiClick = { Id = "rbxassetid://9113880475", Volume = 0.35, Pitch = 1.3 }, -- reused "TerminalBeep"
	Sell = { Id = "rbxassetid://9116612715", Volume = 0.6, Pitch = 1.4 }, -- reused "CanClatter" (coin jingle stand-in)
	Plant = { Id = "rbxassetid://9116173869", Volume = 0.35, Pitch = 0.8 }, -- reused "Pickup", pitched down
	Gate = { Id = "rbxassetid://9120839599", Volume = 0.4 }, -- reused "DoorOpen"
	Thunder = { Id = "rbxassetid://9116537007", Volume = 0.8, Pitch = 0.35 }, -- reused "MetalDrop", pitched way down

	-- Empty slots: add your own.
	Music = { Id = "", Volume = 0.25, Looped = true },
	RainLoop = { Id = "", Volume = 0.35, Looped = true },
	WindLoop = { Id = "", Volume = 0.25, Looped = true },
	Restock = { Id = "", Volume = 0.6 },
	RareAnnounce = { Id = "", Volume = 0.7 },
	WeatherStart = { Id = "", Volume = 0.6 },
	Purchase = { Id = "", Volume = 0.6 },
	Mutation = { Id = "", Volume = 0.6 },
	Daily = { Id = "", Volume = 0.6 },
	Water = { Id = "", Volume = 0.5 },
	Expand = { Id = "", Volume = 0.6 },
}
