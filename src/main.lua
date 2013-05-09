require'websocket'
websocket.bind()

require'extlib'
local Tape = require'tape'

websocket.listen()

require'spotify'.login()
require'jukebox'

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
   onconnect = function()
      return jukebox.getstate()
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
