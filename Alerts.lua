local _, ns = ...
local L = ns.L

-- The alerts: the cards (Moments.lua, Channels.lua) stand in one holder, beside the chat by default, moved
-- with every other piece in Wanderer's placing mode. Nothing of the guild or the group passes there by
-- itself: the chat is where you read. One alert of its own here: a line that names you, when the chat does
-- not show it to you (another tab in front, the chat faded or hidden, you busy when it came).

local W = Wanderer
local U = W and W.Util

local WIDTH = 330 -- the cards' width
local HEIGHT = 60 -- the holder alone (seen in the placing mode)
local GAP = 16 -- between the chat and the alerts
local FALLBACK = { "BOTTOMLEFT", "BOTTOMLEFT", 470, 120 } -- the chat's place unknown
local EXCERPT = 110
local FADED = 0.35 -- a chat window this faded (Wanderer's curtain, the interface hidden) is out of sight

local holder

-- The holder ------------------------------------------------------------------------------------------------

-- The place by default: just right of the chat, at its foot.
function ns.DefaultPlace()
	local chat = DEFAULT_CHAT_FRAME or _G.ChatFrame1
	if not (chat and chat.GetRight and chat.GetEffectiveScale and UIParent.GetEffectiveScale) then return FALLBACK end
	local right, bottom = U.Clean(U.Safe(chat.GetRight, chat)), U.Clean(U.Safe(chat.GetBottom, chat))
	local scale = (chat:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	if type(right) ~= "number" or type(bottom) ~= "number" then return FALLBACK end
	return { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(right * scale + GAP), math.floor(bottom * scale) }
end

local function Place()
	local place = ns.DB().alertsPlace
	if type(place) == "table" and type(place[1]) == "string" then
		place = { place[1], place[1], place[2], place[3] }
	else
		place = ns.DefaultPlace()
	end
	holder:ClearAllPoints()
	holder:SetPoint(place[1], UIParent, place[2], tonumber(place[3]) or 0, tonumber(place[4]) or 0)
end

function ns.Holder() return holder end

function ns.InitHolder()
	local db = ns.DB()
	db.place = nil -- (the old subtitle line's place)
	holder = CreateFrame("Frame", "WandererChatAlerts", UIParent)
	holder:SetSize(WIDTH, HEIGHT)
	holder:SetFrameStrata("LOW")
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	-- (read like the chat when the interface fades around it)
	if holder.SetIgnoreParentAlpha then holder:SetIgnoreParentAlpha(true) end
	W.Placeable({ key = "chatAlerts", label = function() return L.PLACE_LABEL end, frame = holder,
		load = function() return ns.DB().alertsPlace end, save = function(spot) ns.DB().alertsPlace = spot end,
		enabled = function() return ns.On() end,
		default = function() return ns.DefaultPlace() end })
	Place()
	-- (the chat placed by then: the place by default looked at again, once)
	local arrival = CreateFrame("Frame")
	arrival:RegisterEvent("PLAYER_ENTERING_WORLD")
	arrival:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		C_Timer.After(2, Place)
	end)
end

-- Shown unless you are busy.
function ns.RefreshHolder()
	if not holder then return end
	holder:SetShown((ns.On() and not ns.Busy()) and true or false)
end

-- A kind's name as the game says it ("Guild", "Party").
function ns.Where(line)
	if line.kind == "channel" then return line.channel or "" end
	if line.kind == "near" then return L.WHERE_NEAR end
	local chatType = ns.CHAT_TYPE[line.kind] or "SAY"
	return _G["CHAT_MSG_" .. chatType] or chatType
end

-- What the chat shows you ----------------------------------------------------------------------------------

-- The chat windows in sight now: the tab in front of the dock, any window apart; shown and not faded.
local function InSight()
	local list = {}
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. index]
		if type(frame) == "table" and frame.IsVisible and frame:IsVisible() and not ns.IsCombatLogFrame(frame)
			and not ns.IsDebugTab(index) then
			local alpha = frame.GetEffectiveAlpha and U.Clean(U.Safe(frame.GetEffectiveAlpha, frame))
			if type(alpha) ~= "number" or alpha >= FADED then list[#list + 1] = frame end
		end
	end
	return list
end

-- Whether a chat window shows a chat ("GUILD", "PARTY_LEADER": the game's message groups).
local function Shows(frame, group)
	local groups = frame.messageTypeList
	if type(groups) ~= "table" or not group then return false end
	for _, each in pairs(groups) do
		if each == group then return true end
	end
	return false
end

-- Whether a chat window listens to a public channel ("Trade - City", "2. Trade - City"): its channels' names
-- read as the game reads them, from the start of the channel's. (A window without a channel list: its group.)
function ns.ListsChannel(frame, channel)
	local list = type(frame) == "table" and frame.channelList
	if type(list) ~= "table" then return Shows(frame, "CHANNEL") end
	if type(channel) ~= "string" then return false end
	local name = U.Upper((channel:gsub("^%d+%.%s*", "")))
	for _, each in pairs(list) do
		if type(each) == "string" and each ~= "" and name:sub(1, #each) == U.Upper(each) then return true end
	end
	return false
end

-- Whether the chat shows this line where you can read it now (a public channel's: the windows listening to it;
-- the "CHANNEL" group only says the channels' notices).
function ns.ChatShows(line)
	local group = type(line.event) == "string" and line.event:match("^CHAT_MSG_(.+)$")
	for _, frame in ipairs(InSight()) do
		if line.kind == "channel" then
			if ns.ListsChannel(frame, line.channel) then return true end
		elseif Shows(frame, group) then
			return true
		end
	end
	return false
end

-- Your name said ------------------------------------------------------------------------------------------------

-- A line that names you, not in sight: a card, until you read it (a whisper rings already: none).
local function OnHeard(line)
	if line.me or line.arrival or not ns.On("mentionCard") then return end
	if line.kind == "whisper" or line.kind == "bnwhisper" then return end
	if not ns.NamesYou(line.kind, line.sender, line.text) then return end
	if not ns.Busy() and ns.ChatShows(line) then return end
	local chatType = ns.CHAT_TYPE[line.kind]
	ns.Card({ key = "mention:" .. (line.who or ""), kind = "mention", kicker = ns.Where(line), waits = true,
		title = L.MENTION_TITLE:format(ns.Named(line.who, line.guid)),
		body = L.RP_TITLE_QUOTED:format(ns.Excerpt(line.text, EXCERPT)),
		buttons = { { L.GLASS_REPLY, function() ns.Answer(line) end },
			chatType and { L.READ, function() ns.ShowTabOf(chatType, line.kind == "channel" and line.channel or nil) end } or nil } })
end

function ns.InitAlerts()
	ns.Heard.On(OnHeard)
end
