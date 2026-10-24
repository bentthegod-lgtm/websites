# POLISH.md: to-do list for the PC Claude (Blender + ComfyUI)

Everything currently in the game is procedural and built from parts in code. This file lists
what to replace or create, and how to plug it in without breaking gameplay.

Reference renders of the current procedural look: `build/blobbies-preview.png`,
`build/mutations-preview.png`, `build/world-overview.png`, `build/world-base.png`. Re-render
them with `tools/export_blobbies.luau` and `tools/render_preview.mjs` (see README).

## 1. Blender meshes

**General style:** chunky, glossy, toy-like vinyl figures with soft rounded silhouettes, big
expressive eyes and simple colour blocking. Aim for 1.5k to 5k triangles per Blobby. Bake to a
single 512 or 1024 texture or use vertex colours. Keep the **body colour as its own material or
mesh** so the Gold, Diamond and Rainbow mutations can still recolour it (see "How to plug in").
Blobbies face **-Z**, with their feet at Y = 0.

Sizes below are the current in-game bounding boxes (W × H × D in studs) at the rarity scale.
Rarer Blobbies are bigger (Common 1.0x up to Secret 1.66x).

| # | Species | Rarity | Size (studs) | Look to keep |
| --- | --- | --- | --- | --- |
| 1 | Wobbleton | Common | 4.7 × 3.1 × 3.5 | light-blue ball, pale belly, googly eyes, little waving nub arms |
| 2 | Snorkpuff | Common | 3.4 × 4.8 × 3.5 | pink pear shape, tiny eyes with blush, blue beanie with pom, tongue out |
| 3 | Gloopsy | Common | 4.4 × 3.2 × 4.5 | lime-green slime puddle with two eyes on stalks |
| 4 | Bonkus | Common | 3.1 × 4.0 × 3.5 | orange cube, angry brows, buck tooth, propeller beanie (the propeller spins) |
| 5 | Tater Tumble | Uncommon | 2.8 × 6.4 × 3.1 | tall potato, sleepy eyes, top hat, big mustache |
| 6 | Fizzlewick | Uncommon | 4.1 × 5.7 × 4.2 | yellow spiky ball (pink spikes), party hat, antenna |
| 7 | Mumbo Jello | Uncommon | 4.9 × 3.3 × 4.0 | translucent red jelly cube with a grape inside, cyclops eye, jelly arms |
| 8 | Spikelord Pip | Rare | 4.4 × 5.0 × 4.5 | purple spiky ball, angry, viking helmet with horns, red cape |
| 9 | Noodle Nanny | Rare | 2.8 × 8.5 × 5.1 | cream stacked-noodle body, sleepy, chef hat, tail |
| 10 | Captain Squish | Rare | 3.7 × 5.3 × 3.9 | teal ball, sunglasses, navy top hat, bowtie |
| 11 | Disco Dumpling | Epic | 4.8 × 5.8 × 5.0 | white pleated dumpling, shades, purple party hat and bowtie (spins) |
| 12 | Wizzlebop the Wise | Epic | 3.3 × 8.6 × 3.6 | tall indigo, sleepy, crooked wizard hat with glowing star, white mustache |
| 13 | Sir Pancake III | Epic | 5.5 × 3.7 × 6.0 | pancake with syrup and butter, googly eyes, gold crown, monocle |
| 14 | Gigachonk | Legendary | 6.5 × 6.0 × 4.8 | huge green ball, angry, viking helmet, flexing arms |
| 15 | Bubblegum Baron | Legendary | 4.7 × 7.4 × 5.2 | hot-pink pear, cyclops eye, top hat, cape |
| 16 | Lord Wigglesworth | Legendary | 3.3 × 9.5 × 4.3 | orange noodle worm, crown, royal cape |
| 17 | Cosmo Blorbo | Mythic | 7.1 × 6.9 × 5.6 | deep-space purple ball with glowing cyan cyclops eye, halo, antenna |
| 18 | The Grand Gloobini | Mythic | 5.4 × 10.3 × 5.8 | magenta tall wizard, eye stalks, glowing teal wings |
| 19 | Blorbzilla | Secret | 7.9 × 7.0 × 8.5 | charcoal kaiju ball, glowing red spikes and eyes, crown, tail |
| 20 | Void Noodle Supreme | Secret | 6.0 × 11.1 × 6.0 | near-black noodle with neon purple rings, wings, halo |

