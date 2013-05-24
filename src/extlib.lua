function table.copy(t)
   local t2 = {}
   for k,v in pairs(t) do
      t2[k] = v
   end
   return t2
end

function string.enplus(s)
   return s:gsub("([^%w ])", function(c)
      return string.format("%%%02X", string.byte(c))
   end):gsub(" ", "+")
end

function string.startsWith(s1, s2)
   return string.sub(s1, 1, string.len(s2)) == s2
end

local function mk(sysdirkey, uid)
   local d = os.sysdir(sysdirkey)
   if uid then d = d..'/'..uid end
   os.mkpath(d)
   return d
end

os.dir = {
   cache = function(uid)
      return mk(0, uid)
   end,
   prefs = function(uid)
      return mk(1, uid)
   end,
   support = function(uid)
      return mk(2, uid)
   end
}
