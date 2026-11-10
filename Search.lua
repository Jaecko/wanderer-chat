local _, ns = ...
local L = ns.L

-- Search the chat: the lines of a tab (the one whose search button was clicked, else the one in view) in a small
-- window, as plain words in their chat's color; what you type found in them in gold, accents and capitals aside.
-- The older and the newer one a click away (Enter: the older, Shift+Enter: the newer), the line found marked and
-- brought into view. Reading only: nothing is changed in the chat, nothing kept. A button opens the same lines in
-- Wanderer's copy window, for Ctrl+C. Lines the game keeps secret are left out.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local WIDTH, HEIGHT = 600, 400
local MOST = 500 -- lines read, the newest
local QUERY_MOST = 60
local FOUND_COLOR = "|cffffd35c" -- the gold of your name (Highlight.lua)
local UTF8_LETTER = "[%z\1-\127\194-\244][\128-\191]*"

local window
local source -- the chat window searched
local lines = {} -- { plain, folded, r, g, b }, the oldest first
local found = {} -- the lines holding the words (their numbers), the oldest first
local at = 0 -- the one marked, among found
local query = "" -- folded

-- The lines of a chat window, plain (the colors put by the chat taken away first).
local function Read(frame)
	wipe(lines)
	if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return end
	local count = Clean(Safe(frame.GetNumMessages, frame)) or 0
	for index = math.max(1, count - MOST + 1), count do
		local text, r, g, b = Safe(frame.GetMessageInfo, frame, index)
		if type(text) == "string" and not U.IsSecret(text) then
			local plain = U.PlainText(ns.Unpainted and ns.Unpainted(text) or text):gsub("||", "|")
			lines[#lines + 1] = { plain = plain, folded = U.Fold(plain), r = Clean(r), g = Clean(g), b = Clean(b) }
		end
	end
end

-- Words to show as they are (a bar shown as a bar).
local function Escaped(text) return (text:gsub("|", "||")) end

-- A line with the words found in gold. Found letter by letter (folded each: "foret" finds "Forêt").
local function Marked(plain, words)
	local letters, folded, owner = {}, {}, {}
	for from, letter in plain:gmatch("()(" .. UTF8_LETTER .. ")") do
		letters[#letters + 1] = { from, from + #letter - 1 }
		local fold = U.Fold(letter)
		folded[#folded + 1] = fold
		for _ = 1, #fold do owner[#owner + 1] = #letters end
	end
	folded = table.concat(folded)
	local out, last, start = {}, 1, 1
	while true do
		local from, to = folded:find(words, start, true)
		if not from then break end
		local first, final = letters[owner[from]], letters[owner[to]]
		out[#out + 1] = Escaped(plain:sub(last, first[1] - 1))
		out[#out + 1] = FOUND_COLOR .. Escaped(plain:sub(first[1], final[2])) .. "|r"
		last, start = final[2] + 1, to + 1
	end
	out[#out + 1] = Escaped(plain:sub(last))
	return table.concat(out)
end
ns.SearchMarked = Marked -- (tests)

-- The lines drawn again, the one marked brought into view.
local function Draw()
	local list = window.list
	list:Clear()
	local marked = found[at]
	for index, line in ipairs(lines) do
		local text = (query ~= "" and line.folded:find(query, 1, true)) and Marked(line.plain, query) or Escaped(line.plain)
		if index == marked then text = Skin.GlyphText("chevron", "gold") .. " " .. text end
		list:AddMessage(text, line.r or 1, line.g or 1, line.b or 1)
	end
	if marked and list.SetScrollOffset then
		local shown = list.GetNumVisibleLines and Clean(Safe(list.GetNumVisibleLines, list)) or 10
		list:SetScrollOffset(math.max(0, #lines - marked - math.floor(shown / 2)))
	end
	window.count:Set(query ~= "" and (found[1] and ("%d / %d"):format(at, #found) or L.SEARCH_NONE) or nil,
		found[1] and "gold" or "grey")
	window.empty:SetShown(lines[1] == nil)
	for _, button in ipairs({ window.older, window.newer }) do button:SetAlpha(found[2] and 1 or 0.4) end
end

-- The words typed: the lines holding them, the newest marked.
local function Search()
	query = U.Fold(strtrim(window.input:GetText() or ""))
	wipe(found)
	if query ~= "" then
		for index, line in ipairs(lines) do
			if line.folded:find(query, 1, true) then found[#found + 1] = index end
		end
	end
	at = #found
	Draw()
end

-- The older one found (step -1) or the newer (step 1), going round.
local function Step(step)
	if not found[1] then return end
	at = (at - 1 + step) % #found + 1
	Draw()
end

local function Make()
	window = Skin.CreateWindow("WandererChatSearch", "MEDIUM")
	window:SetSize(WIDTH, HEIGHT)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 60 }, "chatSearch")
	local _, title, m = Skin.Header(window, "Wanderer", L.SEARCH_TITLE, { settings = "ext:chat" })
	title:SetPoint("RIGHT", window, "RIGHT", -(m + 60), 0)
	-- The words to find, the count, the older and the newer.
	window.newer = Skin.GlyphButton(window, "down", 14, { L.SEARCH_NEWER, L.SEARCH_NEWER_DESC }, function() Step(1) end)
	window.older = Skin.GlyphButton(window, "up", 14, { L.SEARCH_OLDER, L.SEARCH_OLDER_DESC }, function() Step(-1) end)
	window.input = Skin.CreateInput(window, "WandererChatSearchInput", QUERY_MOST, {
		hint = L.SEARCH_HINT,
		onChange = Search,
		onEnter = function() Step(IsShiftKeyDown() and 1 or -1) end,
		onEscape = function(self)
			if (self:GetText() or "") ~= "" then return self:SetText("") end
			self:ClearFocus()
			window:Hide()
		end,
	})
	window.input:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	window.input:SetPoint("RIGHT", window, "RIGHT", -(m + 130), 0)
	window.older:SetPoint("LEFT", window.input, "RIGHT", 6, 0)
	window.newer:SetPoint("LEFT", window.older, "RIGHT", 2, 0)
	window.count = Skin.Chip(window)
	window.count:SetPoint("LEFT", window.newer, "RIGHT", 6, 0)
	-- The lines, as in the chat, plain (the wheel scrolls).
	local list = CreateFrame("ScrollingMessageFrame", nil, window)
	list:SetPoint("TOPLEFT", window.input, "BOTTOMLEFT", 0, -10)
	list:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -m, m + 32)
	list:SetFontObject(Skin.FontFor("ChatFontNormal"))
	list:SetJustifyH("LEFT")
	list:SetFading(false)
	list:SetMaxLines(MOST)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta) if delta > 0 then self:ScrollUp() else self:ScrollDown() end end)
	window.list = list
	window.empty = Skin.Text(window, "GameTooltipText", "muted")
	window.empty:SetPoint("CENTER", list, "CENTER")
	window.empty:SetText(L.SEARCH_EMPTY)
	-- At its foot: the same lines in the copy window.
	window.copy = Skin.SmallButton(window, L.QUIET_COPY, function() W.CopyChat(source) end, L.CHAT_COPY_BUTTON_TIP)
	window.copy:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -m, m)
end

-- The search over a chat window's lines (frame: that window, else the tab in view).
function ns.OpenSearch(frame)
	source = type(frame) == "table" and frame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
	if not window then Make() end
	Read(source)
	window:SetScale(Skin.FitScale(window))
	window:Show()
	Skin.Get(window):Layout()
	Search()
	window.input:SetFocus()
	window.input:HighlightText()
end
ns.SearchFound = function() return found, at, lines end -- (tests)
