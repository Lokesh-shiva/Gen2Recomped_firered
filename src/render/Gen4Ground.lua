-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SINNOH, DRAWN.
--
-- Platinum has no tileset: its world is 666 land chunks, each a 32 x 32 tile
-- square carrying an NSBMD mesh and a texture set named by the map's own area
-- record. The import stage puts all of that in the cache (see Gen4Terrain);
-- this is what turns it into pixels, and it replaces `TILESET_GEN4_STANDIN` --
-- one flat colour per terrain class, which is a legible plan of a map and is
-- not Sinnoh.
--
-- A CHUNK IS BAKED ONCE, TOP-DOWN, INTO A CANVAS, and the canvas is what the
-- map draws. That is not a shortcut around a 3D view; it is the same thing
-- `Gen3Tiles` already does with its metatile sheets, for the same reason: the
-- geometry does not change, so rasterising it every frame is work done over
-- and over to arrive at the same 512 x 512 picture. When a real camera exists
-- the meshes are already here and this becomes the flat case of it.
--
-- ONE PIXEL PER WORLD UNIT, which is what makes everything else line up: a
-- tile is 16 units and the engine draws tiles at 16 pixels, so the collision
-- grid, the warps and the sprites land on the ground without a second scale to
-- keep in step.
--
-- THE PROJECTION IS ORTHOGRAPHIC AND THE CHUNK'S ORIGIN IS ITS CENTRE.
-- `posScale` is 32 and a chunk's vertices run about -8..+8, so it spans
-- -256..+256 of its 512-unit square -- read as 0..512 seven eighths of the
-- mesh falls off the edge, which looks like a broken decoder and is
-- arithmetic. World +z is south, and a chunk bakes into a CANVAS, where clip
-- y counts the other way round -- see `topDown` for the whole of it.

local Assets = require("src.render.Assets")
local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")
local Gen4TexAnim = require("src.render.Gen4TexAnim")
local Gen4Camera = require("src.render.Gen4Camera")

local Gen4Ground = {}
Gen4Ground.__index = Gen4Ground

-- How many baked chunks to keep. Each is a 512 x 512 canvas -- a megabyte of
-- colour and its depth buffer -- and a screen shows at most four, so this is
-- room to walk about in without rebaking and a bounded cost.
Gen4Ground.CACHE = 16

-- How many chunks may bake in one frame.
--
-- One was too few: a screen shows up to four, a map entry needs all of them,
-- and at one a frame the other three showed the stand-in for three frames --
-- which with the old early-return showed nothing at all. Four is the whole
-- visible set, so a map entry pays one hitch and then nothing; walking into a
-- new chunk pays for that one.
Gen4Ground.BAKES_PER_FRAME = 4

-- The depth range the height is mapped into, and it is a PRECISION choice
-- rather than a safety margin.
--
-- Four thousand was the first guess and it spent almost all of the depth
-- buffer on heights that do not occur: a chunk's own geometry spans tens of
-- units, so two nearly coplanar surfaces -- a floor and the mat on it -- came
-- out a couple of millionths apart in clip space and fought, which reads on
-- screen as alternating rows of one surface and the other. A thousand and
-- twenty-four still clears anything in the cartridge (Mount Coronet is
-- hundreds) and gives four times the resolution to tell them apart.
local DEPTH_RANGE = 1024

-- An orthographic top-down matrix, in the same row-major layout
-- `Gen4Model.perspective` returns.
--
-- CLIP Y COUNTS THE OTHER WAY INTO A CANVAS, and this row used to be -1/half,
-- which baked EVERY CHUNK IN SINNOH UPSIDE DOWN.  Reported from play as "the
-- map ... seems like its upside down and maps arent properly aligned nor
-- walkable areas", and the second half of that sentence is the first half's
-- consequence: the collision grid was never flipped, so a house you could see
-- at the bottom of the screen had its walls at the top and its door on the
-- wrong side of it.
--
-- `Gen4Title` already carries this trap written up -- "Giratina is showing ...
-- upside down" -- and its `FLIP_Y`; a custom `position()` returns clip
-- coordinates directly and so bypasses the projection LOVE would set up for
-- the target, and a canvas's framebuffer counts its rows the opposite way from
-- the screen.  This file was written without that compensation.
--
-- MEASURED RATHER THAN EYEBALLED, on Twinleaf Town (T01, matrix 0, chunk cell
-- 3,27):
--
--   * the four houses' collision footprints are 5x5 at the top-left and
--     bottom-right and 4x4 at the top-right and bottom-left; the baked picture
--     had the 5x5 pair at bottom-left and top-right -- mirrored
--   * all four of the map's warps sit on the BOTTOM row of their own house's
--     footprint, which is where a door is; the door model (build_model 67,
--     placed four times) sits at z = house z + 13, so +z is south in the
--     grid's terms as well as the cartridge's
--   * `Gen4Ground:heightsAt` already reads tile y as +z, so the height lookup
--     and the picture disagreed about which way south was
--   * the asymmetric gaps in the town's border (rows 1-2 only, never rows
--     29-30) rendered at the bottom of the screen
--
-- A vertical flip also reverses triangle winding.  That costs nothing here
-- because `Gen4Model:draw` sets cull mode "none"; if culling is ever turned on
-- for the ground, the winding has to be reversed with it.
--
-- AND IT IS NO LONGER STRAIGHT DOWN.  `Gen4Camera` carries Platinum's own
-- seventeen field cameras; every one of them is TILTED, between 40.6 and 78.4
-- degrees, and the map header says which.  This projects at that pitch as an
-- OBLIQUE camera:
--
--   screenX = x                       screenY = z - y * cot(pitch)
--
-- so the ground plane still maps one to one -- the tile grid, the collision
-- and every sprite stay exactly where they were, and nothing above this file
-- has to change -- while HEIGHT leans up the screen, which is what puts a
-- house's front and a cliff's face back on it.  `Gen4Camera` has the whole
-- argument, including how far that is from the cartridge's perspective one
-- (0.5% on the depth the screen covers; a tenth at its two edges).
--
-- THE CANVAS GROWS UPWARDS BY `leanPx`, because that is where the leaning
-- geometry goes: a chunk's ground still occupies rows leanPx..leanPx+512 and
-- anything standing on it reaches above that.  The blit takes the same leanPx
-- back off, so the ground lands where it always did.  Chunks are drawn north
-- to south, which is already the loop's order and is the order that has to
-- hold once one chunk's towers can overlap the next one's ground.
--
-- `MAX_RISE` is how much height the extra rows allow for.  Measured against
-- the build models this is generous -- the tallest houses are about 160 units
-- -- and terrain that climbs more than this inside one chunk loses its top few
-- rows rather than drawing over its neighbour.
local MAX_RISE = 384

