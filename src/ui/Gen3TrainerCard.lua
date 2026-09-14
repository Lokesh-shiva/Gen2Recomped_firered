-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's TRAINER CARD.
--
-- Not the Gen 2 card.  That one is a Game Boy page with a badge row and a
-- Johto map; this is a 240x160 GBA card whose front carries the player's
-- name, their ID number, their money, their POKéDEX count and their play
-- time, with the eight badges along the bottom -- and a back with the link
-- record on it, which B flips to.
--
-- THE LABELS ARE THE CARTRIDGE'S, found the way the START menu's were: they
-- sit consecutively in the text region in the order the card prints them.
--
--   NAME:   IDNo.   MONEY   POKéDEX   TIME
--
-- and the title line, "{PLAYER}'s TRAINER CARD", is in the same block a few
-- strings later.  Reading them rather than writing them down is what keeps
-- the trailing space and the full stop in "IDNo." -- two details that are
-- wrong in every reconstruction and right here.
--
-- THE BADGES ARE THE CARTRIDGE'S NOW.  They were eight rectangles, filled
-- for the ones earned, because every search for the art had looked for a
-- SPRITE and the cartridge draws them as BACKGROUND TILES -- four tilemap
-- cells per badge, sixteen tiles across, eight side by side in one 1024-byte
-- sheet on one shared palette (RomExtractorGen3:trainerCardBadges).  Their
-- places on this card are the cartridge's too: the first sits four tiles in,
-- they step three tiles apart, and they sit on rows fifteen and sixteen.
--
-- AN UNEARNED BADGE IS NOT DRAWN AT ALL, which is what the cartridge does --
-- there is no empty socket waiting to be filled.
--
-- What is still NOT derived is the rest of the card's ARTWORK: the gradient
-- front and the trainer's picture are graphics the import does not reach yet.
-- This draws the card in the cartridge's own window frame instead, with the
-- fields in their places, and it is the part to replace when that art is
-- extracted.

local Badges = require("src.inventory.Badges")
local Gen3BadgeArt = require("src.render.Gen3BadgeArt")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen3TrainerCard = {}
Gen3TrainerCard.__index = Gen3TrainerCard
Gen3TrainerCard.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: the card fills the screen with a tile of margin.
local CARD = { tx = 1, ty = 1, tw = 28, th = 18 }
local LABEL_X = 24
local VALUE_X = 128
local ROW_PITCH = 18
local FIRST_ROW = 5          -- pixels below the card's inner edge
-- the badge row, in the cartridge's own tile coordinates
local BADGE_FIRST_TX = 4
local BADGE_STEP_TX = 3
local BADGE_TY = 15

function Gen3TrainerCard:uiSize() return GBA_W, GBA_H end
function Gen3TrainerCard:wantsFillScale() return true end

function Gen3TrainerCard:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

local function screenText(game, key)
  local record = ((game.data.constants or {}).gen3Screens or {})[key]
  return record and record.items or nil
end

function Gen3TrainerCard.new(game, opts)
  local self = setmetatable({}, Gen3TrainerCard)
  self.game = game
  self.onCancel = opts and opts.onCancel
  self.back = false
  local labels = screenText(game, "trainerCard")
  if not labels then
    Logger.warn("gen3 trainer card: this dataset carries no field labels -- "
                .. "falling back to the engine's own")
    labels = { Strings("NAME: "), "IDNo.", Strings("MONEY"),
               Strings("POKéDEX"), Strings("TIME") }
  end
  self.labels = labels
  return self
end

function Gen3TrainerCard:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3TrainerCard:frlgRecord()
  local r = (self.game.data.constants or {}).gen3FRLGTrainerCard
  return type(r) == "table" and type(r.images) == "table" and r.images.bg_boy_0 and r or nil
end

function Gen3TrainerCard:update(dt)
  local input = self.game.input
  if self:frlgRecord() then
    -- the card flips top-to-bottom over the midline (Task_AnimateCardFlipDown/Up)
    if self.flip then
      self.flip = self.flip + 1
      if self.flip == 12 then self.back = not self.back end
      if self.flip >= 24 then self.flip = nil end
      return
    end
    if input:wasPressed("a") then
      self.flip = 0
      pcall(function() require("src.core.Sound").play(self.game.data, "Press_AB") end)
    elseif input:wasPressed("b") or input:wasPressed("start") then
      if self.back then self.flip = 0 else self:close() end
    end
    return
  end
  if input:wasPressed("a") then
    self.back = not self.back
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.back then self.back = false else self:close() end
  end
