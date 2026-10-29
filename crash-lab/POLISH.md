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

### New facilities (`src/server/World/Facilities/*`)

Keep the part names / attributes the server reads (`CL_Prop`, `CL_Key`, `CL_Floor`,
`CL_Target`, `CL_Bounce`, `CL_Flip`) and the prop sizes, or update `CourseConfig` to match.

9. **Destruction Testing Zone** (`Destruction.lua`):
   - brick block (7.8×3.9×3), shipping crate (5×5×5), glass pane (7.6×10×0.6) and oil
     drum (4×3×3, upright): an intact mesh plus 3–4 chunk meshes each (the chunks replace
     the pooled fragment parts);
   - wrecking-ball crane (tower, jib, cab, cable + 14-stud ball), shipping containers,
     excavator, dumpster, rubble heaps, floodlight towers.
10. **High-Altitude Launch Facility** (`HighAltitude.lua`):
    - the mesa, canyon walls and pillars as sculpted rock meshes (keep their sizes as
      collision boxes, or use mesh collision fidelity "Box");
    - rope bridges (planks, ropes, hangers: the plank segments are the `HA_Bridge*`
      impact objects), ledges, the cliff-face target arm, cable-car target, windsock,
      pines, mountains.
11. **Experimental Gravity Lab** (`GravityLab.lua`):
    - wall panels with neon trim, ribs, the roof, consoles, coolant tanks;
    - gravity-field emitters, bounce pads (keep `CL_Bounce`), ceiling flip panels (keep
      `CL_Flip`), holo-emitters under the floating rings, the Antimatter Core target.

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
- `Boing`: comedic bounce for crash pads.
- `BounceField` (Gravity Lab): a sci-fi spring / zap when a bounce field fires.
- `TransitWhoosh` (UI): plays on arriving at a facility.
- `MusicLobby` / `MusicRun`: licensed, upbeat, quieter than effects.

Facility slots filled with pitched DEAD AIR reuses (placeholders):
- Destruction Zone: `BrickCrumble` (box crunch x0.55), `BarrelClang` (metal impact x0.7),
  ambient `DemolitionRumble` (machinery x0.7) + `Clank`. Wanted: brick crumble, drum
  clang, glass shatter, wrecking-ball thud, distant diesel engines.
- High-Altitude: ambient `CanyonWind` (ventilation x0.55), `WindGust` (ventilation x1.7).
  Wanted: a real mountain wind loop and short gust whooshes.
- Gravity Lab: ambient `GravityHum` (electric hum x1.5) + `ElectricHum`, `GravityShift`
  (air pressure x2) when a dummy enters a field or hits a flip panel. Wanted: a sci-fi
  field hum and a "gravity drop" swell.

Filled in the polish pass with pitched DEAD AIR reuses (placeholders, replace when you can):
- `AirHiss` and `Whoosh`: the ventilation loop pitched up (x2.4 / x2), cut short.
- `SoftLanding`: the light impact pitched down (x0.6).
- `Achievement`: the objective chime pitched up (x1.3).
- `ChallengeDone`: the purchase chime pitched up (x1.2).

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
| Facility prices / requirements | `CourseConfig.Facilities` | Destruction 6k + 150 props; High-Altitude 20k + 400 st + Air Cannon; Gravity Lab 30k + 1 prestige |
| Wind | `CourseConfig.Courses.HighAltitude.Wind` | every 0.7 s, 12 st/s per gust, 36 st/s per run |
| Free-Fall Bonus | `...HighAltitude.Tuning.FreeFall` | 0.8 pts / stud, 15–240 studs |
| Destruction combo | `...Destruction.Tuning.Combo` | 1.2 s window, 12 pts / step (max 8 steps), cap 500 |
| Low gravity | `...GravityLab.Gravity.Volumes` / `Run` | scale 0.3 / 0.2, flip -0.5; drift limit 7 s; 18 s runs |
| Bounce fields | `...GravityLab.Bounce` | 85 st/s, 6 per run |
