local _, ns = ...
local L = ns.L

-- The public channels quieter (asked for). In General, Trade and the other public channels, a line said again by
-- the same person within a minute, and obvious gold selling (a web address beside words of selling or a price),
-- stay out of the chat; so do the lines holding a word you chose to hide. Never a line of yours, of a friend or of
-- your guild; the guild and the group are other chats, never touched. A whisper stays out only when it sells gold
-- and comes from a stranger (no friend, no guild, no group, no one you wrote to): then no sound, no window, no
-- waiting line either. One quiet line says how many were kept out, once in five minutes at most; a click on it
-- shows them in a small window (this session's only, nothing saved).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local REPEAT = 60 -- seconds: the same words by the same person again within this, kept out
local NOTICE_EVERY = 300 -- seconds between two lines saying how many were kept out
local KEPT = 100 -- lines kept out, kept to be shown
local SAID_MOST = 300 -- what was said lately, looked through once that many
local DECIDED_MOST = 400 -- lines decided (each chat window asks for the same line)
local LINK = "addon:WandererChat:hidden"
local WIDTH, HEIGHT = 520, 340

-- Web addresses, also written apart or disguised ("w w w", "c0m", "(dot)"), looked for in the words without spaces.
local SITES = { "WWW%.", "HTTPS?:", "%.COM", "%.NET", "%.ORG", "%.CN", "%.RU", "%.CC", "%.IO", "%.TOP", "%.SHOP", "C0M",
	"DOTCOM", "%(DOT%)", "%[DOT%]", "{DOT}" }
-- Prices: found anywhere.
local MONEY = { "$", "\226\130\172", "\194\163", "USD", "EUR" } -- ($, euro, pound)

local hidden = {} -- { at, sender, guid, channel, text, why }, the oldest first
local count = 0 -- kept out since the last notice
local lastNotice = -math.huge
local noticeSoon = false
local frames = {} -- the chat windows that would have shown them since the last notice
local said, saidCount = {}, 0 -- who and words -> when
local decided, decidedOrder = {}, {}
local selling -- the words of selling (the client's language and English)

local function Spam(upper)
	local compact = upper:gsub("%s+", "")
	local site = false
	for _, pattern in ipairs(SITES) do
		if compact:find(pattern) then
			site = true
			break
		end
	end
	if not site then return false end
	for _, sign in ipairs(MONEY) do
		if compact:find(sign, 1, true) then return true end
	end
	local words = ns.Words(upper)
	for _, word in ipairs(selling) do
		if ns.Has(words, word) then return true end
	end
	return false
end

-- Your hidden words, read again only when you change them (upper case).
local hiddenWords, hiddenFrom = {}, nil
local function HiddenWords()
	local settings = ns.Settings()
	local text = settings and settings.hiddenWords or ""
	if text ~= hiddenFrom then hiddenFrom, hiddenWords = text, ns.List(text) end
	return hiddenWords
end

-- The first of your hidden words in a line (upper case and plain), else nil.
local function HiddenWord(upper)
	local list = HiddenWords()
	if not list[1] then return nil end
	local words = ns.Words(upper)
	for _, word in ipairs(list) do
		if ns.Has(words, word) then return word end
	end
end

-- Yours, a friend's, your guild's: always in the chat.
local function Known(who, guid)
	if who == ns.Me() or (guid and guid == Clean(Safe(UnitGUID, "player"))) then return true end
	if guid and (Clean(Safe(C_FriendList and C_FriendList.IsFriend, guid)) or Clean(Safe(IsGuildMember, guid))) then return true end
	return ns.GuildMember(who) ~= nil
end

-- Why a line stays out ("repeat", "spam", "word"), or false; and the word, for "word".
local function Decide(text, sender, guid)
	if U.IsSecret(text) or U.IsSecret(sender) or U.IsSecret(guid) then return false end
	text, guid = Clean(text), Clean(guid)
	local who = ns.Who(sender)
	if type(text) ~= "string" or not who or Known(who, guid) then return false end
	local upper = U.Upper(U.PlainText(text))
	local word = HiddenWord(upper)
	if word then return "word", word end
	if not ns.On("quietChannels") then return false end
	local key = who .. "\n" .. strtrim((upper:gsub("%s+", " ")))
	local now = GetTime()
	local last = said[key]
	if not last then saidCount = saidCount + 1 end
	said[key] = now
	if saidCount > SAID_MOST then
		ns.Prune(said, now, REPEAT)
		saidCount = 0
		for _ in pairs(said) do saidCount = saidCount + 1 end
	end
	if last and now - last < REPEAT then return "repeat" end
	if Spam(upper) then return "spam" end
	return false
end

-- How many were kept out, in one quiet line where they would have been (once in five minutes at most).
local function Notice()
	noticeSoon = false
	if count == 0 then return end
	lastNotice = GetTime()
	local muted = Skin.COLORS.muted
	local words = L.QUIET_NOTICE:format(U.Plural(count, L.QUIET_ONE, L.QUIET_MANY)) .. " "
		.. Skin.Colorize("|H" .. LINK .. "|h[" .. L.QUIET_SHOW_THEM .. "]|h", "label")
	count = 0
	local told = false
	for frame in pairs(frames) do
		if frame.AddMessage then
			frame:AddMessage(words, muted[1], muted[2], muted[3])
			told = true
		end
	end
	wipe(frames)
	if not told and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(words, muted[1], muted[2], muted[3]) end
end

local function NoticeSoon()
	if noticeSoon then return end
	noticeSoon = true
	C_Timer.After(math.max(0, lastNotice + NOTICE_EVERY - GetTime()), Notice)
end

local function Keep(entry)
	hidden[#hidden + 1] = entry
	while #hidden > KEPT do table.remove(hidden, 1) end
	count = count + 1
	if ns.RedrawHidden then ns.RedrawHidden() end
end

-- A line decided once (each chat window asks for the same line, and the whisper's listeners too): by its id, else
-- by its words and its moment. decide(text, sender, guid) gives why and the word; entry: the rest of what is kept.
local function Once(text, sender, lineID, guid, decide, entry)
	local id = Clean(lineID) or (tostring(sender) .. "\n" .. tostring(text) .. "\n" .. GetTime())
	local why = decided[id]
	if why == nil then
		local word
		why, word = decide(text, sender, guid)
		decided[id] = why
		decidedOrder[#decidedOrder + 1] = id
		if #decidedOrder > DECIDED_MOST then decided[table.remove(decidedOrder, 1)] = nil end
		if why then
			entry.at, entry.sender, entry.guid, entry.text, entry.why, entry.word = time(), Clean(sender), Clean(guid), text, why, word
			Keep(entry)
		end
	end
	return why
end

-- Whether a line of a public channel stays out (asked by the chat's filter and the line listener: decided once).
function ns.HushedChannel(text, sender, lineID, guid, channel)
	if not ns.On() or not (ns.On("quietChannels") or HiddenWords()[1]) then return false end
	if U.IsSecret(text) or U.IsSecret(sender) then return false end
	if not Once(text, sender, lineID, guid, Decide, { channel = channel }) then return false end
	NoticeSoon()
	return true
end

local function Filter(frame, _, text, sender, _, channel, _, _, _, _, channelName, _, lineID, guid)
	if not ns.HushedChannel(text, sender, lineID, guid, Clean(channel) or Clean(channelName)) then return false end
	if type(frame) == "table" then frames[frame] = true end
	return true
end

-- Whispers from strangers ------------------------------------------------------------------------------------------

-- Someone of your group (by name: the game knows them so).
local function InGroup(who)
	return Clean(Safe(UnitInParty, who)) and true or Clean(Safe(UnitInRaid, who)) ~= nil
end

-- The people you whispered lately (full name -> when), this character's: kept whether the messages window is on
-- or not (its conversations are kept only when it is).
local WROTE_FOR = 30 * 86400
local function Wrote() return type(ns.DB().wrote) == "table" and ns.DB().wrote or {} end
local function NoteWrote(_, _, _, target)
	target = Clean(target)
	if type(target) ~= "string" or target == "" then return end
	local db, now = ns.DB(), time()
	db.wrote = Wrote()
	if not db.wrote[target] then ns.Prune(db.wrote, now, WROTE_FOR) end
	db.wrote[target] = now
end

-- Gold selling from a stranger: "spam", else false. A game master's whisper is never touched.
local function DecideWhisper(text, sender, guid)
	if U.IsSecret(text) or U.IsSecret(sender) or U.IsSecret(guid) then return false end
	text, guid = Clean(text), Clean(guid)
	local who = ns.Who(sender)
	if type(text) ~= "string" or not who or Known(who, guid) or InGroup(who) then return false end
	-- (someone you wrote to is no stranger)
	if Wrote()[Clean(sender)] or (ns.WroteTo and ns.WroteTo(Clean(sender))) then return false end
	return Spam(U.Upper(U.PlainText(text))) and "spam" or false
end

-- Whether a whisper stays out (asked by the chat's filter, the messages window and the line listener: decided once).
function ns.HushedWhisper(text, sender, lineID, guid, flags)
	if not ns.On("quietWhispers") or U.IsSecret(text) or U.IsSecret(sender) then return false end
	flags = Clean(flags)
	if flags == "GM" or flags == "DEV" then return false end
	if not Once(text, sender, lineID, guid, DecideWhisper, { channel = L.CHAT_TAB_WHISPERS }) then return false end
	NoticeSoon()
	return true
end

local function WhisperFilter(frame, _, text, sender, _, _, _, flags, _, _, _, _, lineID, guid)
	if not ns.HushedWhisper(text, sender, lineID, guid, flags) then return false end
	if type(frame) == "table" then frames[frame] = true end
	return true
end

-- The window of what was kept out -------------------------------------------------------------------------------

local window

-- "[2. Trade]": the channel's number and name, without its place.
local function Channel(name)
	if type(name) ~= "string" then return "" end
	return Skin.Colorize("[" .. (name:gsub("%s+%-%s+.*$", "")) .. "] ", "muted")
end

local function Line(entry)
	local name = ns.Who(entry.sender) or entry.sender or "?"
	local who = entry.sender and ("|Hplayer:" .. entry.sender .. "|h[" .. ns.Named(name, entry.guid) .. "]|h") or name
	local why = entry.why == "spam" and L.QUIET_WHY_SPAM or entry.why == "word" and L.QUIET_WHY_WORD:format(entry.word or "")
		or L.QUIET_WHY_REPEAT
	return Skin.Colorize(date("%H:%M", entry.at), "muted") .. "  " .. Channel(entry.channel) .. who .. ": " .. entry.text
		.. "  " .. Skin.Colorize("(" .. why .. ")", "muted")
end

-- The lines as plain text, for the copy window (a chat window's two questions).
local function Copy()
	local list = {}
	for index, entry in ipairs(hidden) do list[index] = Line(entry) end
	W.CopyChat({ GetNumMessages = function() return #list end, GetMessageInfo = function(_, index) return list[index] end })
end

local function Make()
	window = Skin.CreateWindow("WandererChatHidden", "MEDIUM")
	window:SetSize(WIDTH, HEIGHT)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 80 }, "chatHidden")
	local _, title, m = Skin.Header(window, "Wanderer", L.QUIET_TITLE, { settings = "ext:chat" })
	title:SetPoint("RIGHT", window, "RIGHT", -(m + 60), 0)
	window.count = Skin.Chip(window)
	window.count:SetPoint("LEFT", title, "RIGHT", 8, 0)
	window.summary = Skin.Text(window, "GameTooltipTextSmall", "muted")
	window.summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	window.summary:SetPoint("RIGHT", window, "RIGHT", -m, 0)
	window.summary:SetText(L.QUIET_SUMMARY)
	-- The lines, as in the chat (a name under the mouse: its card; the wheel scrolls).
	local list = CreateFrame("ScrollingMessageFrame", nil, window)
	list:SetPoint("TOPLEFT", window.summary, "BOTTOMLEFT", 0, -10)
	list:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -m, m + 32)
	list:SetFontObject(Skin.FontFor("ChatFontNormal"))
	list:SetJustifyH("LEFT")
	list:SetFading(false)
	list:SetMaxLines(KEPT)
	list:SetHyperlinksEnabled(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta) if delta > 0 then self:ScrollUp() else self:ScrollDown() end end)
	list:SetScript("OnHyperlinkClick", function(_, link, text, button) if SetItemRef then SetItemRef(link, text, button) end end)
	if ns.WatchNames then ns.WatchNames(list) end
	window.list = list
	window.empty = Skin.Text(window, "GameTooltipText", "muted")
	window.empty:SetPoint("CENTER", list, "CENTER")
	window.empty:SetText(L.QUIET_EMPTY)
	-- At its foot: the switch itself, then copy and empty.
	window.switch = Skin.Check(window, L.QUIET_CHANNELS, function() return ns.On("quietChannels") end, function(on)
		W.ChangeEverywhere(function()
			local settings = ns.Settings()
			if settings then settings.quietChannels = on end
		end)
	end, L.QUIET_CHANNELS_DESC)
	window.switch:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", m, m + 3)
	window.clear = Skin.SmallButton(window, L.QUIET_CLEAR, function()
		wipe(hidden)
		ns.RedrawHidden()
	end, L.QUIET_CLEAR_DESC)
	window.clear:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -m, m)
	window.copy = Skin.SmallButton(window, L.QUIET_COPY, Copy, L.QUIET_COPY_DESC)
	window.copy:SetPoint("RIGHT", window.clear, "LEFT", -6, 0)
end

function ns.RedrawHidden()
	if not (window and window:IsShown()) then return end
	window.list:Clear()
	for _, entry in ipairs(hidden) do window.list:AddMessage(Line(entry)) end
	window.empty:SetShown(hidden[1] == nil)
	window.count:Set(hidden[1] and tostring(#hidden) or nil, "grey")
	if hidden[1] then window.copy:Enable() window.clear:Enable() else window.copy:Disable() window.clear:Disable() end
	window.switch:Refresh()
end

function ns.ShowHidden()
	if not window then Make() end
	window:SetScale(Skin.FitScale(window))
	window:Show()
	Skin.Get(window):Layout()
	ns.RedrawHidden()
end
ns.HiddenLines = function() return hidden end -- (tests)

-- A click on the notice's link.
local function OnLink(link)
	if link == LINK then ns.ShowHidden() end
end
ns.OpenQuietLink = OnLink -- (tests)

function ns.InitQuiet()
	selling = ns.List(L.QUIET_SELLING .. "," .. ns.LOCALES.enUS.QUIET_SELLING)
	ns.AddFilter("CHAT_MSG_CHANNEL", Filter)
	ns.AddFilter("CHAT_MSG_WHISPER", WhisperFilter)
	ns.OnLink(OnLink)
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
	events:SetScript("OnEvent", NoteWrote)
end
