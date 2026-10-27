-- The always-on HUD (plan/09-UI-STYLE.md, glossy simulator look): the day / night countdown and the
-- next-goal hang tag, the customer list's tuck tab. The frames are authored by ServerStorage.ShopTicketKit; this only fills them in.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")

local Style = require(RS:WaitForChild("UIStyle"))
local C = Style.Color

local player = Players.LocalPlayer
local Hud = {}

local gui, config
local lobby = true -- false while a fix runs (focus mode: the goal tag waits)

-- The Roblox top bar's buttons sit over the top-left corner (owner, 24 Oct: the cash and the tag under it were
-- hidden, PC and phone). The left stack starts under the bar: how far down it reaches, in canvas units.
local stackTop = Style.Edge
local function topbarDepth()
	if not gui then return 0 end
	local scale = gui:FindFirstChild("Fit") and gui.Fit.Scale or 1
	return math.max(0, (GuiService.TopbarInset.Max.Y - gui.AbsolutePosition.Y) / scale)
end

---------------------------------------------------------------- countdown
-- Time left in the day (or night). PC: bottom right, lifted over the Leave button during a fix.
-- Phone: top centre (bottom right is the jump button); during a fix under the cash, as the instruction line
-- has the top centre; hidden while the shop or pay screen is open (they reach the top of a phone).
-- The job's star timer (owner, 24 Oct): PC bottom right, over the Leave button; phone at the very top centre,
-- with the instruction line moved down under it.
local function placeTimer(phone)
	local timer = gui:FindFirstChild("Timer")
	if not timer then return 0 end
	local scale = gui:FindFirstChild("Fit") and gui.Fit.Scale or 1
	local ins = gui:FindFirstChild("Instruction")
	if phone then
		timer.AnchorPoint = Vector2.new(0.5, 0)
		timer.Position = UDim2.new(0.5, 0, 0, Style.Edge)
		-- plan/12: the instruction lives at the BOTTOM centre now — the top belongs to the
		-- countdown and the customers' bubbles, which it used to cover
		if ins then
			ins.AnchorPoint = Vector2.new(0.5, 1)
			ins.Position = UDim2.new(0.5, 0, 1, -84)
		end
		return 0
	end
	if ins then
		ins.AnchorPoint = Vector2.new(0.5, 1)
		ins.Position = UDim2.new(0.5, 0, 1, -Style.Edge - 58)
	end
	local leave = gui:FindFirstChild("Leave")
	local lift = (leave and leave.Visible) and (leave.AbsoluteSize.Y / scale + 12) or 0
	timer.AnchorPoint = Vector2.new(1, 1)
	timer.Position = UDim2.new(1, -Style.Edge, 1, -Style.Edge - lift)
	return timer.Visible and (lift + timer.Size.Y.Offset + 10) or lift
end

local function placeCountdown()
	local cd = gui:FindFirstChild("Countdown")
	if not cd then return end
	local phone = Style.fitScale(workspace.CurrentCamera.ViewportSize) == 0.85
	local above = placeTimer(phone)
	if phone then
		-- a centred panel reaches the top on a phone: the clock steps aside while one is open
		local panel = false
		for _, n in { "Shop", "Store", "PayPanel", "Restock" } do
			if gui:FindFirstChild(n) and gui[n].Visible then panel = true end
		end
		cd.Visible = not panel
		-- the instruction line takes the top centre (a fix, a trash run): then the clock waits under the cash
		local ins = gui:FindFirstChild("Instruction")
		if lobby and not (ins and ins.Visible) then
			cd.AnchorPoint = Vector2.new(0.5, 0)
			cd.Position = UDim2.new(0.5, 0, 0, Style.Edge)
		else
			-- the instruction line has the top centre during a fix: the clock waits under the cash
			cd.AnchorPoint = Vector2.new(0, 0)
			cd.Position = UDim2.fromOffset(Style.Edge, stackTop + 56)
		end
	else
		cd.Visible = true
		cd.AnchorPoint = Vector2.new(1, 1)
		-- stacked over the Leave button and the job timer when they show
		cd.Position = UDim2.new(1, -Style.Edge, 1, -Style.Edge - (lobby and 0 or above))
	end
