local ipairs, table, string, print, type = ipairs, table, string, print, type
local require, pairs, math = require, pairs, math
local WebSocketClient = WebSocketClient
local c = require'websocket.c'
local JSON = require'cjson'
local _ = require'underscore'
local io = io
module(...)

clients = {}
bind = c.bind
listen = c.listen

local function send_json(sock, data)
   data = JSON.encode(data)
   sock:write(c.frame_header(#data)..data)
end

function broadcast(data)
   data = JSON.encode(data)
   data = c.frame_header(#data)..data
   for fd, client in pairs(clients) do
      client:write(data)
   end
end

local function handle_message(sock, rawdata, callback)
   local json = JSON.decode(c.unmask(rawdata))
   if type(json) == 'string' then
      callback(json, nil, function(data)
         send_json(sock, data)
      end)
   else
      for method, data in pairs(json) do
         if method ~= 'callbackId' then
            callback(method, data, function(data)
               data.callbackId = json.callbackId
               send_json(sock, data)
            end)
         end
      end
   end
end

function select(callbacks)
   repeat until c.select(function(sock, handshake)
      local headers = _.chain(handshake):split("\r\n"):compact():map(function(line)
         return _.split(line, '%s*:%s*')
      end):reduce(function(memo, parts)
         memo[parts[1]] = parts[2]
         return memo
      end, {}):value()
      local accept = c.base64(c.sha1(headers['Sec-WebSocket-Key']..'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))

      sock:write("HTTP/1.1 101 Web Socket Protocol Handshake\r\n"..
                 "Upgrade: websocket\r\n"..
                 "Connection: Upgrade\r\n"..
                 "Sec-WebSocket-Accept: "..accept.."\r\n\r\n")

      sock.protocol = headers['Sec-WebSocket-Protocol']
      clients[sock.sockfd] = sock; --TODO do in the C

      send_json(sock, callbacks.onconnect())
   end,
   function(sock)
      opcode, N = sock:read_header()
      if opcode == 1 then
         if N == 126 then
            N = c.ntohs(sock:read(2))
         elseif N == 127 then
            N = c.ntohll(sock:read(8))
         end
         handle_message(sock, sock:read(N + 4), callbacks.onmessage)
      elseif opcode == 8 then --CLOSE
         sock:write(c.frame_header(2, 0x8)..c.unmask(sock:read(6)))
         sock:close()
      elseif opcode == 9 then --PING
         local data = c.unmask(sock:read(N + 4))
         sock:write(c.frame_header(#data, 0xA)..data)
      elseif opcode == 0xA then --PONG
         sock:read(N + 4) -- clear buffer
      else
         sock:close()
      end
   end)
end

function connect(host, port, path)
   path = path or "/"
   port = port or 80
   local sock = c.connect(host, port)
   sock:write((function()
      function r() return c.htonl(math.random(0, 0xfffffff)) end
      local key = c.base64(r()..r()..r()..r())
      return "GET "..path.." HTTP/1.1\r\n"..
             "Host: "..host..":"..port.."\r\n"..
             "Upgrade: websocket\r\n"..
             "Connection: Upgrade\r\n"..
             "Sec-WebSocket-Key: "..key.."\r\n"..
             "Sec-WebSocket-Version: 13\r\n\r\n"
   end)())

   local rsp = "" -- FIXME slooooooow (recvs are unbuffered)
   repeat rsp = rsp..sock:read(1) until rsp:sub(-4, -1) == "\r\n\r\n"

   return {
      send = function(data)
         sock:write(c.frame_header(#data, 1, true)..c.mask(data))
      end,
      recv = function()
         opcode, N = sock:read_header()
         if opcode == 1 then
            if N == 126 then
               N = c.ntohs(sock:read(2))
            elseif N == 127 then
               N = c.ntohll(sock:read(8))
            end
            return sock:read(N)
         elseif opcode == 8 then --CLOSE
            if N > 0 then
               local frame = sock:read(N)
               local code = frame:sub(1, 2)
               sock:write(c.frame_header(2, 0x8, true)..c.mask(code))
               print("Closed: "..c.ntohs(code), frame:sub(3))
            else
               sock:write(c.frame_header(2, 0x8, true)..c.mask(c.htons(1002)))
            end
            sock:close()
         elseif opcode == 9 then --PING
            local data = sock:read(N)
            sock:write(c.frame_header(#data, 0xA, true)..c.mask(data))
         elseif opcode == 10 then --PONG
            sock:read(N) -- clear buffer
         else
            sock:close()
         end
      end
   }
end
