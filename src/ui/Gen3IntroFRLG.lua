-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FIRERED'S OWN BOOT INTRO -- not Emerald's bike-ride attract movie, which
-- Gen3Intro.lua is and which every Gen 3 cache used to boot into, FireRed
-- included.  Reported from play: "are the starting animations... like the
-- intro animation... working well?" -- they were real Emerald art on real
-- Emerald beats, just the wrong cartridge's.
--
-- pret's intro.c stages: a GAME FREAK logo (star, sparkles, the name, then
-- the mark itself), then three scenes -- a close-up of grass, a forest pan
-- that lands on a Gengar/Nidorino close-up, then a fight between them --
-- before handing off to the title screen.
--
-- EVERY BEAT BELOW IS A REAL `this->timer` COMPARISON, read off the matching
-- `IntroCB_*` state in pret's intro.c and cited by line.  Where a state
-- instead waits on an ANIMATION finishing (Scene3_NidorinoAnimIsRunning and
-- kin) rather than a fixed count, the cartridge's own duration is not a
-- table this pass reads, and the number here is this port's -- long enough
-- to read as the beat it stands for, short enough that the fight does not
-- drag. Those beats are marked RECONSTRUCTED below; every other one is real.
--
-- WHAT IS NOT EXTRACTED, same standard as Gen3Intro.lua: the star/sparkle
-- flourish over the logo, the claw-swipe and recoil-dust particles, and the
-- small wide-shot Gengar/Nidorino sprites in scene 2.  Simple shapes stand
-- in.  Every BACKGROUND is the cartridge's own art.
--
-- START, A or B skips it, same as Gen3Intro and CheckForUserInterruption.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Strings = require("src.core.Strings")

local Gen3IntroFRLG = {}
Gen3IntroFRLG.__index = Gen3IntroFRLG
Gen3IntroFRLG.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- ---------------------------------------------------------------------------
-- BEATS.  See intro.c line numbers in each comment.
-- ---------------------------------------------------------------------------

-- GF logo (IntroCB_GF_OpenWindow/Star/RevealName/RevealLogo, :1139-1297)
local T_WINDOW_OPEN  = 6     -- :1159-1163, timer+=8 until 48 (6 calls)
local T_STAR_ON      = T_WINDOW_OPEN + 30    -- :1180, small sparkles start
local T_STAR_END     = T_STAR_ON + 90        -- :1189
local T_NAME_ON      = T_STAR_END + 40       -- :1205, big sparkles' name reveal
local T_NAME_BLEND   = T_NAME_ON + 48        -- RECONSTRUCTED: blend task length (:1210 duration=48)
local T_NAME_END     = T_NAME_BLEND + 50     -- :1226
local T_LOGO_BLEND   = T_NAME_END + 16       -- RECONSTRUCTED: :1238 duration=16
local T_LOGO_BLIT    = T_LOGO_BLEND + 4      -- RECONSTRUCTED: DMA wait, :1258
local T_LOGO_HOLD    = T_LOGO_BLIT + 90      -- :1269
local T_LOGO_OUT     = T_LOGO_HOLD + 20      -- RECONSTRUCTED: :1272 duration=20
local T_LOGO_END     = T_LOGO_OUT + 20       -- :1290

-- Scene 1: the grass (IntroCB_Scene1, :1299-1372)
local T_S1_SETUP     = T_LOGO_END + 10  -- RECONSTRUCTED: DMA + palette-fade wait
local T_S1_ZOOM      = T_S1_SETUP + 20  -- :1347, bg zoom + grass-scroll starts
local T_S1_END       = T_S1_SETUP + 30  -- :1353

-- Scene 2: forest pan into the close-up (IntroCB_Scene2, :1435-1518)
local T_S2_SETUP     = T_S1_END + 10    -- RECONSTRUCTED: DMA + palette-fade wait
local T_S2_CLOSE     = T_S2_SETUP + 60  -- :1489, wide shot -> close-up cut
local T_S2_END       = T_S2_CLOSE + 60  -- :1511

-- Scene 3: entrance (IntroCB_Scene3_Entrance, :1560-1617)
local T_S3_GRASS     = T_S2_END + 16    -- :1611, the passing grass clump appears
local T_S3_ENTER_END = T_S2_END + 70    -- RECONSTRUCTED: :1613 waits for the slide-in anims

