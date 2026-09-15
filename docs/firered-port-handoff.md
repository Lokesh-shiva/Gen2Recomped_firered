# FireRed port — session handoff

Branch `firered-port` in this repo (`D:\gen1recomp-0.1.75-windows\gen2recomp-firered`).
Read this whole file before touching code — it's written so a fresh session
(no prior context) can pick the work back up without re-deriving anything.

Last commits, newest first:
```
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
- **PowerShell gotcha:** `Remove-Item` on paths starting `C:\Program...` gets
  blocked by the sandbox even when the actual target is fine — don't rely on
  it to clean `ngshots/`; just let old screenshots accumulate or use `del`
  via `cmd /c`.
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
  departure (**see bug below**), old man catching demo, Hall of Fame,
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

## Known regression: S.S. Anne departure sprite is corrupted — **not fixed**

**Symptom** (confirmed via `_frlg_art.lua` ART_ONLY=ssanne,
`ngshots/art_ssanne_*.png`): the ship sprite tears/garbles as it slides off
screen instead of moving as one clean sprite.

**Root cause, found this session but not yet fixed**: in
`src/script/Gen3SpecialsFRLG.lua`, special 401 (`DoSSAnneDepartureCutscene`)
directly overwrites `boat.px` every frame:

```lua
boat.px = startPx - math.floor(moved / 5)
boat.shiftPx = -math.floor(moved / 5)
```

But `NPC.px`/`NPC.py` are **not** free-standing render coordinates in this
engine — they're tightly derived from `cellX * 16` / `cellY * 16` plus a
small in-progress-step delta everywhere else in `src/world/NPC.lua` (see
lines ~481, ~644–689). Nothing else that reads the boat's position —
collision, grass/tile overdraw redraw regions keyed by `cellX`/`cellY`,
sprite priority/z-ordering, any palette-zone marking keyed by cell — knows
about this manual `px` override, so those systems keep acting on the boat's
original cell while the sprite itself is drawn hundreds of pixels away. That
mismatch is what produces the "jumbled" look — different subsystems are
drawing/compositing the sprite against stale per-cell state.

**Fix approach for next session**: don't hand-roll a `px` override loop.
Either:
1. Use the existing `scriptMove`/step-offset mechanism the rest of the
   engine's scripted movement uses (search `OverworldState:scriptMove` in
   `OverworldController.lua`) so the position update goes through the same
   path as every other moving NPC, keeping `cellX`/`cellY` and the render
   delta in sync — likely means repeatedly nudging the boat's `cellX` in
   real map cells rather than raw pixels, or
2. If a true off-cell "slide anywhere" motion is needed (the boat genuinely
   travels many screens, further than a cell-based mover was designed for),
   add a dedicated sprite-only offset field (e.g. `shiftPx`) that
   `SpriteRenderer:draw`/`NPC:draw` honours **in addition to** `cellX*16`,
   and audit every other place that reads `npc.px`/`npc.py` directly
   (grass-overdraw markers, `Collision.occupied`, sight-line checks) to make
   sure they don't also need the offset or are explicitly skipped for this
   NPC while the cutscene runs.
Check how the credits scene's player/rival running sprite
(`src/ui/Gen3CreditsFRLG.lua`, `C:loadSprite`/`C:update`) moves — that one is
a **UI-owned sprite**, not a world NPC, so it can freely set its own `x`
without this conflict; it's a model for "sprite that just slides across the
screen" but the S.S. Anne boat is a real map NPC (`LOCALID_SS_ANNE`) so the
same trick can't be copied verbatim without picking one of the two options
above.

**Suggested restart prompt** for the next session (paste as-is, or
paraphrase):

> Read docs/firered-port-handoff.md in gen2recomp-firered (branch
> firered-port). Fix the S.S. Anne departure sprite corruption described
> under "Known regression" — special 401 in src/script/Gen3SpecialsFRLG.lua
> is overwriting boat.px directly instead of going through the engine's
> normal NPC movement path, which desyncs it from cellX/cellY-derived state
> elsewhere (collision, grass overdraw, etc.) and tears the sprite. Fix it
> properly (likely via scriptMove or a dedicated render-only offset field
> that every consumer of npc.px/py is audited against), verify with
> POKEPORT_DRIVER=tests/drivers/_frlg_art.lua ART_ONLY=ssanne and read back
> the ngshots/art_ssanne_*.png screenshots to confirm the ship moves as one
> clean sprite. Then continue down the "Not yet done" list below, testing
> each gym/story beat the same way (real driver, real screenshots, read them
> back — don't just assume code is correct from reading it).

## Not yet done / not yet tested this playthrough

Ordered roughly by what blocks a real playthrough:

1. **No gym has been run through its actual scripts yet** — Brock, Misty,
   Lt. Surge, Erika, Koga, Sabrina, Blaine, Giovanni. Same method as the
   Vermilion trash cans (`_frlg_events.lua` EVENT_ONLY): teleport to the map,
   run the real script/trainer battle chain via `gen3RunFieldScript` or by
   walking triggers, screenshot, verify against pokefirered's own
   `data/scripts/<GymName>.inc`.
2. **Team Rocket**: Mt. Moon, the Game Corner, Rocket Hideout (spin tiles are
   fixed but the full script chain — card key doors, Giovanni fight — is
   untested), Silph Co (elevator alone is verified; the full
   floor-by-floor Rocket-executive chain up to Giovanni is not), Rocket
   Game Corner slot machine.
3. **Elite Four + Champion room**: untested end to end; the
   `DoPokemonLeagueLightingEffect` special is currently a no-op.
4. **Sevii Islands story content**: written but not played through — Cape
   Brink tutor, Icefall Cave ice puzzle, Deoxys triangle (Birth Island),
   Trainer Tower full climb + prize/time board, Resort Gorgeous.
5. **Flash and Fly HMs** — not driven by any test yet (Cut/Rock
   Smash/Strength/Surf/Waterfall/Bike were).
6. **Poké Flute / Snorlax, VS Seeker, Safari Zone, save/load round-trip** —
   none of these have been touched this pass; unknown state.
7. **Diagonal side-stair walk-in animation** (`ExitStairsMovement` in
   pokefirered `field_fadetransition.c`) — arrival facing is correct but the
   16-frame walk-in slide itself isn't drawn.
8. **Credits' mon silhouette/circle-zoom reveal** — currently draws a plain
   shrinking white circle instead of the three-silhouette-then-reveal effect
   `DoCreditsMonScene` does.
9. **S.S. Anne wake trail + smoke puffs** during the departure (separate
   from the sprite-corruption bug above — even once the ship moves cleanly,
   `CreateWakeBehindBoat`/`CreateSmokeSprite` aren't reproduced).

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
- Loose top-level `frlg_*.png` files in the repo root are old manual
  screenshots from earlier sessions, not driver output — ignore/clean them
  up if they get in the way, they're not tracked and not load-bearing.
