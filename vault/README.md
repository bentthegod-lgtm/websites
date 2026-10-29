# VAULT

A Roblox collect-and-deposit game set in an underground bank vault. Players pick up loose loot one item at a time and carry it as a visible stack that grows on their character. They feed it into a deposit machine for Cash, then spend the Cash on upgrades and on unlocking deeper depths. There are seven depths, each with better loot, and they are all stacked inside one building and served by one elevator.

> **Honest status.** This is a Rojo project. It has never been opened or played in Roblox Studio.
>
> What *was* verified headlessly, in Lune:
> - every file lints and compiles;
> - 32 unit tests pass;
> - 23 harness checks pass. They run the real server and client modules against Lune's Roblox instance model, with stubbed engine services and a fake clock.
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
5. **Go deeper.** Unlock the next depth at the elevator panel. B4 and deeper also cost Vault Tokens. Then ride down: the doors close, the motor hums and a floor counter rolls until the doors open on the new depth.
   - Locked floors are always listed on the panel.
   - At the end of each depth's corridor, a vault door hides the next one. You can glimpse its loot through glass in a preview room, and the door swings open once that depth is unlocked.
6. **Later systems:**
   - Rare loot events (one at a time, with a per-depth cooldown).
   - A 35-entry Collection Book, 22 achievements and three UTC daily challenges.
   - Four global leaderboards: total earned, deepest vault, loot collected and best deposit.
   - **Rebirth** from B4. It needs the earnings requirement and a typed `REBIRTH` confirmation, and gives +25% loot value forever plus 10 tokens.
   - The sealed "Ancient Vault" complex, shown as coming soon.

The rule for death and respawn: **you keep your carried loot when you die.** Your stack lives in your profile, not on your character. Dying cancels an elevator ride, and you respawn in the elevator of your current depth.

## The depths

All seven depths are playable. They share one facility language: the same arrival hall (elevator, deposit machine(s), upgrade terminal, signage, cameras, access doors), base materials and trim. Each chamber has **its own floor plan** (`src/server/World/Plans.lua` for B1–B5; B6/B7 use the classic columned chamber plus `Themes.lua`). Depths are stacked 150 studs apart (B1 y = 0 … B7 y = -900), and `FallenPartsDestroyHeight` is -3000.

| Depth | Floor plan | Ceiling | Exit door | Parts | Spawn points (staged) |
|---|---|---|---|---|---|
| B1 Cash Vault | Long banking hall: marble colonnades split a coffered nave (counting floor, six counting tables) from low-soffit side aisles of cash-rack rows, cash carts, safe-deposit walls with open drawers; caged cash pyramid at the nave's end | 30 (aisles 16) | centre | 976 | 144 (74%) |
| B2 Gold Reserve | Tall fortified bullion yard: riveted plating and buttresses, mezzanine catwalk on three sides, a ring of eight heavy gold racks round a central bullion stack under a gantry crane, gold pallets and bullion cages; blast-door entrance | 36 | far right (x 38) | 1003 | 104 (79%) |
| B3 Diamond Chamber | Hexagonal hall: six glass display wings with open pedestals radiate from the faceted crystal in its laser ring; open velvet trays on the slanted walls; stepped ceiling rings, oculus and cool spotlights | 32 | centre, through a vestibule | 621 | 104 (81%) |
| B4 Emerald Reserve | Narrow vaulted gallery (44 wide) under arch ribs; nine side alcoves behind green-lit arches, each with an emerald tower and premium cases; black stands down the nave; obelisk at the north end | 26 | far left (x -36), via a side passage | 711 | 102 (82%) |
| B5 Platinum Reserve | Industrial hall: three rows of 14-stud warehouse racks on the left, a conveyor with three presses and output tables on the right, overhead catwalks, refinery vessel, alloy shelving, cold strip lights, corrugated walls | 38 | right (x 40) | 886 | 140 (86%) |
| B6 Artifact Chamber | Classic chamber: stone columns and arches, mosaic runner, containment pods, sarcophagus | 30 | centre | 673 | 146 |
| B7 Legendary Reserve | Classic chamber: monumental gold entrance, red carpet, gold columns, treasure heaps, tiered dais | 30 | centre | 658 | 142 |

The world totals **5,572 parts**; the harness budget is under 9,000. Live loot comes on top of that, at 48–64 pooled items per depth.

**Loot staging (B1–B5).** Most spawn points sit on the furniture of each floor:
- B1: rack shelves, counting tables, carts, open drawers and pallets.
- B2: ring and wall racks, gold pallets.
- B3: pedestals and trays.
- B4: alcove cases and nave stands.
- B5: rack shelves, the conveyor belt and the press output tables.

The rest are loose floor items along the walking lanes, never on the routes (elevator → chamber → exit door), which are kept-out boxes.

