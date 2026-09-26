-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Professor Rowan's briefcase, which is the first 3D this port draws itself.
--
-- Everything on this screen is the cartridge's own: `psel_all` out of
-- `ev_pokeselect` is one model holding the case, its lid, the three Poke Balls
-- and their shadows; the animation of the same name is 41 frames over its 12
-- joints, and it is what opens the case and tips the balls out in front of it.
-- The words are message bank 360 and the three species are the ones
-- `choose_starter_app.c` names.
--
-- WHAT THIS FILE INVENTS, said here so it is never mistaken for extracted
-- data, and it is now a much shorter list than it was:
--
--   * THE LIFT ON THE SELECTED BALL.  The cartridge has a 73-frame animation
--     per ball for this and they are extracted; what it does with them is app
--     code rather than data, so this raises the chosen one instead.
-- AND THE CAMERA IS NO LONGER ONE OF THEM.  It used to be: "distance and pitch
-- are chosen to frame the posed model", plus a slow endless orbit.  Every one
-- of those numbers is stated outright in `choose_starter_app.c` -- see the
-- camera block below -- and the cartridge's yaw is ZERO AND STAYS ZERO, so the
-- turntable was not a liberty, it was a thing the game does not do.
--
-- AND WHAT USED TO BE HERE.  An earlier version of this screen placed the
-- three balls itself -- a spread measured off the case's inside floor, evenly
-- divided, with the middle ball level with the others.  All of that was wrong,
-- and wrong in a way no amount of measuring the case could have fixed: the
-- positions are in the model's NODE transforms, which this engine did not read
-- until now.  The cartridge puts them at x = -30, 0 and +30 with the middle
-- one 6 units nearer the floor, and the animation then moves all three.

local Font = require("src.render.Font")
local Gen4Anim = require("src.import.Gen4Anim")
local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4StarterSelect = {}
Gen4StarterSelect.__index = Gen4StarterSelect
Gen4StarterSelect.isOpaque = true

local W, H = 256, 192

-- PLATINUM'S OWN MESSAGE BOX, and it used to be a hand-placed rectangle.
--
-- The cartridge's dialogue window is (2, 19) 27x4 tiles -- the TEXT INTERIOR --
-- with DrawMessageBoxFrame reaching two tiles left, three right, one row above
-- and one below, so the box is the full 32-tile width at rows 18..23.  This is
-- that rect in the port's convention (interior plus one tile of border), which
-- is what Font.drawDialogueBox expands.  `{ 0, 16, 32, 8 }` was two rows too
-- tall and, once the frame reader was fixed to reach past its rect, one tile
-- off the screen on each side.
local BOX = { tx = 1, ty = 18, tw = 29, th = 6 }
-- The interior's own origin, and two lines of sixteen: FONT_MESSAGE is
-- maxLetterHeight 16 with lineSpacing 0, and a four-tile window is 32 tall.
local TEXT_X = 16
local TEXT_Y = 152
local LINE_H = 16

