local resolver = require "resolver"
local _ = require 'underscore'

function sanitize(q)
   return _.join(resolver.sanitize(q), ' ')
end

describe("underscore modifications", function()
   it("compacts empty strings", function()
      local a = {0, 1}
      local b = _.compact({nil, false, "", 0, 1})
      assert.same(a, b)
   end)
end)

describe("sanitizing Spotify search queries", function()
   it("removes +", function()
      local o1 = "alone easy target"
      local o2 = sanitize("Alone + Easy Target")
      assert.same(o1, o2)
   end)
   it("removes prime genitive", function()
      local o1 = "chipzel child play"
      local o2 = sanitize("Chipzel Child's Play")
      assert.same(o1, o2)
   end)
   --[[
   it("removes apostrophe genitive", function()
      local o1 = "chipzel child play"
      local o2 = sanitize("Chipzel Child’s Play")
      assert.same(o1, o2)
   end)
   ]]--
   it("splits on in-word hyphens", function()
      local o1 = "foo fighters x scope"
      local o2 = sanitize("Foo Fighters X-Scope")
      assert.same(o1, o2)
   end)
   it("splits on in-word slashes", function()
      local o1 = "foo fighters erase replace"
      local o2 = sanitize("Foo Fighters Erase/Replace")
      assert.same(o1, o2)
   end)
   it("removes in-word periods", function()
      local o1 = "david guetta nothing but beat 20"
      local o2 = sanitize("David Guetta Nothing But the Beat 2.0")
      assert.same(o1, o2)
   end)
   it("does not remove in-number commas", function()
      local o1 = "megadeth 1,320 endgame"
      local o2 = sanitize("Megadeth 1,320 Endgame")
      assert.same(o1, o2)
   end)
end)

describe("generating Spotify search queries", function()
   it("Removes ampersands", function()
      local o1 = {
         artist = "Dave Graney & The Coral Snakes",
         album = "I Was The Hunter & I Was The Prey",
         title = "$1,000,000 in a Red Velvet Suit"
      }
      local o2 = "artist:dave artist:graney artist:coral artist:snakes album:i album:was album:hunter album:prey title:$1,000,000 title:red title:velvet title:suit"
      assert.same(resolver.querize(o1), o2)
   end)
end)
