# Overnight build report

Four new Roblox games, each built from code with a Robux shop, plus DEAD AIR from before.
Everything is on GitHub: `bentthegod-lgtm/websites`, branch `claude/new-game-yhhbwg`.

| Game | Folder | Genre (inspired by) | Checks |
|---|---|---|---|
| **Snatch a Blobby** | `snatch-tycoon/` | steal-and-tycoon (Steal a Brainrot) | lint 0 · compile 41/41 · unit 37/37 · harness 26/26 |
| **Sprout Valley** | `sprout-valley/` | real-time farming (Grow a Garden) | lint 0 · compile 42/42 · unit 43/43 · harness 25/25 |
| **Rebound Rumble** | `rebound-rumble/` | parry-ball PvP (Blade Ball) | lint 0 · compile 41/41 · unit 34/34 · harness 22/22 |
| **PHONES AWAY!** | `phones-away/` | high-school test cheating with your phone (Cheating During Testing) | lint 0 · compile 47/47 · unit 53/53 · harness 39/39 |

I reran every check myself after each game was built, after its bug review, and after my
own fixes.

## How each game was made
1. **Built:** each game copies the structure, tests and shop pattern from DEAD AIR.
2. **Reviewed:** a separate reviewer then hunted for runtime bugs and exploits and fixed the
   confirmed ones:
   * purchases that wouldn't save in a live game now wait and are retried instead of being
     lost;
   * DataStore session locks stop lost progress when a player quickly server-hops;
   * players who join when every base or plot is taken are now queued for the next free one;
   * a dead player no longer joins a round, and the ball no longer gets stuck after a Shield
     save;
   * the bot rigs, a UI leak and mobile button overlap are fixed.

## What every game has
* A Robux shop with Developer Products and Game Passes. All IDs are `0` until you create
  them in Creator Hub. With an ID of `0`, Studio grants the item for free (for testing) and a
  live game says "not available yet".
* DataStore saving with a session lock, receipt de-duplication, and autosave on leave and
  shutdown.
* Studio play-tests save to separate `_Studio` DataStores, so free test purchases never
  reach live data or the leaderboards.
* Retention features: daily login streak, codes (`RELEASE` and others), a global leaderboard
  board, friend invites, session goals, server-wide announcements, and rarity tiers.
* Mobile, gamepad and keyboard controls.
* `README.md` (how to play, shop setup, publishing checklist, honest status) and
  `POLISH.md` (Blender models to remake, ComfyUI prompts for the icon, thumbnails and shop
  icons, sound slots to fill, balance values).

## Not verified (no Roblox Studio here)
Real physics, how it feels to play, UI layout on real phones, the real purchase prompts,
DataStore limits, and performance with full servers. **Play-test each game in Studio
before publishing:** solo first, then Test → Clients and Servers with 2–4 players.

## Prompt for the Claude on your PC
> This folder has four Roblox games (snatch-tycoon, sprout-valley, rebound-rumble, phones-away). Read
> OVERNIGHT-REPORT.md and each game's README.md and POLISH.md. Help me playtest them in
> Studio with `rojo serve`, fix bugs I report, then work through POLISH.md: make the
> Blender models and generate the ComfyUI icon and thumbnails.
