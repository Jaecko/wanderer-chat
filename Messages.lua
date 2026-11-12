local _, ns = ...
local L = ns.L

-- Private messages in their own window, in Wanderer's look: the people you
-- whisper with on the left, the conversation on the right, a line to answer
-- at the bottom. Whispers (and Battle.net whispers) leave the chat for it.
-- The conversation reads as a thread of bubbles drawn with the game's own
-- tooltip frame: theirs on the left, yours on the right in gold, the hour
-- between moments apart.
--
-- A new message opens the window without taking the keyboard, never during a
-- fight or a conversation scene: then the minimap menu counts the unread
-- ones. History is kept per character (Battle.net ones for the session only:
-- the game renews their ids). Events only, besides a light watch (twice a
-- second, while the window is on) that keeps the chat's whisper button in step
-- with the social button.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local WIDTH, HEIGHT = 620, 360
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 520, 280, 1100, 900 -- resized by its corner
local LIST_WIDTH = 208 -- a whole name fits (twelve letters, the game's longest)
local ROW_HEIGHT = 40 -- the name, then a quiet line under it
local INFO_LINES = 3 -- room kept under the conversation's name for who they are
local MAX_LINES = 200 -- kept per person
local MAX_PEOPLE = 40
local ECHO_WAIT = 60 -- seconds: the game's confirmation of a message, recognised within this time
local sessionStart = GetTime and GetTime() or 0 -- (an echo marked before a reload means nothing after it)
local EVENTS = { -- event -> who wrote it
	CHAT_MSG_WHISPER = "them", CHAT_MSG_WHISPER_INFORM = "me",
	CHAT_MSG_BN_WHISPER = "them", CHAT_MSG_BN_WHISPER_INFORM = "me",
}

local window, list, thread, input, header, info, portrait, person
local PORTRAIT, ROW_PORTRAIT = 40, 28
local CLASSES_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
-- The game's race names that its icons spell differently.
local RACE_ICONS = { Scourge = "undead", NightElf = "nightelf", BloodElf = "bloodelf", HighmountainTauren = "highmountain",
	LightforgedDraenei = "lightforged", VoidElf = "voidelf", ZandalariTroll = "zandalari", KulTiran = "kultiran",
	DarkIronDwarf = "darkirondwarf", MagharOrc = "magharorc", Nightborne = "nightborne" }
local rows = {}
local current -- key of the conversation shown
local session = {} -- Battle.net conversations (not saved)

-- Data -----------------------------------------------------------------------------------

-- A Battle.net conversation (kept for the session only).
local function IsBattleNet(key) return key:sub(1, 3) == "BN:" end

local function Store()
	local db = ns.DB()
	db.messages = type(db.messages) == "table" and db.messages or {}
	return db.messages
end

local function Conversation(key)
	if IsBattleNet(key) then
		session[key] = session[key] or { lines = {}, unread = 0, last = 0 }
		return session[key]
	end
	local store = Store()
	store[key] = store[key] or { lines = {}, unread = 0, last = 0 }
	return store[key]
end

local function AllConversations()
	local all = {}
	for key, talk in pairs(Store()) do all[#all + 1] = { key = key, talk = talk } end
	for key, talk in pairs(session) do all[#all + 1] = { key = key, talk = talk } end
	-- Pinned people first, then the most recent.
	table.sort(all, function(a, b)
		if (a.talk.pinned and true or false) ~= (b.talk.pinned and true or false) then return a.talk.pinned and true or false end
		return (a.talk.last or 0) > (b.talk.last or 0)
	end)
	return all
end

-- The oldest people go when there are too many.
local function Trim()
	local all = AllConversations()
	for index = MAX_PEOPLE + 1, #all do
		local key = all[index].key
		if not all[index].talk.pinned then -- a pinned conversation is never forgotten
			if IsBattleNet(key) then session[key] = nil else Store()[key] = nil end
		end
	end
end

-- Whether you wrote to someone (their full name): no stranger then.
function ns.WroteTo(key)
	local talk = type(key) == "string" and Store()[key]
	for _, entry in ipairs(talk and talk.lines or {}) do
		if entry.me then return true end
	end
	return false
end

-- (asked often: counted without sorting)
function ns.UnreadMessages()
	local count = 0
	for _, talk in pairs(Store()) do count = count + (talk.unread or 0) end
	for _, talk in pairs(session) do count = count + (talk.unread or 0) end
	return count
end

-- The counts of what is unread, wherever they are shown (the chat's button, Wanderer's menu and bar).
local function Launchers()
	ns.RefreshChatWhisperButton()
	W.RefreshLaunchers()
end

-- Times, as the player's game writes them ---------------------------------------------------
-- The hour in the game's clock (12 or 24 hours, as chosen), the day in the client's order.

local function Today(t) return date("%Y%m%d") == date("%Y%m%d", t) end

local function Hour(t)
	if _G.GameTime_GetFormattedTime then
		local ok, text = pcall(_G.GameTime_GetFormattedTime, tonumber(date("%H", t)), tonumber(date("%M", t)), true)
		if ok and type(text) == "string" then return text end
	end
	return date("%H:%M", t)
end

local function Day(t)
	if _G.FormatShortDate then
		local ok, text = pcall(_G.FormatShortDate, tonumber(date("%d", t)), tonumber(date("%m", t)))
		if ok and type(text) == "string" then return text end
	end
	return date("%d/%m", t)
end

-- Portraits ---------------------------------------------------------------------------------
-- The real one when the person is around (target, group, nearby with a
-- nameplate); else the portrait of their race and gender as the game knows
-- them; else their class.

local UNITS = { "target", "focus", "mouseover" }
for index = 1, 4 do UNITS[#UNITS + 1] = "party" .. index end
for index = 1, 40 do UNITS[#UNITS + 1] = "raid" .. index end

-- guid -> unit, read in one pass over the units around (for a whole list drawn at once: ns.RefreshMessages).
local unitOf
local function AroundUnits()
	local found = {}
	for _, unit in ipairs(UNITS) do
		local guid = Clean(Safe(UnitGUID, unit))
		if guid and not found[guid] then found[guid] = unit end
	end
	for _, plate in ipairs(C_NamePlate and Safe(C_NamePlate.GetNamePlates) or {}) do
		local unit = U.PlateUnit(plate)
		local guid = unit and Clean(Safe(UnitGUID, unit))
		if guid and not found[guid] then found[guid] = unit end
	end
	return found
end

local function UnitFor(guid)
	if not guid then return end
	return (unitOf or AroundUnits())[guid]
end

local function SetPortrait(texture, talk)
	texture:SetTexCoord(0, 1, 0, 1)
	local unit = UnitFor(talk.guid)
	if unit and SetPortraitTexture then
		Safe(SetPortraitTexture, texture, unit)
		return true
	end
	if talk.race then
		local race = RACE_ICONS[talk.race] or talk.race:lower()
		local gender = talk.sex == 3 and "female" or "male"
		for _, atlas in ipairs({ "raceicon128-" .. race .. "-" .. gender, "raceicon-" .. race .. "-" .. gender }) do
			if U.HasAtlas(atlas) then
				texture:SetAtlas(atlas)
				return true
			end
		end
	end
	-- The class's own icon, from the game's atlas or its sheet of classes.
	local classAtlas = talk.class and "classicon-" .. tostring(talk.class):lower()
	if classAtlas and U.HasAtlas(classAtlas) then
		texture:SetAtlas(classAtlas)
		return true
	end
	local coords = talk.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[talk.class]
	if coords then
		texture:SetTexture(CLASSES_TEXTURE)
		texture:SetTexCoord(unpack(coords))
		return true
	end
	return false
end

-- A round portrait that always shows someone: else their initial in gold on a quiet ground.
local PLACEHOLDER = { 0.16, 0.14, 0.11 }
local function Portrait(owner, size)
	local texture = Skin.RoundPortrait(owner, size)
	texture.initial = Skin.Text(owner, size >= 36 and "GameTooltipHeaderText" or "GameTooltipText", "gold")
	texture.initial:SetPoint("CENTER", texture, "CENTER", 1, 0)
	texture.initial:SetJustifyH("CENTER")
	texture.initial:Hide()
	return texture
end

-- The first letter of a name (a letter of any language), in capitals.
local function Initial(name)
	local first = type(name) == "string" and name:match("^[%z\1-\127\194-\244][\128-\191]*") or nil
	return first and U.Upper(first) or "?"
end

local function ShowPortrait(texture, talk)
	local real = talk and SetPortrait(texture, talk) or false
	if talk and not real then
		texture:SetTexCoord(0, 1, 0, 1)
		texture:SetColorTexture(PLACEHOLDER[1], PLACEHOLDER[2], PLACEHOLDER[3], 1)
	end
	texture:SetShown(talk ~= nil)
	texture.ring:SetShown(talk ~= nil and texture.ringShown or false)
	texture.initial:SetText(Initial(talk and talk.name))
	texture.initial:SetShown(talk ~= nil and not real)
end

-- A class's color (the kit's text color when unknown), and as a text code.
local function ClassRGB(class)
	local r, g, b = U.ClassColor(class)
	if r then return r, g, b end
	local c = Skin.COLORS.text
	return c[1], c[2], c[3]
end
local function Hex(class)
	return U.ColorCode(ClassRGB(class))
end

-- Who they are ------------------------------------------------------------------------------
-- What the chat's name card knows (Social.lua: your group, friends, guild, the
-- players met, your characters), the person near you now, a /who you asked
-- for; else race and class from the message itself. Kept with the
-- conversation, with the time it was true.

local WHO_WAIT = 6 -- seconds before a /who without answer counts as "not found"
local WHO_MISS_SHOWN = 30 -- seconds the "not found" stays
local function Friends(name) return ns.FriendList(name) end -- (Social.lua, loaded after)

local function Short(talk, key)
	return talk.name or (Ambiguate and Clean(Safe(Ambiguate, key, "short"))) or key
end

local function SameName(name, key, short)
	return name == key or (Ambiguate and Safe(Ambiguate, name, "short")) == short
end

local KNOWN = { "level", "class", "className", "raceName", "zone", "guild", "rank", "away" }
local function Learn(talk, key)
	if IsBattleNet(key) then return end
	if talk.seen then talk.seenAt, talk.seen = talk.seenAt or talk.seen, nil end -- (its older name)
	local known = ns.PersonInfo(key, talk.guid)
	for _, field in ipairs(KNOWN) do
		if known[field] ~= nil then talk[field] = known[field] end
	end
	talk.friend = known.friend or nil
	if known.online ~= nil then talk.online = known.online end
	if known.online then talk.seenAt = time() elseif known.seenAt then talk.seenAt = known.seenAt end
	-- Near you now (a nameplate, your target): here, and online.
	local unit = UnitFor(talk.guid)
	if unit then
		talk.level = Clean(Safe(UnitLevel, unit)) or talk.level
		talk.zone = Clean(Safe(GetRealZoneText)) or talk.zone
		talk.online, talk.seenAt = true, time()
	end
end

-- "Level 60 Human Warrior · <Guild> · Officer", then "Ironforge · Online · Friend".
local function InfoLine(talk, key)
	if IsBattleNet(key) then return "" end
	local status
	if talk.looking then
		status = Skin.Colorize(L.MESSAGES_WHO_WAIT, "muted")
	elseif talk.whoMiss and time() - talk.whoMiss < WHO_MISS_SHOWN then
		status = Skin.Colorize(L.MESSAGES_WHO_NONE, "muted")
	end
	local who, where, guild = ns.PersonLines(talk, { classColor = true, status = status })
	-- Who they are on the first line, where and how they are on the second.
	local identity = (who and guild) and (who .. U.SEPARATOR .. guild) or who or guild or ""
	local state = where or ""
	if talk.friend then state = (state ~= "" and state .. U.SEPARATOR or "") .. Skin.Colorize(L.RELATION_FRIEND, "blue") end
	if identity ~= "" and state ~= "" then return identity .. "\n" .. state end
	return identity .. state
end

local function RefreshHeader()
	if not (current and info) then return end
	info:SetText(InfoLine(Conversation(current), current))
end

-- /who on someone, asked from the menu: the answer fills their information.
local whoFor, friendsOpen

local function AskWho(key)
	local send = Friends("SendWho")
	if not send then return end
	local talk = Conversation(key)
	whoFor = key
	friendsOpen = FriendsFrame and FriendsFrame:IsShown()
	Safe(Friends("SetWhoToUi"), true)
	talk.looking, talk.whoMiss = true, nil
	Safe(send, ('n-"%s"'):format(Short(talk, key)))
	RefreshHeader()
	C_Timer.After(WHO_WAIT, function()
		if whoFor ~= key then return end
		whoFor = nil
		Safe(Friends("SetWhoToUi"), false)
		talk.looking, talk.whoMiss = nil, time()
		RefreshHeader()
	end)
end

local function OnWho()
	if not whoFor then return end
	local key, talk = whoFor, Conversation(whoFor)
	local short = Short(talk, key)
	local found = false
	for index = 1, Clean(Safe(Friends("GetNumWhoResults"))) or 0 do
		local entry = Safe(Friends("GetWhoInfo"), index)
		local name = type(entry) == "table" and Clean(entry.fullName)
		if name and SameName(name, key, short) then
			talk.level = Clean(entry.level) or talk.level
			talk.raceName = Clean(entry.raceStr) or talk.raceName
			talk.className = Clean(entry.classStr) or talk.className
			talk.class = Clean(entry.filename) or talk.class
			talk.guild = Clean(entry.fullGuildName)
			talk.zone = Clean(entry.area) or talk.zone
			talk.online, talk.seenAt = true, time()
			found = true
			break
		end
	end
	whoFor = nil
	-- Your own /who afterwards answers in the chat, as the game does.
	Safe(Friends("SetWhoToUi"), false)
	talk.looking = nil
	if not found then talk.whoMiss = time() end
	-- The game's list may open for the answer: closed again if it was closed.
	if FriendsFrame and FriendsFrame:IsShown() and not friendsOpen and not InCombatLockdown() then FriendsFrame:Hide() end
	RefreshHeader()
end

-- What can be done with someone: the game's own actions, in the card of a person.
local function PersonActions(actions, key, talk)
	if IsBattleNet(key) then return end
	local short = Short(talk, key)
	actions[#actions + 1] = { text = L.MESSAGES_WHO, glyph = "chevron", onClick = function() AskWho(key) end }
	actions[#actions + 1] = { text = L.MESSAGES_INVITE, glyph = "plus", onClick = function()
		Safe(C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit, key)
	end }
	if Safe(Friends("GetFriendInfo"), short) then
		actions[#actions + 1] = { text = L.MESSAGES_REMOVE_FRIEND, glyph = "close", onClick = function() Safe(Friends("RemoveFriend"), short) end }
	else
		actions[#actions + 1] = { text = L.MESSAGES_ADD_FRIEND, glyph = "star", onClick = function() Safe(Friends("AddFriend"), key) end }
	end
	if Clean(Safe(Friends("IsIgnored"), key)) then
		actions[#actions + 1] = { text = L.MESSAGES_UNIGNORE, glyph = "back", onClick = function() Safe(Friends("DelIgnore"), key) end }
	else
		actions[#actions + 1] = { text = L.MESSAGES_IGNORE, glyph = "eyeoff", onClick = function() Safe(Friends("AddIgnore"), key) end }
	end
end

-- Window -----------------------------------------------------------------------------------

local function NameOf(talk, key)
	return Hex(talk.class) .. (talk.name or key) .. "|r"
end

-- The thread of bubbles -----------------------------------------------------------------------

local BUBBLE_SHARE = 0.72 -- of the thread's width, at most
local BUBBLE_PAD_X, BUBBLE_PAD_Y = 10, 7
local SAME_GAP, OTHER_GAP = 3, 10 -- between bubbles of the same person, between two people
local TOGETHER = 180 -- seconds: closer messages of one person stay together
local APART = 900 -- seconds: the hour is written between moments further apart
local SCROLL_STEP = 40
local SENDING_ALPHA = 0.65 -- your message until the game confirms it
local BUBBLE_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BUBBLE_LOOK = {
	them = { bg = { 0.05, 0.05, 0.07, 0.88 }, edge = { 0.55, 0.55, 0.6, 0.9 }, text = { 0.95, 0.93, 0.88 } },
	me = { bg = { 0.2, 0.14, 0.04, 0.88 }, edge = { Skin.COLORS.gold[1], Skin.COLORS.gold[2], Skin.COLORS.gold[3], 0.75 },
		text = Skin.COLORS.onGold or { 1, 0.96, 0.84 } },
}

-- How bright a color looks to the eye (the relative luminance of the web's contrast rules).
local function Luminance(r, g, b)
	local function Linear(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * Linear(r) + 0.7152 * Linear(g) + 0.0722 * Linear(b)
end

-- A side's look: the window's own, or built on the color chosen for it (its
-- border lighter, its text dark or light, whichever stands out more on it).
local function Look(me)
	local colors = ns.DB().colors
	local chosen = type(colors) == "table" and colors[me and "me" or "them"]
	if type(chosen) ~= "table" then return me and BUBBLE_LOOK.me or BUBBLE_LOOK.them end
	local r, g, b = chosen[1] or 0, chosen[2] or 0, chosen[3] or 0
	-- (dark text wins above a luminance near 0.18: (L + 0.05) / 0.05 against 1.05 / (L + 0.05))
	local light = Luminance(r, g, b) > 0.18
	return { bg = { r, g, b, 0.9 }, edge = { (r + 1) / 2, (g + 1) / 2, (b + 1) / 2, 0.9 },
		text = light and { 0.08, 0.08, 0.08 } or { 0.97, 0.95, 0.9 } }
end

-- The color of a side, to choose (the window's own when none was chosen).
function ns.MessageColor(side)
	local colors = ns.DB().colors
	local chosen = type(colors) == "table" and colors[side]
	if type(chosen) == "table" then return chosen[1], chosen[2], chosen[3] end
	local bg = BUBBLE_LOOK[side].bg
	return bg[1], bg[2], bg[3]
end

-- side: "me" or "them"; nil color: the window's own again (both sides when side is nil).
function ns.SetMessageColor(side, r, g, b)
	local db = ns.DB()
	db.colors = type(db.colors) == "table" and db.colors or {}
	if side then
		db.colors[side] = r and { r, g, b } or nil
	else
		db.colors = nil
	end
	if window and window:IsShown() then ns.RedrawMessages() end
end

local bubbles, stamps = {}, {} -- pools
local used = { bubbles = 0, stamps = 0, height = 0 }
local lastShown -- the entry shown last (its time and its author)
local bubbleOf = setmetatable({}, { __mode = "k" }) -- entry -> its bubble

local function ThreadWidth()
	return math.max(120, (thread.width or 300))
end

local function Bubble()
	used.bubbles = used.bubbles + 1
	local bubble = bubbles[used.bubbles]
	if bubble then return bubble end
	bubble = CreateFrame("Frame", nil, thread.content, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if bubble.SetBackdrop then bubble:SetBackdrop(BUBBLE_BACKDROP) end
	bubble.text = bubble:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	bubble.text:SetJustifyH("LEFT")
	if bubble.text.SetWordWrap then bubble.text:SetWordWrap(true) end
	bubble.text:SetPoint("TOPLEFT", bubble, "TOPLEFT", BUBBLE_PAD_X, -BUBBLE_PAD_Y)
	-- Item and quest links stay clickable; the hour shows under the mouse.
	if bubble.SetHyperlinksEnabled then pcall(bubble.SetHyperlinksEnabled, bubble, true) end
	bubble:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
	bubble:EnableMouse(true)
	bubble.padTip = true -- (a controller reaches it too: its hour, and the stick scrolls the thread from there)
	bubble:SetScript("OnEnter", function(self)
		if not self.entry then return end
		local t = self.entry.t or time()
		local soft = Skin.COLORS.soft
		Skin.ShowTip(self, { { Day(t) .. " " .. Hour(t), soft[1], soft[2], soft[3] } }, self.entry.me and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
	end)
	bubble:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bubbles[used.bubbles] = bubble
	return bubble
end

local function Stamp()
	used.stamps = used.stamps + 1
	local stamp = stamps[used.stamps]
	if not stamp then
		stamp = Skin.Text(thread.content, "GameTooltipTextSmall", "muted")
		stamp:SetJustifyH("CENTER")
		stamps[used.stamps] = stamp
	end
	return stamp
end

local function ClearThread()
	for index = 1, used.bubbles do bubbles[index]:Hide() bubbles[index].entry = nil end
	for index = 1, used.stamps do stamps[index]:Hide() end
	used.bubbles, used.stamps, used.height = 0, 0, 0
	lastShown = nil
	if window.emptyThread then window.emptyThread:Hide() end
	thread.content:SetHeight(1)
	thread:SetVerticalScroll(0)
end

local function ScrollToEnd()
	local range = math.max(0, used.height - (thread:GetHeight() or 0))
	thread:SetVerticalScroll(range)
end

-- One message as a bubble, under the others.
local function AddBubble(entry, secretText)
	local width = ThreadWidth()
	local t = entry.t or time()
	-- The hour, between moments apart (and before the first one).
	if not lastShown or t - (lastShown.t or 0) > APART then
		local stamp = Stamp()
		stamp:SetText(Today(t) and Hour(t) or Day(t) .. " " .. Hour(t))
		stamp:ClearAllPoints()
		used.height = used.height + (lastShown and OTHER_GAP or 2)
		stamp:SetPoint("TOP", thread.content, "TOP", 0, -used.height)
		stamp:SetWidth(width)
		stamp:Show()
		used.height = used.height + 12
		lastShown = nil
	end
	local together = lastShown and (lastShown.me and true or false) == (entry.me and true or false)
		and t - (lastShown.t or 0) <= TOGETHER
	used.height = used.height + (lastShown and (together and SAME_GAP or OTHER_GAP) or 4)
	local bubble = Bubble()
	if window.emptyThread then window.emptyThread:Hide() end
	local look = Look(entry.me)
	if bubble.SetBackdropColor then
		bubble:SetBackdropColor(look.bg[1], look.bg[2], look.bg[3], look.bg[4])
		bubble:SetBackdropBorderColor(look.edge[1], look.edge[2], look.edge[3], look.edge[4])
	end
	local text = bubble.text
	local color = entry.fight and Skin.COLORS.muted or look.text
	text:SetTextColor(color[1], color[2], color[3])
	local most = math.floor(width * BUBBLE_SHARE) - BUBBLE_PAD_X * 2
	text:SetWidth(most)
	local words = secretText or entry.text or (entry.fight and L.MESSAGES_IN_FIGHT) or ""
	if not pcall(text.SetText, text, words) then text:SetText("") end
	local natural = U.Measure(text, "GetStringWidth", most)
	local textWidth = math.min(most, math.ceil(natural) + 1)
	text:SetWidth(textWidth)
	local textHeight = U.Measure(text, "GetStringHeight", 14)
	bubble:SetSize(textWidth + BUBBLE_PAD_X * 2, textHeight + BUBBLE_PAD_Y * 2)
	bubble:ClearAllPoints()
	if entry.me then
		bubble:SetPoint("TOPRIGHT", thread.content, "TOPRIGHT", -2, -used.height)
	else
		bubble:SetPoint("TOPLEFT", thread.content, "TOPLEFT", 2, -used.height)
	end
	-- Yours waits, a little faded, for the game to confirm it.
	local waiting = entry.echo and GetTime() - entry.echo >= 0 and GetTime() - entry.echo <= ECHO_WAIT
	bubble:SetAlpha(waiting and SENDING_ALPHA or 1)
	bubble.entry = entry
	bubbleOf[entry] = bubble
	bubble:Show()
	used.height = used.height + textHeight + BUBBLE_PAD_Y * 2
	thread.content:SetHeight(math.max(1, used.height + 4))
	lastShown = entry
	ScrollToEnd()
end

local function ShowConversation(key)
	current = key
	local talk = Conversation(key)
	-- (its draft back in the line, as left: the line untouched when it holds it already)
	local draft = talk.draft or ""
	if (input:GetText() or "") ~= draft then input:SetText(draft) end
	talk.unread = 0
	ClearThread()
	for _, entry in ipairs(talk.lines) do AddBubble(entry) end
	window.emptyThread:SetShown(used.bubbles == 0)
	header:SetText(NameOf(talk, key))
	Learn(talk, key)
	info:SetText(InfoLine(talk, key))
	person:SetShown(not IsBattleNet(key))
	ShowPortrait(portrait, talk)
	input:Show()
	ns.RefreshMessages()
end

local function Forget(key)
	if IsBattleNet(key) then session[key] = nil else Store()[key] = nil end
	if current == key then current = nil end
	ns.RefreshMessages()
end

-- The card of a person, the same everywhere (their row, its "..." button, the conversation's own button and its
-- name), near the mouse: pin, mark as read, the game's own actions, then delete (asked first).
local function OpenMenu(owner, key)
	if not key then return end
	local talk = Conversation(key)
	local actions = {}
	actions[#actions + 1] = { text = talk.pinned and L.MESSAGES_UNPIN or L.MESSAGES_PIN, glyph = "star", onClick = function()
		talk.pinned = not talk.pinned or nil
		ns.RefreshMessages()
	end }
	if (talk.unread or 0) > 0 then
		actions[#actions + 1] = { text = L.MESSAGES_MARK_READ, glyph = "bell", onClick = function()
			talk.unread = 0
			ns.RefreshMessages()
		end }
	end
	PersonActions(actions, key, talk)
	-- (the one thing that cannot be undone: asked first)
	actions[#actions + 1] = { text = L.MESSAGES_DELETE, glyph = "close", role = "bad", onClick = function()
		Skin.Ask(L.MESSAGES_DELETE_ASK:format(NameOf(talk, key)), function() Forget(key) end)
	end }
	return Skin.ActionCard(owner, { title = talk.name or key, rows = actions, atCursor = true })
end

-- A tooltip beside its owner (by default at its right, level with it): never far
-- from what the mouse is on, never over the conversation's name.
local function ShowTip(owner, lines, point, relative, x, y)
	if not (lines and lines[1]) then return end
	-- (the kit's tooltip: its first line white here, the others soft)
	local soft, colored = Skin.COLORS.soft, {}
	for index, line in ipairs(lines) do
		colored[index] = index == 1 and { line, 1, 1, 1 } or { line, soft[1], soft[2], soft[3] }
	end
	if Skin.ShowTip(owner, colored, "ANCHOR_NONE") == false then return end
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint(point or "LEFT", owner, relative or "RIGHT", x or 8, y or 0)
end

-- The kit's quiet "..." button, shown and hidden here (on the row shown, under the mouse); below: its tooltip
-- under it.
-- (tip: its own words, read by a kit that knows opts.tip; an older one keeps the row's)
local function MoreButton(parent, onClick, below, tip)
	local more
	more = Skin.RowMore(parent, function() onClick(more) end, nil, nil, { manual = true, below = below, tip = tip })
	more:ClearAllPoints()
	return more
end

-- A row of the list: the gold edge of the one shown, its portrait, the whole
-- name in its class color, a quiet line under it (the hour and the last words),
-- what is unread in a gold chip, a pin. Its own column at the right for the
-- "..." button (under the mouse and on the row shown): it never covers the name.
local ROW_PAD = 8
local EDGE_WIDTH = 2
local TEXT_LEFT = ROW_PAD + ROW_PORTRAIT + ROW_PAD
local MORE_COLUMN = Skin and rawget(Skin, "ROW_MORE") or 26 -- (the kit's "..." column, Skin.ROW_MORE: read only once Wanderer is known recent enough)
local NAME_ROOM = LIST_WIDTH - TEXT_LEFT - MORE_COLUMN - 4

-- Its look, as it is now: shown, under the mouse, or neither.
local function Paint(row)
	local selected = row.key ~= nil and row.key == current
	local hovered = (U.Hovered and U.Hovered(row) or row:IsMouseOver()) or (U.Hovered and U.Hovered(row.more) or row.more:IsMouseOver())
	if selected then
		local gold = Skin.COLORS.gold
		row.background:SetColorTexture(gold[1], gold[2], gold[3], (Skin.CHOSEN or 0.1) + (hovered and (Skin.HOVER or 0.05) or 0))
	else
		row.background:SetColorTexture(1, 1, 1, hovered and (Skin.HOVER or 0.05) or 0)
	end
	row.edge:SetShown(selected)
	row.more:SetShown(selected or hovered)
end

-- The name, whole: a smaller letter when it is long, the tooltip for a name longer still.
local NAME_FONT, NAME_SMALL_FONT
local function SetName(row, talk, key)
	NAME_FONT = NAME_FONT or Skin.FontFor("GameTooltipText")
	NAME_SMALL_FONT = NAME_SMALL_FONT or Skin.FontFor("GameTooltipTextSmall")
	local name = talk.name or key
	local text = row.name
	if text.SetFontObject then text:SetFontObject(NAME_FONT) end
	text:SetText(name)
	row.cut = false
	if U.Measure(text, "GetStringWidth", 0) > NAME_ROOM and text.SetFontObject then
		text:SetFontObject(NAME_SMALL_FONT)
		row.cut = U.Measure(text, "GetStringWidth", 0) > NAME_ROOM
	end
	text:SetTextColor(ClassRGB(talk.class))
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.9)
end

-- The quiet line: the hour of the last message (the day when not today), its
-- words; with no message kept, who they are (level, class, zone), else so. Your words not sent yet first.
local function Excerpt(talk)
	if talk.draft then return Skin.Colorize(L.MESSAGES_DRAFT, "gold") .. " " .. (talk.draft:gsub("[\r\n]+", " ")) end
	local entry = talk.lines and talk.lines[#talk.lines]
	if not entry then
		local parts = {}
		if talk.level then parts[#parts + 1] = LEVEL .. " " .. talk.level end
		if talk.className then parts[#parts + 1] = talk.className end
		if talk.zone then parts[#parts + 1] = talk.zone end
		return parts[1] and table.concat(parts, " ") or L.MESSAGES_NO_LINES
	end
	local t = entry.t or time()
	local when = Today(t) and Hour(t) or Day(t)
	local words = entry.fight and L.MESSAGES_IN_FIGHT or type(entry.text) == "string" and entry.text:gsub("[\r\n]+", " ") or ""
	if entry.me then words = L.MESSAGES_FROM_YOU:format(words) end
	return when .. "  " .. words
end

local function RowFor(index)
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, list)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp") row.padRight = true
	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()
	row.edge = row:CreateTexture(nil, "ARTWORK")
	row.edge:SetWidth(EDGE_WIDTH)
	row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.edge:SetColorTexture(Skin.COLORS.gold[1], Skin.COLORS.gold[2], Skin.COLORS.gold[3], 0.9)
	row.portrait = Portrait(row, ROW_PORTRAIT)
	row.portrait:SetPoint("LEFT", row, "LEFT", ROW_PAD, 0)
	-- The "..." button, in its own column.
	row.more = MoreButton(row, function() if row.key then OpenMenu(row.more, row.key) end end)
	row.more:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.more:SetFrameLevel(row:GetFrameLevel() + 2)
	row.more:HookScript("OnEnter", function() Paint(row) end)
	row.more:HookScript("OnLeave", function() Paint(row) end)
	row.more:Hide()
	row.name = Skin.CreateText(row, "GameTooltipText")
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -6)
	row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -MORE_COLUMN - 4, -6)
	if row.name.SetWordWrap then row.name:SetWordWrap(false) end
	-- Under the name: what is unread (a gold chip), the pin, the last words.
	row.unread = Skin.Chip(row)
	row.unread:SetHeight(14)
	row.unread:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -MORE_COLUMN - 4, 5)
	row.pin = row:CreateTexture(nil, "ARTWORK")
	row.pin:SetSize(12, 12)
	local atlasOk, applied = false, false
	if row.pin.SetAtlas then atlasOk, applied = pcall(row.pin.SetAtlas, row.pin, "PetJournal-FavoritesIcon") end
	if not atlasOk or applied == false then
		row.pin:SetTexture("Interface\\Common\\FavoritesIcon")
	end
	row.line = Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TEXT_LEFT, 7)
	if row.line.SetWordWrap then row.line:SetWordWrap(false) end
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenMenu(self, self.key)
		else
			Skin.Play("click")
			ShowConversation(self.key)
		end
	end)
	row:HookScript("OnEnter", function(self) Paint(self) end)
	row:HookScript("OnLeave", function(self) Paint(self) end)
	-- Beside the row: who they are, and the whole name when it had to be cut.
	row:HookScript("OnEnter", function(self)
		if not self.key then return end
		local talk = Conversation(self.key)
		local lines = { NameOf(talk, self.key) }
		for part in InfoLine(talk, self.key):gmatch("[^\n]+") do lines[#lines + 1] = part end
		if lines[2] or self.cut then ShowTip(self, lines) end
	end)
	row:HookScript("OnLeave", function() GameTooltip:Hide() end)
	rows[index] = row
	return row
end

-- A row given its person: name, quiet line, unread, pin, look.
local function FillRow(row, entry)
	local talk = entry.talk
	row.key = entry.key
	SetName(row, talk, entry.key)
	ShowPortrait(row.portrait, talk)
	local unread = talk.unread or 0
	row.unread:Set(unread > 0 and (unread > 99 and "99+" or tostring(unread)) or nil, "gold")
	row.pin:SetShown(talk.pinned and true or false)
	-- Right to left before the "..." column: the chip, the pin, then the quiet line up to them.
	local reserve = MORE_COLUMN + 4
	if row.unread:IsShown() then reserve = reserve + row.unread:GetWidth() + 4 end
	row.pin:ClearAllPoints()
	row.pin:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -reserve, 6)
	if row.pin:IsShown() then reserve = reserve + 12 + 4 end
	row.line:ClearAllPoints()
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", TEXT_LEFT, 7)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -reserve - 2, 7)
	row.line:SetText(Excerpt(talk))
	Paint(row)
end

-- The search over the people: their name or a word of the conversation.
local SEARCH_HEIGHT = 28 -- the search, then 8 pixels
-- (folded on both sides: accents and capitals aside, "foret" finds "Forêt")
local Fold = U.Fold or U.Upper
local function Matches(entry, query)
	if query == "" then return true end
	local name = (entry.talk.name or entry.key)
	if type(name) == "string" and Fold(name):find(query, 1, true) then return true end
	for _, line in ipairs(entry.talk.lines or {}) do
		if type(line.text) == "string" and Fold(line.text):find(query, 1, true) then return true end
	end
	return false
end

function ns.RefreshMessages()
	if not (window and window:IsShown()) then return end
	local query = Fold(strtrim(window.search and window.search:GetText() or ""))
	local all = {}
	for _, entry in ipairs(AllConversations()) do
		if Matches(entry, query) then all[#all + 1] = entry end
	end
	unitOf = AroundUnits() -- (the units around read once for every row's portrait)
	for index, entry in ipairs(all) do
		local row = RowFor(index)
		FillRow(row, entry)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -SEARCH_HEIGHT - (index - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		row:Show()
	end
	unitOf = nil
	for index = #all + 1, #rows do
		rows[index].key = nil
		rows[index]:Hide()
	end
	window.options:SetShown(current ~= nil)
	Launchers()
	window.empty:SetText(query ~= "" and L.MESSAGES_NO_MATCH or L.MESSAGES_EMPTY)
	window.empty:SetShown(not all[1])
	if not current then
		header:SetText(L.MESSAGES_TITLE)
		info:SetText("")
		person:Hide()
		ShowPortrait(portrait, nil)
		ClearThread()
		input:Hide()
	end
end

-- Your message in the window at once, as you send it: never waiting for the
-- game's confirmation (it may come late, or not reach the addons at all).
local function Echo(key, text)
	local talk = Conversation(key)
	local entry = { t = time(), me = true, from = talk.name, text = text, echo = GetTime() }
	talk.lines[#talk.lines + 1] = entry
	while #talk.lines > MAX_LINES do table.remove(talk.lines, 1) end
	talk.last = time()
	if current == key and window and window:IsShown() then AddBubble(entry) end
	ns.RefreshMessages()
end

local function Send()
	local text = strtrim(input:GetText() or "")
	if text == "" or not current then return end
	input:SetText("")
	Conversation(current).draft = nil
	Echo(current, text)
	if IsBattleNet(current) then
		if BNSendWhisper then pcall(BNSendWhisper, tonumber(current:sub(4)), text) end
	else
		local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		if send then pcall(send, text, "WHISPER", nil, current) end
	end
end

-- (a draft begun or emptied: its row says so, once for the letters typed together)
local RowsSoon = U.Debounce(0.3, function() ns.RefreshMessages() end)

local function CreateWindow()
	window = Skin.CreateWindow("WandererChatMessages", "MEDIUM")
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	-- The size chosen last time, within reason.
	local size = type(ns.DB().size) == "table" and ns.DB().size or {}
	window:SetSize(Skin.Within(tonumber(size[1]) or WIDTH, MIN_WIDTH, MAX_WIDTH),
		Skin.Within(tonumber(size[2]) or HEIGHT, MIN_HEIGHT, MAX_HEIGHT))
	Skin.Dress(window, { "LEFT", UIParent, "LEFT", 40, 60 }, "messagesPos")
	-- A window of its own: the game's windows (the spellbook...) and Escape never
	-- close it, the interface fades around it, and it stays in a fight (to
	-- answer, if you wish). Its cross closes it, or Escape while writing.
	for index = #(UISpecialFrames or {}), 1, -1 do
		if UISpecialFrames[index] == "WandererChatMessages" then table.remove(UISpecialFrames, index) end
	end
	local margin = Skin.Margin() + 6

	-- The people, on the left.
	list = CreateFrame("Frame", nil, window)
	list:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	list:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	list:SetWidth(LIST_WIDTH)
	if list.SetClipsChildren then list:SetClipsChildren(true) end -- a short window: the last people under the rest
	local line = Skin.Rule(window, true, 0.2)
	line:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	line:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 0)
	window.empty = Skin.Text(list, "GameTooltipTextSmall", "muted")
	-- Search: a name or a word.
	window.search = Skin.CreateInput(list, "WandererChatMessagesSearch", 40, {
		hint = L.MESSAGES_SEARCH,
		onChange = function() ns.RefreshMessages() end,
		onEscape = function(self) self:SetText("") self:ClearFocus() end,
	})
	window.search:SetHeight(20)
	window.search:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
	window.search:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	window.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -SEARCH_HEIGHT - 4)
	window.empty:SetPoint("RIGHT", list, "RIGHT", -4, 0)
	window.empty:SetText(L.MESSAGES_EMPTY)

	-- The conversation, on the right.
	portrait = Portrait(window, PORTRAIT)
	portrait:SetPoint("TOPLEFT", list, "TOPRIGHT", 16, 0)
	-- The options of the person shown, at the top right of the conversation (the cross keeps its corner).
	window.options = MoreButton(window, function(self) OpenMenu(self, current) end, true, L.MESSAGES_PERSON_HINT)
	window.options:SetPoint("TOPRIGHT", window, "TOPRIGHT", -36, -margin)
	window.options:Hide()
	-- The window's settings (colors, popup, sound), as every window's cog, left of the "...".
	window.cog = Skin.GlyphButton(window, "cog", 14, L.SETTINGS_COG, function() W.OpenOptions("ext:chat") end)
	window.cog:SetPoint("RIGHT", window.options, "LEFT", -4, 0)
	header = Skin.Text(window, "GameTooltipHeaderText", "gold")
	header:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 12, -3)
	-- (the heading's "?" left of the cog: what the window does)
	local help = Skin.Help and Skin.Help(window, L.MESSAGES_HELP, "HEADING")
	header:SetPoint("RIGHT", window, "RIGHT", -36 - Skin.ROW_MORE - 26 - (help and 20 or 0), 0)
	if header.SetWordWrap then header:SetWordWrap(false) end
	-- Who they are, under the name.
	info = Skin.Text(window, "GameTooltipTextSmall", "soft")
	info:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	-- (the whole width up to the "..." button's edge, on more lines rather than cut)
	info:SetPoint("RIGHT", window, "RIGHT", -36, 0)
	if info.SetWordWrap then info:SetWordWrap(true) end
	if info.SetMaxLines then info:SetMaxLines(INFO_LINES) end
	-- A click on the person (portrait or name): what can be done with them.
	person = CreateFrame("Button", nil, window)
	person:SetPoint("TOPLEFT", portrait, "TOPLEFT")
	person:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT")
	person:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (both open its menu: no top button)
	person:SetScript("OnClick", function(self) OpenMenu(self, current) end)
	Skin.Tooltip(person, L.MESSAGES_PERSON_HINT, "ANCHOR_BOTTOM")
	person:Hide()
	window.options:SetFrameLevel(person:GetFrameLevel() + 2)
	if window.cog then window.cog:SetFrameLevel(person:GetFrameLevel() + 2) end
	-- (the answer line is for a keyboard only, on purpose: writing needs one, as in the game's own chat)
	input = Skin.CreateInput(window, "WandererChatMessagesInput", 255)
	input:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 16, 0)
	input:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	input:SetScript("OnEnterPressed", Send)
	-- What you write stays in its conversation until sent: leave it, come back, it is there.
	input:SetScript("OnTextChanged", function(self)
		if not current then return end
		local text = self:GetText() or ""
		local talk = Conversation(current)
		local draft = strtrim(text) ~= "" and text or nil
		if talk.draft ~= draft then
			talk.draft = draft
			RowsSoon()
		end
	end)
	input:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		window:Hide()
	end)
	thread = CreateFrame("ScrollFrame", "WandererChatMessagesHistory", window)
	-- Room for the name and both lines of who they are, always: nothing
	-- moves when a line comes (an answer to "look them up").
	header:SetText("Ag")
	info:SetText(("Ag\n"):rep(INFO_LINES - 1) .. "Ag")
	local tall = 3 + U.Measure(header, "GetStringHeight", 16) + 4 + U.Measure(info, "GetStringHeight", 13 * INFO_LINES)
	header:SetText("")
	info:SetText("")
	thread:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -10 - math.max(0, math.ceil(tall - PORTRAIT)))
	thread:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 8)
	-- Its width is known from the window's (the frame may not be laid out yet).
	thread.width = window:GetWidth() - margin * 2 - LIST_WIDTH - 16
	-- An empty conversation says so, calmly, in its middle.
	window.emptyThread = Skin.Text(window, "GameTooltipText", "muted")
	window.emptyThread:SetPoint("LEFT", thread, "LEFT", 16, 0)
	window.emptyThread:SetPoint("RIGHT", thread, "RIGHT", -16, 0)
	window.emptyThread:SetJustifyH("CENTER")
	window.emptyThread:SetText(L.MESSAGES_EMPTY_THREAD)
	window.emptyThread:Hide()
	thread.content = CreateFrame("Frame", nil, thread)
	thread.content:SetSize(thread.width, 1)
	thread:SetScrollChild(thread.content)
	thread:EnableMouseWheel(true)
	thread:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, used.height - (self:GetHeight() or 0))
		local value = (self:GetVerticalScroll() or 0) - delta * SCROLL_STEP
		self:SetVerticalScroll(math.min(range, math.max(0, value)))
	end)

	-- The corner: dragged, the window grows or shrinks; the bubbles follow once let go.
	Skin.Resizable(window, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT,
		onResized = function(width, height)
			ns.DB().size = { width, height }
			thread.width = width - margin * 2 - LIST_WIDTH - 16
			thread.content:SetWidth(thread.width)
			if current then ShowConversation(current) else ns.RefreshMessages() end
		end,
	})
	window:HookScript("OnSizeChanged", function() Skin.Get(window):Layout() end)

	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.FitScale(self))
		if current then ShowConversation(current) else ns.RefreshMessages() end
	end)
	Skin.Get(window):Layout()
end

-- The conversation shown, drawn again (a color changed).
function ns.RedrawMessages()
	if current then ShowConversation(current) end
end

-- (answer: the line to write in taken at once)
function ns.ToggleMessages(key, answer)
	-- The chat itself off (or Wanderer): its page, where it is turned on (asked to turn the window on, it would
	-- stay off, and be asked again).
	if not ns.On() then
		if W.OpenOptions then W.OpenOptions("ext:chat") end
		return
	end
	-- The window off, it would never fill: asked to turn it on first (in every profile, as its option does).
	if not ns.On("messagesWindow") then
		Skin.Ask(L.MESSAGES_ASK, function()
			W.ChangeEverywhere(function()
				local settings = ns.Settings()
				if settings then settings.messagesWindow = true end
			end)
			ns.Refresh()
			ns.ToggleMessages(key, answer)
		end)
		return
	end
	if not window then CreateWindow() end
	if key then
		-- (opening, it shows this one at once: the one shown last would be drawn first, and count as read)
		if window:IsShown() then
			ShowConversation(key)
		else
			current = key
			window:Show()
		end
		-- (a reply is written with a keyboard: the controller keeps its own navigation)
		if answer and input:IsShown() and not (U.UsingPad and U.UsingPad()) then input:SetFocus() end
	else
		window:SetShown(not window:IsShown())
	end
end

-- Messages --------------------------------------------------------------------------------

local SOUND_COOLDOWN = 3 -- seconds: a quick exchange rings once, as in the game
local lastSound = 0
local heldForFight = false -- a message came in a fight: the window opens when it ends

local function Enabled()
	return ns.On("messagesWindow")
end

-- The chat no longer shows them (unless another addon, WIM or Chattynator, handles the whispers: never hidden twice).
local function HiddenInChat()
	return ns.On("messagesHideInChat") and not ns.Yields("whispers")
end

-- A message, written or received: kept, shown, and the window opened when quiet.
local function OnMessage(event, text, name, guid, bnID)
	local key
	if event:find("BN_") then
		bnID = Clean(bnID)
		if not bnID then return end
		key = "BN:" .. bnID
	else
		key = Clean(name)
		if not key then return end
	end
	local talk = Conversation(key)
	local me = EVENTS[event] == "me"
	if IsBattleNet(key) then
		-- The game gives a protected name: shown as is, never kept.
		if not U.IsSecret(name) then talk.name = name end
	else
		talk.name = Ambiguate and Clean(Safe(Ambiguate, key, "short")) or key
		guid = Clean(guid)
		if guid then
			local className, class, raceName, race, sex = Safe(GetPlayerInfoByGUID, guid)
			talk.guid = guid
			talk.className = Clean(className) or talk.className
			talk.raceName = Clean(raceName) or talk.raceName
			talk.class = Clean(class) or talk.class
			talk.race = Clean(race) or talk.race
			talk.sex = Clean(sex) or talk.sex
		end
	end
	talk.last = time()
	-- The confirmation of a message already shown when you sent it: nothing more.
	if me then
		for index = #talk.lines, math.max(1, #talk.lines - 10), -1 do
			local line = talk.lines[index]
			if line.echo and line.echo > sessionStart and GetTime() - line.echo >= 0 and GetTime() - line.echo <= ECHO_WAIT
				and (U.IsSecret(text) or line.text == text) then
				line.echo = nil
				if bubbleOf[line] and bubbleOf[line].entry == line then bubbleOf[line]:SetAlpha(1) end
				return
			end
		end
	end
	local entry = { t = time(), me = me or nil, from = talk.name }
	local shown = current == key and window and window:IsShown()
	-- A text the game keeps secret (in a fight) is shown but not kept: the chat
	-- keeps that line (see Filter); a thread not on screen only says one came.
	if U.IsSecret(text) then
		entry.text = nil
		if not shown and not me then
			entry.fight = true
			talk.lines[#talk.lines + 1] = entry
			while #talk.lines > MAX_LINES do table.remove(talk.lines, 1) end
		end
	else
		entry.text = text
		talk.lines[#talk.lines + 1] = entry
		while #talk.lines > MAX_LINES do table.remove(talk.lines, 1) end
	end
	Trim()
	-- The chat no longer shows it, so the game no longer rings: it rings here
	-- with the game's own whisper sound instead (never both: a secret line, in a fight, stays in the chat, which rings).
	if not me and not U.IsSecret(text) and ns.On("messagesSound") and HiddenInChat() and GetTime() - lastSound >= SOUND_COOLDOWN then
		lastSound = GetTime()
		U.PlaySound("TELL_MESSAGE")
	end
	if shown then
		AddBubble(entry, not entry.text and text or nil)
	elseif not me and not entry.fight then
		talk.unread = (talk.unread or 0) + 1
	end
	if not me and not entry.fight and InCombatLockdown() then heldForFight = true end
	-- Opened by a message from someone, never over a fight or a scene, never taking the keyboard.
	if not me and not InCombatLockdown() and not W.InScene() and ns.On("messagesPopup") and not ns.Yields("whispers") then
		if not (window and window:IsShown()) then
			-- Opened by the message itself: its own sound rings, not the window's.
			if not window then CreateWindow() end
			window.quiet = true
			ns.ToggleMessages(key)
			window.quiet = nil
		end
	end
	ns.RefreshMessages()
	-- (the window closed: RefreshMessages stops before the minimap's count)
	if not (window and window:IsShown()) then Launchers() end
end

-- The chat no longer shows them (they are in the window); only those the
-- window can show: a message is never lost between the two.
local function Filter(_, event, text, name, ...)
	if not (Enabled() and HiddenInChat()) then return false end
	if U.IsSecret(text) then return false end -- (in a fight: the window cannot keep it, the chat does)
	if event:find("BN_") then return Clean(select(11, ...)) ~= nil end -- the 13th value: the Battle.net id
	return Clean(name) ~= nil
end

-- The button beside the chat ------------------------------------------------------------
-- At the right of the game's social button, the very same button: its frame,
-- every texture and its count copied as they are, only the friends' icon
-- changed for a speech bubble and the friends online for what is unread (0
-- included). It comes and goes with that button (another addon may hide it)
-- and with its fading.

local chatButton
local CHAT_BUTTON_REFRESH = 0.5
local BUBBLE = "Interface\\GossipFrame\\GossipGossipIcon"
-- The game's own speech bubble of the chat buttons, when it has one.
local BUBBLE_ATLASES = { "communities-icon-chat", "chatframe-button-icon-speech", "chatframe-button-icon-chat" }
local BUBBLE_SIZE = 18
-- A patch of the social picture's empty inside (pixels of its 32), at the
-- lower left: away from its figure and its count.
local INSIDE_PATCH = { 5, 9, 21, 25 }
local INSIDE_INSET = 4

local function SetBubble(texture)
	for _, atlas in ipairs(BUBBLE_ATLASES) do
		if C_Texture and C_Texture.GetAtlasInfo and Safe(C_Texture.GetAtlasInfo, atlas) and texture.SetAtlas then
			texture:SetAtlas(atlas)
			return
		end
	end
	texture:SetTexture(BUBBLE)
	texture:SetTexCoord(0, 1, 0, 1)
end

-- The yellow of the social button's figure.
local BUBBLE_COLOR = Skin.COLORS.gold
local GLOW_LOOPS = 3 -- times the button glows for a new whisper

-- A new whisper: the button glows softly a few times, as the game's buttons do.
local function MakeGlow(button, social)
	if not button.CreateAnimationGroup then return end
	local glow = button:CreateTexture(nil, "OVERLAY")
	local highlight = social.GetHighlightTexture and social:GetHighlightTexture()
	local file = highlight and Clean(Safe(highlight.GetTexture, highlight))
	glow:SetTexture(file or "Interface\\Buttons\\ButtonHilight-Square")
	glow:SetBlendMode("ADD")
	glow:SetAllPoints(button)
	glow:SetAlpha(0)
	local pulse = button:CreateAnimationGroup()
	if not pulse then return end
	local rise = pulse:CreateAnimation("Alpha")
	local fall = pulse:CreateAnimation("Alpha")
	if not (rise and fall) then return end
	rise:SetTarget(glow)
	rise:SetFromAlpha(0)
	rise:SetToAlpha(1)
	rise:SetDuration(0.4)
	rise:SetOrder(1)
	fall:SetTarget(glow)
	fall:SetFromAlpha(1)
	fall:SetToAlpha(0)
	fall:SetDuration(0.6)
	fall:SetOrder(2)
	pulse:SetLooping("REPEAT")
	local loops = 0
	pulse:SetScript("OnLoop", function(self)
		loops = loops + 1
		if loops >= GLOW_LOOPS then self:Stop() end
	end)
	pulse:SetScript("OnStop", function() glow:SetAlpha(0) end)
	button.glow = function()
		loops = 0
		pulse:Stop()
		pulse:Play()
	end
end

local function SocialButton()
	for _, name in ipairs({ "QuickJoinToastButton", "FriendsMicroButton", "ChatFrameSocialButton" }) do
		local button = _G[name]
		if button and not (button.IsForbidden and button:IsForbidden()) then return button end
	end
end

-- The social button's own button textures, and only those it has.
local function Dress(button, social)
	local parts = {
		{ "GetNormalTexture", "SetNormalAtlas", "SetNormalTexture" },
		{ "GetPushedTexture", "SetPushedAtlas", "SetPushedTexture" },
		{ "GetHighlightTexture", "SetHighlightAtlas", "SetHighlightTexture" },
	}
	for _, part in ipairs(parts) do
		local get, setAtlas, setTexture = part[1], part[2], part[3]
		local texture = social[get] and social[get](social)
		local atlas = texture and texture.GetAtlas and Clean(Safe(texture.GetAtlas, texture))
		local file = texture and texture.GetTexture and Clean(Safe(texture.GetTexture, texture))
		if atlas and button[setAtlas] then
			Safe(button[setAtlas], button, atlas)
		elseif file then
			Safe(button[setTexture], button, file)
		end
	end
end

-- Placed as the original is, on the copy's own parts.
local function CopyPoints(copy, region, button, copies)
	for index = 1, (region.GetNumPoints and region:GetNumPoints() or 0) do
		local point, relative, relativePoint, x, y = region:GetPoint(index)
		if point then
			local to = (relative and copies[relative]) or button
			copy:SetPoint(point, to, relativePoint or point, x or 0, y or 0)
		end
	end
end

-- Its friends' icon and count, as they are (its other layers, flashes and
-- queue icons, only show while they play: never copied).
local function CopyRegions(button, social)
	local wanted = {}
	for _, key in ipairs({ "FriendsButton", "FriendCount" }) do
		if type(social[key]) == "table" then wanted[#wanted + 1] = social[key] end
	end
	local copies, order = {}, {}
	for _, region in ipairs(wanted) do
		if region.GetObjectType then
			local kind = region:GetObjectType()
			local copy
			if kind == "Texture" then
				local layer, sublevel = region:GetDrawLayer()
				copy = button:CreateTexture(nil, layer, nil, sublevel)
				local atlas = Clean(Safe(region.GetAtlas, region))
				if atlas then
					copy:SetAtlas(atlas)
				else
					local file = Clean(Safe(region.GetTexture, region))
					if file then copy:SetTexture(file) end
					Safe(copy.SetTexCoord, copy, region:GetTexCoord())
				end
				Safe(copy.SetVertexColor, copy, region:GetVertexColor())
				Safe(copy.SetBlendMode, copy, region:GetBlendMode())
			elseif kind == "FontString" then
				local layer = region:GetDrawLayer()
				copy = button:CreateFontString(nil, layer)
				local font, size, flags = region:GetFont()
				if font then copy:SetFont(font, size, flags) else copy:SetFontObject("GameFontNormalSmall") end
				Safe(copy.SetTextColor, copy, region:GetTextColor())
				Safe(copy.SetShadowOffset, copy, region:GetShadowOffset())
				Safe(copy.SetShadowColor, copy, region:GetShadowColor())
				Safe(copy.SetJustifyH, copy, region:GetJustifyH())
			end
			if copy then
				local width, height = region:GetSize()
				if width and width > 0 and height and height > 0 then copy:SetSize(width, height) end
				copy:SetAlpha(region:GetAlpha() or 1)
				copy:SetShown(region:IsShown())
				copies[region] = copy
				order[#order + 1] = region
			end
		end
	end
	for _, region in ipairs(order) do CopyPoints(copies[region], region, button, copies) end
	return copies
end

function ns.RefreshChatWhisperButton()
	if not chatButton then return end
	local social = chatButton.social
	-- The social button's own size and scale (known once the chat is laid out).
	local width, height = social:GetSize()
	if width and width > 0 and height and height > 0 then
		if math.abs(chatButton:GetWidth() - width) > 0.5 or math.abs(chatButton:GetHeight() - height) > 0.5 then
			chatButton:SetSize(width, height)
		end
		if chatButton.ownIcon then chatButton.icon:SetSize(width * 0.5, width * 0.5) end
	end
	local scale = Clean(Safe(social.GetScale, social))
	if scale and scale > 0 and chatButton:GetScale() ~= scale then chatButton:SetScale(scale) end
	chatButton:SetShown((Enabled() and social:IsShown()) and true or false)
	-- (its watch only while the window is on: a hidden frame runs nothing)
	if chatButton.watcher then chatButton.watcher:SetShown(Enabled()) end
	local unread = ns.UnreadMessages()
	chatButton.count:SetText(unread > 99 and "99+" or tostring(unread))
	-- Where the friends' count is drawn on the social button, measured once
	-- it is laid out: the same spot here.
	local friends = chatButton.friends
	if friends and not chatButton.countPlaced and friends.GetCenter then
		local countX, countY = friends:GetCenter()
		local left, top = social:GetLeft(), social:GetTop()
		if countX and countY and left and top then
			chatButton.count:ClearAllPoints()
			chatButton.count:SetPoint("CENTER", chatButton, "TOPLEFT", countX - left, countY - top)
			chatButton.countPlaced = true
		end
	end
	chatButton.count:Show()
	-- More unread than a moment ago, the window closed: a short glow.
	if unread > (chatButton.lastUnread or unread) and chatButton.glow and not (window and window:IsShown()) then
		chatButton.glow()
	end
	chatButton.lastUnread = unread
end

local function MakeChatButton()
	local social = SocialButton()
	if not social then return end
	local button = CreateFrame("Button", "WandererChatWhisperButton", social:GetParent() or UIParent)
	button.social = social
	local width, height = social:GetSize()
	button:SetSize((width and width > 0) and width or 32, (height and height > 0) and height or 32)
	button:SetPoint("TOPLEFT", social, "TOPRIGHT", 0, 0)
	button:SetFrameStrata(social:GetFrameStrata())
	button:SetFrameLevel(social:GetFrameLevel())
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (both open the messages: no top button)
	Dress(button, social)
	local copies = CopyRegions(button, social)
	-- The friends' icon becomes a speech bubble, at the same place and size.
	local picture = type(social.FriendsButton) == "table" and copies[social.FriendsButton]
	local atlas = picture and Clean(Safe(picture.GetAtlas, picture))
	local sheet = atlas and C_Texture and C_Texture.GetAtlasInfo and Safe(C_Texture.GetAtlasInfo, atlas)
	if type(sheet) == "table" and sheet.leftTexCoord then
		-- The social button's whole picture (its frame and its figure) stays;
		-- its figure is covered by a piece of its own empty inside.
		local function Across(px) return sheet.leftTexCoord + (sheet.rightTexCoord - sheet.leftTexCoord) * px / 32 end
		local function Down(px) return sheet.topTexCoord + (sheet.bottomTexCoord - sheet.topTexCoord) * px / 32 end
		local inside = button:CreateTexture(nil, "BACKGROUND", nil, 1)
		inside:SetTexture(sheet.file or sheet.filename)
		inside:SetTexCoord(Across(INSIDE_PATCH[1]), Across(INSIDE_PATCH[2]), Down(INSIDE_PATCH[3]), Down(INSIDE_PATCH[4]))
		inside:SetPoint("TOPLEFT", button, "TOPLEFT", INSIDE_INSET, -INSIDE_INSET)
		inside:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -INSIDE_INSET, INSIDE_INSET)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		SetBubble(button.icon)
		button.icon:SetSize(BUBBLE_SIZE, BUBBLE_SIZE)
		button.icon:SetPoint("CENTER", button, "CENTER", 0, 3)
	elseif picture then
		SetBubble(picture)
		picture:ClearAllPoints()
		picture:SetPoint("CENTER", button, "CENTER", 0, 3)
		picture:SetSize(BUBBLE_SIZE, BUBBLE_SIZE)
		button.icon = picture
	else
		button.icon = button:CreateTexture(nil, "ARTWORK")
		SetBubble(button.icon)
		button.icon:SetPoint("TOP", button, "TOP", 0, -4)
		button.icon:SetSize(button:GetWidth() * 0.5, button:GetWidth() * 0.5)
		button.ownIcon = true
	end
	-- Yellow, as the social button's figure.
	button.icon:SetVertexColor(BUBBLE_COLOR[1], BUBBLE_COLOR[2], BUBBLE_COLOR[3])
	-- The friends online become what is unread: a text of its own, on top of
	-- everything, in the friends' count's font and at its place on the button.
	local friends = type(social.FriendCount) == "table" and social.FriendCount or nil
	local copied = friends and copies[friends]
	if copied then copied:Hide() end
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if friends then
		local font, size, flags = friends:GetFont()
		if font then button.count:SetFont(font, size, flags) end
		Safe(button.count.SetTextColor, button.count, friends:GetTextColor())
	end
	button.count:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
	button.friends = friends
	button:SetScript("OnClick", function() ns.ToggleMessages() end)
	Skin.Tooltip(button, function()
		local unread = ns.UnreadMessages()
		return unread > 0 and L.MENU_MESSAGES_UNREAD:format(unread) or L.MESSAGES_TITLE
	end)
	-- With the social button: shown, hidden and faded as it is.
	social:HookScript("OnShow", ns.RefreshChatWhisperButton)
	social:HookScript("OnHide", ns.RefreshChatWhisperButton)
	local since = 0
	local watcher = CreateFrame("Frame", nil, UIParent)
	watcher:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < CHAT_BUTTON_REFRESH then return end
		since = 0
		local alpha = Clean(Safe(social.GetAlpha, social))
		if alpha and button:GetAlpha() ~= alpha then button:SetAlpha(alpha) end
		ns.RefreshChatWhisperButton()
	end)
	MakeGlow(button, social)
	button.watcher = watcher
	chatButton = button
	ns.RefreshChatWhisperButton()
end

function ns.InitMessages()
	-- A surprise in the social button's parts never stops the messages.
	pcall(MakeChatButton)
	local frame = CreateFrame("Frame")
	for event in pairs(EVENTS) do frame:RegisterEvent(event) end
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	frame:RegisterEvent("WHO_LIST_UPDATE")
	frame:RegisterEvent("FRIENDLIST_UPDATE")
	-- Your friends or your guild read again (the guild's roster once for a burst, Chat.lua): who they are, again.
	local function Relearn()
		if current and window and window:IsShown() then
			Learn(Conversation(current), current)
			RefreshHeader()
		end
	end
	ns.GuildRead.On(Relearn)
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "WHO_LIST_UPDATE" then return OnWho() end
		if event == "FRIENDLIST_UPDATE" then return Relearn() end
		if event == "PLAYER_TARGET_CHANGED" then
			if current and window and window:IsShown() then ShowPortrait(portrait, Conversation(current)) end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			-- Messages came during the fight: the window opens now, on the newest.
			local held = heldForFight
			heldForFight = false
			if held and Enabled() and ns.On("messagesPopup") and not ns.Yields("whispers") and ns.UnreadMessages() > 0 and not (window and window:IsShown()) then
				if not window then CreateWindow() end
				window.quiet = true
				-- The most recent conversation with something unread.
				local open
				for _, conversation in ipairs(AllConversations()) do
					if (conversation.talk.unread or 0) > 0 and (not open or (conversation.talk.last or 0) > (open.talk.last or 0)) then
						open = conversation
					end
				end
				ns.ToggleMessages(open.key)
				window.quiet = nil
			end
			return
		end
		local text, name = ...
		if not Enabled() then return end
		local guid, bnID = select(12, ...), select(13, ...)
		-- (gold selling whispered by a stranger: no conversation, no sound, no window; Quiet.lua)
		if event == "CHAT_MSG_WHISPER" and ns.HushedWhisper and ns.HushedWhisper(text, name, select(11, ...), guid, select(6, ...)) then return end
		OnMessage(event, text, name, guid, bnID)
	end)
	for event in pairs(EVENTS) do ns.AddFilter(event, Filter) end
end