-- Scene 3: the fight (IntroCB_Scene3_Fight, :1739-1870). Sub-beats are
-- offsets from T_S3_ENTER_END; RECONSTRUCTED ones are marked.
local F_CRY_START    = 0     -- :1748 (30)
local F_CRY_END      = F_CRY_START + 30
local F_CRY_ANIM     = F_CRY_END + 40      -- RECONSTRUCTED: :1755 anim wait
local F_ATTACK_START = F_CRY_ANIM + 30     -- :1762 (30)
local F_ATTACK_LAND  = F_ATTACK_START + 45 -- RECONSTRUCTED: :1771 anim wait
local F_RECOIL_END   = F_ATTACK_LAND + 40  -- RECONSTRUCTED: :1778 anim wait
local F_HOP1_START   = F_RECOIL_END + 16   -- :1786 (16)
local F_HOP2_START   = F_HOP1_START + 20   -- RECONSTRUCTED: :1794 anim wait
local F_ATTACK2      = F_HOP2_START + 20   -- RECONSTRUCTED: :1802 anim wait
local F_NIDO_ATTACKS = F_ATTACK2 + 20      -- :1809 (20)
local F_GENGAR_BACK  = F_NIDO_ATTACKS + 15 -- RECONSTRUCTED: :1817 bounce-phase wait
local F_WHITE_START  = F_GENGAR_BACK + 1   -- :1825-1830
local F_ZOOM         = F_WHITE_START + 121 -- :1832 (timer>120 from :1826)
local F_BLACK_START  = F_ZOOM + 8          -- :1841 (8)
local F_BLACK_HOLD   = F_BLACK_START + 16  -- RECONSTRUCTED: fade wait
local F_END          = F_BLACK_HOLD + 60   -- :1856 (60)

local T_S3_FIGHT      = T_S3_ENTER_END
local T_SCENE_END     = T_S3_FIGHT + F_END

-- The grass's 3-frame animation and Gengar's 2-frame bounce both work the
-- cartridge's own way: separate poses stacked vertically on one tall bg
-- image, picked by cropping a different 128px (16-tile) band -- ChangeBgY
-- with `frame << 15`, which is 128px per step (intro.c :1390, :1658).
local ANIM_BAND_PX = 128

function Gen3IntroFRLG:uiSize() return GBA_W, GBA_H end
function Gen3IntroFRLG:wantsFillScale() return true end

function Gen3IntroFRLG:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- Same fix Gen3Intro carries: play the intro's own song rather than leaving
-- the demo silent.
function Gen3IntroFRLG:enter()
  local data = self.game and self.game.data
  local song = data and Music.special(data, "intro")
  if song and data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

function Gen3IntroFRLG.new(game, onDone)
  local self = setmetatable({}, Gen3IntroFRLG)
  self.game = game
  self.onDone = onDone
  self.frame = 0
  self.finished = false
  self.assets = ((game.data.constants or {}).gen3FRLGIntro or {}).images or {}
  self.imageCache = {}
  return self
end

function Gen3IntroFRLG:finish()
  if self.finished then return end
  self.finished = true
  pcall(Music.stop)
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen3IntroFRLG:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    self:finish()
    return
  end
  self.frame = self.frame + 1
  if self.frame >= T_SCENE_END then self:finish() end
end

-- One extracted piece, cached by path.  Returns nil for anything the
-- extraction stage could not reach, which every draw call below tolerates.
function Gen3IntroFRLG:piece(key)
  local rec = self.assets[key]
  if type(rec) ~= "table" or type(rec.path) ~= "string" then return nil end
  local image = self.imageCache[rec.path]
  if image == nil then
    local ok, img = pcall(Assets.image, rec.path)
    image = ok and img or false
    self.imageCache[rec.path] = image
  end
  if not image then return nil end
  return image, rec
end

