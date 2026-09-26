-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Drawing a Gen 4 model, which is the first real 3D this engine does itself.
--
-- The voxel mod has its own 3D and the tilt ground quad is one mesh with one
-- shader, but the engine core has never had a general "here is a mesh, draw
-- it" path -- so Platinum's 590 buildings, Giratina on the title, the field
-- effects and Professor Rowan's briefcase all had geometry sitting in the
-- cache with nothing able to put it on screen.
--
-- THIS IS DELIBERATELY SELF-CONTAINED.  It does not register a pipeline, does
-- not touch the world pass, and does not ask the Renderer for anything: a
-- screen creates one of these, draws it into its own canvas, and throws it
-- away.  The reason is that the first thing to use it is the starter select --
-- a menu with three Poke Balls in a briefcase -- which has no world behind it
-- and no business being part of the world's pipeline.  When the map meshes
-- arrive they will want the pipeline; a menu does not, and building for the
-- harder case first would mean neither worked.
--
-- WHAT DEPTH COSTS.  A 3D scene needs a depth buffer, which means a canvas
-- created with one and `setDepthMode` around the draw.  Both are restored
-- afterwards, unconditionally, because this runs inside somebody else's draw
-- and leaving either set turns the next 2D blit into a puzzle.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
-- The pose walk lives with the reader that produced the bytecode.  Requiring
-- an importer from a renderer is not pretty; having the same walk written
-- twice and drifting apart would be worse, and this is the walk that decides
-- where every shape stands.
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")

local Gen4Model = {}
Gen4Model.__index = Gen4Model

-- Matches Gen4ModelPack: a vertex is fourteen bytes and a coordinate is fx16.
local VERTEX_BYTES = 14
local FX16 = 4096
local UV_UNITS = 16

-- The vertex shader takes a model-view-projection matrix and nothing else.
--
-- `TransformProjectionMatrix` is LOVE's own 2D transform and is deliberately
-- ignored: the whole point here is to put clip-space coordinates out directly,
-- and mixing the two would apply the 2D camera to a 3D scene.
-- ...AND A TEXTURE TRANSFORM, which is what a Gen 4 texture animation is.
--
-- `bm_anime`'s BTA0 animations scroll, scale and rotate a material's texture
-- coordinates -- that is how Platinum's water moves and its fountains run.
-- THE UNITS ARE NORMALISED, measured rather than assumed: every scroll in that
-- archive runs its translate from 0.0 to exactly -1.0 over its own frame count
-- (the waterfall to -2.0, which is two cycles in the same time) with scale held
-- at 1.0.  A translate that lands on whole units is one full wrap of the
-- texture; texel units would have run to 16 or 64 and do not.
--
-- This port's UVs are already divided by the texture's size when the mesh is
-- built, so the transform applies directly with nothing to convert.
--
-- Two vectors rather than a mat3 because a 2x2 and an offset is all a texture
-- SRT is, and because every shape sends them on every draw -- including the
-- overwhelming majority that are identity.  Sending them ALWAYS is deliberate:
-- a uniform that is declared and not sent reads as zero, and a zero texture
-- matrix collapses every coordinate to one texel, which is a model drawn in a
-- single flat colour.
-- `yCut` IS WHAT MAKES WALK-BEHIND POSSIBLE.
--
-- Every fragment carries the model-space height it came from, and the pixel
-- stage drops the ones at or below the cut.  Drawing a building twice -- once
-- whole, under the sprites, and once with everything below head height cut
-- away, over them -- is what lets a character pass BEHIND a house: the roof
-- and upper walls are painted after the sprite, the ground floor is not, and
-- somebody standing in front of the door is still drawn in front of it.
--
-- The default is a number no geometry reaches, so a caller that does not ask
-- for a cut gets the whole model.  It is SENT ON EVERY DRAW rather than left
-- unset, because an unset uniform reads as zero and zero would quietly cut
-- every model in the game off at the waist.
local SHADER = [[
varying float vModelY;
#ifdef VERTEX
uniform mat4 mvp;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vModelY = vertex_position.y;
    return mvp * vertex_position;
}
#endif
#ifdef PIXEL
uniform vec4 uvRotScale;
uniform vec2 uvTranslate;
uniform float yCut;
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    if (vModelY <= yCut) { discard; }
    vec2 t = vec2(uvRotScale.x * uv.x + uvRotScale.y * uv.y,
                  uvRotScale.z * uv.x + uvRotScale.w * uv.y) + uvTranslate;
    vec4 texel = Texel(tex, t);
    // A Gen 4 texture keeps colour 0 transparent, and a transparent texel must
    // not write depth -- otherwise the hole punched through a leaf or a strap
    // occludes whatever is behind it.  Discarding is what makes that correct
    // rather than merely usually correct.
    if (texel.a < 0.5) { discard; }
    return texel * colour;
}
#endif
]]