**Reachability.** After a depth is built, `Reach.lua` checks every spawn point against the real parts.
- It indexes every colliding part.
- It flood-fills a 2-stud walk grid from the elevator.
- It keeps a point only if the point isn't buried and some reachable cell is within pickup range with a clear line to it.

The harness re-checks this independently. It also checks that every deposit zone, upgrade terminal and exit door is reachable, and that a point in a wall or in sealed rock fails.

The rendered plans are `build/preview-b*-plan.png`, top-down with the ceiling cut away.

## Checks (all five pass)

| Check | Command | Result |
|---|---|---|
| Lint | `selene src` | `0 errors / 0 warnings / 0 parse errors` |
| Compile | `lune run tests/compile` | `compiled 50 files, 0 failures` |
| Unit tests | `lune run tests/run` | `32 passed, 0 failed` |
| Build | `rojo build -o build/Vault.rbxlx` | `Built project to Vault.rbxlx` |
| Harness | `lune run tests/harness build/Vault.rbxlx` | `harness: 23 passed, 0 failed` |

To make the previews, run `lune run tools/export_preview build/Vault.rbxlx build/preview.json && node tools/render_preview.mjs build/preview.json build/`. Setting `ONLY=<name>` renders just one view.

**What the unit tests cover:**
- **Economy:** the curve, every upgrade's direction, price growth, depth gating, modest multipliers, and value per slot rising at least 4× per depth.
- **Greedy-player simulation:** B2 at about 16 trips, then B3 at 31, B4 at 39, B5 at 100, B6 at 272 and B7 at 701. That is roughly 30 hours of play, without Robux.
- **Stack layout:** thresholds, determinism, the piece budget, bottom-to-top order, interlocked layers that don't overlap, monotonic height, and that no arrangement covers the face or clips into the torso (stacks grow wider and deeper, not taller).
- **Loot tables:** weights, caps, size limits and luck.
- **Progress:** the UTC day, deterministic dailies, and book targets.
- **Config:** every audio id is read from DEAD AIR's own config file; every item has a model; shop ids are 0 and nothing sells power.

**What the harness covers:**
1. The world build.
1. Reachability of every spawn point, machine and exit; loot staging share per depth.
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
19. Session lock: lock on load, a taken-over profile stops saving, and a receipt is saved before it is granted.
20. Analytics funnel.
21. **All 11 client controllers initialise** in Main.client's order and handle real server payloads. Client pickups go through to the server; stack pieces are welded; crate mode works; every window opens; the elevator panel lists B1–B7; the book shows silhouettes; and the lighting follows the depth.

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
- **Reworked after render review:** B1–B5 were originally one shared rectangular room with recoloured dressing and loot scattered on bare floor. Each now has its own floor plan, proportions, ceiling, wall treatment and exit position (see "The depths"), with staged loot and a reachability filter. Carried stacks were also lowered and widened so no arrangement covers the face.

### Phase 3 — Storytelling
- **On every floor:** vault doors, cameras, ducts and cable trays with joints, pipes with clamps, hanging signs, restricted signage, warning lights, access panels, and maintenance and security doors.
- **Locked floors** are listed on the elevator panel with their price.
- **Glimpses of the next depth:** each corridor ends in a preview room behind glass that shows the next depth's real loot models. After B7 it shows a stone idol: "Ancient Vault — coming soon".
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
   - 5,572 static parts.
   - Pooled loot.
   - One Heartbeat step on the server, with no per-object loops.
   - Budgets for stack pieces, effects and the range at which other players' stacks are drawn.
   - Position-based zone checks (no Touched events).
   - StreamingEnabled is off, because the whole world is about 5,600 parts.
7. **Testing:** see the checks above. No Studio playtest was done.
8. **Visual QA:** 34 renders, including a top-down plan of every depth, covering every depth's arrival, chamber and stacks views, plus the exit, deposit, elevator, B7 entrance, catalog and stack modes. Fixed from them: rooms rescaled, B1–B5 given distinct floor plans, stacks lowered below the face, the catalog re-framed.
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
| `src/shared` | Economy, LootTable, StackLayout, Progress, LootModels, LightingPresets, Net, Signal, Rng, Format |
| `src/server/World` | Props, Machines, VaultBuilder, Plans (B1–B5 floor plans), Themes (B6/B7), Reach (reachability) |
| `src/server/Services` | Analytics, DataService, PlayerService, ShopService, UpgradeService, QuestService, LootService, DepositService, ElevatorService, LeaderboardService, RateLimit |
| `src/client/Controllers` | ClientState, Ui, AudioController, CollectController, InputController, StackController, DepositController, ElevatorController, HudController, MenuController, TutorialController, EffectsController |
| `tests` | `compile`, `run` with 5 specs, the `harness`, `loader` |
| `tools` | `export_preview.luau`, `render_preview.mjs` |