-- A tall stacked-frame background: crop a 128px band starting at `band`.
function Gen3IntroFRLG:drawBand(key, band, x, y, w, h)
  local image, rec = self:piece(key)
  if not image then return false end
  local iw, ih = image:getDimensions()
  w, h = w or GBA_W, h or GBA_H
  local top = math.min(math.max(0, band or 0), math.max(0, ih - h))
  local quad = love.graphics.newQuad(0, top, math.min(w, iw), math.min(h, ih - top),
                                     iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, quad, x or 0, y or 0)
  return true
end

-- One frame of a side-by-side sprite sheet.
function Gen3IntroFRLG:drawFrame(key, frame, x, y)
  local image, rec = self:piece(key)
  if not image or not rec.cols then return false end
  local fw, fh = rec.cols * 8, rec.rows * 8
  local n = math.max(1, rec.frames or 1)
  local at = (math.floor(frame or 0) % n) * fw
  local iw, ih = image:getDimensions()
  local quad = love.graphics.newQuad(at, 0, fw, fh, iw, ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, quad, math.floor((x or 0) - fw / 2),
                     math.floor((y or 0) - fh / 2))
  return true
end

-- ---------------------------------------------------------------------------
-- THE GAME FREAK LOGO.
-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:drawLogo()
  local f = self.frame
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

  -- the "theatric" window bars, opening from the middle (:1157-1166)
  local openness = math.min(1, f / T_WINDOW_OPEN)
  local barH = math.floor((GBA_H / 2) * (1 - openness))
  if not self:drawBand("gfBg", 0, 0, 0) then
    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  love.graphics.setColor(0, 0, 0, 1)
  if barH > 0 then
    love.graphics.rectangle("fill", 0, 0, GBA_W, barH)
    love.graphics.rectangle("fill", 0, GBA_H - barH, GBA_W, barH)
  end
  if f < T_WINDOW_OPEN then return end

  -- the star crossing the field, RECONSTRUCTED path (real speed constants:
  -- sStarSpeedX=96, sStarSpeedY=16 in 8.8 fixed point -- intro.c :1962-1963)
  if f < T_STAR_END then
    local age = f - T_WINDOW_OPEN
    local sx = -16 + age * (96 / 256)
    local sy = 20 + age * (16 / 256)
    love.graphics.setColor(1, 1, 0.85, 1)
    love.graphics.circle("fill", sx, sy, 3)
    -- sparkles trailing it, spawn rate 8 frames (intro.c :1966)
    for i = 0, 5 do
      local born = i * 8
      local sage = age - born
      if sage >= 0 and sage < 24 then
        local a = 1 - sage / 24
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.circle("line", sx - sage * 0.4, sy - sage * 0.1, 2)
      end
    end
  end

  -- the name, fading up over :1205-1226 then blended in over BG2 (approx as
  -- a plain alpha fade -- the cartridge does it with a palette blend task)
  if f >= T_STAR_ON then
    local nameAlpha = math.min(1, (f - T_STAR_ON) / (T_NAME_BLEND - T_STAR_ON))
    if f >= T_NAME_END then nameAlpha = 1 end
    local img = self:piece("gfText")
    love.graphics.setColor(1, 1, 1, nameAlpha)
    if img then
      self:drawFrame("gfText", 0, GBA_W / 2, 100)
    else
      Font.draw(Strings("GAME FREAK"),
               math.floor((GBA_W - Font.width(Strings("GAME FREAK"))) / 2), 96)
    end
  end

  -- the mark itself, fading in over the art window on the cartridge's own
  -- beats (:1244-1275)
  if f >= T_LOGO_BLEND then
    local a = 1
    if f < T_LOGO_BLIT then a = (f - T_LOGO_BLEND) / (T_LOGO_BLIT - T_LOGO_BLEND) end
    if f >= T_LOGO_OUT then
      a = math.max(0, 1 - (f - T_LOGO_OUT) / (T_LOGO_END - T_LOGO_OUT))
    end
    love.graphics.setColor(1, 1, 1, a)
    if not self:drawFrame("gfArt", 0, GBA_W / 2, 54) then
      love.graphics.circle("fill", GBA_W / 2, 54, 18)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- SCENE 1: the grass.
