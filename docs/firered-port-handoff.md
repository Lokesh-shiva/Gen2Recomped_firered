# FireRed port — session handoff

Branch `firered-port` in this repo (`D:\gen1recomp-0.1.75-windows\gen2recomp-firered`).
Read this whole file before touching code — it's written so a fresh session
(no prior context) can pick the work back up without re-deriving anything.

Last commits, newest first:
```
550e1bc FireRed: finish League and Sevii progression
0461595 FireRed: elevator window view, Bill's teleporter, S.S. Anne departure
1941926 FireRed: missing art scenes, NPC/clone fixes, HM checks, port card
1ea63de FireRed: own tile behaviours, every script special, Trainer Tower, HoF and credits
e5856cd FireRed-only specials ...
a2a3273 FireRed dungeon map previews ...
```
Nothing has been pushed anywhere. Never push — this is Ceedrack's
personal-use codebase (Gen2Recomped License, see LICENSE.md); commit locally
only. Never commit `tools/rom_manifest_firered.json` (untracked, ROM-derived,
contains the charmap).

## How to build/run/test (read this before doing anything else)

- ROM path: `D:\gen1recomp-0.1.75-windows\firered3d\FireRedLeafGreenRecomp\variants\firered\roms\firered_usa.gba`
  — **not** the "(patched).gba" file in the repo root, that's a different hack
  (Pokémon Adventures Red Chapter).
- `lovec.exe` is at `C:\Program Files\LOVE\lovec.exe` (not on PATH). Use
  PowerShell `Start-Process -PassThru -RedirectStandardOutput/-Error`, then
  `$p.WaitForExit()` — `-Wait` alone is unreliable for seeing full log output
  here.
- Reimport after any `src/import/RomExtractorGen3.lua` or
  `src/script/Gen3SpecialsFRLG.lua` change:
  ```powershell
  $env:POKEPORT_VERSION='firered'; $env:POKEPORT_NO_MODS='1'
  $env:POKEPORT_IMPORT_ONLY='1'; $env:POKEPORT_FORCE_IMPORT='1'
  $env:POKEPORT_IMPORT_ROM='D:\gen1recomp-0.1.75-windows\firered3d\FireRedLeafGreenRecomp\variants\firered\roms\firered_usa.gba'
  & 'C:\Program Files\LOVE\lovec.exe' .
  ```
  Then clear `POKEPORT_IMPORT_ONLY`/`POKEPORT_FORCE_IMPORT` before running a
  driver, or it re-imports every launch.
- Headless test driver:
  `$env:POKEPORT_DRIVER='tests/drivers/_frlg_XXX.lua'` then run lovec the same
  way. Drivers live in `tests/drivers/`, are gitignored, and write PNGs to
  `ngshots/`. Read screenshots back with the Read tool (they render as
  images).
- Test with mods off: always keep `POKEPORT_NO_MODS=1` set.
- Also set `POKEPORT_NO_BOOT_REPORT=1` for drivers/imports. Otherwise a
  previous failed launch can stop on the crash-report screen before the
  driver starts, with empty redirected logs.
- On this Codex Windows host, LÖVE could not initialize its filesystem
  inside the sandbox. Request execution escalation for LÖVE runs; do not
  bypass the sandbox. Keep gameplay windows visible: the user explicitly
  wants to watch automated runs, so do not pass `-WindowStyle Hidden`.
- Git may report differing repository ownership for the sandbox account.
  Read-only Git inspection used a command-local
  `-c safe.directory=D:/gen1recomp-0.1.75-windows/gen2recomp-firered`;
  no global Git configuration was changed.
- Preserve the pre-existing deletion of Android
  `RoundTripLatencyActivity.java` and untracked screenshots/manifest.
- Screenshot cleanup is unnecessary. Do not work around a sandbox denial
  with another shell. Keep filesystem operations in PowerShell and validate
  absolute targets before any recursive deletion or move.
