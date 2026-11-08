local _, ns = ...
local L = ns.L

-- The moments: a small card among the alerts (beside the chat), only for something to do, until you act,
-- close it or it grows old (its time runs only while it is shown). Never more than three; a card of the same thing is renewed rather
-- than added. Nothing is ever said for you: a button writes only when you click it, Enter sends it.
-- * Someone greets the guild (or comes online and greets it): "Greet" answers by name, as the hour wants.
-- * Someone says goodbye: the same, to wish them well.
-- (A group sought or a word of yours, when asked for: Channels.lua. Your name, when the chat does not show it:
-- Alerts.lua; in the chat its line is in gold, Highlight.lua.)
-- Writing to the guild yourself lets the guild's cards go: you are in it already. Cards come one a minute at most.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local WIDTH = 330
local GAP = 6
local MOST = 3
local EXCERPT = 110
local BUTTON_HEIGHT = 22
local FADE_IN, FADE_OUT = 0.25, 0.6
local STALE = 60 -- seconds: a card made while you were busy, still worth showing once you are free
local LIFE = { greet = 150, bye = 120, channel = 90, mention = 300, offer = 600 }
local ARRIVED = 300 -- seconds: someone come online this lately "arrives"
local GREET_AGAIN = 1800 -- seconds before the same person's greeting makes a card again
local GREETING_WORDS = 8 -- a greeting at most these many words
local YOU_GREETED = 30 -- seconds: you wrote to the guild this lately, its greetings are answered already
local OFFER_AFTER = 8 -- seconds after logging in (again later while you are busy)
local QUIET = 60 -- seconds between two new cards of these kinds (a card renewed: not counted)
local RATED = { greet = true, bye = true, channel = true }

local cards = {} -- shown, the oldest first
local pool = {}
local lastRated = -math.huge -- when the last card of a rated kind was made

-- Cards ------------------------------------------------------------------------------------------------------

local function Layout()
	local holder = ns.Holder()
	local y = 0
	for index = #cards, 1, -1 do
		local card = cards[index]
		card:ClearAllPoints()
		card:SetPoint("BOTTOM", holder, "BOTTOM", 0, y)
		y = y + card:GetHeight() + GAP
	end
end

