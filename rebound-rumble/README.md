# REBOUND RUMBLE

A fast, flashy deflect-the-homing-ball PvP game for Roblox (an original game in the
"deflect the energy ball" genre). A glowing energy ball hunts one player at a time. Parry it at
the last moment to send it, faster, at whoever you're looking at. Miss and you explode. The last
player standing wins.

Everything is built from code: the lobby, 4 arenas, the ball, the parry weapons, bots, effects and
all the UI. There are no imported models and no uploaded assets.

## Build, run, test

```bash
cd rebound-rumble
rojo build -o build/ReboundRumble.rbxlx      # open this file in Roblox Studio
rojo serve                                   # or live-sync with the Rojo Studio plugin

selene src                                   # lint (custom std: roblox_min.yml)
lune run tests/compile                       # compile every source file
lune run tests/run                           # unit tests (pure logic)
rojo build -o build/ReboundRumble.rbxlx && lune run tests/harness build/ReboundRumble.rbxlx
```

In Studio:

* **Solo:** press Play. You're auto-ready, so a 15 s countdown starts and bots fill the round.
* **Multiplayer:** Test, then Clients and Servers, with 2 to 4 players. With 2 or more ready players
  the countdown drops to 10 s. Wins only count for the leaderboard and the streak when at least
  2 real players are in the round.
* **Saving:** enable *Game Settings > Security > Enable Studio Access to API Services*. Without it
  the game still runs and tells the player that progress isn't saved.
* **Robux items:** while their IDs are 0, every product and pass is granted free in Studio (passes
  only for that session).

## How to play

1. You spawn in the floating sky lobby. You are **READY** by default (side bar toggle). When
   enough players are ready, everyone is teleported into the next arena.
2. The ball charges above the centre pad, then picks a target. The target glows red for everyone,
   and the target's own screen shows a red vignette and **THE BALL IS HUNTING YOU!** It changes to
   **PARRY NOW!** inside the window.
3. Press **Parry** while the ball is close. **The camera direction picks who it goes to next.**
   Each deflect speeds the ball up.
4. Pressing early, or while you're not the target, is a **whiff**. That triggers a long cooldown
   (0.9 s against 0.25 s after a clean parry), so spamming doesn't work.
5. If the ball reaches you, you explode. If your deflect eliminated someone, the kill is yours.
6. Eliminated players spectate. By default the camera follows whoever the ball is hunting, and
   you can also cycle players. The last player standing wins, then everyone returns to the lobby.
   After about 100 s, overtime makes the ball accelerate on its own.

### Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Parry | F or Left Click | R1 / R2 | big PARRY button |
| Ability 1 / 2 | Q / E | X / Y | ability buttons |
| Aim | camera | right stick | drag camera |
| Menu focus | n/a | Select | side bar |
| Spectate cycle | Left / Right arrows | D-pad | < > buttons |

The UI scales down with a UIScale on small screens.

## Systems

