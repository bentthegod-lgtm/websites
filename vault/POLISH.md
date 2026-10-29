# VAULT — polish backlog

Everything in the game is built from Roblox parts, so it runs without any uploaded assets. These are the places where real assets would make the biggest difference. Every swap is local to one builder function.

## 1. Asset swaps (Blender → MeshPart)

Keep each mesh's pivot at the base centre so that the spawn points and `LootModels.kit` offsets still line up. Keep the invisible `Hitbox` part as the PrimaryPart.

| Priority | What | Where | Notes |
|---|---|---|---|
| 1 | Stack pieces (notes, bar, gem tray, crate, chest) | `LootModels.pieceBuilders` | These appear on every character; under 300 tris each. |
| 2 | Gold bar / platinum bar (bevelled, stamped) | `LootModels.builders.GoldBar`, `PlatinumBar`, `k.bar` | Use one mesh and tint it. |
| 3 | Deposit machine body and drum | `Machines.deposit` | Keep the part names Chute, Drum, Screen, Lamp1-5 and StatusLight; the client animates them by name. |
| 4 | Elevator cabin and door leaves | `Machines.elevator` | Keep the DoorL/DoorR Models, their PrimaryParts and the `DoorClosedOffset` attribute. |
| 5 | Vault door (ring, leaf, wheel) | `Props.vaultDoor` | Keep the `Leaf` model and its `HingeAxis` part. |
| 6 | Gems (diamond, emerald cuts) | `k.gem`, `k.octo` | Use glass material with a neon core, or SurfaceAppearance. |
| 7 | Landmarks (crane, crystal, obelisk, refinery, sarcophagus, dais) | `Themes.lua` per depth | These are hero props; they can afford more detail. |
| 8 | Artifacts and legendary items (idol, crown, scepter, chest) | `LootModels.builders` | — |

## 2. Textures (ComfyUI prompts)

Use them as SurfaceAppearance ColorMap and NormalMap pairs, 1024², tileable.

- **Vault wall:** "brushed steel wall panels with rivets, bank vault interior, subtle wear, tileable, PBR albedo, neutral lighting"
- **Vault floor:** "polished dark concrete floor with yellow safety lines, slight reflections, tileable, PBR"
- **Banknote:** "stylised green banknote face, no real currency, no text, game asset, flat albedo"
- **Gold bar stamp:** "embossed gold bullion stamp, fictional mint mark, '999.9', game texture, normal map friendly"
- **B6 mosaic:** "ancient stone mosaic floor, terracotta and turquoise, worn, tileable, PBR"
- **B7 carpet:** "royal red velvet carpet with gold border pattern, tileable"
- **Screen glow:** "green LED dot-matrix display background, subtle scanlines, tileable"

## 3. Audio (empty slots)

Every filled sound reuses an id that DEAD AIR already uses; the config test enforces this. The empty slots below play nothing until you set an id in `src/shared/Config/AudioAssets.lua`:

- `MusicTop`: B1–B2 background, calm, light tension, 70–90 BPM
- `MusicDeep`: B3–B5, deeper pads, more pulse
- `MusicLegendary`: B6–B7, orchestral, treasure-hunt mood
- `CoinShower`: a coin cascade for record deposits
- `CrystalChime`: a soft chime for the B3 ambience one-shots

Use only audio you own or that comes from Roblox's licensed library.

## 4. Feel and juice to try in Studio

- Tune the elevator ride time (`ElevatorService.rideTime`) and the counter roll against how a real round trip feels.
- Camera: a small FOV kick on pickup when the stack mode changes.
- Pickup: a squash-and-stretch on the newest stack piece. The `StackController` tween is the hook for it.
- Deposit: a coin-shower particle on a record. Use the `CoinShower` sound once it has an id.
- Mobile: check the PICKUP button's position against Roblox's jump button on small phones, and move it if they overlap.

## 5. Content backlog

- The Ancient Vault complex: `DepthConfig.NextComplex` is the framework, and B7's preview room already teases it.
- More rare events per depth, for example a "vault breach" event in which loot spills out of a rack.
- A second Collection Book page for specials found during events.