local function Drop(card)
	for index, shown in ipairs(cards) do
		if shown == card then
			table.remove(cards, index)
			break
		end
	end
	card:Hide()
	card.key, card.sound = nil, nil
	pool[#pool + 1] = card
	Layout()
end

-- The cards whose key begins so (nil: all), gone.
function ns.DropCards(prefix)
	for index = #cards, 1, -1 do
		local key = cards[index].key or ""
		if not prefix or key:sub(1, #prefix) == prefix then Drop(cards[index]) end
	end
end

local function Make()
	local card = Skin.CreateWindow(nil, "LOW", ns.Holder(), true)
	card:SetWidth(WIDTH)
	card:EnableMouse(true)
	local margin = Skin.Margin()
	card.kicker = Skin.CreateKicker(card)
	card.kicker:SetPoint("TOPLEFT", card, "TOPLEFT", margin, -margin)
	card.title = Skin.Text(card, "GameFontNormal", "text")
	card.title:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -3)
	card.title:SetWidth(WIDTH - margin * 2 - 20)
	card.title:SetJustifyH("LEFT")
	card.body = Skin.Text(card, "GameTooltipTextSmall", "soft")
	card.body:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.body:SetWidth(WIDTH - margin * 2)
	card.body:SetJustifyH("LEFT")
	card.body:SetMaxLines(3)
	Skin.CloseButton(card, function() Drop(card) end)
	card.buttons = {}
	card.tween = U.Tween(0)
	return card
end

local function Button(card, index, spec)
	local button = card.buttons[index]
	if not button then
		button = Skin.SmallButton(card, "", function(self)
			-- (a card barely seen, coming or going: not a click meant for it)
			if card:GetAlpha() <= 0.3 then return end
			if self.run then self.run() end
			Drop(card)
		end, nil, BUTTON_HEIGHT)
		Skin.Tooltip(button, function(self) return self.tip and self.tip() end)
		card.buttons[index] = button
	end
	button:SetLabel(spec[1])
	button.run, button.tip = spec[2], spec[3]
	return button
end

-- A card: { key, kind, kicker, title, body, buttons = { { label, run, tooltip } }, sound, stale, waits }. One of the
-- same key shown is renewed instead. Made while you are busy (hidden then), it goes if you stay busy long
-- (waits: it stays); its sound rings when it is first seen. A new card of a rated kind within a minute of the last one: none (nil).
function ns.Card(spec)
	local card
	for _, shown in ipairs(cards) do
		if shown.key == spec.key then card = shown end
	end
	local fresh = not card
	if fresh and RATED[spec.kind] then
		if GetTime() - lastRated < QUIET then return nil end
		lastRated = GetTime()
	end
	if fresh then
		card = table.remove(pool) or Make()
		card.key = spec.key
		card.tween = U.Tween(0)
		card:SetAlpha(0)
		card.sound = spec.sound
		cards[#cards + 1] = card
		while #cards > MOST do Drop(cards[1]) end
	end
	card.left = LIFE[spec.kind] or 120
	card.stale = spec.stale or (ns.Busy() and not spec.waits and GetTime() + STALE) or nil
	card.kicker:SetText(U.Upper(spec.kicker or ""))
	card.title:SetText(spec.title or "")
	card.body:SetText(spec.body or "")
	card.body:SetShown(spec.body ~= nil)
	local margin = Skin.Margin()
	local height = margin * 2 + U.Measure(card.kicker, "GetStringHeight", 10) + 3 + U.Measure(card.title, "GetStringHeight", 14)
	if spec.body then height = height + 4 + U.Measure(card.body, "GetStringHeight", 12) end
	local previous
	for index, button in ipairs(card.buttons) do button:SetShown(spec.buttons and spec.buttons[index] ~= nil) end
	for index, entry in ipairs(spec.buttons or {}) do
		local button = Button(card, index, entry)
		button:ClearAllPoints()
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
		else
			button:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", margin, margin)
		end
		button:Show()
		previous = button
	end
	if previous then height = height + 8 + BUTTON_HEIGHT end
	card:SetHeight(height)
	Skin.Get(card):Layout()
	card:Show()
	Layout()
	return card
end

-- (only while the cards are seen: the holder shown)
local function Step(elapsed)
	for index = #cards, 1, -1 do
		local card = cards[index]
		if not card:IsMouseOver() then card.left = card.left - elapsed end
		if card.stale and GetTime() > card.stale then card.left = math.min(card.left, 0) end
		if card.sound then
			if card.left > 0 then U.PlaySound(card.sound) end
			card.sound = nil
		end
		local alpha = card.tween:Step(card.left > 0 and 1 or 0, elapsed, FADE_IN, FADE_OUT)
		card:SetAlpha(alpha)
		if card.left <= 0 and alpha <= 0 then Drop(card) end
	end
end

-- Words of the guild ------------------------------------------------------------------------------------------

local hello, bye -- the words that greet and that say goodbye (the client's language and English)
local arrived, greeted = {}, {} -- name -> when they came online, when their greeting made a card
local spoke = -math.huge -- when you last wrote to the guild
local greeters = { greet = {}, bye = {} } -- the names on each card

-- How many words (Chinese writes without spaces: each of its letters counts as one).
local function Count(words)
	local count = 0
	for word in words:gmatch("%S+") do
		local letters = select(2, word:gsub("[\228-\233][\128-\191][\128-\191]", ""))
		count = count + math.max(1, letters)
	end
	return count
end

-- The length of the longest phrase of the list found in the words (0: none).
local function Longest(words, list)
	local best = 0
	for _, phrase in ipairs(list) do
		if #phrase > best and ns.Has(words, phrase) then best = #phrase end
	end
	return best
end

-- A greeting or a goodbye: the longest phrase found decides ("buenas noches" is a goodbye though "buenas"
-- greets), a goodbye when both are as long.
local function Greeting(words)
	local greets, leaves = Longest(words, hello), Longest(words, bye)
	if leaves > 0 and leaves >= greets then return "bye" end
	if greets > 0 then return "greet" end
end
ns.Greeting, ns.CountWords = Greeting, Count -- (tests)

-- The words to say, by the hour (the evening from 6 pm, the night from 10 pm for a goodbye).
local function Saying(kind, names)
	local hour = tonumber(date("%H")) or 12
	local time = (hour >= 18 or hour < 5) and "_EVENING" or ""
	if kind == "bye" and (hour >= 22 or hour < 5) then time = "_NIGHT" end
	local key = (kind == "greet" and "SAY_HELLO" or "SAY_BYE") .. (#names > 2 and "_ALL" or "") .. time
	return L[key]:format(ns.Names(names))
end
ns.Saying = Saying -- (the name card's greeting, Social.lua)

local function GreetCard(kind, line)
	local names = greeters[kind]
	-- (a card gone: its names with it)
	local shown = false
	for _, card in ipairs(cards) do shown = shown or card.key == kind end
	if not shown then wipe(names) end
	if not tContains(names, line.who) then names[#names + 1] = line.who end
	local title
	if kind == "greet" then
		local recent = #names == 1 and arrived[line.who] and line.at - arrived[line.who] <= ARRIVED
		title = recent and L.GREET_ARRIVED:format(line.who) or (#names == 1 and L.GREET_ONE or L.GREET_SOME):format(ns.Names(names))
	else
		title = (#names == 1 and L.BYE_ONE or L.BYE_SOME):format(ns.Names(names))
	end
	-- (written in the chat's line, sent by your own Enter)
	local function Say()
		local words = Saying(kind, names)
		if words and words ~= "" then ns.OpenChatLine(ns.SLASH.GUILD .. words) end
	end
	return ns.Card({ key = kind, kind = kind, kicker = ns.Where(line), title = title,
		body = #names == 1 and L.RP_TITLE_QUOTED:format(ns.Excerpt(line.text, EXCERPT)) or nil,
		buttons = { { kind == "greet" and L.GREET_BUTTON or L.BYE_BUTTON, Say,
			function() return L.SAY_DESC:format(Saying(kind, names)) end } },
		sound = Skin.SOUNDS.mark })
end

local function OnGuild(line)
	if line.arrival then
		ns.Prune(arrived, line.at, ARRIVED)
		arrived[line.who] = line.at
		return
	end
	if line.kind == "achievement" then return end
	if line.me then
		spoke = line.at
		for _, prefix in ipairs({ "greet", "bye" }) do ns.DropCards(prefix) end
		return
	end
	if not ns.On("greetings") then return end
	local words = ns.Words(line.text)
	if Count(words) > GREETING_WORDS then return end
	local kind = Greeting(words)
	if not kind or line.at - (greeted[kind .. line.who] or -math.huge) < GREET_AGAIN or line.at - spoke <= YOU_GREETED then return end
	ns.Prune(greeted, line.at, GREET_AGAIN)
	-- (no card now, the minute not over: the next greeting of theirs may make one)
	if GreetCard(kind, line) then greeted[kind .. line.who] = line.at end
end

-- The first time: the tabs offered ------------------------------------------------------------------------------

local function Offer()
	local db = ns.DB()
	if db.offered or not ns.On() or ns.AnyChatTab() then return end
	-- (busy: offered a little later, when it can be seen)
	if ns.Busy() then return C_Timer.After(OFFER_AFTER, Offer) end
	db.offered = true
	ns.Card({ key = "offer", kind = "offer", kicker = L.ADDON, title = L.OFFER_TITLE, body = L.OFFER_TEXT,
		buttons = { { L.CHAT_TABS_BUTTON, function() ns.CreateChatTabs() end }, { L.LATER } } })
end

-- English greetings that are common words of the client's language, never taken for one there (Spanish "yo": I).
local NOT_ENGLISH = { esES = { YO = true }, esMX = { YO = true } }

-- The client's words, then the English ones (many write them whatever their language).
local function Phrases(key)
	local list = ns.List(L[key])
	local skip = NOT_ENGLISH[GetLocale and GetLocale() or "enUS"] or {}
	for _, word in ipairs(ns.List(ns.LOCALES.enUS[key])) do
		if not skip[word] and not tContains(list, word) then list[#list + 1] = word end
	end
	return list
end

function ns.InitMoments()
	hello, bye = Phrases("HELLO_WORDS"), Phrases("BYE_WORDS")
	ns.Heard.On(function(line)
		-- (heard while you were busy: the summary tells it)
		if not line.waiting and (ns.GUILD[line.kind] or line.kind == "achievement") then OnGuild(line) end
	end)
	local driver = CreateFrame("Frame", nil, ns.Holder())
	driver:SetScript("OnUpdate", function(_, elapsed)
		if cards[1] then Step(elapsed) end
	end)
	C_Timer.After(OFFER_AFTER, Offer)
end