| System | Where | Notes |
|---|---|---|
| Round flow | `MatchService` | Lobby, Countdown, Playing, Results, Lobby. Bots fill to 5 contestants, and solo is allowed. Arenas rotate. |
| Ball simulation | `BallService` + `shared/BallMath` | Server-authoritative homing with a speed-scaled turn rate and a capped turning circle, so the ball never orbits. It curves after a deflect, speeds up per deflect up to 300, and accelerates in overtime. |
| Parry judging | `shared/ParryJudge` | The client sends `workspace:GetServerTimeNow()` at the press. The server rewinds the ball's recorded path by that latency, capped at 0.25 s, and ignores future or NaN timestamps. A 0.12 s hit grace accepts in-flight parries that were pressed before the hit. It applies cooldowns and a remote rate limit. |
| Client ball | `BallController` | It predicts with the same BallMath between 15 Hz server snapshots and blends out corrections. The ball is visual only. |
| Bots | `BotService` + `shared/BotBrain` | Labelled `[BOT] Name`. Bots use the same ParryJudge as players. Skill decides when they press: inside the window, too early, or never. The chance drops as the ball speeds up. |
| Abilities | `AbilityService` | Dash, Super Jump, Swap, Freeze and Shield. They cost coins only, and the loadout can only be changed in the lobby. The server validates everything. Dash and Super Jump are applied by the owning client, which has physics ownership. |
| Economy | `RewardService` + `shared/Economy` | Coins for playing, kills, parries, survival time, wins and win-streak bonus, all capped. Pass multipliers add up to a cap of 2.5x. |
| Cosmetics | `CosmeticService` + `shared/CrateRoll` | Parry weapons (sword, bat, katana, hammer, scythe from parts), ball trails and explosion colours in 6 rarity tiers. Crates show their odds, have pity at 40 opens, refund duplicates, and announce Legendary and Mythic drops server-wide. |
| Data | `DataService` | DataStore with retries, versioned schema and migration (v1 to v2), autosave every 90 s, save on leave and BindToClose, and an in-memory fallback. leaderstats: Wins, Streak, Coins. |
| Leaderboard | `LeaderboardService` | OrderedDataStore "Most Wins" board in the lobby, refreshed every 60 s, with every call in pcall. |
| Retention | `RewardService`, `MenuController` | 7-day daily streak, codes, friend invite bonus (once per session), 3 session goals, a "Like the game for a code" sign, and win-streak and kill-streak announcements. |
| HUD | `HudController` | Coins, streak, alive count, target warning, ball speed, parry and ability cooldowns, kill feed, banners, results screen and coin popups. |
| Effects | `EffectsController` | Weapon swing arcs, parry flash, explosions with shards, rings and light, confetti, shield pop, freeze shell, swap warp, win fireworks and camera shake (can be turned off). |

### Abilities (coins only)

| Ability | Price | Cooldown | Effect |
|---|---|---|---|
| Dash | free | 6 s | Burst in your move direction. |
| Super Jump | 750 | 8 s | Launch upward. |
| Swap | 1,500 | 22 s | Swap places with a random opponent. The ball keeps its target. |
| Freeze | 2,500 | 30 s | Only while the ball hunts you: 30% speed for 1.2 s. You still must parry. |
| Shield | 4,000 | passive | Your first miss each round is absorbed. The ball keeps its speed and goes to a random player, with no kill credit. |

### Codes

`RELEASE` (300 coins), `PARRY` (150), `LIKETHEGAME` (200), `RUMBLE` (1 Premium Spin). Edit them in
`src/shared/Config/ProgressionConfig.lua`.

## Robux shop

The **SHOP** button is in the lobby side bar. Prices are display-only; the real price is whatever
you set in Creator Hub.

**Developer Products** (`ShopConfig.Products`, set `ProductId`):

| Key | Item | Display price |
|---|---|---|
| Coins500 | +500 coins | R$ 49 |
| Coins1500 | +1,500 coins | R$ 129 |
| Coins5000 | +5,000 coins | R$ 399 |
| Spin1 | 1 Premium Spin (no Commons, odds shown) | R$ 39 |
| Spin5 | 5 Premium Spins | R$ 179 |
| ExplosionParty | Server Explosion Party: every explosion becomes confetti for 10 min, announced with your name (extends, max 30 min) | R$ 99 |

**Game Passes** (`ShopConfig.Passes`, set `PassId`):

| Key | Pass | Display price |
|---|---|---|
| VIP | Gold VIP tag over your head and in chat, 1.5x coins | R$ 299 |
| DoubleCoins | 2x coins | R$ 199 |
| PrismTrail | Exclusive animated rainbow ball trail (cosmetic) | R$ 149 |
| ExtraSlot | 2 ability slots (lobby-only loadout) | R$ 249 |

**Fairness:** nothing sold changes parry timing, ball speed or ability power. Abilities can't be
bought with Robux directly. Robux coins only speed up what free players earn by playing, and the
extra slot gives flexibility, not power.