-- HOW HIGH A CHARACTER REACHES, in the units the models are built in.
--
-- A tile is 16 units and an overworld sprite stands about two of them, so
-- geometry above 32 is over everybody's head.  That is the whole rule behind
-- the canopy: the part of a building higher than this can be painted AFTER the
-- sprites without ever covering one that is standing in front of it, and
-- painting it there is what lets somebody walk behind the house.
--
-- Approximate on purpose.  The exact answer depends on how far north of the
-- building the character is standing, which is a per-sprite comparison this
-- does not make; what it buys instead is occlusion at all, for one extra bake
-- and one extra blit, with no per-frame model draws.
local CANOPY_Y = 32

-- ...AND IT IS THE CARTRIDGE'S CAMERA NOW, not an oblique approximation of it.
--
-- The oblique kept the ground plane one to one and leaned height up the screen
-- by cot(pitch).  That was chosen so no sprite had to move, and it is what made
-- the world read as flat: the cartridge COMPRESSES the ground.
--
-- `Camera_AdjustPositionAroundTarget` puts the eye due south of its target and
-- above it, which gives screen axes `right = (1,0,0)` and
-- `up = (0, cos p, -sin p)`, and therefore
--
--     screenX = x                screenY = z * sin(pitch) - y * cos(pitch)
--
-- Ground depth scales by sin, height by cos.  The oblique's 1 and cot are that
-- same picture stretched vertically by 1/sin -- 16.6% at DEFAULT's 59 degrees,
-- 30.4% at an interior's 50 -- and a world stretched a third taller than it
-- should be is a world that does not read as tilted at all.
--
-- ONLY TWO COEFFICIENTS CHANGE.  Row 2 is the screen-Y row: the height term
-- goes from `-2*lean/height` to `-2*cos/height` and the ground term from
-- `2/height` to `2*sin/height`.  At pitch 90 that is sin = 1, cos = 0, which
-- collapses to exactly the straight-down matrix above it -- so the OPTIONS
-- row's 90 is still the flat bake, with no second code path.
--
-- ROW 3, THE DEPTH ROW, IS LEFT ALONE and that is deliberate rather than
-- lazy: it reads `-(y + lean*z)/DEPTH_RANGE`, and multiplying through by
-- sin(pitch) gives `-(y*sin + z*cos)/(DEPTH_RANGE*sin)` -- the true view-axis
-- depth, scaled by a positive constant.  A depth test only cares about order,
-- so the row was already right for every pitch.
local function projection(half, sinP, cosP, height)
  if cosP <= 1e-6 then
    return {
      1 / half, 0, 0, 0,
      0, 0, 1 / half, 0,
      0, -1 / DEPTH_RANGE, 0, 0,
      0, 0, 0, 1,
    }, 0
  end
  local lean = cosP / sinP
  -- The rows the chunk's own ground occupies are `2*half*sin`; everything
  -- above them is room for whatever stands on it.
  local leanPx = height - 2 * half * sinP
  return {
    1 / half, 0, 0, 0,
    0, -2 * cosP / height, 2 * sinP / height, leanPx / height,
    0, -1 / DEPTH_RANGE, -lean / DEPTH_RANGE, 0,
    0, 0, 0, 1,
  }, leanPx
end

-- ---------------------------------------------------------------------------

