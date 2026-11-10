local _, ns = ...
local L = ns.L

-- Five comforts of the chat (options):
-- * Your sent messages with the arrow keys: Up and Down bring them back while
--   you type, the last one first (as in a terminal), Left and Right move in
--   the text instead of turning your character. They are kept here, the last
--   32 of each character, from one session to the next, and put back in the box: this never
--   relies on the game's own memory of the box (Alt + arrows), which some
--   clients do not answer.
-- * Copy the chat: a discreet button in the corner of the chat, shown while
--   the mouse is over it, opens the chat of that tab as plain text; another
--   beside it searches the same lines (Search.lua).
-- * The conversations kept: each tab keeps its last lines (its channels, as
--   the game shows them) from one session to the next, for each character;
--   after a reload or a new session they are back in their tab, a little
--   dimmed, under a quiet line. Secret lines are never kept.
-- * Web addresses become links: a click opens the address, ready to copy
--   (the game lets nothing be copied from the chat), in the guild's windows too.
-- * One text size for every chat window.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local KEPT = 32 -- sent messages kept, as many as the game remembers
local BUTTON_SIZE = 18
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon" -- (the game's own magnifier)
local CHECK_EVERY = 0.1
local FADE_IN, FADE_OUT = 0.2, 0.5
local LOG_KEPT = 150 -- lines kept per tab
local LOG_DIM = 0.7 -- the lines of before, a little dimmed

local boxes = {} -- edit box -> true: watched
local browsing = {} -- edit box -> { index, draft } while you go through your messages
local buttons = {} -- chat frame -> its copy button

local function Settings()
	local settings = ns.Settings()
	return settings and settings.enabled and settings or nil
end

