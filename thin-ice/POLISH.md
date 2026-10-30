# THIN ICE – polish notes

What was checked while rebuilding, and what is left for a Studio pass.

## Done in this build

- **Startup stays fast.**
  - The shore camp is ~880 parts, built once (about 0.02 s in Lune).
  - Each round's lake is built incrementally, 48 tiles per Heartbeat. A Normal lake takes 11 frames with a worst frame of about 3–6 ms in Lune.
  - The harness times both builds and fails if either gets slow.
- **The monster only hears.** It has no line-of-sight code anywhere. Perception is the noise list, plus feeling footsteps through the ice within 7 studs. Standing still always hides you.
- **Snowball lures carry no owner.** The monster goes to the spot, not to the thrower.
- **Gusts matter twice.** They halve the monster's hearing and add chill. Clients thicken the fog and snow.
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
- **13+ scare.** It is short, has no gore and can be switched off (Settings → Scare effects).

## Worth a look in Studio

- **Water feel.** Breaking through drops you to the lakebed under a translucent water plane. The server hauls you out after 2.5 s. Check it doesn't look like you're stuck in the floor. Optionally add a splash ParticleEmitter at the hole.
- **Rubber-banding.** The speed check allows `speed × 1.35 + 6` studs/s over 0.5 s windows. Watch for false snaps on high ping.
- **Monster pathing.** It walks straight to its goal over holes and through rocks (it's a monster). If that reads badly, add simple steering around rock tiles.
- **Carried shard.** It is welded to the carrier's HumanoidRootPart above the head. Check that it's visible from the carrier's own camera.
- **Lighting.** Night lighting with Atmosphere, Bloom and a cold ColorCorrection. Check Future lighting on low-end phones, and use Settings → Reduced effects for less fog and snow.
- **Audio.** The 18 sound IDs are reused from DEAD AIR. Re-pitch or replace any that don't fit the cold setting. Wind and music slots are empty.

## Ideas for later

- A spectator camera for lost players, cycling through teammates.
- Ice-skate patches: frictionless thick ice that's fast but very loud to stop on.
- A second monster variant for Nightmare: a "Listener" that never moves but calls the Antlered.
- Seasonal outfits and a lantern trail effect.
