-- Bridge to native secondary-display output (Android Presentation). The C
-- functions live in mobile/android/love/src/jni/love/src/common/android.cpp.
-- Everything is guarded: off Android, or if the symbols cannot be resolved,
-- this stays inert and the renderer keeps the in-window stacked layout.

local SecondScreen = {}
local C = nil

local function log(msg)
  pcall(function() require("src.core.Logger").info("SecondScreen: %s", msg) end)
end

do
  local ok, ffi = pcall(require, "ffi")
  if not (ok and ffi) then
    log("ffi unavailable (not LuaJIT); second display disabled")
  else
    pcall(ffi.cdef, [[
      int love_android_secondary_ready();
      void love_android_push_secondary(const void *rgba, int w, int h);
      void love_android_secondary_enable(int on);
    ]])
    local okLib, lib = pcall(ffi.load, "love")
    if okLib and lib and pcall(function() return lib.love_android_secondary_ready end) then
      C = lib
      log("bridge linked via ffi.load('love')")
    elseif pcall(function() return ffi.C.love_android_secondary_ready end) then
      C = ffi.C
      log("bridge linked via default namespace")
    else
      log(("bridge symbols not found (ffi.load ok=%s); second display disabled")
        :format(tostring(okLib)))
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE SECOND TRANSPORT: A PAIR OF FILES.
--
-- Reported from play: "the second screen isnt working on the ayn thors bottom
-- screen for platinum".  It cannot: the three C symbols above live in the
-- vendored love-android tree and nothing has compiled them, so `available`
-- answers false, `display` mode is never offered, and the bottom screen stays
-- in the window.
--
-- WHY A SECOND ONE RATHER THAN FINISHING THE FIRST.  The FFI bridge needs new
-- code inside `liblove.so`, which means the NDK sources under
-- `mobile/android/love/src/jni/...` and a full native rebuild.  This one needs
-- no native code at all: a plain Java `Presentation`, which is an ordinary
-- class in the app module, talking to Lua through two files in the save
-- directory.  Both transports answer the same three questions, so the rest of
-- the engine cannot tell them apart and the faster one wins when it exists.
--
-- THE PROTOCOL, in full, because it has two ends and only one of them is in
-- this repository's language:
--
--   second_display/host.txt   written by the HOST, once a second.  Four
--                             space-separated fields: a protocol version, the
--                             number of displays it can see, and the panel's
--                             width and height.  Its MODIFICATION TIME is the
--                             heartbeat -- a host that has gone away stops
--                             touching it and `available` goes false within
--                             `HOST_STALE`.
--   second_display/frame.bin  written by LUA.  A TWELVE-byte header -- the
--                             four characters "G2SD", then version, width,
--                             height and sequence as little-endian u16 -- then
--                             width*height*4 bytes of RGBA.  The sequence
--                             number is what tells the host a new frame has
--                             arrived without it having to compare 192KB.
--   second_display/touch.txt  written by the HOST, read and truncated by Lua.
--                             One event per line: `down|move|up id x y`, with
--                             x and y already in the panel's own 256x192.
--
-- EVERYTHING IS IN THE SAVE DIRECTORY because that is the one place LOVE can
-- write on Android without a permission, and the host can find it: it is under
-- the app's own files directory, which is the one path an Android app always
-- knows.
-- ---------------------------------------------------------------------------
SecondScreen.DIR = "second_display"
SecondScreen.HOST = SecondScreen.DIR .. "/host.txt"
SecondScreen.FRAME = SecondScreen.DIR .. "/frame.bin"
SecondScreen.TOUCH = SecondScreen.DIR .. "/touch.txt"
SecondScreen.PROTOCOL = 1
SecondScreen.MAGIC = "G2SD"
-- How long a host may go quiet before it is treated as gone.  Two seconds is
-- twice its heartbeat, so one missed write is not a disconnection.
SecondScreen.HOST_STALE = 2.0

local fileHost = nil       -- the last parsed host.txt, or false
local fileSeq = 0

local function fs()
  return love and love.filesystem
end

-- u16, little-endian, as two characters
local function u16(v)
  v = math.floor(tonumber(v) or 0) % 65536
  return string.char(v % 256, math.floor(v / 256))
end

-- Read the host's line and decide whether it is still there.  `now` is passed
-- in rather than read, so a check can drive the clock.
function SecondScreen.readHost(now)
  local f = fs()
  if not (f and f.getInfo) then return nil end
  local info = f.getInfo(SecondScreen.HOST)
  if not info then fileHost = false return nil end
  now = tonumber(now)
  if now == nil and love.timer and love.timer.getTime then
    local okNow, t = pcall(love.timer.getTime)
    now = okNow and t or nil
  end
  -- `modtime` is seconds since the epoch and `now` is LOVE's own clock, so the
  -- two cannot be subtracted.  What can be compared is the modtime against
  -- the last one seen: a host that is alive keeps changing it.
  local stamp = tonumber(info.modtime)
  local body = f.read(SecondScreen.HOST)
  if type(body) ~= "string" then fileHost = false return nil end
  local version, displays, w, h =
    body:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
  if not version then fileHost = false return nil end
  fileHost = {
    version = tonumber(version), displays = tonumber(displays),
    width = tonumber(w), height = tonumber(h), stamp = stamp, seenAt = now,
  }
  return fileHost
