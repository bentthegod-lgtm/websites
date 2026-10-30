# THIN ICE

A co-op survival horror game for Roblox, for 1–6 players. Your group crosses a frozen lake at night to chip glowing **frozen cores** out of the ice and carry them back to the beacon on the shore. Every step stresses the ice, and thin ice is dark and cracks fast. Under it sleeps **the Antlered**, a tall, blind, antlered creature that hunts **only by sound**. Sneak, throw snowballs to lure it away, thaw frozen friends, and reach the rescue sled before it leaves.

> **Honest status.** This is a Rojo project, **rebuilt from scratch** from the recovered design (the first version was lost with its session). It has never been opened or played in Roblox Studio.
>
> What *was* verified headlessly, in Lune:
> - every file lints (selene) and compiles;
> - 24 unit tests pass (lake generation, ice / stamina / warmth / noise maths, the monster's brain, rewards, config);
> - 29 harness checks pass. They run the real server and client modules against Lune's Roblox instance model, with stubbed engine services and a fake clock. They play whole rounds: vote, ready, countdown, the lake built over 11 frames, footsteps, ice breaking under a sprinter, falling in and climbing out, the monster waking, hearing, hunting and catching, thawing, the flask, chipping and delivering cores, the sled escape, rounds that fail, players leaving, receipts, the session lock and every client screen.
>
> Lune has no physics and no renderer, so the harness moves characters itself. The world was checked visually with three.js renders of the exported parts (`build/preview-*.png`), which are not Roblox's renderer. **Follow the Studio test plan below before publishing.**

## Quick start

```bash
cd thin-ice
rojo build -o build/ThinIce.rbxlx    # then open build/ThinIce.rbxlx in Roblox Studio and press Play
# or live-sync: rojo serve           (then Connect in the Rojo Studio plugin)
```

1. Open `build/ThinIce.rbxlx` in Studio.
2. **To test saving:** Game Settings → Security → turn on **Enable Studio Access to API Services**. Without it the game still runs and tells you saving is off.
3. Press **Play** (solo), or **Test → Clients and Servers** with 2–3 players. The game is built around friends thawing each other.
4. Studio uses separate `_Studio` DataStores, so test saves never touch live data. Robux items with an ID of 0 are granted free in Studio for testing.

## Controls

| Action | Keyboard / gamepad | Mobile |
|---|---|---|
| Sneak (quiet, light on the ice) | **C** toggles (setting: hold) / **B** | **SNEAK** |
| Sprint (loud, heavy on the ice) | hold **Shift** / **L3** | hold **SPRINT** |
| Throw a snowball where you look | **F** / **R2** | **THROW** |
| Chip a core, pick one up, thaw a friend | hold **E** at the prompt | hold the prompt |
| Menu | **M** / **Select** | **MENU** |

## How a round plays

1. **Camp (lobby).** Everyone spawns at the warming hut, walks the boardwalk with its lamp posts, and gathers at the campfire and the dock. Press **READY** and vote a difficulty: Easy, Normal, Hard or Nightmare. The most votes wins and a tie goes to the easier one. The countdown starts when everyone is ready, or 25 s after the first person readies up.
2. **The ice forms.** A new lake is generated from a fresh seed: 16 × 32 tiles in four zones.
   - **Pine Shallows** has mostly thick ice.
   - **Thin Flats** has lots of dark, thin ice.
   - **Boulder Isles** has rocks and ice crystals to hide behind.
   - **Wreck Bay** holds the wrecked boat and more holes.

   Every core and brazier is guaranteed reachable from the shore. The lake is built 48 tiles per frame (11 frames), so the server never stalls.
3. **Cross.** You have warmth, stamina and snowballs.
   - **Ice stress.** Sprinting stresses a tile almost 3× more than walking, and carrying a core adds weight. A tile **cracks** at half strength, which makes a visible web of cracks and a loud crack the monster hears. At full strength it **breaks**. You fall into freezing water, then haul yourself onto the nearest ice 2.5 s later. Broken ice refreezes as thin ice after 40 s.
   - **Warmth** drains on the ice, fast in water and faster in blizzard gusts. Braziers on the lake, the campfire and the shore warm you. At zero you freeze solid.
   - **Snowballs** (3 to start, refill at snow drifts) land 46 studs away and make a loud noise there with no owner. It's a lure.
4. **The Antlered.** It sleeps under the ice for a grace period (30 / 22 / 16 / 12 s by difficulty), then bursts out and prowls toward life.
   - It is blind: it reacts only to noises, scaled by distance, difficulty and weather. Faint sounds make it stop and listen, then investigate. Loud or close ones start a hunt that follows each new sound. Once the noise stops it searches around the last sound, then goes back to prowling.
   - It feels footsteps through the ice within 7 studs (even sneaking). Standing still is the only way to hide that close.
   - **Blizzard gusts** halve what it hears, a risky window to move.
   - It never leaves the ice: **the shore is safe.**
   - If it catches you, you're frozen in an ice block with a short, tasteful scare (see below).
5. **Frozen.** Friends hold **E** for 3 s beside your block to thaw you; you stand up beside them with some warmth back. A **Thermos Flask** (optional purchase) thaws you once, 8 s after freezing. Frozen for 45 s means you're lost for the round and watch from the shore.
6. **Cores.**
   - Hold **E** for 3 s to chip a core free. Chipping is **loud**.
   - Carry the glowing shard over your head to the beacon. Falling in, freezing or leaving drops it where you were, and anyone can pick it back up.
   - Each delivered core lights the beacon more.
7. **Escape.** When every core is in, *"ALL CORES IN! Get to the sled – it leaves soon!"* gives you 45 s. Everyone who reaches the sled escapes.
8. **A round always ends:** with the sled; with *"Everyone froze on the ice."*; when the time limit runs out (9 / 8 / 7.5 / 7 min); or when every participant has left. Then everyone gets a results card with their reward lines, and the lake is cleared.

## Progression and shop

- **Rewards.** 20 coins for playing, 30 per core you delivered, 25 per friend you thawed and 80 for escaping. The total is multiplied by difficulty (×1 / 1.4 / 2 / 3). XP comes with coins, and levels follow a rising curve.
- **Daily reward.** A 7-step login streak pays 50 to 300 coins.
- **Daily goals.** Deliver a core, thaw a friend, throw 5 snowballs and escape. Each pays once a day.
- **Codes:** `THINICE` (150 coins), `ANTLERS` (100 coins and a Thermos Flask), `COLDFEET` (75 coins).
- **Wardrobe** (purely visual):
  - 7 outfits: beanie, pompom, scarf and jacket colour, built on your own avatar.
  - 4 lantern colours: a real light that you carry.
  - Unlocked with coins, levels, Robux or VIP. The menu shows 3D previews.
- **Robux, all optional:**
  - Thermos Flask ×1 and ×5. The flask is the only gameplay item, and a friend can always thaw you for free.
  - Polar Explorer outfit and Aurora lantern.
  - **VIP pass:** Golden Parka, a VIP tag and +10% coins.
- **Board.** A global *Most escapes* board stands at camp and is also in the menu.

## The scare (13+, tasteful)

When the Antlered catches **you**:
- a split-second close-up of its blind, eyeless face, rendered from the real model in a ViewportFrame;
- a cold white flash that fades in under a second;
- a camera jolt.

There is no gore, blood or screaming. With **Scare effects** turned off in Settings, this becomes a gentle blue fade. Set the experience's maturity questionnaire honestly (mild fear).

## What you need to add before publishing

| Item | Where | Notes |
|---|---|---|
| 4 Developer Products | `src/shared/Config/ShopConfig.lua` → `ProductId` | Flask1 (R$25), Flask5 (R$99), Polar (R$79), Aurora (R$49) |
| 1 Game Pass | `ShopConfig.Passes[1].PassId` | VIP (R$149) |
| Music and wind (optional) | `src/shared/Config/AudioAssets.lua` | `Wind`, `GustWind`, `LobbyMusic`, `LakeMusic` and `UIClick` are empty. Add Creator Store audio you have rights to. Empty slots are skipped safely. |
| Thumbnail and icon | `thumbnail-1920x1080.png`, `icon-512.png` | Rendered from the game's own models (`tools/store_art.mjs`) |

**No asset IDs were invented.** The 18 filled sound slots reuse IDs that the DEAD AIR project in this repo already uses (a unit test enforces this). Verify they still play in Studio.

## Studio test plan

1. **Solo.** Ready up and play Easy.
   - Thin (dark) tiles break under a sprint.
   - You fall in and climb out.
   - Warmth recovers at braziers and on the shore.
   - The monster wakes after the grace period and turns toward your sprinting.
   - Chip a core and deliver it.
   - The beacon brightens.
2. **2–3 clients.**
   - One player gets caught, sees the scare and is frozen. Another thaws them and they appear beside the rescuer.
   - Leave mid-round while carrying a core: the core should drop.
   - Finish a round with the sled.
3. **Physics feel.** Not testable headlessly.
   - Check that falling into a hole looks right (the water is 2.2 studs below the ice) and that you cannot jump out of the hole faster than the 2.5 s auto-climb in a way that feels wrong.
   - Check that the speed check never rubber-bands normal play on a laggy connection. Tune `Move.Tolerance` / `Slack` if it does.
4. **Saving** (API access on). Rejoin and check that coins, the wardrobe, flasks and the streak persist.
5. **Mobile emulator.**
   - The SPRINT / SNEAK / THROW buttons don't cover the thumbstick.
   - The HUD scales down.

## Project layout

```
src/shared/      Config (Game, Cosmetic, Shop, Audio), LakeGen, IceMath, MonsterBrain, Progress,
                 Models (all procedural part models), Net, Rng, Signal, Format
src/server/      Main.server.lua; World/LobbyBuilder (camp, cliffs, water, aurora), World/LakeBuilder
                 (incremental lake); Services: Data, Round, Survival, Ice, Objective, Monster, Noise,
                 Weather, Reward, Shop, Player, Leaderboard, RateLimit
src/client/      Main.client.lua; Controllers: ClientState, Ui, Input, Hud, Menu, Effects, Lighting, Audio
tests/           run.luau (unit specs), harness.luau (headless game), compile.luau, loader.luau
tools/           export_preview.luau, render_preview.mjs (previews), store_art.mjs (thumbnail + icon)
```

## Checks

```bash
selene src
lune run tests/compile
lune run tests/run
rojo build -o build/ThinIce.rbxlx
lune run tests/harness build/ThinIce.rbxlx
# previews / store art
lune run tools/export_preview build/ThinIce.rbxlx build/preview.json
node tools/render_preview.mjs build/preview.json build/
node tools/store_art.mjs build/preview.json .
```

**Part counts.**

| Area | Parts | Notes |
|---|---|---|
| Shore camp | 878 | Built once at startup, in about 0.02 s in Lune |
| A round's lake | 760–840 | Varies by difficulty, about 3 ms per build frame in Lune |
| During a round | about 1,750 | Plus players |
