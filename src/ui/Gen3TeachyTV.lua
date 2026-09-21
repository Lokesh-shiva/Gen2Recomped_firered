-- FireRed's TEACHY TV key-item screen.
--
-- The cartridge's teachy_tv.c presents four always-available lessons and,
-- once the TM CASE exists, two more about TMs and registering key items.
-- RomExtractorGen3 supplies this screen's real gTeachyTv_* background and the
-- cartridge's own menu/tutorial strings from the player's ROM.  The four
-- POKeDUDE battle demonstrations are still a separate battle-controller job;
-- until that controller is ported, choosing a lesson plays its exact pre/post
-- lesson text rather than silently refusing the key item (the old behaviour).

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local TeachyTV = {}
TeachyTV.__index = TeachyTV
TeachyTV.isOpaque = true

local GBA_W, GBA_H = 240, 160
local ROW_PITCH = 16

local LESSONS = {
  {
    key = "battle", textKey = "battle", label = "Teach me how to battle.",
    text = "POKéDUDE: Welcome!\fIn battle, choose FIGHT, then pick a move.\nLower the foe's HP to win.\fWatch your own HP, too. If every POKéMON faints,\nyou'll black out.",
  },
  {
    key = "status", textKey = "status", label = "What are status problems?",
    text = "POKéDUDE: Status problems can change a battle.\fPOISON and BURN drain HP. PARALYSIS can stop a move.\nSLEEP and FREEZE keep a POKéMON from acting.\fItems and POKéMON CENTERS can cure these conditions.",
  },
  {
    key = "matchups", textKey = "matchups", label = "What are type matchups?",
    text = "POKéDUDE: Every move has a type.\fSome types are super effective, some are not very effective,\nand some do nothing at all.\fTry different moves and learn which matchups give you the edge!",
  },
  {
    key = "catch", textKey = "catch", label = "I want to catch POKéMON.",
    text = "POKéDUDE: First weaken a wild POKéMON without knocking it out.\fThen open the BAG and throw a POKé BALL.\nStatus problems can make a catch easier, too.",
  },
  {
    key = "tms", textKey = "tms", label = "Teach me about TMs.", needsTMCase = true,
    text = "POKéDUDE: TMs teach moves to compatible POKéMON.\fOpen the TM CASE, choose a TM, then choose the POKéMON.\nA TM is used up after teaching; HMs are kept.",
  },
  {
    key = "register", textKey = "register", label = "How do I register an item?", needsTMCase = true,
    text = "POKéDUDE: Important KEY ITEMS can be registered for quick use.\fIn the BAG, choose a KEY ITEM and select REGISTER.\nYou can change the registered item whenever you like.",
  },
}

function TeachyTV:uiSize() return GBA_W, GBA_H end
function TeachyTV:wantsFillScale() return true end

function TeachyTV:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function record(data)
  local r = data and data.constants and data.constants.gen3TeachyTV
  return type(r) == "table" and r or nil
end

local function romLabel(data, key, fallback)
  local r = record(data)
  local label = r and r.labels and r.labels[key]
  return type(label) == "string" and label ~= "" and label or fallback
end

local function romLesson(data, lesson)
  local r = record(data)
  local texts = r and r.texts
  if type(texts) ~= "table" then return lesson.text end
  local before = texts[lesson.textKey .. "Before"]
  local after = texts[lesson.textKey .. "After"]
  if type(before) == "string" and before ~= "" then
    if type(after) == "string" and after ~= "" then return before .. "\f" .. after end
    return before
  end
  return lesson.text
end

function TeachyTV.entries(save, data)
  local hasCase = save and save.inventory and save.inventory.TM_CASE
  local out = {}
  for _, lesson in ipairs(LESSONS) do
    if not lesson.needsTMCase or hasCase then
      out[#out + 1] = {
        key = lesson.key,
        textKey = lesson.textKey,
        needsTMCase = lesson.needsTMCase,
        label = romLabel(data, lesson.key, lesson.label),
        text = romLesson(data, lesson),
      }
    end
  end
  out[#out + 1] = { key = "cancel", label = romLabel(data, "cancel", "CANCEL") }
  return out
end

function TeachyTV.new(game)
  local self = setmetatable({}, TeachyTV)
  self.game = game
  self.rows = TeachyTV.entries(game.save, game.data)
  self.index, self.top = 1, 1
  return self
end

function TeachyTV:close()
  Sound.play(self.game.data, "Press_AB")
  self.game.stack:pop()
end

function TeachyTV:move(delta)
  self.index = (self.index - 1 + delta) % #self.rows + 1
  local visible = self:visibleRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then self.top = self.index - visible + 1 end
  Sound.play(self.game.data, "Press_AB")
end

function TeachyTV:visibleRows()
  local r = record(self.game.data)
  local L = r and r.list or {}
  local hasCase = self.game.save and self.game.save.inventory
                  and self.game.save.inventory.TM_CASE
  return math.max(1, math.floor(tonumber(hasCase and L.maxShowed
                                         or L.noCaseMaxShowed)
                                 or (hasCase and 6 or 5)))
end

function TeachyTV:choose()
  local row = self.rows[self.index]
  if not row or row.key == "cancel" then return self:close() end
  Sound.play(self.game.data, "Press_AB")
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, Strings(row.text)))
end

function TeachyTV:background()
  local r = record(self.game.data)
  local path = r and r.images and r.images.screen
  if type(path) ~= "string" then return nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  return ok and img or nil
end

function TeachyTV:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("down") then self:move(1)
  elseif input:wasPressed("up") then self:move(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("b") then self:close() end
end

function TeachyTV:keypressed(key)
  if key == "down" then return self:move(1) end
  if key == "up" then return self:move(-1) end
  if key == "a" then return self:choose() end
  if key == "b" then return self:close() end
end

function TeachyTV:draw()
  local bg = self:background()
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.12, 0.18, 0.20, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(0.84, 0.91, 0.88, 1)
    love.graphics.rectangle("fill", 8, 8, 224, 136)
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(2, 1, 26, 3)
    Font.draw("TEACHY TV", 16, 16)
    Font.drawBox(2, 4, 26, 14)
  end
  love.graphics.setColor(1, 1, 1, 1)

  local r = record(self.game.data)
  local L = r and r.list or {}
  local hasCase = self.game.save and self.game.save.inventory
                  and self.game.save.inventory.TM_CASE
  local x = (tonumber(L.x) or 32) + (tonumber(L.itemX) or 8)
  local cursorX = (tonumber(L.x) or 32) + (tonumber(L.cursorX) or 0)
  local y0 = (tonumber(L.y) or 8)
             + (tonumber(hasCase and L.upTextY or L.noCaseUpTextY)
                or (hasCase and 6 or 14))
  local visible = self:visibleRows()
  for i = 0, visible - 1 do
    local rowIndex = self.top + i
    local row = self.rows[rowIndex]
    if not row then break end
    local y = y0 + i * (tonumber(L.rowHeight) or ROW_PITCH)
    if rowIndex == self.index then Font.drawCode(Theme.cursor, cursorX, y) end
    Font.draw(row.label, x, y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return TeachyTV
