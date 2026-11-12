local _, ns = ...
local L = ns.L

-- Wanderer Chat's page among Wanderer's options: the chat itself first (what most want), then the tabs and the
-- public channels, then the finer settings, each beside what it belongs to, folded away under "More settings".

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local SOUNDS = { { "TELL_MESSAGE", "SOUND_WHISPER" }, { "RAID_WARNING", "SOUND_WARNING" }, { "MAP_PING", "SOUND_PING" },
	{ "READY_CHECK", "SOUND_READY" } }

-- The chat's settings (none while Wanderer is off: read as empty, nothing written).
local function Settings() return ns.Settings() or {} end

-- A list of words of yours (watched, hidden, your other names), asked in one line, separated by commas.
local function WordsAsk(key, prompt)
	return function()
		Skin.AskText(prompt, Settings()[key] or "", function(words)
			W.ChangeEverywhere(function()
				local settings = ns.Settings()
				if settings then settings[key] = words end
			end)
		end, 200, true)
	end
end

-- The tabs "Create the tabs" makes, ticked in a card beside the button, then made from its last row.
function ns.TabsCard(owner)
	local settings = ns.Settings()
	if not settings then return end
	local rows = {}
	for _, tab in ipairs(ns.CHAT_TABS) do
		local key = "CHAT_TAB_" .. tab.key:upper()
		local on = settings[tab.key] and true or false
		rows[#rows + 1] = { text = L[key], glyph = on and "check" or "dot", role = not on and "muted" or nil, hint = L[key .. "_DESC"],
			onClick = function()
				W.ChangeEverywhere(function()
					local now = ns.Settings()
					if now then now[tab.key] = not on end
				end)
				ns.TabsCard(owner)
			end }
	end
	rows[#rows + 1] = { text = L.CHAT_TABS_BUTTON, glyph = "plus", hint = L.CHAT_TABS_DESC, onClick = ns.CreateChatTabs }
	return Skin.ActionCard(owner, { title = L.CHAT_TABS, rows = rows })
end

function ns.Options(o)
	local function Check(key, label, refresh) return o.Checkbox("chat", key, L[label], L[label .. "_DESC"], refresh) end
	local enabled = Check("enabled", "ENABLE", ns.Refresh)
	local on = o.IsOn("chat", "enabled")
	local function Under(widget, parent, isOn) return o.Under(widget, parent or enabled, isOn or on) end
	local function Also(key) return function() return on() and Settings()[key] and true or false end end
	-- (an option whose job another addon does: greyed, with its name)
	local function Yield(widget, job) return o.Yield(widget, job) end
	local function RefreshGlass() if ns.RefreshGlass then ns.RefreshGlass() end end

	-- The chat: the essentials.
	o.Header(L.SECTION_THE_CHAT)
	-- (its display: glass, or the game's own chat as the game draws it)
	local display = Under(Yield(o.Dropdown("CHAT_DISPLAY", L.CHAT_DISPLAY, L.CHAT_DISPLAY_DESC, "glass",
		{ { "glass", L.CHAT_DISPLAY_GLASS }, { "game", L.CHAT_DISPLAY_GAME } },
		function() return Settings().look == "game" and "game" or "glass" end,
		function(value)
			local settings = ns.Settings()
			if not settings then return end
			settings.look = value == "game" and "game" or "glass"
			RefreshGlass()
		end), "chatLook"))
	local glassOn = function() return on() and Settings().look ~= "game" end
	-- (in glass: how long a line stays; the game has no such option)
	Under(o.Dropdown("CHAT_GLASS_FADE", L.GLASS_FADE, L.GLASS_FADE_DESC, "20",
		{ { "20", L.GLASS_FADE_SECONDS:format(20) }, { "60", L.GLASS_FADE_MINUTES:format(1) },
			{ "120", L.GLASS_FADE_MINUTES:format(2) }, { "0", L.GLASS_FADE_NEVER } },
		function() return tostring(tonumber(Settings().glassFade) or 20) end,
		function(value)
			local settings = ns.Settings()
			if not settings then return end
			settings.glassFade = tonumber(value) or 20
			RefreshGlass()
		end), display, glassOn)
	-- (the hours: the game's own option, set from here; nothing kept twice)
	Under(o.Toggle("CHAT_GLASS_TIMES", L.GLASS_TIMES, L.GLASS_TIMES_DESC, true,
		function() return ns.GlassTimesFormat ~= nil and ns.GlassTimesFormat() ~= nil end,
		function(value)
			if InCombatLockdown() then return end
			local current = GetCVar("showTimestamps")
			if value and (current == nil or current == "none") then
				SetCVar("showTimestamps", "%H:%M ")
			elseif not value and current ~= "none" then
				SetCVar("showTimestamps", "none")
			end
			if ns.GlassTimesFormat then ns.GlassTimesFormat() end
		end), display, on)
	local messages = Under(Check("messagesWindow", "MESSAGES_ENABLE", ns.Refresh))
	local messagesOn = Also("messagesWindow")
	local mention = Under(Check("mention", "CHAT_MENTION", ns.RefreshTabs))
	local mentionOn = Also("mention")
	Under(o.Button(L.OTHER_NAMES, L.WORDS_BUTTON, L.OTHER_NAMES_DESC, WordsAsk("otherNames", L.OTHER_NAMES_PROMPT)), mention, mentionOn)
	Under(Check("mentionCard", "MENTION_CARD"), mention, mentionOn)
	-- (under the pad, a press on the card says it at once)
	Under(Check("greetings", "GREETINGS")).descPad = L.GREETINGS_DESC_PAD
	-- (the people in the chat: a card on a name, the answers in its menu)
	Under(Check("nameCard", "NAME_CARD")).descPad = L.NAME_CARD_DESC_PAD
	Under(Check("replies", "REPLIES")).descPad = L.REPLIES_DESC_PAD

	-- The tabs: which ones in the button's card, made there.
	o.Header(L.SECTION_TABS)
	Under(o.Button(L.CHAT_TABS, L.CHAT_TABS_BUTTON, L.CHAT_TABS_DESC, function(button) ns.TabsCard(button) end))
	Under(Check("unread", "UNREAD", ns.RefreshTabs))

	-- The public channels: quieter, a group sought, your words.
	o.Header(L.SECTION_CHANNELS)
	Under(Check("quietChannels", "QUIET_CHANNELS"))
	Under(Check("quietWhispers", "QUIET_WHISPERS"))
	Under(Check("uncensor", "UNCENSOR"))
	Under(o.Button(L.HIDDEN_WORDS, L.WORDS_BUTTON, L.HIDDEN_WORDS_DESC, WordsAsk("hiddenWords", L.HIDDEN_WORDS_PROMPT)))
	-- (what was kept out: the repeats, the gold selling, your hidden words, the strangers' whispers)
	Under(o.Button(L.QUIET_TITLE, L.QUIET_SHOW_THEM, L.QUIET_SHOW_DESC, function()
		o.CloseSettings()
		ns.ShowHidden()
	end))
	Under(Check("lookingFor", "LOOKING_FOR"))
	Under(o.Button(L.WORDS, L.WORDS_BUTTON, L.WORDS_DESC, WordsAsk("words", L.WORDS_PROMPT)))

	-- Finer: in the chat itself (folded under "More settings", as every section below).
	o.Header(L.SECTION_IN_CHAT, { advanced = true })
	Under(Yield(Check("shortChannels", "SHORT_CHANNELS"), "chatLook"))
	Under(Check("emphasis", "EMPHASIS"))
	-- (your name)
	Under(Check("mentionChannels", "CHAT_MENTION_CHANNELS"), mention, mentionOn)
	local sound = Under(Check("mentionSoundOn", "MENTION_SOUND_ON"), mention, mentionOn)
	local sounds = {}
	for _, each in ipairs(SOUNDS) do sounds[#sounds + 1] = { each[1], L[each[2]] } end
	Under(o.Dropdown("CHAT_MENTION_SOUND", L.MENTION_SOUND, L.MENTION_SOUND_DESC, "TELL_MESSAGE", sounds,
		function() return Settings().mentionSound or "TELL_MESSAGE" end,
		function(value)
			local settings = ns.Settings()
			if not settings then return end
			settings.mentionSound = value
			U.PlaySound(value)
		end), sound, function() return mentionOn() and Settings().mentionSoundOn and true or false end)
	-- (its lowest step: each window keeps the size set in the game's own tab menu)
	Under(o.Slider("CHAT_FONT_SIZE", L.CHAT_FONT_SIZE, "chat.fontSize", function(value)
		return value <= ns.GAME_SIZE and L.CHAT_FONT_SIZE_GAME or ("%d"):format(value)
	end, ns.ApplyFontSize))
	-- (the class colors and the rest are the game's own options: shown where they are)
	local gameOptions = Under(o.Button(L.PANEL_GAME_OPTIONS, L.PANEL_GAME_OPTIONS_BUTTON, L.PANEL_GAME_OPTIONS_DESC, function()
		if InCombatLockdown() then return end
		local game = _G.Settings -- (the game's settings: this file's Settings() is the chat's)
		local id = type(game) == "table" and game.SOCIAL_CATEGORY_ID
		if not (id and game.OpenToCategory) then return end
		-- (not with a controller: the game's settings opened from an addon block the game's own actions)
		local util = _G.Wanderer and _G.Wanderer.Util
		if util and util.UsingPad and util.UsingPad() then return end
		o.CloseSettings()
		pcall(game.OpenToCategory, id)
	end))
	-- (not offered with a controller, whenever it is taken up)
	local function UsingPad() return U and U.UsingPad and U.UsingPad() or false end
	if type(gameOptions) == "table" then gameOptions.hidden = UsingPad end

	-- Finer: where the alerts stand.
	-- (placing is the mouse's: not offered with a controller, nor its section, whenever it is taken up)
	if W.PlaceMode then
		local presence = o.Header(L.SECTION_PRESENCE, { advanced = true })
		if type(presence) == "table" then presence.hidden = UsingPad end
		local place = Under(o.Button(L.PLACE, L.PLACE_BUTTON, L.PLACE_DESC, function()
			o.CloseSettings()
			W.PlaceMode()
		end))
		if type(place) == "table" then place.hidden = UsingPad end
	end

	-- Finer: the chat's comforts, writing and reading.
	o.Header(L.SECTION_CHAT_COMFORT, { advanced = true })
	Under(Yield(Check("arrowHistory", "CHAT_ARROWS", ns.RefreshComfort), "chatHistory"))
	Under(Check("copyButton", "CHAT_COPY_BUTTON", ns.RefreshComfort))
	Under(Yield(Check("keepLog", "CHAT_KEEP_LOG"), "chatLog"))
	Under(Check("links", "CHAT_LINKS"))

	-- Finer: the private messages window.
	o.Header(L.SECTION_MESSAGES, { advanced = true })
	Under(Yield(Check("messagesPopup", "MESSAGES_POPUP"), "whispers"), messages, messagesOn)
	Under(Check("messagesSound", "MESSAGES_SOUND"), messages, messagesOn)
	Under(Yield(Check("messagesHideInChat", "MESSAGES_HIDE_CHAT"), "whispers"), messages, messagesOn)
	Under(o.Button(L.MESSAGES_TITLE, L.OPEN, L.MESSAGES_OPEN_DESC, function()
		o.CloseSettings()
		ns.ToggleMessages()
	end), messages, messagesOn)
	for _, side in ipairs({ "me", "them" }) do
		Under(o.Button(L["MESSAGES_COLOR_" .. side:upper()], L.MESSAGES_COLOR_BUTTON, L.MESSAGES_COLOR_DESC, function()
			local r, g, b = ns.MessageColor(side)
			Skin.PickColor(r, g, b, function(nr, ng, nb) ns.SetMessageColor(side, nr, ng, nb) end)
		end), messages, messagesOn)
	end
	Under(o.Button(L.MESSAGES_COLOR_RESET, L.MESSAGES_COLOR_RESET_BUTTON, L.MESSAGES_COLOR_RESET_DESC, function() ns.SetMessageColor(nil) end),
		messages, messagesOn)
end
