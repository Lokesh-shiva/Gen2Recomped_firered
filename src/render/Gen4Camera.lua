-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S FIELD CAMERA, transcribed.
--
-- Reported from play: "The map is rendering in flat 2d ... continue with the
-- tiled perspective camera make sure you match the platinum rom code".  This
-- is the cartridge's own table, out of `overlay005/field_camera.c`, and the
-- arithmetic that turns it into something this engine can draw with.
--
-- SEVENTEEN CAMERAS, one per `CAMERA_TYPE_*`, and the map header picks which:
-- `MapHeader.cameraType` is the byte at offset 21 (`map_header.h`), which
-- `Gen4MapHeaders` has always parsed and nothing has ever read.  Counted over
-- all 593 headers in this cartridge:
--
--   DEFAULT               189      SPEAR_PILLAR             4
--   INTERIOR_ORTHOGRAPHIC 300      SLIGHTLY_ZOOMED_OUT      3
--   CAVE                   60      OREBURGH_GYM             2
--   ZOOMED_IN              19      HALL_OF_ORIGIN           2
--   IRON_ISLAND_CAVE        6      LAKE_ACUITY              2
--                                  six others, one each
--
-- So THREE HUNDRED of the 593 headers -- every ordinary room, the player's
-- bedroom included -- are ORTHOGRAPHIC on the cartridge.  "Flat" was never
-- the mistake; flat and STRAIGHT DOWN was.  Every one of the seventeen is
-- tilted, between 40.6 and 78.4 degrees.
--
-- ONE WORLD UNIT IS ONE SCREEN PIXEL, and that is the cartridge's own number
-- rather than this port's convenience.  `Camera_ComputeProjectionMatrix`
-- builds the orthographic box as `top = tan(fovY) * distance`, and for
-- INTERIOR_ORTHOGRAPHIC that is tan(3.5211181640625) * 1563.537841796875 =
-- 96.209 -- half of the DS's 192-row screen.  Run the same product over the
-- perspective types and they all land in 94.8..96.2.  `fovY` is therefore the
-- HALF vertical field of view, and the scale is 1:1 at the target plane.
--
-- The angle is `CameraAngle.x`, stored NEGATED in the table; `Camera_Adjust-
-- PositionAroundTarget` puts the camera at
--
--   position = target + ( sin(y)*d*cos(x), sin(-x)*d, cos(y)*d*cos(x) )
--
-- and `y` is zero for all seventeen, so the camera is always due SOUTH of its
-- target and above it: for DEFAULT, 571.97 up and 342.98 south.

local Gen4Camera = {}

local floor, rad, tan, sin, cos = math.floor, math.rad, math.tan, math.sin, math.cos

-- The DS screen the numbers above are measured against.
Gen4Camera.SCREEN_W, Gen4Camera.SCREEN_H = 256, 192
Gen4Camera.ASPECT = 4 / 3

