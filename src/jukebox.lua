local table, io, type, os, require = table, io, type, os, require
local JSON = require'cjson'
local resolver = require'resolver'
local spotify = require'spotify'
local Tape = require'tape'
local _ = require'underscore'
module(...)

local TAPES_JSON_PATH = os.dir.support().."/tapes.json"

state = "stopped"
index = 1
subindex = 1

tapes = (function()
   local f = io.open(TAPES_JSON_PATH, "r")
   return (f and JSON.decode(f:read("*all"))) or {}
end)()
_.each(tapes, function(tape) Tape.new(tape) end)

function current_track()
   if #tapes > 0 then
      return tapes[index].tracks[subindex]
   else
      return nil
   end
end

spotify.prefetch(current_track())

function getstate()
   return {
      state = state,
      index = index - 1,
      subindex = subindex - 1,
      tapes = tapes
   }
end

local function save()
   if os.fork() == 0 then
      local f = io.open(TAPES_JSON_PATH, "w")
      f:write(JSON.encode(tapes))
      f:close()
      os._exit()
   end
end

--TODO catch errors and send back down WS

function queue(data)
   if type(data) ~= "table" then
      error("Invalid tape data") end
   if not data.tracks then -- tape is a single
      data.tracks = {table.copy(data)} end
   table.insert(tapes, Tape.new(data))
   save()
   resolver.resolve(data, function()
      save() --TODO excessive as happens every track
   end)

   --TODO check for valid tape data like artist, album, etc.
end

function remove(index)
   table.remove(tapes, index + 1)
   save()
   --TODO require index AND route
end

function move(data)
   local tape = table.remove(tapes, data.from + 1)
   table.insert(tapes, data.to + 1, tape)
end

function stop(data)
   state = "stopped"
   index = 1
   subindex = 1
   spotify.stop()
end

function pause(data)
   if data == nil then -- the string "pause" was passed, act as a toggle
      if state == "paused" then
         state = "playing"
      elseif state == "playing" then
         state = "paused"
      end
   else
      state = data and "paused" or "playing"
   end
end

function sync_if_changes(callback)
   local oldstate = getstate()
   oldstate.tapes = table.copy(oldstate.tapes)
   callback()
   local newstate = getstate()
   if not _.isEqual(oldstate, newstate) then
      require'websocket'.broadcast(newstate)
   end
end

function next_resolvable_track()
   for ii = index, #tapes do
      for jj = subindex, #tapes[ii].tracks do
         local track = tapes[ii].tracks[jj]
         local pid = track.partnerID
         if pid == nil or pid ~= "unresolved" then return track end
      end
   end
end

local function actual_play()
   resolver.resolve(current_track(), function(track, url)
      spotify.play(url, {
         next = next_resolvable_track,
         onexhaust = function()
            sync_if_changes(function()
               state = 'stopped'
            end)
         end,
         ontrack = function(url)
            sync_if_changes(function()
               index, subindex = (function()
                  for ii, tape in ipairs(tapes) do
                     local jj = _.indexOf(tape.tracks, function(track)
                        return track.partnerID == url
                     end)
                     if jj > 0 then return ii, jj end
                  end
                  return index, subindex -- FIXME what TODO?
               end)()
            end)
         end
      })
   end)
end

--TODO on error specify that you can send play: "help" to get docs
--TODO passing tape and track to mean index and subindex seems wrong
--TODO use constants rather than strings for state variable
function play(data)
   if data == false then
      pause(true)
   elseif data == true or data == nil then
      if state == "stopped" then
         play({tape = index, track = subindex})
      elseif state == "paused" then
         pause(false)
      end
   elseif data == "toggle" then
      play(state ~= "playing")
   elseif data == "next" then
      if # tapes[index].tracks > subindex then
         play({track = subindex + 1})
      elseif #tapes > index then
         play({tape = index + 1, track = 1})
      else
         stop()
      end
   elseif data == "prev" or data == "previous" or data == "back" then
      if subindex > 1 then
         play({track = subindex - 1})
      elseif index > 1 then
         play({tape = index - 1, track = 1})
      else
         play({tape = 1, track = 1})
      end
   elseif type(data) == "number" then
      play({tape = data + 1, track = 1})
   elseif type(data) == "table" then
      local b1 = type(data.tape) == "number"
      local b2 = type(data.track) == "number"
      if b1 or b2 then
         state = "playing"
         if b1 then index = data.tape subindex = 1 end
         if b2 then subindex = data.track end
         actual_play()
      else
         queue(data)
         play({tape = #tapes})
      end
   else
      error("Cannot play that thing")
   end
end
