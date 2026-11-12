local _, ns = ...
local L = ns.L

-- People in the chat.
-- * A name in the chat rested on under the mouse (a quarter of a second) brings a small card beside it, to know
--   at once who it is: the name in its class's color, level and class, where they are and whether online, their
--   guild and rank, when a member of yours was last online, a Friend chip, your own note on them (this
--   character's, a click to change it). Only what the game already knows: your guild's roster, your friends, your
--   group, the players you pointed at or targeted, what a chat line carries. Never a /who. The card only tells:
--   the game's own clicks on the name do the rest (a left click whispers, a right click opens its menu).
-- * The private messages window on: a left click on a name opens your conversation with them there, instead of
--   the chat's whisper line (Shift and the other keys keep the game's own clicks).
-- * A right click on a name: the game's own menu gets Greet, Reply, Quote and Copy the line.
-- Nothing is ever sent for you: Greet, Reply and Quote write in the chat's line and your Enter sends it. No secure
-- frame: nothing here minds a fight.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local DELAY = 0.25 -- seconds a name is rested on before its card
local GRACE = 0.4 -- seconds the card waits for the mouse to come onto it
local WIDTH = 248
local ICON = 14
local NOTE_HEIGHT = 20
local LINES_KEPT = 300 -- chat lines remembered (to quote one, to know whose it was)
local MET_KEPT = 400 -- players met kept this session
local QUOTE_MOST = 180 -- letters of a quoted line (the chat's line holds 255)
local NOTE_MOST = 120
local FRESH = 120 -- seconds: a player met this lately needs no "seen ... ago"
local MENU_TAGS = { "MENU_UNIT_FRIEND" } -- the game's menu of a name in the chat (UnitPopup's "FRIEND")

local NOTE_ICON = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"

-- What the chat said -----------------------------------------------------------------------------------------------

local lines, lineOrder = {}, {} -- line id -> the line heard (Chat.lua); the ids, oldest first
local guidByName = {} -- short name -> the last guid seen saying something

