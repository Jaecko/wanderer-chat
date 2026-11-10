local _, ns = ...

-- A look at everything drawn over the chat, for a problem seen on screen (/wchat dump): every texture shown in the
-- whole interface whose box crosses the chat's, with its owner, size, opacity and colour, and the glass's own
-- veils line by line. Written into the account's saved data (WandererChatAccountDB.glassDump, replaced each
-- time), read after a /reload. Words for a developer: never translated.

local W = Wanderer
local U = W and W.Util

local MIN_SIZE = 24 -- smaller pieces (icons, letters) left out
local MAX_LINES = 400

local function Clean(value)
	if U then return U.Clean(value) end
	return value
end

local function Path(region)
	local parts, node, guard = {}, region, 0
	while node and guard < 12 do
		guard = guard + 1
		local name = node.GetName and Clean(node:GetName())
		if name then
			table.insert(parts, 1, name)
			break
		end
		local parent = node.GetParent and node:GetParent()
		local key
		if parent then
			for k, v in pairs(parent) do
				if v == node and type(k) == "string" then key = k break end
			end
		end
		table.insert(parts, 1, key or ("<" .. tostring(node.GetObjectType and node:GetObjectType() or "?") .. ">"))
		node = parent
	end
	return table.concat(parts, ".")
end

local function Box(region)
	local ok, left, bottom, width, height = pcall(region.GetRect, region)
	if not ok then return nil end
	left, bottom, width, height = Clean(left), Clean(bottom), Clean(width), Clean(height)
	if type(left) ~= "number" or type(bottom) ~= "number" or type(width) ~= "number" or type(height) ~= "number" then return nil end
	return left, bottom, width, height
end

local function Crosses(a, b)
	return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end

-- The opacity the eye sees: a frame says it; a texture or a text has its own times its frame's.
local function Seen(region)
	if region.GetEffectiveAlpha then return Clean(region:GetEffectiveAlpha()) end
	local own = region.GetAlpha and Clean(region:GetAlpha()) or 1
	local parent = region.GetParent and region:GetParent()
	local above = parent and parent.GetEffectiveAlpha and Clean(parent:GetEffectiveAlpha()) or 1
	if type(own) ~= "number" or type(above) ~= "number" then return nil end
	return own * above
end

local function Fmt(n) return type(n) == "number" and ("%.2f"):format(n) or tostring(n) end

local function Describe(region)
	local left, bottom, width, height = Box(region)
	local alpha = Seen(region)
	local r, g, b, a
	if region.GetVertexColor then r, g, b, a = region:GetVertexColor() end
	local layer, sub
	if region.GetDrawLayer then layer, sub = region:GetDrawLayer() end
	local atlas = region.GetAtlas and Clean(region:GetAtlas())
	local file = region.GetTexture and Clean(region:GetTexture())
	local strata = region.GetParent and region:GetParent() and region:GetParent().GetFrameStrata and region:GetParent():GetFrameStrata()
	return ("%s | %s/%s %s | box=%d,%d %dx%d | effAlpha=%s | vertex=%s,%s,%s,%s | %s"):format(Path(region), tostring(layer),
		tostring(sub), tostring(strata), left or -1, bottom or -1, width or -1, height or -1, Fmt(alpha), Fmt(Clean(r)), Fmt(Clean(g)),
		Fmt(Clean(b)), Fmt(Clean(a)), atlas and ("atlas=" .. atlas) or ("tex=" .. tostring(file)))
end

function ns.GlassDump()
	local lines = {}
	local chat = _G.ChatFrame1
	local cl, cb, cw, ch = Box(chat)
	if not cl then return end
	-- (the chat with its tabs above and its line to write below)
	local area = { cl - 12, cb - 40, cw + 24, ch + 70 }
	lines[#lines + 1] = ("chat box=%d,%d %dx%d at %s"):format(cl, cb, cw, ch, date and date("%H:%M:%S") or "")
	-- Every texture shown, big enough, crossing the chat.
	-- (the glass's own pieces, whatever their size: a veil is one line tall)
	local own = {}
	local pieces = ns.GlassPieces and ns.GlassPieces() or {}
	for _, piece in pairs(pieces) do own[piece] = true end
	local frame = EnumerateFrames and EnumerateFrames()
	local seen = 0
	while frame and #lines < MAX_LINES do
		seen = seen + 1
		if not (frame.IsForbidden and frame:IsForbidden()) and frame.IsVisible and frame:IsVisible() and frame.GetRegions then
			for _, region in ipairs({ frame:GetRegions() }) do
				-- (each piece looked at under a guard: one the game keeps to itself never stops the look)
				pcall(function()
					if not (region.GetObjectType and region:GetObjectType() == "Texture" and region:IsVisible()) then return end
					local left, bottom, width, height = Box(region)
					local alpha = Seen(region)
					local big = left and (own[frame] or (width >= MIN_SIZE and height >= MIN_SIZE))
					if big and type(alpha) == "number" and alpha > 0.02 and Crosses({ left, bottom, width, height }, area) then
						local ok, text = pcall(Describe, region)
						lines[#lines + 1] = ok and text or ("? " .. tostring(text))
					end
				end)
			end
		end
		frame = EnumerateFrames(frame)
	end
	-- The glass's veils, line by line.
	if ns.GlassVeils then
		for _, text in ipairs(ns.GlassVeils()) do lines[#lines + 1] = text end
	end
	lines[#lines + 1] = ("frames looked at: %d"):format(seen)
	WandererChatAccountDB = WandererChatAccountDB or {}
	WandererChatAccountDB.glassDump = lines
	return #lines
end
