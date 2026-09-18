-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S PC.
--
-- The PC in the room the game starts in is a script -- `special 217 /
-- "{PLAYER} booted up the PC." / special 252 BedroomPC / waitstate` -- and
-- 252 opened the GAME BOY screen, because nothing was registered under
-- `PlayerPC` for Hoenn.  Reported from play: "the pc in the starting bedroom
-- ... I get the gen1 menus for depositing items".
--
-- The words and the ORDER are the cartridge's, read by
-- RomExtractorGen3:extractPCMenu out of Emerald's own three menu tables:
--
--     ITEM STORAGE / MAILBOX / DECORATION / TURN OFF
--       ITEM STORAGE -> WITHDRAW ITEM / DEPOSIT ITEM / TOSS ITEM / CANCEL
--       MAILBOX      -> READ / MOVE TO BAG / GIVE / CANCEL
--
-- Note that WITHDRAW comes FIRST here.  Gen 1's screen puts it after nothing
-- at all -- its rows are WITHDRAW / DEPOSIT / TOSS / LOG OFF -- but the two
-- happen to agree on that one; what they do not agree on is the menu ABOVE
-- it, which Gen 1 does not have.
--
-- WHAT WORKS AND WHAT DOES NOT.  Item storage is the same store, the same
-- rules and the same three flows the older screen already implements -- what
-- differed between the cartridges was the furniture, not what withdrawing an
-- item does, so those are reused rather than rewritten.  MAILBOX and
-- DECORATION are the cartridge's rows and are shown as the cartridge shows
-- them, but this port has neither mail nor secret-base decorations yet, so
-- choosing one says so rather than doing nothing: an empty mailbox is a
-- state the cartridge has too, and it is the honest answer here.

local Menu = require("src.ui.Menu")
local Strings = require("src.core.Strings")

local Gen3PlayerPC = {}

local function record(game)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3PCMenu
  return type(r) == "table" and r or nil
end

-- A row's label, from the dataset where there is one.  A cache imported
-- before extractPCMenu existed keeps the same rows in the same order under
-- names this file spells itself, so the screen never comes up blank.
local FALLBACK = {
  main = { "ITEM STORAGE", "MAILBOX", "DECORATION", "TURN OFF" },
  itemStorage = { "WITHDRAW ITEM", "DEPOSIT ITEM", "TOSS ITEM", "CANCEL" },
  mailbox = { "READ", "MOVE TO BAG", "GIVE", "CANCEL" },
}

function Gen3PlayerPC.words(game, menu)
  local r = record(game)
  local list = (r and r[menu]) or FALLBACK[menu]
  return list or {}
end

