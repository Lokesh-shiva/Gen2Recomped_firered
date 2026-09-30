-- Native lower-screen save companion for single-screen generations.
local SecondScreen = require("src.ui.SecondScreen")
local Boxes = require("src.pokemon.Boxes")
local Bag = require("src.inventory.Bag")
local Party = require("src.pokemon.Party")
local GameVersion = require("src.core.GameVersion")

local M = {}
local W,H=256,192
local tabs={"PARTY","BOXES","BAG","PLAYER"}
local state={tab=1,box=1,bagOffset=0,selectedBoxSlot=nil,selectedParty=nil,host=nil}

local function speciesName(game,mon)
  if not mon then return "-" end
  local d=game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return (d and (d.name or d.displayName)) or tostring(mon.species or "?")
end
local function itemName(game,id)
  local d=game.data and game.data.items and game.data.items[id]
  return (d and (d.name or d.displayName)) or tostring(id)
end
local function rect(x,y,w,h,fill)
  local g=love.graphics
  if fill then g.setColor(fill[1],fill[2],fill[3],fill[4] or 1); g.rectangle("fill",x,y,w,h) end
  g.setColor(1,1,1,.28); g.rectangle("line",x,y,w,h)
end
local function text(s,x,y)
  love.graphics.setColor(1,1,1,1); love.graphics.print(tostring(s),x,y)
end
local function tabAt(x,y)
  if y>28 then return nil end
  local tw=W/#tabs
  local i=math.floor(x/tw)+1
  return (i>=1 and i<=#tabs) and i or nil
end

local function boxes(game)
  Boxes.load(game.data)
  return Boxes.ensure(game.save)
end

local function drawParty(game)
  local party=game.save.party or {}
  text("PARTY "..#party.."/"..Party.MAX,6,34)
  for i=1,Party.MAX do
    local y=50+(i-1)*22
    local mon=party[i]
    local sel=state.selectedParty==i
    rect(6,y,244,19,sel and {.20,.42,.32,1} or {.10,.12,.16,1})
    if mon then
      text(i..". "..speciesName(game,mon),12,y+4)
      text("Lv"..tostring(mon.level or "?"),190,y+4)
    else text(i..". --",12,y+4) end
  end
end

local function drawBoxes(game)
  local bs=boxes(game); local count=Boxes.count(); local cap=Boxes.capacity()
  state.box=math.max(1,math.min(count,state.box or game.save.currentBox or 1))
  local box=bs[state.box]
  text("< BOX "..state.box.."/"..count.." >",8,34)
  local cols=5; local cellW=47; local cellH=24
  for i=1,math.min(cap,30) do
    local c=(i-1)%cols; local r=math.floor((i-1)/cols)
    local x=6+c*50; local y=52+r*27
    local mon=box[i]; local sel=state.selectedBoxSlot==i
    rect(x,y,47,24,sel and {.25,.34,.48,1} or {.10,.12,.16,1})
    if mon then text(speciesName(game,mon):sub(1,7),x+3,y+3); text("L"..tostring(mon.level or "?"),x+3,y+13)
    else text(tostring(i),x+18,y+8) end
  end
  text("Tap slot: withdraw   Party tab: deposit",8,177)
end

local function bagList(game)
  game.save.inventory=game.save.inventory or {}
  return Bag.order(game.save)
end
local function drawBag(game)
  local ids=bagList(game); local visible=7
  state.bagOffset=math.max(0,math.min(math.max(0,#ids-visible),state.bagOffset or 0))
  text("BAG  "..#ids.." slots",8,34)
  for row=1,visible do
    local idx=state.bagOffset+row; local id=ids[idx]
    local y=50+(row-1)*18
    rect(6,y,244,16,{.10,.12,.16,1})
    if id then
      text(itemName(game,id):sub(1,24),10,y+2)
      text("x"..tostring(game.save.inventory[id] or 0),210,y+2)
    end
  end
  text("^",232,34); text("v",244,34)
end

local function drawPlayer(game)
  local p=game.save.player or {}
  local badges=0
  for k,v in pairs(game.save.inventory or {}) do if v and tostring(k):find("BADGE",1,true) then badges=badges+1 end end
  text("PLAYER",8,36)
  text("Name: "..tostring(p.name or game.save.playerName or "PLAYER"),8,58)
  text("Money: $"..tostring(game.save.money or 0),8,78)
  text("Badges: "..badges,8,98)
  text("Version: "..tostring(GameVersion.get and GameVersion.get() or "?"),8,118)
  text("Live companion - changes use current save",8,156)
end

local function draw(game)
  local g=love.graphics
  g.setColor(.035,.045,.065,1); g.rectangle("fill",0,0,W,H)
  local tw=W/#tabs
  for i,label in ipairs(tabs) do
    rect((i-1)*tw,0,tw,28,i==state.tab and {.18,.34,.55,1} or {.08,.10,.14,1})
    text(label,(i-1)*tw+5,9)
  end
  if state.tab==1 then drawParty(game)
  elseif state.tab==2 then drawBoxes(game)
  elseif state.tab==3 then drawBag(game)
  else drawPlayer(game) end
end

local function touch(game,x,y)
  local t=tabAt(x,y); if t then state.tab=t; return end
  if state.tab==1 then
    if y>=50 then state.selectedParty=math.max(1,math.min(6,math.floor((y-50)/22)+1)) end
  elseif state.tab==2 then
    if y>=30 and y<50 then
      if x<80 then state.box=math.max(1,state.box-1) elseif x>170 then state.box=math.min(Boxes.count(),state.box+1) end
      return
    end
    if y>=52 and y<174 then
      local c=math.floor((x-6)/50); local r=math.floor((y-52)/27)
      if c>=0 and c<5 and r>=0 then
        local slot=r*5+c+1
        local bs=boxes(game); local box=bs[state.box]
        if slot<=Boxes.capacity() then
          local mon=box[slot]
          if mon and #(game.save.party or {})<Party.MAX then
            box[slot]=nil; table.insert(game.save.party,mon)
          elseif not mon and state.selectedParty and (game.save.party or {})[state.selectedParty] then
            box[slot]=table.remove(game.save.party,state.selectedParty)
            state.selectedParty=nil
          end
          state.selectedBoxSlot=slot
        end
      end
    end
  elseif state.tab==3 then
    local ids=bagList(game); local visible=7
    if y<50 and x>220 then
      if x<242 then state.bagOffset=math.max(0,state.bagOffset-1)
      else state.bagOffset=math.min(math.max(0,#ids-visible),state.bagOffset+1) end
    end
  end
end

local function hostFor(game)
  if not state.host then
    local h={secondScreenAlways=true,secondScreenNativePanel=true,data={},save={options={secondScreenMode="display"}}}
    function h.touchpressed(_,_,x,y) touch(h.game,x,y) end
    function h.touchmoved() end
    function h.touchreleased() end
    state.host=h
  end
  state.host.game=game
  return state.host
end

function M.tick(game)
  local gen=GameVersion.generation and GameVersion.generation(GameVersion.get()) or 1
  if gen>=4 or not SecondScreen.deviceReady() then return false end
  local h=hostFor(game)
  local ok=pcall(SecondScreen.draw,h,function() draw(game) end)
  pcall(SecondScreen.flush,h)
  return ok
end

return M
