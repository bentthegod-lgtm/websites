# THIN ICE – polish notes

What was checked while rebuilding, and what is left for a Studio pass.

## Done in this build

- **Startup stays fast.**
  - The shore camp is ~1,050 parts, built once (about 0.02–0.04 s in Lune).
  - Each round's lake (now 26 × 50 tiles, ~2,050 parts) is built incrementally, 64 tiles per Heartbeat: 21 frames, worst frame about 3–8 ms in Lune.
  - The harness times both builds and fails if a lake build frame takes over 30 ms.
- **The monster only hears.** It has no line-of-sight code anywhere. Perception is the noise list, plus feeling footsteps through the ice within 7 studs. Standing still always hides you.
- **Snowball lures carry no owner.** The monster goes to the spot, not to the thrower.
- **Whiteouts matter three ways.** For 15–20 s they halve the monster's hearing, make it 30% faster and add chill. Clients close the fog (density 0.82) and quadruple the snow.
- **Readable ice.**
  - Thin ice is darker and see-through, normal ice is tinted by zone, and thick ice is pale with snow patches.
  - Cracks appear at half strength and stress damage darkens the tile.
  - Original holes never refreeze. Breaks refreeze as thin ice after 40 s.
- **Safe rows.**
  - The first two rows off the shore never break.
  - Neither do braziers, snow drifts or core tiles.
  - The shore is safe from the monster.
- **A round always ends:**
  - sled (success, or the sled timer);
  - everyone frozen or lost;
  - time limit;
  - every participant left (abort with no results).
- **Server-authoritative.**
  - Move modes are requests. The server limits them by stamina, sets WalkSpeed and runs a windowed speed check that snaps back teleports.
  - Throws, chips, pick-ups, thaws and deliveries are validated by distance and state.
  - All remotes are rate-limited and type-checked.
- **Data.**
  - Session-locked profiles with migrate-then-reconcile, so junk saved values are clamped.
  - Receipts are idempotent and refused when the profile can't persist live.
  - Studio uses `_Studio` stores.
- **13+ scare.** It is short, has no gore and can be switched off (Settings → Scare effects); Reduced effects also softens it.

## v2: bigger, scarier, polish, sound

- **Bigger.** 26 × 50 tiles (2× the area), a 5th zone, **The Deep Hollow** (Z 360–440): black ice over black water, the half-sunken lighthouse at (0, 400) ringed by eight ice spires. Cores / braziers / drifts / time limits / sled wait retuned (see README). IcePath covers the bigger grid automatically (mean ~2.5 ms per plan in Lune, re-planned at most twice a second). Hard / Nightmare: a smarter Antlered (searches 1.5× / 2× longer) instead of a second one.
- **Scarier.** Fog by distance from shore; dim clouded moon; whiteouts; presence cues (distant calls, breath + crunching steps, heartbeat + frost vignette, chase layer for the hunted player, fog silhouettes); a cracked-ice trail behind the monster (cosmetic, last 24 tiles); a gaunter model with frost breath, ice growths and a client-side head-tilt / listening pose; four ambient scares; a stronger catch scare.
- **Polish.** Eased warmth / stamina bars; a beacon compass while carrying; a big sled countdown that pulses red; sled departure lights and horn; the beacon's sky beam (faint per core, blazing when all are in); chip / deliver / break / splash bursts; snowball impact puffs; breath puffs on everyone in the cold; a warm colour grade by fires; snow scaled by graphics quality; bigger mobile buttons (150 × 66); a UI volume slider; a per-player results table.
- **Sound.** All 34 slots filled from DEAD AIR IDs only (enforced by a unit test), re-pitched and layered. See README → Sound for the full mapping and which are stand-ins.

## Worth a look in Studio

- **Water feel.** Breaking through drops you to the lakebed under a translucent water plane. The server hauls you out after 2.5 s. Check it doesn't look like you're stuck in the floor. Optionally add a splash ParticleEmitter at the hole.
- **Rubber-banding.** The speed check allows `speed × 1.35 × window + 8` studs per 0.5 s window (a flat 8-stud allowance for bursty network updates), and ignores stale positions for up to 0.75 s after any server move (climb-out, thaw, snap-back). Watch for false snaps on high ping.
- **Monster pathing.** It walks the tile grid (A* in `IcePath`, re-planned at most twice a second) around open water, rocks and the wreck. A goal it can't reach counts as reached at the nearest tile; if it makes no progress for 10 s it dives and resurfaces on open ice away from players. Check that its turns read well.
- **Carried shard.** It is welded to the carrier's HumanoidRootPart above the head. Check that it's visible from the carrier's own camera.
- **Lighting.** Night lighting with Atmosphere, Bloom and a cold ColorCorrection. Check Future lighting on low-end phones, and use Settings → Reduced effects for less fog and snow.
- **Audio.** Every slot reuses a DEAD AIR ID. The weakest stand-ins (replace first): Splash (metal-drop), BrazierCrackle (a pitched pour, not fire), Horn (a pitched alarm), Step / MonsterStep (pitched "Land"), the wind (a pitched ventilation loop). Check nothing is too loud at 100% sliders.
- **Darkness.** The Deep Hollow should feel deadly but stay readable: tune `GameConfig.Lake.FogFar`, `Lighting.Brightness` (0.7) and the client grade if testers can't read thin ice there.
- **Head animation.** The client re-poses the Antlered's head every frame on top of the server's body moves; check it doesn't jitter on high ping.

## Ideas for later

- A spectator camera for lost players, cycling through teammates.
- Ice-skate patches: frictionless thick ice that's fast but very loud to stop on.
- A second monster variant for Nightmare: a "Listener" that never moves but calls the Antlered.
- Seasonal outfits and a lantern trail effect.
