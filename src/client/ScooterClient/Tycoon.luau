-- Tycoon boards (owner, 24 Oct: "make the game feel a bit more like a tycoon. players should know what does
-- what and why without too much text"). Once the trash is out at night (the Night attribute), every machine
-- you can still upgrade gets a small board over it: its icon, a pip per level and the price, green when you
-- can afford it. The next two machines you haven't bought yet (cheapest first) stand as blue see-through
-- ghosts where they will go, with a padlock on their boards. Tap a board to buy (the same buy as the upgrade stand's list); the machine pops in
-- and the board moves on to the next level. No words on the boards, only the price.
-- Owner, 24 Oct: too much clutter. Now only the machine you're standing near shows its board, plus one gold
-- "next goal" board (the cheapest thing you can buy next), and only one ghost at a time.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local M = {}
local env -- player, config, style, garage, myStations, stations (shop id -> station name), templates, P, buy(item), busy()
local boards = {} -- [id] = { bb, anchor, icon, lock, pips, price, priceBg, scale }
local ghosts = {} -- [id] = model
local folder

-- machines that are part of the garage itself
local BUILT_IN = { Bench = "Bench", Belt = "Conveyor", Bin = "Dumpster" }
local ICON = { WashBay = "Bucket" } -- shop items without an Icon of their own
local GHOST = Color3.fromRGB(60, 140, 255)
local NEXT_LOCKED = 1 -- how many machines you don't own yet show a ghost at once
local NEAR = 12 -- studs: you're standing at a machine when you're this close to its board
local W, H = 3.6, 1.7 -- studs

local function outline(o, t)
	local s = Instance.new("UIStroke")
	s.Color = env.style.Color.Ink
	s.Thickness = t or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

local function at(x, y, w, h)
	return UDim2.fromScale(x / W, y / H), UDim2.fromScale(w / W, h / H)
end

local function makeBoard(item)
	local Style = env.style
	local anchor = Instance.new("Part")
	anchor.Name = "Board_" .. item.Id
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tycoon_" .. item.Id
	bb.Adornee = anchor
	bb.AlwaysOnTop = true
	bb.Active = true
	bb.LightInfluence = 0
	bb.MaxDistance = 45
	bb.ResetOnSpawn = false
	bb.Size = UDim2.fromScale(W, H)
	bb.Enabled = false
	local hit = Instance.new("TextButton")
	hit.Name = "Card"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundColor3 = Style.Color.White
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = bb
	Instance.new("UICorner", hit).CornerRadius = UDim.new(0, Style.Radius.Small)
	outline(hit)
	local scale = Instance.new("UIScale")
	scale.Parent = hit
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Style.Icon[item.Icon or ICON[item.Id]] or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Position, icon.Size = at(0.15, 0.15, 1.4, 1.4)
	icon.Parent = hit
	local lock = Instance.new("ImageLabel")
	lock.Name = "Lock"
	lock.BackgroundTransparency = 1
	lock.Image = Style.Icon.Padlock
	lock.ScaleType = Enum.ScaleType.Fit
	lock.Position, lock.Size = at(0.95, 0.85, 0.75, 0.75)
	lock.ZIndex = 2
	lock.Parent = hit
	local pips = Instance.new("Frame")
	pips.Name = "Pips"
	pips.BackgroundTransparency = 1
	pips.Position, pips.Size = at(1.75, 0.2, 1.65, 0.38)
	pips.Parent = hit
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0.06, 0)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = pips
	-- upgrade system v5: 10 dots, the tier-ups (1, 4, 8) full height, the boosts shorter
	local count = item.Ups or #item.Names
	list.Padding = UDim.new(0.03, 0)
	for i = 1, count do
		local p = Instance.new("Frame")
		p.Name = tostring(i)
		p.LayoutOrder = i
		p.BorderSizePixel = 0
		local big = item.Ups and env.config.TierUps[i]
		p.Size = UDim2.fromScale(1 / count - 0.03, big and 1 or 0.6)
		Instance.new("UICorner", p).CornerRadius = UDim.new(0, 2)
		outline(p, 1.5)
		p.Parent = pips
	end
	local priceBg = Instance.new("Frame")
	priceBg.Name = "Price"
	priceBg.BorderSizePixel = 0
	priceBg.Position, priceBg.Size = at(1.75, 0.78, 1.65, 0.75)
	priceBg.Parent = hit
	Instance.new("UICorner", priceBg).CornerRadius = UDim.new(0, Style.Radius.Small)
	outline(priceBg)
	local price = Instance.new("TextLabel")
	price.BackgroundTransparency = 1
	price.Size = UDim2.fromScale(1, 1)
	price.FontFace = Style.Font.Chunky
	price.TextScaled = true
	price.TextColor3 = Style.Color.White
	price.Parent = priceBg
	local ps = Instance.new("UIStroke")
	ps.Color = Style.Color.Ink
	ps.Thickness = 1.5
	ps.Parent = price
	Instance.new("UIPadding", price).PaddingTop = UDim.new(0.12, 0)
	bb.Parent = env.player:WaitForChild("PlayerGui")
	local b = { bb = bb, anchor = anchor, icon = icon, lock = lock, pips = pips, price = price, priceBg = priceBg, scale = scale }
	local buying = false
	hit.Activated:Connect(function()
		if buying or env.busy() then return end
		buying = true
		scale.Scale = 0.88
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		env.buy(item)
		buying = false
	end)
	boards[item.Id] = b
	return b
end

-- Where a machine you haven't bought will stand: its level-1 look, see-through, no collisions.
local function ghostOf(item, name)
	if ghosts[item.Id] then return ghosts[item.Id] end
	local t = env.templates:FindFirstChild(name)
	if not t then return nil end
	local m = t:Clone()
	for _, d in m:GetDescendants() do
		local lo = d:GetAttribute("TierMin")
		if lo and lo > 1 then d:Destroy() end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
			d.Material = Enum.Material.SmoothPlastic
			d.Color = GHOST
			d.Transparency = math.max(d.Transparency, 0.45)
			if d:IsA("MeshPart") then d.TextureID = "" end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif not (d:IsA("Model") or d:IsA("Folder") or d:IsA("Attachment") or d:IsA("SpecialMesh") or d:IsA("WeldConstraint") or d:IsA("Weld")) then
			d:Destroy() -- prompts, sounds, lights, effects, guis
		end
	end
	m:PivotTo(env.P.PF * m:GetPivot())
	m.Name = "Ghost_" .. item.Id
	ghosts[item.Id] = m
	return m
end

local function topOf(o)
	if o:IsA("Model") then
		local cf, size = o:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y / 2, 0)
	end
	return o.Position + Vector3.new(0, o.Size.Y / 2, 0)