end

-- The five rows, as {label, value} in the cartridge's order.
function Gen3TrainerCard:rows()
  local game = self.game
  local save = game.save or {}
  local player = save.player or {}
  local dex = 0
  for _ in pairs((save.pokedex or {}).owned or {}) do dex = dex + 1 end
  local t = math.floor(tonumber(save.playTime) or 0)
  local id = tonumber(player.id) or 0
  local labels = self.labels
  return {
    { labels[1] or "NAME: ", player.name or Strings("PLAYER") },
    { labels[2] or "IDNo.", ("%05d"):format(id % 100000) },
    { labels[3] or "MONEY", Strings("₽%d", math.floor(save.money or 0)) },
    { labels[4] or "POKéDEX", tostring(dex) },
    { labels[5] or "TIME",
      ("%d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60) },
  }
end

-- FIRERED'S CARD: every position below is trainer_card.c's CARD_TYPE_FRLG
-- column, relative to text window 1 at tile (1,1).
local FRLG_INK = { 0.38, 0.38, 0.38 }
local FRLG_SHADOW = { 0.84, 0.84, 0.80 }

local function frlgText(text, x, y)
  local two = Font.beginTwoTone(FRLG_INK, FRLG_SHADOW)
  if not two then love.graphics.setColor(FRLG_INK[1], FRLG_INK[2], FRLG_INK[3], 1) end
  Font.draw(text, x + 8, y + 8)
  if two then Font.endTwoTone() end
  love.graphics.setColor(1, 1, 1, 1)
end

local function frlgRight(text, right, y)
  frlgText(text, right - Font.width(text), y)
end

function Gen3TrainerCard:drawFireRed(record)
  local g = love.graphics
  local Assets = require("src.render.Assets")
  local save = self.game.save or {}
  local player = save.player or {}
  local gender = player.gender == "girl" and "girl" or "boy"
  local stars = math.max(0, math.min(4, tonumber(save.trainerStars) or 0))
  local function img(key)
    local path = record.images[key]
    if not path then return nil end
    local ok, image = pcall(Assets.image, path)
    return ok and image or nil
  end
  local labels = record.labels or {}
  g.setColor(1, 1, 1, 1)
  local bg = img(("bg_%s_%d"):format(gender, stars))
  if bg then g.draw(bg, 0, 0) end

  -- the flip squashes the card toward its middle row and back out
  local sy = 1
  if self.flip then sy = math.abs(12 - self.flip) / 12 end
  g.push()
  g.translate(0, 80)
  g.scale(1, math.max(0.02, sy))
  g.translate(0, -80)
  local face = img(("%s_%s_%d"):format(self.back and "back" or "front", gender, stars))
  if face then g.draw(face, 0, 0) end

  if not self.back then
    frlgText((labels.name or "NAME: ") .. (player.name or ""), 20, 29)
    local id = tonumber(player.id) or 0
    frlgText((labels.id or "IDNo.") .. ("%05d"):format(id % 100000), 142, 10)
    frlgText(labels.money or "MONEY", 20, 56)
    frlgRight((labels.yen or "$") .. tostring(math.floor(save.money or 0)), 134, 56)
    local flags = save.flags or {}
    if flags.FLAG_G3_0829 then
      local dex = 0
      for _ in pairs((save.pokedex or {}).owned or {}) do dex = dex + 1 end
      frlgText(labels.pokedex or "POKéDEX", 20, 72)
      frlgRight(tostring(dex), 136, 72)
    end
    local t = math.floor(tonumber(save.playTime) or 0)
    frlgText(labels.time or "TIME", 20, 88)
    frlgRight(tostring(math.min(999, math.floor(t / 3600))), 119, 88)
    -- the colon blinks once a second (BlinkTimeColon)
    if math.floor((save.playTime or 0) * 1) % 2 == 0 then frlgText(":", 119, 88) end
    frlgText(("%02d"):format(math.floor(t / 60) % 60), 124, 88)

    -- the trainer, in window 2 at tile (19,5), offset 13,4
    local path = require("src.pokemon.Sprites").playerPath(self.game.data, "front",
      { kind = "trainer_card", save = save })
    if type(path) == "string" then
      local ok, pic = pcall(Assets.image, path)
      if ok and pic then g.draw(pic, 19 * 8 + 13, 5 * 8 + 4) end
    end

    -- stars from tile (15,7), badges on rows 16-17 four tiles in, three apart
    local star = img("star")
    for i = 0, stars - 1 do if star then g.draw(star, (15 + i) * 8, 7 * 8) end end
    local sheet = img("badges")
    if sheet then
      local iw, ih = sheet:getDimensions()
      for i, entry in ipairs(Badges.list(self.game.data)) do
        if i <= 8 and Badges.has(save, entry) then
          g.draw(sheet, g.newQuad((i - 1) * 16, 0, 16, 16, iw, ih), (4 + (i - 1) * 3) * 8, 16 * 8)
        end
      end
    end
  else
    frlgText(player.name or "", 138, 11)
  end
  g.pop()
  g.setColor(1, 1, 1, 1)
end

function Gen3TrainerCard:draw()
  local record = self:frlgRecord()
  if record then return self:drawFireRed(record) end
  local inset = math.max(0, math.floor((ROW_PITCH - Font.glyphHeight()) / 2))
  love.graphics.setColor(0.13, 0.34, 0.29, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
  love.graphics.setColor(0, 0, 0, 1)

  local title = Strings("%s's TRAINER CARD",
                        (self.game.save.player or {}).name
                        or Strings("PLAYER"))
  Font.draw(title, math.floor((GBA_W - Font.width(title)) / 2),
            (CARD.ty + 1) * 8 + inset)

  if self.back then
    -- the back: the link record, which this save does not keep yet, so the
    -- card says so rather than printing zeros that look like facts
    Font.draw(Strings("No link records yet."), LABEL_X,
              (CARD.ty + 4) * 8 + inset)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- THE PORTRAIT.
  --
  -- The card carried no picture at all, and the comment at the top of this
  -- file said the art was out of reach.  It is not: the player's own face is
  -- also the RIVAL'S -- whichever of the pair you did not choose is who you
  -- fight -- so both are in gTrainerFrontPicTable, and extractTrainerSprites
  -- writes field.playerForms with each one's file, read off the PKMN TRAINER
  -- rows the cartridge names BRENDAN and MAY.  Sprites.playerForm picks the
  -- one matching the save's gender, which is the same mechanism Crystal's
  -- KRIS uses.
  --
  -- Drawn before the rows so the fields sit over it if the two ever overlap,
  -- and skipped silently when there is no picture -- a cache imported before
  -- the portraits were derived must still show a usable card.
  do
    local Sprites = require("src.pokemon.Sprites")
    local path = Sprites.playerPath(self.game.data, "front",
                                    { kind = "trainer_card",
                                      save = self.game.save })
    if type(path) == "string" then
      local Assets = require("src.render.Assets")
      local okImg, img = pcall(Assets.image, path)
      if okImg and img then
        love.graphics.setColor(1, 1, 1, 1)
        local px = (CARD.tx + CARD.tw) * 8 - img:getWidth() - 8
        local py = (CARD.ty + 3) * 8
        love.graphics.draw(img, px, py)
        love.graphics.setColor(0, 0, 0, 1)
      end
    end
  end

  local y = (CARD.ty + 3) * 8 + FIRST_ROW
  for _, row in ipairs(self:rows()) do
    Font.draw(row[1], LABEL_X, y + inset)
    Font.draw(row[2], VALUE_X, y + inset)
    y = y + ROW_PITCH
  end

  -- THE BADGE ROW, at the cartridge's own coordinates: the first badge four
  -- tiles in, three tiles between them, on rows fifteen and sixteen.
  local game = self.game
  local list = Badges.list(game.data)
  for i, entry in ipairs(list) do
    if Badges.has(game.save, entry) then
      local x, y = (BADGE_FIRST_TX + (i - 1) * BADGE_STEP_TX) * 8, BADGE_TY * 8
      local image = Gen3BadgeArt.image(game.data, i)
      if image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, x, y)
      else
        -- no sheet in this cache: the block of colour this card used to draw
        love.graphics.setColor(0.95, 0.82, 0.30, 1)
        love.graphics.rectangle("fill", x + 2, y + 2, 12, 12)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3TrainerCard
