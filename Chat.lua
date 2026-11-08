local ADDON, ns = ...
local L = ns.L

-- Wanderer Chat: presence without taking room. The chat stays the one place to read. In the chat, the lines
-- that name you are in gold and the guild and the group stand out a little (Highlight.lua). Alerts, beside the
-- chat (Alerts.lua), come only for you or for something to do: your name said where you could not read it, a
-- greeting to answer (Moments.lua; a group sought or a word of yours when asked for: Channels.lua). The chat keeps its comforts (Comfort.lua), its tabs
-- with what is unread (Tabs.lua) and the private messages in their window (Messages.lua). Here: the settings,
-- what is kept, and every line heard, handed to the others.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

ns.GAME_SIZE = 9 -- the font size slider's lowest step: each window keeps the game's own

ns.DEFAULTS = {
	enabled = true,
	-- The chat's display: "glass" (the game's chat dressed, Glass.lua) or "game" (as the game draws it).
	look = "glass",
	lookReset2 = false, -- (glass made the display of every profile once, in the glass round)
	glassFade = 20, -- in glass, seconds a line stays before it fades (0: always)
	shortChannels = true, -- "[2. Trade - City]" as "[2. Trade]"
	-- The tabs "Create the chat tabs" makes, and what came on each while it was not shown.
	group = true, guild = true, whispers = true, channels = true,
	unread = true,
	-- The chat's comforts.
	arrowHistory = true, -- Up and Down bring back your sent messages, kept between sessions
	copyButton = true, -- a discreet copy button in the corner of the chat
	keepLog = true, -- each tab keeps its last lines from one session to the next
	links = true, -- web addresses in the chat become links, ready to copy
	fontSize = 16, -- every chat window at this size; the lowest step: the game's own (set tab by tab)
	-- Private messages in their own window: asked for.
	messagesWindow = false,
	messagesPopup = true, -- the window opens on a new message (never in a fight)
	messagesHideInChat = true, -- and the chat no longer shows them
	messagesSound = true, -- the game's own whisper sound, which the chat no longer plays for them
	messagesMoved = false, -- (the settings of the window, once read from Wanderer's)
	-- The alerts, beside the chat: your name said where you could not read it, a greeting to answer (groups
	-- sought and your words: asked for).
	mentionCard = true, greetings = true,
	-- In the chat itself.
	mention = true, -- the lines that name you in gold, their tab marked
	mentionChannels = false, -- and in the public channels (General, Trade...)
	mentionSoundOn = true, -- a sound when your name is said, once a minute at most
	mentionSound = "TELL_MESSAGE", -- its sound (a SOUNDKIT name)
	emphasis = true, -- the guild's and the group's lines a little brighter in the General tab
	lookingFor = false, -- a group sought for a dungeon of your level, in the public channels
	words = "", -- your own words watched in the public channels, separated by commas
	-- People in the chat (Social.lua).
	nameCard = true, -- a card on a player's name under the mouse: who, where, their guild, your note
	replies = true, -- the game's menu of a name in the chat: greet, reply, quote (written, sent by your Enter)
	-- The public channels quieter (Quiet.lua): on for a new character (every way to play turns it on); a saved one keeps its own.
	quietChannels = true, -- the same words again within a minute, and obvious gold selling, kept out
	quietWhispers = true, -- gold selling whispered by a stranger: no sound, no window, kept out with them
	hiddenWords = "", -- your words that keep a line out of the public channels, separated by commas
	otherNames = "", -- your other names (a nickname, your main), in gold and alerting as your own, separated by commas
}

function ns.Settings() return W and W.Settings and W.Settings("chat") or nil end

-- A setting, Wanderer and the chat on (no key: the chat on).
function ns.On(key)
	local settings = ns.Settings()
	if not (settings and settings.enabled) then return false end
	return key == nil or settings[key] and true or false
end

-- What is kept, all this character's: the messages, the lines of each tab, what you sent, the bubbles' colors,
-- the window's size, the alerts' place.
function ns.DB()
	WandererChatDB = type(WandererChatDB) == "table" and WandererChatDB or {}
	return WandererChatDB
end

