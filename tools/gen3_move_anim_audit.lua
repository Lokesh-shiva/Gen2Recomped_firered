-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- EVERY EMERALD MOVE, AGAINST WHAT THE CARTRIDGE'S OWN SCRIPT ASKS FOR.
--
-- Reported from play: "go through all of the pokemon emerald moves and ensure
-- theyre rendering properly a lot of them seem messed up still they should
-- render the moves like they are in the rom".
--
-- THE PROBLEM WITH "A LOT OF THEM SEEM MESSED UP" is that it cannot be acted on
-- until it is counted.  `src/import/RomExtractorGen3.lua` reads move animations
-- out of the real ROM and recognises each visual task by ADDRESS, verifying the
-- function by disassembling it -- which is the right way round, and is why what
-- it extracts can be trusted.  But a `createvisualtask` whose pointer is in no
-- table is SILENTLY NOTHING: the move comes out quiet and no record is left that
-- anything was dropped.  There is no self-report, by construction.
--
-- So this reads the other end.  `tools/gen3_anim_expect.lua` is the cartridge's
-- whole script list, transcribed from pret/pokeemerald (which builds byte-for-
-- byte to the retail ROM, so the scripts are the cartridge's, with the functions
-- NAMED rather than only addressed).  This tool subtracts the dataset from it and
-- names every move whose script asks for an effect the dataset carries nothing
-- for.
--
-- IT IS A RATCHET, NOT A PASS/FAIL.  Every number below is expected to be
-- non-zero today; BASELINE records what it was when this was written, and the
-- tool fails if a count goes UP.  Lower a baseline in the same commit that fixes
-- the moves, so a later change cannot quietly undo the work.
--
-- WHAT IT CANNOT TELL YOU.  That an effect is present is not that it is right:
-- a shake of the wrong battler, or four frames where the cartridge has twenty,
-- satisfies the class test here.  This measures PRESENCE per class.  The values
-- are what `RomExtractorGen3` verifies against the ROM itself.
--
-- Usage: texlua tools/gen3_move_anim_audit.lua [path/to/emerald/data/generated]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local Expect = dofile(root .. "gen3_anim_expect.lua")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

-- ---------------------------------------------------------------------------
section("1. the transcribed script table is well formed")
-- ---------------------------------------------------------------------------
-- The table is generated, so the thing worth checking is that it survived
-- generation -- a truncated write or a mangled row would otherwise read as "the
-- cartridge asks for nothing here", which is the one answer that cannot be
-- distinguished from a clean dataset.
local MOVES = Expect.MOVES
local rows, taskRows, withSprites = 0, 0, 0
for name, row in pairs(MOVES) do
  rows = rows + 1
  ok(type(name) == "string" and name ~= "", "a row has no move key")
  ok(type(row.sprites) == "number" and row.sprites >= 0,
     "%s has no sprite count", tostring(name))
  if (row.sprites or 0) > 0 then withSprites = withSprites + 1 end
  if row.tasks then
    taskRows = taskRows + 1
    ok(type(row.tasks) == "table" and #row.tasks > 0,
       "%s carries an empty task list, which is not the same as no tasks", name)
    for i, t in ipairs(row.tasks or {}) do
      ok(type(t) == "table" and type(t[1]) == "string" and t[1] ~= "",
         "%s task %d has no name", name, i)
      for j = 1, #t do
        ok(type(t[j]) == "string", "%s task %d argument %d is not a string",
           name, i, j)
      end
    end
  end
end
io.write(("  %d moves, %d with a visual task, %d that spawn a particle\n")
         :format(rows, taskRows, withSprites))
-- 354 is what Emerald's gBattleAnims_Moves holds once MOVE_NONE and the COUNT
-- sentinel are dropped, and it is also what the dataset carries. A count that
-- has drifted means the transcription and the dataset no longer line up, and
-- every "missing" below would then be an artefact of the mismatch.
ok(rows == 354, "the table holds %d moves; Emerald has 354", rows)
ok(taskRows > 250, "only %d moves carry a task; the cartridge gives most of them "
   .. "at least a shake", taskRows)

-- ---------------------------------------------------------------------------
section("2. the dataset")
-- ---------------------------------------------------------------------------
local dataRoot = arg and arg[1] or "G:/Gen2Recomped/emerald/data/generated"
local path = dataRoot .. "/moves.lua"
local chunk, err = loadfile(path)
if not chunk then
  io.write(("  cannot read %s\n  %s\n"):format(path, tostring(err)))
  io.write("\n  Pass the generated Emerald data root as the first argument.\n")
  io.write(("\n%d checks, %d failed (the dataset half did not run)\n")
           :format(checks, fails))
  os.exit(fails == 0 and 2 or 1)
end
local moves = chunk()
local nData = 0
for _ in pairs(moves) do nData = nData + 1 end
io.write(("  %s: %d moves\n"):format(path, nData))
ok(nData == rows, "the dataset has %d moves and the script table %d", nData, rows)