-- forMap(map, data) -> a ground, or nil when this is not a Gen 4 map with
-- terrain in the cache. Nil is the ordinary answer for every other
-- generation and for a Platinum cache imported before the terrain stage, and
-- the caller falls back to the tile path it always used.
function Gen4Ground.forMap(map, data)
  local terrain = data and data.gen4_terrain
  local def = map and map.def
  if not (terrain and terrain.chunks and terrain.matrices and def) then return nil end

  local grid = terrain.matrices[def.layout]
  if not (grid and grid.land) then return nil end

  local record = terrain.maps and terrain.maps[def.id]
  local set = record and terrain.sets and terrain.sets[record.texture]
  if not set then
    -- The mesh without its textures is a grey solid, which is worse than the
    -- stand-in it would be replacing.
    Logger.warn("gen4 ground: %s names no texture set; keeping the stand-in",
                tostring(def.id))
    return nil
  end

  local self = setmetatable({}, Gen4Ground)
  self.terrain = terrain
  self.def = def
  self.grid = grid
  self.set = set
  self.chunkPx = (terrain.chunkUnits or 512) * (terrain.pixelsPerUnit or 1)
  self.half = (terrain.chunkUnits or 512) / 2
  -- THE MAP'S OWN CAMERA, by the `cameraType` byte in its header.  A cache
  -- imported before that byte was carried through has no `cameraType`, and
  -- `Gen4Camera.forType` answers DEFAULT for it -- which is the right answer
  -- for the 189 headers that use it and a tilted one for the rest, rather than
  -- the straight-down view that was never any map's.
  self:applyCamera()
  -- Where this map's corner sits in its matrix, in pixels. A map cropped out
  -- of a shared matrix draws the same chunks; it just starts part way in.
  self.offsetX = (def.originX or 0) * 16
  self.offsetY = (def.originY or 0) * 16
  self.baked = {}
  self.canopies = {}
  self.order = {}
  -- The building models, by index into `build_model.narc`, built on first use.
  -- An absent set is not a failure: a cache imported before the buildings were
  -- extracted draws the floors and nothing on them, which is what it did
  -- before and is better than refusing to draw the ground.
  self.buildingSet = ((data.gen4_models or {}).sets or {}).buildings
  self.buildings = {}
  -- The texture animations, by the name of the model they drive.  `bm_anime`
  -- and `build_model` are separate archives, so this is the one place the two
  -- meet at run time -- and it is built once per map rather than searched.
  self.animsByName = {}
  local field = ((data.gen4_models or {}).sets or {}).field
  for _, record in ipairs((field or {}).animations or {}) do
    if record.name then
      local list = self.animsByName[record.name]
      if not list then list = {} ; self.animsByName[record.name] = list end
      list[#list + 1] = record
    end
  end
  self.animated = {}     -- land -> { canvas, frame } | false
  -- The terrain mesh of a chunk that has moving props on it, held because that
  -- chunk's depth pass runs every frame.  Only those chunks, so a map with no
  -- fountains holds nothing.
  self.depthModels = {}
  self.clock = 0
  return self
end

-- The camera this map is drawn with, and everything derived from it.
--
-- Re-run whenever the OPTIONS tilt changes: the pitch is baked INTO the chunk
-- canvases, so a new pitch means the bakes are stale.  `Gen4Camera.generation`
-- ticks on every change and `draw` compares it, which is cheaper than a hook
-- and cannot be missed by a screen that forgot to call one.
function Gen4Ground:applyCamera()
  self.camera = Gen4Camera.forMap(self.def)
  self.tiltGeneration = Gen4Camera.generation
  local sinP, cosP = Gen4Camera.scales(self.camera)
  self.groundScale, self.heightScale = sinP, cosP
  self.lean = Gen4Camera.lean(self.camera)
  -- The canvas is the compressed ground plus room for what stands on it.
  self.canvasPx = math.ceil(self.chunkPx * sinP + cosP * MAX_RISE)
  self.view, self.leanPx = projection(self.half, sinP, cosP, self.canvasPx)
  -- SAY WHICH CAMERA IS IN USE, once per change.  There are two ways to end up
  -- with a flat world that look identical on screen -- the map's header naming
  -- a straight-down type, or the OPTIONS `CAM TILT` row pinned to 90 -- and
  -- without this the only way to tell them apart is to read the save.
  local camera = self.camera or {}
  local key = ("%s/%s"):format(tostring(camera.id), tostring(camera.pitch))
  if self.reportedCamera ~= key then
    self.reportedCamera = key
    Logger.info("gen4 camera: %s at %.2f deg (%s) -- ground x%.3f, height x%.3f",
                tostring(camera.id), tonumber(camera.pitch) or 0,
                camera.chosen and "chosen in OPTIONS" or "the map header's own",
                sinP, cosP)
  end
end

-- How much of a map pixel a screen row is worth, so the overworld can place
-- its camera and its sprites in the same picture the ground is drawn in.  One
-- at pitch 90, which is the flat bake and every other generation.
function Gen4Ground:scale()
  return self.groundScale or 1, self.heightScale or 0
end

-- Drop every baked chunk, keeping the store and the height data open.  The
-- tilt changed; the geometry did not.
function Gen4Ground:dropBakes()
  for _, canvas in pairs(self.baked) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.baked, self.order = {}, {}
  -- ...and the canopies, which are baked at the same pitch, go stale with it,
  -- and are a canvas per chunk exactly like the bakes above.
  for _, canvas in pairs(self.canopies or {}) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.canopies = {}
  for _, entry in pairs(self.animated or {}) do
    if type(entry) == "table" and entry.canvas and entry.canvas.release then
      pcall(entry.canvas.release, entry.canvas)
    end
  end
  for _, held in pairs(self.depthModels or {}) do
    if type(held) == "table" and held.release then pcall(held.release, held) end
  end
  self.animated, self.depthModels = {}, {}
end

-- The animation records driving one building, or nil.  `false` is cached so a
-- chunk with forty copies of a static house asks once.
-- Returns the animation records AND the model's own flipbook frames, because
-- a BTP0 is only playable when both are present and every caller needs the
-- pair.
function Gen4Ground:animationsFor(index)
  local set = self.buildingSet
  local packed = set and set.models and set.models[index + 1]
  local name = packed and packed.name
  local list = name and self.animsByName[name]
  local images = packed and packed.patternImages
  if not (list and Gen4TexAnim.animates(list, images)) then return nil end
  return list, images
end

-- ONE BUILDING, by its member index.  `false` is cached for a model that does
-- not resolve, so a chunk with fifty copies of a broken model asks once.
function Gen4Ground:building(index)
  if self.buildings[index] ~= nil then return self.buildings[index] or nil end
  local set = self.buildingSet
  local packed = set and set.models and set.models[index + 1]
  if not packed then
    self.buildings[index] = false
    return nil
  end
  local shapes = {}
  for i, s in ipairs(packed.shapes or {}) do
    shapes[#shapes + 1] = {
      name = s.name, index = i - 1,
      vertices = s.vertices, indices = s.indices,
      vertexCount = s.vertexCount, triangleCount = s.triangleCount,
      -- THE MATERIAL TRAVELS WITH THE SHAPE, and it has to.
      --
      -- This list is rebuilt rather than passed through, and it dropped
      -- `material`, `texture` and `alpha` -- so the renderer, which decides a
      -- shape's translucency from exactly those three, saw nothing to decide
      -- with and drew every one opaque.  That is why the building shadows
      -- stayed solid black after the polygon alpha was extracted and applied:
      -- the value was read off the cartridge correctly and then thrown away
      -- one function before it was used.
      material = s.material, texture = s.texture, alpha = s.alpha,
      -- 22 of the 590 carry no texture of their own.  They are drawn
      -- untextured rather than wearing a borrowed picture: a wrong picture on
      -- a building looks deliberate, and a flat one does not.
      image = s.image,
    }
  end
  if #shapes == 0 then
    self.buildings[index] = false
    return nil
  end
  local model = Gen4Model.new({ name = ("build%d"):format(index),
                                posScale = packed.posScale, shapes = shapes })
  self.buildings[index] = model or false
  return model
end

-- WHERE A BUILDING STANDS, as a row-major matrix in the chunk's own units.
--
-- The object record's x/y/z are already divided out of 20.12 fixed point by
-- `Gen4Maps.objects`, and `Gen4Model` has already multiplied the model's own
-- `posScale` into its vertices -- so both sides are in world units and this is
-- an ordinary scale-then-translate with nothing left to reconcile.
--
-- A SCALE OF ZERO IS NOT A SCALE.  Some records leave the three scale fields
-- empty, and reading those as zero collapses the model to a point -- which
-- draws nothing and looks exactly like a missing building.  Absent means one.
local function placement(object)
  local sx = (object.scaleX and object.scaleX ~= 0) and object.scaleX or 1
  local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
  local sz = (object.scaleZ and object.scaleZ ~= 0) and object.scaleZ or 1
  return {
    sx, 0,  0,  object.x or 0,
    0,  sy, 0,  object.y or 0,
    0,  0,  sz, object.z or 0,
    0,  0,  0,  1,
  }
end

-- The chunk store, opened once and read in ranges.
--
-- Not read whole: the packed geometry is 17.7 MB and a map needs a few chunks
-- of it. `File:seek` plus `File:read` is the difference between seventeen
-- megabytes resident for every Platinum session and a few hundred kilobytes.
function Gen4Ground:store()
  if self.file ~= nil then return self.file or nil end
  local path = self.terrain.chunkFile
  local fs = love and love.filesystem
  if not (path and fs and fs.newFile) then self.file = false return nil end
  local file, why = fs.newFile(Assets.resolve(path), "r")
  if not file then
    Logger.warn("gen4 ground: %s would not open (%s)", tostring(path), tostring(why))
    self.file = false
    return nil
  end
  self.file = file
  return file
end

function Gen4Ground:slice(at, bytes)
  local file = self:store()
  if not (file and bytes and bytes > 0) then return nil end
  if not file:seek(at) then return nil end
  return file:read(bytes)
end

-- The model for one chunk, rebuilt from the store in the shape `Gen4Model`
-- already takes -- which is why there is no second loader here: a terrain
-- chunk and a Poke Ball are the same kind of thing to the renderer, and the
-- only difference is where their bytes came from.
--
-- NO NODES AND NO POSE, and that is measured rather than assumed. A model's
-- shapes are placed by the matrix slot each is bound to, and across all 666
-- chunks -- 7,547 shapes -- EVERY shape is bound to slot 0. Thirty-three
-- chunks do carry more than one node and 207 node matrices are not the
-- identity, so the nodes are not absent; nothing places a shape with them.
-- The vertices are already in the chunk's own space, which is what the first
-- render of one off the cartridge showed and this counts.
function Gen4Ground:modelFor(land)
  local record = self.terrain.chunks[land]
  if not record then return nil end
  local shapes = {}
  for _, s in ipairs(record.shapes or {}) do
    local vertices = self:slice(s.vertexAt, s.vertexBytes)
    local indices = self:slice(s.indexAt, s.indexBytes)
    if vertices and indices then
      -- THE TEXTURE, AND THE PALETTE IT IS WORN WITH.  A shape names both,
      -- because the material does; 29 textures in this cartridge are worn with
      -- two different palettes and are filed under "<texture>#<palette>" as
      -- well as under their own name.  Everything else is filed once, so the
      -- second lookup misses and the first answers.
      local textures = self.set.textures
      local texture = s.texture and
        ((s.palette and textures[s.texture .. "#" .. s.palette])
         or textures[s.texture])
      shapes[#shapes + 1] = {
        name = s.name,
        index = #shapes,
        vertices = vertices, indices = indices,
        vertexCount = s.vertexCount, triangleCount = s.triangleCount,
        image = texture and texture.path or nil,
      }
    end
  end
  if #shapes == 0 then return nil end
  return Gen4Model.new({ name = ("chunk%d"):format(land),
                         posScale = record.posScale, shapes = shapes })
end

-- bake(land) -> a canvas, or nil.
function Gen4Ground:bake(land)
  local model = self:modelFor(land)
  if not model then return nil end
  local px = self.chunkPx
  local colour, depth = Gen4Model.newTarget(px, self.canvasPx)
  if not colour then
    -- No depth buffer on this device. Everything else still works; the ground
    -- keeps the stand-in rather than being drawn back to front.
    self.noDepth = true
    return nil
  end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ colour, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  local view = self.view
  model:draw(view)

  -- ...AND THE BUILDINGS STANDING ON IT, into the same canvas and the same
  -- depth buffer.  They are baked with the floor rather than drawn every frame
  -- for the reason the floor is: the geometry does not change, and a town with
  -- forty houses would otherwise be forty model draws a frame to arrive at the
  -- picture that was already there.
  --
  -- The depth buffer is what makes this correct rather than an overlay: a
  -- house drawn after the ground but BELOW it -- a basement, a bridge's
  -- underside -- stays hidden, which painting in order would not manage.
  local record = self.terrain.chunks[land]
  local placed, missing = 0, 0
  for _, object in ipairs((record and record.objects) or {}) do
    -- ...EXCEPT the ones that move.  A fountain baked into the floor is a
    -- fountain that never runs, and re-baking the whole chunk on the animation
    -- clock to move one of them is the cost this split exists to avoid.
    if not self:animationsFor(object.model) then
      local building = self:building(object.model)
      if building then
        building:draw(Gen4Model.multiply(view, placement(object)))
        placed = placed + 1
      else
        missing = missing + 1
      end
    end
  end

  -- SAY WHETHER ANYTHING STOOD ON THE FLOOR.
  --
  -- Reported from play: *"buildings outside are still not showing any height
  -- or 3d"*.  A chunk whose houses never baked is a flat floor, and a flat
  -- floor drawn through a correct oblique matrix looks EXACTLY like a correct
  -- floor drawn through a flat one -- so the picture cannot tell the two
  -- apart, and neither could I.  This can: 387 of the cartridge's 666 chunks
  -- carry objects, 3,476 placements between them, and if `placed` comes back 0
  -- on a chunk with objects the fault is the model lookup, not the camera.
  if not self.reportedBake then
    self.reportedBake = true
    Logger.info("gen4 ground: chunk %s baked %d building(s), %d unresolved "
                .. "(canvas %dx%d, lean %d)", tostring(land), placed, missing,
                px, self.canvasPx, math.floor(self.leanPx or 0))
  end

  g.setCanvas(previous[1] and previous or nil)
  return colour
end

-- THE PART OF A CHUNK THAT GOES OVER THE SPRITES.
--
-- Reported from play, repeatedly: *"buildings outside are still not showing
-- any height or 3d"*.  The buildings were there the whole time -- measured
-- against the cartridge's own models, Twinleaf's houses rise 45 to 58 screen
-- pixels at this camera -- but NOTHING IN THE WORLD EVER PASSED IN FRONT OF
-- THE PLAYER.  Every sprite drew over every building, so walking "behind" a
-- house put you on top of its roof, and a world nothing can occlude you in
-- reads as flat however much height its geometry has.
--
-- This is the same picture as `bake`, minus the ground floor: the terrain goes
-- in FIRST WITH THE COLOUR MASK OFF so the depth buffer still hides whatever a
-- hill should hide, and each building is then drawn with everything below
-- CANOPY_Y cut away.  Blitted after the entity pass.
function Gen4Ground:bakeCanopy(land)
  -- WITHOUT THE HEIGHT CUT THIS PASS IS WORSE THAN NOTHING: it would paint
  -- whole buildings over the sprites, so a character standing at a front door
  -- would vanish into it.  No cut, no canopy.
  if not Gen4Model.cutsHeight() then return false end
  -- A CHUNK WITH NO PROPS STILL HAS WALLS.  This used to require `objects`,
  -- which meant every interior -- where the geometry that should mask the
  -- player is the room itself -- got no canopy at all.
  local record = self.terrain.chunks[land]
  if not record then return false end
  local objects = record.objects or {}

  local px = self.chunkPx
  local canvas, depth = Gen4Model.newTarget(px, self.canvasPx)
  if not canvas then return false end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ canvas, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  local view = self.view

  local terrain = self.depthModels[land]
  if terrain == nil then
    terrain = self:modelFor(land) or false
    self.depthModels[land] = terrain
  end
  if terrain then
    local r, gr, b, a = g.getColorMask()
    g.setColorMask(false, false, false, false)
    terrain:draw(view)
    g.setColorMask(r, gr, b, a)
    -- ...AND THEN THE TERRAIN'S OWN TALL GEOMETRY, IN COLOUR.
    --
    -- A Gen 4 chunk mesh is not just a floor.  Interior walls, cliff faces and
    -- the trees that are part of the land rather than props all live in it --
    -- so a canopy made only of `objects` left exactly the things the player
    -- most obviously walks in front of.  Reported from play: *"indoor tiles
    -- don't have my character walk behind them and mask the character neither
    -- do trees, it shows me as walking on top of their tiles"*.
    --
    -- Drawn a second time with the same cut the buildings get, over the depth
    -- the pass above just laid down, so a wall still hides what is behind it.
    terrain:draw(view, nil, nil, CANOPY_Y)
  end

  local drawn = 0
  for _, object in ipairs(objects) do
    local building = self:building(object.model)
    if building then
      -- The cut is stated in WORLD units and the shader tests MODEL ones, so
      -- the object's own lift and scale come back off before it is sent.
      local scale = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
      building:draw(Gen4Model.multiply(view, placement(object)), nil, nil,
                    (CANOPY_Y - (object.y or 0)) / scale)
      drawn = drawn + 1
    end
  end

  g.setCanvas(previous[1] and previous or nil)
  -- The terrain pass alone is reason enough to keep the canvas: an interior
  -- has no props and all of its masking geometry.
  if drawn == 0 and not terrain then return false end
  return canvas
end

function Gen4Ground:canopyFor(land)
  if self.noDepth or land == nil then return nil end
  local held = self.canopies[land]
  if held ~= nil then return held or nil end
  -- ON THE SAME BUDGET AS THE GROUND, and for the same reason: walking into a
  -- town wants several chunks at once, and baking them all in the frame the
  -- map opens is a visible hitch.  A chunk with no canopy yet simply has none
  -- drawn this frame, which costs one frame of missing roofs rather than a
  -- stutter -- and the chunk's ground is already on screen, so nothing is
  -- blank while it waits.
  if (self.canopyBudget or 0) <= 0 then return nil end
  self.canopyBudget = self.canopyBudget - 1
  local made = self:bakeCanopy(land)
  self.canopies[land] = made or false
  return made or nil
end

-- The canopy pass: the same chunks `draw` just painted, in the same places,
-- carrying only what stands above head height.  Called after the sprites.
function Gen4Ground:drawCanopy(camX, camY, vw, vh)
  if self.noDepth or not self.grid then return false end
  self.canopyBudget = Gen4Ground.BAKES_PER_FRAME
  local px = self.chunkPx
  local grid = self.grid
  local sinP = self.groundScale or 1
  local left = camX + self.offsetX
  local top = camY + self.offsetY
  local x0 = math.floor(left / px)
  local y0 = math.floor(top / px)
  local x1 = math.floor((left + (vw or 0)) / px)
  local y1 = math.floor((top + (vh or 0) / sinP) / px)

  local g = love.graphics
  local r, gr, b, a = g.getColor()
  g.setColor(1, 1, 1, 1)
  local drawn = 0
  for cy = y0, y1 do
    for cx = x0, x1 do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local canopy = self:canopyFor(land)
        if canopy then
          g.draw(canopy, cx * px - left, (cy * px - top) * sinP - self.leanPx)
          drawn = drawn + 1
        end
      end
    end
  end
  g.setColor(r, gr, b, a)
  return drawn > 0
end

-- THE MOVING PROPS, on their own canvas, re-drawn when the clock moves.
--
-- The terrain is drawn into it FIRST WITH THE COLOUR MASK OFF, which fills the
-- depth buffer without painting anything.  That is what keeps a prop behind a
-- hill behind it: the canvas comes out transparent everywhere the props are
-- not, and correctly occluded everywhere they are.  Drawing the props alone
-- would have put a lake in front of the cliff above it.
function Gen4Ground:bakeAnimated(land, frame)
  local record = self.terrain.chunks[land]
  local objects = record and record.objects
  if not objects then return nil end

  local moving = {}
  for _, object in ipairs(objects) do
    local records, images = self:animationsFor(object.model)
    if records then
      moving[#moving + 1] = { object = object, records = records, images = images }
    end
  end
  if #moving == 0 then return false end

  local px = self.chunkPx
  local canvas, depth = Gen4Model.newTarget(px, self.canvasPx)
  if not canvas then return false end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ canvas, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  local view = self.view

  -- KEPT, not rebuilt.  `modelFor` reads the geometry out of the side-car file
  -- and builds a LOVE mesh per shape; calling it once a frame for every chunk
  -- with a fountain on it would cost more than the animation it is paying for.
  -- The static bake calls it once and throws it away on purpose -- it is used
  -- once -- and this one is used every frame, so this one is held.
  local terrain = self.depthModels[land]
  if terrain == nil then
    terrain = self:modelFor(land) or false
    self.depthModels[land] = terrain
  end
  if terrain then
    local r, gr, b, a = g.getColorMask()
    g.setColorMask(false, false, false, false)
    terrain:draw(view)
    g.setColorMask(r, gr, b, a)
  end

  for _, item in ipairs(moving) do
    local building = self:building(item.object.model)
    if building then
      building:draw(Gen4Model.multiply(view, placement(item.object)), nil,
                    Gen4TexAnim.materials(item.records, frame, item.images))
    end
  end

  g.setCanvas(previous[1] and previous or nil)
  return canvas
end

-- The moving-prop canvas for a chunk at the current clock, rebuilt only when
-- the clock has moved on.  `false` means this chunk has nothing that moves,
-- which is most of them, and is remembered so it is asked once.
function Gen4Ground:animatedFor(land)
  if self.noDepth or land == nil then return nil end
  local entry = self.animated[land]
  if entry == false then return nil end
  if entry and entry.frame == self.clock then return entry.canvas end

  local canvas = self:bakeAnimated(land, self.clock)
  if canvas == false or canvas == nil then
    self.animated[land] = false
    return nil
  end
  if entry and entry.canvas and entry.canvas.release then
    pcall(entry.canvas.release, entry.canvas)
  end
  self.animated[land] = { canvas = canvas, frame = self.clock }
  return canvas
end

function Gen4Ground:canvasFor(land)
  if self.noDepth or land == nil then return nil end
  local hit = self.baked[land]
  if hit ~= nil then return hit or nil end
  if self.budget <= 0 then return nil end
  self.budget = self.budget - 1

  local canvas = self:bake(land)
  self.baked[land] = canvas or false
  self.order[#self.order + 1] = land
  -- Oldest out first. A player walks in one direction, so the chunk longest
  -- unused is behind them.
  while #self.order > Gen4Ground.CACHE do
    local old = table.remove(self.order, 1)
    local dropped = self.baked[old]
    if dropped and dropped.release then pcall(dropped.release, dropped) end
    self.baked[old] = nil
    -- ...and its canopy, a third canvas of the same size, allocated per chunk
    -- exactly like the other two and just as much of a leak if forgotten.
    local canopy = self.canopies[old]
    if canopy and canopy.release then pcall(canopy.release, canopy) end
    self.canopies[old] = nil
    -- ...and its moving props, which are a second canvas of the same size and
    -- would otherwise be the leak this eviction exists to prevent.
    local moving = self.animated[old]
    if type(moving) == "table" and moving.canvas and moving.canvas.release then
      pcall(moving.canvas.release, moving.canvas)
    end
    self.animated[old] = nil
    local held = self.depthModels[old]
    if type(held) == "table" and held.release then pcall(held.release, held) end
    self.depthModels[old] = nil
  end
  return canvas
end

-- draw(camX, camY, vw, vh) -- the chunks the camera can see, in map pixels.
function Gen4Ground:draw(camX, camY, vw, vh)
  if self.noDepth then return false end
  if self.tiltGeneration ~= Gen4Camera.generation then
    self:dropBakes()
    self:applyCamera()
  end
  self.budget = Gen4Ground.BAKES_PER_FRAME
  -- One tick a frame, which is the clock every animation in this cartridge is
  -- authored against: its frame counts ARE frames.
  --
  -- DELIBERATELY NOT WRAPPED.  The obvious wrap is a round number, and every
  -- round number this archive's periods do NOT all divide into -- 16, 20, 21,
  -- 25, 60, 61, 91 and 121 are among them -- so a wrap would make every
  -- animation whose period is coprime to it jump phase once a wrap.  A Lua
  -- number counts frames exactly past any session anyone will play, so the
  -- honest clock is the one that does not pretend to a period it has not got.
  self.clock = self.clock + 1

  local px = self.chunkPx
  local grid = self.grid
  local sinP = self.groundScale or 1
  -- Camera is in MAP pixels; the matrix is what the chunks are laid out in, so
  -- the map's own corner goes back on before anything is divided.
  local left = camX + self.offsetX
  local top = camY + self.offsetY
  local x0 = math.floor(left / px)
  local y0 = math.floor(top / px)
  local x1 = math.floor((left + (vw or 0)) / px)
  -- ...AND MORE ROWS FIT ON SCREEN ONCE THE GROUND IS COMPRESSED.  A screen
  -- `vh` pixels tall shows `vh / sin(pitch)` map pixels of depth -- at the
  -- default camera that is one and a sixth again, and asking for the old range
  -- leaves a band of unpainted map along the bottom edge.
  local y1 = math.floor((top + (vh or 0) / sinP) / px)

  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local drawn = 0
  for cy = y0, y1 do
    for cx = x0, x1 do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local canvas = self:canvasFor(land)
        if canvas then
          -- `leanPx` comes back off: the canvas grew upwards, so its ground
          -- still starts at the chunk's own corner.
          -- The chunk's ground starts at its own corner, COMPRESSED -- the
          -- canvas was baked at the camera's pitch, so the only thing left to
          -- do here is put its top-left where that pitch says it goes.
          local sx = cx * px - left
          local sy = (cy * px - top) * sinP - self.leanPx
          g.draw(canvas, sx, sy)
          drawn = drawn + 1
          local moving = self:animatedFor(land)
          if moving then
            g.draw(moving, sx, sy)
          end
        end
      end
    end
  end
  return drawn > 0
end

-- ---------------------------------------------------------------------------
-- HOW HIGH THE GROUND IS
-- ---------------------------------------------------------------------------
--
-- A Gen 3 map is flat and its one elevation byte per tile is the whole story.
-- A Gen 4 map is a mesh: a bridge crosses over a path, a slope rises between
-- two tiles, a ledge has a top and a bottom at the same point. The BDHC in
-- each chunk is the cartridge's own answer -- sloped plates with a plane each
-- -- and all 666 of them parse, 8,974 plates between them.
--
-- MEASURED, over all 681,984 tile centres in the cartridge:
--
--   * 76.4% have a plate under them
--   * 0.48% have MORE THAN ONE, up to four deep -- which is the bridge case,
--     and the reason this returns a list rather than a number
--   * about 14% of WALKABLE tiles have none, and that is not a gap: a tile
--     with no plate is flat ground at the chunk's own base, which is what
--     DEFAULT is
--
-- AND IT USES THE BRUTE-FORCE LOOKUP, NOT THE STRIP INDEX. The BDHC carries a
-- scanline index for finding plates quickly, and checked against walking every
-- plate it agrees on 99.59% of tiles and DROPS a plate on 404 of 98,304 --
-- never the other way round. Thirteen plates per chunk is nothing to walk, and
-- a height that is silently absent four times in a thousand is a player
-- falling through a bridge.
Gen4Ground.DEFAULT_HEIGHT = 0

function Gen4Ground:bdhcFor(land)
  self.bdhc = self.bdhc or {}
  local hit = self.bdhc[land]
  if hit ~= nil then return hit or nil end

  local record = self.terrain.chunks[land]
  local path = self.terrain.heightFile
  local fs = love and love.filesystem
  if not (record and record.heightBytes and path and fs and fs.newFile) then
    self.bdhc[land] = false
    return nil
  end
  if self.heights == nil then
    local file = fs.newFile(Assets.resolve(path), "r")
    self.heights = file or false
  end
  local file = self.heights or nil
  if not (file and file:seek(record.heightAt)) then
    self.bdhc[land] = false
    return nil
  end
  local bytes = file:read(record.heightBytes)
  local parsed = bytes and require("src.import.Gen4Bdhc").parse(bytes)
  self.bdhc[land] = parsed or false
  return parsed
end

-- heightsAt(tileX, tileY) -> a list of world heights, highest first.
--
-- Map tile coordinates, the same ones collision and the events are in. Empty
-- means no plate, which is the chunk's base rather than a hole.
function Gen4Ground:heightsAt(tileX, tileY)
  local grid = self.grid
  local tiles = self.terrain.chunkTiles or 32
  local mx = tileX + math.floor(self.offsetX / 16)
  local my = tileY + math.floor(self.offsetY / 16)
  if mx < 0 or my < 0 then return {} end
  local cx, cy = math.floor(mx / tiles), math.floor(my / tiles)
  if cx >= grid.width or cy >= grid.height then return {} end
  local land = grid.land[cy * grid.width + cx + 1]
  local bdhc = land and self:bdhcFor(land)
  if not bdhc then return {} end

  local unit = self.terrain.tileUnits or 16
  local half = (self.terrain.chunkUnits or 512) / 2
  -- The centre of the tile, in the chunk's own space -- which is centred on
  -- the origin, so the half-square comes off.
  local x = ((mx % tiles) + 0.5) * unit - half
  local z = ((my % tiles) + 0.5) * unit - half
  -- PLAIN NUMBERS, HIGHEST FIRST -- and this used to sort the records.
  --
  -- `Gen4Bdhc.heightsAt` answers { index = n, height = y } records, not
  -- heights, so `table.sort(list, a > b)` was asking Lua to order two TABLES,
  -- which raises; and `heightAt` below was handing its caller a record where
  -- it promised a number.  Neither had ever fired because nothing called
  -- either function -- the movement grid still reads elevation 0 -- and the
  -- moment something did it would have gone off on the first tile with two
  -- surfaces under it.  Sampled over 42,624 tiles spread across all 666
  -- chunks, 652 of them (1.5%) have more than one plate: every bridge in
  -- Sinnoh, which is exactly where a player walks.
  local records = require("src.import.Gen4Bdhc").heightsAt(bdhc, x, z) or {}
  local list = {}
  for i = 1, #records do list[i] = records[i].height end
  table.sort(list, function(a, b) return a > b end)
  return list
end

-- HOW FAR UP THE SCREEN A THING STANDING HERE IS LIFTED, in pixels.
--
-- The ground leans; whatever is standing on it has to lean with it, or a
-- character walks through the hill they are supposed to be on top of.  This is
-- the same `z - y * cot(pitch)` the chunk bake uses, applied to one point: the
-- height under a tile, times the lean.
--
-- `px`/`py` are MAP PIXELS rather than tiles, so a caller can pass a sprite's
-- own position and get an answer that changes as it walks rather than one that
-- jumps a whole tile early.  It is still a step per tile -- the BDHC's plates
-- are per region, so the ground itself steps there too -- rather than a ramp;
-- a ramp wants the plate's own plane evaluated at the exact point, which
-- `Gen4Bdhc` can do and this does not ask for yet.
--
-- The heights are cached per tile and the RAW height is what is cached, not
-- the lifted pixels: the tilt can change under this and the terrain cannot.
-- HOW FAR UP THE SCREEN THE GROUND UNDER A POINT LIFTS WHATEVER STANDS ON IT.
--
-- `height * cos(pitch)`, because that is what the camera does with a vertical
-- offset.  It was `height * cot(pitch)` to match the oblique, which lifted
-- everything by a sixth too much at the default pitch.
function Gen4Ground:rise(px, py)
  local cosP = self.heightScale or 0
  if cosP <= 1e-6 then return 0 end
  local tileX = math.floor((tonumber(px) or 0) / 16)
  local tileY = math.floor((tonumber(py) or 0) / 16)
  local cache = self.riseCache
  if not cache then cache = {} ; self.riseCache = cache end
  local key = tileY * 8192 + tileX
  local height = cache[key]
  if height == nil then
    height = self:heightAt(tileX, tileY) or 0
    cache[key] = height
  end
  return height * cosP
end

-- The one height to stand on, when the caller has no opinion: the highest.
-- A caller that DOES have one -- a player already under a bridge -- should ask
-- for the list and pick the surface nearest the height they are on.
function Gen4Ground:heightAt(tileX, tileY)
  local list = self:heightsAt(tileX, tileY)
  return list[1] or Gen4Ground.DEFAULT_HEIGHT, list
end

function Gen4Ground:release()
  for _, canvas in pairs(self.baked) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.baked, self.order = {}, {}
  -- ...and the canopies, which are baked at the same pitch, go stale with it,
  -- and are a canvas per chunk exactly like the bakes above.
  for _, canvas in pairs(self.canopies or {}) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.canopies = {}
  -- ...and the moving props' canvases and the terrain meshes held for their
  -- depth pass, which are the two things this map allocated that the loop above
  -- does not walk.
  for _, entry in pairs(self.animated or {}) do
    if type(entry) == "table" and entry.canvas and entry.canvas.release then
      pcall(entry.canvas.release, entry.canvas)
    end
  end
  for _, held in pairs(self.depthModels or {}) do
    if type(held) == "table" and held.release then pcall(held.release, held) end
  end
  self.animated, self.depthModels = {}, {}
  if self.file and self.file.close then pcall(self.file.close, self.file) end
  if self.heights and self.heights.close then pcall(self.heights.close, self.heights) end
  self.file, self.heights, self.bdhc = nil, nil, nil
end

return Gen4Ground