end

local function updateCountdown()
	local cd = gui:FindFirstChild("Countdown")
	if not cd then return end
	-- like Steal An Egg's night timer: the icon is what comes next, the text is how long until it does
	local night = workspace:GetAttribute("Phase") == "Night"
	local left = math.max(0, math.floor((workspace:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
	cd.Time.Text = left >= 60 and ("in %dm %ds"):format(left // 60, left % 60) or ("in %ds"):format(left)
	if cd:GetAttribute("Night") ~= night then
		cd:SetAttribute("Night", night)
		cd.Icon.Image = night and Style.Icon.Sun or Style.Icon.Moon
	end
end

---------------------------------------------------------------- customers lost today
-- Owner, 24 Oct: a small chip beside the cash, "2 lost today", from the server's LostToday attribute (resets at
-- dawn). Hidden while nobody has gone home; it gives a little shake each time it goes up.
local function lostChip()
	local cash = gui:FindFirstChild("Cash")
	if not cash then return end
	local chip = Instance.new("Frame")
	chip.Name = "LostToday"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(1, 86, 0.5, 0)
	chip.Size = UDim2.fromOffset(0, 34)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.BackgroundColor3 = C.White or Color3.new(1, 1, 1)
	chip.Visible = false
	chip.ZIndex = cash.ZIndex
	Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", chip)
	stroke.Thickness = 2.5
	stroke.Color = C.Ink
	local pad = Instance.new("UIPadding", chip)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 10)
	local row = Instance.new("UIListLayout", chip)
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 4)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(24, 24)
	icon.Image = Style.Icon.Cross
	icon.ZIndex = chip.ZIndex + 1
	icon.Parent = chip
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromOffset(0, 28)
	text.AutomaticSize = Enum.AutomaticSize.X
	text.FontFace = Style.Font.Chunky
	text.TextSize = 18
	text.TextColor3 = C.Stop
	text.ZIndex = chip.ZIndex + 1
	text.Parent = chip
	local scale = Instance.new("UIScale", chip)
	local shown = 0
	local function update()
		local n = player:GetAttribute("LostToday") or 0
		text.Text = ("%d lost today"):format(n)
		chip.Visible = n > 0
		if n > shown then
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		shown = n
	end
	player:GetAttributeChangedSignal("LostToday"):Connect(update)
	update()
end

---------------------------------------------------------------- next goal
-- The cheapest machine, unlock or upgrade you could buy next (stock refills never count).
local function nextGoal()
	local byId = {}
	for _, item in config.Shop do byId[item.Id] = item end
	local best, bestPrice
	for _, item in config.Shop do
		if item.Starter or item.Kind == "Stock" then continue end
		local holder = item.Holder and byId[item.Holder]
		if holder and holder.Locked and (player:GetAttribute(item.Holder) or 0) == 0 then continue end
		if item.Needs and (player:GetAttribute(item.Needs) or 0) == 0 then continue end
		local level = player:GetAttribute(item.Id) or 0
		-- waiting for a bench or garage tier (Gate): not a goal yet
		if level == 0 and config.gateOpen and not config.gateOpen(item, function(g) return player:GetAttribute(g) end) then continue end
		local price
		if item.Kind == "Level" then
			price = item.Prices and item.Prices[level + 1]
		elseif level == 0 then
			price = item.Price
		end
		if price and (not bestPrice or price < bestPrice) then
			best, bestPrice = item, price
		end
	end
	return best, bestPrice
end

local ready = false
local function updateGoal()
	local tag = gui:FindFirstChild("Goal")
	if not tag then return end
	local item, price = nextGoal()
	tag.Visible = lobby and item ~= nil
	if not item then return end
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash") and ls.Cash.Value or 0
	tag.Icon.Image = Style.Icon[item.Icon or ""] or Style.Icon.Wrench
	tag.Price.Text = "$" .. Style.money(price)
	TweenService:Create(tag.Bar.Fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(cash / price, 0, 1), 1) }):Play()
	local nowReady = cash >= price
	if nowReady ~= ready then
		tag.Gloss.Color = Style.glossColors(nowReady and C.Gold or C.Panel)
	end
	ready = nowReady