-- ---------------------------------------------------------------------------
section("3. what the script asks for, and what the dataset carries")
-- ---------------------------------------------------------------------------
-- BY CLASS, not by task name.  The dataset does not record which cartridge
-- function a record came from -- it records the EFFECT, already reduced to
-- numbers the renderer can walk -- so the only honest question is whether
-- anything of the right kind is there at all.
local function has(s, sub) return s:find(sub, 1, true) ~= nil end
local CLASSES = {
  { name = "shake",
    wants = function(t) return has(t, "Shake") or has(t, "RockMonBackAndForth") end,
    keys = { "shakes", "shake" },
    what = "the hit reaction -- the struck Pokemon jerking" },
  { name = "blend",
    wants = function(t)
      return has(t, "Blend") or has(t, "PaletteFade") or has(t, "ColorCycle")
         or has(t, "Grayscale") or has(t, "InvertScreen") or has(t, "Flash")
         or has(t, "MetallicShine")
    end,
    keys = { "blends", "whiteout", "scanlines", "flash", "variants" },
    what = "the tint or flash over the mon or the screen" },
  { name = "scale",
    wants = function(t)
      return has(t, "Scale") or has(t, "Grow") or has(t, "Stretch")
         or has(t, "Squish") or has(t, "Swell")
    end,
    keys = { "scale", "affineTasks", "affine", "variants" },
    what = "the mon growing or being squashed" },
  { name = "translate",
    wants = function(t)
      return has(t, "Translate") or has(t, "Sway") or has(t, "Lunge")
         or has(t, "Splash") or has(t, "SlideMon") or has(t, "Hop")
         or has(t, "Bounce")
    end,
    keys = { "heaves", "orbit", "affineTasks" },
    what = "the ATTACKER moving -- the lunge that makes a contact move read" },
  { name = "rotate",
    wants = function(t) return has(t, "Rotate") or has(t, "Spin") end,
    keys = { "rotate", "affineTasks" },
    what = "the mon turning on the spot" },
  { name = "bg",
    wants = function(t)
      return has(t, "Background") or has(t, "SlidingBg") or has(t, "SurfWave")
    end,
    alsoWants = function(row) return (row.bg or 0) > 0 end,
    keys = { "monBgTimeline", "surf", "scanlines" },
    what = "the background the move swaps in" },
}

-- A CLASS KEY MUST NOT BE ONE EVERY MOVE HAS.
--
-- The ratchet below only bites when a count goes UP, so a class whose key
-- list is too GENEROUS makes moves look fixed and cannot be caught there --
-- adding `duration` to any class would report nothing missing at all, and
-- that was a planted fault this file let through on the first draft.  So the
-- keys are measured against the dataset itself: a key carried by almost every
-- move cannot be evidence of anything.  95% sits above `events` (89%) and
-- below `sound` (97%) and `duration` (100%), which are the three that would
-- do the damage.
local keyShare = {}
do
  local total = 0
  for _, mv in pairs(moves) do
    total = total + 1
    for key in pairs(mv.anim or {}) do
      keyShare[key] = (keyShare[key] or 0) + 1
    end
  end
  for key, n in pairs(keyShare) do keyShare[key] = n / math.max(1, total) end
end
for _, cls in ipairs(CLASSES) do
  for _, key in ipairs(cls.keys) do
    local share = keyShare[key] or 0
    ok(share <= 0.95,
       "the %s class counts `%s` as evidence, and %.1f%% of moves carry it "
       .. "-- a key that common makes every move look fixed", cls.name, key,
       share * 100)
  end
end

local report = {}
for _, cls in ipairs(CLASSES) do
  local want, have, miss = 0, 0, {}
  for name, row in pairs(MOVES) do
    local asks = cls.alsoWants and cls.alsoWants(row) or false
    for _, t in ipairs(row.tasks or {}) do
      if cls.wants(t[1]) then asks = true break end
    end
    if asks then
      want = want + 1
      local anim = moves[name] and moves[name].anim
      local got = false
      for _, key in ipairs(cls.keys) do
        if anim and anim[key] ~= nil then got = true break end
      end
      if got then have = have + 1 else miss[#miss + 1] = name end
    end
  end
  table.sort(miss)
  report[cls.name] = miss
  io.write(("  %-10s script asks it for %3d moves, dataset carries %3d, "
            .. "MISSING %3d   (%s)\n")
           :format(cls.name, want, have, #miss, cls.what))
end
-- and the flattest failure of all: a script that spawns particles against a
-- dataset row with no events, which is a move that draws nothing whatsoever
local noEvents = {}
for name, row in pairs(MOVES) do
  if (row.sprites or 0) > 0 then
    local anim = moves[name] and moves[name].anim
    if not (anim and anim.events) then noEvents[#noEvents + 1] = name end
  end
end
table.sort(noEvents)
report.noEvents = noEvents
io.write(("  %-10s script spawns particles for %d moves that have no events "
          .. "at all\n"):format("silent", #noEvents))

section("4. the moves, by name")
for _, key in ipairs({ "noEvents", "translate", "rotate", "blend", "shake",
                       "bg", "scale" }) do
  local list = report[key]
  if #list > 0 then
    io.write(("\n  %s (%d):\n"):format(key, #list))
    local line = "   "
    for _, n in ipairs(list) do
      if #line + #n + 2 > 76 then io.write(line, "\n") line = "   " end
      line = line .. " " .. n
    end
    if line ~= "   " then io.write(line, "\n") end
  end
end

-- ---------------------------------------------------------------------------
section("5. the ratchet")
-- ---------------------------------------------------------------------------
-- What each count was when this tool was written, against the dataset extracted
-- on 2026-09-29. Lower these in the same commit that fixes the moves.
local BASELINE = {
  shake = 21, blend = 46, scale = 2, translate = 31, rotate = 8, bg = 20,
  noEvents = 10,
}
for key, was in pairs(BASELINE) do
  local now = #report[key]
  ok(now <= was,
     "%s: %d moves are missing it, up from %d -- something that used to render "
     .. "has stopped", key, now, was)
  if now < was then
    io.write(("  %-9s %d -> %d  (lower the baseline in this commit)\n")
             :format(key, was, now))
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