-- The chat lived in Wanderer before: what it kept comes here once, this character's part when it logs in.
-- What was the account's then (the bubbles' colors, the window's size) is each character's start for a
-- month, kept apart (WandererChatAccountDB); a character made later starts clean.
local MONTH = 30 * 86400
local function MoveIn()
	local db = ns.DB()
	if db.movedIn then return end
	db.movedIn = true
	for name, old in pairs({ history = "chatHistory", log = "chatLog", fontBefore = "chatFontBefore", messages = "messages" }) do
		if db[name] == nil then db[name] = W.MoveOut(old, true) end
	end
	WandererChatAccountDB = type(WandererChatAccountDB) == "table" and WandererChatAccountDB or {}
	local account = WandererChatAccountDB
	if not account.movedIn then
		account.movedIn = true
		account.colors = account.colors or W.MoveOut("messageColors")
		account.size = account.size or W.MoveOut("messagesSize")
	end
	account.sharedUntil = account.sharedUntil or time() + MONTH
	if time() <= account.sharedUntil then
		for _, name in ipairs({ "colors", "size" }) do
			if db[name] == nil then db[name] = U.Copy(account[name]) end
		end
	end
	account.offered = nil
end

-- The window's settings, read once from where Wanderer kept them (each profile when it is used).
local MOVED = { enabled = "messagesWindow", popup = "messagesPopup", hideInChat = "messagesHideInChat", sound = "messagesSound" }
local function MoveSettings()
	local settings, old = ns.Settings(), W.Settings("messages")
	-- (the glass round: glass is the display of every profile once, the panel and the bubbles gone; free to choose after)
	if settings and not settings.lookReset2 then
		settings.lookReset2 = true
		settings.look = "glass"
		settings.panel, settings.bubbles, settings.lookReset, settings.calmFade = nil, nil, nil, nil
		ns.DB().panel = nil -- (the panel's place, kept by the panel)
	end
	if not settings or settings.messagesMoved then return end
	settings.messagesMoved = true
	if type(old) ~= "table" then return end
	for from, to in pairs(MOVED) do
		if type(old[from]) == "boolean" then settings[to] = old[from] end
	end
end

-- People ----------------------------------------------------------------------------------------------------

function ns.Me() return Clean(Safe(UnitName, "player")) end

-- A sender's name as the chat shows it (without the realm, when it is yours).
function ns.Who(sender)
	sender = Clean(sender)
	if type(sender) ~= "string" then return nil end
	return Ambiguate and Clean(Safe(Ambiguate, sender, "none")) or sender:match("^([^%-]+)") or sender
end

-- A name in its class's color, when its class is known.
function ns.Named(name, guid)
	local _, class = Safe(GetPlayerInfoByGUID, Clean(guid))
	local r, g, b = U.ClassColor(Clean(class))
	return r and U.Colorize(name, r, g, b) or name
end

-- A few words of a message, plain (no links, no colors), cut at a whole letter.
function ns.Excerpt(text, most)
	text = U.PlainText(text)
	if #text > most then text = text:sub(1, most):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
	return text
end

-- Names said together: "Lysa", "Lysa and Tom", "Lysa, Tom and Eric", "Lysa, Tom and 2 others".
function ns.Names(list)
	if #list == 1 then return list[1] end
	if #list == 2 then return L.NAMES_TWO:format(list[1], list[2]) end
	if #list == 3 then return L.NAMES_THREE:format(list[1], list[2], list[3]) end
	return L.NAMES_MANY:format(list[1], list[2], #list - 2)
end

-- Words of a message, upper case and plain, between spaces (" HELLO ALL "): found whole with Has().
function ns.Words(text)
	local words = U.Upper(U.PlainText(text)):gsub("[%.,;:!%?%(%)\"]", " "):gsub("%s+", " ")
	return " " .. words .. " "
end

-- Chinese, Japanese and Korean letters (their first byte): these write without spaces between words, so
-- their words are found within the text.
local CJK = "[\227-\237]"
function ns.IsCJK(text) return type(text) == "string" and text:find(CJK) ~= nil end

function ns.Has(words, phrase)
	if ns.IsCJK(phrase) then return words:find(phrase, 1, true) ~= nil end
	return words:find(" " .. phrase .. " ", 1, true) ~= nil
end

-- A list of words or phrases separated by commas, upper case (a locale's, a setting's).
function ns.List(text)
	local list = {}
	for item in tostring(text or ""):gmatch("[^,]+") do
		item = U.Upper(strtrim(item))
		if item ~= "" then list[#list + 1] = item end
	end
	return list
end

-- The entries of a table of times (key -> when) older than window seconds, gone.
function ns.Prune(list, now, window)
	for key, at in pairs(list) do
		if now - at > window then list[key] = nil end
	end
end

-- The Wanderer tab of the chat (diagnostic mode): its number, looked for again only when the tabs change.
local debugIndex, debugKnown = nil, false
function ns.IsDebugTab(index)
	if index == nil then return false end
	if not debugKnown then
		debugKnown, debugIndex = true, nil
		for i = 1, NUM_CHAT_WINDOWS or 10 do
			if W.IsDebugTab(i) then
				debugIndex = i
				break
			end
		end
	end
	return index == debugIndex
end
local function TabsChanged()
	debugKnown = false
	if ns.TabKeysChanged then ns.TabKeysChanged() end
end

-- Your guild ------------------------------------------------------------------------------------------------

-- short name -> what the roster says (ns.GuildRead fired each time it is read again): { rank, level, className, class, zone, online, away (seconds offline when
-- read), guid }. Read once for a burst of updates: nothing asked of the server beyond what the game asks.
local members = {}
local membersAt = 0 -- when it was read (time())
local function InGuild(name) return name ~= nil and members[name] ~= nil end

-- Seconds since a member was last online, from the roster's years, months, days and hours (nil: unknown).
local function Offline(index)
	local years, months, days, hours = Safe(GetGuildRosterLastOnline, index)
	years, months, days, hours = Clean(years), Clean(months), Clean(days), Clean(hours)
	if not (years or months or days or hours) then return nil end
	return (((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24 + (hours or 0)) * 3600
end

local function ReadGuild()
	members, membersAt = {}, time()
	for index = 1, (IsInGuild and IsInGuild()) and Clean(Safe(GetNumGuildMembers)) or 0 do
		local full, rank, _, level, className, zone, _, _, online, _, class, _, _, _, _, _, guid = Safe(GetGuildRosterInfo, index)
		local name = ns.Who(full)
		if name then
			online = Clean(online) and true or false
			members[name] = { rank = Clean(rank), level = Clean(level), className = Clean(className), class = Clean(class),
				zone = Clean(zone), online = online, away = not online and Offline(index) or nil, guid = Clean(guid) }
		end
	end
	ns.GuildRead.Fire()
end

-- A member of your guild by name (as the chat shows it): the roster's entry and when it was read, else nil.
function ns.GuildMember(name)
	local entry = name and members[ns.Who(name) or name]
	if entry then return entry, membersAt end
end

-- The roster asked again when it is older than a minute (the game answers with GUILD_ROSTER_UPDATE).
function ns.FreshenGuild()
	if time() - membersAt < 60 or not (IsInGuild and IsInGuild()) then return end
	if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
end

-- Lines heard -------------------------------------------------------------------------------------------------
-- One listener for every line of the chat (events: once each, whatever the tabs), given to the others as
-- { kind, event, text, who, sender, guid, lineID, channel, me, at }. A secret line (the game's, during a fight) is
-- never read.

ns.KINDS = {
	CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "officer", CHAT_MSG_GUILD_ACHIEVEMENT = "achievement",
	CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
	CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
	CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
	CHAT_MSG_SAY = "near", CHAT_MSG_YELL = "near", CHAT_MSG_EMOTE = "near",
	CHAT_MSG_CHANNEL = "channel", CHAT_MSG_WHISPER = "whisper", CHAT_MSG_SYSTEM = "system",
	CHAT_MSG_BN_WHISPER = "bnwhisper",
}
ns.GUILD = { guild = true, officer = true }
ns.GROUP = { party = true, raid = true, instance = true }
-- (each kind's own chat, for its color and to answer in it)
ns.CHAT_TYPE = { guild = "GUILD", officer = "OFFICER", party = "PARTY", raid = "RAID", instance = "INSTANCE_CHAT",
	near = "SAY", channel = "CHANNEL", whisper = "WHISPER", system = "SYSTEM", achievement = "GUILD_ACHIEVEMENT" }

-- ns.Heard: every line (made in Init, once Wanderer is known to be recent enough: an older one has no signals).
local ONLINE -- the game's line of someone coming online, as a pattern

-- Busy: a fight, a conversation scene, away from the keyboard.
function ns.Busy()
	return (InCombatLockdown and InCombatLockdown()) or Clean(Safe(UnitAffectingCombat, "player")) or W.InScene()
		or Clean(Safe(UnitIsAFK, "player")) or false
end

-- Whether a line matters to the cards: the guild, the group, an arrival (heard while busy: it waits, no card).
local function Kept(line)
	return ns.GUILD[line.kind] or ns.GROUP[line.kind] or line.arrival
end

-- The last one to speak to you or near you, for the key that answers.
ns.last = nil

local function OnEvent(_, event, text, sender, _, channel, _, flags, _, _, baseChannel, _, lineID, guid, bnID)
	local kind = ns.KINDS[event]
	if not kind or not ns.On() or U.IsSecret(text) or U.IsSecret(sender) then return end
	-- (gold selling whispered by a stranger: kept out, never heard; Quiet.lua)
	if kind == "whisper" and ns.HushedWhisper and ns.HushedWhisper(text, sender, lineID, guid, flags) then return end
	-- (a public line kept out of the chat, a repeat, gold selling or a hidden word: no card for it either)
	if kind == "channel" and ns.HushedChannel and ns.HushedChannel(text, sender, lineID, guid, Clean(channel) or Clean(baseChannel)) then
		return
	end
	-- A Battle.net whisper: only kept for the key that answers (its id, its name as the game gave it).
	if kind == "bnwhisper" then
		bnID = Clean(bnID)
		if bnID then ns.last = { kind = kind, bnID = bnID, sender = Clean(sender), at = GetTime() } end
		return
	end
	local line = { kind = kind, event = event, text = Clean(text), sender = Clean(sender), who = ns.Who(sender),
		guid = Clean(guid), lineID = Clean(lineID), at = GetTime() }
	if type(line.text) ~= "string" then return end
	if kind == "system" then
		-- Someone of your guild comes online (the game's own line).
		local name = ONLINE and line.text:match(ONLINE)
		name = name and ns.Who(name:match("^([^:]+)"))
		if not (name and InGuild(name)) then return end
		line.kind, line.who, line.arrival = "guild", name, true
	else
		if not line.who then return end
		-- (by the character itself: a name may carry a family name the game's own does not)
		line.me = (line.guid ~= nil and line.guid == Clean(Safe(UnitGUID, "player"))) or line.who == ns.Me()
		if kind == "channel" then line.channel = Clean(baseChannel) or Clean(channel) end
		if not line.me and kind ~= "near" and kind ~= "channel" and kind ~= "achievement" then
			ns.last = line
		end
	end
	if Kept(line) and not line.me and ns.Busy() then line.waiting = true end
	ns.Heard.Fire(line)
end

-- Answering --------------------------------------------------------------------------------------------------

-- A private message to someone: in the messages window when it is on, else in the chat.
function ns.Whisper(name)
	if not name then return end
	if ns.On("messagesWindow") then return ns.ToggleMessages(name, true) end
	if ChatFrame_SendTell then ChatFrame_SendTell(name) end
end

-- The same to a Battle.net friend (its id; its name as the game gave it, for the chat).
local function WhisperBattleNet(bnID, name)
	if ns.On("messagesWindow") then return ns.ToggleMessages("BN:" .. bnID, true) end
	if name and ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(name) end
end

-- Each chat's slash (by the game's chat type), to answer where a line was said; the others answer privately.
ns.SLASH = { GUILD = "/g ", OFFICER = "/o ", PARTY = "/p ", PARTY_LEADER = "/p ", RAID = "/raid ", RAID_LEADER = "/raid ",
	RAID_WARNING = "/raid ", INSTANCE_CHAT = "/i ", INSTANCE_CHAT_LEADER = "/i " }

-- Words written in the chat's line (a click on a greeting, a reply): sent only by your own Enter, never by a stray
-- click.
function ns.OpenChatLine(text)
	local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
	if open and text and text ~= "" then open(text, SELECTED_DOCK_FRAME or DEFAULT_CHAT_FRAME) end
end

-- The chat's line opened to answer where a line was said (privately for a public channel or the street).
function ns.Answer(line)
	if not line then return end
	if line.kind == "bnwhisper" then return WhisperBattleNet(line.bnID, line.sender) end
	if line.kind == "whisper" or line.kind == "channel" or line.kind == "near" then return ns.Whisper(line.sender) end
	ns.OpenChatLine(ns.SLASH[ns.CHAT_TYPE[line.kind] or ""])
end

-- The chat's plumbing, the same for every file ---------------------------------------------------------------

-- A filter on a chat event (wherever this game keeps the function).
function ns.AddFilter(event, fn)
	local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if add then pcall(add, event, fn) end
end

-- A click on an addon's link: the game hands them over through its registry, older games through SetItemRef;
-- heard by both, each listener told once.
local linkListeners, lastLink, lastLinkAt = {}, nil, -math.huge
local function HeardLink(link)
	if type(link) ~= "string" or U.IsSecret(link) then return end
	if link == lastLink and GetTime() - lastLinkAt < 0.3 then return end
	lastLink, lastLinkAt = link, GetTime()
	for _, listener in ipairs(linkListeners) do listener(link) end
end
function ns.OnLink(listener)
	if not linkListeners[1] then
		if EventRegistry and EventRegistry.RegisterCallback then
			EventRegistry:RegisterCallback("SetItemRef", function(_, link) HeardLink(link) end, {})
		end
		if SetItemRef then hooksecurefunc("SetItemRef", HeardLink) end
	end
	linkListeners[#linkListeners + 1] = listener
end

-- A chat's color ("GUILD", "CHANNEL2"): r, g, b, nil when the game does not say it.
function ns.ChatColor(chatType)
	local info = type(ChatTypeInfo) == "table" and chatType and ChatTypeInfo[chatType]
	if type(info) ~= "table" or type(info.r) ~= "number" then return nil end
	return info.r, info.g or 1, info.b or 1
end

-- Whether a line shown (its color, the id of its chat when the game gives it) is of one of these chats: by the
-- id when both are known, else by the color.
function ns.IsChatType(chatTypes, r, g, b, id)
	local types = type(ChatTypeInfo) == "table" and ChatTypeInfo or {}
	for _, chatType in ipairs(chatTypes) do
		local info = types[chatType]
		if type(info) == "table" then
			if id ~= nil and info.id ~= nil then
				if info.id == id then return true end
			elseif r ~= nil and info.r == r and info.g == g and info.b == b then
				return true
			end
		end
	end
	return false
end

-- Another addon doing one of the chat's jobs, asked for every line: the answer kept a few seconds.
local yieldsKept = {}
function ns.YieldsNow(job)
	local kept = yieldsKept[job]
	if kept and GetTime() - kept.at < 5 then return kept.who end
	yieldsKept[job] = { at = GetTime(), who = ns.Yields(job) }
	return yieldsKept[job].who
end

-- The chat's line being written in now (the game's own, wherever this game keeps it), or nil.
function ns.ActiveEditBox()
	local util = ChatFrameUtil
	local box = util and util.GetActiveWindow and Safe(util.GetActiveWindow)
	if not box and ChatEdit_GetActiveWindow then box = Safe(ChatEdit_GetActiveWindow) end
	return type(box) == "table" and box or nil
end

-- Another addon doing one of the chat's jobs ("chatHistory", "chatLog", "whispers", "chatLook"): its name, else nil.
function ns.Yields(job) return W and W.Yields and W.Yields(job) or nil end

function WandererChat_Reply() if ns.ready then ns.Answer(ns.last) end end
function WandererChat_ToggleMessages() if ns.ready then ns.ToggleMessages() end end

-- Start ------------------------------------------------------------------------------------------------------

function ns.Refresh()
	if not ns.ready then return end
	MoveSettings()
	ns.RefreshComfort()
	ns.RefreshMessages()
	ns.RefreshChatWhisperButton()
	ns.RefreshTabs()
	ns.RefreshHolder()
	if ns.RefreshGlass then ns.RefreshGlass() end
end

BINDING_HEADER_WANDERERCHAT = "Wanderer Chat"
BINDING_NAME_WANDERERCHAT_MESSAGES = L.BINDING_MESSAGES
BINDING_NAME_WANDERERCHAT_REPLY = L.BINDING_REPLY
-- (Wanderer's own name for it, before the chat moved: a key chosen then still opens the messages)
BINDING_NAME_WANDERER_MESSAGES = L.BINDING_MESSAGES_FORMER

local DUMP_DELAY = 8 -- seconds before /wchat dump looks at everything (the fading followed for 40)

-- At login: everything set up, then every line heard.
local function Start()
	MoveIn()
	MoveSettings()
	SLASH_WANDERERCHAT1 = "/wchat"
	SlashCmdList.WANDERERCHAT = function(words)
		-- (/wchat dump: what is drawn over the chat, written for a look after a /reload)
		-- (taken a few seconds later: the line to write closed, the mouse away, the chat back at rest as it fades)
		if type(words) == "string" and strtrim(words):lower() == "dump" and ns.GlassDump then
			W.Print(L.DUMP_SOON:format(40))
			-- (then a look every 2 seconds for 40 seconds: the lines fading, as they fade)
			local samples = {}
			for at = 0, 40, 2 do
				C_Timer.After(at, function()
					if ns.GlassSample then for _, line in ipairs(ns.GlassSample(at)) do samples[#samples + 1] = line end end
					if at == DUMP_DELAY then ns.GlassDump() end
					if at == 40 then
						WandererChatAccountDB = WandererChatAccountDB or {}
						WandererChatAccountDB.glassSamples = samples
						W.Print(L.DUMP_DONE:format(#samples))
					end
				end)
			end
			return
		end
		-- (/wchat search: the search over the chat in view)
		if type(words) == "string" and strtrim(words):lower() == "search" and ns.OpenSearch then return ns.OpenSearch() end
		ns.ToggleMessages()
	end
	-- (glass first: the lines of before, put back by the comforts, come dressed)
	if ns.InitGlass then ns.InitGlass() end
	ns.InitComfort()
	ns.InitMessages()
	ns.InitTabs()
	ns.InitHighlight()
	ns.InitHolder()
	ns.InitAlerts()
	ns.InitMoments()
	ns.InitChannels()
	ns.InitSocial()
	ns.InitQuiet()
	ns.ready = true
	-- (the tabs renamed, opened or closed: the Wanderer tab looked for again)
	for _, name in ipairs({ "FCF_OpenNewWindow", "FCF_Close", "FCF_SetWindowName" }) do
		if _G[name] then hooksecurefunc(name, TabsChanged) end
	end
	local readSoon = U.Debounce(1, ReadGuild)
	local events = CreateFrame("Frame")
	events:RegisterEvent("GUILD_ROSTER_UPDATE")
	events:RegisterEvent("PLAYER_GUILD_UPDATE")
	events:RegisterEvent("UPDATE_CHAT_WINDOWS")
	events:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_CHAT_WINDOWS" then return TabsChanged() end
		-- (often, while the guild's window is open: once for a burst)
		readSoon()
	end)
	if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
	ReadGuild()
	local heard = CreateFrame("Frame")
	for chatEvent in pairs(ns.KINDS) do pcall(heard.RegisterEvent, heard, chatEvent) end
	heard:SetScript("OnEvent", OnEvent)
end

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	-- (built on Wanderer's API 17, its ChangeEverywhere: an older Wanderer is only asked to update, nothing of it is called)
	if (W.API or 1) < 17 then return W.Print(L.NEEDS_WANDERER) end
	ns.Heard, ns.GuildRead = U.Signal(), U.Signal()
	ONLINE = U.FormatPattern(ERR_FRIEND_ONLINE_SS or "|Hplayer:%s|h[%s]|h has come online.")
	W.RegisterExtension({
		key = "chat",
		addon = ADDON,
		slash = "/wchat",
		title = L.ADDON,
		news = L.NEWS_LINES,
		defaults = ns.DEFAULTS,
		ranges = { ["chat.fontSize"] = { ns.GAME_SIZE, 24, 1 } },
		launcher = {
			label = function()
				local unread = ns.UnreadMessages()
				return unread > 0 and L.MENU_MESSAGES_UNREAD:format(unread) or L.MESSAGES_TITLE
			end,
			open = function() ns.ToggleMessages() end,
			shown = function() return ns.On("messagesWindow") end,
			attention = function() return ns.On("messagesWindow") and ns.UnreadMessages() > 0 end,
		},
		refresh = ns.Refresh,
		options = ns.Options,
	})
	local login = CreateFrame("Frame")
	login:RegisterEvent("PLAYER_LOGIN")
	login:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_LOGIN")
		Start()
	end)
end

if W and W.WhenLoaded then W.WhenLoaded(ADDON, ns.Init) elseif W and W.Print then W.Print(L.NEEDS_WANDERER) end