-- !! THE MODEL IS Y-UP, AND THIS FILE USED TO ROTATE IT AS THOUGH IT WERE NOT.
--
-- There was a `Z_UP_TO_Y_UP` here, a 90-degree turn about X applied to the
-- whole scene, justified as "`psel_all` was exported with the vertical axis
-- last -- its lid reaches y = 116 in what the case model calls depth".  The
-- 116 is real and the reading of it was wrong: it is the SECOND component of
-- psel_all's box, which is Y.  (`psel_trunk` -- the case on its own, in its own
-- rest pose with the lid already swung back -- is the model that reaches 116 in
-- Z, and that is where the observation came from.)
--
-- THREE INDEPENDENT THINGS SAY Y IS UP, and any one of them settles it:
--
--   * `pmsel_bg`, the ground it stands on, measures
--     lo = (-160, 0, -304) and hi = (160, 0, 208) -- 320 by 512 units of floor
--     with EXACTLY ZERO THICKNESS IN Y.  A plane flat in an axis is a plane of
--     constant height in that axis.
--   * `SetupCamera` ends with `Camera_SetUp(&(VecFx32){0, FX32_ONE, 0})`.
--     The cartridge states its up vector and it is +Y.
--   * The header of this very file already knew.  It records the balls at
--     x = -30, 0 and +30 "with the middle one 6 units nearer the floor", and
--     the node translations are (-30, 50, 0), (0, 44, 0), (30, 50, 0): the six
--     units are in Y, so Y is the axis the floor is measured along.
--
-- Rotated, the case lay on its back, the floor stood up as a slab across the
-- corner, and the camera -- see below -- was underneath it looking up.
--
-- THE CAMERA, EVERY NUMBER OF IT FROM `choose_starter_app.c`.
--
-- `SetupCamera` opens the scene with target (0,0,0), distance 300, angle.x
-- `(-30 * 0xffff) / 360`, angle.y ZERO, fovY `(22 * 0xffff) / 360`.
-- `StartCameraMovement` then runs ONCE, over six steps, before "These are Poke
-- Balls!" is printed: angle.x -30 -> -50 degrees, distance 300 -> 200, and the
-- target's z 0 -> 36.  `AdvanceStarterMovement` is linear in the step count.
--
-- TWO CONVENTIONS TO GET RIGHT, both checked rather than assumed:
--
--   * 22 IS THE HALF ANGLE.  `NNS_G3dGlbPerspective` takes sin and cos of the
--     fov and forms `cos/sin` for the y scale, i.e. 1/tan(fov) where the
--     standard matrix has 1/tan(full/2).  The orthographic branch of
--     `Camera_ComputeProjectionMatrix` says the same thing out loud:
--     `top = tan(fovY) * distance`, which is a half-height.  So the full
--     vertical field of view is 44 degrees, which is what
--     `Gen4Model.perspective` takes.
--   * `Gen4Model.orbit` PUTS THE EYE BELOW THE TARGET FOR A POSITIVE PITCH.
--     Evaluated rather than reasoned about: orbit({0,0,0}, 300, 0, rad(-30))
--     gives eye (0, 150, 259.8), and `Camera_AdjustPositionAroundTarget`
--     computes exactly that from angle.x = -30.  So the cartridge's own signed
--     number is handed straight to `orbit` and the two agree to the decimal.
--     The old code passed +0.55, which is the same shot from underneath.
--
-- The clip planes corroborate the whole reading: the cartridge's own
-- CAMERA_DEFAULT_NEAR_CLIP 150 and FAR_CLIP 900 fit this scene at these
-- distances with room to spare (measured 174.8 to 406.7 from the eye across
-- both camera stages) -- and they would not if the scale or the distances were
-- wrong, so they are used here as stated.
local FOV_Y = math.rad(44)
local NEAR_CLIP, FAR_CLIP = 150, 900
local CAMERA_FROM = { pitch = math.rad(-30), distance = 300, targetZ = 0 }
local CAMERA_TO   = { pitch = math.rad(-50), distance = 200, targetZ = 36 }
local CAMERA_STEPS = 6

-- Straight up is Y, which is the whole point of the block above.
local SELECTED_LIFT = 12.0
local FRAME_STEP = 1             -- animation frames per engine frame

function Gen4StarterSelect:uiSize() return W, H end
function Gen4StarterSelect:wantsFillScale() return true end
function Gen4StarterSelect:wantsEdgeBleed() return false end

function Gen4StarterSelect:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

local function multiply(a, b)
  local out = {}
  for row = 0, 3 do
    for col = 0, 3 do
      local sum = 0
      for k = 0, 3 do
        sum = sum + a[row * 4 + k + 1] * b[k * 4 + col + 1]
      end
      out[row * 4 + col + 1] = sum
    end
  end
  return out
end

local function named(list, name)
  for _, item in ipairs(list or {}) do
    if item.name == name then return item end
  end
  return nil
end

