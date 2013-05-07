local Tape = require 'tape'

describe("#tape", function()
   it("knows it is an album", function()
      o1 = { route = '/music/madonna/mdna' }
      assert.is_true(Tape.isalbum(o1))
      setmetatable(o1, {__index = Tape})
      assert.is_true(o1:isalbum())
   end)
   it("knows it is an album when there are pluses", function()
      o1 = { route = '/music/foo+fighters/bar' }
      assert.is_true(Tape.isalbum(o1))
      setmetatable(o1, {__index = Tape})
      assert.is_true(o1:isalbum())
   end)
   it("knows a track isn't an album", function()
      o1 = { route = '/music/foo+fighters/bar/jee' }
      assert.is_false(Tape.isalbum(o1))
   end)
   it("knows track routes", function()
      o1 = { route = '/music/foo+fighters/bar/jee' }
      assert.is_true(Tape.istrack(o1))
   end)
   it("allows query strings on the end of tracks", function()
      o1 = { route = '/music/foo+fighters/bar/jee?foo&bar' }
      assert.is_true(Tape.istrack(o1))
   end)
end)