local function Keep(line)
	if line.who and line.guid then guidByName[line.who] = line.guid end
	local id = line.lineID
	if not id then return end
	local known = lines[id] ~= nil
	lines[id] = line
	if known then return end
	lineOrder[#lineOrder + 1] = id
	if #lineOrder > LINES_KEPT then lines[table.remove(lineOrder, 1)] = nil end
end

-- A line by its id (a player link carries it), nil when long gone.
function ns.LineByID(id) return lines[tonumber(id) or id] end

-- Players met: pointed at, targeted ------------------------------------------------------------------------------

local met, metByName, metCount = {}, {}, 0 -- guid -> { name, level, class, className, raceName, guild, rank, zone, at }

local function Forget()
	-- (the oldest half, once the list is full: a session meets many people in a city)
	local list = {}
	for guid, entry in pairs(met) do list[#list + 1] = { guid, entry.at } end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	for index = 1, math.floor(#list / 2) do
		local entry = met[list[index][1]]
		if entry and metByName[entry.name] == list[index][1] then metByName[entry.name] = nil end
		met[list[index][1]] = nil
	end
	metCount = #list - math.floor(#list / 2)
end

local function Meet(unit)
	if not Clean(Safe(UnitIsPlayer, unit)) then return end
	local guid = Clean(Safe(UnitGUID, unit))
	local name = ns.Who(Clean(Safe(UnitName, unit)))
	if not (guid and name) or name == ns.Me() then return end
	local className, class = Safe(UnitClass, unit)
	local guild, rank = Safe(GetGuildInfo, unit)
	if not met[guid] then metCount = metCount + 1 end
	met[guid] = { name = name, level = Clean(Safe(UnitLevel, unit)), class = Clean(class), className = Clean(className),
		raceName = Clean(Safe(UnitRace, unit)), guild = Clean(guild), rank = Clean(rank), zone = Clean(Safe(GetRealZoneText)),
		at = time() }
	metByName[name] = guid
	if metCount > MET_KEPT then Forget() end
end

-- Who someone is -----------------------------------------------------------------------------------------------

-- The friends list's functions, current or older names (the messages window's actions use them too).
local function Friends(name) return C_FriendList and C_FriendList[name] or _G[name] end
ns.FriendList = Friends

-- Your group's unit of that name (nil: not in it).
local function GroupUnit(short, guid)
	local raid = IsInRaid and Clean(Safe(IsInRaid))
	local count = raid and (Clean(Safe(GetNumGroupMembers)) or 0) or 4
	for index = 1, count do
		local unit = (raid and "raid" or "party") .. index
		if Clean(Safe(UnitExists, unit)) then
			local same = guid and Clean(Safe(UnitGUID, unit)) == guid or ns.Who(Clean(Safe(UnitName, unit))) == short
			if same then return unit, raid and index or nil end
		end
	end
end

local function NoteKey(info) return info.guid or info.name end

local function Notes()
	local db = ns.DB()
	db.notes = type(db.notes) == "table" and db.notes or {}
	return db.notes
end

-- Your note on someone (by their guid when known, else their name), nil when none.
function ns.PlayerNote(info)
	local notes = Notes()
	return (info.guid and notes[info.guid]) or notes[info.name]
end

function ns.SetPlayerNote(info, text)
	local notes = Notes()
	text = text and strtrim(text) or ""
	if text == "" then text = nil end
	-- (kept by guid when known: two players may share a first name)
	if info.guid then notes[info.name] = nil end
	notes[NoteKey(info)] = text
end

-- Everything known of someone named so in the chat (name: as the link gives it; guid: the line's, if any).
-- { name, full, guid, class, className, raceName, level, zone, guild, rank, online, away, seenAt, friend, group,
--   guildmate, mine, note }
function ns.PersonInfo(full, guid)
	local short = ns.Who(full) or full
	local info = { name = short, full = full, guid = guid or guidByName[short] or metByName[short] }
	if info.guid then
		local className, class, raceName = Safe(GetPlayerInfoByGUID, info.guid)
		info.className, info.class, info.raceName = Clean(className), Clean(class), Clean(raceName)
	end
	local function Fill(field, value)
		if info[field] == nil then info[field] = value end
	end
	-- Your group: what the game shows of them now.
	local unit, raidIndex = GroupUnit(short, info.guid)
	if unit then
		info.group = true
		info.level = Clean(Safe(UnitLevel, unit))
		Fill("class", select(2, Safe(UnitClass, unit)))
		local zone = raidIndex and select(7, Safe(GetRaidRosterInfo, raidIndex))
		info.zone = Clean(zone) or (Clean(Safe(UnitIsVisible, unit)) and Clean(Safe(GetRealZoneText))) or nil
		info.online = Clean(Safe(UnitIsConnected, unit)) and true or false
	end
	-- Your friends.
	local friend = Safe(Friends("GetFriendInfo"), short)
	if type(friend) == "table" then
		info.friend = true
		if info.online == nil then info.online = friend.connected and true or false end
		if friend.connected then
			Fill("level", Clean(friend.level))
			Fill("zone", Clean(friend.area))
			Fill("className", Clean(friend.className))
		end
	end
	-- Your guild (the roster; a namesake with another guid is someone else).
	local member, readAt = ns.GuildMember(short)
	if member and not (info.guid and member.guid and member.guid ~= info.guid) then
		info.guildmate = true
		info.guild, info.rank = Clean(Safe(GetGuildInfo, "player")), member.rank
		Fill("level", member.level)
		Fill("class", member.class)
		Fill("className", member.className)
		if info.online == nil then info.online = member.online end
		if member.online then Fill("zone", member.zone) end
		if member.away then info.away = member.away + math.max(0, time() - (readAt or time())) end
	end
	-- Someone you pointed at or targeted this session.
	local seen = info.guid and met[info.guid] or (not info.guid and met[metByName[short] or ""])
	if seen then
		Fill("level", seen.level)
		Fill("class", seen.class)
		Fill("className", seen.className)
		Fill("raceName", seen.raceName)
		Fill("guild", seen.guild)
		Fill("rank", seen.rank)
		if not info.zone and seen.zone then info.zone, info.seenAt = seen.zone, seen.at end
	end
	-- One of your own characters (the ledger).
	if W.Characters then
		for _, character in ipairs(W.Characters(true)) do
			if character.name == short then
				info.mine = true
				Fill("level", character.level)
				Fill("class", character.class)
			end
		end
	end
	if not info.className and info.class and LOCALIZED_CLASS_NAMES_MALE then info.className = LOCALIZED_CLASS_NAMES_MALE[info.class] end
	info.note = ns.PlayerNote(info)
	return info
end

-- Writing in the chat's line ---------------------------------------------------------------------------------------

-- Where to answer a line of that chat: its own chat for the guild and the group, else privately (a public
-- channel, the street, a whisper).
local function Start(full, chatType)
	return ns.SLASH[chatType or ""] or ("/w " .. full .. " ")
end
local function Prefill(text) ns.OpenChatLine(text) end -- (sent only by your own Enter)

-- The greeting of the hour (the greet cards' own words), the reply, the quote: { full, name, chatType, lineID }.
function ns.GreetPerson(who)
	Prefill(Start(who.full, who.chatType) .. ns.Saying("greet", { who.name }))
end
function ns.ReplyPerson(who)
	local slash = ns.SLASH[who.chatType or ""]
	Prefill(slash and (slash .. L.REPLY_FORMAT:format(who.name)) or Start(who.full))
end
function ns.QuotePerson(who)
	local line = ns.LineByID(who.lineID)
	if not (line and line.text) then return end
	Prefill(Start(who.full, who.chatType) .. L.QUOTE_FORMAT:format(ns.Excerpt(line.text, QUOTE_MOST)))
end

-- The line itself, ready for Ctrl+C (the box of the web addresses): "Name: words", plain.
function ns.CopyLine(who)
	local line = ns.LineByID(who.lineID)
	if not (line and line.text) then return end
	Skin.ShowCopy(L.COPY_LINE_PROMPT, (line.who or who.name) .. ": " .. U.PlainText(line.text))
end

-- The card ----------------------------------------------------------------------------------------------------------

local card -- made at its first use
local pending -- the link waiting its quarter second
local overLink = false
local menuHooked = false

local function Hide()
	pending = nil
	if card and card:IsShown() then card:Hide() end
end

local function EditNote()
	local who = card and card.who
	if not who then return end
	local info = card.info
	Hide()
	Skin.AskText(L.CARD_NOTE_PROMPT:format(info.name), info.note or "", function(text) ns.SetPlayerNote(info, text) end,
		NOTE_MOST, true)
end

local function Card()
	if card then return card end
	-- (a card at the mouse, read over the chat and every window: drawn as a tooltip, nearly solid)
	card = Skin.CreateWindow("WandererChatNameCard", "TOOLTIP")
	if Skin.PadWindow then Skin.PadWindow(card) end
	local cardSkin = Skin.Get(card)
	if cardSkin then
		cardSkin.minOpacity = 0.97
		cardSkin:ApplyStyle()
	end
	card:EnableMouse(true)
	card:SetClampedToScreen(true)
	local m = Skin.Margin() + 6
	card.margin = m
	card.kicker = Skin.CreateKicker(card)
	card.kicker:SetPoint("TOPLEFT", card, "TOPLEFT", m, -m)
	card.chips = { Skin.Chip(card), Skin.Chip(card) }
	card.chips[1]:SetPoint("TOPRIGHT", card, "TOPRIGHT", -m, -m + 3)
	card.chips[2]:SetPoint("RIGHT", card.chips[1], "LEFT", -4, 0)
	card.name = Skin.CreateText(card, "GameFontNormalLarge")
	card.name:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -4)
	card.name:SetPoint("RIGHT", card, "RIGHT", -m, 0)
	if card.name.SetWordWrap then card.name:SetWordWrap(false) end
	-- (who, where, which guild: one line each, shown when known)
	card.rows = {}
	for index, role in ipairs({ "soft", "muted", "label" }) do
		local row = Skin.Text(card, "GameTooltipTextSmall", role)
		if row.SetWordWrap then row:SetWordWrap(false) end
		card.rows[index] = row
	end
	card.rule = Skin.Rule(card, false, 0.14)
	-- Your note: its sign and its words (or an invitation to write one), a click to change it.
	card.note = CreateFrame("Button", nil, card)
	card.note:SetHeight(NOTE_HEIGHT)
	card.note.icon = card.note:CreateTexture(nil, "ARTWORK")
	card.note.icon:SetSize(ICON, ICON)
	card.note.icon:SetPoint("LEFT")
	card.note.icon:SetTexture(NOTE_ICON)
	card.note.text = Skin.Text(card.note, "GameTooltipTextSmall", "soft")
	card.note.text:SetPoint("LEFT", card.note.icon, "RIGHT", 6, 0)
	card.note.text:SetPoint("RIGHT", card.note, "RIGHT", 0, 0)
	if card.note.text.SetWordWrap then card.note.text:SetWordWrap(false) end
	local hover = card.note:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, Skin.HOVER or 0.05)
	card.note:SetScript("OnClick", function() Skin.Play("click") EditNote() end)
	Skin.Tooltip(card.note, function() return { L.CARD_NOTE, { (U.UsingPad and U.UsingPad()) and L.CARD_NOTE_DESC_PAD or L.CARD_NOTE_DESC, Skin.COLORS.text[1], Skin.COLORS.text[2], Skin.COLORS.text[3] } } end, "ANCHOR_BOTTOM")
	-- A right click on the card: your note.
	card:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then EditNote() end end)
	-- Kept while the mouse is on its name or on it, or the controller in it; a moment more after.
	card:SetScript("OnUpdate", function(self, elapsed)
		if overLink or self:IsMouseOver() or (Skin.PadHolds and Skin.PadHolds(self)) then
			self.away = 0
			return
		end
		self.away = (self.away or 0) + elapsed
		if self.away > GRACE then self:Hide() end
	end)
	card:HookScript("OnHide", function(self)
		self.who, self.info, self.away = nil, nil, 0
		if GameTooltip:IsOwned(self.note) then GameTooltip:Hide() end
	end)
	return card