### Setup steps

1. Publish the place (File, then Publish to Roblox).
2. In Creator Hub, open the experience, then **Monetization**, then **Developer Products**. Create
   the 6 products above, then copy each numeric ID into `ProductId` in
   `src/shared/Config/ShopConfig.lua`.
3. Under **Monetization**, then **Passes**, create the 4 passes and copy each ID into `PassId`.
4. Rebuild and publish. With an ID of 0, a live game says "not available yet".
5. Receipts are de-duplicated per player (PurchaseId stored in the profile and saved before
   PurchaseGranted is returned). If the save fails, NotProcessedYet is returned and Roblox retries.

## Audio

No asset IDs are invented. `src/shared/Config/AudioAssets.lua` reuses IDs from the DEAD AIR
project's licensed-library picks (metal clang for the parry, impact for explosions, terminal beep
for UI and countdown, pickup for coins, stings for win and loss) and one built-in
`rbxasset://sounds/action_jump.mp3`. Empty slots are skipped until you add your own:
`Whiff`, `Confetti`, `Dash`, `FreezeCast`, `SwapWarp`, `LobbyMusic`, `BattleMusic`.

## Publishing checklist

- [ ] Paste every Product and Pass ID, then rebuild.
- [ ] Enable API Services (DataStores) for the published game.
- [ ] Fill the empty audio slots with sounds you own or that are marked usable.
- [ ] Replace the procedural models from POLISH.md if you want, keeping names and orientation.
- [ ] Upload the icon (512x512) and 3 thumbnails (1920x1080) using the POLISH.md prompts.
- [ ] Set Max Players to about 12 to 16 (the round supports up to 16 contestants).
- [ ] Set genre to Fighting / PvP and enable mobile, gamepad and desktop.
- [ ] Do a real multiplayer playtest (see "Not verified").

### Maturity questionnaire suggestions

Violence: mild, stylised and non-graphic. Characters "explode" into neon shards or confetti, with
no blood or gore. Repeated violence: yes, mild. No fear, romance, crude humour, gambling with
real-world value, or alcohol/drugs. **Paid random items: yes.** Premium Spins are a paid
random-item mechanic with the odds displayed in-game, so answer accordingly. Free chat is
Roblox default. The expected result is a 9+ / Mild rating, depending on how Roblox weighs the paid
random items.

## Honest status

**Verified here (no Studio available):**

* `selene src`: 0 errors, 0 warnings.
* `lune run tests/compile`: all 41 source files compile.
* `lune run tests/run`: 34 unit tests on ball homing (including no orbiting at max speed), parry
  window, lag-compensation bounds, mashing versus timed presses, bot decisions, coin math and caps,
  daily streak, codes, crate odds matching the published percentages, and pity.
* `tests/harness.luau` loads the Rojo-built place in Lune against Roblox's reflection database.
  It builds the lobby and every arena, all weapons and bots. It runs the real services with
  stubbed engine services through: a receipt sent twice and granted once, the Studio free grants,
  ability buy/equip, crates and duplicates, codes, daily and invite, junk remote arguments, the
  lobby countdown, a full simulated solo round vs bots (with a timed parry, a whiff, Freeze, Swap,
  a kill feed, confetti during an Explosion Party, and rewards), a ranked 2-player round (with a
  Shield save and a leaver), spectator status, and every client controller rendering real server
  payloads.

**Not verified (needs a Studio playtest):**

* Real physics: character movement, bot walking (Humanoid:MoveTo with a rigless welded bot),
  Dash and Super Jump feel, and flung confetti and shards.
* Network feel: how smooth the client ball prediction is at real latency, and whether the parry
  window and lag-compensation values feel fair. Tune `GameConfig.Parry` and `GameConfig.Ball`.
* Visual layout of the UI on real phones and consoles, and the look of the arenas.
* Real MarketplaceService, DataStore, OrderedDataStore, SocialService and TextChatService
  behaviour.
