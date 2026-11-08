local _, ns = ...

-- In the chat itself, read at a glance:
-- * A line that names you (your character's name, whole, or one of the other names you gave) is in gold, in every tab that shows it; its tab, when
--   it is not shown, gets a small gold dot (Tabs.lua). Said in your guild, your group, around you or in a
--   whisper; in the public channels only when asked for. No card: the chat is where you read.
-- * In the General tab, the lines of your guild and your group are a little brighter than their own color,
--   to stand out among the public channels.
-- Only the words are colored, never a link, an icon or a color another addon set; a secret line (the game's,
-- during a fight) is never touched. A sound when your name is said: asked for, once a minute at most.

local W = Wanderer
local U = W and W.Util

local NAMED = "|cffffd35c" -- the gold of the lines that name you (its own: the tabs know them by it)
ns.NAMED_COLOR = NAMED
local BRIGHTER = 0.35 -- how far toward white the guild's and the group's lines go in the General tab
local SOUND_AGAIN = 60 -- seconds between two sounds of your name

-- Where your name counts: the guild, the group, around you, a whisper; the public channels when asked for.
local NAMEABLE = { guild = true, officer = true, party = true, raid = true, instance = true, near = true,
	whisper = true, bnwhisper = true }
local function NameHere(kind)
	if kind == "channel" then return ns.On("mentionChannels") end
	return NAMEABLE[kind] == true
end

-- Your name ----------------------------------------------------------------------------------------------------

-- Whether the letter holding the byte at this place is Chinese, Japanese or Korean (written without spaces),
-- or one of their marks or the general ones ("，", "…": their first byte from 226 on).
local function WideAt(text, at)
	local start = at
	while start > 1 and at - start < 3 and (text:byte(start) or 0) >= 128 and (text:byte(start) or 0) < 192 do
		start = start - 1
	end
	local lead = text:byte(start) or 0
	return lead >= 226 and lead <= 239
end

-- Whether the byte at this place ends a name: nothing, a space or a mark, or a letter of a script written
-- without spaces (Korean "이름님", Chinese "小明你好"). before: the byte just before the name.
local function Edge(text, at, before)
	local byte = text:byte(at)
	if not byte or at < 1 then return true end
	if byte < 128 then return not string.char(byte):match("%w") end
	if before then return WideAt(text, at) end
	return byte >= 226 and byte <= 239
end

-- A name alone, whole (not "Eric" within "Frederic"): letters around it end the match. A name in Chinese
-- or Korean letters is found anywhere in the text. upper: the text, upper case.
local function Said(upper, name)
	local from, to = upper:find(name, 1, true)
	if from and ns.IsCJK(name) then return true end
	while from do
		if Edge(upper, from - 1, true) and Edge(upper, to + 1) then return true end
		from, to = upper:find(name, to + 1, true)
	end
	return false
end

-- Your other names (a nickname, your main), set by you: read again only when you change them (upper case).
local others, othersFrom = {}, nil
local function OtherNames()
	local settings = ns.Settings()
	local text = settings and settings.otherNames or ""
	if text ~= othersFrom then othersFrom, others = text, ns.List(text) end
	return others
end

-- Your name, or one of your other names, in a text.
local function NamesMe(text)
	local me = ns.Me()
	if not (me and type(text) == "string") then return false end
	local upper = U.Upper(text)
	if Said(upper, U.Upper(me)) then return true end
	for _, name in ipairs(OtherNames()) do
		if Said(upper, name) then return true end
	end
	return false
end
ns.NamesMe = NamesMe -- (tests)

-- Painting a line -------------------------------------------------------------------------------------------------

-- The end of each escape the words keep whole: a color ("|c" to "|r"), a link ("|H" to its second "|h"), an
-- icon, an atlas, a Battle.net name.
local ENDS = { c = "|r", T = "|t", A = "|a", K = "|k" }
local function EscapeEnd(text, bar)
	local code = text:sub(bar + 1, bar + 1)
	if code == "H" then
		local first = text:find("|h", bar + 2, true)
		return first and select(2, text:find("|h", first + 2, true))
	end
	local close = ENDS[code]
	if close then return select(2, text:find(close, bar + 2, true)) end
end

-- The words of a line in a color (hex: "|cffrrggbb"); what is between escapes only, the escapes as they were.
local function Paint(text, hex)
	local out, words, at = {}, {}, 1
	local function Flush()
		local plain = table.concat(words)
		if plain:find("%S") then out[#out + 1] = hex .. plain .. "|r" else out[#out + 1] = plain end
		wipe(words)
	end
	while at <= #text do
		local bar = text:find("|", at, true)
		if not bar then
			words[#words + 1] = text:sub(at)
			break
		end
		if bar > at then words[#words + 1] = text:sub(at, bar - 1) end
		local stop = EscapeEnd(text, bar)
		if stop then
			Flush()
			out[#out + 1] = text:sub(bar, stop)
			at = stop + 1
		elseif text:sub(bar + 1, bar + 1) == "" or text:sub(bar + 1, bar + 1):match("[cHTAK]") then
			-- (an escape left open: the rest kept as it is)
			Flush()
			out[#out + 1] = text:sub(bar)
			at = #text + 1
		else
			-- ("||", "|n" and the like: words)
			words[#words + 1] = text:sub(bar, bar + 1)
			at = bar + 2
		end
	end
	Flush()
	return table.concat(out)
end
ns.PaintLine = Paint -- (tests)

-- The lines painted lately, painted -> as said: the kept log stores them as said (Comfort.lua).
local painted, paintedCount = {}, 0
local PAINTED_MOST = 40
local function Remember(colored, text)
	if paintedCount >= PAINTED_MOST then
		wipe(painted)
		paintedCount = 0
	end
	painted[colored], paintedCount = text, paintedCount + 1
end

-- A line of the chat as it was said, without the colors put here (a chat line holding a painted message).
function ns.Unpainted(line)
	if type(line) ~= "string" or U.IsSecret(line) or not next(painted) then return line end
	for colored, text in pairs(painted) do
		local from, to = line:find(colored, 1, true)
		if from then return line:sub(1, from - 1) .. text .. line:sub(to + 1) end
	end
	return line
end

-- A chat's color, a little brighter ("|cffrrggbb"), nil when the game does not say it.
local function Brighter(chatType)
	local r, g, b = ns.ChatColor(chatType)
	if not r then return nil end
	local function Up(value) return math.floor(math.min(1, value + (1 - value) * BRIGHTER) * 255 + 0.5) end
	return ("|cff%02x%02x%02x"):format(Up(r), Up(g), Up(b))
end

-- Whether a line of this kind ("guild", "channel"...) by this author names you where your name counts.
-- (In glass, such a line also gets a thin gold edge and a light gold tint, Glass.lua.)
function ns.NamesYou(kind, author, text)
	if not ns.On("mention") or U.IsSecret(author) or U.IsSecret(text) then return false end
	return NameHere(kind) and ns.Who(author) ~= ns.Me() and NamesMe(text) or false
end

-- The filter: each chat window asks it, for each line it is about to show (frame: that window).
local function Filter(frame, event, text, author, ...)
	if not ns.On() or type(text) ~= "string" or U.IsSecret(text) or U.IsSecret(author) or text == "" then return false end
	local kind = ns.KINDS[event]
	local hex
	if ns.NamesYou(kind, author, text) then
		hex = NAMED
	elseif ns.On("emphasis") and (ns.GUILD[kind] or ns.GROUP[kind]) and frame ~= nil and frame == DEFAULT_CHAT_FRAME then
		hex = Brighter(event:match("^CHAT_MSG_(.+)$"))
	end
	if not hex then return false end
	local colored = Paint(text, hex)
	Remember(colored, text)
	return false, colored, author, ...
end
ns.HighlightFilter = Filter -- (tests)

-- The sound ------------------------------------------------------------------------------------------------------

local lastSound = -math.huge
local function OnHeard(line)
	if line.me or line.arrival or not (ns.On("mention") and ns.On("mentionSoundOn")) then return end
	-- (a whisper rings already: the game's sound, or the messages window's)
	if line.kind == "whisper" or not NameHere(line.kind) or not NamesMe(line.text) then return end
	if GetTime() - lastSound < SOUND_AGAIN then return end
	lastSound = GetTime()
	local sound = ns.Settings().mentionSound
	U.PlaySound(type(sound) == "string" and sound or "TELL_MESSAGE")
end

function ns.InitHighlight()
	for event, kind in pairs(ns.KINDS) do
		if NAMEABLE[kind] or kind == "channel" then ns.AddFilter(event, Filter) end
	end
	ns.Heard.On(OnHeard)
end
