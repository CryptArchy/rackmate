require'websocket'
require'cjson'

sock = websocket.connect("localhost", 9001, "/getCaseCount")
n = require'cjson'.decode((sock.recv()))
sock.close()

function test(id)
   print()
   print("Running test: "..id)
   print()

   sock = websocket.connect("localhost", 9001, "/runCase?case="..id.."&agent=rackmate")

   repeat
      local rcvd, opcode = sock.recv()
      if opcode == 1 then sock.send(rcvd) end
   until opcode == 1 and not rcvd or not sock.open
end

for id = 1, n do
   local status, err = pcall(test, id)
   if err then print("ERR: "..err) end
end

websocket.connect("localhost", 9001, "/updateReports?agent=rackmate")