end

-- While affordable the tag swings on its hole every 4 s.
local function swing(tag)
	local steps = { 8, -5, 0 }
	for _, deg in steps do
		local t = TweenService:Create(tag, TweenInfo.new(0.5 / #steps, Enum.EasingStyle.Sine), { Rotation = deg })
		t:Play()
		t.Completed:Wait()
	end
end

---------------------------------------------------------------- customer list
-- Owner, 24 Oct: the big cards were clutter. Each waiting customer is now a small square tile top right: the
-- scooter, how many fixes (badge) and a patience bar along the bottom. Tap a tile and it opens into the full
-- card (name, fixes, pay, the X that sends them away for Robux) for OPEN_FOR seconds, then shrinks back.
-- The X still goes through ScooterServer RejectJob / ProcessReceipt.
local tucked = false -- no tuck tab any more: the tiles are small enough to stay
local OPEN_FOR = 4
local function isPhone()
	return Style.fitScale(workspace.CurrentCamera.ViewportSize) == 0.85
end

local shapeRow -- below, with the rest of the phone layout

local function placeCustomers(animate)
	local list = gui:FindFirstChild("Customers")
	if not list then return end
	local phone = isPhone()
	if tucked == nil then tucked = phone end
	local w = phone and 184 or 260
	list.Toggle.Visible = false
	list.Rows.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right -- tiles hug the right edge; an open card grows left
	local goal = UDim2.new(1, tucked and w + 6 or -Style.Edge, 0, 102)
	if animate then
		TweenService:Create(list, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = goal }):Play()
	else
		list.Position = goal
	end
end

local function wireRow(row)
	if not row:IsA("Frame") or row.Name ~= "Row" then return end
	-- the whole tile is a button: tap to open the full card, it closes again by itself
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = row.ZIndex
	tap.Parent = row
	local token
	tap.Activated:Connect(function()
		local open = not row:GetAttribute("Open")
		row:SetAttribute("Open", open)
		shapeRow(row, isPhone())
		local mine = {}
		token = mine
		if open then
			task.delay(OPEN_FOR, function()
				if token == mine and row.Parent then
					row:SetAttribute("Open", false)
					shapeRow(row, isPhone())
				end
			end)
		end
	end)
	row:GetAttributeChangedSignal("Fixes"):Connect(function() shapeRow(row, isPhone()) end)
	shapeRow(row, isPhone())
	row.Reject.Button.Activated:Connect(function()
		local id = row:GetAttribute("JobId")
		if not id then return end
		local r = RS.ScooterRemotes.RejectJob:InvokeServer(id)
		if r == "prompt" then MarketplaceService:PromptProductPurchase(player, config.RejectProductId) end
	end)
end

---------------------------------------------------------------- phone layout
-- Phones get their own layout of the same pieces (plan/09-UI-STYLE.md, Scale and Where things go): a 993 x 459
-- canvas, the bottom corners belong to the thumbstick and the jump button, the job ticket shows one fix at a
-- time, the customer cards drop the name but keep fixes, pay, patience and the X. Every PC piece is still there.
-- Hud.layout is pure (gui, phone) so the edit-mode preview can run it too.
-- a small square tile: picture, fix-count badge, patience bar along the bottom
local function shapeTile(row, phone)
	local s = phone and 56 or 64
	row.Size = UDim2.fromOffset(s, s)
	row.Title.Visible = false
	row.Info.Visible = false
	row.Reject.Visible = false
	row.Pic.AnchorPoint = Vector2.zero
	row.Pic.Position = UDim2.fromOffset(8, 3)
	row.Pic.Size = UDim2.fromOffset(s - 12, s - 16)
	row.Bar.Position = UDim2.new(0, 9, 1, -11)
	row.Bar.Size = UDim2.new(1, -15, 0, 6)
	local badge = row:FindFirstChild("Count")
	if not badge then
		badge = Instance.new("TextLabel")
		badge.Name = "Count"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -3, 0, 3)
		badge.Size = UDim2.fromOffset(20, 20)
		badge.BackgroundColor3 = Style.Color.Ink
		badge.TextColor3 = Style.Color.White
		badge.FontFace = Style.Font.Chunky
		badge.TextSize = 14
		badge.ZIndex = row.ZIndex + 3
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, Style.Radius.Small)
		badge.Parent = row
	end
	badge.Text = tostring(row:GetAttribute("Fixes") or "")
	badge.Visible = badge.Text ~= ""
