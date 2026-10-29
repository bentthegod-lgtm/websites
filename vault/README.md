# VAULT

A Roblox collect-and-deposit game set in an underground bank vault. Every depth is a **deep pool of treasure**: players walk down from the rim into a basin 42 studs deep filled with a sea of loot, pick it up one item at a time, carry it as a visible stack that grows on their character, and feed it into a deposit machine for Cash. Cash buys upgrades and unlocks deeper depths. At the bottom of each pool a massive vault door opens onto a tunnel that leads down to the next, deeper pool. There are seven pools, 90 studs apart, also joined by one elevator for quick travel.

> **Honest status.** This is a Rojo project. It has never been opened or played in Roblox Studio.
>
> What *was* verified headlessly, in Lune:
> - every file lints and compiles;
> - 38 unit tests pass;
> - 28 harness checks pass. They run the real server and client modules against Lune's Roblox instance model, with stubbed engine services and a fake clock.
>
> Persistence, session locking, receipts and multiplayer (two players, races, leaving) have been exercised **only in that harness**. Lune has no physics and no renderer, so characters are moved by the harness. The world was checked visually with three.js renders of the exported parts (`build/preview-*.png`). Those renders are not Roblox's renderer.
>
> Before publishing, follow the Studio test plan below.

## Quick start

```bash
cd vault
rojo build -o build/Vault.rbxlx     # then open build/Vault.rbxlx in Roblox Studio and press Play
# or live-sync: rojo serve          (then Connect in the Rojo Studio plugin)
```

**Opening it in Studio:**
1. Open `build/Vault.rbxlx`.
2. **To test saving:** go to Game Settings → Security and turn on **Enable Studio Access to API Services**. Without it the game runs fine, but it tells you that saving is off.
3. Press **Play** (solo), or use **Test → Clients and Servers** with 2 players to check multiplayer.
4. Studio uses separate `_Studio` DataStores and OrderedDataStores, so test saves never touch live data.

**Controls:**

| Action | Keyboard / gamepad | Mobile |
|---|---|---|
| Pick up (hold to keep collecting) | **E** / **ButtonX** | **PICKUP** button |
| Deposit, floor select, upgrades | **E** at the machine prompt | Tap the prompt |
| Menus | U upgrades, G depths, B book, J achievements, L leaderboards, K stats, P shop, O settings | Menu buttons on the left |

## How it plays

1. **Collect.** Walk up to loot. The nearest item in reach is outlined, with a billboard showing its value. Press E to pick it up.
   - The server checks the claim: the item exists, it is on your depth, you are in reach (with latency slack), the pickup cooldown has passed and you have capacity.
   - If two players reach the same item on the same frame, exactly one gets it.
2. **Carry.** Your stack grows on your character and changes arrangement as it grows:

   | Items | Arrangement |
   |---|---|
   | 1–3 | In the hand |
   | 4–12 | A bundle at the chest |
   | 13–36 | A wide stack in both arms |
   | 37–90 | A large block with interlocked bullion |
   | 91+ | A strapped crate overhead |

   Each loot type has its own piece: banded notes, bevelled bars, glass gem trays, artifact crates and velvet chests. Other players see your stack too, within a range limit and a piece budget.
3. **Deposit.** Use the machine's prompt, or turn on Auto-deposit and walk into the painted zone. The server takes your stack *first* and then pays, so a deposit pays exactly once. The deposit summary card shows a NEW RECORD when you beat your best.
4. **Upgrade.** There are 11 Cash upgrades in four categories (Collection, Capacity, Movement, Earnings) and three Vault Token perks.
   - Advanced upgrades appear deeper down: Cash Magnet at B3, Advanced Capacity at B4 and Auto-Collect at B5.
