local ipairs, table, string, print, type = ipairs, table, string, print, type
local require, pairs, math, loadstring = require, pairs, math, loadstring
local pairs, pcall, io, _select = pairs, pcall, io, select
local WebSocketClient = WebSocketClient
local c = require'websocket.c'
local JSON = require'cjson'
local _ = require'underscore'
module(...)

clients = {}
bind = c.bind
listen = c.listen

function WebSocketClient:read_frame()
   local opcode, N = self:read_header()
   if opcode == 1 then
      if N == 126 then
         N = c.ntohs(self:read(2))
      elseif N == 127 then
         N = c.ntohll(self:read(8))
      end
      return c.unmask(self:read(N + 4))
   elseif opcode == 8 then --CLOSE
      self:write(c.frame_header(2, 0x8)..c.unmask(self:read(6)))
      self:close()
   elseif opcode == 9 then --PING
      local data = c.unmask(self:read(N + 4))
      self:write(c.frame_header(#data, 0xA)..data)
   elseif opcode == 0xA then --PONG
      self:read(N + 4) -- clear buffer
   else
      self:close()
   end
end

function WebSocketClient:send_json(data)
   data = JSON.encode(data)
   self:write(c.frame_header(#data)..data)
end

function broadcast(data, protocol)
   data = JSON.encode(data)
   data = c.frame_header(#data)..data
   _.chain(clients):select(function(client)
      return protocol == nil or client.protocol == protocol
   end):invoke('write', data)
end

function select(callbacks)
   function handshake(sock)
      local rsp = sock:read(4)
      if rsp ~= "ctc:" then
         rsp = rsp..sock:read()
         local headers = _.chain(rsp):split("\r\n"):compact():map(function(line)
            return _.split(line, '%s*:%s*')
         end):object():value()

         local accept = c.base64(c.sha1(headers['Sec-WebSocket-Key']..'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))

         sock:write("HTTP/1.1 101 Web Socket Protocol Handshake\r\n"..
                    "Upgrade: websocket\r\n"..
                    "Connection: Upgrade\r\n"..
                    "Sec-WebSocket-Accept: "..accept.."\r\n\r\n")
         sock.protocol = headers['Sec-WebSocket-Protocol']
         clients[sock.fd] = sock
         sock:send_json(callbacks.onconnect(sock.protocol))
      else
         rsp = sock:read() --TODO should send length as next byte or something
         sock:close()
         rsp:gsub('(\w+)%.', "require'%1'.")
         local status, err = pcall(loadstring(rsp))
         if err then print("ctc:"..rsp..": "..err) end
      end
   end

   local done = false
   repeat c.select(function(sock)
      if not _.contains(clients, sock) then
         handshake(sock)
      else
         local json = JSON.decode(sock:read_frame())
         if type(json) ~= 'string' then
            local method = _.chain(json):keys():without('callbackId'):first():value()
            callbacks.onmessage(method, json[method], function(data)
               data.callbackId = json.callbackId
               sock:send_json(data)
            end)
         elseif json == 'quit' then
            done = true --TODO don't let select loop again
         else
            callbacks.onmessage(json, nil, function(data)
               sock:send_json(data)
            end)
         end
      end
   end) until done
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
         data = JSON.encode(data)
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