end

shapeRow = function(row, phone)
	if not row:GetAttribute("Open") then return shapeTile(row, phone) end
	if row:FindFirstChild("Count") then row.Count.Visible = false end
	row.Info.Visible = true
	row.Reject.Visible = true
	row.Pic.AnchorPoint = Vector2.new(0, 0.5)
	row.Pic.Position = UDim2.new(0, 14, 0.5, 0)
	-- phones drop the name (the picture shows the scooter) but keep the fixes and pay, patience and the X
	-- (owner, 24 Oct: on phones the X covered the fixes and pay, so there it moves down beside the patience bar)
	local w = phone and 184 or 260
	row.Size = UDim2.fromOffset(w, phone and 54 or 62)
	row.Title.Visible = not phone
	row.Info.Position = UDim2.fromOffset(phone and 58 or 74, phone and 6 or 27)
	row.Info.Size = UDim2.new(1, phone and -64 or -144, 0, 16)
	row.Pic.Size = UDim2.fromOffset(phone and 44 or 54, phone and 44 or 54)
	row.Bar.Position = UDim2.fromOffset(phone and 58 or 74, phone and 34 or 46)
	row.Bar.Size = UDim2.fromOffset(phone and w - 58 - 54 or 172, 8)
	row.Reject.AnchorPoint = phone and Vector2.new(1, 1) or Vector2.new(1, 0)
	row.Reject.Position = phone and UDim2.new(1, -6, 1, -5) or UDim2.new(1, -8, 0, 8)
	row.Reject.Size = UDim2.fromOffset(phone and 42 or 60, phone and 24 or 30)
end

local function shapeFix(row, phone)
	if not row:IsA("Frame") or not row:FindFirstChild("Box") then return end
	row.Size = UDim2.new(1, 0, 0, phone and 44 or 36)
	row.Box.Size = UDim2.fromOffset(phone and 32 or 26, phone and 32 or 26)
	row.Box.Tick.Size = UDim2.fromOffset(phone and 38 or 30, phone and 38 or 30)
end

-- The ticket head on a narrow card: the title tab stops short of the 1/3 count (a long name ends in "..."),
-- and the rarity / pay / mood chips shrink together when they'd run past the card's edge.
local function fitHead(job, phone)
	local head = job:FindFirstChild("Head")
	if not head then return end
	local tabMax = (phone and 230 or 250) - 20 - 40
	local tab = head:FindFirstChild("Tab")
	if tab then
		local c = tab:FindFirstChildOfClass("UISizeConstraint")
		if c then c.MaxSize = Vector2.new(tabMax, 40) end
		local title = tab:FindFirstChild("Title")
		if title then
			local tc = title:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint")
			tc.MaxSize = Vector2.new(tabMax - 28, math.huge)
			tc.Parent = title
			title.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end
end

local function fitChips(info)
	local list = info:FindFirstChildOfClass("UIListLayout")
	local scale = info:FindFirstChild("Fit") or Instance.new("UIScale")
	scale.Name = "Fit"
	scale.Parent = info
	local room = info.Parent.AbsoluteSize.X
	local used = list and list.AbsoluteContentSize.X or 0
	if room <= 0 or used <= 0 then return end
	local want = math.clamp(scale.Scale * room / used, 0.6, 1)
	if math.abs(want - scale.Scale) > 0.01 then scale.Scale = want end
