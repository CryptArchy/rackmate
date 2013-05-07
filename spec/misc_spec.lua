require 'extlib'

describe("#string", function()
   it("startsWith", function()
      assert.is_true(string.startsWith("foo", 'fo'))
   end)
end)
