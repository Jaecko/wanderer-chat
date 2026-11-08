local _, ns = ...
local L = ns.L

-- The public channels (General, Trade, Looking for group...) pass by; only what is for you comes up on a
-- card: someone looking for players for a dungeon of your level (said by its name or by the short names
-- players use), or a word you chose (a profession, an item, a place). Never while your group is full or
-- you are inside a dungeon. One card for each person now and then, a whisper one click away.

local W = Wanderer
local U = W and W.Util

local EXCERPT = 110
local AGAIN = 600 -- seconds before the same person makes a card again
local LEVELS = 2 -- levels around a dungeon's own that still count

-- dungeon area -> the short names players use (the levels and the dungeons themselves: Wanderer's world data,
-- Forever's own included, found by their game name). "~": a short name that is also a common word or
-- abbreviation ("st", "wc", "library"): it counts only right beside the words that seek ("LFM SM", "LF2M for cath").
local SHORT = {
	[2437] = "RFC", [718] = "~WC,WAILING CAVERNS", [1581] = "DEADMINES", [209] = "SFK", [719] = "BFD",
	[717] = "~STOCKS,STOCKADE", [133] = "GNOMER,GNOMEREGAN", [1717] = "RFK",
	[796] = "~SM,~CATH,ARMO,~ARMORY,~LIB,~LIBRARY,~GY,~GRAVEYARD,SCARLET MONASTERY", [722] = "RFD",
	[1517] = "ULDA,ULDAMAN", [978] = "ZF", [2100] = "MARA,MARAUDON", [1417] = "~ST,~TEMPLE,SUNKEN TEMPLE",
	[1584] = "BRD", [1583] = "LBRS,UBRS,~BRS", [2557] = "DME,DMW,DMN,DIRE MAUL", [2017] = "STRAT,STRATH,STRATHOLME",
	[2057] = "SCHOLO,SCHOLOMANCE",
}
local NEAR = 2 -- words at most between a weak short name and the words that seek

local seeking -- the words that look for players (the client's language and English)
local seen = {} -- name -> when they made a card

-- Your words, read again only when you change them: { upper case (to find), as you typed it (to show) }.
local yours, yoursFrom = {}, nil
local function YourWords()
	local text = ns.Settings().words or ""
	if text ~= yoursFrom then
		yoursFrom, yours = text, {}
		for item in tostring(text):gmatch("[^,]+") do
			item = strtrim(item)
			if item ~= "" then yours[#yours + 1] = { U.Upper(item), item } end
		end
	end
	return yours
end

-- The dungeons of your level: { name, words, weak } (their names read once, in your language).
local ofLevel, level
local function OfLevel()
	local now = U.Clean(U.Safe(UnitLevel, "player")) or 1
	if level == now and ofLevel then return ofLevel end
	local list, named = {}, true
	for _, place in ipairs(W.ZoneLevels() or {}) do
		if place.kind == "dungeon" and place.low and now >= place.low - LEVELS and now <= place.high + LEVELS then
			local name, short = U.AreaName(place.area), SHORT[place.area] or ""
			local words, weak = {}, {}
			for _, word in ipairs(ns.List(short)) do
				if word:sub(1, 1) == "~" then weak[#weak + 1] = word:sub(2) else words[#words + 1] = word end
			end
			if name then words[#words + 1] = U.Upper(name) else named = false end
			-- (a dungeon with neither a name known yet nor a short name: nothing to find it by)
			if words[1] or weak[1] then list[#list + 1] = { name = name or short:match("^~?([^,]+)"), words = words, weak = weak } end
		end
	end
	-- (kept for this level once every name is known)
	if named then level, ofLevel = now, list end
	return list
end

local function Free()
	if U.Clean(U.Safe(IsInInstance)) then return false end
	return (U.Clean(U.Safe(GetNumGroupMembers)) or 0) < 5
end

local function Card(line, title)
	ns.Prune(seen, line.at, AGAIN)
	seen[line.who] = line.at
	ns.Card({ key = "channel:" .. line.who, kind = "channel", kicker = ns.Where(line), title = title,
		body = L.RP_TITLE_QUOTED:format(ns.Excerpt(line.text, EXCERPT)),
		buttons = { { L.WHISPER, function() ns.Whisper(line.sender) end } } })
end

-- Where a phrase stands among the words (" LFM FOR SM "): { first, last } word numbers of each place.
local function Spans(words, phrase)
	local spans, from = {}, 1
	local size = select(2, phrase:gsub(" ", ""))
	while true do
		local at = words:find(" " .. phrase .. " ", from, true)
		if not at then return spans end
		local first = select(2, words:sub(1, at):gsub(" ", ""))
		spans[#spans + 1] = { first, first + size }
		from = at + 1
	end
end

-- A weak short name, whole, within NEAR words of one of the seeking words found.
local function Beside(words, weak, found)
	local places = Spans(words, weak)
	if not places[1] then return false end
	for _, seek in ipairs(found) do
		for _, near in ipairs(Spans(words, seek)) do
			for _, place in ipairs(places) do
				if place[1] <= near[2] + NEAR + 1 and place[2] >= near[1] - NEAR - 1 then return true end
			end
		end
	end
	return false
end
ns.LfgBeside = Beside -- (tests)

local function OnChannel(line)
	if line.kind ~= "channel" or line.me or line.at - (seen[line.who] or -math.huge) < AGAIN then return end
	-- (the line's words made only when something is looked for: the public channels are busy)
	local mine, lookingFor = YourWords(), ns.On("lookingFor")
	if not (mine[1] or lookingFor) then return end
	local words = ns.Words(line.text)
	-- A word of yours.
	for _, word in ipairs(mine) do
		if ns.Has(words, word[1]) then
			return Card(line, L.WORD_TITLE:format(ns.Named(line.who, line.guid), word[2]))
		end
	end
	-- A group sought for a dungeon of your level.
	if not (lookingFor and Free()) then return end
	local found = {}
	for _, word in ipairs(seeking) do
		if ns.Has(words, word) then found[#found + 1] = word end
	end
	if not found[1] then return end
	for _, dungeon in ipairs(OfLevel()) do
		local named = false
		for _, word in ipairs(dungeon.words) do named = named or ns.Has(words, word) end
		for _, word in ipairs(dungeon.weak) do named = named or Beside(words, word, found) end
		if named then return Card(line, L.LFG_TITLE:format(ns.Named(line.who, line.guid), dungeon.name)) end
	end
end

function ns.InitChannels()
	seeking = ns.List(L.LFG_WORDS .. "," .. ns.LOCALES.enUS.LFG_WORDS)
	ns.Heard.On(function(line)
		if line.kind == "channel" and ns.On() then OnChannel(line) end
	end)
end
