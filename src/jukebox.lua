local table, io, type, os, require = table, io, type, os, require
local print, ipairs, pcall, select = print, ipairs, pcall, select
local JSON = require'cjson'
local resolver = require'resolver'
local spotify = require'spotify'
local Tape = require'tape'
local _ = require'underscore'
local playlogger = require'playlogger'
module(...)

-- What happens here:
-- 1. we respond to external input commands
-- 2. we set the expected state
-- 3. we control the player
-- 4. the player tries to reflect that state, but if not, it updates us on actual state


local TAPES_JSON_PATH = os.dir.support().."/tapes.json"

state = "stopped"
index = 1
subindex = 1

local tapes = (function()
   local f = io.open(TAPES_JSON_PATH, "r")
   local status, tapes = pcall(function() return JSON.decode(f:read("*all")) end)
   return status and tapes
end)() or {}
_.each(tapes, function(tape) Tape.new(tape) end)

function np()
   if #tapes > 0 then
      return tapes[index].tracks[subindex]
   else
      return nil
   end
end

spotify.prefetch(np())

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
      pcall(function()
         local f = io.open(TAPES_JSON_PATH, "w")
         f:write(JSON.encode(tapes))
         f:close()
      end)
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
   resolver.resolve(data, function()
      save() --TODO excessive as happens every track
   end)

   --TODO check for valid tape data like artist, album, etc.
end

local function actual_play()
   resolver.resolve(np(), function(track, url)
      if (url == "unresolved") then
         subindex = subindex + 1
         if subindex > #tapes[index].tracks then
            index = index + 1
            subindex = 1
         end
         if index > #tapes then
            return stop()
         end
         return actual_play()
      end

      spotify.play(url, {
         next = function()
            --TODO make it a callback to return so we can resolve if necessary
            return (next_resolvable_track() or {}).partnerID
         end,
         onexhaust = function()
            sync_if_changes(function()
               state = 'stopped'
            end)
            playlogger.ended()
         end,
         ontrack = function(url)
            sync_if_changes(function()
               --TODO we must pass track objects into Spotify as this lookup will fail in tapes with dupe tracks!
               index, subindex = (function()
                  for ii, tape in ipairs(tapes) do
                     local jj = _.indexOf(tape.tracks, function(track)
                        return track.partnerID == url
                     end)
                     if jj then return ii, jj end
                  end
                  return index, subindex -- FIXME what TODO?
               end)()
            end)
            playlogger.track(np())
         end,
         onpause = function()
            playlogger.pause(np())
         end,
         onresume = function()
            playlogger.resume(np())
         end,
      })
   end)
end

function remove(rmindex)
   local tape = tapes[index]
   table.remove(tapes, rmindex + 1)
   if rmindex + 1 == index then
      if index > #tapes then
         stop()
      else
         subindex = 1
         if state == 'playing' then actual_play() end
      end
   elseif tape then                  -- there was a current index
      index = _.indexOf(tapes, tape) -- update index if necessary
   end
end

function move(data)
   local tape = tapes[index]
   local rmtape = table.remove(tapes, data.from + 1)
   table.insert(tapes, data.to + 1, rmtape)
   if tape then index = _.indexOf(tapes, tape) end
end

function stop(data)
   state = "stopped"
   index = 1
   subindex = 1
   spotify.stop()
end

function pause(data)
   --TODO unpause should check if the loaded_track is different as it may have changed in eg. remove during pause

   if data == nil then -- the string "pause" was passed, act as a toggle
      if state == "paused" then
         state = "playing"
      elseif state == "playing" then
         state = "paused"
      end
   else
      state = data and "paused" or "playing"
   end
   spotify.pause(state == "paused");
end

function sync_if_changes(callback)
   local oldstate = getstate()
   oldstate.tapes = table.copy(oldstate.tapes)
   callback()
   local newstate = getstate()
   if not _.isEqual(oldstate, newstate) then
      require'websocket'.broadcast(newstate)
      if not _.isEqual(oldstate.tapes, newstate.tapes) then
         save() end
   end
end

function next_resolvable_track()
   local jj = subindex + 1
   for ii = index, #tapes do
      local tape = tapes[ii]
      while jj <= #tape.tracks do
         local track = tape.tracks[jj]
         local pid = track.partnerID
         if pid == nil or pid ~= "unresolved" then
            return track end
         jj = jj + 1
      end
      jj = 1
   end
end

--TODO on error specify that you can send play: "help" to get docs
--TODO passing tape and track to mean index and subindex seems wrong
--TODO use constants rather than strings for state variable
function play(data)
   function play(params)
      if params.index then
         index = params.index
         subindex = 1
      end
      if params.subindex then
         subindex = params.subindex
      end
      if params.index or params.subindex then
         state = "playing"
         if not pcall(actual_play) then
            stop()
         end
      end
   end

   if data == "toggle" then
      data = state ~= "playing" end

   if data == false then
      pause(true)
   elseif data == true or data == nil then
      if state == "stopped" then
         play{index = 1}
      elseif state == "paused" then
         pause(false)
      end
   elseif data == "next" then
      if state == "stopped" then
         play{index = 1}
      elseif # tapes[index].tracks > subindex then
         play{subindex = subindex + 1}
      elseif #tapes > index then
         play{index = index + 1}
      else
         stop()
      end
   elseif data == "prev" or data == "previous" or data == "back" then
      if state == "stopped" then
         play{index = 1}
      elseif subindex > 1 then
         play{subindex = subindex - 1}
      elseif index > 1 then
         play{index = index - 1}
      else
         play{index = 1}
      end
   elseif type(data) == "number" then
      play{index = data + 1}
   elseif type(data) == "table" then
      -- +1 because Lua indexes start at ONE
      local b1 = type(data.index) == "number" and data.index + 1
      local b2 = type(data.subindex) == "number" and data.subindex + 1
      if b1 or b2 then
         play{index = b1, subindex = b2}
      elseif _.isArray(data) and #data >= 2 then
         play{index = data[1], subindex = data[2]}
      else
         queue(data)
         play{index = #tapes}
      end
   else
      error("Cannot play that thing")
   end
end
