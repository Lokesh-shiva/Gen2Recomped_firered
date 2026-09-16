-- WHICH GENERATIONS A MOD IS ON FOR.
--
-- Asked for directly: "a per generation mod selection menu so you can have
-- mods on for gen1, gen2, or gen3 games selectively".  A mod that retextures
-- Hoenn has nothing to say about Red, and a Johto map pack loaded under
-- Emerald is at best dead weight -- but until this there was one switch for
-- the whole installation and no way to say so.
--
-- THE SHAPE ON DISK IS THE OLD ONE UNTIL IT HAS TO CHANGE, which is the point
-- of this module existing at all.  `options.mods[id]` has always been a plain
-- boolean, and it still is for every mod that is on (or off) everywhere:
--
--   true / false            -- exactly as before, all three generations
--   nil                     -- no entry; the caller's own default decides
--   { on = <bool>,          -- the master switch
--     gens = { b, b, b } }  -- ...and which generations it reaches
--
-- So a build that has never seen a per-generation mod writes and reads what it
-- always did, an older build handed one of these tables sees a truthy value
-- (the mod stays on, which is the safe way round), and nothing has to be
-- migrated in either direction.
--
-- THE MASTER IS NOT DERIVED FROM THE CHIPS.  `on = false` is off everywhere
-- whatever the chips say, and the chips are REMEMBERED while it is off -- a
-- player who turns a mod off and back on gets their selection back rather than
-- a reset to all three.  That is the whole reason this is a record and not
-- three loose booleans.

local ModGens = {}

ModGens.GENERATIONS = { 1, 2, 3 }
ModGens.COUNT = 3

local function blankGens(value)
  return { value, value, value }
end

-- decode(value) -> on, gens
--
-- `on` is nil when there is no entry at all, which is NOT the same as false:
-- the loader reads a missing entry as "enabled unless the mod is
-- experimental", and flattening that to false here would silently switch off
-- every mod nobody has ever touched.
function ModGens.decode(value)
  if value == nil then return nil, blankGens(true) end
  if type(value) == "table" then
    local gens = {}
    local src = type(value.gens) == "table" and value.gens or {}
    for i = 1, ModGens.COUNT do
      -- absent means on: a record written by a build that knew about two
      -- generations must not switch the third one off
      gens[i] = src[i] ~= false
    end
    local on
    if value.on == nil then on = true else on = value.on and true or false end
    return on, gens
  end
  return value and true or false, blankGens(true)
end

function ModGens.allOn(gens)
  for i = 1, ModGens.COUNT do
    if gens and gens[i] == false then return false end
  end
  return true
end

-- encode(on, gens) -> the value to store.  A boolean whenever it can be one,
-- so the file only grows a record for a mod that actually needs one.
function ModGens.encode(on, gens)
  if ModGens.allOn(gens) then return on and true or false end
  local out = {}
  for i = 1, ModGens.COUNT do out[i] = gens[i] ~= false end
  return { on = on and true or false, gens = out }
end

-- Is this mod on for `generation`?  nil when there is no entry, so the caller
-- can apply its own default (the loader's "missing means enabled, except
-- experimental").
function ModGens.active(value, generation)
  local on, gens = ModGens.decode(value)
  if on == nil then return nil end
  if not on then return false end
  local g = tonumber(generation)
  if not (g and g >= 1 and g <= ModGens.COUNT) then return on end
  return gens[g] ~= false
end

-- ...and the same question with the default folded in, which is what a caller
-- comparing against a live toggle wants.
function ModGens.resolve(value, generation, experimental)
  local a = ModGens.active(value, generation)
  if a ~= nil then return a end
  return not experimental
end

-- Flip the master switch, keeping the chips.
function ModGens.withEnabled(value, on)
  local _, gens = ModGens.decode(value)
  return ModGens.encode(on, gens)
end

-- Flip one generation.
--
-- Turning a generation ON also turns the master on, because the alternative is
-- a chip that lights up and changes nothing -- the in-game manager has no
-- master switch of its own to offer, and a player ticking GEN 3 means "run
-- this under Emerald" whatever the switch above it was doing.
--
-- Turning the LAST one off leaves the master alone: the mod is then off
-- everywhere by its chips, and flicking any chip back on revives it without a
-- second click.
function ModGens.withGen(value, generation, want)
  local on, gens = ModGens.decode(value)
  local g = tonumber(generation)
  if not (g and g >= 1 and g <= ModGens.COUNT) then
    return ModGens.encode(want, gens)
  end
  gens[g] = want and true or false
  if want then on = true end
  if on == nil then on = true end
  return ModGens.encode(on, gens)
end

-- The three chips for a row, as booleans.  Separate from decode so a caller
-- that only wants to DRAW them does not have to care about the master.
function ModGens.gensOf(value)
  local _, gens = ModGens.decode(value)
  return gens
end

ModGens.LABELS = { "GEN 1", "GEN 2", "GEN 3" }
ModGens.SHORT = { "G1", "G2", "G3" }

return ModGens