end

local function refresh()
	local Style, player = env.style, env.player
	local night = player:GetAttribute("Night") == true and not env.busy()
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash") and stats.Cash.Value or 0
	-- the machines you don't own yet that may show: cheapest first
	local locked = {}
	for _, item in env.config.Shop do
		if item.Kind == "Level" and (item.Icon or ICON[item.Id]) and env.stations[item.Id] and (player:GetAttribute(item.Id) or 0) == 0
			and not (item.Needs and (player:GetAttribute(item.Needs) or 0) == 0)
			and env.config.gateOpen(item, function(g) return player:GetAttribute(g) end) then
			table.insert(locked, item)
		end
	end
	table.sort(locked, function(a, b) return a.Prices[1] < b.Prices[1] end)
	-- the next goal: the cheapest thing you could buy next (a level-up or the first ghost)
	local goal, goalPrice = nil, math.huge
	for _, item in env.config.Shop do
		if item.Kind == "Level" and (item.Icon or ICON[item.Id]) then
			local lv = player:GetAttribute(item.Id) or 0
			local p = item.Prices[lv + 1]
			local ok = p and not (item.Needs and (player:GetAttribute(item.Needs) or 0) == 0)
			if ok and lv == 0 then ok = locked[1] == item end
			if ok and p < goalPrice then goal, goalPrice = item.Id, p end
		end
	end
	local char = player.Character
	local me = char and char:FindFirstChild("HumanoidRootPart")
	local placed = {} -- board positions so far: a board too close to another one goes on top of it
	for _, item in env.config.Shop do
		if item.Kind ~= "Level" or not (item.Icon or ICON[item.Id]) then continue end
		local level = player:GetAttribute(item.Id) or 0
		local price = item.Prices[level + 1]
		local waiting = (item.Needs and (player:GetAttribute(item.Needs) or 0) == 0)
			or (level == 0 and not env.config.gateOpen(item, function(g) return player:GetAttribute(g) end))
		local station = env.stations[item.Id]
		local where
		if station then
			where = env.myStations:FindFirstChild(station)
		elseif item.Id == "Charger" then
			where = env.myStations:FindFirstChild("BatteryDock")
		elseif BUILT_IN[item.Id] then
			where = env.garage:FindFirstChild(BUILT_IN[item.Id])
		end
		local rank = table.find(locked, item)
		local wantGhost = night and level == 0 and price ~= nil and not where and rank ~= nil and rank <= NEXT_LOCKED
		local ghost = wantGhost and ghostOf(item, station) or ghosts[item.Id]
		if ghost then ghost.Parent = wantGhost and folder or nil end
		if wantGhost then where = ghost end
		local show = night and price ~= nil and not waiting and where ~= nil
		if show and item.Id ~= goal and me then
			local flat = topOf(where) - me.Position
			show = Vector3.new(flat.X, 0, flat.Z).Magnitude <= NEAR
		end
		local b = boards[item.Id] or (show and makeBoard(item))
		if b then
			b.bb.Enabled = show
			if show then
				local top = topOf(where) + Vector3.new(0, 1.4, 0)
				if item.Id == "Charger" then top += env.P.vec(Vector3.new(-3.8, 0, 0)) end -- beside the rack's own board
				local moved = true
				while moved do
					moved = false
					for _, p in placed do
						local flat = Vector3.new(p.X - top.X, 0, p.Z - top.Z).Magnitude
						if flat < W * 0.95 and math.abs(p.Y - top.Y) < H * 1.05 then
							top = Vector3.new(top.X, p.Y + H * 1.1, top.Z)
							moved = true
						end
					end
				end
				table.insert(placed, top)
				if (b.anchor.Position - top).Magnitude > 0.05 then b.anchor.Position = top end
				b.lock.Visible = level == 0
				local edge = b.bb.Card:FindFirstChildOfClass("UIStroke")
				if edge then
					edge.Color = item.Id == goal and Style.Color.Gold or Style.Color.Ink
					edge.Thickness = item.Id == goal and 3 or 2
				end
				for _, p in b.pips:GetChildren() do
					local i = tonumber(p.Name)
					local done = item.Ups and env.config.upgradesOf(level) or level
					if i then p.BackgroundColor3 = i <= done and Style.Color.Gold or Style.Color.EnamelLine end
				end
				b.price.Text = "$" .. Style.money(price)
				b.priceBg.BackgroundColor3 = cash >= price and Style.Color.Cash or Style.Color.EnamelLine
			end
		end
	end
end

function M.init(e)
	env = e
	folder = Instance.new("Folder")
	folder.Name = "TycoonBoards"
	folder.Parent = workspace
	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then warn("Tycoon boards: " .. tostring(err)) end
			task.wait(0.4)
		end
	end)
end

return M
