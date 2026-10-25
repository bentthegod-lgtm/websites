# MAGNET MAYHEM

A multiplayer Roblox simulator about magnets:

* switch your magnet on and scrap vibrates, lifts and flies at you, spinning;
* it piles up in a growing scrap tornado around your head;
* you sell it at a giant shredder and upgrade;
* you pull ever-heavier junk, up to a Prototype Magnetic Reactor and The Golden Taxi.

Everything (map, models, magnet, UI, effects) is built from code in this Rojo project.

> **Status, honestly:** every check that can run here passes: lint, compile, 33 unit tests and
> a 28-check headless harness that runs the real modules on the built place. **Nobody has played
> it in Roblox Studio yet.** No Studio or Roblox client is available in this environment, so
> how it feels to play, the physics, the camera and the real devices are unverified. See
> [What still needs work](#what-still-needs-work).

## Build and run

```bash
cd magnet-mayhem
rojo build -o build/MagnetMayhem.rbxlx      # open this file in Roblox Studio and press Play
# or live-sync into an open place:
rojo serve                                  # then Connect from the Rojo Studio plugin
```

## How to play

1. **Hold Left Mouse** (or the MAGNET button) near scrap. It's outlined yellow if you can pull
   it and red if it's too heavy.
2. Your **pile** grows above your head. The bar at the bottom shows capacity.
3. Walk onto the yellow **sell pad** at the shredder (or press E at its console) to sell.
4. Open **UPGRADES** at the station (or with the HUD button or M) and spend your coins. Buy the
   next **magnet tier** for big jumps in strength, range and capacity.
5. Unlock **Metro Wreck** at the east gate (strength 6 + 15K coins) for city scrap.
6. Use the **magnetic pulse** (R) for a big grab on a cooldown. Watch for **Magnetic Storms**.
7. Late game: **prestige** for permanent Magnet Cores.

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Magnet (hold) | Left mouse | R2 | MAGNET (hold) |
| Magnetic pulse | R | R1 | PULSE |
| Sprint | Left Shift (hold) | L3 (toggle) | SPRINT (toggle) |
| Interact (sell, upgrades, gate) | E | X | tap prompt |
| Menu | M | D-pad up | menu buttons |
| Camera mode (3rd / 1st person) | V | D-pad down | Settings |
| Player list | Tab (Roblox default) | | |

Shift lock is turned off (`StarterPlayer.EnableMouseLockOption = false`) so Shift can sprint.
Settings > Controls lists everything in game.

## Phase reports

### Phase 1: Inspect and plan

* **What was there:** the repository held five other finished games and no MAGNET MAYHEM
  project, so this is a new folder. The infrastructure is reused from those games: Rojo layout,
  selene std (`roblox_min.yml`), the Lune test runner and harness approach, and Sprout Valley's
  reviewed DataStore session lock.
* **Tools:** Rojo, Lune and Selene, plus Chromium and three.js for preview renders.
  Not available: Roblox Studio, a Roblox client and Blender, so there are no meshes; see
  POLISH.md.

### Phase 2: Playable core

* **Rustyard map:** `src/server/World/WorldBuilder.lua`.
* **Third-person camera:** `CameraController` gives a shoulder offset and a first-person toggle.
* **Magnet:**
  * `MagnetService` (server) claims scrap, times the flight and awards it once.
  * `MagnetController` (client) shows the vibrate, lift, accelerate and spin flight, plus
    outlines, glow and hum.
  * `Attraction` is the shared, pure maths.
* **Scrap:** `ScrapService` is the registry, with a spatial grid, weighted spawns and atomic
  claims. `ScrapModels` builds 26 procedural models.
* **Pile:** `PileLayout` places pieces in stable slots, drawn with one `BulkMoveTo` per frame.
  There is an overflow cluster beyond the visual budget.
* **Selling and coins:** `EconomyService` handles the pad, the prompt and the button, and pays
  once.
* **HUD:** `HudController`.

### Phase 3: Progression

* **Upgrades:** 12 of them in four categories (Magnet, Capacity, Movement, Economy), plus 6
  magnet tiers that visibly change the rig (more coils, bigger core, fins, rings, halo).
  `UpgradeService`, `EconomyConfig`, `MagnetConfig`, `MagnetModel`.
* **Heavy objects:** they need magnet strength. Heavy-Lift Clamps allow more heavy pulls at once
  with less wind-up.
* **Zones:** `ZoneService` handles zone unlocks: the requirements, the gate barrier (non-solid
  only for players who unlocked it), and a server-side push-back if someone is inside a locked
  zone.
* **Saving:** `DataService` covers persistence (details under *Saving*).

### Phase 4: Presentation

* **Lighting:** Rustyard has warm late-afternoon light (Atmosphere, colour grade, restrained
  bloom, sun rays). Metro Wreck is at urban dusk. `LightingController` blends between them.
* **Effects and sound:**
  * **Shredder:** rollers, pistons, belt slats, warning lights, sparks and smoke.
  * **Selling:** a staged animation flies the pile into the hopper.
  * **Rewards:** rare-discovery cards and grouped value popups.
* **Audio:** `AudioController` has five volume groups, per-cue throttling and a shared budget for
  floods of small clinks. Ambient emitters play at random intervals, and music changes by zone
  (once you add tracks).

### Phase 5: Content

* **Scrap Codex:** silhouettes and "???" until discovered, with count, best value and zone.
* **Progress:** 14 achievements, 12 starter quests, an interactive 6-step tutorial driven by
  real events (skippable, replayable, saved), and daily objectives (3 per UTC day, deterministic,
  scaled by tier). `QuestService`, `QuestConfig`, `Progress`.
* **Metro Wreck:** a real second zone with 10 objects, including the legendary Golden Taxi.
* **Magnetic Storm:** `EventService` runs a timed server event.

### Phase 6: Multiplayer and polish

* **Other players' piles:** drawn from player attributes with a smaller budget, updated at 15 Hz
  and hidden beyond 220 studs.
* **Leaderboards:** two global boards (total scrap value and rare discoveries).
* **Storms:** announcements and storm rewards based on participation.
* **Controls:** gamepad and touch.
* **Settings:** camera, sensitivity, 5 volumes, reduced effects, particle quality, cosmetics,
  codes, tutorial replay, controls.
* **Performance:** `PerformanceConfig` holds the budgets.
* **Analytics:** onboarding funnel events (`Analytics`, pcall'd).

### Phase 7: QA

| Check | Result |
|---|---|
| `selene src` | `0 errors / 0 warnings / 0 parse errors` |
| `lune run tests/compile` | `compiled 47 files, 0 failures` |
| `lune run tests/run` | `33 passed, 0 failed` |
| `rojo build -o build/MagnetMayhem.rbxlx` | `Built project to MagnetMayhem.rbxlx` |
| `lune run tests/harness build/MagnetMayhem.rbxlx` | `harness: 29 passed, 0 failed` |

* **Bugs found by tests and fixed:**
  * The first claim waited about 0.2 s for the claim budget, so it felt laggy. The first grab
    is now instant.
  * Maxed Heavy-Lift Clamps made a safe arrive faster than a toolbox. Heavy wind-ups now never
    go below medium ones.
  * Strength upgrades alone reached Metro Wreck, which made magnet tiers pointless. The
    strength step was reduced.
* **Bugs found in the preview renders and fixed:**
  * Metro building windows faced away from the streets.
  * The upgrade station and leaderboards faced away from the spawn.
  * The skyline floated over the void.

## Systems in detail

**Magnet flow.** The client sends only `Magnet(on)` and `Pulse()`. Every 0.1 s the server:

1. finishes due flights, validating that the player is still there, alive, within
   range × 2.2 and in an unlocked zone, then `ScrapService.consume()`. That only succeeds once,
   so there's never a double award;
2. claims new objects from a spatial query, limited by:
   * the claims-per-second budget;
   * objects in flight (Multi-Grip);
   * heavy slots (Clamps);
   * the remaining capacity;
   * strength and zone unlocks;
3. broadcasts one Attract, Collected and Released batch to everyone.

Values come from config on the server (lucky finds and storm multipliers included). Leaving,
dying, prestiging or walking away releases in-flight scrap instead of awarding it.

**Selling.** The server checks you're at the shredder. Then the pile value × your multiplier is
paid, the pile is cleared in the same step, and a 1.2 s cooldown applies. The pad is checked by
a server loop, not `Touched`, so repeated touches can't pay twice.

**Security.** Every remote is type-checked and rate-limited. Prices, values, rarities, ranges and
rewards come only from server config. Saved data is validated on load: upgrade levels are
clamped, unknown keys dropped, and tier and coins clamped. Rewards (quests, achievements,
dailies, codes, receipts) are marked as granted before they are paid.

**Performance budgets** (`PerformanceConfig`):

* 300 active scrap objects in total: Rustyard 150, Metro 120;
* 42 detailed pile pieces for you and 14 for each other player;
* 70 animated flights at once (extra ones snap);
* particle multipliers, at most 6 popups a second, and a shared audio budget.

## Saving

**What's saved:**

* coins and earnings;
* upgrades, tier and zones;
* the carried pile, so you don't lose it on leave;
* the codex, achievements, quest index, daily state and tutorial;
* prestige;
* settings, cosmetics, codes and receipts.

**How it's saved:**

* **Session lock.** Data loads with `UpdateAsync`, taking a session lock. A fresh lock held by
  another server makes the load wait and retry; a stale lock (older than 3 autosaves) is taken
  over.
* **Fallback.** If loading fails, an in-memory profile is used, the player is told, purchases
  wait (`NotProcessedYet`) and nothing is overwritten.
* **When.** Autosave runs every 60 s, plus on leave (3 retries) and on `BindToClose` (in
  parallel).
* **Studio.** Studio uses separate `_Studio` stores, so free test grants never reach live data.

**Save/load test plan** (needs a published place with *Game Settings → Security → Enable Studio
Access to API Services* on):

1. Join and collect scrap. Sell, then buy two upgrades and the Copper Coil. Leave the pile
   half full and stop the test.
2. Start again: the coins, upgrades, tier and half pile should all be back, with the tutorial
   step unchanged.
3. Unlock Metro Wreck, discover a new codex entry, finish a daily, and redeem `MAGNET`. Stop
   the test and start again: all of it should be kept, and `MAGNET` should now be refused.
4. Change volumes and camera mode, then rejoin: the settings should be kept.
5. Use two Studio clients (Test → Clients and Servers) with different accounts and check that
   each has its own data.
6. Turn API access off and play: the "not saving" warning should show and nothing should error.

## Robux shop (optional, cosmetic only)

| Item | Kind | Shown price | Config |
|---|---|---|---|
| Chrome Magnet | Game Pass | R$ 99 | `ShopConfig.Passes` ChromeSkin |
| Gold Rush Magnet | Game Pass | R$ 199 | GoldSkin |
| Spark Trail | Game Pass | R$ 79 | SparkTrail |
| Neon Pulse Magnet | Developer Product (permanent) | R$ 149 | NeonSkin |
| Plasma Trail | Developer Product (permanent) | R$ 99 | PlasmaTrail |

* **No pay-to-win:** nothing in the shop changes stats or progression.
* **Free cosmetics:** Hazard Stripes (from the first prestige) and Rust Dust (from 1,000
  collected).
* **Setup:** in Creator Hub → Monetization, create each Pass and Product. Paste the IDs into
  `ShopConfig.lua` and set the same prices there.
* **Until an ID is set:** Studio grants the item free (for testing) and live games say "not
  available yet".
* **Purchases:** handled through `ProcessReceipt`. The receipt is saved before
  `PurchaseGranted` is returned, so a purchase is never granted twice.

## IDs and assets you must provide

* **Game Pass and Developer Product IDs:** see above. All are currently `0`.
* **Audio:** some slots are empty and are silently skipped until you add sounds you have
  rights to:
  * `MagnetCharge`, `ChainRattle`, `QuestDone`, `LevelUp`, `Birds`;
  * music: `MusicRustyard`, `MusicMetro`.

  The filled ones reuse Creator Store IDs already used in DEAD AIR, and the unit test checks
  that every ID comes from that list. Listen to them in Studio and swap any that don't fit.
* **No badge IDs are used.** Achievements are in-game only.
* **Experience icon and thumbnails:** prompts are in POLISH.md.
* **Maturity questionnaire:** there is no violence, blood or fear. It's a cartoon scrapyard,
  so answer "None" for everything; the label should be Minimal (all ages).

## Testing checklist (run in Studio; not done here)

**Core**
- [ ] The magnet pulls nearby scrap, with no lag on the first grab.
- [ ] Out-of-range scrap is never pulled.
- [ ] Each object is rewarded once.
- [ ] Heavy objects need the right strength; red outlines and a notice appear when they're too
  heavy.
- [ ] The pile stays above your head, doesn't block the camera or trap you, and never collides.
- [ ] Selling clears the pile and pays once.
- [ ] Standing on the pad doesn't pay repeatedly.
- [ ] Each upgrade changes how the magnet feels.

**Progression**
- [ ] Coins, upgrades, tier, zones, the pile and the codex all save.
- [ ] Quests and dailies don't pay twice.
- [ ] Prestige resets only what its dialog lists.

**Multiplayer** (2–4 clients)
- [ ] Two players can collect different objects at the same time.
- [ ] Two players racing for one object: only one gets it.
- [ ] Other players' piles look right and don't lag.
- [ ] A storm rewards only real participants.
- [ ] The gate opens only for players who unlocked it.

**UI**
- [ ] The layout works on PC, phone (Device Emulator) and gamepad.
- [ ] Buttons don't overlap the Roblox jump button or top bar.
- [ ] Values are readable, menus close, volume sliders work, and the camera toggle works.

**Reliability**
- [ ] Leaving mid-pull or mid-sale causes no errors and no lost pile.
- [ ] Data-load failure shows the warning.
- [ ] Spamming remotes does nothing harmful.
- [ ] Buying something unaffordable is refused.
- [ ] A rare object that despawns mid-pull is handled cleanly.

## What still needs work

* **A real Studio play-test.** This covers:
  * how the magnet feels;
  * camera framing with a big pile;
  * the welded rig's position on R15 and R6 characters;
  * mobile layout;
  * the cost of drawing many players' piles.
* **Balance.** First-pass numbers come from config maths (there's a unit test that the first
  sale buys the first upgrade); real players are needed to tune the curve.
* **Animations.** There are no custom character animations (activation pose, heavy-pull
  recoil). The camera punch and the procedural machine animation stand in for them.
* **Zones.** Only Rustyard and Metro Wreck are built. Industrial Core, Military Salvage and
  Orbital Graveyard are listed as coming soon, on purpose, rather than shipped as empty maps.
* **Personal records and friend comparisons.** These are limited to the codex "best value"
  and the global boards.

## Project layout

```
src/shared/            configs + pure logic (ReplicatedStorage.MagnetMayhem)
  Config/              Game, Scrap, Magnet, Economy, Zone, Quest, Event, Shop, Performance, Audio
  Attraction.lua       pull timing + flight curve (pure, tested)
  Economy.lua          prices, stats, sale values, prestige (pure, tested)
  PileLayout.lua       stable pile slots (pure, tested)
  Progress.lua         quest / daily helpers (pure, tested)
  ScrapModels.lua      procedural scrap models (swap for MeshParts later)
  MagnetModel.lua      the wearable magnet rig per tier / skin
src/server/World/      WorldBuilder (Rustyard, gate, Metro Wreck)
src/server/Services/   Data, Upgrade, Scrap, Magnet, Economy, Zone, Quest, Event, Shop,
                       Player, Leaderboard, Analytics
src/client/Controllers/ ClientState, Ui, Audio, Camera, Input, Magnet, Hud, Effects,
                       Lighting, Tutorial, Menu
tests/                 unit specs, loader, compile check, headless harness
tools/                 preview exporter + three.js renderer
```

Preview renders (rough three.js approximations, not Roblox screenshots):

```bash
lune run tools/export_preview build/MagnetMayhem.rbxlx build/preview.json
node tools/render_preview.mjs build/preview.json build/
```