-- THE SAME SHADER WITHOUT THE HEIGHT CUT, kept as a fallback.
--
-- The cut needs a `varying`, and a varying is the one part of this shader that
-- a driver can reasonably refuse -- GLES wants a precision qualifier, and some
-- older GL profiles are fussy about declaring one outside the stage blocks.
-- If it will not compile, losing walk-behind is a much smaller loss than
-- losing every model in the game, which is what `ensureShader` returning nil
-- costs: `draw` bails on a nil shader and the whole world goes black.
local SHADER_NO_CUT = [[
#ifdef VERTEX
uniform mat4 mvp;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    return mvp * vertex_position;
}
#endif
#ifdef PIXEL
uniform vec4 uvRotScale;
uniform vec2 uvTranslate;
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    vec2 t = vec2(uvRotScale.x * uv.x + uvRotScale.y * uv.y,
                  uvRotScale.z * uv.x + uvRotScale.w * uv.y) + uvTranslate;
    vec4 texel = Texel(tex, t);
    if (texel.a < 0.5) { discard; }
    return texel * colour;
}
#endif
]]

local shader
local shaderCuts = false

local function ensureShader()
  if shader ~= nil then return shader or nil end
  local ok, made = pcall(love.graphics.newShader, SHADER)
  if ok and made then
    shader, shaderCuts = made, true
    return shader
  end
  Logger.warn("gen4 model: the mesh shader with the height cut would not "
              .. "compile (%s) -- falling back to the plain one, so models "
              .. "still draw but nothing will occlude a sprite",
              tostring(made))
  local plainOk, plain = pcall(love.graphics.newShader, SHADER_NO_CUT)
  if not plainOk or not plain then
    Logger.error("gen4 model: the mesh shader would not compile (%s); "
                 .. "no 3D model will draw", tostring(plain))
    shader = false
    return nil
  end
  shader, shaderCuts = plain, false
  return shader
end

-- Whether this device got the shader that can cut a model off at a height.
-- The canopy pass asks, because baking one that cannot cut would paint whole
-- buildings over the sprites instead of only their roofs.
function Gen4Model.cutsHeight()
  ensureShader()
  return shaderCuts
end

-- ---------------------------------------------------------------------------
-- Matrices
-- ---------------------------------------------------------------------------

-- Row-major 4x4s, as flat sixteen-element tables, because that is the layout
-- Shader:send takes and converting once here beats converting at every draw.
local function identity()
  return { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 }
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

function Gen4Model.perspective(fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  return {
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) / (near - far), (2 * far * near) / (near - far),
    0, 0, -1, 0,
  }
end

-- A camera that looks at a point from a distance, around it and above it.
-- Spelled out rather than composed from a `lookAt` because the only thing that
-- ever moves it is a turntable, and two angles read better than an eye vector.
function Gen4Model.orbit(target, distance, yaw, pitch)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local rotateY = {
    cy, 0, -sy, 0,
    0, 1, 0, 0,
    sy, 0, cy, 0,
    0, 0, 0, 1,
  }
  local rotateX = {
    1, 0, 0, 0,
    0, cp, sp, 0,
    0, -sp, cp, 0,
    0, 0, 0, 1,
  }
  local translate = identity()
  translate[4] = -(target and target[1] or 0)
  translate[8] = -(target and target[2] or 0)
  translate[12] = -(target and target[3] or 0)
  local back = identity()
  back[12] = -(distance or 1)
  return multiply(back, multiply(rotateX, multiply(rotateY, translate)))
end

