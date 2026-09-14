-- FIRERED'S OWN SPECIALS.
--
-- The importer rewrites every FireRed `special n` to the Emerald index of the
-- same-named function (manifest specialRemap), so everything the two games
-- share already runs on Gen3Commands.SPECIALS.  A FireRed-only special has no
-- Emerald twin and arrives as 0x1000 + its FireRed index (pokefirered
-- data/specials.inc); this file is where those are served, each written from
-- the pokefirered function of the same name.  Emerald handlers that do the
-- same job under another name are aliased rather than rewritten.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

return function(Gen3Commands)
  local S = Gen3Commands.SPECIALS
  local getVar, setVar = Gen3Commands.getVar, Gen3Commands.setVar
  local VAR_RESULT = Gen3Commands.VAR_RESULT
  local BASE = 0x1000
  local function def(index, fn) S[BASE + index] = fn end
  local function alias(index, emerald)
    if S[emerald] then S[BASE + index] = S[emerald] end
  end
  local function var(ctx, id) return math.floor(tonumber(getVar(ctx.save, id)) or 0) end
  local function texts(ctx)
    local c = ctx.game and ctx.game.data and ctx.game.data.constants
    return (c and c.gen3FRLGSpecialTexts) or {}
  end
  local function flag(ctx, n)
    return ((ctx.save and ctx.save.flags) or {})[Gen3Commands.flagKey(n)] == true
  end
  local function setFlag(ctx, n)
    ctx.save.flags = ctx.save.flags or {}
    ctx.save.flags[Gen3Commands.flagKey(n)] = true
  end
  local function mapId(ctx)
    local ow = ctx.overworld
    return ow and ow.map and ow.map.id
  end

  -- ---- Emerald twins under FireRed names ---------------------------------
  alias(148, 151)   -- BufferBigGuyOrBigGirlString  = GetPlayerBigGuyGirlString
  alias(214, 217)   -- AnimatePcTurnOn              = DoPCTurnOnEffect
  alias(304, 306)   -- IsThereRoomInAnyBoxForMorePokemon
  alias(327, 329)   -- GetPartyMonSpecies           = ScriptGetPartyMonSpecies
  alias(336, 338)   -- IsMonOTNameNotPlayers        = MonOTNameNotPlayer
  alias(286, 288)   -- GetRandomSlotMachineId       = GetSlotMachineId
  alias(220, 223)   -- SelectMoveDeleterMove        = MoveDeleterChooseMoveToForget
  alias(191, 194)   -- GetDaycareCost               = GetDaycareCostAndPrepareString
  alias(163, 166)   -- Script_IsFanClubMemberFanOfPlayer
  alias(164, 167)   -- Script_GetNumFansOfPlayerInTrainerFanClub
  alias(165, 168)   -- Script_BufferFanClubTrainerName
  alias(310, 312)   -- ShakeScreen                  = ShakeCamera

  -- ---- things with no visible effect in this port ------------------------
  -- The quest log (the "previously on..." replay), the help system, the
  -- fame checker's flavour flags and the message-box walkaway are FireRed
  -- systems the port does not have; their specials answer "not replaying"
  -- and change nothing.
  for _, i in ipairs({ 361, 368, 369, 371, 372, 381, 382, 383, 388, 392, 400,
                       408, 409, 417, 196, 359, 360 }) do
    def(i, function() end)
  end
  def(391, function() return 0 end)            -- GetQuestLogState: not replaying

  -- ---- gym and field puzzles -----------------------------------------------
  -- SetVermilionTrashCans: the first switch in 0x8004, its neighbour in 0x8005
  def(347, function(ctx)
    local first = math.random(0, 14) + 1
    local second = first
    local r = function(n) return math.random(0, n - 1) end
    local steps = {
      [1] = { 1, 5 }, [2] = { 1, 5, -1 }, [3] = { 1, 5, -1 }, [4] = { 1, 5, -1 },
      [5] = { 5, -1 }, [6] = { -5, 1, 5 }, [7] = { -5, 1, 5, -1 }, [8] = { -5, 1, 5, -1 },
      [9] = { -5, 1, 5, -1 }, [10] = { -5, 5, -1 }, [11] = { -5, 1 }, [12] = { -5, 1, -1 },
      [13] = { -5, 1, -1 }, [14] = { -5, 1, -1 }, [15] = { -5, -1 },
    }
    local choices = steps[first]
    second = first + choices[r(#choices) + 1]
    if second > 15 then
      if first % 5 == 1 then second = first + 1
      elseif first % 5 == 0 then second = first - 1
      else second = first + 1 end
    end
    setVar(ctx.save, 0x8004, first)
    setVar(ctx.save, 0x8005, second)
  end)

  -- ForcePlayerOntoBike (Cycling Road) and ForcePlayerToStartSurfing (Seafoam)
  def(343, function(ctx)
    local save = ctx.save
    if not save.onBike then
      save.onBike, save.bikeKind = true, "mach"
    end
  end)
  def(353, function(ctx)
    local ow = ctx.overworld
    local p = ow and ow.player
    if not p then return end
    p.surfing = true
    if ow.map and ow.map.cellElevation then
      p.elevation = ow.map:cellElevation(p.cellX, p.cellY) or p.elevation
    end
  end)
  -- SeafoamIslandsB4F_CurrentDumpsPlayerOnLand: the current carries you off
  -- the water facing north
  def(348, function(ctx)
    local ow = ctx.overworld
    local p = ow and ow.player
    if not p then return end
    p.surfing = false
    p.facing = "up"
  end)

  -- ---- battles -------------------------------------------------------------
  def(312, function(ctx) Commands.g3_wild_battle(ctx) end)   -- StartLegendaryBattle
  def(236, function(ctx) Commands.g3_wild_battle(ctx) end)   -- StartSpecialBattle
  -- StartMarowakBattle: the ghost at Pokemon Tower 6F.  With the SILPH SCOPE it
  -- is MAROWAK, level 30, and can be fought; without it the cartridge runs an
  -- unwinnable GHOST battle, which this port answers as a run.
  def(342, function(ctx)
    local bag = (ctx.save or {}).inventory or {}
    if (bag.SILPH_SCOPE or 0) > 0 then
      Commands.g3_set_wild(ctx, 105, 30, 0)
      Commands.g3_wild_battle(ctx)
    else
      ctx.lastBattleResult = "run"
    end
  end)

  -- ---- elevators (Silph Co., Rocket Hideout, Celadon, Trainer Tower) -------
  local SILPH = { MAP_G01_N47 = 4, MAP_G01_N48 = 5, MAP_G01_N49 = 6, MAP_G01_N50 = 7,
                  MAP_G01_N51 = 8, MAP_G01_N52 = 9, MAP_G01_N53 = 10, MAP_G01_N54 = 11,
                  MAP_G01_N55 = 12, MAP_G01_N56 = 13, MAP_G01_N57 = 14,
                  MAP_G01_N42 = 3, MAP_G01_N43 = 2, MAP_G01_N45 = 0,
                  MAP_G10_N00 = 4, MAP_G10_N01 = 5, MAP_G10_N02 = 6, MAP_G10_N03 = 7,
                  MAP_G10_N04 = 8, MAP_G02_N10 = 3 }
  local CURSOR = { MAP_G01_N57 = { 0, 0 }, MAP_G01_N56 = { 0, 1 }, MAP_G01_N55 = { 0, 2 },
                   MAP_G01_N54 = { 0, 3 }, MAP_G01_N53 = { 0, 4 }, MAP_G01_N52 = { 1, 4 },
                   MAP_G01_N51 = { 2, 4 }, MAP_G01_N50 = { 3, 4 }, MAP_G01_N49 = { 4, 4 },
                   MAP_G01_N48 = { 5, 4 }, MAP_G01_N47 = { 5, 5 },
                   MAP_G01_N42 = { 0, 0 }, MAP_G01_N43 = { 0, 1 }, MAP_G01_N45 = { 0, 2 },
                   MAP_G10_N04 = { 0, 0 }, MAP_G10_N03 = { 0, 1 }, MAP_G10_N02 = { 0, 2 },
                   MAP_G10_N01 = { 0, 3 }, MAP_G10_N00 = { 0, 4 }, MAP_G02_N10 = { 0, 1 } }
  local function dynamicMap(ctx)
    local warp = (ctx.save or {}).gen3DynamicWarp
    return warp and warp.map
  end
  def(216, function(ctx)                        -- GetElevatorFloor -> VAR_ELEVATOR_FLOOR
    local m = dynamicMap(ctx)
    local floor = (m and SILPH[m]) or 4
    if m and m:match("^MAP_G02_N0[1-9]$") then floor = 15 end
    setVar(ctx.save, 0x403A, floor)
  end)
  def(440, function(ctx)                        -- InitElevatorFloorSelectMenuPos
    local c = CURSOR[dynamicMap(ctx) or ""] or { 0, 0 }
    ctx.save.frlgElevatorScroll = c[1]
    return c[2]
  end)
  def(306, function(ctx)                        -- DrawElevatorCurrentFloorWindow
    local t = texts(ctx)
    local ow = ctx.overworld
    if not ow then return end
    ow.frlgFloorWindow = { nowOn = t.nowOn or Strings("Now on:"),
                           floor = (t.floors or {})[var(ctx, 0x8005) + 1] or "" }
  end)
  def(352, function(ctx)                        -- CloseElevatorCurrentFloorWindow
    if ctx.overworld then ctx.overworld.frlgFloorWindow = nil end
  end)
  -- AnimateElevator: the car shakes a pixel every third frame for a count set
  -- by how many floors it travels (sElevatorAnimationDuration), then dings
  local ELEVATOR_SHAKES = { 8, 16, 24, 32, 38, 46, 53, 56, 57 }
  def(273, function(ctx)
    local ow, runner = ctx.overworld, ctx.runner
    if not (ow and runner) then return end
    local n = math.min(8, math.abs(var(ctx, 0x8005) - var(ctx, 0x8006)))
    local done = false
    ow.gen3Elevator = { shakes = ELEVATOR_SHAKES[n + 1], frames = 0, period = 3, amplitude = 1,
                        resume = function()
                          if done then return end
                          done = true
                          ow.gen3Elevator = nil
                          ow.bgShakeY = 0
                          runner:resume()
                        end }
    runner:yield()
  end)

  -- ListMenu (0x8004 = which list) and ReturnToListMenu.  The answer is the
  -- row in VAR_RESULT, 127 for backing out; the badge list stays open
  -- across the script's reply and is re-asked by ReturnToListMenu.
  local function listLabels(ctx, which)
    local t = texts(ctx)
    local exit = t.exit or Strings("EXIT")
    local f = t.floors or {}
    if which == 0 then
      local rows = {}
      for i = 1, 8 do rows[i] = (t.badges or {})[i] or ("BADGE %d"):format(i) end
      rows[9] = exit
      return rows, 4
    elseif which == 1 then
      return { f[15], f[14], f[13], f[12], f[11], f[10], f[9], f[8], f[7], f[6], f[5], exit }, 7
    elseif which == 2 then
      return { f[4], f[3], f[1], exit }, 4
    elseif which == 3 then
      return { f[9], f[8], f[7], f[6], f[5], exit }, 4
    elseif which == 6 then
      return { f[16], f[4], exit }, 3
    end
  end
  local function runList(ctx, which)
    local rows, visible = listLabels(ctx, which)
    if not rows then
      setVar(ctx.save, VAR_RESULT, 0x7F)
      return 0x7F
    end
    local picked = Gen3Commands.listPick(ctx, rows, nil, visible)
    local answer = picked and (picked - 1) or 0x7F
    setVar(ctx.save, VAR_RESULT, answer)
    return answer
  end
  def(344, function(ctx)
    local which = var(ctx, 0x8004)
    ctx.save.frlgLastList = which
    return runList(ctx, which)
  end)
  def(345, function(ctx)
    local which = ctx.save.frlgLastList
    if which then return runList(ctx, which) end
  end)

  -- ---- the Seagallop ferry and the Sevii Islands ---------------------------
  local MORE, CANCEL = 254, 127
  def(425, function(ctx)                        -- GetSeagallopNumber
    local o, d = var(ctx, 0x8004), var(ctx, 0x8006)
    local function either(x) return o == x or d == x end
    if either(8) then return 1 end
    if either(0) then return 7 end
    if either(9) then return 10 end
    if either(10) then return 12 end
    local function inSet(x, a, b, c) return x == a or x == b or x == c end
    if inSet(o, 1, 2, 3) and inSet(d, 1, 2, 3) then return 2 end
    if inSet(o, 4, 5) and inSet(d, 4, 5) then return 3 end
    if inSet(o, 6, 7) and inSet(d, 6, 7) then return 5 end
    return 6
  end)
  def(423, function(ctx)                        -- DrawSeagallopDestinationMenu
    local t = texts(ctx)
    local names = t.seagallop or {}
    local origin, page = var(ctx, 0x8004), var(ctx, 0x8005)
    local dest, count
    if page == 1 then
      dest, count = (origin < 5) and 5 or 4, 5
    else
      dest, count = 0, 6
    end
    local rows, i = {}, 0
    while i < count - 2 do
      if dest ~= origin then
        rows[#rows + 1] = names[dest + 1] or ""
        i = i + 1
      end
      dest = dest + 1
      if dest == 8 then dest = 0 end
    end
    rows[#rows + 1] = t.other or Strings("OTHER")
    rows[#rows + 1] = t.exit or Strings("EXIT")
    local picked = Gen3Commands.listPick(ctx, rows, nil, #rows)
    setVar(ctx.save, VAR_RESULT, picked and (picked - 1) or CANCEL)
  end)
  def(424, function(ctx)                        -- GetSelectedSeagallopDestination
    local result, origin = var(ctx, VAR_RESULT), var(ctx, 0x8004)
    if result == CANCEL then return CANCEL end
    if var(ctx, 0x8005) == 1 then
      if result == 3 then return MORE end
      if result == 4 then return CANCEL end
      if result == 0 then return origin > 4 and 4 or 5 end
      if result == 1 then return origin > 5 and 5 or 6 end
      if result == 2 then return origin > 6 and 6 or 7 end
      return 0
    end
    if result == 4 then return MORE end
    if result == 5 then return CANCEL end
    if result >= origin then return result + 1 end
    return result
  end)
  local HARBORS = {
    [0] = { "MAP_G03_N05", 0x17, 0x20 }, { "MAP_G32_N04", 8, 5 }, { "MAP_G33_N04", 8, 5 },
    { "MAP_G38_N00", 8, 5 }, { "MAP_G35_N05", 8, 5 }, { "MAP_G36_N02", 8, 5 },
    { "MAP_G37_N02", 8, 5 }, { "MAP_G31_N06", 8, 5 }, { "MAP_G03_N08", 0x15, 7 },
    { "MAP_G02_N59", 8, 5 }, { "MAP_G02_N58", 8, 5 },
  }
  def(379, function(ctx)                        -- DoSeagallopFerryScene
    local dest = HARBORS[var(ctx, 0x8006)] or HARBORS[0]
    Commands.warp(ctx, dest[1], dest[2], dest[3])
  end)
  def(429, function(ctx)                        -- IsPlayerLeftOfVermilionSailor
    local p = ctx.overworld and ctx.overworld.player
    return (mapId(ctx) == "MAP_G03_N05" and p and p.cellX < 24) and 1 or 0
  end)
  -- DoSSAnneDepartureCutscene: the horn and the wake behind the boat; the
  -- script moves the ship itself
  def(401, function(ctx) pcall(Commands.play_sound, ctx, "SS_Anne_Horn") end)

  -- ---- Pokedex, starter, party --------------------------------------------
  def(354, function(ctx)                        -- GetStarterSpecies
    local starters = { [0] = 1, 7, 4 }             -- BULBASAUR, SQUIRTLE, CHARMANDER
    return starters[var(ctx, 0x4031)] or 1
  end)
  def(403, function(ctx) return ctx.save.nationalDex and 1 or 0 end)  -- IsNationalPokedexEnabled
  local function kantoCounts(ctx)
    local dex = (ctx.save or {}).pokedex or {}
    local mons = (ctx.game and ctx.game.data and ctx.game.data.pokemon) or {}
    local seen, owned = 0, 0
    for id in pairs(dex.seen or {}) do
      local n = tonumber((mons[id] or {}).dex)
      if n and n >= 1 and n <= 151 then seen = seen + 1 end
    end
    for id in pairs(dex.owned or {}) do
      local n = tonumber((mons[id] or {}).dex)
      if n and n >= 1 and n <= 151 then owned = owned + 1 end
    end
    return seen, owned
  end
  def(212, function(ctx)                        -- GetPokedexCount
    local seen, owned
    if var(ctx, 0x8004) == 0 then
      seen, owned = kantoCounts(ctx)
    else
      seen, owned = Gen3Commands.dexCounts(ctx, true)
    end
    setVar(ctx.save, 0x8005, seen)
    setVar(ctx.save, 0x8006, owned)
    return ctx.save.nationalDex and 1 or 0
  end)
  def(213, function(ctx)                        -- GetProfOaksRatingMessage
    local count = var(ctx, 0x8004)
    local lines = texts(ctx).rating or {}
    setVar(ctx.save, VAR_RESULT, 0)
    local index = math.min(15, math.floor(count / 10) + 1)
    if count >= 150 then
      index = 16
      setVar(ctx.save, VAR_RESULT, 1)
    end
    local line = lines[index]
    if line then Commands.show_text(ctx, line) end
  end)
  def(335, function(ctx)                        -- HasAllKantoMons
    local _, owned = kantoCounts(ctx)
    return owned >= 150 and 1 or 0
  end)
  def(432, function(ctx)                        -- HasAllMons
    local _, owned = Gen3Commands.dexCounts(ctx, true)
    return owned >= 386 and 1 or 0
  end)
  def(355, function(ctx)                        -- SetSeenMon (0x8004 = species)
    local data = ctx.game and ctx.game.data
    local id = Gen3Commands.speciesId(data, var(ctx, 0x8004))
    if not id then return end
    ctx.save.pokedex = ctx.save.pokedex or {}
    ctx.save.pokedex.seen = ctx.save.pokedex.seen or {}
    ctx.save.pokedex.seen[id] = true
  end)
  local function party(ctx) return (ctx.save and ctx.save.party) or {} end
  def(380, function(ctx)                        -- DoesPlayerPartyContainSpecies
    local data = ctx.game and ctx.game.data
    local want = Gen3Commands.speciesId(data, var(ctx, 0x8004))
    for _, mon in ipairs(party(ctx)) do
      if mon.species == want then return 1 end
    end
    return 0
  end)
  def(230, function(ctx)                        -- GetLeadMonFriendship
    local lead = Gen3Commands.leadMon and Gen3Commands.leadMon(ctx)
    local f = tonumber(lead and (lead.friendship or lead.happiness)) or 0
    if f == 255 then return 6 elseif f >= 200 then return 5 elseif f >= 150 then return 4
    elseif f >= 100 then return 3 elseif f >= 50 then return 2 elseif f > 0 then return 1 end
    return 0
  end)

  -- ---- the league and after -----------------------------------------------
  -- EnterHallOfFame: FireRed's GameClear.  FLAG_SYS_GAME_CLEAR is 0x82C here
  -- (Emerald's is 0x864), then the same ceremony and walk home.
  def(272, function(ctx)
    local data = ctx.game and ctx.game.data
    if data then
      data.constants = data.constants or {}
      data.constants.gen3GameClear = data.constants.gen3GameClear or { flag = 0x82C }
    end
    if S[275] then return S[275](ctx) end
    setFlag(ctx, 0x82C)
  end)
  def(410, function(ctx)                        -- SetPostgameFlags
    ctx.save.frlgChampionSaveWarp = true
  end)
  def(421, function() end)                      -- DoCredits (run by the ceremony)
  def(93, function(ctx) return 0 end)           -- Field_AskSaveTheGame

  Logger.info("gen3: FireRed specials served")
end
