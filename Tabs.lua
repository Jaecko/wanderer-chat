local _, ns = ...
local L = ns.L

-- Chat tabs: one click makes a tab for the group, one for the guild, one for whispers and one for the public
-- channels, docked beside the game's own. A one-time setup, not a rule: the tabs then belong to the player
-- (rename, move, close as in the game). A tab that already exists under the same name is never made twice;
-- General keeps all it shows, but the public channels when they get their own tab.
--
-- On each tab, what came while it was not shown: a small count in gold at its corner (only your guild, your
-- group and your whispers: the public channels, the system and the loot pass uncounted), and a gold dot when
-- a line there names you; seen even when the game has faded the tabs; the tab shown, they go.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Clean = U and U.Clean

ns.CHAT_TABS = {
	{ key = "group", groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
		"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
	{ key = "guild", groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
	{ key = "whispers", groups = { "WHISPER", "BN_WHISPER" } },
	{ key = "channels", channels = true },
}

local function TabName(tab)
	return L["CHAT_TAB_" .. tab.key:upper()]
end

-- The chat window of this name, shown or docked (its index).
local function WindowIndex(name)
	if not GetChatWindowInfo then return end
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local existing, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(index)
		if Clean(existing) == name and (shown or docked) then return index end
	end
end

-- Whether one of the tabs is there already (the first offer is then not made).
function ns.AnyChatTab()
	for _, tab in ipairs(ns.CHAT_TABS) do
		if WindowIndex(TabName(tab)) then return true end
	end
	return false
end

-- The game's functions, wherever this version of the game keeps them.
local function Call(frame, method, global, ...)
	if frame[method] then return pcall(frame[method], frame, ...) end
	if _G[global] then return pcall(_G[global], frame, ...) end
end

local function Clear(frame)
	Call(frame, "RemoveAllMessageGroups", "ChatFrame_RemoveAllMessageGroups")
	Call(frame, "RemoveAllChannels", "ChatFrame_RemoveAllChannels")
end

-- The public channels you are in (General, Trade...): their names.
local function PublicChannels()
	local list = {}
	if not GetChannelList then return list end
	local values = { GetChannelList() }
	for index = 1, #values, 3 do
		local name = Clean(values[index + 1])
		if type(name) == "string" then list[#list + 1] = name end
	end
	return list
end

-- Makes the chosen tabs; returns the names made and the names already there.
function ns.CreateChatTabs()
	local made, kept = {}, {}
	local settings = ns.Settings()
	if not settings or InCombatLockdown() or not FCF_OpenNewWindow then return made, kept end
	for _, tab in ipairs(ns.CHAT_TABS) do
		if settings[tab.key] then
			local name = TabName(tab)
			if WindowIndex(name) then
				kept[#kept + 1] = name
			else
				-- true: without the default channels, only what the tab is for.
				local ok, frame = pcall(FCF_OpenNewWindow, name, true)
				if ok and frame then
					Clear(frame)
					for _, group in ipairs(tab.groups or {}) do Call(frame, "AddMessageGroup", "ChatFrame_AddMessageGroup", group) end
					if tab.channels then
						-- (their own tab now: General no longer shows them)
						for _, channel in ipairs(PublicChannels()) do
							Call(frame, "AddChannel", "ChatFrame_AddChannel", channel)
							if DEFAULT_CHAT_FRAME then Call(DEFAULT_CHAT_FRAME, "RemoveChannel", "ChatFrame_RemoveChannel", channel) end
						end
					end
					made[#made + 1] = name
				end
			end
		end
	end
	if made[1] then
		W.Print(L.MSG_CHAT_TABS:format(table.concat(made, ", ")))
	elseif kept[1] then
		W.Print(L.MSG_CHAT_TABS_EXIST)
	else
		W.Print(L.MSG_CHAT_TABS_NONE)
	end
	return made, kept
end

-- The tab where a kind of line is read: the first docked one showing its group, or listening to its public
-- channel (channel: its name), General at last.
function ns.ShowTabOf(chatType, channel)
	local frame
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local candidate = _G["ChatFrame" .. index]
		local docked = select(9, GetChatWindowInfo(index))
		if not docked then candidate = nil end
		local groups = candidate and candidate.messageTypeList
		local shows = candidate and (channel and ns.ListsChannel and ns.ListsChannel(candidate, channel)
			or (not channel and type(groups) == "table" and tContains and tContains(groups, chatType)))
		if shows and candidate ~= DEFAULT_CHAT_FRAME then
			frame = candidate
			break
		end
	end
	frame = frame or DEFAULT_CHAT_FRAME
	if frame and FCF_SelectDockFrame then pcall(FCF_SelectDockFrame, frame) end
	if frame and frame.ScrollToBottom then pcall(frame.ScrollToBottom, frame) end
end

-- What came on each tab ----------------------------------------------------------------------------------------

local MOST = 99 -- shown as "99+" beyond
local SETTLE = 5 -- seconds after the start: the lines the game gives at login (the guild's message) are not news
local DOT = 9 -- the gold dot's size
local counts, named, badges, dots, watched = {}, {}, {}, {}, {}
local settled = false

-- The chats counted: the guild, the group, the whispers (yours sent: not news).
local COUNTED = { "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
	"INSTANCE_CHAT_LEADER", "WHISPER", "BN_WHISPER" }

-- Whether a line shown is one of those: by the id of its chat the game gives with it, else by its color.
local function Counts(r, g, b, id)
	-- (a game without the chats' colors: every line, as before)
	if type(ChatTypeInfo) ~= "table" then return true end
	return ns.IsChatType(COUNTED, r, g, b, id)
end

local function Badge(frame)
	if badges[frame] then return badges[frame], dots[frame] end
	local tab = frame.GetName and _G[(frame:GetName() or "") .. "Tab"]
	if not tab then return end
	local badge = Skin.Text(tab, "GameFontNormalSmall", "gold")
	badge:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT", -6, -8)
	local dot = Skin.GlyphOn(tab:CreateTexture(nil, "OVERLAY"), "dot")
	dot:SetSize(DOT, DOT)
	-- (seen when the game has faded the tabs: that is when they are wanted)
	for _, part in ipairs({ badge, dot }) do
		if part.SetIgnoreParentAlpha then part:SetIgnoreParentAlpha(true) end
		part:Hide()
	end
	badges[frame], dots[frame] = badge, dot
	return badge, dot
end

local function Draw(frame)
	local badge, dot = Badge(frame)
	if not badge then return end
	local count = counts[frame] or 0
	local tab = _G[(frame:GetName() or "") .. "Tab"]
	local tabShown = tab and tab:IsShown() or false
	local countShown = count > 0 and ns.On("unread") and tabShown
	badge:SetText(count > MOST and MOST .. "+" or tostring(count))
	badge:SetShown(countShown)
	local dotShown = named[frame] and ns.On("mention") and tabShown or false
	dot:SetShown(dotShown)
	badge:ClearAllPoints()
	dot:ClearAllPoints()
	-- In glass, the tabs are plain words, shown with the mouse: the dot and the count just after them, with them.
	local words = ns.GlassHolds and ns.GlassHolds(frame) and type(tab.Text) == "table" and tab.Text or nil
	for _, part in ipairs({ badge, dot }) do
		if part.SetIgnoreParentAlpha then part:SetIgnoreParentAlpha(words == nil) end
	end
	if words then
		dot:SetPoint("LEFT", words, "RIGHT", 3, 0)
		badge:SetPoint("LEFT", dotShown and dot or words, "RIGHT", dotShown and 2 or 3, 0)
		return
	end
	-- Your name: the dot, before the count when there is one.
	badge:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT", -6, -8)
	if countShown then
		dot:SetPoint("RIGHT", badge, "LEFT", -2, 0)
	else
		dot:SetPoint("BOTTOMRIGHT", tab, "TOPRIGHT", -6, -8)
	end
end

local function Counted(frame, text, r, g, b, id)
	if not settled or frame:IsVisible() or ns.restoring or not ns.On() then return end
	if ns.IsCombatLogFrame(frame) then return end
	local index = tonumber((frame:GetName() or ""):match("^ChatFrame(%d+)$"))
	if ns.IsDebugTab(index) then return end
	local changed = false
	if type(text) == "string" and not U.IsSecret(text) and ns.On("mention") and text:find(ns.NAMED_COLOR, 1, true) then
		named[frame], changed = true, true
	end
	if ns.On("unread") and Counts(r, g, b, id) then
		counts[frame], changed = (counts[frame] or 0) + 1, true
	end
	if changed then Draw(frame) end
end

local function Watch()
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. index]
		if frame and not watched[frame] and frame.AddMessage then
			watched[frame] = true
			hooksecurefunc(frame, "AddMessage", Counted)
			-- Shown: read.
			frame:HookScript("OnShow", function(self)
				counts[self], named[self] = nil, nil
				Draw(self)
			end)
		end
	end
end

function ns.RefreshTabs()
	Watch()
	for frame in pairs(watched) do Draw(frame) end
end

function ns.InitTabs()
	Watch()
	C_Timer.After(SETTLE, function() settled = true end)
	-- A tab made later (by you or by Wanderer): watched too.
	if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() C_Timer.After(0, Watch) end) end
	-- (a tab shown or hidden with the dock: its count with it)
	if FCF_DockUpdate then hooksecurefunc("FCF_DockUpdate", function() for frame in pairs(watched) do Draw(frame) end end) end
end