5. **Go deeper.** Unlock the next depth at the elevator panel (B4 and deeper also cost Vault Tokens). Then either:
   - **walk down:** the vault door at the bottom of your pool swings open, and the tunnel behind it ramps down past a window into the next depth's loot, coming out on the next pool's back rim; or
   - **ride the elevator** between any unlocked rims: the doors close, the motor hums and a floor counter rolls until the doors open on the new depth.
   - Locked floors are always listed on the panel, and a locked door blocks its tunnel.
6. **Later systems:**
   - Rare loot events (one at a time, with a per-depth cooldown).
   - A 35-entry Collection Book, 22 achievements and three UTC daily challenges.
   - Four global leaderboards: total earned, deepest vault, loot collected and best deposit.
   - **Rebirth** from B4. It needs the earnings requirement and a typed `REBIRTH` confirmation, and gives +25% loot value forever plus 10 tokens.
   - The sealed "Ancient Vault" complex, shown as coming soon.

The rule for death and respawn: **you keep your carried loot when you die.** Your stack lives in your profile, not on your character. Dying cancels an elevator ride, and you respawn in the elevator of your current depth.

## The depths: seven pools of treasure

Every depth has the same pool layout (`src/server/World/Pools.lua`) and its own look: walls, steps, treasure, monument, palette and lighting.

