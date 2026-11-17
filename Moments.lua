local _, ns = ...
local L = ns.L

-- The moments: a small card among the alerts (beside the chat), only for something to do, until you act,
-- close it or it grows old (its time runs only while it is shown). Never more than three; a card of the same thing is renewed rather
-- than added. Nothing is ever said for you: a button writes only when you click it, Enter sends it.
-- * A group sought or a word of yours, when asked for: Channels.lua.
-- * Your name, when the chat does not show it: Alerts.lua (in the chat its line is in gold, Highlight.lua).
-- * The first time, the tabs offered.
-- (The guild's greetings and goodbyes made a card too: removed at the user's request, 2026-11-16, more
-- bothersome than useful.)

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local WIDTH = 330
local GAP = 6
local MOST = 3
local BUTTON_HEIGHT = 22
local FADE_IN, FADE_OUT = 0.25, 0.6
local STALE = 60 -- seconds: a card made while you were busy, still worth showing once you are free
local LIFE = { channel = 90, mention = 300, offer = 600 }
local OFFER_AFTER = 8 -- seconds after logging in (again later while you are busy)
local QUIET = 60 -- seconds between two new cards of these kinds (a card renewed: not counted)
local RATED = { channel = true }

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
	-- (the game look: the game's small gold title, written as it is)
	card.game = rawget(Skin, "GameWindows") ~= nil and Skin.GameWindows()
	if card.game and _G.GameFontNormalSmall then card.kicker:SetFontObject(Skin.FontFor("GameFontNormalSmall")) end
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
	card.kicker:SetText(card.game and (spec.kicker or "") or U.Upper(spec.kicker or ""))
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
		if not ((U.Hovered and U.Hovered(card)) or card:IsMouseOver()) then card.left = card.left - elapsed end
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

-- The name card's greeting (Social.lua) ------------------------------------------------------------------------

-- The words to say, by the hour (the evening from 6 pm, the night from 10 pm for a goodbye).
local function Saying(kind, names)
	local hour = tonumber(date("%H")) or 12
	local time = (hour >= 18 or hour < 5) and "_EVENING" or ""
	if kind == "bye" and (hour >= 22 or hour < 5) then time = "_NIGHT" end
	local key = (kind == "greet" and "SAY_HELLO" or "SAY_BYE") .. (#names > 2 and "_ALL" or "") .. time
	return L[key]:format(ns.Names(names))
end
ns.Saying = Saying

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

function ns.InitMoments()
	local driver = CreateFrame("Frame", nil, ns.Holder())
	driver:SetScript("OnUpdate", function(_, elapsed)
		if cards[1] then Step(elapsed) end
	end)
	C_Timer.After(OFFER_AFTER, Offer)
end