-- ---------------------------------------------------------------------------
-- THE LIST BEHIND THESE ROWS IS THE BAG'S, NOT THE GAME BOY'S.
--
-- Reported from play: "after I write withdraw item then the menu where potion
-- is visible... that menu is gbc color".  It was.  The three flows used to be
-- taken wholesale from src/ui/PlayerPC.lua, and those push `ListMenu`, which
-- paints a 160x144 white Game Boy page with the Game Boy font -- so choosing
-- WITHDRAW ITEM out of a Gen 3 PC dropped the player onto a Kanto screen.
--
-- It is the same bug the catching tutorial had ("the bag he opens in the
-- tutorial is the gen1 bag"), and it has the same answer: Gen3BagMenu already
-- draws the cartridge's list, frame, description box and quantities, and it
-- already knows how to show a list that is NOT the bag's own contents and to
-- hand a pick back instead of using it (`rows` + `pick`/`onPick`, written for
-- DisplayListMenuID's tutorial arm and for "which berry are you planting").
-- Item storage is exactly that shape: a list of what is in the PC, and a pick.
--
-- WHAT IS REUSED AND WHAT IS NOT.  The store, the capacity rule and the
-- quantity prompt are unchanged -- they were never the problem -- so this
-- borrows PlayerPC's own helpers where they are screen-agnostic and replaces
-- only the screen.  DEPOSIT opens the real bag, which is what the cartridge
-- opens: you are choosing out of your pockets, not out of the PC.
local function itemDef(game, id)
  return (game.data.items or {})[id]
end

local function itemName(game, id)
  local def = itemDef(game, id)
  return (def and def.name) or id
end

-- A Gen3BagMenu row per stack in `store`, in item order, with the CANCEL the
-- cartridge ends every one of these lists with.
local function storageRows(game, store)
  local ids = {}
  for id, n in pairs(store) do
    if (tonumber(n) or 0) > 0 then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local rows = {}
  for _, id in ipairs(ids) do
    local def = itemDef(game, id)
    rows[#rows + 1] = {
      id = id,
      label = itemName(game, id),
      qty = tonumber(store[id]),
      -- a key item prints no count, here as in the bag
      important = (def and (def.keyItem or (tonumber(def.importance) or 0) ~= 0))
                  or nil,
      description = def and (def.description or def.desc),
    }
  end
  rows[#rows + 1] = { close = true, label = Strings("CANCEL") }
  return rows
end

-- The bag screen, showing `rows` under `title` with the pocket switch locked
-- off: this list is one list, not three pockets.
local function storageList(game, title, rows, onPick, onCancel)
  local menu = require("src.ui.Gen3BagMenu").new(game, {
    rows = rows, pick = true, onPick = onPick, onCancel = onCancel,
  })
  menu.pockets = { { key = "ITEM", name = title } }
  menu.pocket = 1
  menu.lockPocket = true
  game.stack:push(menu)
  return menu
end

-- Key items and HMs always move one, with no prompt (IsKeyItem in
-- players_pc.asm, and FireRed's own ItemStorage arm does the same).
local function askQuantity(game, id, max, cb)
  local def = itemDef(game, id)
  if (def and def.keyItem) or tostring(id):find("^HM_") or (max or 1) <= 1 then
    return cb(1)
  end
  game.stack:push(require("src.ui.QuantityBox").new(game, {
    max = max,
    onDone = function(qty) if qty then cb(qty) end end,
  }))
end

local function say(game, text, after)
  game.stack:push(require("src.render.TextBox").new(game, text, after))
end

local function g3Withdraw(game, back)
  local pc = game.save.pcItems
  local open
  open = function()
    storageList(game, Strings("WITHDRAW ITEM"), storageRows(game, pc),
      function(id)
        askQuantity(game, id, pc[id] or 1, function(qty)
          local Bag = require("src.inventory.Bag")
          if not Bag.add(game.save, id, qty, game.data) then
            return say(game, Strings("You can't carry\nany more items."), open)
          end
          pc[id] = (pc[id] or 0) - qty
          if pc[id] <= 0 then pc[id] = nil end
          require("src.core.Sound").play(game.data, "Withdraw_Deposit")
          say(game, Strings("Withdrew\n%s.", itemName(game, id)), open)
        end)
      end, back)
  end
  open()
end

-- wNumBoxItems capacity: 50 stacks (PC_ITEM_CAPACITY)
local function pcFull(game, pc, id)
  if pc[id] then return false end -- growing an existing stack is fine
  local cap = (game.data.field or {}).pcItemCap or 50
  local stacks = 0
  for _ in pairs(pc) do stacks = stacks + 1 end
  return stacks >= cap
end

local function g3Deposit(game, back)
  local pc = game.save.pcItems
  local Bag = require("src.inventory.Bag")
  local open
  open = function()
    -- the REAL bag: depositing is choosing out of your own pockets
    local menu = require("src.ui.Gen3BagMenu").new(game, {
      pick = true,
      onCancel = back,
      onPick = function(id)
        if Bag.isBadge and Bag.isBadge(id) then return open() end
        local have = (game.save.inventory or {})[id] or 1
        askQuantity(game, id, have, function(qty)
          if pcFull(game, pc, id) then
            return say(game, Strings("No room left to\nstore items."), open)
          end
          Bag.remove(game.save, id, qty)
          pc[id] = (pc[id] or 0) + qty
          require("src.core.Sound").play(game.data, "Withdraw_Deposit")
          say(game, Strings("%s was\nstored via PC.", itemName(game, id)), open)
        end)
      end,
    })
    game.stack:push(menu)
  end
  open()
end

local function g3Toss(game, back)
  local pc = game.save.pcItems
  local open
  open = function()
    storageList(game, Strings("TOSS ITEM"), storageRows(game, pc),
      function(id)
        local def = itemDef(game, id)
        if (def and def.keyItem) or tostring(id):find("^HM_") then
          return say(game, Strings("That's too impor-\ntant to toss!"), open)
        end
        askQuantity(game, id, pc[id] or 1, function(qty)
          say(game, Strings("Toss %s?", itemName(game, id)), function()
            game.stack:push(require("src.ui.ChoiceBox").new(game, function(yes)
              if not yes then return open() end
              pc[id] = (pc[id] or 0) - qty
              if pc[id] <= 0 then pc[id] = nil end
              say(game, Strings("Threw away %s.", itemName(game, id)), open)
            end, { noSound = true }))
          end)
        end)
      end, back)
  end
  open()
end

-- ITEM STORAGE, in the cartridge's order.
local function itemStorage(game, onCancel)
  local words = Gen3PlayerPC.words(game, "itemStorage")
  game.save.pcItems = game.save.pcItems or {}
  local flows = { g3Withdraw, g3Deposit, g3Toss }
  local rows = {}
  for i, label in ipairs(words) do
    local flow = flows[i]
    rows[#rows + 1] = {
      label = Strings(label),
      keepOpen = flow ~= nil,
      onSelect = flow and function() flow(game) end or nil,
    }
  end
  -- sWindowTemplate_ItemStorageSubmenu: (1,1), 14 wide inside its frame
  local sub = Menu.new(game, rows, { noSound = true, tx = 0, ty = 0, tw = 16,
                                     onCancel = onCancel })
  -- placed on the GBA's own 240x160, not the Game Boy's centred 160x144
  function sub:uiSize() return 240, 160 end
  game.stack:push(sub)
end

-- DECORATION -- the same screen the secret base's PC opens.
--
-- Reported from play: "the lady in the game corner that is supposed to give
-- you a doll doesnt give you anything".  She does: a thousand coins buy a
-- DOLL and it lands in the decoration inventory, and her line is "we'll send
-- it to your PC at home".  This row said the feature was not built, so home
-- was where the doll went to disappear.  The screen behind it -- DECORATE,
-- PUT AWAY, TOSS -- has existed since the secret bases went in; only this
-- door onto it was missing.
local function decoration(game, back)
  local okC, Gen3Commands = pcall(require, "src.script.Gen3Commands")
  local okD, Decor = pcall(require, "src.world.Gen3Decorations")
  -- ASKED BEFORE ANYTHING IS PUSHED.  A cache imported before the decoration
  -- tables were read has no menu to show, and finding that out halfway
  -- through would leave the player looking at a screen that had already
  -- decided to go back.
  local rows = okD and (Decor.record(game and game.data) or {}).menu
  if not (okC and Gen3Commands.decorationPC and type(rows) == "table"
          and #rows > 0) then
    return false
  end
  Gen3Commands.decorationPC(
    { game = game, save = game.save, overworld = game.overworld }, back)
  return true
end

local function notBuilt(game, what)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game,
    Strings("%s is not in this\nport yet.", what)))
end

-- `onDone` is what the script's `waitstate` is waiting for: Gen3Commands'
-- pushBlocking parks the runner until this screen closes.  Every way out of
-- here goes through `close`, so the park can never outlive the screen.
-- WHICH OF THE FOUR ROWS THIS PC SHOWS.
--
-- The bedroom's shows all four; the one in a Poke Centre leaves DECORATION
-- out and shows three.  That is not this screen's choice -- both specials
-- load a list of row numbers, and the import reads both (pcMenuOrders).  A
-- dataset without them shows everything, which is what this screen did
-- before either was read.
function Gen3PlayerPC.order(game, which, count)
  local r = record(game)
  local list = which and r and r.orders and r.orders[which]
  if type(list) == "table" and #list > 0 then return list end
  local all = {}
  for i = 1, count do all[i] = i end
  return all
end

-- ...and the way back onto this screen once one of its rows is finished with.
-- The decoration menu pushes its own stack of menus and pops them itself, so
-- what it returns to has to be a FRESH PC menu rather than the one it
-- replaced -- which is exactly what the cartridge does: every one of the PC's
-- rows ends by walking back into the PC script.
function Gen3PlayerPC.reopen(game, opts)
  local ok, menu = pcall(Gen3PlayerPC.new, game, opts)
  if ok and menu then pcall(game.stack.push, game.stack, menu) end
end

function Gen3PlayerPC.new(game, opts)
  opts = opts or {}
  game.save.pcItems = game.save.pcItems or {}
  local words = Gen3PlayerPC.words(game, "main")
  local menu
  local function close()
    local done = opts.onDone
    opts.onDone = nil
    if done then done() end
  end
  local rows = {}
  for _, i in ipairs(Gen3PlayerPC.order(game, opts.order, #words)) do
    local label = words[i]
    local row = { label = Strings(label or "") }
    if i == 1 then
      row.keepOpen = true
      row.onSelect = function() itemStorage(game) end
    elseif i == 3 then
      -- DECORATION opens its own screen, and that screen owns what happens
      -- next -- so this row does NOT keepOpen: the decoration menu walks back
      -- into this one itself when the player is done with it.
      row.onSelect = function()
        if not decoration(game, function() Gen3PlayerPC.reopen(game, opts) end) then
          notBuilt(game, Strings(label))
        end
      end
    elseif i == 2 then
      row.keepOpen = true
      row.onSelect = function() notBuilt(game, Strings(label)) end
    else
      -- TURN OFF: the row that ends the session
      row.onSelect = close
    end
    rows[#rows + 1] = row
  end
  menu = Menu.new(game, rows, {
    -- PlayersPCMenu holds BIT_NO_MENU_BUTTON_SOUND on both cartridges
    noSound = true,
    -- sWindowTemplate_TopMenu_*: (1,1), 13 wide inside its frame
    tx = 0, ty = 0, tw = 15,
    onCancel = close,
  })
  function menu:uiSize() return 240, 160 end
  return menu
end

return Gen3PlayerPC
