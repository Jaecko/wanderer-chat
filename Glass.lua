local _, ns = ...
local L = ns.L

-- The chat in glass (the chat display "Glass", the default): the game's own chat, its engine whole (its windows,
-- links, commands, history, other addons' filters), only dressed.
-- * At rest: no frame, no tabs, no buttons. Each line still shown lies on a light dark veil that fades out to the
--   right, and goes after a while (20 s by default, a choice; a line naming you stays a minute), in 3 s.
-- * The mouse over the chat, or writing: a quiet ground behind it all, the tabs as plain words (the one shown in
--   gold and underlined, the others muted, their counts in gold), a thin scroll bar; gone again 1.5 s after.
--   Gone up in the lines: "2 new" (or "Back to the latest") at the foot, a click comes back down.
-- * Each line read at a glance: "21:04  G  Lysa  text". The hour in a fixed column (when the game's own option
--   shows the times), the chat as one letter in its color (a public channel: its number), the name as the game
--   colors it, then the words in a neutral light. Every line keeps its letter and its name (each fades on its
--   own).
-- * What concerns you: a line naming you has a thin gold edge and a light gold tint, a whisper a violet edge; a
--   whisper not answered yet waits in one small line above the chat (Reply, or dismiss it); the guild's message
--   of the day, once, quietly.
-- How lines are rewritten, safely: the game builds each line and adds it to its window; just after (a hook that
-- never changes what the game does), the line kept in the window's history gets its new words, before it is ever
-- drawn. Nothing of the game's is replaced: no format string, no AddMessage of ours, no filter changing who said
-- it. A secret line (the game's, during a fight) is never read: it stays as the game made it, as does any line
-- not understood (another addon's format).
-- A window taken apart and the combat log keep the game's look. Off, or another addon dressing the chat
-- (ElvUI, Prat, Chattynator): every piece back exactly as it was, the rewritten lines given their words back.
-- Also here: shorter channel names ("[2. Trade - City]" as "[2. Trade]") for the game's own look, a filter.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

-- The look (the approved "Glass" values).
local INK = { 0.055, 0.059, 0.071 } -- #0E0F12
local WORDS = { 0.91, 0.894, 0.855 } -- #E8E4DA, the words of a line
local VIOLET = { 0.886, 0.545, 0.91 } -- #E28BE8, a whisper's edge
local GOLD = Skin.COLORS.gold
local TAB_HOVER = { 1, 1, 1 }
local TAB_WORDS = { 0.96, 0.95, 0.92 } -- a tab not shown: soft, still readable on the ground
-- (the palette's muted, as a color code: the hour and the quiet words)
local MUTED = Skin.COLORS.muted or Skin.COLORS.text
local MUTED_HEX = U.ColorCode(MUTED[1], MUTED[2], MUTED[3])
local VEIL, VEIL_SOLID = 0.45, 0.55 -- the veil at rest: its darkness under the words, the part of the width before it fades
local GROUND = 0.55 -- the ground under the mouse
local BOX_GROUND = 0.85
local TINT = 0.1 -- a line naming you
local EDGE = 2
local MARGIN = 8 -- around the lines (the 8 px rhythm)
local TAB_ROOM = 24 -- the tabs' row above the lines
local BOX_HEIGHT = 26
local TIME_COLUMN = 36
local TAG_ROOM = 8 -- after the letter's column
local NAME_ROOM = 6 -- after the name
local NAMED_HOLD = 60 -- seconds a line naming you stays
local FADE_TIME = 3
local HOVER_IN, HOVER_OUT, LINGER = 0.15, 0.3, 1.5
local CHECK, SYNC_EVERY = 0.1, 1
local LOG_DIM = 0.7 -- the lines of before (Comfort.lua), dimmed as they were
local BLANK = "Interface\\AddOns\\WandererChat\\Media\\Blank"

-- The game's pieces taken off: the window's frame, the tabs' art, the line's art.
local FRAME_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft",
	"HighlightMiddle", "HighlightRight", "glow" }
local BOX_ART = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }
local SCROLL_PARTS = { "ScrollBar", "ScrollToBottomButton" }
-- The game's chat buttons (whichever this game has, and the private messages' own): shown with the tabs.
local GAME_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton", "FriendsMicroButton",
	"ChatFrameSocialButton", "TextToSpeechButtonFrame", "WandererChatWhisperButton" }

