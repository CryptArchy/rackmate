local _ = require'underscore'

local function fix_route(t)
   if t.route then
      return end
   if t.album then
      t.route = "/music/"..t.artist:enplus().."/"..t.album:enplus().."/"..t.title:enplus()
   else
      t.route = "/music/"..t.artist:enplus().."/"..t.title:enplus()
   end
end


local Tape = {}

function Tape.new(o)
   setmetatable(o, {__index = Tape})
   fix_route(o)
   o.tracks = _.map(o.tracks or {}, function(track)
      setmetatable(track, {__index = Tape})
      fix_route(track)
      return track
   end)
   return o
end

function Tape.isalbum(t)
   local caps = t.route:match('^/music/[^/]+/([^/]+)$')
   caps = _(caps):split(' ') -- lua stdlib is... weird
   return not not (caps and caps[1] and caps[1] ~= '.bsides' and caps[2] == nil)
end

function Tape.istrack(t)
   return not not t.route:match('^/music/[^/]+/[^/]+/[^/]+$')
end

function Tape.isep(t)
   return t.type == "EP"
end

return Tape