-- Exported beside the two camera helpers, because a caller that builds its own
-- view and projection has to combine them and re-deriving a 4x4 multiply at
-- every call site is how two of them end up disagreeing.
Gen4Model.multiply = multiply

-- A camera placed where the cartridge puts it, looking where it looks.
--
-- `orbit` above is the right shape for a turntable and the wrong one for a
-- scripted shot: Platinum's title camera is two POINTS that interpolate --
-- eye (0, 192, 600) to (-64, 192, 484) over sixty frames, target fixed at
-- (0, 100, -18) -- and turning a pair of points into a distance and two
-- angles to hand to `orbit` would throw away the straight line between them.
function Gen4Model.lookAt(eye, target, up)
  up = up or { 0, 1, 0 }
  local fx, fy, fz = target[1] - eye[1], target[2] - eye[2], target[3] - eye[3]
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
  if fl < 1e-6 then fl = 1 end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local sx = fy * up[3] - fz * up[2]
  local sy = fz * up[1] - fx * up[3]
  local sz = fx * up[2] - fy * up[1]
  local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
  -- Looking straight down the up axis: any side vector will do, and picking
  -- one is better than dividing by zero.
  if sl < 1e-6 then sx, sy, sz, sl = 1, 0, 0, 1 end
  sx, sy, sz = sx / sl, sy / sl, sz / sl
  local ux = sy * fz - sz * fy
  local uy = sz * fx - sx * fz
  local uz = sx * fy - sy * fx
  return {
    sx, sy, sz, -(sx * eye[1] + sy * eye[2] + sz * eye[3]),
    ux, uy, uz, -(ux * eye[1] + uy * eye[2] + uz * eye[3]),
    -fx, -fy, -fz, (fx * eye[1] + fy * eye[2] + fz * eye[3]),
    0, 0, 0, 1,
  }
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- new(record) -> model, or nil when the record carries nothing drawable.
--
-- `record` is one entry of the cache's `gen4_models`: a name, a position scale
-- and a list of shapes, each with its packed vertices, its packed indices and
-- the texture its material wears.
function Gen4Model.new(record)
  if type(record) ~= "table" or type(record.shapes) ~= "table" then return nil end
  if not ensureShader() then return nil end

  local self = setmetatable({}, Gen4Model)
  self.name = record.name
  self.posScale = record.posScale or 1
  self.bounds = record.bounds
  self.shapes = {}
  -- The model's own node transforms and the bytecode that arranges them.  A
  -- model whose nodes are all identity -- most of them -- poses to identity
  -- and costs nothing; the briefcase's do the work.
  self.nodes = record.nodes or {}
  self.ops = record.ops or {}

  for _, shape in ipairs(record.shapes) do
    local image
    if shape.image then
      local ok, loaded = pcall(Assets.image, shape.image)
      if ok and loaded then
        image = loaded
        -- Nearest, always: these are 16 and 64 pixel textures on a model that
        -- will be drawn several times their own size, and smoothing them turns
        -- a Poke Ball's seam into a smear.
        image:setFilter("nearest", "nearest")
        image:setWrap("repeat", "repeat")
      end
    end

    -- The texture's own size is what turns a coordinate in sixteenths of a
    -- texel into the 0-1 the sampler wants.  Without an image there is nothing
    -- to divide by and the shape draws untextured, which is what an untextured
    -- material means anyway.
    local tw, th = 1, 1
    if image then tw, th = image:getDimensions() end

    local count = shape.vertexCount or 0
    local vertices = {}
    -- The shape's own box, kept while the vertices are still here.  It is what
    -- `framing` works from: the header states a bounding box too, but it does
    -- not agree with the geometry on two thirds of this cartridge's models, so
    -- the measured one is the one to trust.
    local lo = { math.huge, math.huge, math.huge }
    local hi = { -math.huge, -math.huge, -math.huge }
    for i = 0, count - 1 do
      local at = i * VERTEX_BYTES
      local r, g, b = shape.vertices:byte(at + 11, at + 13)
      local x = s16(shape.vertices, at) / FX16 * self.posScale
      local y = s16(shape.vertices, at + 2) / FX16 * self.posScale
      local z = s16(shape.vertices, at + 4) / FX16 * self.posScale
      if x < lo[1] then lo[1] = x end
      if y < lo[2] then lo[2] = y end
      if z < lo[3] then lo[3] = z end
      if x > hi[1] then hi[1] = x end
      if y > hi[2] then hi[2] = y end
      if z > hi[3] then hi[3] = z end
      vertices[i + 1] = {
        x, y, z,
        s16(shape.vertices, at + 6) / UV_UNITS / tw,
        s16(shape.vertices, at + 8) / UV_UNITS / th,
        r or 255, g or 255, b or 255, 255,
      }
    end
    if #vertices > 0 then
      local map = {}
      for i = 0, (shape.triangleCount or 0) * 3 - 1 do
        local a, b = shape.indices:byte(i * 2 + 1, i * 2 + 2)
        -- Back to one-based, which is what setVertexMap takes.
        map[i + 1] = (a + b * 256) + 1
      end

      local okMesh, mesh =
        pcall(love.graphics.newMesh, FORMAT, vertices, "triangles", "static")
      if okMesh and mesh then
        if #map > 0 then pcall(mesh.setVertexMap, mesh, map) end
        if image then mesh:setTexture(image) end
        self.shapes[#self.shapes + 1] =
          { mesh = mesh, name = shape.name, index = shape.index,
            -- The MATERIAL, kept because a texture animation names one.  It
            -- was being dropped here, which is why nothing could have driven
            -- an animation even once the animation was decoded.
            material = shape.material,
            image = image,
            lo = lo, hi = hi }
      else
        Logger.warn("gen4 model %s: shape %s would not build (%s)",
                    tostring(record.name), tostring(shape.name), tostring(mesh))
      end
    end
  end

  if #self.shapes == 0 then return nil end
  return self
end

-- framing(pose) -> centre, distance
--
-- The model's own centre and how far away a camera has to sit to see all of
-- it, measured off the geometry IN THE POSE IT WILL BE DRAWN IN.  A pose
-- matters here: the briefcase's three Poke Balls are 60 units apart only once
-- their nodes have placed them, and framing the unposed shapes would put the
-- camera close enough to lose two of them off the sides.
function Gen4Model:framing(pose)
  pose = pose or self:restPose()
  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }
  for _, shape in ipairs(self.shapes) do
    local m = pose[shape.index]
    for corner = 0, 7 do
      local p = {
        (corner % 2 == 0) and shape.lo[1] or shape.hi[1],
        (math.floor(corner / 2) % 2 == 0) and shape.lo[2] or shape.hi[2],
        (math.floor(corner / 4) % 2 == 0) and shape.lo[3] or shape.hi[3],
      }
      if m then
        p = {
          m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4],
          m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8],
          m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12],
        }
      end
      for k = 1, 3 do
        if p[k] < lo[k] then lo[k] = p[k] end
        if p[k] > hi[k] then hi[k] = p[k] end
      end
    end
  end
  if lo[1] > hi[1] then return { 0, 0, 0 }, 4 end
  local centre = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
  local extent = math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
  return centre, math.max(0.001, extent) * 1.8
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- The rest pose: every shape's place with the model's own node transforms.
-- Built once and kept, because a model with identity nodes would otherwise
-- redo the same walk every frame to arrive at nothing.
function Gen4Model:restPose()
  if not self.rest then
    local nodes = self.nodes
    self.rest = Gen4Nsbmd.pose(self.ops, function(index)
      local node = nodes[index + 1]
      return node and node.matrix
    end)
  end
  return self.rest
