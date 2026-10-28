# CRASH LAB: polish list (for the Claude on your PC)

Every model is built from parts in code. Swap in meshes where they clearly improve the
look. Keep part names and attributes, because the server checks `CL_Floor`, `CL_Key`,
`CL_Prop`, `CL_Target` and `CL_Soft`, and the client animates parts by name.

## Blender: mesh swaps (priority order)

1. **Crash-test dummy** (`src/shared/DummyModel.lua`). Make 11 MeshParts with the same
   names and sizes: Root 2×1.7×1.1, Head about 1.35, arms 0.6×1.2, legs 0.75×1.35. Add
   moulded joints, the classic black/yellow quadrant markers, a visor slot and rounded
   limbs. Keep the attachment positions (joint centres) so the BallSocket rig still lines
   up. Stay low-poly (under 600 tris per part).
2. **Standard Launcher** (`MachineModels.standard`): catapult frame, axle, an `Arm` model
   (pivot at the axle) with a cup. The arm rotates about its pivot's X axis.
3. **Spring Cannon:** a `Barrel` model with rails and hoops, 7 `Coil` rings and a `Piston`.
   Coils and piston slide along the barrel's Z axis.
4. **Experimental Air Cannon:** a `Barrel` model (tube, breech, bands, muzzle), a `Tank`,
   pipes, a `Gauge` with a `Needle`, and a `Beacon` with a PointLight.
5. **Destructibles** (`FacilityBuilder` props). Each needs an intact mesh plus 3–5 debris
   chunk meshes:
   - cardboard box (4×4×4);
   - plastic pin (2.6×7×2.6);
   - wooden fence (20×6×1.2);
   - glass panel (12×14×1);
   - tower block (3×3×3).
6. **Targets:** swinging target board, sliding target on a carriage, the gong (13 radius)
   with its frame.
7. **Lobby landmarks:** the crashed-car exhibit, the CRASH LAB sign letters as a mesh,
   upgrade-station and Dummy Locker kiosks.
8. **Arena dressing:** test fans (hub + 4 blades: keep `FanHub` / `FanBlade` names and the
   `Fan` attribute), light towers, gantries, net posts.

## ComfyUI prompts

- **Game icon (512×512):** "cartoon crash test dummy flying out of a yellow catapult,
  comic motion lines, bright yellow and black hazard stripes background, bold 3D game icon
  style, clean shading, no text"
- **Thumbnail 1 (1920×1080):** "wide shot of a colourful industrial crash test arena,
  yellow-black hazard stripes, a crash test dummy tumbling through a neon ring, cardboard
  boxes exploding, glass panel shattering, sunny daylight, Roblox-style 3D render, playful"
- **Thumbnail 2:** "three launch machines side by side - catapult, spring cannon,
  experimental air cannon with warning beacon - on a launch deck, players cheering,
  stylised 3D, high contrast"
- **Thumbnail 3:** "close-up of a crash test dummy smacking into a giant gong, comic impact
  burst, scoreboard showing a new record, bright cartoon style"
- **Shop / UI icons (256×256, transparent background):** neon glowing crash dummy;
  fireworks burst; rainbow trail swoosh; coin stack with a hazard stripe; each upgrade
  (speedometer, weight plate, stopwatch, protractor, crosshair, shield, spinning arrows,
  star, x2 badge, clipboard).

## Sound slots to fill (`src/shared/Config/AudioAssets.lua`)

Empty (silent until filled):
- `AirHiss`: rising pneumatic hiss.
- `Whoosh`: flight whoosh.
- `SoftLanding`: cushion thump.
- `Boing`: comedic bounce.
- `Achievement` / `ChallengeDone`: short jingles.
- `MusicLobby` / `MusicRun`: licensed, upbeat, quieter than effects.

Reused from DEAD AIR (some are dark, so consider brighter replacements):
- `StandardPrep`, `StandardRelease`, `SpringCompress`, `SpringSnap`, `AirPressure`,
  `AirBlast`;
- impacts, prop sounds, `GongHit`, ambient.

Only use audio you own or that the Creator Store marks as usable, and update the
allow-list in `tests/config.spec.luau` when you add IDs.

## Balance values to tune after play-tests

| Value | Where | Now |
|---|---|---|
| Machine speeds | `MachineConfig` BaseSpeed | 112 / 150 / 205 st/s |
| Max launch speed | `ScoringConfig.MaxLaunchSpeed` | 310 |
| Points per stud / height | `ScoringConfig` | 1 / 0.5 |
| Impact tiers + caps | `ScoringConfig.Impact` | 22/55/100/160 st/s; 3 per object; 10 + 3/lvl |
| Coins per point | `ScoringConfig.CoinsPerPoint` | 0.5 (min 8) |
| Upgrade costs | `UpgradeConfig.List` | Power 60 × 1.55^n … |
| Machine unlocks | `MachineConfig` Cost / Requirement | 2.5k + 140 st; 25k + Payload 1 + 300 st |
| Settle / stuck / time limit | `GameConfig.Run` | 4 st/s for 1.4 s / 4 s / 22 s |
| Prop break speeds and strength | `CourseConfig.DestructibleKinds` | |
| Prestige score | `Progress.PrestigeScore` | 3,000 |
