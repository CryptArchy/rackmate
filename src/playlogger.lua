local websocket = require'websocket'
local _ = require'underscore'
local table, ipairs, os, math, print, string = table, ipairs, os, math, print, string;
module(...)

local clients = {}

local function rfc8601()
   -- ref: http://lua-users.org/wiki/TimeZone
   local now = os.time()
   local timezone = os.difftime(now, os.time(os.date("!*t", now)))
   local h, m = math.modf(timezone / 3600)
   local Z = string.format("%+.4d", 100 * h + 60 * m)
   return os.date('%Y-%m-%dT%H:%M:%SZ'..Z, now)
end

local function broadcast(event, track)
   local time = rfc8601()
   for i, client in ipairs(clients) do
      client.send{
         userid = client.user,
         passkey = client.pass,
         playbackEvent = event,
         url = "/playlog",
         eventTime = time,
         track = track
      }
      _{
         userid = client.user,
         passkey = client.pass,
         playbackEvent = event,
         url = "/playlog",
         eventTime = time,
         track = track
      }:print()
   end
end

local function parse_uri(s)
   for i, pattern in ipairs{"^([%w%.]+):(%d+)(/.*)$", "^([%w%.]+)(/.*)$", "^([%w%.]+)$"} do
      local host, port, path = s:match(pattern)
      if host then
         return host, port, path
      end
   end
end

function handshake(data)
   local sock = _(clients).find(function(client)
      return client.user == data.userid
   end)
   if sock and sock.pass == data.passkey then
      return
   elseif sock then
      sock:close() -- password changed, open a new playlogger
   end
   sock = websocket.connect(parse_uri(data.endpoint))
   sock.pass = data.passkey
   sock.user = data.userid
   table.insert(clients, sock)
end

function track(track)
   broadcast("TrackStarted", track)
end
function pause(track)
   broadcast("PlaybackPaused", track)
end
function resume(track)
   broadcast("PlaybackResumed", track)
end
function ended()
   broadcast("PlaybackEnded")
end

--TODO remove playloggers!
--TODO don't insert duplicate playloggers!