end

-- posed(matrixOf) -> { [shape index] = 4x4 }
--
-- The same walk with somebody else's matrices: `matrixOf(node)` returns a
-- joint animation's frame, and a node the animation does not cover falls back
-- to the model's own.  That fallback is not a nicety -- an animation with
-- fewer joints than the model has nodes would otherwise collapse the rest to
-- the origin, which reads as geometry gone missing rather than as a mismatch.
function Gen4Model:posed(matrixOf)
  if not matrixOf then return self:restPose() end
  local nodes = self.nodes
  return Gen4Nsbmd.pose(self.ops, function(index)
    return matrixOf(index) or (nodes[index + 1] and nodes[index + 1].matrix)
  end)
end

-- draw(viewProjection, pose) -- into whatever canvas is set.
--
-- One matrix send per shape rather than one per model, because each shape
-- stands where its node puts it.  `pose` is what `restPose` or `posed`
-- returned; leaving it out draws the rest pose.
--
-- The depth mode is set and RESTORED here rather than left to the caller.
-- This is called from inside a screen's draw, and a depth test left switched
-- on makes the next ordinary 2D draw vanish or show through in ways that look
-- like a bug in the thing that comes after it.
-- One of a flipbook's frames, by the path the import stage wrote it under.
-- Cached per model, and a path that will not load is remembered as `false` so
-- a missing frame is asked for once rather than once a frame.
function Gen4Model:frameImage(path)
  if type(path) ~= "string" then return nil end
  self.frames = self.frames or {}
  if self.frames[path] == nil then
    local ok, loaded = pcall(Assets.image, path)
    if ok and loaded then
      loaded:setFilter("nearest", "nearest")
      loaded:setWrap("repeat", "repeat")
      self.frames[path] = loaded
    else
      Logger.warn("gen4 model %s: animation frame %s would not load",
                  tostring(self.name), tostring(path))
      self.frames[path] = false
    end
  end
  return self.frames[path] or nil