- **Rim (y0):** the front deck holds the elevator, the deposit machine(s), the upgrade terminal and signage (and B1's leaderboards). Side rims and a back rim run round the pool behind railings, with columns and floodlights.
- **The pool:** a basin 104 × 96 studs and **42 deep**. Its "water" is a walkable sea of loot. From the rim:
  - nine grand steps (1 stud rise each) lead to the first terrace at -9;
  - three ramps of about 31° with flat terraces between them drop to -20, -31 and finally the deep end at -42 (the shallow end is 9 deep, the deep end 42).
  - The walkable surface is simple collidable boxes and slabs in a darker shade of the loot. **The pool is filled with real pickups:** about 1,950 slots per depth tile every step, terrace and ramp wall to wall, on a 2.4-stud jittered brick grid with random yaw and a little height. Every slot holds a collectible item of that depth (non-colliding, anchored, flush on the surface, so walking on the pile is stable). A collected slot shows the dark surface as a dent until it refills.
  - Climbable truss ladders run up the deep end to the back rim.
- **Vault door:** a massive round door in the pool's back wall at the bottom, locked until the next depth is unlocked (the client swings it open; it swings into the pool so it never blocks the tunnel).
- **Tunnel:** behind the door, tunnel A ramps down (14°) under the back rim to a landing with a window into a preview of the next depth's loot. Tunnel C ramps down again (27°) and comes out on the **next depth's back rim, 90 studs lower** (each pool is lower than the last). B7's landing ends at the sealed Ancient Vault.

| Depth | Pool | Architecture parts | Fill slots | Fill parts when occupied |
|---|---|---|---|---|
| B1 Cash Vault | White marble with gold bands and nosings; a sea of banknote bundles; caged cash pyramid on the back rim | 645 | 1951 | 2053 |
| B2 Gold Reserve | Riveted steel and hazard stripes; heaped gold bars and coins; a gantry crane lowering a pallet of gold into the pool | 665 | 1944 | 1994 |
| B3 Diamond Chamber | Blue-grey marble with cool neon bands; glittering diamond clusters; the giant crystal monument | 607 | 1946 | 1962 |
| B4 Emerald Reserve | Dark slate with green neon; emerald clusters; emerald obelisk | 618 | 1946 | 1958 |
| B5 Platinum Reserve | Corrugated steel and diamond-plate steps; platinum ingots; refinery vessel with a chute pouring into the pool | 604 | 1943 | 1977 |
| B6 Artifact Chamber | Sandstone with turquoise bands; coins, urns and relic boxes; sarcophagus under a stone arch | 625 | 1942 | 1960 |
| B7 Legendary Reserve | Black marble, gold pilasters and red-carpet steps; crowns, gold, rubies and chests; tiered treasure dais | 614 | 1944 | 2024 |

The static world totals **4,422 parts** (the elevator shaft included). An **occupied** depth adds its fill: about 1,950 pickups in at most ~2,050 parts (common to rare loot is one part each; Epic+ use detailed models and stay capped at a handful), so an occupied depth is about 2,700 parts. An **idle** depth (nobody on it or heading to it for 30 s) has no fill at all and shows its 16 stand-in slabs instead.

**Loot.** Every fill slot is luckier the deeper it sits: its `bonus` (1.0 at the rim, up to 1.8 at the bottom) multiplies Rare Loot Luck (capped at 2×), so the best finds sit at the deep end. Commons to rares are unlimited in the fill; Epic+ keep their MaxActive caps. Collected slots refill after the depth's `RefillDelay` (4 s on B1 up to 7 s on B7) from a FIFO queue, at most 300 per tick. A depth's fill **materialises only while it is occupied**: a player on it, behind the upper depth's vault door, or riding the elevator to it (filled before arrival). It is unloaded 30 s after the last player leaves. The server looks pickups up through a spatial hash per depth (8-stud buckets) for the magnet and Auto-Collect; the client indexes them the same way for targeting. Claims are still by id and atomic. After a depth is built, `Reach.lua` keeps only slots a player can stand on.
- It indexes every colliding part.
- It builds a multi-level walk graph (1.5-stud columns, every walkable surface up to ~53° a node, neighbours joined when within 1.25 studs of height), flood-filled from the arrival deck.
- It keeps a point only if it isn't buried and a reachable node is within pickup range with a clear line to it.

**Deposits.** Rim machines pay full price. From B2 a secondary **deep-end chute** machine stands at the pool bottom and pays **85%**. It shortens the walk back up without making the rim pointless. The full-stack arrow points at the nearest machine on your own depth, with climbing counted double.

**Safety.** Twice a second the server checks every character is inside a safe volume (rims, the pool, the tunnels). Anyone outside (fell through, stuck in rock, out of the map) is returned to their depth's elevator on the rim. Anyone who gets onto a depth they haven't unlocked is returned too. Walking down onto an unlocked depth records it as your current depth, like an elevator ride.

**Preview renders** (`build/preview-*.png`): for each depth a rim view looking down into the pool, a view from the bottom looking up, the vault door, a top-down plan and the stacks. Also `preview-descent` (a cut-away of B1's pool and tunnel above B2), `preview-b1-tunnel`, the deposit, the elevator, the catalog and the stack modes.

**Map export** (`build/preview.json`): every part carries `d` (1–7 = the depth it belongs to; 0 = the shared elevator shaft and spawn; the catalog sheet is 0 too). A depth's tunnel down to the next rim belongs to the depth it starts in. `meta.depthSpacing` is 90, and `meta.depths[d]` gives `rimY`, `poolBottomY`, `rimCentre`, `poolCentre`, `yMin` and `yMax`:

| Depth | rimY | pool bottom | yMin .. yMax | rim centre |
|---|---|---|---|---|
| B1 | 0 | -42 | -92 .. 26 | (0, 0, -59) |
| B2 | -90 | -132 | -182 .. -62 | (0, -90, -59) |
| B3 | -180 | -222 | -272 .. -154 | (0, -180, -59) |
| B4 | -270 | -312 | -362 .. -244 | (0, -270, -59) |
| B5 | -360 | -402 | -452 .. -332 | (0, -360, -59) |
| B6 | -450 | -492 | -542 .. -424 | (0, -450, -59) |
| B7 | -540 | -582 | -632 .. -514 | (0, -540, -59) |

The ranges overlap, because each depth's tunnel reaches down to the next rim, so assign parts by `d`, not by y.

## Checks (all five pass)

| Check | Command | Result |
|---|---|---|
| Lint | `selene src` | `0 errors / 0 warnings / 0 parse errors` |
| Compile | `lune run tests/compile` | `compiled 55 files, 0 failures` |
| Unit tests | `lune run tests/run` | `38 passed, 0 failed` |
| Build | `rojo build -o build/Vault.rbxlx` | `Built project to Vault.rbxlx` |
| Harness | `lune run tests/harness build/Vault.rbxlx` | `harness: 28 passed, 0 failed` |

To make the previews, run `lune run tools/export_preview build/Vault.rbxlx build/preview.json && node tools/render_preview.mjs build/preview.json build/`. Setting `ONLY=<name>` renders just one view.

**What the unit tests cover:**
- **Economy:** the curve, every upgrade's direction, price growth, depth gating, modest multipliers, and value per slot rising at least 4× per depth.
- **Greedy-player simulation:** tokens now accrue with play time (achievements and dailies), and the search time per pickup reflects the full pools (~0.25 s, was ~1.6 s with sparse floors). Before the fill: B2 ~20 min (15 trips), B7 ~29 h. With full pools and loot values scaled ×0.55 (`LootConfig.FullPoolValue`): B2 ~18 min (30 shorter trips), B7 ~29 h. A test keeps both within 35% / 25% of the pre-fill balance.
- **Fill:** the grid leaves no bare patch wider than 2.7 studs, stays at 1,500–2,000 slots on the surface and is deterministic; the spatial hash matches brute force; the refill queue honours delay, order and the per-tick cap; Epic+ stay capped in a full pool; every common-to-rare item has a single-part look that fits a slot.
- **Stack layout:** thresholds, determinism, the piece budget, bottom-to-top order, interlocked layers that don't overlap, monotonic height, and that no arrangement covers the face or clips into the torso (stacks grow wider and deeper, not taller).
- **Loot tables:** weights, caps, size limits and luck.
- **Progress:** the UTC day, deterministic dailies, and book targets.
- **Config:** every audio id is read from DEAD AIR's own config file; every item has a model; shop ids are 0 and nothing sells power.

**What the harness covers:**
1. The world build.
1. The pool profile: it starts at the rim, segments meet, steps rise at most 1 stud, ramps (and both tunnel ramps) are at most 40°, the basin is 42 deep with the deep end deeper, and the tunnel ends exactly on the next rim.
1. Reachability on foot from the rim (multi-level walk graph): every spawn point, the rare-event spot, every deposit zone (rim and chute), the terminal and the vault door; loot denser and luckier deeper; walls and space under the pool fail.
1. Pool fill: a depth fills on arrival (and for an elevator rider before they arrive), has one pickup per slot, unloads 30 s after it empties and shows its stand-in again; nearest-pickup lookups match brute force on the dense grid; a collected slot stays empty until `RefillDelay` and then refills in place. Magnet and Auto-Collect stay capped in a full pool. The two-player race runs on the dense grid too.
1. Vault doors: with the leaf closed the tunnel is unreachable; with it swung open (the client's DoorMath) the walk continues through tunnel A and C onto the next depth's rim and its arrival deck; B7 ends sealed.
2. Services start, and every depth is stocked.
3. Join and placement.
4. Collect: distance, depth, cooldown and junk ids are all checked; the value is fixed at pickup; models are pooled.
5. A two-player race over five items, with exactly one winner each time.
6. Capacity, including the full-stack notice.
7. Deposit once, with the prompt, the remote and the auto-zone all fired in the same frame; no deposit or pickup on a locked depth.
8. Upgrades: stats change, locked upgrades are refused, and 30-request spam can't overspend.
9. Unlocks happen in order and need both prices; the elevator validates the ride and moves the rider.
10. Deeper loot is worth more.
11. The magnet reserves what it pulls, and Auto-Collect works.
12. Rare events: one at a time, a per-depth cooldown checked over 10 simulated minutes, expiry, and a token reward.
13. Each book entry and achievement fires once.
14. Dailies and codes each pay once.
15. Rebirth requires its confirmation.
16. Receipts: idempotent, capped, and refused live when the profile can't persist; id-0 items are refused live; cosmetics leave stats unchanged.
17. Settings validation and junk remotes.
18. Death and leaving: a ride cancels on death, carried loot is kept, a respawn returns you to your depth, and leaving mid-ride or mid-magnet cleans up.
18. Safety: a player under the pool, off the map or past a locked door is returned to the rim; one who walks down to an unlocked depth has it recorded; the deep-end chute pays exactly 85%.
19. Session lock: lock on load, a taken-over profile stops saving, and a receipt is saved before it is granted.
20. Analytics funnel.
21. **All 11 client controllers initialise** in Main.client's order and handle real server payloads. Client pickups go through to the server; stack pieces are welded; crate mode works; every window opens; the elevator panel lists B1–B7; the book shows silhouettes; exit doors open only once their depth is unlocked; and the lighting follows the depth.

## Per-phase reports

### Phase 1 — Core loop
- **Pickup:** E/ButtonX/PICKUP pickup through `LootService.collect`. The claim is atomic: the item is unregistered before any reward is given.
- **Carried inventory:** stored in `profile.Carried` and published as player attributes, so every client can draw every stack.
- **Stack layout:** a pure, deterministic `StackLayout` with five arrangements and per-category pieces (`LootModels.piece`). Pieces are welded to the root and tween between layouts.
- **Deposit machine:**
  - The model has a plinth, cabinet, hopper, chute, a spinning drum, a screen, five lamps, a status light, guards, and a painted auto-deposit zone.
  - The prompt and the zone share one code path.
  - On deposit, the machine chases its lamps, spins the drum and counts up on its screen, plays sounds, and shows the stack flying in plus an equipped effect.
- **Currencies:** Cash, and Vault Tokens from achievements, dailies, rare finds, rebirth and codes.
- **Upgrades:** gated by depth. Purchases are rate limited and charged atomically.

### Phase 2 — Depths and elevator
- **Seven depths** in one continuous vertical structure, all sharing one shaft. The shaft has rails, cables, counterweights, lights and landing numbers.
- **Elevator:** a cabin with sliding doors, a floor panel and buttons, a shaft window, the depth display above the doors, and sounds.
- **The ride** is a validated transition, not physics. The server checks that the depth is unlocked, that you are at the cabin, that you aren't already riding, and the cooldown. The ride lasts 1.4 s + 0.35 s per floor, capped at 3.6 s. The client closes the doors, plays the motor, counts floors on an overlay with passing light bars, and shows an arrival title card.
- **Fixed during this phase:** riders used to arrive facing the back wall of the cabin. They now face out of the doors, and the harness asserts it.
- **Rebuilt as deep pools (user request):** the depths were first flat rooms, then distinct floor plans with staged furniture. At the user's request every depth is now a deep pool of treasure: walk down from the rim, a vault door at the deep end, and a tunnel down to the next, deeper pool (see "The depths"). The furniture staging from the floor-plan pass (including B6/B7's staged loot) is gone; loot is now spread over the pool's treasure surface. Carried stacks stay lowered and widened so no arrangement covers the face.

### Phase 3 — Storytelling
- **On every depth:** the vault door with restricted signage and warning lights, cameras watching the pool, floodlit pool walls, rim columns and railings, a monument on the back rim, hanging signs, access panels, and maintenance and security doors.
- **Locked floors** are listed on the elevator panel with their price.
- **Glimpses of the next depth:** each tunnel landing has a preview room behind glass that shows the next depth's real loot models. After B7 it shows a stone idol: "Ancient Vault — coming soon".
- **The exit door** opens on the client once the next depth is unlocked.

### Phase 4 — Systems
- **Loot:** 28 normal items plus 7 rare-event specials, with rarities from Common to Mythic. Loot spawns at validated points with per-item caps, respawns per depth, and comes from a pool.
- **Rare events:**
  - A global gap of 120–240 s between events.
  - Each depth then waits 420 s before it can host another.
  - An event lasts 180 s, and players are told when one appears and when it is gone.
- **Progress systems:** the Collection Book (an extra token for each new Epic+ find), 22 achievements (three of them unlock stack themes), three UTC dailies with money targets scaled to your depth, four OrderedDataStore leaderboards with batched writes, and rebirth with a preview of what it resets and keeps.
- **Second complex:** the framework is in place (`DepthConfig.NextComplex`).

### Phase 5 — UI
- **HUD:**
  - Cash and Tokens that count up.
  - A boost timer.
  - A depth chip showing the next requirement as a progress bar.
  - Menu buttons with their shortcut keys.
  - A carried panel with a slot bar, which pulses **STACK FULL — DEPOSIT** when full.
  - An arrow on the floor plus a "DEPOSIT HERE" marker pointing to the nearest machine.
  - The deposit summary card.
  - Toasts, queued milestone popups (with a 3D icon of the item), announcements, and the mobile PICKUP button.
- **Windows:** Upgrades (category tabs and cards showing the effect now → next), Depths (the vertical panel), Collection Book (silhouettes for undiscovered items), Achievements, Daily, Stats & Rebirth (typed confirmation), Leaderboards, Shop, and Settings (5 volume sliders, auto-deposit, show others, reduced effects, camera sway, tutorial replay, and codes).
- **Onboarding:** a five-step chip, with a "HERE" marker over the thing to use. Each step advances on the real action. You can skip it.

### Phase 6 — Audio
- **Every filled id is reused from DEAD AIR.** No id was invented; `config.spec` reads DEAD AIR's file to enforce this.
- **Ambience:** each depth has 2D beds, 3D emitters placed by the themes, and random one-shots.
- **Pickup sounds** differ by loot category, with pitch variation and anti-stacking.
- **Empty slots:** the music tracks, CoinShower and CrystalChime are empty and stay silent until you add audio (see POLISH.md).

### Phase 7 — Monetization (optional only)
- **What's for sale:**
  - Stack themes, a trail and deposit effects, which change looks only.
  - VIP: +10% deposit payout and a tag.
  - A 15-minute +25% Value Boost, which stacks to a 60-minute cap.
- **The ids are all 0.** Studio grants the item free for testing; a live game says "not available yet".
- **Receipts** are idempotent and saved before they are acknowledged. They return `NotProcessedYet` when the player isn't loaded, can't persist live, or is leaving.
- **The base game is completely playable without Robux.**

## Final delivery report (10 points)

1. **What was built:** a complete VAULT Rojo project. It has 50 source files: 10 server services, 6 world modules, 11 client controllers, and shared configs and logic.
2. **What is playable:** all 7 depths, end to end. The full core loop, upgrades, unlocks, the elevator, rare events, book, achievements, dailies, leaderboards, rebirth, shop and settings are all in.
3. **Server authority:** the server decides every value, claim, capacity check, payout, price, unlock and ride. The client only displays and requests.
4. **Persistence:**
   - A session-locked DataStore profile.
   - Migration runs before defaults are filled in, and loaded data is validated and clamped.
   - Autosave every 60 s, a save on leave, and a save on BindToClose.
   - `_Studio` stores for testing.
5. **Exploit resistance:**
   - Distance and depth checks; you can't use a depth you haven't unlocked, even by teleporting there.
   - Pickup cooldowns with a tolerance, rate limits, and NaN- and junk-safe remotes.
   - The stack is taken before payment, and claims are atomic.
6. **Performance:**
   - 4,422 static parts, plus ~2,000 fill parts on each occupied depth only.
   - Pooled loot.
   - One Heartbeat step on the server, with no per-object loops.
   - Budgets for stack pieces, effects and the range at which other players' stacks are drawn.
   - Position-based zone checks (no Touched events).
   - StreamingEnabled is off, because the whole world is about 5,700 parts.
7. **Testing:** see the checks above. No Studio playtest was done.
8. **Visual QA:** 41 renders: each pool from the rim, from the bottom, at its vault door, from above and with stacks, plus a cut-away of the descent, the tunnel, the deposit, the elevator, the catalog and the stack modes. Fixed from them: pools given lower ceilings and rounded treasure banks so the basin dominates, darker treasure colours, tunnel walls, preview cameras clear of the mannequins; earlier, stacks lowered below the face and the catalog re-framed.
9. **Known limitations:** listed below.
10. **What you need to provide:** listed below.

## Limitations

- **Never run in Roblox Studio.** Physics, camera feel, the real renderer, TweenService timing, ProximityPrompt behaviour on real devices, and mobile layout are untested.
- **Elevator:** the ride is a short transition. The cabin does not physically travel, by design.
- **Door tweens:** the door and leaf animations are client-only and tween a Value object. They are untested in an engine.
- **Leaderboards** are empty in Studio unless API access is on. They refresh every 60 s.
- **Visuals are primitive parts.** Every loot model is built from parts; see POLISH.md for asset swaps.
- **Balance** comes from a simulation. Real players will need tuning, mainly B4's token gate and the cost curves from B5 to B7.

## What you need to provide

- **Game Pass ids:** for `VIP`, `NeonVault` and `GoldTrail`, set in `src/shared/Config/ShopConfig.lua`.
- **Developer Product ids:** for `GoldenGlow`, `Confetti` and `ValueBoost`, in the same file.
- **Audio, if you want it:** music tracks for `MusicTop`, `MusicDeep` and `MusicLegendary`, plus `CoinShower` and `CrystalChime`, in `src/shared/Config/AudioAssets.lua`.
- **Optional replacement meshes and textures:** see POLISH.md.

## Studio test plan (save / load and multiplayer)

1. **Solo, with API access on:**
   - Collect until full, check the FULL banner and the arrow, then deposit.
   - Buy Carrying Capacity and watch the stack's arrangement change.
   - Leave and rejoin: Cash, upgrades, the carried stack and the book should all still be there.
2. **Two clients:**
   - Both players race for the same bill.
   - Each player's stack is visible to the other.
   - One player leaves mid-elevator ride; the server output should show no errors.
3. **Deposits:** stand in the deposit zone with Auto-deposit on and press E at the same time. You should be paid once.
4. **Progression:** unlock B2 and ride down. Check the doors, the counter and the title card. The B1 exit door should be open on rejoin.
5. **Death:** reset your character while carrying loot. You should respawn in your depth's elevator with the stack intact.
6. **Purchases:** with a real product id set, buy a boost twice. The Receipts table should hold two entries.
7. **Mobile emulator:** check the PICKUP button, that the windows fit, and the UIScale.

## Files

The Rojo project maps the folders like this:
- `src/shared` → `ReplicatedStorage.Vault`
- `src/server` → `ServerScriptService.VaultServer`
- `src/client` → `StarterPlayerScripts.VaultClient`

| Folder | Contents |
|---|---|
| `src/shared/Config` | Game, loot, depth, upgrade, quest, cosmetic, shop, performance and audio configs |
| `src/shared` | DoorMath, Economy, LootTable, StackLayout, Progress, LootModels, LightingPresets, Net, Signal, Rng, Format |
| `src/server/World` | Props, Machines, VaultBuilder, Pools (the treasure pools, doors and tunnels), Themes (materials, helpers, preview rooms), Reach (reachability) |
| `src/server/Services` | Analytics, DataService, PlayerService, ShopService, UpgradeService, QuestService, LootService, DepositService, ElevatorService, LeaderboardService, RateLimit |
| `src/client/Controllers` | ClientState, Ui, AudioController, CollectController, InputController, StackController, DepositController, ElevatorController, HudController, MenuController, TutorialController, EffectsController |
| `tests` | `compile`, `run` with 5 specs, the `harness`, `loader` |
| `tools` | `export_preview.luau`, `render_preview.mjs` |