**Environment pieces:**

| Asset | Size (studs) | Notes |
| --- | --- | --- |
| Pedestal | 5.4 dia × 2.4 tall | marble column, coloured top disc in the plot colour, thin neon ring that turns the rarity colour |
| Collect pad | 4.4 × 0.3 × 2.6 | glowing green pad with a coin/arrow motif, sits 4 studs in front of each pedestal |
| Base shell | 52 wide × 56 deep, walls 14 tall | three walls plus two front segments with a 20-stud entrance; trim in the plot colour; floor inlay |
| Laser door | 20 × 14 opening | two dark metal posts (1.6 × 15.5 × 1.8) with neon strips; 6 laser beams (keep the beams as separate parts) |
| Lock console | 2.4 × 2.6 × 2.4 | sci-fi pedestal with a big red arcade button |
| Base sign | 24 × 3.4 | marquee board above the entrance (text is a SurfaceGui; keep a flat front face) |
| Red carpet | 14 × 330 | velvet carpet with gold edge rails and chevrons; it could get a scrolling texture |
| Blobby Portal | ring radius 9 | swirling arcane ring with a base platform |
| Exit hole | 16 dia | cartoon hole with a "BYE BYE BLOBBIES" arch |
| Boards | 18 × 22 | leaderboard and event board frames (SurfaceGui faces the front) |
| Coin | 2.2 dia × 0.4 | Cash Rain coin |
| Props | | stylised trees, lamp posts, fences, a background skyline/hills |

**How to plug in a Blobby mesh** (in `src/shared/BlobbyModels.lua`):

* Keep the `Root` part (invisible, anchored, at the feet), the `Body` part and the `Bob` Motor6D
  (Root → Body, pivot at the feet). The client animates `Bob.Transform`.
* Replace the parts the shape, eyes, hat and accessory functions create with MeshParts welded to
  `Body`. All parts must stay `CanCollide = false`, `CanTouch = false`, `CanQuery = false` and
  `Massless = true`, because the Blobby gets welded onto a player's head.
* Give the body-colour mesh the attribute `BodyPart = true` so `applyMutation` recolours it.
  Rainbow sets `Rainbow = true` and the client cycles that part's hue.
* Parts that spin (propeller, halo) hang off a `SpinnerHub` with a Motor6D named `Spinner` and a
  `Speed` attribute.
* Keep the `PromptAttachment` and `LabelAttachment` positions roughly at mid-height and above the
  head.
* An easy approach is a lookup `MeshIds[species.Id]`: if it has an ID, clone the MeshPart from
  ReplicatedStorage, otherwise fall back to the procedural build.

## 2. ComfyUI images

**Style for all images:** bright, saturated, glossy 3D cartoon render (Pixar-like toy style),
soft studio lighting, clean shapes, no text unless stated, Roblox-friendly. Use this negative
prompt everywhere: `text, watermark, logo, realistic, gore, blood, scary, dark, blurry, low
quality, extra limbs`.

**Game icon (512×512):**
> Square game icon, a chubby light-blue blob creature with huge googly eyes being carried
> overhead by a sneaky cartoon character running away, a red carpet and glowing portal
> behind, gold coins flying, purple and gold background burst, glossy 3D toy render,
> centered, bold silhouette, high contrast

**Thumbnail 1 (1920×1080), "the heist":**
> Wide action shot, a cartoon blocky character sprinting out of a pastel walled base while
> carrying a glowing golden blob creature over their head, the owner chasing behind with a
> giant cartoon slap hand, red laser door beams, motion lines, coins flying, bright daylight,
> glossy 3D render, dynamic angle

**Thumbnail 2 (1920×1080), "the carpet":**
> A long red velvet carpet with gold rails, a parade of 8 different cute blob creatures
> (round, tall, flat pancake, spiky, jelly cube, noodle worm) waddling out of a swirling
> purple portal, each with a coloured rarity glow (white, green, blue, purple, gold, pink,
> cyan), pastel bases on both sides, sunny sky, glossy 3D toy render