-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:drawScene1()
  local f = self.frame - T_LOGO_END
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  -- the silhouette background zooms in across the cut to scene 2 (:1419-1430,
  -- the same stacked-frame trick, picked up a beat early so it reads as
  -- already moving when scene 2 opens)
  local zoomFrame = f >= T_S1_ZOOM
                    and math.min(2, math.floor((f - T_S1_ZOOM) / 4)) or 0
  self:drawBand("scene1Bg", zoomFrame * ANIM_BAND_PX, 0, 0)
  -- the grass's own 3-frame sway, on top (:1385-1391)
  local swayFrame = math.floor(f / 6) % 3
  local drewGrass = self:drawBand("scene1Grass", swayFrame * ANIM_BAND_PX, 0, 0)
  if not drewGrass and zoomFrame == 0 then
    love.graphics.setColor(0.2, 0.55, 0.2, 1)
    love.graphics.rectangle("fill", 0, GBA_H - 40, GBA_W, 40)
  end
  -- fade to white going into scene 2
  if f >= T_S1_ZOOM then
    local into = (f - T_S1_ZOOM) / (T_S1_END - T_S1_ZOOM)
    love.graphics.setColor(1, 1, 1, math.min(1, into))
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- SCENE 2: the forest pan into the close-up.
-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:drawScene2()
  local f = self.frame - T_S1_END
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  if f < T_S2_CLOSE - T_S1_END then
    -- the wide shot: background trees pan one way, foreground plants the
    -- other (Scene2_Task_PanForest, :1521-1525)
    local age = math.max(0, f - 10)
    local bgShift = -math.floor(age * 0.9)
    local fgShift = math.floor(age * 1.1)
    local bg = self:piece("scene2Bg")
    if bg then
      local iw = bg:getDimensions()
      local x = bgShift % iw
      love.graphics.draw(bg, x - iw, 0)
      love.graphics.draw(bg, x, 0)
    end
    local plants = self:piece("scene2Plants")
    if plants then
      local iw = plants:getDimensions()
      local x = fgShift % iw
      love.graphics.draw(plants, x - iw, GBA_H - 64)
      love.graphics.draw(plants, x, GBA_H - 64)
    end
  else
    -- the cut to the close-up: Gengar above, Nidorino below (:1489-1502)
    self:drawBand("scene2GengarClose", 0, 0, 0, GBA_W, 80)
    self:drawBand("scene2NidorinoClose", 0, 0, 80, GBA_W, 80)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- SCENE 3: entrance, then the fight.
-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:bgScrollX(f, fast)
  -- Scene3_Task_BgScroll: fast while the two are sliding in, slow once the
  -- passing grass clump signals the cut is settled (:1623-1629)
  local speed = fast and 4 or 0.3
  return -math.floor(f * speed)
end