- Existing drivers worth knowing about (all in `tests/drivers/`, all
  gitignored so check they still exist before assuming):
  `_frlg_tiles.lua` (TILE_ONLY=spin,stairs,cycle,fast,furniture,pc,tower),
  `_frlg_events.lua` (EVENT_ONLY=trash,silph,ferry,hof),
  `_frlg_hms.lua` (HM_ONLY=cut,smash,strength,surf,waterfall,bike),
  `_frlg_art.lua` (ART_ONLY=diploma,seagallop,fossil,credits,regionmap,ssanne;
  CREDITS_FAST=1 shortens the credits page durations for testing),
  `_frlg_npcwalk.lua`, `_frlg_card.lua`, `_frlg_audit.lua` (specials
  coverage — needs `FRLG_SPECIALS` env pointing at a scratchpad file listing
  pokefirered's `data/specials.inc`), `_frlg_terrain.lua` (needs `FRLG_MB` =
  path to pokefirered's `metatile_behaviors.h`).

## Reference material

- `D:\gen1recomp-0.1.75-windows\pokefirered` — shallow pret clone, **the**
  ground truth for behaviour. Has real C source with named symbols; far more
  reliable than guessing from ASM.
- `firered3d\FireRedLeafGreenRecomp\variants\firered\symbols\all_symbols.tsv`
  — FireRed's symbol table (address/size/kind/name). Addresses are raw
  `0x08xxxxxx`; this engine's `rom:u8/u32/bytes/lz77` index ROM-file offsets
  with that `0x08000000` prefix **stripped**. A script-label symbol sometimes
  sits one byte early (on the previous script's `0x02`/`0x03` end byte, or a
  string's `0xFE`/`0xFF` terminator) — `RomExtractorGen3:frlgScriptStart`
  handles this, use it for any new script-address work.
- Memory file `firered-port-route.md` (in this Claude installation's memory
  dir) has the accumulated technical notes — symbol addresses, gotchas,
  driver env-var names, etc. Read it if it's available to you.

## What's done and verified (tested in-game, screenshots checked)

- **Import pipeline**: 4,021 scripts decode with 0 failures. Tilesets,
  sprites (386 species × front/back/shiny/icon, all present), trainer pics,
  overworld art, all UI screens (start menu, bag, PC, box storage, Pokédex,
  town map, naming screen, trainer card, summary).
- **All 196 script specials** the FRLG scripts actually call have handlers
  (`src/script/Gen3SpecialsFRLG.lua`) — Trainer Tower, Route 5 Day Care, size
  records (Heracross/Magikarp), Cape Brink tutor, Deoxys puzzle, Icefall Cave
  ice, Five Island resort, Daisy's massage, berry powder shop, PC menu,
  elevator (floor window + list + shake + **window-view metatile cycling**),
  Seagallop ferry + **crossing scene**, Bill's teleporter animation, S.S. Anne
  departure (**fixed; see verification below**), old man catching demo, Hall of Fame,
  credits.
- **Tile behaviours**: 106/111 carried into the engine (the rest have no C
  effect on this cartridge). Spin tiles, Cycling Road pull-down + grass, fast
  water refusal, side stairs (0xEC–0xEF, arrival facing correct), 31
  furniture/sign/PC/TV metatile scripts, ice/waterfall correctly
  distinguished (previously conflated by the shape-based Emerald deriver).
- **HMs tested on real map objects**: Cut, Rock Smash, Strength (was reading
  Emerald's flag, fixed to FireRed's `FLAG_SYS_USE_STRENGTH` = 0x805),
  Waterfall, Surf (FireRed's own "used SURF!" text, not the Game Boy
  fallback), Bicycle (step speed correct).
- **NPC/object fixes**: FireRed's "clone" objects (`kind == 255` in the
  imported map data — off-map stand-ins so a neighbour's NPC shows across a
  map seam) were being spawned as real, frozen, walk-through duplicates —
  this is what caused the "duplicated fat man in Pallet Town" bug. Fixed in
  `objectVisible` (`src/world/OverworldController.lua`) and in the
  neighbour-ghost spawner (`rebuildNeighbors`) — clones never spawn, and an
  off-map neighbour object is never turned into a ghost either (the
  neighbour's own real object already covers it).
- **Trainer Tower**: floors/trainers/prizes read from ROM
  (`extractFireRedTrainerTower`), challengers now actually appear on their
  floor (fixed a post-transition object-sync ordering bug — a script that
  finishes *inside* `run()` rather than being polled the next frame wasn't
  triggering the entity resync), battle pics draw in true colour (was being
  squashed through the Game Boy 4-shade SGB remap — affects **all** Gen 3
  trainer battles, not just the tower; fixed in
  `BattleState.trainerPalette`).
- **Hall of Fame**: full FireRed-specific ceremony
  (`src/ui/Gen3HallOfFameFRLG.lua`) — team flies in one at a time with cries
  and stat lines, confetti, player walks in, NAME/IDNo./TIME window,
  "LEAGUE CHAMPION! CONGRATULATIONS!".
- **Credits**: full FireRed-specific roll (`src/ui/Gen3CreditsFRLG.lua`) —
  runs the actual `sCreditsScript` read from ROM, city fly-over maps with the
  player/rival running sprite, starter POKé BALL reveal scenes, copyright
  card, THE END.
- **Diploma, museum fossil pictures, town-map SWITCH button for Sevii
  pages** — all drawn from ROM-extracted art (`extractFireRedExtraArt`,
  `constants.gen3FRLGArt`).
- **Port splash card** added before the GAME FREAK logo
  (`src/ui/Gen3IntroFRLG.lua`, `Gen3IntroFRLG:drawCard`) — names the engine,
  Ceedrack, the port author, and states it's an unaffiliated fan project. No
  Nintendo/GAME FREAK marks used. Override text via
  `data.field.boot.studio = { credit=, author=, portAuthor=, year=, notice=,
  notice2= }`.

## S.S. Anne departure — fixed and verified 2026-09-16

The earlier movement-only diagnosis was incomplete. The ship's 128x64
frame stores four consecutive 64x32 OAM pieces. Decoding those bytes as one
row-major 128x64 image scrambled the artwork before it ever moved.

- `RomExtractorGen3:overworldFramePixels` now composes oversized object
  frames from their ROM subsprite tables (signed coordinates, shape/size,
  and tile offsets). Ordinary sprites retain their existing decode path.
- Special 401 uses a visual `shiftPx`, consumed by `NPC:pose` and the
  billboard anchor. The map/collision coordinates remain stationary, as
  they do in the cartridge's `x2` animation. Horizontal movement does not
  change y sorting; true-color redraw and reflections consume the pose.
  Terrain/collision/sight checks retain map coordinates intentionally.
- The cutscene now uses `runner.waitingCheck`. The old detached field task
  was invisible to the stuck-script watchdog, which could cancel the scene
  at 720 frames. The off-screen check uses the shifted sprite centre.

Verification: `tests/parity_frlg_ship.lua` passes 6 checks, including
synthetic four-piece ROM composition, unchanged map position, visual speed,
live wait registration and eventual completion. Before the fixes, the
composition check and three departure assertions failed.

After a full forced ROM reimport, `tests/frlg_ship_driver.lua` completed
the actual departure script and returned to Vermilion with scene variable
0x407E = 2 after 1,410 driver frames. Screenshots
`ngshots/ship_fixed_{180,480,900,1200,return}.png` show the intact ship and
the return to the dock. The early/mid-departure and return screenshots were
read back. Import: 4,021 scripts; 152 overworld sheets, zero unreadable.
Smoke and wake effects remain pending.

## Gym progression and Psychic category — verified 2026-09-16

The gym coverage now has both halves: the existing leader driver verifies
all eight real battle/reward chains, and `tests/frlg_gym_puzzles_driver.lua`
starts at every gym entrance and reaches the leader through the real map
mechanics.

`tests/frlg_gyms_driver.lua` separately passed each leader's defeated flag,
badge flag, TM reward flag, exactly one awarded TM, and completed script:
Brock TM39, Misty TM03, Surge TM34, Erika TM19, Koga TM06, Sabrina TM04,
Blaine TM38, and Giovanni TM26.

- Brock and Misty: complete collision-correct walkways, including trainer
  sight battles. The driver pathfinder uses `Collision.canMove`, so Cerulean's
  elevation/directional walkway rules are exercised rather than bypassed.
- Surge: reads the two randomized switch positions initialized by
  `SetVermilionTrashCans`, interacts with both trash cans, and crosses the
  opened electric barrier.
- Erika: uses Cut on the required tree and traverses the hedge/trainer route.
- Koga: solves the invisible-wall collision maze.
- Sabrina: uses a legal four-pad route to the central room and avoids crossing
  unintended pads while moving within each room.
- Blaine: answers all six quiz machines correctly (YES, NO, NO, NO, YES, NO),
  opening each door before advancing.
- Giovanni: plans around the actual FRLG arrow and stop tile behaviours and
  lets the runtime perform every forced spinner movement.

The combined run passed all 8 routes. The eight final-position screenshots
`ngshots/gym_puzzle_{Brock,Misty,Surge,Erika,Koga,Sabrina,Blaine,Giovanni}.png`
were read back and show the player at each leader with the puzzle route open.
Use `POKEPORT_DRIVER=tests/frlg_gym_puzzles_driver.lua`,
`POKEPORT_SPEED=8`, and optionally `GYM_ONLY=<leader>`.

The `PSYCHC has no category` warning was a registry rebuild bug, not bad ROM
extraction. `data/generated/type_chart.lua` had the correct `special` category,
but `TypeChart.registerInto` registered only the built-in Gen 1 names; the mod
catalog rebuild then discarded generated Gen 3 records such as `PSYCHC`,
`ELECTR`, and `FIGHT`. It now registers the generated type table when present
and falls back to the built-in table for older datasets. The focused regression
`tests/parity_gen3_type_categories.lua` passes 3/3. The combined gym run used
PSYCHIC throughout many real trainer battles and emitted no missing-category
warning.

## Team Rocket progression and traversal — verified 2026-09-16

This group is closed. Two visible drivers cover both story scripts and
physical routes.

`tests/frlg_rocket_driver.lua` passes the real Game Corner grunt/poster reveal;
Hideout Lift Key, both B4F guards, Giovanni and Silph Scope; Silph Card Key,
7F rival, Lapras gift, 11F Giovanni, and the president's Master Ball.

`tests/frlg_rocket_traversal_driver.lua` covers everything that remained:

- all four Mt. Moon Rocket grunts, Super Nerd Miguel, the real YES choice on
  the Dome Fossil, the fossil item, and both completion flags;
- a physical Game Corner machine interaction, three-coin bet, spin, three reel
  stops, result, and clean return to the overworld;
- the actual Silph 5F Card Key item ball, a 2F barrier script, its door flag,
  and walking through the cells that were blocked before the door opened;
- the open poster's real warp followed by collision- and spinner-aware travel
  through Hideout B1F, B2F, B3F, and B4F using each floor's real stair warp.

The slot run exposed a FireRed cache gap: `extractSlotMachine` previously
recognized only Emerald's reel layout, so FireRed's `playslotmachine` command
returned without opening a screen. The FireRed branch now imports its 3x21
reel table, seven payout classes, per-symbol palettes, reel art, digits, and
background from the cartridge. `Gen3Slots` applies FireRed's asymmetric cherry
and grouped Pokemon payout rules while preserving the Emerald rules. A forced
ROM reimport completed with 4,021 scripts and reported `3 reels, 7 symbols, 7
payouts, 9 pictures`.

The final visible traversal run and separate story regression both exited
successfully. Screenshots were read back for Mt. Moon, the slot screen/result,
the crossed Card Key barrier, B4F arrival, the poster staircase, and Silph's
president room. Logs: `ngshots/rocket_traversal.log` and
`ngshots/rocket_progression.log`.

The Mt. Moon Rocket grunt and Super Nerd battles also exposed a shared battle
placement bug. FireRed's cave backdrop has edge detail on rows away from the
platform surface; the scanner used those rows' horizontal extremes while using
the surface row's height, shifting opponent trainers and Pokemon left toward
the HP panel. `measurePlatforms` now keeps x bounds and y from the same widest
platform row. `tests/frlg_mtmoon_battle_placement_driver.lua` visibly checks
both encounters at the trainer and Pokemon phases; the measured centers are
now opponent `175.5` and player `63.5`, matching the drawn cave platforms.
Screenshots: `ngshots/mtmoon_rocket_trainer.png`,
`ngshots/mtmoon_rocket_mons.png`, `ngshots/mtmoon_scientist_trainer.png`, and
`ngshots/mtmoon_scientist_mons.png`.

## League and Sevii regression coverage — verified 2026-09-17

FireRed's League import uses raw group-and-number map IDs while the story
layer uses named rooms. `Data:seedDefaults` now aliases the six League maps,
binds the imported Elite Four objects to their story text and names Lance and
the Champion objects for their scripted entrances. It also exposes the three
imported original-Champion parties (`TERRY_438` through `TERRY_440`) as the
shared `OPP_RIVAL3` class in starter order.

Visible runs passed Lorelei, Bruno, Agatha and Lance with their victory flags;
the Champion driver then entered from Lance's room, fought the imported rival
party and set `EVENT_BEAT_CHAMPION_RIVAL`. The Hall of Fame driver consumed
the Champion handoff marker and recorded the team. It explicitly vetoes the
save callback, so no test writes the player's real save.

`tests/frlg_champion_driver.lua` and `tests/frlg_hall_of_fame_driver.lua`
hold those regressions. `DoPokemonLeagueLightingEffect` remains visually a
no-op, but it does not prevent the battle or ceremony progression.

`tests/frlg_sevii_progression_driver.lua` passed the imported FireRed special
paths for Cape Brink's fully-friendly Blastoise tutor selection and reward
flag, Resort Gorgeous's requested species/reward selection, all eleven Birth
Island triangle touches through Deoxys awakening, Icefall Cave's persisted
cracked ice, and Trainer Tower's eight floor initializations, timer record and
prize. This coverage operates on an isolated fresh save and does not write to
disk.

## Launcher and developer-console regressions — verified 2026-09-17

FireRed is now an official launcher tab before Emerald, with its own
red-orange accent. It is included in `GameVersion.ORDER`, so readiness,
import, save-slot selection and the launcher counter all use the same version
list. `tests/firered_launcher_driver.lua` verifies its placement and
importability.

The developer console no longer synthesizes printable keys from key names.
`love.textinput` is forwarded through `Game` to the active overlay, which
preserves Caps Lock, keyboard-layout symbols, composed text and paste.
`tests/console_textinput_driver.lua` asserts an uppercase identifier with an
underscore reaches the console unchanged.

## Not yet done / not yet tested this playthrough

Ordered roughly by what blocks a real playthrough:

1. **Flash and Fly HMs** — not driven by any test yet (Cut/Rock
   Smash/Strength/Surf/Waterfall/Bike were).
2. **Poké Flute / Snorlax, VS Seeker, Safari Zone, save/load round-trip** —
   none of these have been touched this pass; unknown state.
3. **Diagonal side-stair walk-in animation** (`ExitStairsMovement` in
   pokefirered `field_fadetransition.c`) — arrival facing is correct but the
   16-frame walk-in slide itself isn't drawn.
4. **Credits' mon silhouette/circle-zoom reveal** — currently draws a plain
   shrinking white circle instead of the three-silhouette-then-reveal effect
   `DoCreditsMonScene` does.
5. **S.S. Anne wake trail + smoke puffs** during the departure (separate
   from the sprite-corruption bug above — even once the ship moves cleanly,
   `CreateWakeBehindBoat`/`CreateSmokeSprite` aren't reproduced).

## Start-flow reports checked — one closed, one was a real bug (fixed) — 2026-09-17

The two items logged in the previous version of this section were re-checked
this session by actually running the flow and reading back real screenshots
(not just reading code).

1. **"Start menu entries missing (expected NEW GAME, OPTIONS, EXIT)"** — not
   a bug. Ran `tests/drivers/_frlg_title.lua`
   (`POKEPORT_DRIVER=tests/drivers/_frlg_title.lua`), read back
   `ngshots/title_menu.png`: it shows `CONTINUE` (with PLAYER/POKéDEX/TIME/
   BADGES filled in from the save) and `NEW GAME`, both rendering correctly.
   **This is cartridge-accurate** — real FireRed's main menu (pokefirered
   `main_menu.c`) only ever has CONTINUE + NEW GAME; OPTION lives inside the
   in-game START menu once you're playing, not on this screen, and a GBA
   cartridge has no EXIT at all. `src/ui/Gen3MainMenu.lua` already documents
   this in its own header comment and deliberately skips OPTION/EXIT for
   `GameVersion.get() == "firered"` (see the `~= "firered"` check, ~line 94).
   Whoever filed the original report was likely expecting Emerald's four-row
   menu and flagging FireRed's genuinely-shorter one as broken.
2. **"Player sprite missing during name entry"** — real bug, now fixed. The
   **Oak-speech naming sequence** (`src/ui/Gen3OakSpeechFRLG.lua`, the
   "which one is right for you?" platform scene) was never the issue — it
   already showed the player's trainer sprite correctly (verified via
   `tests/drivers/_frlg_newgame.lua`, `ngshots/frlg_ng_015.png` and
   `ngshots/frlg_ng_024.png`).

   The actual bug was the **keyboard-typing screen** (`src/ui/NamingScreen.lua`).
   A first pass this session grepped pokefirered's `naming_screen.c` for
   "Pic"/"Sprite" only, found nothing, and wrongly concluded the cartridge
   draws no portrait there at all — that conclusion was wrong and got
   committed to this doc. The user corrected it directly after seeing the
   actual screen: *"in keyboard typing there's only a green patch.... above
   that there should be player sprite and if pokemon name is typing then the
   pokemon sprite."* A broader grep (`MonIcon\|OBJ_EVENT\|PlayerAvatar\|Icon`)
   found the real dispatch table, `sIconFunctions` in `naming_screen.c`:
   `NamingScreen_CreatePlayerIcon` draws the player's own overworld walk
   sprite (south-facing stand frame) next to the question when naming the
   player or rival, and `NamingScreen_CreateMonIcon` draws the species'
   bouncing party icon when giving a Pokémon a nickname. This port's
   `src/ui/NamingScreen.lua` had never drawn either — the plate's background
   tiles decode fine (including the green ground-shadow ellipse the icon
   normally stands on), but nothing was ever drawn on top of it, so the
   ellipse sat empty.

   **Fix**: `NamingScreen` now takes `opts.kind` (`"player"` or `"mon"`,
   plus `opts.species`/`opts.mon` for the mon case) and draws the
   corresponding icon over the plate in both `drawFireRed` and `drawGen3`.
   The player icon resolves the current gender's overworld walk sheet the
   same way `Player:refreshForm` does (`Sprites.playerForm` +
   `FieldDefaults.fieldValue(data, "playerSprites", "walk")`), crops its
   south-facing standing frame (frame 0), and draws it directly — Gen 3
   overworld sheets import as `trueColor = true` full-RGBA PNGs
   (`RomExtractorGen3:extractOverworldSprites`), so no palette remap is
   needed outside the world-render pipeline. The mon icon reuses the exact
   resolution `Gen3PartyMenu:iconFor` uses (`data.icons.bySpecies` /
   `data.pokemon[species].icon`, through the `pokemon.icon` mod seam) and
   the same two-frame bounce. Wired through every real call site:
   `Gen3OakSpeechFRLG.lua`'s player-naming call (`kind = "player"`; rival
   naming intentionally left without an icon — the dedicated rival
   overworld sheet `naming_screen.c` uses isn't extracted by this port, and
   showing the wrong sprite would be worse than showing none), and the two
   nickname sites in `Gen3Commands.lua` plus the caught-mon nickname site in
   `BattleState.lua` (all `kind = "mon", mon = mon`).

   Verified by pushing `NamingScreen` directly with each `kind`
   (`tests/drivers/_frlg_keyboard_check.lua` for `"player"`,
   `tests/drivers/_frlg_nickname_check.lua` for `"mon"`) and reading back
   `ngshots/keyboard_check_01.png` (Red standing on the ground-shadow patch,
   full colour) and `ngshots/nickname_check_01.png` (Charizard's party icon
   in the same spot). Icon placement (centred at GBA pixel x=56, bottom
   anchored around y=52) is an estimate from pokefirered's OAM coordinates
   for `NamingScreen_CreatePlayerIcon`/`CreateMonIcon` (`~(56,37)`/`~(56,40)`)
   rather than a pixel-exact port of the OAM tables; it reads correctly in
   the screenshots but is worth a closer look if it ever looks off by a few
   pixels against real hardware.