**Thumbnail 3 (1920×1080), "the collection":**
> A pastel pink base full of marble pedestals, each holding a different goofy blob creature
> with hats (top hat, crown, viking helmet, wizard hat), piles of cash on green glowing pads,
> a rainbow-coloured mythic blob in the center with sparkles, confetti, glossy 3D render

**Shop and UI icons (512×512 each, transparent or plain background):**

* Pocket of Cash: a small stack of green cash bills with a coin
* Bag of Cash: a bulging money sack with a dollar sign and coins spilling
* Vault of Cash: an open golden vault overflowing with cash
* Server Luck x2: a glowing four-leaf clover with "x2" sparkles, blue aura
* Mythic Crate: an ornate pink and gold treasure crate glowing, with a mystery blob peeking out
* Lock Base Now: a red laser padlock with a lightning bolt
* 2x Cash: a big golden "2x" made of coins
* VIP: a golden crown with a "VIP" ribbon (text allowed here)
* Auto-Collect: a magnet pulling coins
* Speedy Snatcher: a running shoe with wings carrying a blob
* +3 Pedestals: three marble pedestals with a plus sign
* HUD buttons: shop cart, rebirth (circular arrows with a star), daily gift box, index book,
  codes (ticket), invite (two friends), slap (cartoon hand), lock (padlock), drop (down arrow)
* Rarity badges (256×256): Common to Secret gem shapes in the rarity colours

Upload them as Decals or Images, then use them on the Game Pass and Product pages. In the HUD you
can add `ImageLabel`s with those IDs; the buttons are built in `HudController.buildMenu` and
`MenuController.shopCard`.

## 3. Sounds to fill (`src/shared/Config/AudioAssets.lua`)

* `Music` (empty): upbeat, bouncy tycoon or simulator loop, about 100 to 120 BPM.
* `BlobbySqueak` (empty): a cute squeak or boing when a Blobby lands on its pedestal.
* Worth replacing the reused DEAD AIR horror-ish sounds with cartoon ones:
  * `Slap`: a cartoon slap
  * `StealAlarm`: a comedic siren
  * `StealSuccess` and `Reward`: a short fanfare
  * `CollectCash`: a cash register "cha-ching"
  * `RareSpawn`: magical chimes
  * `EventStart`: an air horn or announcer sting
  * `LockOn` and `LockOff`: laser hum up and down

## 4. Animations (need uploaded Animation assets)

* A slap swing for the slapper (play it client-side in `HudController.slap`).
* Carry pose: both arms up while carrying (play it when the `Carry` remote arrives).
* Optional: a hit flinch on knockback.

## 5. Balance values to tune after playtests

* `GameConfig`:
  * Carpet: `SpawnInterval` 2.6 s, `Speed` 4.5, `MaxOnCarpet` 28
  * Slots: `BaseSlots` 8, `MaxRebirthSlots` 5
  * `Steal`: `CarryTimeout` 45 s, speed multipliers 0.55 and 0.75, `StunAfterSlap` 1.6 s
  * `Slap`: `Range` 10, `Cooldown` 0.9 s
  * `Lock`: 45 s locked, 60 s cooldown
  * `Rebirth`: `BaseCost` 50K, `CostGrowth` 6, +0.5 per rebirth
  * Offline: 50% rate, 3 h cap
  * `Events`: every 15 min, 3 min long
* `RarityConfig` weights (52 / 26 / 13 / 6 / 2.2 / 0.6 / 0.12%).
* `MutationConfig` chances (4%, 1.5% and 0.4%; x2, x3 and x6).
* `BlobbyConfig` prices and incomes. Payback is currently 20 to 60 s per Blobby, which is fast and
  in line with the genre. If players blow through it, make the late tiers 1.5x pricier.
* `RewardConfig` goal rewards: 1 to 8 minutes of income each. These may be generous; consider
  halving them.
* `ShopConfig` cash pack minutes (10 / 45 / 180) against their Robux prices.