-- The chats a line can come from, by the group its player link names (the game's own categories).
local GROUPS = { SAY = { "SAY" }, YELL = { "YELL" }, GUILD = { "GUILD" }, OFFICER = { "OFFICER" },
	PARTY = { "PARTY", "PARTY_LEADER" }, RAID = { "RAID", "RAID_LEADER", "RAID_WARNING" },
	INSTANCE_CHAT = { "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }, WHISPER = { "WHISPER", "WHISPER_INFORM" },
	CHANNEL = { "CHANNEL" }, BN = { "BN_WHISPER", "BN_WHISPER_INFORM" } }
local EVERY = { "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
	"INSTANCE_CHAT_LEADER", "WHISPER", "WHISPER_INFORM", "SAY", "YELL", "CHANNEL" }
-- Each chat's letter (its text key) and its family (the leader's words are the group's).
local TAGS = { GUILD = "GUILD", OFFICER = "OFFICER", PARTY = "PARTY", PARTY_LEADER = "PARTY", RAID = "RAID",
	RAID_LEADER = "RAID", RAID_WARNING = "RAID", INSTANCE_CHAT = "INSTANCE", INSTANCE_CHAT_LEADER = "INSTANCE",
	WHISPER = "WHISPER", WHISPER_INFORM = "WHISPER", BN_WHISPER = "WHISPER", BN_WHISPER_INFORM = "WHISPER",
	SAY = "SAY", YELL = "YELL" }
local INFORM = { WHISPER_INFORM = true, BN_WHISPER_INFORM = true }
local TAG_KEYS = { "GUILD", "OFFICER", "PARTY", "RAID", "INSTANCE", "WHISPER", "SAY", "YELL" }

local active, waiting = false, false
local hidden, under, over, holder, pin, marker, bar
local parents = {} -- a piece taken off -> its parent
local dressed = {} -- chat window -> what it was: { fading, time, duration } (its lines rewritten unless the combat log's)
local tabs, styled = {}, {} -- tab -> { text, line, color }; -> true while dressed
local boxes = {} -- edit box -> { ground, accent, header, font, headerPoints, points, height, on }
local carried = {} -- game button -> its parent
local hooked = {} -- chat window -> its lines heard
local originals = setmetatable({}, { __mode = "k" }) -- a history line rewritten -> { message, r, g, b, timestamp }
local unseen = {} -- chat window -> lines come while you were up in them
local decor = {} -- a line drawn -> its veil, edge and tint
local decorFrame -- the window whose lines are dressed now
local visited = {} -- (each drawing: the veils of the lines listed now)
local combatInFront = false -- the combat log is the tab shown
local Writing -- (below: whether you write in the chat now)
local dockAlpha
local hover = U and U.Tween(0)
local shownHover, lastNear = 0, -math.huge

local function Round(value) return math.floor((tonumber(value) or 0) + 0.5) end

-- Pieces ---------------------------------------------------------------------------------------------------------

local function Points(region)
	local list = {}
	for index = 1, (region.GetNumPoints and region:GetNumPoints()) or 0 do
		local point, relative, relativePoint, x, y = region:GetPoint(index)
		if point then list[#list + 1] = { point, relative, relativePoint, x, y } end
	end
	return list
end

local function PutPoints(region, list)
	region:ClearAllPoints()
	for _, each in ipairs(list or {}) do pcall(region.SetPoint, region, each[1], each[2], each[3], each[4], each[5]) end
end

-- A piece of the game's taken off (under a hidden frame: whatever the game shows or fades, it stays unseen), and
-- put back.
local function Tuck(region)
	if type(region) ~= "table" or parents[region] or not region.SetParent then return end
	parents[region] = region:GetParent() or UIParent
	region:SetParent(hidden)
end

local function Untuck(region)
	if type(region) ~= "table" or not parents[region] then return end
	region:SetParent(parents[region])
	parents[region] = nil
end

local function Art()
	return type(_G.CHAT_FRAME_TEXTURES) == "table" and _G.CHAT_FRAME_TEXTURES or FRAME_ART
end

-- The window shown in the dock.
local function Selected()
	local dock, get = _G.GENERAL_CHAT_DOCK, _G.FCFDock_GetSelectedWindow
	local frame = dock and get and Safe(get, dock)
	return frame or SELECTED_DOCK_FRAME or DEFAULT_CHAT_FRAME
end

-- Every chat window (the game's ten, the whispers apart).
local function Windows()
	local list, seen = {}, {}
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. index]
		if type(frame) == "table" and frame.GetName then list[#list + 1], seen[frame] = frame, true end
	end
	for _, name in ipairs(type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetName and not seen[frame] then list[#list + 1], seen[frame] = frame, true end
	end
	return list
end

local function Docked(frame) return frame == ChatFrame1 or (frame.isDocked and true or false) end

-- Never a protected piece in a fight (the chat's are not, in this game: in case one is, it waits).
local function Blocked()
	if not InCombatLockdown() then return false end
	for _, frame in ipairs({ ChatFrame1, ChatFrame1EditBox, GeneralDockManager }) do
		if type(frame) == "table" and frame.IsProtected and frame:IsProtected() then return true end
	end
	return false
end

-- A chat's color ("GUILD", "CHANNEL2") as a color code, nil when the game does not say it.
local function TypeHex(chatType)
	local r, g, b = ns.ChatColor(chatType)
	return r and U.ColorCode(r, g, b) or nil
end

-- Widths -----------------------------------------------------------------------------------------------------------
-- Columns stay straight in a font whose letters differ in width: each word is measured once in the window's own
-- font, and a clear space of the exact width the rest needs follows it.

local measurers = {} -- chat window -> its hidden ruler
local widths, widthCount = {}, 0 -- "font size flags" -> { text -> width }

local function Width(frame, text)
	local font, size, flags = Safe(frame.GetFont, frame)
	if type(font) ~= "string" or type(size) ~= "number" then return #text * 6 end
	local key = font .. size .. tostring(flags)
	local cache = widths[key]
	if not cache then
		cache = {}
		widths[key] = cache
	end
	local width = cache[text]
	if width then return width end
	local ruler = measurers[frame]
	if not ruler then
		ruler = frame:CreateFontString(nil, "BACKGROUND")
		ruler:SetAlpha(0)
		ruler:SetPoint("TOPLEFT", frame, "TOPLEFT")
		measurers[frame] = ruler
	end
	pcall(ruler.SetFont, ruler, font, size, flags)
	ruler:SetText(text)
	width = U.Measure(ruler, "GetStringWidth", #text * 6)
	ruler:SetText("")
	-- (a long session in Trade: the names measured, a few hundred at most)
	if widthCount > 600 then
		wipe(widths)
		widthCount = 0
		widths[key] = cache
		wipe(cache)
	end
	cache[text], widthCount = width, widthCount + 1
	return width
end

-- A clear space this wide: a real space (the copy reads it), then an invisible mark for the rest.
local function Space(frame, width)
	local rest = Round(width - Width(frame, " "))
	if rest <= 0 then return " " end
	return " |T" .. BLANK .. ":1:" .. rest .. "|t"
end

-- Each chat's letter in this game's language.
local function Tag(key) return L["GLASS_TAG_" .. key] or key:sub(1, 1) end

-- The letters' column: as wide as the widest letter (or channel number), then its room.
local function TagColumn(frame)
	local widest = Width(frame, "88")
	for _, key in ipairs(TAG_KEYS) do widest = math.max(widest, Width(frame, Tag(key))) end
	return widest + TAG_ROOM
end

-- The hour's column, or "" when the game's own option shows no times.
local timesAt, timesFormat = -math.huge, nil
local function TimesFormat()
	if GetTime() - timesAt >= 1 then
		timesAt = GetTime()
		local value = Clean(Safe(GetCVar, "showTimestamps"))
		timesFormat = (type(value) == "string" and value ~= "none") and strtrim(value) or nil
		if timesFormat == "" then timesFormat = nil end
	end
	return timesFormat
end
ns.GlassTimesFormat = function() timesAt = -math.huge return TimesFormat() end -- (the option, tests)

-- The game's own hour at the start of a line ("21:04 "), as written with this format, else nil.
local stampPatterns = {}
local function StampPattern(format)
	if type(format) ~= "string" or format == "none" or format == "" then return nil end
	local pattern = stampPatterns[format]
	if pattern then return pattern end
	pattern = format:gsub("%%(.)", function(code)
		if code == "H" or code == "I" or code == "k" or code == "l" then return "\1" end
		if code == "M" or code == "S" then return "\2" end
		if code == "p" then return "\3" end
		return "\4"
	end)
	pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("\1", " ?%%d%%d?"):gsub("\2", "%%d%%d"):gsub("\3", "[^%%s|]+"):gsub("\4", "[^|]-")
	stampPatterns[format] = "^" .. pattern
	return stampPatterns[format]
end

local function Stamp(text)
	for _, format in ipairs({ _G.CHAT_TIMESTAMP_FORMAT, Clean(Safe(GetCVar, "showTimestamps")) }) do
		local pattern = StampPattern(format)
		if pattern then
			local stamp = text:match(pattern)
			if stamp then return strtrim(stamp), text:sub(#stamp + 1) end
			-- (in a color of its own)
			local colored = text:match("^|c%x%x%x%x%x%x%x%x(.-)|r")
			if colored and colored:match(pattern .. "$") then
				return strtrim(colored), text:sub(#colored + 13)
			end
		end
	end
	return nil, text
end

local function TimeColumn(frame, stamp)
	local format = TimesFormat()
	if not format then return "" end
	-- (the lines of before keep their own hour)
	local hour = (ns.restoring and stamp) or Clean(Safe(date, format)) or stamp
	if not hour then return "" end
	hour = strtrim(hour)
	local width = math.max(TIME_COLUMN, Width(frame, hour) + MARGIN)
	return MUTED_HEX .. hour .. "|r" .. Space(frame, width - Width(frame, hour))
end

-- Reading a line --------------------------------------------------------------------------------------------------

-- A chat's words around the name ("|Hchannel:GUILD|h[Guild]|h ", ": "), from the game's own, nil when unknown.
local function Around(chatType)
	local format = _G["CHAT_" .. (chatType:match("^CHANNEL") and "CHANNEL" or chatType) .. "_GET"]
	if type(format) ~= "string" then return nil end
	local at = format:find("%s", 1, true)
	if not at then return nil end
	return format:sub(1, at - 1), format:sub(at + 2)
end

-- What came before the name holds this chat's words, then only the game's mark of someone away or busy.
local function Fits(chatType, before, after)
	local pre, post = Around(chatType)
	if not pre or after:sub(1, #post) ~= post then return nil end
	local channel = ""
	if chatType:match("^CHANNEL") then
		channel = before:match("^|Hchannel:[^|]*|h[^|]*|h ?")
		if not channel then return nil end
	end
	if before:sub(#channel + 1, #channel + #pre) ~= pre then return nil end
	local flag = before:sub(#channel + #pre + 1)
	if flag:find("|H", 1, true) or #flag > 160 then return nil end
	return flag, after:sub(#post + 1), channel, pre
end

-- The chat of an id the game gave with the line ("GUILD", "CHANNEL2"), nil when unknown.
local byID, byIDCount = {}, -1
local function TypeOfID(id)
	if type(id) ~= "number" or type(ChatTypeInfo) ~= "table" then return nil end
	if byID[id] == nil then
		-- (read again when the game adds chats: a channel joined)
		local count = 0
		for _ in pairs(ChatTypeInfo) do count = count + 1 end
		if count ~= byIDCount then
			byIDCount = count
			wipe(byID)
			for chatType, info in pairs(ChatTypeInfo) do
				if type(info) == "table" and type(info.id) == "number" then byID[info.id] = chatType end
			end
		end
	end
	return byID[id]
end

-- The first player link of a line: where it starts and ends, what it points to, what it shows.
local function PlayerLink(text)
	local plain, battleNet = text:find("|Hplayer:", 1, true), text:find("|HBNplayer:", 1, true)
	local from = plain and battleNet and math.min(plain, battleNet) or plain or battleNet
	if not from then return nil end
	local targetEnd = text:find("|h", from + 2, true)
	local close = targetEnd and text:find("|h", targetEnd + 2, true)
	if not close then return nil end
	return from, close + 1, text:sub(from + 2, targetEnd - 1), text:sub(targetEnd + 2, close - 1)
end

-- A line as the game wrote it, read: { chatType, number, flag, target, display, message, pre }, else nil.
local function Read(rest, id)
	local from, to, target, display = PlayerLink(rest)
	if not from then return nil end
	local before, after = rest:sub(1, from - 1), rest:sub(to + 1)
	local candidates
	if target:sub(1, 9) == "BNplayer:" then
		candidates = GROUPS.BN
	else
		local group = target:match("^player:[^:]*:[^:]*:([^:]*)")
		candidates = GROUPS[group or ""] or EVERY
	end
	local known = TypeOfID(id)
	local number
	if known and known:match("^CHANNEL%d") then known, number = "CHANNEL", known:match("(%d+)$") end
	local list = candidates
	if known then list = { known } for _, each in ipairs(candidates) do if each ~= known then list[#list + 1] = each end end end
	for _, chatType in ipairs(list) do
		if chatType ~= "CHANNEL" or before:find("|Hchannel:", 1, true) then
			local flag, message, channel, pre = Fits(chatType, before, after)
			if flag then
				if chatType == "CHANNEL" then number = channel:match("^|Hchannel:%a+:(%d+)") or number end
				return { chatType = chatType, number = number, flag = flag, target = target,
					display = display:match("^%[(.*)%]$") or display, message = message, pre = pre }
			end
		end
	end
	return nil
end
ns.GlassRead = Read -- (tests)

-- Writing it again ------------------------------------------------------------------------------------------------

-- The guild's message of the day, as the game writes it.
local motdPattern
local motdShown = {} -- this session: message -> true

-- A line as Glass shows it: its new words, its kind ("player", "motd", "drop") and who said it (for the lines
-- together), or nil to leave it as the game made it.
local function Rewrite(frame, text, id)
	local stamp, rest = Stamp(text)
	local column = TimeColumn(frame, stamp)
	local line = Read(rest, id)
	if not line then
		local motd = motdPattern and rest:match(motdPattern)
		if motd and motd ~= "" then
			-- (one kept from before, back with the old lines: not news, the guild's own comes after)
			if ns.restoring then return nil, "drop" end
			local db = ns.DB()
			-- (once: the same message again, at the next login or in a second tab, goes)
			if motdShown[motd] or db.glassMotd == motd then
				motdShown[motd] = true
				return nil, "drop"
			end
			motdShown[motd], db.glassMotd = true, motd
			local hex = TypeHex("GUILD") or MUTED_HEX
			local width = TagColumn(frame)
			local tag = Tag("GUILD")
			return column .. hex .. tag .. "|r" .. Space(frame, width - Width(frame, tag)) .. MUTED_HEX .. L.GLASS_MOTD
				.. "|r" .. Space(frame, NAME_ROOM) .. motd, "motd"
		end
		-- (a line of the game's, the system's, an addon's: the hour in its column, the words as they were)
		if column ~= "" and stamp then return column .. rest, "plain" end
		return nil
	end
	local chatType = line.chatType
	local colorType = chatType == "CHANNEL" and line.number and ("CHANNEL" .. line.number) or chatType
	local hex = TypeHex(colorType) or TypeHex(chatType) or MUTED_HEX
	local tag = chatType == "CHANNEL" and (line.number or "#") or Tag(TAGS[chatType] or "SAY")
	local name = line.display
	if not name:find("^|c") and not name:find("^|K") then name = hex .. name .. "|r" end
	local head = line.flag .. "|H" .. line.target .. "|h" .. name .. "|h"
	if INFORM[chatType] then head = MUTED_HEX .. strtrim(line.pre) .. "|r " .. head end
	local width = TagColumn(frame)
	-- (every line keeps its letter and its name: a line fades on its own, the one above it may be gone)
	return column .. hex .. tag .. "|r" .. Space(frame, width - Width(frame, tag)) .. head .. Space(frame, NAME_ROOM)
		.. line.message, "player"
end

-- The line just added to a window's history (its newest), when it holds these words.
local function Newest(frame, text)
	local buffer = frame.historyBuffer
	if type(buffer) ~= "table" or not buffer.GetEntryAtIndex then return nil end
	local entry = Safe(buffer.GetEntryAtIndex, buffer, 1)
	if type(entry) ~= "table" or U.IsSecret(entry.message) or entry.message ~= text then return nil end
	return entry
end

local function Dirty(frame)
	if frame.MarkDisplayDirty then Safe(frame.MarkDisplayDirty, frame) end
end

-- A line added to a window of the chat: its words again, before it is drawn.
local function Added(frame, text, _, _, _, id)
	if not (active and dressed[frame] and not dressed[frame].combat) then return end
	if type(text) ~= "string" or U.IsSecret(text) then return end
	-- (gone up in the lines: one more to come back to)
	local offset = Clean(Safe(frame.GetScrollOffset, frame))
	if type(offset) == "number" and offset > 0 then unseen[frame] = (unseen[frame] or 0) + 1 end
	local entry = Newest(frame, text)
	if not entry then return end
	local new, kind = Rewrite(frame, text, id)
	if kind == "drop" then
		if frame.RemoveMessagesByPredicate then Safe(frame.RemoveMessagesByPredicate, frame, function(each) return each == entry end) end
		return
	end
	if not new then return end
	originals[entry] = { message = entry.message, r = entry.r, g = entry.g, b = entry.b, timestamp = entry.timestamp }
	entry.message = new
	if kind == "player" then
		local dim = ns.restoring and LOG_DIM or 1
		entry.r, entry.g, entry.b = WORDS[1] * dim, WORDS[2] * dim, WORDS[3] * dim
		-- A line naming you stays a minute.
		local fading, visible = Safe(frame.GetFading, frame), Clean(Safe(frame.GetTimeVisible, frame))
		if fading and type(visible) == "number" and visible < NAMED_HOLD and type(entry.timestamp) == "number"
			and ns.NAMED_COLOR and new:find(ns.NAMED_COLOR, 1, true) then
			entry.timestamp = entry.timestamp + NAMED_HOLD - visible
		end
	end
	Dirty(frame)
end

-- Every line rewritten given its words back.
local function GiveWordsBack()
	for entry, was in pairs(originals) do
		entry.message, entry.r, entry.g, entry.b, entry.timestamp = was.message, was.r, was.g, was.b, was.timestamp
	end
	wipe(originals)
	for _, frame in ipairs(Windows()) do Dirty(frame) end
end

-- The tabs --------------------------------------------------------------------------------------------------------

local function FrameOfTab(tab)
	local name = tab.GetName and tab:GetName()
	return name and _G[(name:gsub("Tab$", ""))] or nil
end

-- Plain words: gold and underlined for the one shown, muted for the others (a little lighter under the mouse).
local function Paint(tab, hovered)
	local state = tabs[tab]
	if not (state and state.text and styled[tab]) then return end
	local selected = FrameOfTab(tab) == Selected()
	-- (light words on the dark ground, a shadow under them: the tab shown in gold, the others a soft light, full
	-- light under the mouse; the game dims the tabs themselves already)
	local c = selected and GOLD or (hovered and TAB_HOVER or TAB_WORDS)
	state.text:SetTextColor(c[1], c[2], c[3])
	state.text:SetShadowOffset(1, -1)
	state.text:SetShadowColor(0, 0, 0, 1)
	if state.line then state.line:SetShown(selected) end
end

local function StyleTab(tab)
	if type(tab) ~= "table" or styled[tab] then return end
	for _, key in ipairs(TAB_ART) do Tuck(tab[key]) end
	Tuck(_G[(tab:GetName() or "") .. "Flash"])
	local state = tabs[tab]
	if not state then
		state = {}
		local text = tab.Text
		if type(text) ~= "table" then text = tab.GetFontString and tab:GetFontString() end
		state.text = type(text) == "table" and text or nil
		if state.text then
			local line = tab:CreateTexture(nil, "OVERLAY")
			line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
			line:SetHeight(EDGE)
			line:SetPoint("TOPLEFT", state.text, "BOTTOMLEFT", 0, -3)
			line:SetPoint("TOPRIGHT", state.text, "BOTTOMRIGHT", 0, -3)
			line:Hide()
			state.line = line
			state.plate = tab:CreateTexture(nil, "BACKGROUND")
			state.plate:SetColorTexture(INK[1], INK[2], INK[3], 1)
			state.plate:SetPoint("TOPLEFT", state.text, "TOPLEFT", -6, 3)
			state.plate:SetPoint("BOTTOMRIGHT", state.text, "BOTTOMRIGHT", 6, -4)
			state.plate:SetAlpha(0)
		end
		tab:HookScript("OnEnter", function(self) Paint(self, true) end)
		tab:HookScript("OnLeave", function(self) Paint(self) end)
		tabs[tab] = state
	end
	if state.text then
		state.color = { state.text:GetTextColor() }
		local x, y = state.text:GetShadowOffset()
		state.shadow = { x, y, state.text:GetShadowColor() }
	end
	styled[tab] = true
	Paint(tab)
end

local function UnstyleTab(tab)
	if type(tab) ~= "table" or not styled[tab] then return end
	styled[tab] = nil
	for _, key in ipairs(TAB_ART) do Untuck(tab[key]) end
	Untuck(_G[(tab:GetName() or "") .. "Flash"])
	local state = tabs[tab]
	state.alpha = nil
	for _, part in ipairs({ state.text, state.line }) do
		if part.SetIgnoreParentAlpha then part:SetIgnoreParentAlpha(false) end
		part:SetAlpha(1)
	end
	if state.plate then state.plate:SetAlpha(0) end
	if state.line then state.line:Hide() end
	if state.text and state.color and state.color[1] then state.text:SetTextColor(unpack(state.color)) end
	local shadow = state.text and state.shadow
	if shadow and shadow[1] then
		state.text:SetShadowOffset(shadow[1], shadow[2])
		if shadow[3] then state.text:SetShadowColor(shadow[3], shadow[4], shadow[5], shadow[6]) end
	end
end

-- The line to write in ----------------------------------------------------------------------------------------------

-- Where the line goes, in small capitals in that chat's color (the game's own words and color), the text after it.
local function DressHeader(box)
	local state = boxes[box]
	if not (state and state.on and state.header) then return end
	local header = state.header
	local text = header:GetText()
	if type(text) == "string" and not U.IsSecret(text) then
		local upper = U.Upper(text)
		if upper ~= text then header:SetText(upper) end
	end
	header:ClearAllPoints()
	header:SetPoint("LEFT", box, "LEFT", MARGIN, 0)
	local width = header:IsShown() and U.Measure(header, "GetStringWidth", 0) or 0
	local suffix = box.headerSuffix or _G[(box:GetName() or "") .. "HeaderSuffix"]
	if type(suffix) == "table" and suffix.IsShown and suffix:IsShown() then width = width + U.Measure(suffix, "GetStringWidth", 0) end
	if box.SetTextInsets then pcall(box.SetTextInsets, box, MARGIN + width + (width > 0 and MARGIN or 0), MARGIN, 0, 0) end
end

-- Its band only while you write in it (a line the game always shows stays bare at rest).
local function Focus(box, on)
	local state = boxes[box]
	if not state then return end
	on = state.on and on and true or false
	state.ground:SetShown(on)
	state.accent:SetShown(on)
end

local function StyleBox(box)
	if type(box) ~= "table" or (boxes[box] and boxes[box].on) then return end
	local name = box:GetName() or ""
	for _, key in ipairs(BOX_ART) do Tuck(_G[name .. key]) end
	local state = boxes[box]
	if not state then
		state = {}
		state.ground = box:CreateTexture(nil, "BACKGROUND", nil, -6)
		state.ground:SetAllPoints()
		state.ground:SetColorTexture(INK[1], INK[2], INK[3], BOX_GROUND)
		state.accent = box:CreateTexture(nil, "BORDER")
		state.accent:SetPoint("TOPLEFT")
		state.accent:SetPoint("TOPRIGHT")
		state.accent:SetHeight(1)
		state.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
		state.header = box.header or _G[name .. "Header"]
		if state.header and state.header.GetFontObject then state.font = state.header:GetFontObject() end
		if box.UpdateHeader then hooksecurefunc(box, "UpdateHeader", DressHeader) end
		box:HookScript("OnEditFocusGained", function(self) Focus(self, true) end)
		box:HookScript("OnEditFocusLost", function(self) Focus(self, false) end)
		boxes[box] = state
	end
	state.points, state.height = Points(box), box:GetHeight()
	state.headerPoints = state.header and Points(state.header)
	state.on = true
	if (tonumber(state.height) or 0) > 0 then box:SetHeight(BOX_HEIGHT) end
	Focus(box, box.HasFocus and box:HasFocus() or (box.IsShown and box:IsShown() and Writing and Writing()) or false)
	if state.header and state.header.SetFontObject then
		local small = Skin.FontFor and Skin.FontFor("GameFontNormalSmall") or _G.GameFontNormalSmall
		if small then pcall(state.header.SetFontObject, state.header, small) end
	end
	DressHeader(box)
end

local function UnstyleBox(box)
	local state = type(box) == "table" and boxes[box]
	if not (state and state.on) then return end
	state.on = false
	local name = box:GetName() or ""
	for _, key in ipairs(BOX_ART) do Untuck(_G[name .. key]) end
	state.ground:Hide()
	state.accent:Hide()
	if (tonumber(state.height) or 0) > 0 then box:SetHeight(state.height) end
	if state.header then
		if state.font and state.header.SetFontObject then pcall(state.header.SetFontObject, state.header, state.font) end
		if state.headerPoints and state.headerPoints[1] then PutPoints(state.header, state.headerPoints) end
	end
	-- (the game's own words and room again)
	local update = box.UpdateHeader or _G.ChatEdit_UpdateHeader
	if update then Safe(update, box) end
end

-- Fading ------------------------------------------------------------------------------------------------------------

-- Seconds a line stays (0: always).
local function FadeAfter()
	local settings = ns.Settings() or {}
	local value = tonumber(settings.glassFade)
	return value and value >= 0 and value or 20
end

local function ApplyFade(frame)
	if not (frame.SetFading and frame.SetTimeVisible) then return end
	local after = FadeAfter()
	if after == 0 then
		if Safe(frame.GetFading, frame) then Safe(frame.SetFading, frame, false) end
		return
	end
	if not Safe(frame.GetFading, frame) then Safe(frame.SetFading, frame, true) end
	if Clean(Safe(frame.GetTimeVisible, frame)) ~= after then Safe(frame.SetTimeVisible, frame, after) end
	if frame.SetFadeDuration and Clean(Safe(frame.GetFadeDuration, frame)) ~= FADE_TIME then Safe(frame.SetFadeDuration, frame, FADE_TIME) end
end

-- A window dressed, and back ----------------------------------------------------------------------------------------

local function Dress(frame)
	local name = frame:GetName() or ""
	-- (the combat log keeps the game's window and its lines: only its tab and its line to write in are dressed)
	local combat = ns.IsCombatLogFrame and ns.IsCombatLogFrame(frame) or false
	local was = { combat = combat }
	if not combat then
		for _, key in ipairs(Art()) do Tuck(_G[name .. key]) end
		Tuck(frame.buttonFrame or _G[name .. "ButtonFrame"])
		for _, key in ipairs(SCROLL_PARTS) do Tuck(frame[key] or _G[name .. key]) end
		was.fading = Safe(frame.GetFading, frame)
		was.time = Clean(Safe(frame.GetTimeVisible, frame))
		was.duration = Clean(Safe(frame.GetFadeDuration, frame))
		ApplyFade(frame)
	end
	StyleTab(_G[name .. "Tab"])
	StyleBox(frame.editBox or _G[name .. "EditBox"])
	if not hooked[frame] and frame.AddMessage then
		hooked[frame] = true
		hooksecurefunc(frame, "AddMessage", Added)
	end
	dressed[frame] = was
end

local function Undress(frame)
	local name = frame:GetName() or ""
	local was = dressed[frame] or {}
	for _, key in ipairs(Art()) do Untuck(_G[name .. key]) end
	Untuck(frame.buttonFrame or _G[name .. "ButtonFrame"])
	for _, key in ipairs(SCROLL_PARTS) do Untuck(frame[key] or _G[name .. key]) end
	if not was.combat then
		if was.fading ~= nil and frame.SetFading then Safe(frame.SetFading, frame, was.fading and true or false) end
		if was.time and frame.SetTimeVisible then Safe(frame.SetTimeVisible, frame, was.time) end
		if was.duration and frame.SetFadeDuration then Safe(frame.SetFadeDuration, frame, was.duration) end
	end
	UnstyleTab(_G[name .. "Tab"])
	UnstyleBox(frame.editBox or _G[name .. "EditBox"])
	dressed[frame], unseen[frame] = nil, nil
end

-- The game's chat buttons with the tabs (taken before their frame is taken off), and back.
local function Carry()
	for _, name in ipairs(GAME_BUTTONS) do
		local button = _G[name]
		if type(button) == "table" and button.SetParent and not carried[button]
			and not (button.IsForbidden and button:IsForbidden()) and not (button.IsProtected and button:IsProtected()) then
			carried[button] = button:GetParent() or UIParent
			button:SetParent(holder)
		end
	end
end

local function SetDown()
	for button, parent in pairs(carried) do button:SetParent(parent) end
	wipe(carried)
end

-- Each window: dressed while docked, the game's look when taken apart.
local function Sync()
	if not active then return end
	if Blocked() then
		waiting = true
		return
	end
	local changed = false
	for _, frame in ipairs(Windows()) do
		local docked = Docked(frame)
		if docked and not dressed[frame] then
			Dress(frame)
			changed = true
		elseif not docked and dressed[frame] then
			Undress(frame)
			changed = true
		elseif dressed[frame] and not dressed[frame].combat then
			ApplyFade(frame)
		end
	end
	Carry()
	for tab in pairs(styled) do Paint(tab) end
	-- (the tabs' counts beside their words, or at their corner again)
	if changed and ns.RefreshTabs then ns.RefreshTabs() end
end

-- The lines at rest: a veil under each, a mark on those that concern you ------------------------------------------

local function Lines(frame)
	local list = frame.visibleLines
	if type(list) == "table" then return list end
	local container = frame.FontStringContainer
	if type(container) == "table" and container.GetRegions then
		local found = {}
		for _, region in ipairs({ container:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then found[#found + 1] = region end
		end
		return found
	end
	return {}
end

-- (an opacity to a hundredth: the gradient written again only when it really changes)
local function Round100(value) return math.floor(value * 100 + 0.5) / 100 end

local function Decor(line)
	local d = decor[line]
	if d then return d end
	d = { alpha = -1 }
	d.solid = under:CreateTexture(nil, "BACKGROUND")
	d.solid:SetColorTexture(INK[1], INK[2], INK[3], VEIL)
	d.fade = under:CreateTexture(nil, "BACKGROUND")
	Skin.FadingRule(d.fade, VEIL, false, INK)
	d.tint = under:CreateTexture(nil, "BORDER")
	d.edge = under:CreateTexture(nil, "ARTWORK")
	d.edge:SetWidth(EDGE)
	for _, part in ipairs({ d.solid, d.fade, d.tint, d.edge }) do part:Hide() end
	decor[line] = d
	return d
end

-- Its pieces held to the line (a line drawn is the same one each time: placed once), the width of the window.
local function Place(d, line, frame, spacing)
	local width = Round(frame:GetWidth() + MARGIN)
	if d.line == line and d.width == width and d.spacing == spacing then return end
	d.line, d.width, d.spacing = line, width, spacing
	local half = spacing / 2
	d.solid:ClearAllPoints()
	d.solid:SetPoint("TOPLEFT", line, "TOPLEFT", -MARGIN, half)
	d.solid:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", -MARGIN, -half)
	d.solid:SetWidth(Round(width * VEIL_SOLID))
	d.fade:ClearAllPoints()
	d.fade:SetPoint("TOPLEFT", d.solid, "TOPRIGHT")
	d.fade:SetPoint("BOTTOMLEFT", d.solid, "BOTTOMRIGHT")
	d.fade:SetWidth(width - Round(width * VEIL_SOLID))
	d.tint:ClearAllPoints()
	d.tint:SetPoint("TOPLEFT", d.solid, "TOPLEFT")
	d.tint:SetPoint("BOTTOMLEFT", d.solid, "BOTTOMLEFT")
	d.tint:SetWidth(width)
	d.edge:ClearAllPoints()
	d.edge:SetPoint("TOPLEFT", d.solid, "TOPLEFT")
	d.edge:SetPoint("BOTTOMLEFT", d.solid, "BOTTOMLEFT")
end

-- What a line says of you: "named" (gold), "whisper" (violet), or nil (read again only when its words change).
local function MarkOf(d, line)
	local text = line:GetText()
	if U.IsSecret(text) then
		-- (its mark of the line before taken away with the next drawing)
		if d.mark ~= nil then d.alpha = -1 end
		d.text, d.mark = nil, nil
		return nil
	end
	if text == d.text then return d.mark end
	d.text = text
	local mark
	if type(text) == "string" then
		if ns.NAMED_COLOR and text:find(ns.NAMED_COLOR, 1, true) then
			mark = "named"
		elseif text:find("|Hplayer:[^|]*:WHISPER") or text:find("|HBNplayer:", 1, true) then
			mark = "whisper"
		end
	end
	if mark ~= d.mark then
		d.mark = mark
		local c = mark == "whisper" and VIOLET or GOLD
		d.edge:SetColorTexture(c[1], c[2], c[3], 0.9)
		d.tint:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], mark == "named" and TINT or 0)
		d.alpha = -1
	end
	return mark
end

-- (every veil, not only those of the lines listed now: a line the game took out of its list keeps no veil)
local function HideDecor()
	for _, d in pairs(decor) do
		if d.alpha ~= 0 then
			for _, part in ipairs({ d.solid, d.fade, d.tint, d.edge }) do part:Hide() end
			d.alpha = 0
		end
	end
end

-- The game dims the tabs themselves even once they are there: their words and the gold line are read at full, and
-- still come and go with the tabs.
local TAB_FULL_AT = 0.2 -- the game's own dimmest tab: already read at full
local TAB_PLATE = 0.4 -- darker under the words: 7:1 or better on any ground, measured, snow included
local function TabWords()
	for tab, state in pairs(tabs) do
		if state.text and styled[tab] and state.text.SetIgnoreParentAlpha and tab.GetEffectiveAlpha then
			local seen = Clean(Safe(tab.GetEffectiveAlpha, tab))
			local alpha = math.min(1, (type(seen) == "number" and seen or 0) / TAB_FULL_AT)
			if state.alpha ~= alpha then
				state.alpha = alpha
				for _, part in ipairs({ state.text, state.line }) do
					part:SetIgnoreParentAlpha(true)
					part:SetAlpha(alpha)
				end
				if state.plate then
				state.plate:SetIgnoreParentAlpha(true)
				state.plate:SetAlpha(alpha * TAB_PLATE)
				end
			end
		end
	end
end

-- Each frame: every line's veil and mark at the line's own opacity (the game fades each line), the veil away
-- under the mouse (the ground then).
local function DrawLines()
	TabWords()
	local frame = Selected()
	local combat = active and frame and dressed[frame] and dressed[frame].combat or false
	if combat ~= combatInFront then
		combatInFront = combat
		under.ground:SetAlpha(combat and 0 or shownHover)
	end
	local wanted = active and frame and dressed[frame] and not dressed[frame].combat and frame:IsVisible() and frame or nil
	if wanted ~= decorFrame then
		HideDecor()
		decorFrame = wanted
	end
	if not wanted then return end
	local spacing = Clean(Safe(frame.GetSpacing, frame)) or 0
	local veil = 1 - shownHover
	local top, bottom = Clean(Safe(frame.GetTop, frame)), Clean(Safe(frame.GetBottom, frame))
	-- (the interface's own opacity taken out: the veils stand under it already)
	local whole = Clean(Safe(UIParent.GetEffectiveAlpha, UIParent)) or 1
	if whole <= 0 then whole = 1 end
	wipe(visited)
	for _, line in ipairs(Lines(frame)) do
		local d = Decor(line)
		visited[d] = true
		-- (the window's own fading counts: a line's opacity as the eye sees it)
		-- (a text has no opacity of its own as seen: its own times its frame's, the window's fading included)
		local own = Clean(Safe(line.GetAlpha, line)) or 0
		local lineFrame = Safe(line.GetParent, line)
		local above = type(lineFrame) == "table" and Clean(Safe(lineFrame.GetEffectiveAlpha, lineFrame)) or whole
		local alpha = line:IsShown() and math.min(1, own * (above or whole) / whole) or 0
		-- (a line out of the window's visible part, scrolled away or clipped: no veil where no words are seen)
		if alpha > 0 and top and bottom then
			local lineTop, lineBottom = Clean(Safe(line.GetTop, line)), Clean(Safe(line.GetBottom, line))
			if lineTop and lineBottom and (lineBottom < bottom - 1 or lineTop > top + 1) then alpha = 0 end
		end
		local text = alpha > 0 and line:GetText()
		if not text or (not U.IsSecret(text) and text == "") then alpha = 0 end
		local mark = alpha > 0 and MarkOf(d, line) or d.mark
		-- (placed again whenever the window's width or the spacing changed, whatever the opacity: Place says)
		if alpha > 0 then Place(d, line, frame, spacing) end
		if alpha ~= d.alpha or veil ~= d.veil then
			d.alpha, d.veil = alpha, veil
			if alpha <= 0 then
				for _, part in ipairs({ d.solid, d.fade, d.tint, d.edge }) do part:Hide() end
			else
				d.solid:SetAlpha(alpha * veil)
				-- (a gradient's own colours carry its opacity: this game draws it whatever SetAlpha says, so the
				-- line's fading is written into the gradient itself)
				local fadeAlpha = Round100(VEIL * alpha * veil)
				if d.fadeAlpha ~= fadeAlpha then
					d.fadeAlpha = fadeAlpha
					Skin.FadingRule(d.fade, fadeAlpha, false, INK)
				end
				d.solid:SetShown(veil > 0)
				d.fade:SetShown(veil > 0)
				d.tint:SetAlpha(alpha)
				d.edge:SetAlpha(alpha)
				d.tint:SetShown(mark == "named")
				d.edge:SetShown(mark ~= nil)
			end
		end
	end
	-- A line the game took out of its list (its lines laid out again: a size, a font): its veil goes with it.
	for _, d in pairs(decor) do
		if not visited[d] and d.alpha ~= 0 then
			for _, part in ipairs({ d.solid, d.fade, d.tint, d.edge }) do part:Hide() end
			d.alpha = 0
		end
	end
end

-- Under the mouse ----------------------------------------------------------------------------------------------------

function Writing()
	local box = ns.ActiveEditBox and ns.ActiveEditBox()
	return box ~= nil and box.IsShown ~= nil and box:IsShown() and true or false
end

-- The mouse over the chat (its lines, the tabs above, the line to write in below, the buttons beside).
local function Near()
	local ok, near = pcall(ChatFrame1.IsMouseOver, ChatFrame1, TAB_ROOM, -(BOX_HEIGHT + 4), -MARGIN * 2, MARGIN)
	if ok and near then return true end
	if U.IsMouseOver(GeneralDockManager) then return true end
	for button in pairs(carried) do
		if button:IsVisible() and U.IsMouseOver(button) then return true end
	end
	return false
end

-- The ground under the mouse, from the tabs to the line to write in.
local function HoldGround()
	under:ClearAllPoints()
	under:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", -MARGIN, TAB_ROOM)
	under:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", MARGIN, -(BOX_HEIGHT + 4))
end

local function ShowHover(value)
	shownHover = value
	-- (the combat log in front keeps its own ground)
	under.ground:SetAlpha(combatInFront and 0 or value)
	if GeneralDockManager then GeneralDockManager:SetAlpha((dockAlpha or 1) * value) end
	holder:SetAlpha(value)
	bar:SetAlpha(value)
end

-- The thin scroll bar and the way back to the latest lines.
local function DrawScroll()
	local frame = decorFrame
	local offset = frame and Clean(Safe(frame.GetScrollOffset, frame)) or 0
	if type(offset) ~= "number" then offset = 0 end
	if offset <= 0 and frame then unseen[frame] = nil end
	-- (the way back: whenever you are up in the lines)
	if frame and offset > 0 then
		local count = unseen[frame] or 0
		marker.text:SetText(count == 1 and L.GLASS_NEW_ONE or count > 1 and L.GLASS_NEW:format(count) or L.GLASS_LATEST)
		marker:SetWidth(U.Measure(marker.text, "GetStringWidth", 80) + 2 * (24 + MARGIN))
		marker:Show()
	else
		marker:Hide()
	end
	local total = frame and Clean(Safe(frame.GetNumMessages, frame)) or 0
	local shown = frame and #Lines(frame) or 0
	if type(total) ~= "number" or total <= shown or shown <= 0 then
		bar:Hide()
		return
	end
	bar:Show()
	local height = bar:GetHeight() or 0
	if height <= 0 then return end
	local thumb = math.max(MARGIN * 2, Round(height * shown / total))
	local range = math.max(1, total - shown)
	local y = Round((height - thumb) * math.min(1, offset / range))
	bar.thumb:SetHeight(thumb)
	bar.thumb:ClearAllPoints()
	bar.thumb:SetPoint("BOTTOM", bar, "BOTTOM", 0, y)
end

-- A whisper waiting for an answer -------------------------------------------------------------------------------------

local pending = {} -- { full, name, guid, text }, the newest last

local function WhispersInChat()
	return not (ns.On("messagesWindow") and ns.On("messagesHideInChat") and not ns.Yields("whispers"))
end

local function DrawPin()
	local entry = pending[#pending]
	if not (active and entry and WhispersInChat()) then
		pin:Hide()
		return
	end
	local name = ns.Named and ns.Named(entry.name, entry.guid) or entry.name
	local words = #pending > 1 and L.GLASS_WHISPERED_MORE:format(name, #pending - 1) or L.GLASS_WHISPERED:format(name)
	pin.text:SetText(words .. "  " .. MUTED_HEX .. "\194\183|r")
	pin:Show()
end

local function Forget(name)
	name = ns.Who(name)
	for index = #pending, 1, -1 do
		if pending[index].name == name then table.remove(pending, index) end
	end
	DrawPin()
end
ns.GlassForgetWhisper = Forget -- (tests)

local function Whispered(line)
	if line.kind ~= "whisper" or line.me or not line.who then return end
	Forget(line.who)
	pending[#pending + 1] = { full = line.sender, name = line.who, guid = line.guid, text = line.text }
	while #pending > 20 do table.remove(pending, 1) end
	DrawPin()
end
function ns.GlassPending() return pending end -- (tests)

-- On and off --------------------------------------------------------------------------------------------------------

local function Activate()
	if active then return end
	active = true
	dockAlpha = GeneralDockManager and GeneralDockManager:GetAlpha() or 1
	holder:SetFrameStrata(ChatFrame1:GetFrameStrata() or "LOW")
	under:SetFrameStrata(ChatFrame1:GetFrameStrata() or "LOW")
	under:SetFrameLevel(math.max(0, (ChatFrame1:GetFrameLevel() or 1) - 1))
	under:Show()
	over:Show()
	holder:Show()
	Carry()
	Sync()
	HoldGround()
	hover:Set(0)
	ShowHover(0)
	DrawPin()
end

local function Deactivate()
	if not active then return end
	for frame in pairs(dressed) do Undress(frame) end
	SetDown()
	HideDecor(decorFrame)
	decorFrame = nil
	if GeneralDockManager then GeneralDockManager:SetAlpha(dockAlpha or 1) end
	-- (anything still off, put back)
	for region in pairs(parents) do Untuck(region) end
	GiveWordsBack()
	wipe(unseen)
	under:Hide()
	over:Hide()
	holder:Hide()
	pin:Hide()
	active = false
end

local function Wanted()
	return ns.On() and (ns.Settings() or {}).look == "glass" and not ns.Yields("chatLook") and ChatFrame1 ~= nil
		and GeneralDockManager ~= nil
end

function ns.GlassActive() return active end
-- (tests: its pieces, a line's veil and mark)
-- (/wchat dump over time: one short line per chat line, how the game fades it and how its veil follows)
function ns.GlassSample(at)
	local out = {}
	local frame = decorFrame
	if not frame then return { ("t=%d no veils"):format(at) } end
	local container = rawget(frame, "FontStringContainer")
	out[#out + 1] = ("t=%d hover=%s frameAlpha=%s container=%s"):format(at, tostring(shownHover), tostring(Clean(Safe(frame.GetAlpha, frame))),
		tostring(container and Clean(Safe(container.GetAlpha, container))))
	for index, line in ipairs(Lines(frame)) do
		local d = decor[line]
		local _, _, _, textAlpha = line:GetTextColor()
		local ok, l, b, w = pcall(d and d.fade.GetRect or line.GetRect, d and d.fade or line)
		out[#out + 1] = ("  %d shown=%s alpha=%s textAlpha=%s top=%s | solid=%s/%s fade=%s/%s at %s,%s w=%s"):format(index, tostring(line:IsShown()),
			tostring(Clean(Safe(line.GetAlpha, line))), tostring(Clean(textAlpha)), tostring(Clean(Safe(line.GetTop, line))),
			tostring(d and d.solid:IsShown()), tostring(d and d.solid:GetAlpha()), tostring(d and d.fade:IsShown()), tostring(d and d.fade:GetAlpha()),
			tostring(ok and Clean(l)), tostring(ok and Clean(b)), tostring(ok and Clean(w)))
	end
	return out
end

-- (/wchat dump: each line's veil as drawn now, GlassDump.lua)
function ns.GlassVeils()
	local out = {}
	local frame = decorFrame
	out[#out + 1] = ("veils on %s, hover=%s, active=%s"):format(frame and (frame:GetName() or "?") or "none", tostring(shownHover), tostring(active))
	if not frame then return out end
	local top, bottom = Clean(Safe(frame.GetTop, frame)), Clean(Safe(frame.GetBottom, frame))
	out[#out + 1] = ("frame top=%s bottom=%s effAlpha=%s"):format(tostring(top), tostring(bottom), tostring(Clean(Safe(frame.GetEffectiveAlpha, frame))))
	for index, line in ipairs(Lines(frame)) do
		local d = decor[line]
		local text = Clean(line:GetText())
		text = type(text) == "string" and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 40) or tostring(text)
		out[#out + 1] = ("line %d shown=%s alpha=%s eff=%s top=%s bottom=%s | veil alpha=%s solid=%s/%s fade=%s/%s tint=%s edge=%s | %s"):format(
			index, tostring(line:IsShown()), tostring(Clean(Safe(line.GetAlpha, line))), tostring(Clean(Safe(line.GetEffectiveAlpha, line))),
			tostring(Clean(Safe(line.GetTop, line))), tostring(Clean(Safe(line.GetBottom, line))), tostring(d and d.alpha),
			tostring(d and d.solid:IsShown()), tostring(d and d.solid:GetAlpha()), tostring(d and d.fade:IsShown()),
			tostring(d and d.fade:GetAlpha()), tostring(d and d.tint:IsShown()), tostring(d and d.edge:IsShown()), text)
	end
	-- Every veil drawn now, its line listed or not (a veil left behind shows here).
	local listed = {}
	for _, line in ipairs(Lines(frame)) do if decor[line] then listed[decor[line]] = true end end
	for _, d in pairs(decor) do
		if d.solid:IsShown() or d.fade:IsShown() or d.tint:IsShown() or d.edge:IsShown() then
			local ok, l, b, w, h = pcall(d.solid.GetRect, d.solid)
			out[#out + 1] = ("veil shown | listed=%s | solid=%s,%s %sx%s alpha=%s | fade=%s alpha=%s"):format(tostring(listed[d] == true),
				tostring(ok and Clean(l)), tostring(ok and Clean(b)), tostring(ok and Clean(w)), tostring(ok and Clean(h)),
				tostring(d.solid:GetAlpha()), tostring(d.fade:IsShown()), tostring(d.fade:GetAlpha()))
		end
	end
	return out
end

function ns.GlassPieces() return { under = under, over = over, marker = marker, pin = pin, bar = bar, holder = holder } end
function ns.GlassDecor(line) return decor[line] end
-- Whether a chat window is dressed in glass now (its tab's count beside its words).
function ns.GlassHolds(frame) return active and dressed[frame] ~= nil end

function ns.RefreshGlass()
	if not under then return end
	if Blocked() then
		waiting = true
		return
	end
	waiting = false
	if Wanted() then
		Activate()
		Sync()
		for frame, was in pairs(dressed) do
			if not was.combat then ApplyFade(frame) end
		end
	else
		Deactivate()
		if ns.RefreshTabs then ns.RefreshTabs() end
	end
end

-- Shorter channel names (the game's own look) -----------------------------------------------------------------------

-- "2. Trade - City" -> "2. Trade" (the number kept: the game reads it), only when it stays longer than every
-- channel the window listens to (the game finds the channel by a shorter name).
-- (asked for every line of every window: the answer kept a few seconds)
local function OtherLook() return ns.YieldsNow("chatLook") ~= nil end

local function ShortChannel(frame, _, text, author, language, channel, ...)
	if type(channel) ~= "string" or U.IsSecret(channel) or not ns.On("shortChannels") or OtherLook() then
		return false
	end
	local number, name = channel:match("^(%d+%. )(.-)%s+%-%s+.+$")
	if not (number and name and name ~= "") then return false end
	local short = number .. name
	local list = type(frame) == "table" and type(frame.channelList) == "table" and frame.channelList or {}
	for _, each in pairs(list) do
		if type(each) == "string" and #short <= #each then return false end
	end
	if type(text) ~= "string" or text == "" then return false end
	return false, text, author, language, short, ...
end

-- Start ---------------------------------------------------------------------------------------------------------------

local function Build()
	-- (under the interface itself: what is taken off keeps its scale, so its pieces keep their places)
	hidden = CreateFrame("Frame", nil, UIParent)
	hidden:Hide()
	-- Under the lines: the ground under the mouse, the veils at rest.
	under = CreateFrame("Frame", "WandererChatGlass", UIParent)
	under:Hide()
	under.ground = under:CreateTexture(nil, "BACKGROUND", nil, -8)
	under.ground:SetAllPoints()
	under.ground:SetColorTexture(INK[1], INK[2], INK[3], GROUND)
	-- Over them: the scroll bar, the way back, the whisper waiting.
	over = CreateFrame("Frame", nil, UIParent)
	over:SetAllPoints(ChatFrame1)
	over:SetFrameStrata("MEDIUM")
	over:Hide()
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints(UIParent)
	holder:Hide()
	bar = CreateFrame("Frame", nil, over)
	bar:SetWidth(EDGE)
	bar:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", MARGIN - 2, 0)
	bar:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", MARGIN - 2, 0)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints()
	bar.track:SetColorTexture(1, 1, 1, 0.06)
	bar.thumb = bar:CreateTexture(nil, "ARTWORK")
	bar.thumb:SetWidth(EDGE)
	bar.thumb:SetColorTexture(WORDS[1], WORDS[2], WORDS[3], 0.45)
	bar:Hide()
	-- "2 new" between two fine rules: a click, the latest lines again.
	marker = CreateFrame("Button", nil, over)
	marker:SetHeight(16)
	marker:SetPoint("BOTTOM", ChatFrame1, "BOTTOM", 0, 2)
	marker.ground = marker:CreateTexture(nil, "BACKGROUND")
	marker.ground:SetAllPoints()
	marker.ground:SetColorTexture(INK[1], INK[2], INK[3], 0.85)
	marker.text = Skin.Text(marker, "GameTooltipTextSmall", "gold")
	marker.text:SetPoint("CENTER")
	for index, side in ipairs({ "LEFT", "RIGHT" }) do
		local rule = marker:CreateTexture(nil, "ARTWORK")
		rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
		rule:SetSize(24, 1)
		rule:SetPoint(index == 1 and "RIGHT" or "LEFT", marker.text, side, index == 1 and -MARGIN or MARGIN, 0)
	end
	marker:SetScript("OnClick", function()
		local frame = decorFrame
		if frame and frame.ScrollToBottom then Safe(frame.ScrollToBottom, frame) end
		if frame then unseen[frame] = nil end
	end)
	marker:Hide()
	-- The whisper waiting for an answer, above the chat.
	pin = CreateFrame("Frame", nil, over)
	pin:SetHeight(20)
	pin:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -MARGIN, TAB_ROOM + 4)
	pin:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", MARGIN, TAB_ROOM + 4)
	pin:EnableMouse(true)
	pin.ground = pin:CreateTexture(nil, "BACKGROUND")
	pin.ground:SetAllPoints()
	pin.ground:SetColorTexture(INK[1], INK[2], INK[3], 0.7)
	pin.edge = pin:CreateTexture(nil, "ARTWORK")
	pin.edge:SetPoint("TOPLEFT")
	pin.edge:SetPoint("BOTTOMLEFT")
	pin.edge:SetWidth(EDGE)
	pin.edge:SetColorTexture(VIOLET[1], VIOLET[2], VIOLET[3], 0.9)
	pin.text = Skin.Text(pin, "GameTooltipTextSmall", "soft")
	pin.text:SetPoint("LEFT", pin, "LEFT", MARGIN + EDGE, 0)
	if pin.text.SetWordWrap then pin.text:SetWordWrap(false) end
	pin.close = CreateFrame("Button", nil, pin)
	pin.close:SetSize(16, 16)
	pin.close:SetPoint("RIGHT", pin, "RIGHT", -4, 0)
	pin.close.icon = Skin.Glyph(pin.close, "close", 10)
	pin.close.icon:SetPoint("CENTER")
	pin.close:SetScript("OnClick", function()
		local entry = pending[#pending]
		if entry then Forget(entry.name) end
	end)
	Skin.Tooltip(pin.close, { L.GLASS_DISMISS }, "ANCHOR_TOP")
	pin.reply = Skin.CreateLink(pin, L.GLASS_REPLY, function()
		local entry = pending[#pending]
		if not entry then return end
		Forget(entry.name)
		ns.Whisper(entry.full)
	end)
	pin.reply:SetPoint("LEFT", pin.text, "RIGHT", 4, 0)
	-- (what they said, under the mouse)
	Skin.Tooltip(pin, function()
		local entry = pending[#pending]
		if entry and entry.text then return { entry.name, { ns.Excerpt(entry.text, 160), Skin.COLORS.text[1], Skin.COLORS.text[2], Skin.COLORS.text[3] } } end
	end, "ANCHOR_TOP")
	pin:Hide()
	-- (a controller: its touchpad goes to the whisper waiting, its answer and its cross)
	if Skin.PadNotice then Skin.PadNotice(pin) end
end

function ns.InitGlass()
	if not (Skin and ChatFrame1) then return end
	Build()
	motdPattern = U.FormatPattern(_G.GUILD_MOTD_TEMPLATE or "Guild Message of the Day: %s")
	ns.AddFilter("CHAT_MSG_CHANNEL", ShortChannel)
	-- The game docking, taking apart, opening or closing a window: followed.
	local soon = U.Debounce(0, Sync)
	for _, name in ipairs({ "FCF_DockUpdate", "FCF_DockFrame", "FCF_UnDockFrame", "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow",
		"FCF_Close" }) do
		if _G[name] then hooksecurefunc(name, soon) end
	end
	if _G.FCFTab_UpdateColors then hooksecurefunc("FCFTab_UpdateColors", function(tab) Paint(tab) end) end
	if _G.ChatEdit_UpdateHeader then hooksecurefunc("ChatEdit_UpdateHeader", DressHeader) end
	ns.Heard.On(Whispered)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "CHAT_MSG_WHISPER_INFORM" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, _, target)
		if event == "CHAT_MSG_WHISPER_INFORM" then
			-- (answered: the waiting line goes)
			if not U.IsSecret(target) and Clean(target) then Forget(target) end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if waiting then ns.RefreshGlass() end
			return
		end
		soon()
	end)
	-- Each frame: the lines' veils, the ground under the mouse; a look now and then at the rest.
	local since, synced, writing = 0, 0, false
	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		if not active then return end
		since, synced = since + elapsed, synced + elapsed
		if since >= CHECK then
			since = 0
			if Near() or Writing() then lastNear = GetTime() end
			-- (writing: shown all along)
			writing = Writing()
			-- (shown, and faded with the interface, as the chat is)
			local shown = (ChatFrame1:IsShown() or (GeneralDockManager and GeneralDockManager:IsShown())) and true or false
			for _, frame in ipairs({ under, over, holder }) do
				if frame:IsShown() ~= shown then frame:SetShown(shown) end
			end
			DrawScroll()
		end
		if synced >= SYNC_EVERY then
			synced = 0
			Sync()
		end
		local wanted = GetTime() - lastNear < LINGER and 1 or 0
		if writing then wanted = 1 end
		local value = hover:Step(wanted, elapsed, HOVER_IN, HOVER_OUT)
		if value ~= shownHover then ShowHover(value) end
		DrawLines()
	end)
	ns.RefreshGlass()
end