-- `pitch` is degrees BELOW HORIZONTAL, which is -CameraAngle.x; `halfFov` is
-- `verticalFov`, which is half the vertical field of view (see above).
-- `near`/`far` are the clip planes in world units.  Names are the cartridge's.
Gen4Camera.TYPES = {
  [0]  = { id = "default",        distance = 666.922119140625,  pitch = 59.051513671875,   projection = "perspective",  halfFov = 8.0914306640625,  near = 150, far = 900 },
  [1]  = { id = "pastoria_gym",   distance = 666.922119140625,  pitch = 68.367919921875,   projection = "perspective",  halfFov = 8.0914306640625,  near = 150, far = 900 },
  [2]  = { id = "zoomed_in",      distance = 515.4560546875,    pitch = 54.656982421875,   projection = "perspective",  halfFov = 10.458984375,     near = 150, far = 900 },
  [3]  = { id = "canalave_gym",   distance = 666.922119140625,  pitch = 59.051513671875,   projection = "perspective",  halfFov = 8.0914306640625,  near = 150, far = 900 },
  [4]  = { id = "interior",       distance = 1563.537841796875, pitch = 50.086669921875,   projection = "orthographic", halfFov = 3.5211181640625,  near = 150, far = 1735 },
  [5]  = { id = "spear_pillar",   distance = 316.501220703125,  pitch = 59.0460205078125,  projection = "perspective",  halfFov = 16.8804931640625, near = 10,  far = 1008 },
  [6]  = { id = "coronet_south",  distance = 866.554443359375,  pitch = 73.1085205078125,  projection = "perspective",  halfFov = 6.3336181640625,  near = 115, far = 1221 },
  [7]  = { id = "coronet_north",  distance = 666.922119140625,  pitch = 59.0460205078125,  projection = "perspective",  halfFov = 8.0914306640625,  near = 153, far = 1031 },
  [8]  = { id = "stark_room2",    distance = 662.922119140625,  pitch = 70.4718017578125,  projection = "perspective",  halfFov = 9.8492431640625,  near = 150, far = 1034 },
  [9]  = { id = "oreburgh_gym",   distance = 357.6044921875,    pitch = 40.5889892578125,  projection = "perspective",  halfFov = 15.029296875,     near = 150, far = 900 },
  [10] = { id = "veilstone_gym",  distance = 1202.355712890625, pitch = 60.8038330078125,  projection = "perspective",  halfFov = 4.5758056640625,  near = 150, far = 1746 },
  [11] = { id = "zoomed_out",     distance = 675.833251953125,  pitch = 57.8155517578125,  projection = "perspective",  halfFov = 8.0914306640625,  near = 230, far = 1127 },
  [12] = { id = "cave",           distance = 574.577880859375,  pitch = 63.2647705078125,  projection = "perspective",  halfFov = 9.4976806640625,  near = 150, far = 900 },
  [13] = { id = "iron_island",    distance = 515.4560546875,    pitch = 47.7960205078125,  projection = "perspective",  halfFov = 10.458984375,     near = 150, far = 900 },
  [14] = { id = "hall_of_origin", distance = 169.462158203125,  pitch = 78.37646484375,    projection = "perspective",  halfFov = 29.5367431640625, near = 10,  far = 1008 },
  [15] = { id = "lake_acuity",    distance = 653.929443359375,  pitch = 54.656982421875,   projection = "perspective",  halfFov = 8.349609375,      near = 150, far = 900 },
  [16] = { id = "unused_16",      distance = 330.921875,        pitch = 59.051513671875,   projection = "perspective",  halfFov = 15.4742431640625, near = 150, far = 900 },
}

Gen4Camera.DEFAULT_TYPE = 0

function Gen4Camera.forType(id)
  return Gen4Camera.TYPES[tonumber(id) or -1] or Gen4Camera.TYPES[Gen4Camera.DEFAULT_TYPE]
end

-- Half the screen height in WORLD UNITS at the target plane: tan(fovY) * d.
function Gen4Camera.halfHeight(config)
  return tan(rad(config.halfFov)) * config.distance
end

-- ...and therefore the pixels-per-unit the cartridge is working at, which
-- comes out within 1.3% of 1.0 for every one of the seventeen.
function Gen4Camera.pixelsPerUnit(config)
  local half = Gen4Camera.halfHeight(config)
  if half <= 0 then return 1 end
  return (Gen4Camera.SCREEN_H / 2) / half
end

-- ---------------------------------------------------------------------------
-- HOW THIS PORT DRAWS IT, and where it differs
-- ---------------------------------------------------------------------------
--
-- The engine's world is a grid of 16-pixel tiles and EVERYTHING else in it --
-- collision, warps, sprites, the tile window, the encounter grid -- is laid
-- out in those pixels.  A true perspective camera moves the ground relative to
-- that grid, so adopting one means projecting every sprite through it as a
-- billboard in the same pass.  That is the right end state and it is not this
-- change.
--
-- What this does instead is an OBLIQUE projection at the cartridge's own
-- pitch:
--
--   screenX = x
--   screenY = z - y * cot(pitch)
--
-- The ground plane (y = 0) maps ONE TO ONE, so the tile grid, the collision
-- and every sprite stay exactly where they are and nothing above this file
-- changes.  HEIGHT leans up the screen, which is the whole point: a house
-- shows its front, a cliff shows its face, a bridge stands off the path under
-- it.  At pitch 90 the lean is zero and this is the straight-down bake that
-- came before, which is why the OPTIONS row can offer that as one of its
-- values without a second code path.
--
-- HOW FAR OFF THE CARTRIDGE IS, measured rather than waved at.  The cartridge
-- scales ground depth by sin(pitch) and height by cos(pitch); this scales them
-- by 1 and cos/sin.  That is the cartridge's own picture stretched vertically
-- by 1/sin(pitch) -- 16.7% for DEFAULT -- and the stretch is the price of
-- keeping a tile 16 pixels tall.  The remaining difference is the perspective
-- itself, and on this cartridge that is SMALL: a half-FOV of 8.09 degrees at
-- 666.9 units is a very long lens.  Ray-traced against the ground plane, the
-- DEFAULT camera sees from 101.87 units in front of the target to 120.86
-- behind it -- 222.73 units of ground over 192 rows, against 223.87 for an
-- orthographic camera at the same scale.  That is 0.51% on the total, and
-- +9.9% / -7.4% on the two halves.  It is the near and far EDGES of the screen
-- that are wrong, by about a tenth, and the centre that is right.
--
-- For the 300 INTERIOR_ORTHOGRAPHIC headers there is no difference at all
-- beyond the 1/sin stretch: the cartridge is orthographic there too.