end

-- Is a file-protocol host attached?  A host that is present but reports no
-- second display is NOT available: the panel is what the mode needs, not the
-- host.
function SecondScreen.fileAvailable(now)
  local h = SecondScreen.readHost(now)
  if not h then return false end
  if h.version ~= SecondScreen.PROTOCOL then return false end
  return (h.displays or 0) >= 2
end

-- Hand the host a frame.  `imageData` is LOVE's own, and its string is the
-- RGBA the host blits; nothing here converts, because a conversion per frame
-- is the cost this design exists to avoid.
function SecondScreen.filePush(imageData, w, h)
  local f = fs()
  if not (f and f.write and imageData and imageData.getString) then
    return false
  end
  local okStr, body = pcall(imageData.getString, imageData)
  if not (okStr and type(body) == "string") then return false end
  fileSeq = (fileSeq + 1) % 65536
  local header = SecondScreen.MAGIC .. u16(SecondScreen.PROTOCOL)
    .. u16(w) .. u16(h) .. u16(fileSeq)
  -- WRITTEN WHOLE, then renamed, is what a reader would want -- and LOVE's
  -- filesystem has no rename.  The sequence number in the header is the
  -- answer instead: a host that reads a torn frame sees a sequence it has
  -- already drawn, or a length that does not match, and waits for the next
  -- one rather than drawing half a picture.
  local ok = pcall(f.write, SecondScreen.FRAME, header .. body)
  return ok and true or false
end

-- Everything the host has recorded since the last call, in order, and the file
-- is emptied.  Returns a list of { kind, id, x, y }.
function SecondScreen.pollTouch()
  local f = fs()
  if not (f and f.getInfo and f.read) then return nil end
  if not f.getInfo(SecondScreen.TOUCH) then return nil end
  local body = f.read(SecondScreen.TOUCH)
  if type(body) ~= "string" or body == "" then return nil end
  -- EMPTIED BEFORE THE EVENTS ARE HANDED OUT, not after: a handler that
  -- raises must not leave the same taps in the file to be replayed on every
  -- frame for the rest of the session.
  pcall(f.write, SecondScreen.TOUCH, "")
  local out = {}
  for line in body:gmatch("[^\r\n]+") do
    local kind, id, x, y = line:match("^(%a+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
    if kind == "down" or kind == "move" or kind == "up" then
      out[#out + 1] = { kind = kind, id = tonumber(id),
                        x = tonumber(x), y = tonumber(y) }
    end
  end
  if not out[1] then return nil end
  return out
end

function SecondScreen.usable()
  return C ~= nil or SecondScreen.fileAvailable()
end

-- Which transport answered, for the log and for a check to assert on.
function SecondScreen.backend()
  if C ~= nil then return "ffi" end
  if SecondScreen.fileAvailable() then return "file" end
  return nil
end

-- IS A SECOND PANEL ATTACHED RIGHT NOW.
--
-- CACHED, because src/ui/SecondScreen.lua asks this from `mode`, and `mode` is
-- asked several times per frame by every caller that has to decide where to
-- draw.  It is still RE-asked -- a display can be plugged in or pulled out
-- mid-session -- just not thousands of times a second.  The window is short
-- enough that plugging a screen in is noticed within a few frames of a second.
SecondScreen.PROBE_INTERVAL = 0.5
local probedAt, probed = nil, false

local function clock()
  if love and love.timer and love.timer.getTime then
    local ok, t = pcall(love.timer.getTime)
    if ok then return t end
  end
  return nil
end

function SecondScreen.available()
  -- The native bridge first -- it hands the host a pointer and costs nothing
  -- per frame -- then the file protocol, which needs no native code at all.
  if not C then return SecondScreen.fileAvailable() end
  local now = clock()
  if probedAt and now and (now - probedAt) < SecondScreen.PROBE_INTERVAL then
    return probed
  end
  local ok, r = pcall(C.love_android_secondary_ready)
  probed = (ok and r ~= 0) and true or false
  probedAt = now or probedAt or 0
  return probed
end

-- Force the next `available` call to ask the host again.  Called when the mode
-- changes, so a player who has just plugged a screen in does not wait out the
-- probe interval to see the option take.
function SecondScreen.forget()
  probedAt, probed = nil, false
end

function SecondScreen.push(imageData, w, h)
  if not imageData then return false end
  if not C then return SecondScreen.filePush(imageData, w, h) end
  return pcall(function()
    C.love_android_push_secondary(imageData:getFFIPointer(), w, h)
  end)
end

function SecondScreen.setEnabled(on)
  if not C then return end
  pcall(function() C.love_android_secondary_enable(on and 1 or 0) end)
end

return SecondScreen