end

-- Phones show one fix at a time: the first one not ticked yet (fixes run in order). The head's 1/3 shows how
-- far along the job is. PC shows the whole list.
local function showFixes(g, phone)
	local job = g:FindFirstChild("JobCard")
	if not job then return end
	local list = {}
	for _, row in job:GetChildren() do
		if row:IsA("Frame") and row:FindFirstChild("Box") and row.Name ~= "RowTemplate" then table.insert(list, row) end
	end
	table.sort(list, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	local current
	for _, row in list do
		if not row:GetAttribute("Done") then current = row break end
	end
	current = current or list[#list]
	for _, row in list do row.Visible = not phone or row == current end
end
Hud.showFixes = showFixes

-- top: where the left stack starts (under the Roblox top bar); the edit preview leaves it at the edge.
function Hud.layout(g, phone, top)
	top = math.max(Style.Edge, top or 0)
	if g == gui then stackTop = top end
	-- the left stack (plan/12): cash, day goal, next goal — measured heights, clean gaps,
	-- the whole column below the Roblox topbar (`top` is the topbar depth)
	do
		local scale = g:FindFirstChild("Fit") and g.Fit.Scale or 1
		local y = top
		local function stack(el, gap)
			if not el then return end
			el.AnchorPoint = Vector2.new(0, 0)
			el.Position = UDim2.fromOffset(Style.Edge, y)
			y += el.AbsoluteSize.Y / (scale ~= 0 and scale or 1) + gap
		end
		stack(g:FindFirstChild("Cash"), 8)
		stack(g:FindFirstChild("DayGoal"), 12)
		stack(g:FindFirstChild("Goal"), 0)
	end
	local job = g:FindFirstChild("JobCard")
	if job then
		job.Position = UDim2.fromOffset(Style.Edge, top + 126)
		job.Size = UDim2.fromOffset(phone and 230 or 250, 0)
		fitHead(job, phone)
		for _, row in job:GetChildren() do shapeFix(row, phone) end
		showFixes(g, phone)
	end
	local menu = g:FindFirstChild("Upgrades")
	if menu then
		-- the menu ball sits on the left edge under the goal tag: the thumbstick has the bottom left on phones,
		-- and on PC the chat window moves there (Hud.start), clear of the cash
		menu.AnchorPoint = Vector2.new(0, 0.5)
		menu.Position = UDim2.new(0, Style.Edge, 0.5, 20)
	end
	local shop = g:FindFirstChild("Shop")
	if shop then
		-- mobile: the shop hangs off the left centre; PC: down at the bottom centre,
		-- clear of the countdown in the bottom-right corner
		shop.Size = UDim2.fromOffset(phone and 560 or 580, phone and 318 or 372)
		if phone then
			shop.AnchorPoint = Vector2.new(0, 0.5)
			shop.Position = UDim2.new(0, Style.Edge, 0.62, 0) -- left, biased low (owner: "move the shop ui down")
		else
			shop.AnchorPoint = Vector2.new(0.5, 1)
			shop.Position = UDim2.new(0.5, 0, 1, -Style.Edge)
		end
	end
	local store = g:FindFirstChild("Store")
	if store then
		store.Size = UDim2.fromOffset(phone and 580 or 600, phone and 330 or 440)
		store.Position = UDim2.fromScale(0.5, phone and 0.56 or 0.55)
	end
	local list = g:FindFirstChild("Customers")
	if list then
		list.Size = UDim2.fromOffset(phone and 184 or 260, 0)
		for _, row in list.Rows:GetChildren() do
			if row:IsA("Frame") then shapeRow(row, phone) end
		end
	end
end

---------------------------------------------------------------- preview gallery (Studio play tests only)
-- PlayerGui.UIPreviews (ShopTicketKit.boards) holds a made-up copy of every screen, PC and phone. In a Studio
-- play test ] and [ flip through them (the real game is board 0); the pay boards replay their stars. Live
-- servers never show them: the folder is deleted at start.
local function gallery()
	local folder = player:WaitForChild("PlayerGui"):FindFirstChild("UIPreviews")
	if not folder then return end
	if not RunService:IsStudio() then
		folder:Destroy()
		return
	end
	local boards = folder:GetChildren()
	table.sort(boards, function(a, b) return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0) end)
	local at = 0
	local function show()
		gui.Enabled = at == 0
		local vp = workspace.CurrentCamera.ViewportSize
		for i, b in boards do
			b.Enabled = i == at
			if i == at then
				b.Fit.Scale = b:GetAttribute("Phone") and vp.X / 993 or Style.fitScale(vp)
				local pay = b:FindFirstChild("PayPanel")
				if pay and pay.Visible and pay:GetAttribute("Stars") then
					for n = 1, 5 do pay.Stars["S" .. n].ImageColor3 = C.StarOff end
					task.spawn(require(script.Parent.PayFX).stars, pay.Stars, pay:GetAttribute("Stars"), pay)
				end
			end
		end
	end
	UIS.InputBegan:Connect(function(input, typing)
		if typing then return end
		if input.KeyCode == Enum.KeyCode.RightBracket then
			at = (at + 1) % (#boards + 1)
			show()
		elseif input.KeyCode == Enum.KeyCode.LeftBracket then
			at = (at - 1) % (#boards + 1)
			show()
		end
	end)
end

function Hud.lobby(on)
	lobby = on
	if gui then
		updateGoal()
		placeCountdown()
	end
end

function Hud.start(e)
	gui, config = e.gui, e.config
	-- panels left showing for the edit-mode preview (ShopTicketKit.preview) start hidden in a real game
	for _, o in gui:GetDescendants() do
		if o:GetAttribute("EditPreviewSample") then
			o:Destroy()
		elseif o:GetAttribute("EditPreview") and o:IsA("GuiObject") then
			o.Visible = false
		elseif o:GetAttribute("EditPreviewLobby") and o:IsA("GuiObject") then
			o.Visible = true -- a lobby piece hidden so the edit preview shows the job state
		end
	end
	Style.fit(gui)
	Style.wireAll(gui)
	task.spawn(gallery)
	lostChip()

	-- plan/12: the star row above the instruction is gone — the timer's par bar carries it.
	-- Shrinking the timer lets the instruction frame move up into the stars' place.
	do
		local timer = gui:FindFirstChild("Timer")
		if timer and timer:FindFirstChild("Stars") then
			local scale = gui:FindFirstChild("Fit") and gui.Fit.Scale or 1
			local h = timer.Stars.AbsoluteSize.Y / (scale ~= 0 and scale or 1)
			timer.Stars.Visible = false
			timer.Size = UDim2.new(timer.Size.X.Scale, timer.Size.X.Offset, timer.Size.Y.Scale, math.max(24, timer.Size.Y.Offset - h))
		end
	end

	---------------------------------------------------------------- day goal (Fever loop, plan/12)
	-- Today's cash target with 1/2/3 stars (CF's TargetLow/Med/High): a small chip under
	-- the cash. The server's GetDay holds the numbers; it polls every few seconds.
	do
		local panel = Instance.new("Frame")
		panel.Name = "DayGoal"
		panel.Size = UDim2.fromOffset(216, 34)
		panel.BackgroundColor3 = C.White or Color3.new(1, 1, 1)
		panel.Visible = false
		Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
		local stroke = Instance.new("UIStroke", panel)
		stroke.Thickness = 2.5
		stroke.Color = C.Ink
		local row = Instance.new("UIListLayout", panel)
		row.FillDirection = Enum.FillDirection.Horizontal
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Padding = UDim.new(0, 6)
		local pad = Instance.new("UIPadding", panel)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		local label = Instance.new("TextLabel")
		label.Name = "Goal"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromOffset(0, 20)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.FontFace = Style.Font.Chunky
		label.TextSize = 15
		label.TextColor3 = C.Ink
		label.Text = ""
		label.Parent = panel
		local stars = {}
		for i = 1, 3 do
			local s = Instance.new("TextLabel")
			s.Name = "S" .. i
			s.BackgroundTransparency = 1
			s.Size = UDim2.fromOffset(18, 20)
			s.FontFace = Style.Font.Chunky
			s.TextSize = 18
			s.Text = "★"
			s.TextColor3 = C.StarOff
			s.Parent = panel
			stars[i] = s
		end
		panel.Parent = gui
		local last
		local function refresh(t)
			local day = workspace:GetAttribute("Phase") == "Day"
			panel.Visible = day and lobby and t ~= nil
			if not t then return end
			last = t
			label.Text = ("$%s / $%s"):format(Style.money(t.Cash), Style.money(t.GoalHigh))
			local n = t.Cash >= t.GoalHigh and 3 or t.Cash >= t.GoalMed and 2 or t.Cash >= t.GoalLow and 1 or 0
			for i = 1, 3 do
				stars[i].TextColor3 = i <= n and C.Gold or C.StarOff
			end
		end
		task.spawn(function()
			local remotes = RS:WaitForChild("ScooterRemotes")
			local getDay = remotes:WaitForChild("GetDay")
			while true do
				local ok, t = pcall(function() return getDay:InvokeServer() end)
				if ok then refresh(t) end
				task.wait(3)
			end
		end)
		workspace:GetAttributeChangedSignal("Phase"):Connect(function() refresh(last) end)
	end

	local function relayout()
		Hud.layout(gui, isPhone(), topbarDepth())
		placeCountdown()
		placeCustomers(false)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(relayout)
	Hud.layout(gui, isPhone(), topbarDepth())
	placeCountdown()
	-- PC: the chat window opens over the top-left corner, where the cash is, so it moves to the bottom left
	-- (the menu ball moved up to the left edge). Phones keep it where it is: chat starts closed there.
	local chat = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if chat and not isPhone() and not UIS.TouchEnabled then
		pcall(function()
			chat.VerticalAlignment = Enum.VerticalAlignment.Bottom
			chat.HorizontalAlignment = Enum.HorizontalAlignment.Left
		end)
	end
	-- each job sets new chip texts: refit the chips row whenever its width or the card's width changes
	local info = gui.JobCard.Head.Info
	local function refit() task.defer(fitChips, info) end
	info.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refit)
	gui.JobCard.Head:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	gui.JobCard.ChildAdded:Connect(function(row)
		shapeFix(row, isPhone())
		task.defer(showFixes, gui, isPhone()) -- once the whole list is in
		-- a fix ticked: it shows its tick for a moment, then the next one takes its place
		row:GetAttributeChangedSignal("Done"):Connect(function()
			task.delay(0.7, function() showFixes(gui, isPhone()) end)
		end)
	end)
	for _, n in { "Shop", "Store", "PayPanel", "Restock", "Instruction", "Timer", "Leave" } do
		if gui:FindFirstChild(n) then gui[n]:GetPropertyChangedSignal("Visible"):Connect(placeCountdown) end
	end
	local list = gui:FindFirstChild("Customers")
	if list then
		list.Rows.ChildAdded:Connect(wireRow)
		list.Toggle.Button.Activated:Connect(function()
			tucked = not tucked
			placeCustomers(true)
		end)
		placeCustomers(false)
	end
	for _, n in { "Phase", "PhaseEndsAt" } do
		workspace:GetAttributeChangedSignal(n):Connect(updateCountdown)
	end
	task.spawn(function()
		while true do
			updateCountdown()
			task.wait(0.25)
		end
	end)

	player.AttributeChanged:Connect(updateGoal)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats")
		ls:WaitForChild("Cash").Changed:Connect(updateGoal)
		updateGoal()
	end)
	task.spawn(function()
		while true do
			task.wait(4)
			local tag = gui:FindFirstChild("Goal")
			if ready and tag and tag.Visible then swing(tag) end
		end
	end)
end

return Hud