end

-- The identity texture transform, sent for every shape that has no animation
-- on it -- which is nearly all of them, nearly all of the time.
local UV_IDENTITY = { 1, 0, 0, 1 }
local UV_NO_SHIFT = { 0, 0 }

-- draw(viewProjection, pose, materials)
--
-- `materials` is optional and maps a MATERIAL NAME to what this frame does to
-- it: `{ uv = { a, b, c, d, tx, ty }, image = <path> }`.  Both halves are
-- optional -- a BTA0 supplies the first, a BTP0 the second -- and a material
-- with no entry draws exactly as it did before this parameter existed.
--
-- `image` is a PATH and the loading is done here, once per path, because the
-- caller is a per-frame animation evaluator and asking it to hold LOVE Images
-- would put an asset cache in a file that has no business owning one.
local NO_CUT = -1.0e9

-- A MATERIAL'S POLYGON ALPHA, 0..31, and what to do when the cache predates it.
--
-- `polyAttr` bits 16..20 are the DS's per-material alpha and 31 is opaque.  A
-- building's ground shadow is 9 -- measured off `funsui` in the cartridge,
-- where the two ordinary materials are 31 and `h_kage` is 9.  Without it every
-- shadow drew at full strength, and its texture is a 16x16 of palette index 0
-- which on that material is opaque BLACK, not transparent: *"there are shadows
-- for the houses but they're showing as black"*.  They were exactly black.
local ALPHA_MAX = 31

-- THE FALLBACK IS A MEASUREMENT, NOT A GUESS.  `h_kage` is the cartridge's one
-- shadow texture and it is 9/31 on every material that wears it, so a cache
-- written before `alpha` existed can still be drawn correctly by name.  It
-- costs one string match on 153 of the 590 building models and lets the fix
-- land without a re-import; a cache that carries the real value never consults
-- it.
local SHADOW_ALPHA = 9
local function shapeAlpha(shape)
  local stated = tonumber(shape.alpha)
  if stated then return math.min(stated, ALPHA_MAX) / ALPHA_MAX end
  local name = tostring(shape.material or shape.texture or "")
  if name:lower():find("kage", 1, true) then return SHADOW_ALPHA / ALPHA_MAX end
  return 1
end

