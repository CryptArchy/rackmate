local table, ipairs, pairs, math, string, print, require = table, ipairs, pairs, math, string, print, require
local _ = require'underscore'
module(...)

local function levenshtein(string1, string2)
   local str1, str2, distance = {}, {}, {}
   str1.len, str2.len = string.len(string1), string.len(string2)
   string.gsub(string1, "(.)", function(s) table.insert(str1, s) end)
   string.gsub(string2, "(.)", function(s) table.insert(str2, s) end)

   for i = 0, str1.len do
      distance[i] = {}
      distance[i][0] = i
   end

   for i = 0, str2.len do
      distance[0][i] = i
   end

   for i = 1, str1.len do
      for j = 1, str2.len do
         local tmpdist = 1
         if(str1[i-1] == str2[j-1]) then tmpdist = 0 end
         distance[i][j] = math.min(distance[i-1][j] + 1, distance[i][j-1]+1, distance[i-1][j-1] + tmpdist)
      end
   end
   return distance[str1.len][str2.len];
end

function sanitize(query)
   return _.chain(query)
      -- splitting on +-/ tends to help with Spotify search queries
      :split("[%+%-%/ \n\t\r]+")
      :compact()
      :invoke('lower')
      -- removing these characters generally always helps
      -- TODO obviously, don’t remove these if the query is ONLY these
      :without("a", "an", "and", "are", "be", "in", "of", "on", "the", "to", "&")
      :map(function(s)
         -- Spotify queries allow you to remove these suffixes and still work,
         -- though most the rest of the time truncating the string breaks it.
         -- TODO support unicode ’
         if #s > 2 and s:byte(-1) == 115 and s:byte(-2) == 39 then
            return s:sub(0, -3)
         else
            return s
         end
      end)
      :map(function(s)
         -- Spotify allows us to remove internal periods, eg.
         -- "Nothing but the Beat 2.0" can be "Nothing but the Beat 20"
         local s, ignored = s:gsub("%.", "")
         return s
      end):uniq():value()
end

function querize(tape)
   return _.chain({"artist", "album", "title"}):map(function(key)
      return _.map(sanitize(tape[key]), function(s)
         return key..':'..s
      end)
   end):flatten():join(' '):value()
end

-- TODO shouldn't underscore min return index too?
local function find_best(results, track, callback)
   if #results == 0 then
      track.partnerID = "unresolved"
      callback(track, "unresolved")
      return nil
   end
   local minii = 0
   local min = math.huge;
   _.chain(results):map(function(result)
      return levenshtein(result.title, track.title)
   end):each(function(distance, ii)
      if distance < min then
         minii = ii
         min = distance
      end
   end)
   track.partnerID = results[minii].url
   if callback then callback(track, track.partnerID, min) end
   return minii
end

local function resolve_album(album, callback)
   require'spotify'.search(querize{
      artist = album.artist,
      album = album.title
   }, function(results)
      _.each(album.tracks, function(track)
         local jj = find_best(results, track, callback)
         if jj and jj > 0 then -- don't use a track more than once
            table.remove(results, jj) end
      end)
   end)
end

local function resolve_compilation(tape, callback)
   for ii, track in ipairs(tape.tracks or {}) do
      if track.partnerID then
         callback(track, track.partnerID)
      else
         require'spotify'.search(querize{
            artist = track.artist,
            -- feat/featuring and that sort of thing impedes resolution
            title = track.title:gsub("%(?feat%.?(uring%)?", '')
         }, function(results)
            find_best(results, track, callback)
         end)
      end
   end
end

function resolve(tape, callback)
   if tape:isalbum() then --and not tape:isep() then
      resolve_album(tape, callback)
   elseif tape:istrack() then
      resolve_compilation({tracks = {tape}}, callback)
   else
      resolve_compilation(tape, callback)
   end
end
