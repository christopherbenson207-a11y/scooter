-- Customer bubbles, Cooking Fever style: pictures instead of words.
-- Waiting: what their scooter needs (one icon per fix, the paint can in the colour they want) over a patience
-- bar that drains green, yellow, red. Owner, 24 Oct: no emojis at all (they get annoying), so there are no
-- faces or reactions: their body shows how they feel (ScooterClient.Fun animations) and the bar's colour.
-- Only the customer who's waited longest and anyone within NEAR studs of you show a bubble (plan/11 clutter rule).
-- Sizes are in studs, so far-off bubbles shrink instead of covering the screen.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Style = require(RS:WaitForChild("UIStyle"))

local M = {}
local ctx -- customers, pclock, active()

local FIX_ICON = {
	Tyre = "Tyre", Worn = "TyreRack", Charge = "Charger", Battery = "Battery", Nitro = "Nitro",
	Light = "Bulb", Mud = "Bucket", Rust = "Bucket", Paint = "PaintCan", Bolts = "Wrench", -- mud and rust: the wash bay
}
local FACES = {} -- no faces (owner, 24 Oct)
local NEAR = 40 -- studs: bubbles show for customers this close to you (plus the one who's waited longest)
local Players = game:GetService("Players")
local CELL, BAR, PAD, TAIL, EDGE = 1.5, 0.3, 0.3, 0.5, 0.5 -- studs

local function icon(name, job)
	if name == "Paint" and job.PaintTo then
		local to = tostring(job.PaintTo)
		if to:find("Blue") then return Style.Icon.PaintBlue end
		if to:find("Yellow") then return Style.Icon.PaintYellow end
	end
	return Style.Icon[FIX_ICON[name] or "Wrench"]
end

local function outline(o)
	local s = Instance.new("UIStroke")
	s.Color = Style.Color.Ink
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
end

local function frame(name, parent, color, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color or Style.Color.White
	f.BackgroundTransparency = color and 0 or 1
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function emoji(name, parent, z)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.FontFace = Style.Font.Sans
	t.Text = ""
	t.ZIndex = z
	t.Parent = parent
	return t
end

function M.attach(c)
	local head = c.model and c.model:FindFirstChild("Head")
	if not head then return end
	local old = head:FindFirstChild("Bubble")
	if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Bubble"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 90
	bb.Enabled = false
	local root = frame("Root", bb)
	root.Size = UDim2.fromScale(1, 1)
	local pop = Instance.new("UIScale")
	pop.Parent = root
	local card = frame("Card", root, Style.Color.White, 2)
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, Style.Radius.Small)
	outline(card)
	local tail = frame("Tail", root, Style.Color.White, 1)
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Rotation = 45
	outline(tail)
	local icons = frame("Icons", card, nil, 3)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = icons
	local problems = c.job and c.job.Problems or {}
	for i, name in problems do
		local im = Instance.new("ImageLabel")
		im.BackgroundTransparency = 1
		im.Image = icon(name, c.job)
		im.ScaleType = Enum.ScaleType.Fit
		im.Size = UDim2.fromScale(1 / #problems, 1)
		im.LayoutOrder = i
		im.ZIndex = 3
		im.Parent = icons
	end
	local bar = frame("Bar", card, Style.Color.Track, 3)
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local fill = frame("Fill", bar, Style.Color.Cash, 4)
	fill.Size = UDim2.fromScale(1, 1)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local react = emoji("React", card, 3)
	local face = emoji("Face", root, 5)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	-- a VIP: gold bubble edge, a crown on its corner and a gold outline round them
	local crown
	if c.job and c.job.Mood == "VIP" then
		crown = Instance.new("ImageLabel")
		crown.Name = "Crown"
		crown.BackgroundTransparency = 1
		crown.Image = Style.Icon.Star
		crown.ScaleType = Enum.ScaleType.Fit
		crown.ZIndex = 5
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Parent = root
		card.UIStroke.Color = Style.Color.Gold
		card.UIStroke.Thickness = 3
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = Style.Color.Gold
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = c.model
	end
	bb.Parent = head
	c.bubble = { bb = bb, pop = pop, card = card, tail = tail, icons = icons, bar = bar, fill = fill, react = react,
		face = face, crown = crown, n = #problems }
end

-- Size and place everything for a mode: "order" (icons + bar) or "react" / "face" (one emoji).
local function layout(b, mode)
	local cw, ch
	if mode == "order" then
		cw, ch = b.n * CELL + 2 * PAD, PAD + CELL + PAD * 0.7 + BAR + PAD
	else
		cw, ch = CELL + 2 * PAD, CELL + 2 * PAD
	end
	local W, H = cw + 2 * EDGE, ch + TAIL + EDGE
	b.bb.Size = UDim2.fromScale(W, H)
	b.bb.StudsOffset = Vector3.new(0, 0.9 + H / 2, 0)
	local function at(x, y) return UDim2.fromScale(x / W, y / H) end
	b.card.Position, b.card.Size = at(EDGE, EDGE), at(cw, ch)
	b.tail.Position, b.tail.Size = at(W / 2, EDGE + ch), at(TAIL, TAIL)
	b.face.Position, b.face.Size = at(EDGE + cw - 0.15, EDGE + 0.15), at(1.1, 1.1)
	if b.crown then b.crown.Position, b.crown.Size = at(EDGE + 0.1, EDGE + 0.05), at(1, 1) end
	local function inCard(x, y) return UDim2.fromScale(x / cw, y / ch) end
	b.icons.Position, b.icons.Size = inCard(PAD, PAD), inCard(cw - 2 * PAD, CELL)
	b.bar.Position, b.bar.Size = inCard(PAD, PAD + CELL + PAD * 0.7), inCard(cw - 2 * PAD, BAR)
	b.react.Position, b.react.Size = inCard(PAD, PAD), inCard(CELL, CELL)
	b.icons.Visible = mode == "order"
	b.bar.Visible = mode == "order"
	b.react.Visible = mode ~= "order"
end

local function bump(b)
	b.pop.Scale = 0.6
	TweenService:Create(b.pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function update()
	local act = ctx.active()
	local now = os.clock()
	local char = Players.LocalPlayer.Character
	local me = char and char:FindFirstChild("HumanoidRootPart")
	-- the one who's waited longest (least patience left) always shows, so the yard never goes blank
	local first, least = nil, math.huge
	for _, c in ctx.customers do
		if c.job and not c.done and c.expires and not (act and act.customer == c) and c.expires < least then
			first, least = c, c.expires
		end
	end
	for _, c in ctx.customers do
		local b = c.bubble
		if b and b.bb.Parent then
			c.react, c.reactUntil = nil, nil
			local mine = act and act.customer == c
			local head = b.bb.Parent
			local near = c == first or not me or (head:IsA("BasePart") and (head.Position - me.Position).Magnitude <= NEAR)
			local order = c.job ~= nil and not c.done and not mine and c.expires ~= nil and near
			local face = FACES[c.mood or 0]
			if c.done then face = nil end
			local mode = c.react and "react" or order and "order" or face and "face" or nil
			if mode ~= b.mode then
				b.mode = mode
				b.bb.Enabled = mode ~= nil
				if mode then layout(b, mode) bump(b) end
			end
			local middle = mode == "react" and c.react or mode == "face" and face or ""
			if b.react.Text ~= middle then
				b.react.Text = middle
				if middle ~= "" then bump(b) end
			end
			local corner = mode == "order" and face or ""
			if b.face.Text ~= corner then
				b.face.Text = corner
				b.face.Visible = corner ~= ""
			end
			if mode == "order" then
				local left = math.clamp((c.expires - ctx.pclock()) / c.patience, 0, 1)
				b.fill.Size = UDim2.fromScale(left, 1)
				b.fill.BackgroundColor3 = left > 0.5 and Style.Color.Cash or left > 0.25 and Style.Color.Gold or Style.Color.Stop
				b.fill.BackgroundTransparency = left < 0.2 and math.sin(now * 14) > 0 and 0.6 or 0
			end
		end
	end
end

-- Reactions used to pop an emoji; now they show nothing (owner, 24 Oct). Kept so callers don't change.
function M.say(c)
	if not c.bubble then M.attach(c) end
	c.react, c.reactUntil = nil, nil
end

-- Customers step off the bus out of sight: fade them (and what they're pushing) in where they appear.
function M.fadeIn(models, time)
	local parts = {}
	for _, model in models do
		for _, p in model:GetDescendants() do
			if (p:IsA("BasePart") or p:IsA("Decal")) and p.Transparency < 1 then
				table.insert(parts, { p, p.Transparency })
				p.Transparency = 1
			end
		end
	end
	task.spawn(function()
		local t = 0
		while t < time do
			t += RunService.Heartbeat:Wait()
			local a = math.min(1, t / time)
			for _, e in parts do
				if e[1].Parent then e[1].Transparency = 1 - (1 - e[2]) * a end
			end
		end
	end)
end

function M.init(e)
	ctx = e
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(update)
			if not ok then warn("Bubbles: " .. tostring(err)) end
		end
	end)
end

return M