end

-- Someone in words, the same on the name card and in the messages window (info: ns.PersonInfo's fields):
-- who ("Level 34 Human Mage"), where and how ("Stranglethorn Vale · Online"), their guild ("<Guild> · Officer"),
-- each nil when unknown. opts.classColor: the class in its color; opts.status: words in place of the online part
-- (a /who under way).
function ns.PersonLines(info, opts)
	opts = opts or {}
	local who = {}
	if info.level then who[#who + 1] = (LEVEL or "Level") .. " " .. info.level end
	if info.raceName then who[#who + 1] = info.raceName end
	if info.className then
		local r, g, b = U.ClassColor(info.class)
		who[#who + 1] = (opts.classColor and r) and U.Colorize(info.className, r, g, b) or info.className
	end
	local where = {}
	if info.zone then where[#where + 1] = info.zone end
	if opts.status then
		where[#where + 1] = opts.status
	elseif info.online == true then
		where[#where + 1] = Skin.Colorize(L.MESSAGES_ONLINE, "good")
	elseif info.away then
		where[#where + 1] = info.away < 3600 and L.CARD_LAST_ONLINE_HOUR or L.CARD_LAST_ONLINE:format(U.Ago(info.away))
	elseif info.online == false then
		where[#where + 1] = Skin.Colorize(L.MESSAGES_OFFLINE, "muted")
	elseif info.seenAt and time() - info.seenAt > FRESH then
		where[#where + 1] = L.MESSAGES_SEEN:format(U.Ago(time() - info.seenAt))
	end
	local guild = info.guild and ("<" .. info.guild .. ">") or nil
	if info.rank then guild = guild and (guild .. U.SEPARATOR .. info.rank) or info.rank end
	return who[1] and table.concat(who, " ") or nil, where[1] and table.concat(where, U.SEPARATOR) or nil, guild
end

-- The card's lines: who (else "unknown"), where and how, the guild.
local function Rows(info)
	local who, where, guild = ns.PersonLines(info)
	return { who or L.CARD_UNKNOWN, where, guild }
end

-- A piece of the card across it, its top at y under the card's.
local function At(region, y)
	local m = card.margin
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", card, "TOPLEFT", m, -y)
	region:SetPoint("TOPRIGHT", card, "TOPRIGHT", -m, -y)
end

-- The card drawn for someone: { full, name, guid, chatType, lineID }.
local function Fill(who)
	local info = ns.PersonInfo(who.full, who.guid)
	card.who, card.info = who, info
	local m = card.margin
	card.kicker:SetText(U.Upper((info.guildmate and L.CARD_GUILD) or (info.mine and L.CARD_MINE)
		or (info.group and L.CARD_GROUP) or L.CARD_PLAYER))
	local r, g, b = U.ClassColor(info.class)
	card.name:SetText(info.name)
	if r then card.name:SetTextColor(r, g, b) else card.name:SetTextColor(Skin.COLORS.gold[1], Skin.COLORS.gold[2], Skin.COLORS.gold[3]) end
	-- (the chips: a friend, in your group when the heading says otherwise)
	local chips = {}
	if info.friend then chips[#chips + 1] = { L.RELATION_FRIEND, "blue" } end
	if info.group and (info.guildmate or info.mine) then chips[#chips + 1] = { L.CARD_GROUP_CHIP, "green" } end
	for index, chip in ipairs(card.chips) do chip:Set(chips[index] and chips[index][1], chips[index] and chips[index][2]) end
	-- The lines, under the name.
	local y = m + U.Measure(card.kicker, "GetStringHeight", 10) + 4 + U.Measure(card.name, "GetStringHeight", 16) + 6
	for index, text in ipairs(Rows(info)) do
		local row = card.rows[index]
		row:SetShown(text ~= nil)
		if text then
			row:SetText(text)
			At(row, y)
			y = y + U.Measure(row, "GetStringHeight", 12) + 3
		end
	end
	card.rows[1]:SetTextColor(unpack(Skin.COLORS[info.className and "soft" or "muted"]))
	y = y + 5
	At(card.rule, y)
	y = y + 6
	At(card.note, y)
	card.note.text:SetText(info.note or L.CARD_NOTE_ADD)
	card.note.text:SetTextColor(unpack(Skin.COLORS[info.note and "soft" or "muted"]))
	card.note.icon:SetAlpha(info.note and 1 or 0.6)
	y = y + NOTE_HEIGHT
	-- (as wide as its longest line, within reason)
	local width = WIDTH
	for _, row in ipairs(card.rows) do
		if row:IsShown() then width = math.max(width, U.Measure(row, "GetStringWidth", 0) + m * 2) end
	end
	width = math.min(math.max(width, U.Measure(card.name, "GetStringWidth", 0) + m * 2 + 60), WIDTH + 120)
	card:SetSize(width, y + m)
	Skin.Get(card):Layout()
end

-- Beside the mouse, above it and to its right (the chat is low on the screen; the screen's edges hold it in).
-- Under a controller: beside the chosen element (the kit's own point, when it has one).
local function Place()
	card:SetScale(Skin.Scale())
	local x, y
	if Skin.CursorPoint then x, y = Skin.CursorPoint() else x, y = GetCursorPosition() end
	local scale = card:GetEffectiveScale()
	if not (x and y and scale and scale > 0) then return end
	card:ClearAllPoints()
	card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale + 10)
end

local function Open(who)
	if not ns.On("nameCard") or who.full == "" or ns.Who(who.full) == ns.Me() then return end
	if ns.FreshenGuild then ns.FreshenGuild() end
	Card()
	Fill(who)
	Place()
	card.away = 0
	-- (a controller: it waits to be chosen, never taking the cross by itself)
	card.quiet = true
	card:Show()
	if card.Raise then card:Raise() end
end

-- A player link: { full, name, lineID, chatType, guid } ("player:Name-Realm:lineID:CHATTYPE:target"), else nil.
function ns.ParsePlayerLink(link)
	if type(link) ~= "string" or U.IsSecret(link) then return nil end
	local body = link:match("^player:(.+)$")
	if not body then return nil end
	local full, lineID, chatType = body:match("^([^:]*):?([^:]*):?([^:]*)")
	if not full or full == "" then return nil end
	local who = { full = full, name = ns.Who(full) or full, lineID = tonumber(lineID), chatType = chatType ~= "" and chatType or nil }
	local line = who.lineID and lines[who.lineID]
	who.guid = line and line.guid or nil
	return who
end

local function OnLinkEnter(_, link)
	if not ns.On("nameCard") then return end
	local who = ns.ParsePlayerLink(link)
	if not who then return end
	overLink = true
	pending = who
	C_Timer.After(DELAY, function()
		-- (still this name under the mouse, the mouse not gone onto the card)
		if pending ~= who or not overLink then return end
		pending = nil
		Open(who)
	end)
end

local function OnLinkLeave()
	overLink = false
	pending = nil
end
ns.NameCard = function() return card end -- (tests)

-- A plain left click on a name, the private messages window on (and no other addon keeping the whispers): your
-- conversation with them in it, its line to answer taken. The game has opened its whisper line already, on the
-- same click: the window's line takes the keys from it, and the game puts its own line away as it always does.
function ns.NameClicked(link, button)
	if button ~= "LeftButton" or IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() or not ns.On("messagesWindow") or ns.Yields("whispers") then return end
	if type(link) ~= "string" or U.IsSecret(link) then return end
	Hide()
	local bnID = link:match("^BNplayer:[^:]*:(%d+)")
	if bnID then return ns.ToggleMessages("BN:" .. bnID, true) end
	local who = ns.ParsePlayerLink(link)
	if not who or who.name == ns.Me() then return end
	ns.ToggleMessages(who.full, true)
end

-- The chat's windows, each once (the temporary ones of whispers too, and any window given: the hidden lines').
local hooked = setmetatable({}, { __mode = "k" })
function ns.WatchNames(frame)
	if type(frame) ~= "table" or hooked[frame] or not frame.HookScript then return end
	hooked[frame] = true
	pcall(frame.HookScript, frame, "OnHyperlinkEnter", OnLinkEnter)
	pcall(frame.HookScript, frame, "OnHyperlinkLeave", OnLinkLeave)
	pcall(frame.HookScript, frame, "OnHyperlinkClick", function(_, link, _, button) ns.NameClicked(link, button) end)
end

local function WatchChatFrames()
	for index = 1, NUM_CHAT_WINDOWS or 10 do ns.WatchNames(_G["ChatFrame" .. index]) end
	for _, name in ipairs(type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}) do ns.WatchNames(_G[name]) end
end

-- The game's menu of a name in the chat -------------------------------------------------------------------------------

local function Used() ns.DB().repliesUsed = true end

local function MenuEntries(_, root, context)
	if not (ns.On("replies") and type(context) == "table" and root and root.CreateButton) then return end
	-- (from a chat line only: the friends list opens this menu too)
	local name, chatType, lineID = Clean(context.name), Clean(context.chatType), Clean(context.lineID)
	if type(name) ~= "string" or not (chatType or lineID) then return end
	local server = Clean(context.server)
	local full = (server and not name:find("-", 1, true)) and (name .. "-" .. server) or name
	local who = { full = full, name = ns.Who(full) or name, chatType = chatType, lineID = tonumber(lineID) }
	if who.name == ns.Me() then return end
	if root.CreateDivider then root:CreateDivider() end
	root:CreateButton(L.REPLY_GREET:format(who.name), function() Used() ns.GreetPerson(who) end)
	root:CreateButton(L.REPLY_TO:format(who.name), function() Used() ns.ReplyPerson(who) end)
	if ns.LineByID(who.lineID) then
		root:CreateButton(L.REPLY_QUOTE, function() Used() ns.QuotePerson(who) end)
		root:CreateButton(L.REPLY_COPY, function() ns.CopyLine(who) end)
	end
end
ns.ReplyMenuEntries = MenuEntries -- (tests)

-- Into the game's menu once it has one (Menu.ModifyMenu); nothing else is touched.
function ns.HookReplyMenus()
	if menuHooked or not (Menu and Menu.ModifyMenu) then return menuHooked end
	for _, tag in ipairs(MENU_TAGS) do
		if pcall(Menu.ModifyMenu, tag, MenuEntries) then menuHooked = true end
	end
	return menuHooked
end

-- Start --------------------------------------------------------------------------------------------------------------

function ns.InitSocial()
	ns.Heard.On(Keep)
	WatchChatFrames()
	if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", WatchChatFrames) end
	ns.HookReplyMenus()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "UPDATE_CHAT_WINDOWS" }) do events:RegisterEvent(event) end
	events:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_CHAT_WINDOWS" then return WatchChatFrames() end
		if not ns.On("nameCard") then return end
		Meet(event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover")
	end)
end