function Gen3IntroFRLG:drawScene3Bg(f)
  local bg = self:piece("scene3Bg")
  love.graphics.setColor(1, 1, 1, 1)
  if bg then
    local iw = bg:getDimensions()
    local fast = f < T_S3_GRASS - T_S2_END
    local shift = self:bgScrollX(f, fast) % iw
    love.graphics.draw(bg, shift - iw, 0)
    love.graphics.draw(bg, shift, 0)
  else
    love.graphics.setColor(0.1, 0.1, 0.2, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
end

function Gen3IntroFRLG:drawScene3()
  local f = self.frame - T_S2_END
  self:drawScene3Bg(f)

  -- Gengar's idle bounce, the bg-layer stacked-frame trick (:1649-1661) --
  -- cycle through however many poses the extraction actually found, rather
  -- than assuming the cartridge's own 2
  local _, bounceRec = self:piece("scene3GengarBounce")
  local bounceRows = bounceRec and math.max(1, math.floor((bounceRec.rows or 8) * 8 / ANIM_BAND_PX)) or 1
  local bounceFrame = math.floor(f / 30) % bounceRows
  self:drawBand("scene3GengarBounce", bounceFrame * ANIM_BAND_PX, 152, 16, 64, 64)

  -- Nidorino slides in over the entrance (Scene3_StartNidorinoEntrance(0,
  -- 180, 52) -- :1603), then stands at x=180 for the fight
  local enterSpan = math.max(1, T_S3_ENTER_END - T_S2_END)
  local slideT = math.min(1, f / enterSpan)
  slideT = slideT * slideT * (3 - 2 * slideT)
  local nidoX = 0 + (180 - 0) * slideT
  self:drawFrame("scene3Nidorino", 0, nidoX, 104)

  -- the small grass clump that passes through the foreground (:1611-1612,
  -- :1702-1733)
  if f >= T_S3_GRASS then
    local age = f - T_S3_GRASS
    local gx = 296 - age * 5
    if gx > -32 then
      love.graphics.setColor(0.15, 0.4, 0.15, 1)
      love.graphics.rectangle("fill", gx, 112, 12, 10)
    end
  end

  if f < T_S3_ENTER_END - T_S2_END then return end
  local ff = f - (T_S3_ENTER_END - T_S2_END)

  -- Nidorino's cry: a small hop-in-place (RECONSTRUCTED motion on the real
  -- sprite; the cry itself is a sound the engine does not yet route here)
  if ff >= F_CRY_START and ff < F_CRY_ANIM then
    local age = ff - F_CRY_START
    local hop = math.sin(math.min(1, age / 20) * math.pi) * 6
    love.graphics.setColor(1, 1, 1, 1)
    self:drawFrame("scene3Nidorino", 0, 180, 104 - hop)
  end

  -- Gengar's attack: the four-piece back sprite converges on Nidorino
  -- (Scene3_CreateGengarSprite, :1877-1896 -- quadrant layout reconstructed
  -- from the `(i & 1) * 48 + 49` x-offset the source uses)
  if ff >= F_GENGAR_BACK then
    local age = ff - F_GENGAR_BACK
    local settle = math.min(1, age / 20)
    for i = 0, 3 do
      local qx = (i % 2) * 48 + 49
      local qy = math.floor(i / 2) * 40 + 30
      local jitter = (1 - settle) * ((i % 2 == 0) and -6 or 6)
      love.graphics.setColor(0.35, 0.2, 0.45, 1)
      love.graphics.rectangle("fill", qx + jitter - 16, qy - 16, 32, 32)
    end
  end

  -- Nidorino's recoil from the hit
  if ff >= F_ATTACK_LAND and ff < F_RECOIL_END then
    local age = ff - F_ATTACK_LAND
    local kick = math.max(0, 10 - age) * 1.5
    love.graphics.setColor(1, 1, 1, 1)
    self:drawFrame("scene3Nidorino", 0, 180 + kick, 104)
  end

  -- Nidorino's own two hops and attack lunge back at Gengar
  if ff >= F_HOP1_START and ff < F_NIDO_ATTACKS then
    local hopAge = (ff - F_HOP1_START) % 20
    local hop = math.sin(math.min(1, hopAge / 12) * math.pi) * 5
    love.graphics.setColor(1, 1, 1, 1)
    self:drawFrame("scene3Nidorino", 0, 180 - hopAge * 0.3, 104 - hop)
  elseif ff >= F_NIDO_ATTACKS and ff < F_GENGAR_BACK then
    local age = ff - F_NIDO_ATTACKS
    local lunge = math.min(1, age / 10) * 30
    love.graphics.setColor(1, 1, 1, 1)
    self:drawFrame("scene3Nidorino", 0, 180 - lunge, 104)
  elseif ff < F_HOP1_START then
    love.graphics.setColor(1, 1, 1, 1)
    self:drawFrame("scene3Nidorino", 0, 180, 104)
  end

  -- the finale: white flash, then fade to black and hold for the title cut
  -- (:1830-1857)
  if ff >= F_WHITE_START then
    local into = math.min(1, (ff - F_WHITE_START) / (F_ZOOM - F_WHITE_START))
    love.graphics.setColor(1, 1, 1, into * 0.9)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  if ff >= F_BLACK_START then
    local into = math.min(1, (ff - F_BLACK_START) / (F_BLACK_HOLD - F_BLACK_START))
    love.graphics.setColor(0, 0, 0, into)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------

function Gen3IntroFRLG:draw()
  local f = self.frame
  if f < T_LOGO_END then
    self:drawLogo()
  elseif f < T_S1_END then
    self:drawScene1()
  elseif f < T_S2_END then
    self:drawScene2()
  else
    self:drawScene3()
  end
end

return Gen3IntroFRLG