local function EditBoxes()
	local list = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local box = _G["ChatFrame" .. i .. "EditBox"]
		if box then list[#list + 1] = box end
	end
	return list
end

-- Each character has its own messages (a few only: KEPT), in the saved variables.
local function History()
	local db = ns.DB()
	db.history = type(db.history) == "table" and db.history or {}
	return db.history
end

-- A message sent: remembered for the next session (never a secret one).
local function Remember(text)
	if type(text) ~= "string" or text == "" or U.IsSecret(text) then return end
	local history = History()
	if history[#history] == text then return end
	history[#history + 1] = text
	while #history > KEPT do table.remove(history, 1) end
end

-- The lines of each tab, per character, by the tab's name (a tab moved keeps its lines):
-- { [name] = { { text, r, g, b }, ... } }.
local function Log()
	local db = ns.DB()
	db.log = type(db.log) == "table" and db.log or {}
	return db.log
end

local restoring = false -- the lines of before put back: not kept twice
local logged = {} -- chat frame -> true: watched

-- An addon that keeps the chat's lines itself (Prat, Chattynator, ElvUI's history...): it restores them.
-- (asked for every line: the answer kept a few seconds)
local function OtherHistory()
	if ns.YieldsNow("chatLog") then return true end
	local ok, on = pcall(function()
		local E = _G.ElvUI and _G.ElvUI[1]
		return E and E.private and E.private.chat and E.private.chat.enable and E.db and E.db.chat
			and E.db.chat.chatHistory and true or false
	end)
	return ok and on or false
end

local function LogOn()
	local settings = Settings()
	return settings and settings.keepLog and not OtherHistory() and true or false
end

-- Each window's key in the log: its tab's name ("General", "Guild"), a second tab of the same name told apart
-- ("General#2"), a window with no name by its number. Read again when the tabs change. (No name known yet, at the
-- very start: read again next time, nothing kept.)
local tabKeys, lastKeys -- (lastKeys: the keys before the tabs changed, for a tab renamed)
local function TabKey(index)
	local keys = tabKeys
	if not keys then
		keys = {}
		local seen, named = {}, false
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local name = U.Clean(U.Safe(GetChatWindowInfo, i))
			if type(name) ~= "string" or name == "" then name = "#" .. i else named = true end
			seen[name] = (seen[name] or 0) + 1
			keys[i] = seen[name] > 1 and (name .. "#" .. seen[name]) or name
		end
		if named then tabKeys = keys end
	end
	return keys[index] or ("#" .. index)
end
function ns.TabKeysChanged()
	lastKeys = tabKeys or lastKeys
	tabKeys = nil
end

-- A tab renamed: its lines kept under its new name (one already there under that name left as it is).
function ns.TabRenamed(index)
	local old = (tabKeys or lastKeys or {})[index]
	ns.TabKeysChanged()
	local new = TabKey(index)
	if not old or old == new or old:sub(1, 1) == "#" or new:sub(1, 1) == "#" then return end
	local log = Log()
	if type(log[old]) == "table" and log[new] == nil then log[new], log[old] = log[old], nil end
end
ns.ChatTabKey = TabKey -- (tests)

-- The combat log (the game's second tab, loaded later) keeps its own lines: never touched.
local function IsCombatLogFrame(frame)
	return frame == _G.COMBATLOG or frame == _G.ChatFrame2
end
ns.IsCombatLogFrame = IsCombatLogFrame

-- A private message (sent or received): never kept on disk; the messages window keeps its own, when it is on.
local WHISPERS = { "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM" }
local function IsWhisper(text, r, g, b, id)
	if text:find("|K", 1, true) or text:find("|HBNplayer", 1, true) or text:find("|Hplayer:[^|]*:WHISPER") then return true end
	return ns.IsChatType(WHISPERS, r, g, b, id)
end
ns.IsWhisperLine = IsWhisper -- (tests)

local function Keep(_, index, text, r, g, b, id)
	if restoring or not LogOn() or type(text) ~= "string" or U.IsSecret(text) or text == "" then return end
	if IsWhisper(text, r, g, b, id) then return end
	-- The Wanderer tab (diagnostic mode) is never kept.
	if ns.IsDebugTab(index) then return end
	local log, key = Log(), TabKey(index)
	log[key] = log[key] or {}
	local lines = log[key]
	-- (as it was said: the gold of your name and the guild's brighter words stay in this session)
	lines[#lines + 1] = { ns.Unpainted(text), r, g, b }
	while #lines > LOG_KEPT do table.remove(lines, 1) end
end

-- The log of before this version (by window number): each under its tab's name now, once.
local function KeyByName(log)
	local numbered = {}
	for index in pairs(log) do
		if type(index) == "number" then numbered[#numbered + 1] = index end
	end
	for _, index in ipairs(numbered) do
		local lines, key = log[index], TabKey(index)
		-- (its tab's name not known yet: left by number until it is)
		if key:sub(1, 1) ~= "#" then
			log[index] = nil
			if log[key] == nil and type(lines) == "table" then log[key] = lines end
		end
	end
end

-- The lines of before, back in their tab, under a quiet line.
local function Restore()
	if not LogOn() then return end
	local log = Log()
	KeyByName(log)
	restoring = true
	ns.restoring = true
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame, lines = _G["ChatFrame" .. index], log[TabKey(index)]
		if frame and type(lines) == "table" and lines[1] and frame.AddMessage and not IsCombatLogFrame(frame) then
			-- (private messages kept by an older version: shown no more, let go)
			for at = #lines, 1, -1 do
				local line = lines[at]
				if type(line) ~= "table" or type(line[1]) ~= "string" or IsWhisper(line[1], line[2], line[3], line[4]) then
					table.remove(lines, at)
				end
			end
			if lines[1] then U.Safe(frame.AddMessage, frame, Skin.Colorize(L.CHAT_LOG_BEFORE, "muted")) end
			for _, line in ipairs(lines) do
				local r, g, b = line[2] or 1, line[3] or 1, line[4] or 1
				U.Safe(frame.AddMessage, frame, line[1], r * LOG_DIM, g * LOG_DIM, b * LOG_DIM)
			end
		end
	end
	restoring = false
	ns.restoring = false
end

ns.RestoreChatLog = Restore -- (tests)

local function WatchLog()
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. index]
		if frame and not logged[frame] and frame.AddMessage and not IsCombatLogFrame(frame) then
			logged[frame] = true
			hooksecurefunc(frame, "AddMessage", function(self, text, r, g, b, id)
				Keep(self, index, text, r, g, b, id)
			end)
			-- A tab emptied (/clear, /wanderer clear): the lines it kept go with its content.
			if frame.Clear then hooksecurefunc(frame, "Clear", function() Log()[TabKey(index)] = nil end) end
		end
	end
end

-- Web addresses --------------------------------------------------------------------------

local LINK = "addon:Wanderer:url:" -- (the name links had before the chat moved here: kept, old lines still open)
local LINK_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }

local function LinksOn()
	local settings = Settings()
	return settings and settings.links and true or false
end

-- Each word that is an address becomes a link (its last mark of punctuation stays outside).
local function Linkify(text)
	if type(text) ~= "string" or U.IsSecret(text) or text:find("|H", 1, true) then return text end
	-- (most lines have no address: looked at word by word only when one may be there)
	if not (text:find("://", 1, true) or text:find("www.", 1, true)) then return text end
	return (text:gsub("%S+", function(word)
		if not (word:match("^https?://%S") or word:match("^www%.[%w%-]+%.%a")) then return nil end
		local address, tail = word:match("^(.-)([%.,;:!%?%)]*)$")
		return Skin.Colorize("|H" .. LINK .. address .. "|h[" .. address .. "]|h", "blue") .. tail
	end))
end
ns.Linkify = Linkify -- (tests)

local function LinkFilter(_, _, message, ...)
	if U.IsSecret(message) or not LinksOn() then return false end
	local linked = Linkify(message)
	if linked ~= message then return false, linked, ... end
	return false
end

-- A click on an address: shown ready to copy.
local function OpenLink(link)
	if type(link) ~= "string" or link:sub(1, #LINK) ~= LINK then return end
	Skin.ShowCopy(L.CHAT_LINK_COPY, link:sub(#LINK + 1))
end

local function WatchLinks()
	for _, event in ipairs(LINK_EVENTS) do ns.AddFilter(event, LinkFilter) end
	ns.OnLink(OpenLink)
end
ns.OpenChatLink = OpenLink -- (tests)

-- Web addresses in the guild's windows ------------------------------------------------------
-- The guild's information and its message of the day are shown by the game's
-- own windows, outside the chat: the addresses in what they show become links
-- too (only what is shown: the text kept by the guild never changes).

local GUILD_WINDOWS = { "CommunitiesFrame", "GuildFrame", "GuildInfoFrame" }
local GUILD_ADDONS = { Blizzard_Communities = true, Blizzard_GuildUI = true }
local GUILD_DEPTH = 10 -- frames looked into, at most, under a guild window
local GUILD_AGAIN = 0.5 -- seconds: the game fills its texts just after showing them
local listening = setmetatable({}, { __mode = "k" }) -- frame -> its links answer clicks

local function HearClicks(frame)
	if listening[frame] or not frame.HookScript then return end
	listening[frame] = true
	if frame.SetHyperlinksEnabled then pcall(frame.SetHyperlinksEnabled, frame, true) end
	pcall(frame.HookScript, frame, "OnHyperlinkClick", function(_, link) OpenLink(link) end)
end

-- Every text of a frame and of its children: its addresses made links. Returns how many texts.
local function LinkTexts(frame, depth)
	if depth > GUILD_DEPTH or not frame.GetRegions or (frame.IsForbidden and frame:IsForbidden()) then return 0 end
	local count = 0
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
			local text = U.Clean(region:GetText())
			if text and (text:find("https?://") or text:find("www%.")) then
				local linked = Linkify(text)
				if linked ~= text then
					region:SetText(linked)
					HearClicks(frame)
					count = count + 1
				end
			end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do count = count + LinkTexts(child, depth + 1) end
	return count
end

local function LinkGuildWindows()
	if not LinksOn() then return end
	for _, name in ipairs(GUILD_WINDOWS) do
		local window = _G[name]
		if window and window.IsShown and window:IsShown() then
			LinkTexts(window, 1)
		end
	end
end
ns.LinkGuildWindows = LinkGuildWindows -- (tests)

local function WatchGuildWindows()
	local hooked = {}
	local function Hook()
		for _, name in ipairs(GUILD_WINDOWS) do
			local window = _G[name]
			if window and not hooked[window] and window.HookScript then
				hooked[window] = true
				window:HookScript("OnShow", function()
					LinkGuildWindows()
					C_Timer.After(GUILD_AGAIN, LinkGuildWindows)
				end)
			end
		end
	end
	Hook()
	local linkSoon = U.Debounce(GUILD_AGAIN, LinkGuildWindows)
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("GUILD_MOTD")
	events:RegisterEvent("GUILD_ROSTER_UPDATE")
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if GUILD_ADDONS[name] then Hook() end
			return
		end
		-- The game filled the guild's texts again: their links again (once for a burst).
		linkSoon()
	end)
end

-- The copy button of a chat frame.
local function Button(frame)
	if buttons[frame] then return buttons[frame] end
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
	button:SetFrameLevel(frame:GetFrameLevel() + 10)
	-- (the kit's grid glyph, gold under the mouse: the note icon stays for your notes on players)
	local icon = Skin.Glyph(button, "grid", BUTTON_SIZE - 4)
	icon:SetPoint("CENTER")
	button:HookScript("OnEnter", function() Skin.GlyphOn(icon, "grid") end)
	button:HookScript("OnLeave", function()
		local c = Skin.COLORS.label
		icon:SetVertexColor(c[1], c[2], c[3])
	end)
	button:SetScript("OnClick", function() W.CopyChat(frame) end)
	Skin.Tooltip(button, { L.COPY_TITLE, L.CHAT_COPY_BUTTON_TIP }, "ANCHOR_TOPLEFT")
	-- Beside it, the search of the same lines (Search.lua): shown and faded with it.
	local search = CreateFrame("Button", nil, button)
	search:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	search:SetPoint("RIGHT", button, "LEFT", -2, 0)
	search.icon = search:CreateTexture(nil, "ARTWORK")
	search.icon:SetSize(BUTTON_SIZE - 6, BUTTON_SIZE - 6)
	search.icon:SetPoint("CENTER")
	search.icon:SetTexture(SEARCH_ICON)
	local function Tint(role)
		local c = Skin.COLORS[role]
		search.icon:SetVertexColor(c[1], c[2], c[3])
	end
	Tint("label")
	search:HookScript("OnEnter", function() Tint("gold") end)
	search:HookScript("OnLeave", function() Tint("label") end)
	search:SetScript("OnClick", function() ns.OpenSearch(frame) end)
	Skin.Tooltip(search, { L.SEARCH_TITLE, L.SEARCH_TIP }, "ANCHOR_TOPLEFT")
	button.search = search
	button:SetAlpha(0)
	button:Hide()
	button.tween = U.Tween(0)
	buttons[frame] = button
	return button
end

-- (another addon bringing your messages back with the arrows, Prat or Chattynator: its own way, not two)
local function ArrowsOn()
	local settings = Settings()
	return settings and settings.arrowHistory and not ns.Yields("chatHistory") and true or false
end

-- Up: one message further back; Down: one closer, then your text again.
local function Browse(box, key)
	if not ArrowsOn() or (key ~= "UP" and key ~= "DOWN") then return end
	local history = History()
	if not history[1] then return end
	local state = browsing[box]
	if key == "UP" then
		if not state then
			state = { index = #history + 1, draft = box:GetText() or "" }
			browsing[box] = state
		end
		state.index = math.max(1, state.index - 1)
	else
		if not state then return end
		state.index = state.index + 1
	end
	local text = history[state.index]
	if not text then
		text = state.draft
		browsing[box] = nil
	end
	box.wandererSetting = true
	box:SetText(text)
	box.wandererSetting = nil
	if box.SetCursorPosition then box:SetCursorPosition(#text) end
end

local function Watch()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then Button(frame) end
	end
	for _, box in ipairs(EditBoxes()) do
		if not boxes[box] and box.AddHistoryLine then
			boxes[box] = true
			hooksecurefunc(box, "AddHistoryLine", function(self, text)
				Remember(text)
				browsing[self] = nil
			end)
			box:HookScript("OnArrowPressed", Browse)
			box:HookScript("OnEditFocusGained", function(self)
				browsing[self] = nil
				-- The arrows to the box while you type (asked again each time: never lost).
				if ArrowsOn() and self.SetAltArrowKeyMode then U.Safe(self.SetAltArrowKeyMode, self, false) end
			end)
			box:HookScript("OnEditFocusLost", function(self) browsing[self] = nil end)
			box:HookScript("OnTextChanged", function(self, userInput)
				if userInput and not self.wandererSetting then browsing[self] = nil end
			end)
		end
	end
end

local arrowsApplied = false -- the arrows set here (else they are the game's or another addon's)

-- One size for the text of every chat window -----------------------------------------------
-- The game sets it window by window (right click on a tab): here once for all,
-- new windows included, only when you chose a size (the slider's lowest step
-- leaves the game's own). Each window's size before is kept (per character) and
-- given back when you return to the game's size or turn the chat's options off.

local function ChatWindows()
	local list = {}
	for index = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. index]
		if frame then list[#list + 1] = { index = index, frame = frame } end
	end
	-- Whisper windows the game opened apart.
	for _, name in ipairs(type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}) do
		local frame = _G[name]
		local index = frame and frame.GetID and frame:GetID()
		if index and index > (NUM_CHAT_WINDOWS or 10) then list[#list + 1] = { index = index, frame = frame } end
	end
	return list
end

local function SizeOf(window)
	local _, size = U.Safe(GetChatWindowInfo, window.index)
	size = U.Clean(size)
	if size then return size end
	if not window.frame.GetFont then return end
	local _, height = window.frame:GetFont()
	return height and math.floor(height + 0.5)
end

local function SetSize(window, size)
	if FCF_SetChatWindowFontSize then
		U.Safe(FCF_SetChatWindowFontSize, nil, window.frame, size)
	elseif window.frame.GetFont then
		local font, _, flags = window.frame:GetFont()
		if font then window.frame:SetFont(font, size, flags) end
		if SetChatWindowSize then U.Safe(SetChatWindowSize, window.index, size) end
	end
end

local function FontSizes()
	local db = ns.DB()
	local before = type(db.fontBefore) == "table" and db.fontBefore or {}
	local settings = Settings()
	local size = settings and settings.fontSize
	if size and size <= ns.GAME_SIZE then size = nil end
	if size then
		for _, window in ipairs(ChatWindows()) do
			local current = SizeOf(window)
			if before[window.index] == nil and current then before[window.index] = current end
			if current ~= size then SetSize(window, size) end
		end
		db.fontBefore = before
	elseif next(before) then
		-- The game's size again (or the chat's options off): each window as it was.
		for _, window in ipairs(ChatWindows()) do
			local old = before[window.index]
			if old and SizeOf(window) ~= old then SetSize(window, old) end
		end
		db.fontBefore = nil
	end
end
ns.ApplyFontSize = FontSizes

function ns.RefreshComfort()
	FontSizes()
	Watch()
	local settings = Settings()
	local arrows = ArrowsOn()
	if arrows or arrowsApplied then
		for _, box in ipairs(EditBoxes()) do
			if box.SetAltArrowKeyMode then U.Safe(box.SetAltArrowKeyMode, box, not arrows) end
		end
	end
	arrowsApplied = arrows
	local copy = settings and settings.copyButton and true or false
	for _, button in pairs(buttons) do
		if not copy then
			button.tween:Set(0)
			button:SetAlpha(0)
			button:Hide()
		end
		button.enabled = copy
	end
end

function ns.InitComfort()
	-- A window opened later (a whisper apart, a new tab): at the same size.
	if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() FontSizes() end) end
	if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() FontSizes() end) end
	-- A tab renamed: its kept lines follow it.
	if _G.FCF_SetWindowName then
		hooksecurefunc("FCF_SetWindowName", function(frame)
			local index = type(frame) == "table" and frame.GetID and frame:GetID()
			if type(index) == "number" and index > 0 then ns.TabRenamed(index) end
		end)
	end
	-- The lines of before first, then every new one kept.
	Restore()
	WatchLog()
	WatchLinks()
	WatchGuildWindows()
	Watch()
	ns.RefreshComfort()
	local since, awake = 0, false
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		local check = since >= CHECK_EVERY
		if check then since = 0 end
		-- (between two checks, only while a button shows or fades: else every one sleeps)
		if not (check or awake) then return end
		awake = false
		for frame, button in pairs(buttons) do
			if check then
				button.wanted = button.enabled and frame:IsVisible() and (U.IsMouseOver(frame) or U.IsMouseOver(button)) and 1 or 0
			end
			local wanted = button.wanted or 0
			-- (asleep and wanted asleep: nothing to do)
			if wanted > 0 or button:IsShown() then
				if wanted > 0 and not button:IsShown() then button:Show() end
				local alpha = button.tween:Step(wanted, elapsed, FADE_IN, FADE_OUT)
				if alpha ~= button:GetAlpha() then button:SetAlpha(alpha) end
				if alpha <= 0 and wanted == 0 then button:Hide() else awake = true end
			end
		end
	end)
end