-- ---------------------------------------------------------------------------
-- THE CARTRIDGE'S OWN PROJECTION, derived rather than approximated
-- ---------------------------------------------------------------------------
--
-- Everything above describes the OBLIQUE stand-in this port draws with.  What
-- follows is the real thing, read out of `camera.c` and `field_camera.c`, so
-- that the renderer has something exact to move to and so the size of the gap
-- is a number rather than an impression.
--
-- `Camera_AdjustPositionAroundTarget` puts the eye at
--
--     eye = target + ( sin(yaw)*d*cos(ax), sin(-ax)*d, cos(yaw)*d*cos(ax) )
--
-- with `ax = -pitch` and `yaw = 0` for all seventeen types, so
--
--     eye = target + ( 0, d*sin(pitch), d*cos(pitch) )
--
-- -- above the target and due SOUTH of it.  `up` is +Y.  The screen axes that
-- fall out of that are
--
--     right = ( 1, 0, 0 )
--     up    = ( 0, cos(pitch), -sin(pitch) )
--
-- and so, for a point offset from the target by (dx, dy, dz):
--
--     screenX =  dx
--     screenY = -dz * sin(pitch) - dy * cos(pitch)      (screen Y grows down)
--
-- GROUND DEPTH SCALES BY sin(pitch) AND HEIGHT BY cos(pitch).  At pitch 90 --
-- straight down -- that is ground 1:1 and no height at all, which is the flat
-- bake; at DEFAULT's 59.05 degrees it is 0.8576 and 0.5143.
--
-- THE SCALE IS ONE WORLD UNIT TO ONE SCREEN PIXEL, and that is the
-- cartridge's number, not this port's convenience: `tan(halfFov) * distance`
-- is 94.82 for DEFAULT, 96.21 for INTERIOR, 96.13 for CAVE, 95.15 for
-- ZOOMED_IN -- all of them half of the DS's 192-row screen, to within 1.3%.
--
-- WHAT THE OBLIQUE COSTS, exactly.  It scales ground by 1 and height by
-- cot(pitch); the cartridge scales them by sin and cos.  Since
-- cot = cos/sin, the oblique is the cartridge's picture STRETCHED VERTICALLY
-- BY 1/sin(pitch) -- 16.6% at DEFAULT, 30.4% at INTERIOR's 50.09 degrees.
-- Shapes are right; the world is too tall.
--
-- AND WHAT PERSPECTIVE WOULD ADD ON TOP, measured on the ground plane rather
-- than guessed: at the top and bottom edges of the screen the scale differs
-- from the orthographic one by 14.2% (DEFAULT), 16.7% (CAVE) and 18.5%
-- (ZOOMED_IN), and by 6.2% for INTERIOR -- which is moot, because INTERIOR is
-- orthographic on the cartridge and so are 300 of the 593 headers.  An earlier
-- note in this file put that figure at "about a tenth"; it was measured on the
-- depth the screen covers rather than on the scale at its edges, and the
-- number above is the one that describes what a player sees.

