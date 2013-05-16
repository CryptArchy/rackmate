require'websocket'
websocket.bind()
require'extlib'
local Tape = require'tape'
local _ = require'underscore'
websocket.listen()
local spotify = require'spotify'
spotify.login{
   onchange = function(state)
      websocket.broadcast(_.extend({spotify = state}, jukebox.getstate()), 'rackmate')
   end
}

local jukebox = require'jukebox' -- must come after Spotify: does immediate resolution

local handlers = {
   move = jukebox.move,
   play = jukebox.play,
   pause = jukebox.pause,
   queue = jukebox.queue,
   remove = jukebox.remove,
   resolve = function(data, write)
      local ii = 0
      require'resolver'.resolve(Tape.new(data), function(track, partnerID)
         ii = ii + 1
         write{
            track = track.route,
            resolved = partnerID ~= "unresolved",
            partnerID = partnerID,
            keepCallbackAlive = ii < #data.tracks
         }
      end)
   end,
   handshake = require'playlogger'.handshake
}

websocket.select{
   onconnect = function(protocol)
      local state = jukebox.getstate()
      if protocol == 'rackmate' then
         state.spotify = spotify.getstate() end
      return state
   end,
   onmessage = function(method, data, reply)
      if handlers[method] then
         jukebox.sync_if_changes(function()
            handlers[method](data, reply)
         end)
      elseif data then
         print("Unhandled: "..method..": "..require'cjson'.encode(data))
      else
         print("Unhandled: "..method);
      end
   end
}

spotify.logout()