function Gen4StarterSelect.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4StarterSelect)
  self.game = game
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.index = 1
  -- Which of the camera move's six steps has been taken.  It runs once, when
  -- the case finishes opening, and then stays where it stopped.
  self.camStep = 0
  self.frame = 0
  self.phase = "opening"

  local data = game.data or {}
  self.lines = (data.gen4_menus or {}).starter or {}
  self.rows = self.lines.rows or {}

  local set = ((data.gen4_models or {}).sets or {}).starter
  if not set then
    -- A cache from before the models stage.  Saying so and closing is better
    -- than an empty screen the player cannot leave.
    Logger.warn("gen4 starter select: this cache carries no starter models")
    self.unavailable = true
    return self
  end

  local record = named(set.models, "psel_all")
  self.scene = Gen4Model.new(record)
  self.ground = Gen4Model.new(named(set.models, "pmsel_bg"))
  if not self.scene then
    Logger.warn("gen4 starter select: the briefcase model would not build")
    self.unavailable = true
    return self
  end

  -- Node index by name, so a ball can be found without counting.  The two
  -- nodes per ball -- `psel_mb_a` and `psel_mb_a_` -- are its body and its
  -- lid; both move together and both take the lift.
  self.ballNodes = {}
  for i, row in ipairs(self.rows) do
    local wanted = { [tostring(row.model)] = true, [tostring(row.model) .. "_"] = true }
    local found = {}
    for index, node in ipairs(record.nodes or {}) do
      if wanted[node.name] then found[#found + 1] = index - 1 end
    end
    self.ballNodes[i] = found
  end

  -- The animation that opens it, paired by NAME with the model rather than by
  -- position in the archive: the two sit in different members and nothing but
  -- the name says they belong together.
  local animation = named(set.animations, "psel_all")
  if animation and animation.tracks then
    self.tracks = {}
    for _, track in ipairs(animation.tracks) do
      self.tracks[track.index] = track
    end
    self.frames = animation.frames or 1
  else
    -- Extracted before the tracks existed.  The rest pose is the closed case,
    -- which is honest about what is missing rather than pretending.
    Logger.warn("gen4 starter select: this cache carries no opening animation")
    self.frames = 1
  end

  return self
end

-- Where every shape stands this frame: the animation's own matrices, with the
-- chosen ball raised.  Rebuilt only when something changed, because the walk
-- is cheap but not free and most frames change nothing.
function Gen4StarterSelect:poseNow()
  local key = ("%d/%d/%s"):format(self.frame, self.index, tostring(self.phase))
  if self.poseKey == key then return self.pose end

  local lifted = {}
  if self.phase ~= "opening" then
    for _, node in ipairs(self.ballNodes[self.index] or {}) do lifted[node] = true end
  end

  local tracks, frame = self.tracks, self.frame
  self.pose = self.scene:posed(function(node)
    local track = tracks and tracks[node]
    local m = track and Gen4Anim.unpackFrame(track.matrices, frame)
    if m and lifted[node] then
      -- Straight up, which is Y -- the translation at index 8, not 12.  The
      -- lift used to go on Z and so moved the chosen ball TOWARDS the player
      -- across the floor rather than off it.
      m = { m[1], m[2], m[3], m[4],
            m[5], m[6], m[7], m[8] + SELECTED_LIFT,
            m[9], m[10], m[11], m[12],
            0, 0, 0, 1 }
    end
    return m
  end)
  self.poseKey = key
  return self.pose
end

-- ------------------------------------------------------------------- text --

function Gen4StarterSelect:pagesOf(text)
  if type(text) ~= "string" or text == "" then return { "" } end
  -- The cartridge's colour codes pick a palette row this port does not have a
  -- text style for yet; dropped rather than printed as `{COLOR 3}`.
  text = text:gsub("{COLOR %d+}", "")
  local pages = {}
  -- "\v" and "\f" are the two waits the cartridge writes -- scroll-and-wait
  -- and clear-and-wait.  This screen puts its words up a page at a time, so
  -- both are a page break here.  ("\v" was "\r" until the decoder was
  -- corrected; see Gen4Text.)
  for page in (text .. "\v"):gmatch("([^\v\f]*)[\v\f]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

function Gen4StarterSelect:say(text)
  self.pages = self:pagesOf(text)
  self.page = 1
end

function Gen4StarterSelect:currentText()
  if self.phase == "opening" or self.phase == "intro" then return self.lines.intro end
  if self.phase == "choosing" then return self.lines.choose end
  local row = self.rows[self.index]
  return row and row.offer or ""
end

-- ------------------------------------------------------------------- flow --

function Gen4StarterSelect:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4StarterSelect:confirm()
  local row = self.rows[self.index]
  if not row then return end
  self.game.stack:pop()
  if self.onChoose then self.onChoose(row.species, row) end
end

function Gen4StarterSelect:update()
  if self.unavailable then return self:close() end
  -- The camera move, once the case is open.  Six steps and then done, exactly
  -- as `AdvanceCameraMovement` runs it -- not a turntable.
  if self.phase ~= "opening" and self.camStep < CAMERA_STEPS then
    self.camStep = self.camStep + 1
  end
  local input = self.game.input
  if not input then return end
  if not self.pages then self:say(self:currentText()) end

  -- The case opens once, and then stays open.  A player who presses A while it
  -- is still opening skips to the end rather than being made to wait, which is
  -- what the cartridge does with every other unskippable flourish.
  if self.phase == "opening" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.frame = self.frames - 1
    else
      self.frame = self.frame + FRAME_STEP
    end
    if self.frame >= self.frames - 1 then
      self.frame = self.frames - 1
      self.phase = "intro"
      self:say(self:currentText())
    end
    return
  end

  if self.phase == "intro" then
    if input:wasPressed("a") or input:wasPressed("b") then
      if self.page < #self.pages then
        self.page = self.page + 1
      else
        self.phase = "choosing"
        self:say(self:currentText())
      end
    end
    return
  end

  local n = #self.rows
  if n == 0 then return end
  if input:wasPressed("left") then
    self.index = (self.index - 2) % n + 1
    self.phase = "offering"
    self:say(self:currentText())
  elseif input:wasPressed("right") then
    self.index = self.index % n + 1
    self.phase = "offering"
    self:say(self:currentText())
  elseif input:wasPressed("a") then
    if self.phase == "choosing" then
      self.phase = "offering"
      self:say(self:currentText())
    elseif self.page < #self.pages then
      self.page = self.page + 1
    else
      self:confirm()
    end
  elseif input:wasPressed("b") then
    self.phase = "choosing"
    self:say(self:currentText())
  end
end

-- ------------------------------------------------------------------- draw --

-- The scene, into a canvas of its own with a depth buffer.
--
-- A canvas rather than straight onto the UI surface because a depth test needs
-- a depth buffer attached, and the UI surface has none.  Built once and kept:
-- allocating a pair of canvases every frame is the kind of thing that only
-- shows up as a stutter on somebody else's machine.
function Gen4StarterSelect:drawScene()
  if not self.colour then
    self.colour, self.depth = Gen4Model.newTarget(W, H)
    if not self.colour then self.noDepth = true end
  end
  if self.noDepth then return nil end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)

  local pose = self:poseNow()

  -- The cartridge's two camera stages, linearly between them, and NOTHING
  -- derived from the model.  `framing` is right for a model this screen has
  -- never seen before; it is the wrong answer when the game states the shot.
  local k = math.min(self.camStep, CAMERA_STEPS) / CAMERA_STEPS
  local function lerp(a, b) return a + (b - a) * k end
  local target = { 0, 0, lerp(CAMERA_FROM.targetZ, CAMERA_TO.targetZ) }

  local projection = Gen4Model.perspective(FOV_Y, W / H, NEAR_CLIP, FAR_CLIP)
  local view = Gen4Model.orbit(target,
                               lerp(CAMERA_FROM.distance, CAMERA_TO.distance),
                               0, lerp(CAMERA_FROM.pitch, CAMERA_TO.pitch))
  local viewProjection = multiply(projection, view)

  if self.ground then self.ground:draw(viewProjection) end
  self.scene:draw(viewProjection, pose)

  g.setCanvas(previous[1] and previous or nil)
  return self.colour
end

function Gen4StarterSelect:draw()
  local g = love.graphics
  g.setColor(0.06, 0.07, 0.12, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local scene = self:drawScene()
  if scene then
    g.draw(scene, 0, 0)
  else
    -- No depth buffer on this device.  The screen still works as a menu; it
    -- simply has no picture, which is better than a briefcase drawn back to
    -- front.
    Font.draw(Strings("CHOOSE A POKéMON"), 24, 40)
  end

  Font.drawDialogueBox(BOX.tx, BOX.ty, BOX.tw, BOX.th)
  local page = self.pages and self.pages[self.page] or ""
  local y = TEXT_Y
  for line in (tostring(page) .. "\n"):gmatch("([^\n]*)\n") do
    -- The interior is two lines; the third would land on the bottom border.
    if y >= TEXT_Y + LINE_H * 2 then break end
    Font.draw(line, TEXT_X, y)
    y = y + LINE_H
  end

  -- The three names under the case, with the chosen one marked.  The cartridge
  -- puts these on the bottom screen, which this port does not have yet.
  if self.phase ~= "opening" and self.phase ~= "intro" and #self.rows > 0 then
    local slot = math.floor(W / #self.rows)
    for i, row in ipairs(self.rows) do
      local x = (i - 1) * slot + 8
      if i == self.index then
        Font.drawCode(Theme.cursor, x - 8, (BOX.ty - 2) * 8)
      end
      Font.draw(tostring(row.name or ""), x, (BOX.ty - 2) * 8)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4StarterSelect