Lesson for next time a "missing sprite/menu row" report shows up: check the
**real cartridge's own layout** (pokefirered source) before assuming this
port is wrong — FireRed's screens are frequently *shorter* than Emerald's
equivalents by design, not broken.

## Process notes for whoever picks this up

- **Always verify with a driver + screenshot read-back**, not just by
  reading the code. Several bugs this session (Trainer Tower not spawning,
  trainer pics wrong colour, the clone-object duplicate) were only found by
  actually looking at rendered output — the code read as plausible in
  isolation.
- When adding a new FRLG-only special, check `pokefirered/data/specials.inc`
  for the exact index and `pokefirered/src/*.c` for the real C function
  (grep by name) before writing the handler — don't guess behaviour.
- Never commit `tools/rom_manifest_firered.json`.
- The retained regression files include (`tests/parity_frlg_ship.lua`,
  `tests/parity_gen3_type_categories.lua`, `tests/frlg_ship_driver.lua`,
  `tests/frlg_gyms_driver.lua`, `tests/frlg_gym_puzzles_driver.lua`,
  `tests/frlg_rocket_driver.lua`,
  `tests/frlg_rocket_traversal_driver.lua`, and
  `tests/frlg_mtmoon_battle_placement_driver.lua`,
  `tests/frlg_champion_driver.lua`, `tests/frlg_hall_of_fame_driver.lua`, and
  `tests/frlg_sevii_progression_driver.lua`,
  `tests/firered_launcher_driver.lua`, and
  `tests/console_textinput_driver.lua`) have narrow `.gitignore` exceptions
  so they can be retained; other scratch tests stay ignored. Changes from
  2026-09-16 are uncommitted.
- Loose top-level `frlg_*.png` files in the repo root are old manual
  screenshots from earlier sessions, not driver output — ignore/clean them
  up if they get in the way, they're not tracked and not load-bearing.