function Gen4Model:draw(viewProjection, pose, materials, yCut)
  local g = love.graphics
  if not (shader and viewProjection) then return false end
  pose = pose or self:restPose()
  local previousShader = g.getShader()
  local mode, write = g.getDepthMode()
  local culling = g.getMeshCullMode()

  g.setShader(shader)
  g.setDepthMode("less", true)
  -- BACK FACES ARE NOT CULLED, and that is the cartridge's own choice rather
  -- than laziness: a DS polygon carries its own front/back flags in its
  -- material, plenty of Gen 4 geometry is single-sided sheets meant to be seen
  -- from either side, and culling them uniformly loses the far wall of the
  -- briefcase.  With a depth buffer the cost of drawing both is a few
  -- overdrawn pixels.
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1, 1)
  if shaderCuts then shader:send("yCut", tonumber(yCut) or NO_CUT) end
  for _, shape in ipairs(self.shapes) do
    -- Per shape, because a model mixes opaque walls with a translucent shadow
    -- and one colour for the whole model would make one of them wrong.
    g.setColor(1, 1, 1, shapeAlpha(shape))
    local place = pose[shape.index]
    shader:send("mvp", place and multiply(viewProjection, place) or viewProjection)

    local state = materials and shape.material and materials[shape.material]
    local uv = state and state.uv
    if uv then
      shader:send("uvRotScale", { uv[1], uv[2], uv[3], uv[4] })
      shader:send("uvTranslate", { uv[5] or 0, uv[6] or 0 })
    else
      shader:send("uvRotScale", UV_IDENTITY)
      shader:send("uvTranslate", UV_NO_SHIFT)
    end

    -- A BTP0 swaps which picture the material wears.  Swapped back afterwards
    -- rather than left: the mesh is shared with the baked copy of this model,
    -- and a texture left on it is a door stuck open everywhere else it appears.
    local swapped = state and state.image and self:frameImage(state.image)
    if swapped then shape.mesh:setTexture(swapped) end
    g.draw(shape.mesh)
    if swapped then
      if shape.image then shape.mesh:setTexture(shape.image)
      else shape.mesh:setTexture() end
    end
  end

  g.setMeshCullMode(culling)
  g.setDepthMode(mode, write)
  g.setShader(previousShader)
  return true
end

-- A canvas that can hold a depth buffer, which an ordinary one cannot.
--
-- Returned as a pair because LOVE wants them handed back together
-- (`setCanvas { colour, depthstencil = depth }`), and a caller that kept only
-- the colour one would get a scene with no depth test and no error.
-- THE DEPTH FORMATS TO TRY, best first.
--
-- `depth24` alone is not a safe ask.  It is the common desktop format and the
-- one to prefer, but plenty of drivers -- Intel integrated parts and anything
-- going through ANGLE especially -- expose only the packed depth+stencil
-- combination, and a few mobile-derived ones only ever offer `depth16`.  A
-- single ask meant one unsupported format turned the WHOLE 3D path off and
-- left a flat world that looked like a bug in the camera rather than a
-- capability that was never there.
local DEPTH_FORMATS = { "depth24", "depth24stencil8", "depth32f", "depth16" }

-- Worked out once: `newCanvas` is not free to call speculatively, and the
-- answer cannot change while the game is running.
local depthFormat, depthChecked = nil, false

local function chooseDepthFormat()
  if depthChecked then return depthFormat end
  depthChecked = true
  -- ASK BEFORE TRYING.  `getCanvasFormats` is the driver's own list, so a
  -- format it does not name is one no amount of retrying will produce.
  local ok, supported = pcall(love.graphics.getCanvasFormats)
  for _, format in ipairs(DEPTH_FORMATS) do
    if not ok or supported == nil or supported[format] then
      local made, canvas = pcall(love.graphics.newCanvas, 8, 8,
                                 { format = format, readable = false })
      if made and canvas then
        depthFormat = format
        if canvas.release then canvas:release() end
        Logger.info("gen4 model: depth buffer format %s", format)
        return depthFormat
      end
    end
  end
  Logger.warn("gen4 model: no depth canvas format available (tried %s); "
              .. "3D models cannot be drawn on this device",
              table.concat(DEPTH_FORMATS, ", "))
  return nil
end

function Gen4Model.newTarget(width, height)
  local format = chooseDepthFormat()
  if not format then return nil end
  local okColour, colour = pcall(love.graphics.newCanvas, width, height)
  if not okColour or not colour then return nil end
  local okDepth, depth = pcall(love.graphics.newCanvas, width, height,
                               { format = format, readable = false })
  if not okDepth or not depth then
    -- Without a depth buffer the model would draw in submission order, which
    -- on a solid object means the back of it in front.  Better to draw nothing
    -- and say why.
    Logger.warn("gen4 model: %s canvas of %dx%d failed (%s); "
                .. "3D models cannot be drawn at this size",
                format, width, height, tostring(depth))
    return nil
  end
  colour:setFilter("nearest", "nearest")
  return colour, depth
end

return Gen4Model