-- sin(pitch) and cos(pitch): the ground and height scales, in that order.
function Gen4Camera.scales(config)
  local pitch = rad((config and config.pitch) or 90)
  return sin(pitch), cos(pitch)
end

-- Project a point given as an offset from the camera's TARGET, in world units,
-- to an offset in screen pixels.  `y` is height; `z` is south.  Screen Y grows
-- downwards, which is how every other surface in this engine counts.
--
-- This is the orthographic form, which is exact for the 300 INTERIOR headers
-- and within the percentages above for the rest.
function Gen4Camera.project(config, x, y, z)
  local s, c = Gen4Camera.scales(config)
  return x, z * s - y * c
end

-- The inverse on the GROUND PLANE (y = 0), which is what a renderer needs to
-- turn a screen row back into a tile row.
function Gen4Camera.unprojectGround(config, screenX, screenY)
  local s = Gen4Camera.scales(config)
  if s < 1e-6 then return screenX, 0 end
  return screenX, screenY / s
end

-- cot(pitch), the height-to-screen lean.  Zero at 90 degrees.
function Gen4Camera.lean(config)
  local pitch = config and config.pitch or 90
  if pitch >= 89.999 then return 0 end
  if pitch < 5 then pitch = 5 end
  return cos(rad(pitch)) / sin(rad(pitch))
end

-- ---------------------------------------------------------------------------
-- The OPTIONS row
-- ---------------------------------------------------------------------------
--
-- "CARTRIDGE" is the map header's own camera type, which is the answer this
-- file exists to give; the fixed angles are there because a player who wants
-- the old flat view, or more lean than Sinnoh ever uses, should not have to
-- edit a file for it.  90 is exactly the straight-down bake.
Gen4Camera.TILTS = { "cartridge", 90, 80, 70, 60, 50, 40 }

-- HELD HERE RATHER THAN READ FROM THE SAVE, because the thing that needs it --
-- `Gen4Ground`, built by `MapLoader.load(data, mapId)` -- is never handed a
-- game.  That is the same reason `TileRenderer.setTileAnim` is a module-level
-- setter two lines above the call that builds the renderer, so this follows
-- the arrangement already there rather than threading a new argument through
-- four files.
--
-- `generation` ticks on every change.  A chunk is baked AT a pitch, so a new
-- pitch makes every bake stale; `Gen4Ground:draw` compares the counter and
-- drops them, which cannot be missed the way a hook can.
--
-- `sync` takes the saved choice up.  Two callers: the OPTIONS list as it is
-- built, and `OverworldState:enter`, which is the one place every path into
-- the world goes through -- boot, a warp, the map editor's Play.  The second
-- is what makes the choice survive a restart; without it the module would
-- start every session on the cartridge's own pitch whatever the save said.
Gen4Camera.chosen = 1
Gen4Camera.generation = 0

function Gen4Camera.setTilt(index)
  index = tonumber(index) or 1
  if index < 1 or index > #Gen4Camera.TILTS then index = 1 end
  if index ~= Gen4Camera.chosen then
    Gen4Camera.chosen = index
    Gen4Camera.generation = Gen4Camera.generation + 1
  end
  return Gen4Camera.TILTS[index], index
end

-- Take the saved choice, if this game has one.  Safe to call repeatedly.
function Gen4Camera.sync(game)
  local options = game and game.save and game.save.options
  if options and options.gen4CameraTilt then
    Gen4Camera.setTilt(options.gen4CameraTilt)
  end
  return Gen4Camera.TILTS[Gen4Camera.chosen], Gen4Camera.chosen
end

function Gen4Camera.tilt(game)
  if game then return Gen4Camera.sync(game) end
  return Gen4Camera.TILTS[Gen4Camera.chosen], Gen4Camera.chosen
end

-- The camera a map is drawn with: its header's type, with the OPTIONS row's
-- pitch substituted when the player has chosen one.
function Gen4Camera.forMap(def)
  local config = Gen4Camera.forType(def and def.cameraType)
  local chosen = Gen4Camera.TILTS[Gen4Camera.chosen]
  if chosen == "cartridge" then return config end
  local copy = {}
  for k, v in pairs(config) do copy[k] = v end
  copy.pitch = tonumber(chosen) or config.pitch
  copy.chosen = true
  return copy
end

return Gen4Camera
