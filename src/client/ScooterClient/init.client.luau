-- Fix My Scooter: broken scooters queue on the conveyor; pick one and the clock
-- starts. Each problem is its own minigame using the tools around the bench.
-- Stars depend on time; then hand it back or test-ride it for a tip.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(RS:WaitForChild("ScooterConfig"))
Config.P = require(script:WaitForChild("Plot")) -- this player's plot (see the Plot module)
Config.Crowd = require(RS:WaitForChild("ScooterCrowd")) -- the customers' walk from the bus stop
Config.Mini = require(script:WaitForChild("Minigames")) -- crane, mud and washing, light wiring, spin guide
Config.Fun = require(script:WaitForChild("Fun")) -- customers' chatter, antics and reactions
local Remotes = RS:WaitForChild("ScooterRemotes")
local Templates = RS:WaitForChild("Scooters")
local StationTemplates = RS:WaitForChild("Stations")
RS:WaitForChild("Tools") -- the tool models are in before any fix starts

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FixUI")
local garage = Config.P.garage -- this player's own garage (built by the server)
local bench = garage:WaitForChild("Bench")
local SPOT = garage:WaitForChild("ScooterSpot").CFrame
local BIN = bench:WaitForChild("Bin").Position + Vector3.new(0, bench.Bin.Size.Y / 2 + 0.7, 0) -- just over the wheelie bin's opening
local road = workspace:WaitForChild("TestRoad")
local FINISH_Z = 500
local START = Vector3.new(1200, 0.1, 42)
local QUEUE_X = { -16.2, -22.6, -29.0, -35.4, -41.8 } -- slots on the belt, nearest the bench first (the 5th holds overflow when two jobs are parked)
local HATCH = garage:WaitForChild("DropOff").CFrame -- outside end of the conveyor
local REPAIR_CAM = CFrame.lookAt(SPOT.Position + Config.P.vec(Vector3.new(1.2, 4.6, 7.4)), SPOT.Position + Config.P.vec(Vector3.new(1.2, 2.5, 0)))

Config.Sound = require(script:WaitForChild("Sounds")) -- every id, button clicks, till, bell, music
local SFX = {
	Tap = Config.Sound.Id.Click,
	Done = Config.Sound.Id.Bright,
	Miss = Config.Sound.Id.Miss,
	Ratchet = Config.Sound.Id.Ratchet,
	Pump = Config.Sound.Id.Pump,
}
local function sfx(id, volume, pitch)
	if id == SFX.Tap and Config.Sound.justClicked() then return end -- the button already clicked
	local s = Instance.new("Sound")
	s.SoundGroup = Config.Sound.Sfx
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.Parent = gui
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
end

-- Feel (plan/12): one impact knob — a short camera shake while the bench owns the camera.
-- Misses, blow-outs, big pays and upgrades call it with a magnitude; it never stacks hard.
local shake
do
	local shakeMag, shakeUntil = 0, 0
	shake = function(mag, time)
		shakeMag = math.max(shakeMag, mag or 0.15)
		shakeUntil = os.clock() + (time or 0.25)
	end
	RunService.RenderStepped:Connect(function()
		local left = shakeUntil - os.clock()
		if left <= 0 or shakeMag <= 0 then return end
		if camera.CameraType ~= Enum.CameraType.Scriptable then return end -- never fights the free camera
		local k = math.min(1, left / 0.25) * shakeMag
		camera.CFrame = camera.CFrame * CFrame.Angles(
			(math.random() - 0.5) * k * 0.05, (math.random() - 0.5) * k * 0.05, (math.random() - 0.5) * k * 0.015)
		if left <= 0.03 then shakeMag = 0 end
	end)
end

local RARITY = {}
for i, r in Config.Rarities do
	RARITY[r.Name] = r
	r.Index = i
end
local RUST = Color3.fromRGB(150, 85, 45)
local TAN = Color3.fromRGB(223, 185, 103)
local DIM = Color3.fromRGB(80, 82, 95)
local GREEN = Color3.fromRGB(88, 190, 96)
local RED = Color3.fromRGB(225, 70, 70)
local BLUE = Color3.fromRGB(70, 150, 240)

local ui = {
	cash = gui.Cash.Amount,
	job = gui.JobCard,
	ins = gui.Instruction,
	bar = gui.Instruction.Bar,
	pop = gui.Pop,
	shopBtn = gui.Upgrades,
	shop = gui.Shop,
	ride = gui.RideStatus,
	pay = gui.PayPanel,
	timer = gui.Timer,
	gauge = gui.Gauge,
	timing = gui.Timing,
	wires = gui.Wires,
	style = require(RS:WaitForChild("UIStyle")), -- Shop Ticket tokens (plan/09-UI-STYLE.md)
	hud = require(script.Hud), -- clock + next-goal tag

	payfx = require(script.PayFX), -- the day card's star moment
	restock = require(script.Restock), -- out of stock: the 10 R$ restock card
	skill = require(script.Skill), -- PERFECT / GOOD / MISS on timing taps, combos
	daycard = require(script.DayCard), -- the day summary once the last customer is served
	guide = require(script.Guide), -- what to do next: a gold glow and a trail on the floor
	store = require(script.Store), -- the Robux store (the menu ball, the + on the cash)
	moments = require(script.Moments), -- Hang on!, cheers while you work
	bubbles = require(script.Bubbles), -- customer bubbles: fix icons, patience bar, faces (no words)
	tycoon = require(script.Tycoon), -- night: price boards over every machine, ghosts of the ones to buy
}
for _, n in { "Action", "Leave" } do
	if gui:FindFirstChild(n) then gui[n].Visible = false end
end

local state = "idle" -- idle | picking | chores | repair | results | ride
local awayFromBench = false -- a flat tyre sends you over to the floor pump mid-repair
local active -- the session being worked: { job, model, started, customer, slotIndex, slotCF, done, painted, wrongPaint, paintQuality, dropped, stopped, result }
-- Fever parallel bench (plan/12): a picked job can be parked back on the belt while another
-- is worked; every session's clock keeps running, so juggling costs stars — choose wisely.
local parked = {} -- [job id] = a parked session
local pendingPickId -- a belt scooter tapped mid-repair: picked at the next fix boundary
local switchTo -- a parked scooter tapped: work on it after the current fix
local startSession -- defined near pickJob below
local function parallelCap()
	local tier = Config.tierOf(player:GetAttribute("Bench") or 1)
	local P = Config.ParallelBench or { Tier2 = 2, Tier4 = 3 }
	return tier >= 4 and (P.Tier4 or 3) or tier >= 2 and (P.Tier2 or 2) or 1
end
local function inFlight()
	local n = active and 1 or 0
	for _ in parked do n += 1 end
	return n
end
-- the bench's pay multiplier, worked out the way the server does (bench level x Caro's upgrade packs)
local function benchPay()
	local pay = Config.stat("Bench", player:GetAttribute("Bench") or 1, "Pay") or 1
	return pay * (1 + Config.Caro.PackPay * ((player:GetAttribute("LookTier") or 1) - 1))
end
local origs = {} -- [scooter model] = { [part] = original look }
local orig = {}

---------------------------------------------------------------- input
local holding = false
local pointer = Vector2.zero
local pendingPress

UIS.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.Space and state == "repair" then
		pendingPress = pointer -- space pumps / hits on PC
		return
	end
	if processed then return end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		holding = true
		pointer = Vector2.new(input.Position.X, input.Position.Y)
		pendingPress = pointer
	end
end)
UIS.InputChanged:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
	end
end)
UIS.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		holding = false
	end
end)
-- A release outside the window never fires InputEnded; trust the real button state.
RunService.Heartbeat:Connect(function()
	if holding and UIS.MouseEnabled and not UIS.TouchEnabled and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		holding = false
	end
end)

-- Which of `parts` is under the screen point? Raycast first, then the nearest
-- one on screen within a finger's width so small parts are easy to hit.
local function pick(pos, parts)
	if not pos then return nil end
	local ray = camera:ScreenPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if hit then return hit.Instance end
	local best, bestD = nil, 70
	for _, p in parts do
		local sp, onScreen = camera:WorldToScreenPoint(p.Position)
		if onScreen then
			local d = (Vector2.new(sp.X, sp.Y) - pos).Magnitude
			if d < bestD then best, bestD = p, d end
		end
	end
	return best
end

local function partsOf(model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then table.insert(list, d) end
	end
	return list
end

---------------------------------------------------------------- effects
-- Parts to work on get a bright outline plus a glossy shine that keeps
-- sweeping over them (a ForceField-material shell), coloured by the job's rarity.
local glow, unglow
do
	local glows = {} -- { highlight, shell, part }
	local glowFolder = Instance.new("Folder")
	glowFolder.Name = "Glints"
	glowFolder.Parent = workspace
	local SHELL = 1.05 -- the shine shell sits just outside the part
	local function glowColor()
		local r = active and RARITY[active.job.Rarity]
		return (r and r.Glow) or Config.Rarities[1].Glow
	end
	-- Roblox only draws ~31 Highlights, so a long list (a rack full of tyres or batteries)
	-- shares one highlight over the parts' own shine shells: only those parts glow, not the
	-- rest of the machine (the charger on the battery station).
	glow = function(parts)
		local col = glowColor()
		local group = #parts > 6 and Instance.new("Model")
		if group then
			group.Name = "GlowGroup"
			local h = Instance.new("Highlight")
			h.Adornee = group
			h.FillColor = col
			h.OutlineTransparency = 1
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = group
			group.Parent = glowFolder
			table.insert(glows, { h = h, group = group })
		end
		for _, p in parts do
			local h = not group and Instance.new("Highlight")
			if h then
				h.Adornee = p
				h.FillColor = col
				h.OutlineTransparency = 1 -- outlines render jaggy; the fill and shine read smoothly
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = p
			end
			local shell = p:Clone()
			shell:ClearAllChildren()
			shell.Name = "Shine"
			shell.Material = Enum.Material.ForceField
			shell.Color = col
			shell.Transparency = 0
			shell.Anchored = true
			shell.CanCollide = false
			shell.CanQuery = false
			shell.CanTouch = false
			shell.CastShadow = false
			shell.Size = p.Size * SHELL
			shell.CFrame = p.CFrame
			shell.Parent = group or glowFolder
			table.insert(glows, { h = h, shell = shell, part = p })
		end
	end
	unglow = function()
		for _, g in glows do
			if g.h then g.h:Destroy() end
			if g.shell then g.shell:Destroy() end
			if g.group then g.group:Destroy() end
		end
		table.clear(glows)
	end
	RunService.RenderStepped:Connect(function()
		local a = 0.35 + math.sin(os.clock() * 6) * 0.22
		for _, g in glows do
			if g.h then g.h.FillTransparency = a end
			-- the shell follows the part (parts move and resize during fixes)
			if not g.part then
				continue
			elseif g.part.Parent then
				g.shell.CFrame = g.part.CFrame
				g.shell.Size = g.part.Size * SHELL
				g.shell.Transparency = g.part.Transparency > 0.9 and 1 or 0
			else
				g.shell.Transparency = 1
			end
		end
	end)
end

-- Cartoon ink outlines on things you use and the people around (not the room
-- shell: an outlined floor puts an ink ring round everything standing on it).
-- Roblox draws at most ~31 Highlights, so all machines share one; each
-- scooter, person and fixed prop gets its own.
-- Highlight outlines aren't anti-aliased: solid black looked jaggy (owner, 22 Oct),
-- so the ink is partly see-through to soften the edges.
local outline
do
	local OUTLINES = true
	local INK = Color3.fromRGB(0, 0, 0)
	local INK_TRANSPARENCY = 0.4
	local outlineFolder = Instance.new("Folder")
	outlineFolder.Name = "CelOutlines"
	outlineFolder.Parent = workspace
	-- keeps Highlights under Roblox's cap: glows always win, these outlines share the rest (plan/11)
	Config.Highlights = require(script:WaitForChild("Highlights"))
	task.spawn(Config.Highlights.init)
	outline = function(target)
		if not (OUTLINES and target) then return end
		local h = Instance.new("Highlight")
		h.Name = target.Name
		h.Adornee = target
		h.FillTransparency = 1
		h.OutlineColor = INK
		h.OutlineTransparency = INK_TRANSPARENCY
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = outlineFolder
		target.Destroying:Connect(function() h:Destroy() end)
		return h
	end
end

local function emit(at, props, count)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	for k, v in props do e[k] = v end
	e.Enabled = false
	e.Parent = a
	e:Emit(count)
	task.delay(1.5, function() a:Destroy() end)
end
local function sparkle(at)
	emit(at, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 150)),
		Size = NumberSequence.new(0.5, 0),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	}, 25)
end
local function puff(at, color, count)
	emit(at, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(color or Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new(0.25, 0.6),
		Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(60, 60),
	}, count or 6)
end

-- Run fn(alpha 0..1) every frame for `duration` seconds.
local function animate(duration, fn, style, dir)
	local t0 = os.clock()
	while true do
		local a = math.min(1, (os.clock() - t0) / duration)
		fn(TweenService:GetValue(a, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out))
		if a >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end

-- Belt slats creep along while anything rides the conveyor.
local beltRunning = 0
do
	local slats, slatMin, slatMax = {}, math.huge, -math.huge
	for _, p in garage:WaitForChild("Conveyor"):GetChildren() do
		if p.Name == "Slat" then
			table.insert(slats, p)
			slatMin = math.min(slatMin, p.Position.Z)
			slatMax = math.max(slatMax, p.Position.Z)
		end
	end
	local slatSpan = slatMax - slatMin + 1.5
	RunService.RenderStepped:Connect(function(dt)
		if beltRunning <= 0 then return end
		for _, p in slats do
			local z = p.Position.Z + dt * 7
			if z > slatMax + 0.75 then z -= slatSpan end
			p.CFrame = CFrame.new(p.Position.X, p.Position.Y, z)
		end
	end)
end

local function slideModel(model, to, time, style, onBelt)
	local from = model:GetPivot()
	if onBelt then beltRunning += 1 end
	animate(time, function(a) model:PivotTo(from:Lerp(to, a)) end, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if onBelt then beltRunning -= 1 end
end

-- Land with a small bounce.
local function settle(model)
	local base = model:GetPivot()
	animate(0.25, function(a) model:PivotTo(base - Vector3.new(0, math.sin(a * math.pi) * 0.12, 0)) end)
	model:PivotTo(base)
end

local function popScale(gui, from, time)
	local sc = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", gui)
	sc.Scale = from or 0.8
	TweenService:Create(sc, TweenInfo.new(time or 0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function popText(text, scale, hold, color)
	local pop = ui.pop
	pop.Text = text
	pop.TextColor3 = color or TAN
	pop.Visible = true
	pop.UIScale.Scale = 0
	TweenService:Create(pop.UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scale or 1 }):Play()
	task.delay(hold or 1, function()
		if pop.Text == text then pop.Visible = false end
	end)
end

local function setInstruction(text, step)
	ui.ins.Visible = true
	if ui.ins.Text.Text ~= text then popScale(ui.ins, 0.88) end
	ui.ins.Text.Text = text
	if step and active then ui.ins.Step.Text = ("FIX %d OF %d"):format(step, #active.job.Problems) end
end
local function setBar(p)
	ui.bar.Visible = p ~= nil
	if p then ui.bar.Fill.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1) end
end
-- upgrade system v5: an old save's Charger and Bin came back as cash, once (the server sets Refunded)
task.delay(4, function()
	local r = player:GetAttribute("Refunded")
	if r then popText(("Refund +$%d"):format(r), 0.55, 1.8, GREEN) end
end)
-- yesterday's day goal (Fever loop, CF's level stars): at dawn the stars you earned, and the chest
-- if there was one. DayResult = "dawn|stars|bonus", set once per dawn by the server.
player:GetAttributeChangedSignal("DayResult"):Connect(function()
	local dawn, stars, bonus = tostring(player:GetAttribute("DayResult") or ""):match("^(%d+)|(%d+)|(%d+)$")
	if not dawn then return end
	stars, bonus = tonumber(stars), tonumber(bonus)
	local row = string.rep("★", stars) .. string.rep("☆", 3 - stars)
	if stars == 0 then
		popText("Goal " .. row .. "  Beat it today!", 0.6, 2.4, TAN)
		return
	end
	local text = "Goal " .. row .. (bonus > 0 and ("  Chest +$" .. ui.style.money(bonus)) or "")
	popText(text, 0.65, 2.6, stars == 3 and ui.style.Color.Gold or GREEN)
	sfx(SFX.Done, 0.8, 1 + stars * 0.15)
	if stars == 3 then shake(0.3, 0.3) end
end)

-- Context offers (plan/12): short need-timed popups — a big customer about to walk, or the
-- exact cash missing for the upgrade on the stand. Never shown mid-minigame; dismisses itself.
do
	local card = Instance.new("Frame")
	card.Name = "Offer"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 76)
	card.Size = UDim2.fromOffset(330, 76)
	card.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
	card.Visible = false
	card.ZIndex = 30
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color, stroke.Thickness = Color3.fromRGB(255, 196, 61), 3
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -56, 0, 24)
	title.FontFace = ui.style.Font.Chunky
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = card
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(14, 36)
	sub.Size = UDim2.new(1, -120, 0, 30)
	sub.FontFace = ui.style.Font.Sans
	sub.TextSize = 15
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.TextWrapped = true
	sub.TextColor3 = Color3.fromRGB(178, 182, 196)
	sub.Parent = card
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Size = UDim2.fromOffset(98, 36)
	buy.Position = UDim2.new(1, -110, 1, -46)
	buy.BackgroundColor3 = ui.style.Color.Gold
	buy.TextColor3 = Color3.fromRGB(18, 19, 25)
	buy.FontFace = ui.style.Font.Chunky
	buy.TextSize = 16
	Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 8)
	buy.Parent = card
	local no = Instance.new("TextButton")
	no.Name = "No"
	no.Size = UDim2.fromOffset(30, 30)
	no.Position = UDim2.new(1, -38, 0, 6)
	no.BackgroundColor3 = Color3.fromRGB(60, 64, 78)
	no.Text = "X"
	no.TextColor3 = Color3.new(1, 1, 1)
	no.FontFace = ui.style.Font.Chunky
	no.TextSize = 14
	Instance.new("UICorner", no).CornerRadius = UDim.new(0, 8)
	no.Parent = card
	card.Parent = gui
	local token = 0
	local function hide()
		token += 1
		card.Visible = false
	end
	no.Activated:Connect(hide)
	buy.Activated:Connect(function()
		local ok, r = pcall(function() return Remotes.OfferBuy:InvokeServer(card:GetAttribute("Kind")) end)
		if ok and r == "prompt" then
			pcall(function()
				game:GetService("MarketplaceService"):PromptProductPurchase(player, card:GetAttribute("ProductId"))
			end)
		end
		hide()
	end)
	Remotes.Offer.OnClientEvent:Connect(function(o)
		if state == "repair" or state == "ride" then return end -- never mid-minigame
		token += 1
		local my = token
		card:SetAttribute("Kind", o.Kind or "")
		card:SetAttribute("ProductId", o.ProductId or 0)
		if o.Kind == "Rescue" then
			title.Text = ((o.Scooter or "A customer") .. " is walking out!")
			sub.Text = (("$%d job — keep them %ds?"):format(o.Pay or 0, o.Seconds or 10))
			buy.Text = (("%d R$"):format(o.Price or 24))
			buy.BackgroundColor3 = ui.style.Color.Gold
		else
			title.Text = "Short on cash?"
			sub.Text = ("Top up and grab %s tonight."):format(o.Item or "that upgrade")
			buy.Text = "TOP UP"
			buy.BackgroundColor3 = ui.style.Color.Cash
		end
		card.Visible = true
		popScale(card, 0.8, 0.25)
		task.delay((o.Seconds or 10) + 0.5, function()
			if token == my then card.Visible = false end
		end)
	end)
end

---------------------------------------------------------------- character
local function getRig()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return char, hum, hrp
end

local function freeze(on)
	local _, hum = getRig()
	if hum then
		hum.WalkSpeed = on and 0 or 16
		hum.UseJumpPower = true
		hum.JumpPower = on and 0 or 50
	end
end

-- Your own avatar gets the ink outline too.
local selfOutline
local function outlineSelf(char)
	if selfOutline then selfOutline:Destroy() end
	selfOutline = outline(char)
end
if player.Character then outlineSelf(player.Character) end
player.CharacterAdded:Connect(outlineSelf)

-- Hide your own avatar while the camera is on the bench so it never blocks the view.
local function hideSelf(on)
	local char = player.Character
	if not char then return end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = on and 1 or 0 end
	end
	if selfOutline then selfOutline.Enabled = not on end
end

-- Ride input: keyboard plus the humanoid's move direction (touch stick, gamepad).
local function getMove(hum)
	local throttle, steer = 0, 0
	if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then throttle += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then throttle -= 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then steer += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then steer -= 1 end
	if throttle == 0 and steer == 0 and hum and hum.MoveDirection.Magnitude > 0.1 then
		local look = camera.CFrame.LookVector
		local flat = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z))
		local m = flat:VectorToObjectSpace(hum.MoveDirection)
		throttle, steer = -m.Z, m.X
	end
	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1)
end

---------------------------------------------------------------- stations
-- Tools you own stand around the bench (only you see your own).
local STATION_FOR = {
	Pump = "Pump", BatteryDock = "BatteryDock", TyreRack = "TyreRack", Wrench = "WrenchRack",
	Bucket = "Bucket", PaintBooth = "PaintBooth", NitroKit = "NitroKit", WireKit = "BulbBox", WashBay = "WashBay",
}
local myStations = Instance.new("Model") -- a Model so one outline covers every machine
myStations.Name = "MyStations"
myStations.Parent = workspace
outline(myStations)
for _, name in { "Bench", "Conveyor", "PartsShop", "Dumpster", "OpenSign" } do
	outline(garage:FindFirstChild(name))
end
local stationLevel = {}

-- Upgrades show as colour and size until real models exist (Look in Config.Shop).
local SHOP = {}
for _, item in Config.Shop do SHOP[item.Id] = item end
local lookOrig = setmetatable({}, { __mode = "k" }) -- [part] = its own colour (level 1)
local function tintLook(root, item, level, time)
	local look = item and item.Look
	if not (look and root) then return end
	local want = look.Colors and look.Colors[level]
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") then
			for _, pattern in look.Parts do
				if p.Name:match("^" .. pattern .. "$") or p.Name:match("^" .. pattern .. "_T%d+$") then
					if not lookOrig[p] then lookOrig[p] = p.Color end
					local color = want or lookOrig[p]
					if time then
						TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Sine), { Color = color }):Play()
					else
						p.Color = color
					end
					break
				end
			end
		end
	end
end
local worldLevel = {} -- [shop id] = level shown on a machine that stands in the garage

-- How many old parts the bin holds before it has to go out (the bench's T4 chute: never). The bin is part
-- of the workbench since upgrade system v5.
local function binCap()
	local item = SHOP.Bench
	return item and item.BinCap and item.BinCap[player:GetAttribute("Bench") or 1] or 4
end

-- The pump hose is a real rope: a chain of points with gravity, pinned at the
-- pump outlet and the nozzle. It hangs, lies on the floor and drapes over the
-- bench edge instead of cutting through anything.
local makeHose
do
	local HOSE = { Points = 28, Length = 9, Thickness = 0.2, Gravity = 70, Color = Color3.fromRGB(32, 33, 38) }
	local hose -- { pump, a, b, pos, prev, parts }
	local benchBox -- solid volume of the bench: hoses can't go inside it
	do
		local top = bench:WaitForChild("Mat")
		local stand = bench:WaitForChild("StandBase")
		local half = stand.Size / 2
		local sp, tp = Config.P.toLocal(stand.Position), Config.P.toLocal(top.Position)
		benchBox = {
			min = Vector3.new(sp.X - half.X, -math.huge, sp.Z - half.Z),
			max = Vector3.new(sp.X + half.X, tp.Y + top.Size.Y / 2, sp.Z + half.Z),
		}
	end

	makeHose = function(pump)
		if hose then
			for _, p in hose.parts do p:Destroy() end
			hose = nil
		end
		local a = pump.BaseCap:FindFirstChild("HoseStart")
		local b = pump.Nozzle:FindFirstChild("HoseEnd")
		if not (a and b) then return end
		local from, to = a.WorldPosition, b.WorldPosition
		local h = { pump = pump, a = a, b = b, pos = {}, prev = {}, parts = {} }
		for i = 1, HOSE.Points do
			local p = from:Lerp(to, (i - 1) / (HOSE.Points - 1))
			h.pos[i], h.prev[i] = p, p
		end
		for i = 1, HOSE.Points - 1 do
			local seg = Instance.new("Part")
			seg.Name = "Hose"
			seg.Shape = Enum.PartType.Cylinder
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.CanTouch = false
			seg.CastShadow = false
			seg.Color = HOSE.Color
			seg.Material = Enum.Material.SmoothPlastic
			seg.Parent = pump
			h.parts[i] = seg
		end
		hose = h
	end

	local function hoseCollide(p, floorY)
		p = Config.P.toLocal(p)
		local r = HOSE.Thickness / 2
		if p.Y < floorY + r then p = Vector3.new(p.X, floorY + r, p.Z) end
		local lo, hi = benchBox.min - Vector3.one * r, benchBox.max + Vector3.one * r
		if p.X > lo.X and p.X < hi.X and p.Z > lo.Z and p.Z < hi.Z and p.Y < hi.Y then
			-- inside the bench: push out the shortest way (over the top or out a side)
			local outs = {
				{ hi.Y - p.Y, Vector3.new(p.X, hi.Y, p.Z) },
				{ p.X - lo.X, Vector3.new(lo.X, p.Y, p.Z) },
				{ hi.X - p.X, Vector3.new(hi.X, p.Y, p.Z) },
				{ p.Z - lo.Z, Vector3.new(p.X, p.Y, lo.Z) },
				{ hi.Z - p.Z, Vector3.new(p.X, p.Y, hi.Z) },
			}
			local best = outs[1]
			for _, o in outs do
				if o[1] < best[1] then best = o end
			end
			p = best[2]
		end
		return Config.P.toWorld(p)
	end

	local function stepHose(h, dt)
		local n = HOSE.Points
		local seg = HOSE.Length / (n - 1)
		local floorY = h.pump:GetPivot().Position.Y
		local g = Vector3.new(0, -HOSE.Gravity * dt * dt, 0)
		local pos, prev = h.pos, h.prev
		for i = 2, n - 1 do
			local p = pos[i]
			local v = (p - prev[i]) * 0.97
			-- rubbing on the floor or the bench top slows it down
			if p.Y <= floorY + HOSE.Thickness * 0.6 or math.abs(p.Y - benchBox.max.Y - HOSE.Thickness / 2) < 0.05 then
				v = Vector3.new(v.X * 0.6, v.Y, v.Z * 0.6)
			end
			prev[i] = p
			pos[i] = p + v + g
		end
		pos[1], pos[n] = h.a.WorldPosition, h.b.WorldPosition
		for _ = 1, 16 do
			for i = 1, n - 1 do
				local p1, p2 = pos[i], pos[i + 1]
				local d = p2 - p1
				local len = d.Magnitude
				if len > 1e-4 then
					local fix = d * ((len - seg) / len)
					if i == 1 then
						pos[i + 1] = p2 - fix
					elseif i + 1 == n then
						pos[i] = p1 + fix
					else
						pos[i] = p1 + fix * 0.5
						pos[i + 1] = p2 - fix * 0.5
					end
				end
			end
			for i = 2, n - 1 do pos[i] = hoseCollide(pos[i], floorY) end
		end
	end

	local function drawHose(h)
		for i, part in h.parts do
			local p1, p2 = h.pos[i], h.pos[i + 1]
			local len = (p2 - p1).Magnitude
			part.Size = Vector3.new(len + HOSE.Thickness * 0.6, HOSE.Thickness, HOSE.Thickness)
			if len > 1e-4 then
				part.CFrame = CFrame.lookAt((p1 + p2) / 2, p2) * CFrame.Angles(0, math.pi / 2, 0)
			end
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		if not (hose and hose.pump.Parent) then return end
		stepHose(hose, math.min(dt, 1 / 30))
		drawHose(hose)
	end)
end

-- Battery stock: a little battery with the count floats over the holder.
local BATTERY_PACK
for _, item in Config.Shop do
	if item.Id == "Batteries" then BATTERY_PACK = item end
end
-- How much a holder (like the battery rack) can take at its current level.
local function holderCap(stockItem)
	for _, item in Config.Shop do
		if item.Id == stockItem.Holder and item.Capacity then
			return item.Capacity[player:GetAttribute(item.Id) or 1] or item.Capacity[1]
		end
	end
	return math.huge
end

-- Battery stock you can see: the owner's rack holds 6 batteries and every rack
-- level stacks another tray on top. One battery shows for every battery you have.
local rackCells = setmetatable({}, { __mode = "k" }) -- [dock] = { {body, cap}, ... }
local function buildRack(dock)
	local trayParts = { dock.RackBase, dock.RackGrid }
	for i = 1, 6 do
		table.insert(trayParts, dock["Battery" .. i])
		table.insert(trayParts, dock["Battery" .. i .. "Cap"])
	end
	local base = dock.RackBase
	local height = 0
	for _, p in trayParts do
		height = math.max(height, p.Position.Y + p.Size.Y / 2 - (base.Position.Y - base.Size.Y / 2))
	end
	local tiers = math.ceil(holderCap(BATTERY_PACK) / 6)
	local cells = {}
	for t = 1, tiers do
		local lift = Vector3.new(0, (t - 1) * (height + 0.02), 0)
		local tray = {}
		for _, p in trayParts do
			local c = p
			if t > 1 then
				c = p:Clone()
				c.Name = p.Name .. "_T" .. t
				c.CFrame = p.CFrame + lift
				c.Parent = dock
			end
			tray[p.Name] = c
		end
		for i = 1, 6 do table.insert(cells, { tray["Battery" .. i], tray["Battery" .. i .. "Cap"] }) end
	end
	if tiers > 1 then
		-- two posts up the back hold the trays
		local h = tiers * (height + 0.02)
		for _, sx in { -1, 1 } do
			local post = Instance.new("Part")
			post.Name = "Upright"
			post.Anchored, post.CanCollide, post.CanTouch = true, false, false
			post.Size = Vector3.new(0.1, h, 0.1)
			post.Color, post.Material = base.Color, Enum.Material.Metal
			post.CFrame = base.CFrame * CFrame.new(sx * (base.Size.X / 2 + 0.05), h / 2 - base.Size.Y / 2, 0)
			post.Parent = dock
		end
	end
	rackCells[dock] = cells
	local function refresh()
		local n = player:GetAttribute("Batteries") or 0
		for i, c in cells do
			local t = i <= n and 0 or 1
			c[1].Transparency, c[2].Transparency = t, t
		end
	end
	refresh()
	local conn = player:GetAttributeChangedSignal("Batteries"):Connect(refresh)
	dock.Destroying:Connect(function() conn:Disconnect() end)
end

-- Where the top battery on the rack is (the next one you take).
local function topCell(dock)
	local cells = rackCells[dock]
	local c = cells and cells[player:GetAttribute("Batteries") or 0]
	return c and c[1].Position
end

-- Tyre stock you can see: the owner's rack holds 4 tyres; every level stacks
-- another tier on top. One tyre shows for every tyre you have.
local RACKS = {} -- tyres(rack), topTyre(rack), bulbs(box), topBulb(box)
do
	local tyreCells = setmetatable({}, { __mode = "k" }) -- [rack] = { {tyre, hub}... }
	local TIER = { "FrameL", "FrameR", "RailBack", "RailFront", "TopBar" }
	function RACKS.tyres(rack)
		local parts = {}
		for _, n in TIER do table.insert(parts, rack[n]) end
		for i = 1, 4 do
			table.insert(parts, rack["Tyre" .. i])
			table.insert(parts, rack["Tyre" .. i .. "Hub"])
		end
		local height = rack.FrameL.Size.Y + 0.02
		local tiers = math.ceil(holderCap(SHOP.Tyres) / 4)
		local cells = {}
		for t = 1, tiers do
			local tier = {}
			for _, p in parts do
				local c = p
				if t > 1 then
					c = p:Clone()
					c.Name = p.Name .. "_T" .. t
					c.CFrame = p.CFrame + Vector3.new(0, (t - 1) * height, 0)
					c.Parent = rack
				end
				tier[p.Name] = c
			end
			for i = 1, 4 do
				table.insert(cells, { tier["Tyre" .. i], tier["Tyre" .. i .. "Hub"] })
			end
		end
		tyreCells[rack] = cells
		local function refresh()
			local n = player:GetAttribute("Tyres") or 0
			for i, c in cells do
				local t = i <= n and 0 or 1
				c[1].Transparency, c[2].Transparency = t, t
			end
		end
		refresh()
		local conn = player:GetAttributeChangedSignal("Tyres"):Connect(refresh)
		rack.Destroying:Connect(function() conn:Disconnect() end)
	end
	-- the tyre you'd take next (the last one put on the rack)
	function RACKS.topTyre(rack)
		local cells = tyreCells[rack]
		return cells and cells[player:GetAttribute("Tyres") or 0]
	end

	-- Bulb stock: the owner's wire kit box has a tray of 4 bulbs; the Pro kit adds a
	-- second tray where the third wire spool sits. One bulb shows per bulb you have.
	local bulbCells = setmetatable({}, { __mode = "k" }) -- [box] = { { bulb, base }... }
	function RACKS.bulbs(box)
		local cells = {}
		for i = 1, 4 do table.insert(cells, { box["Bulb" .. i], box["Bulb" .. i .. "Base"] }) end
		if holderCap(SHOP.Bulbs) > 4 and box:FindFirstChild("Spool3") then
			local shift = Config.P.vec(Vector3.new(Config.P.toLocal(box.Spool3.Position).X - Config.P.toLocal(box.BulbTray.Position).X, 0, 0))
			box.Spool3.Transparency, box.Wire3.Transparency = 1, 1
			local tray = box.BulbTray:Clone()
			tray.Name = "BulbTray2"
			tray.CFrame = tray.CFrame + shift
			tray.Parent = box
			for i = 1, 4 do
				local cell = {}
				for k, n in { "Bulb" .. i, "Bulb" .. i .. "Base" } do
					local c = box[n]:Clone()
					c.Name = n .. "_T2"
					c.CFrame = c.CFrame + shift
					c.Parent = box
					cell[k] = c
				end
				table.insert(cells, cell)
			end
		end
		bulbCells[box] = cells
		local function refresh()
			local n = player:GetAttribute("Bulbs") or 0
			for i, cell in cells do
				cell[1].Transparency = i <= n and 0.15 or 1
				cell[2].Transparency = i <= n and 0 or 1
			end
		end
		refresh()
		local conn = player:GetAttributeChangedSignal("Bulbs"):Connect(refresh)
		box.Destroying:Connect(function() conn:Disconnect() end)
	end
	function RACKS.topBulb(box)
		local cells = bulbCells[box]
		return cells and cells[player:GetAttribute("Bulbs") or 0]
	end
	-- what to tap on a stock holder: its frame plus every part in stock you can see
	-- (so the tyres, bulbs or batteries themselves glow, not just the shelf)
	function RACKS.targets(model, frame, stock)
		local list = {}
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				local isStock = false
				for _, pat in stock do
					if p.Name:match(pat) then isStock = true end
				end
				if isStock then
					if p.Transparency < 1 then table.insert(list, p) end
				else
					for _, pat in frame do
						if p.Name:match(pat) then
							table.insert(list, p)
							break
						end
					end
				end
			end
		end
		return list
	end
end

-- Out of stock (owner, 24 Oct): no cash buying or borrowing in the day; the 10 R$ restock card instead. When
-- it runs out, the customers who needed the part go home (the job on the bench too: its fix throws
-- OUT_OF_STOCK and runRepair sends it back).
local function needStock(stockId, onBench)
	if ui.restock.offer(stockId) then return true end
	ui.restock.giveUp(stockId, onBench)
	return false
end

local function refreshStations()
	for attr, name in STATION_FOR do
		local level = player:GetAttribute(attr) or 0
		local needs = SHOP[attr] and SHOP[attr].Needs
		if needs and (player:GetAttribute(needs) or 0) == 0 then level = 0 end
		local existing = myStations:FindFirstChild(name)
		if level > 0 and (not existing or stationLevel[name] ~= level) and state ~= "repair" then
			local m = StationTemplates:WaitForChild(name):Clone()
			-- each tier's look: anything tagged TierMin / TierMax (a Tier2 folder, a rim that a
			-- glowing one replaces at tier 3) only stays if this tier (1-4, from the level) is in its range
			local tier = Config.tierOf(level)
			for _, d in m:GetDescendants() do
				local lo, hi = d:GetAttribute("TierMin"), d:GetAttribute("TierMax")
				if (lo and tier < lo) or (hi and tier > hi) then d:Destroy() end
			end
			m:PivotTo(Config.P.PF * m:GetPivot()) -- the templates are in plot 0; move to this plot
			local item = SHOP[attr]
			local grow = item and item.Look and item.Look.Grow or 0
			m:ScaleTo(m:GetScale() * (1 + grow * (tier - 1)))
			tintLook(m, item, level)
			local fromScale = existing and existing:GetScale()
			if existing then existing:Destroy() end
			m.Parent = myStations
			stationLevel[name] = level
			if name == "Pump" then makeHose(m) end
			if name == "BatteryDock" then
				buildRack(m)
				tintLook(m, item, level)
			end
			if name == "TyreRack" then
				RACKS.tyres(m)
				tintLook(m, item, level) -- the shelves it just grew
			elseif name == "BulbBox" then
				RACKS.bulbs(m)
				tintLook(m, item, level)
			end
			if fromScale then
				-- installed: it pops up from its old size to the new one
				local toScale = m:GetScale()
				m:ScaleTo(fromScale)
				sparkle(m:GetPivot().Position + Vector3.new(0, 1.5, 0))
				sfx(SFX.Done, 0.7, 0.8)
				task.spawn(animate, 0.6, function(a)
					if m.Parent then m:ScaleTo(fromScale + (toScale - fromScale) * a) end
				end, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		elseif level == 0 and existing then
			existing:Destroy()
		end
	end
	-- machines that stand in the garage (belt, bench, bin) only change colour
	for _, item in Config.Shop do
		local look = item.Look
		if look and look.Model then
			local level = player:GetAttribute(item.Id) or 1
			if worldLevel[item.Id] ~= level then
				local root = garage:FindFirstChild(look.Model)
				local upgraded = worldLevel[item.Id] ~= nil
				tintLook(root, item, level, upgraded and 0.6 or nil)
				if upgraded and root then
					sparkle(root:GetPivot().Position + Vector3.new(0, 2, 0))
					sfx(SFX.Done, 0.7, 0.8)
				end
				worldLevel[item.Id] = level
			end
		end
	end
end

---------------------------------------------------------------- breaking
local function remember(p)
	if orig[p] then return end -- keep the very first (unbroken) look
	orig[p] = { CFrame = p.CFrame, Size = p.Size, Color = p.Color, Material = p.Material }
end

-- Small blinking warning light stuck on a part (dead / low battery).
local blinkers = {}
local function warnLight(m, onPart, color)
	local led = Instance.new("Part")
	led.Name = "WarnLight"
	led.Shape = Enum.PartType.Ball
	led.Size = Vector3.new(0.22, 0.22, 0.22)
	led.Anchored = true
	led.CanCollide = false
	led.Material = Enum.Material.Neon
	led.Color = color
	led.CFrame = onPart.CFrame + Vector3.new(0, onPart.Size.Y / 2 + 0.06, 0)
	led.Parent = m
	blinkers[led] = true
	return led
end
RunService.RenderStepped:Connect(function()
	local on = math.floor(os.clock() * 3) % 2 == 0
	for led in blinkers do
		if led.Parent then led.Transparency = on and 0 or 0.85 else blinkers[led] = nil end
	end
end)

-- Rotate parts around a hinge point (used for the wonky handlebar and dangling light).
local function hinge(parts, at, angles)
	local h = CFrame.new(at)
	for _, p in parts do p.CFrame = h * angles * h:Inverse() * p.CFrame end
end

-- The owner's broken-tyre meshes (ReplicatedStorage.TyreVariants.<scooter>), made
-- in the same Blender scene as the scooter, so they sit exactly where the tyre is.
-- The real tyre hides behind it until it's fixed.
local function tyreVariant(m, tyre, meshName, newName)
	local set = RS:FindFirstChild("TyreVariants") and RS.TyreVariants:FindFirstChild(m.Name)
	local mesh = set and set:FindFirstChild(meshName)
	if not mesh then return nil end
	local v = mesh:Clone()
	v.Name = newName
	v.CFrame = tyre.CFrame
	v.Parent = m
	tyre.Transparency = 1
	return v
end

local BREAK = {
	Mud = function(m) Config.Mini.dirty(m, remember) end, -- caked in mud where you can see it (Minigames)
	Tyre = function(m)
		remember(m.TyreFront)
		remember(m.TyreFrontHub)
		local v = tyreVariant(m, m.TyreFront, "TyreFront_Flat", "TyreFlat")
		if v then
			v.Color = Color3.fromRGB(60, 60, 64)
			return
		end
		-- no mesh for this scooter: squash the tyre, flat at the bottom and bulging out
		local t = m.TyreFront
		local d = t.Size.Y
		for _, n in { "TyreFront", "TyreFrontHub" } do
			local p = m[n]
			remember(p)
			p.CFrame = p.CFrame - Vector3.new(0, d * 0.19, 0)
		end
		if t:IsA("MeshPart") then
			-- a mesh tyre squashes by size: shorter, and wider along the ground
			local s = t.Size
			local wide = s.X >= s.Z and Vector3.new(1.16, 0.62, 1) or Vector3.new(1, 0.62, 1.16)
			t.Size = s * wide
		else
			local mesh = Instance.new("SpecialMesh")
			mesh.Name = "Flat"
			mesh.MeshType = Enum.MeshType.Cylinder
			mesh.Scale = Vector3.new(1, 0.62, 1.16)
			mesh.Parent = t
		end
		t.Color = Color3.fromRGB(60, 60, 64)
	end,
	Battery = function(m)
		local b, cap = m.Battery, m.BatteryCap
		remember(b)
		remember(cap)
		b.Color = Color3.fromRGB(58, 48, 44)
		b.Material = Enum.Material.Slate
		cap.Color = Color3.fromRGB(70, 72, 70)
		cap.Material = Enum.Material.CorrodedMetal
		-- swollen: the case bulges out the sides
		local bulge = Instance.new("Part")
		bulge.Name = "BatteryJunk"
		bulge.Size = Vector3.new(1, 1, 1)
		bulge.Color = b.Color
		bulge.Material = Enum.Material.Slate
		bulge.Anchored, bulge.CanCollide, bulge.CanQuery = true, false, false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(b.Size.X * 1.18, b.Size.Y * 0.8, b.Size.Z * 1.18)
		mesh.Parent = bulge
		bulge.CFrame = b.CFrame
		bulge.Parent = m
		-- cracks down the case, scorch marks
		for i = 1, 3 do
			local crack = Instance.new("Part")
			crack.Name = "BatteryJunk"
			crack.Anchored, crack.CanCollide, crack.CanQuery = true, false, false
			crack.Color = Color3.fromRGB(15, 14, 14)
			crack.Size = Vector3.new(0.025, b.Size.Y * (0.35 + math.random() * 0.3), 0.025)
			local side = (i % 2 == 0) and 1 or -1
			crack.CFrame = b.CFrame * CFrame.new((i - 2) * b.Size.X * 0.28, (math.random() - 0.5) * 0.12, side * (b.Size.Z / 2 + 0.06)) * CFrame.Angles(0, 0, (math.random() - 0.5) * 0.9)
			crack.Parent = m
		end
		-- green-white crust round the terminals
		for _, sx in { -1, 1 } do
			for k = 1, 3 do
				local crust = Instance.new("Part")
				crust.Name = "BatteryJunk"
				crust.Shape = Enum.PartType.Ball
				local d = 0.07 + math.random() * 0.06
				crust.Size = Vector3.new(d, d, d)
				crust.Anchored, crust.CanCollide, crust.CanQuery = true, false, false
				crust.Color = Color3.fromRGB(170, 215, 180):Lerp(Color3.fromRGB(240, 245, 235), math.random())
				crust.Material = Enum.Material.Sand
				crust.CFrame = cap.CFrame * CFrame.new(sx * cap.Size.X * 0.28 + (math.random() - 0.5) * 0.1, cap.Size.Y / 2 + 0.02, (math.random() - 0.5) * cap.Size.Z * 0.6)
				crust.Parent = m
			end
		end
		-- a thin wisp of smoke
		local smoker = Instance.new("Part")
		smoker.Name = "BatteryJunk"
		smoker.Size = Vector3.new(0.1, 0.1, 0.1)
		smoker.Transparency = 1
		smoker.Anchored, smoker.CanCollide, smoker.CanQuery = true, false, false
		smoker.CFrame = cap.CFrame + Vector3.new(0, cap.Size.Y / 2, 0)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 75), Color3.fromRGB(150, 150, 155))
		smoke.Size = NumberSequence.new(0.15, 0.6)
		smoke.Transparency = NumberSequence.new(0.4, 1)
		smoke.Lifetime = NumberRange.new(0.8, 1.4)
		smoke.Speed = NumberRange.new(0.6, 1.2)
		smoke.SpreadAngle = Vector2.new(12, 12)
		smoke.Rate = 5
		smoke.Parent = smoker
		smoker.Parent = m
		warnLight(m, cap, Color3.fromRGB(255, 50, 40))
	end,
	Worn = function(m)
		-- bald and cracked (the rim stays as it is: a new tyre doesn't clean rims)
		for _, n in { "TyreRear", "TyreRearHub" } do remember(m[n]) end
		local v = tyreVariant(m, m.TyreRear, "TyreRear_Worn", "TyreWorn")
		if v then
			v.Color = Color3.fromRGB(110, 98, 90)
			return
		end
		m.TyreRear.Color = Color3.fromRGB(110, 98, 90)
		m.TyreRear.Material = Enum.Material.Slate
		local t = m.TyreRear
		local r = t.Size.Y / 2
		local width = math.min(t.Size.X, t.Size.Y, t.Size.Z) -- works for block and mesh tyres
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2 + 0.4
			local c = Instance.new("Part")
			c.Name = "WornCrack"
			c.Anchored = true
			c.CanCollide = false
			c.Color = Color3.fromRGB(35, 30, 28)
			c.Size = Vector3.new(0.05, r * 0.5, 0.06)
			c.CFrame = CFrame.new(t.Position) * (m:GetPivot() - m:GetPivot().Position) * CFrame.new(math.cos(a) * r * 0.72, math.sin(a) * r * 0.72, width / 2 + 0.01) * CFrame.Angles(0, 0, a + 0.5)
			c.Parent = m
		end
	end,
	Light = function(m)
		-- smashed and hanging off the stem
		remember(m.Light)
		remember(m.LightRim)
		m.Light.Material = Enum.Material.SmoothPlastic
		m.Light.Color = Color3.fromRGB(60, 60, 66)
		local twins = {}
		for _, n in { "Light2", "LightRim2", "LightBar" } do
			local p = m:FindFirstChild(n)
			if p then
				remember(p)
				table.insert(twins, p)
			end
		end
		if m:FindFirstChild("Light2") then
			m.Light2.Material = Enum.Material.SmoothPlastic
			m.Light2.Color = Color3.fromRGB(60, 60, 66)
		end
		-- a dead, smoky bulb pokes out of the smashed lens
		local front = (m.Light.Position - m.LightRim.Position).Unit
		local bulb = Instance.new("Part")
		bulb.Name = "DeadBulb"
		bulb.Shape = Enum.PartType.Ball
		bulb.Size = Vector3.new(0.2, 0.2, 0.2)
		bulb.Anchored, bulb.CanCollide = true, false
		bulb.Material = Enum.Material.Glass
		bulb.Color = Color3.fromRGB(70, 66, 62)
		bulb.Transparency = 0.1
		bulb.CFrame = CFrame.new(m.Light.Position + front * 0.1)
		bulb.Parent = m
		local hanging = { m.Light, m.LightRim, bulb }
		for _, p in twins do table.insert(hanging, p) end
		hinge(hanging, m.LightRim.Position + Config.P.vec(Vector3.new(-0.1, 0.25, 0)), Config.P.rot(CFrame.Angles(0, 0, math.rad(-40))))
	end,
	Bolts = function(m)
		for i = 1, 3 do
			local b = m["Bolt" .. i]
			remember(b)
			b.CFrame = b.CFrame + m:GetPivot():VectorToWorldSpace(Vector3.new(0, 0, 0.35)) -- loose, sticking out (not rusty: tightening doesn't clean them)
		end
		-- loose clamp: the handlebar sits wonky
		local bar = { m.Handlebar, m.Screen }
		for _, p in m:GetChildren() do
			if p.Name == "Grip" or p.Name:match("^Phone") then table.insert(bar, p) end
		end
		for _, p in bar do remember(p) end
		hinge(bar, m.Handlebar.Position, Config.P.rot(CFrame.Angles(math.rad(14), 0, 0)))
	end,
	Charge = function(m)
		remember(m.Battery)
		m.Battery.Color = Color3.fromRGB(225, 95, 50)
		warnLight(m, m.BatteryCap, Color3.fromRGB(255, 160, 40))
	end,
	Paint = function(m)
		-- faded, dusty paint
		for _, p in m:GetChildren() do
			if p.Name == "Deck" or p.Name == "DeckNose" or p.Name == "DeckTail" or p.Name == "Stem" or p.Name == "RearFender" or p.Name == "FrontFender" then
				if not orig[p] then
					remember(p)
					p.Color = p.Color:Lerp(Color3.fromRGB(150, 145, 140), 0.6)
				end
			end
		end
	end,
	Nitro = function() end, -- an upgrade, nothing to break
	Rust = function(m)
		-- corrosion all over the metal bits, patchy shades so it reads as rust
		local RUSTY = { Handlebar = true, Stem = true, Grip = true, StemClamp = true, RearFender = true, Screen = true }
		for _, p in m:GetChildren() do
			if RUSTY[p.Name] then
				remember(p)
				p.Color = RUST:Lerp(Color3.fromRGB(110, 60, 30), math.random() * 0.6)
				p.Material = Enum.Material.CorrodedMetal
			end
		end
	end,
}

-- Saved looks are relative to the scooter, so they still apply after it moves.
-- (Uses its own table so a scooter arriving mid-repair can't touch the one on the bench.)
local function breakScooter(model, problems)
	local pivot = model:GetPivot()
	local onBench = orig
	orig = {}
	for _, name in problems do BREAK[name](model) end
	local rel = {}
	for p, o in orig do
		rel[p] = { CFrame = pivot:ToObjectSpace(o.CFrame), Size = o.Size, Color = o.Color, Material = o.Material }
	end
	origs[model] = rel
	orig = onBench
end

-- Turn the saved relative looks into world space for the scooter's current spot.
local function loadOrig(model)
	local pivot = model:GetPivot()
	orig = {}
	for p, o in origs[model] or {} do
		orig[p] = { CFrame = pivot * o.CFrame, Size = o.Size, Color = o.Color, Material = o.Material }
	end
end

---------------------------------------------------------------- minigame helpers
-- Wait for a tap on one of `parts` while repairing.
local function tapOn(parts)
	pendingPress = nil
	glow(parts)
	while true do
		local press = pendingPress
		pendingPress = nil
		if press and state == "repair" then
			local hit = pick(press, parts)
			if hit then
				unglow()
				sfx(SFX.Tap, 0.7)
				return hit
			end
		end
		task.wait()
	end
end

-- Old parts pile up in the parts bin on the bench until you take the trash out
-- at closing time.
local binCount = 0
local binJunk = Instance.new("Folder")
binJunk.Name = "BinJunk"
binJunk.Parent = workspace
local JUNK = { Color3.fromRGB(60, 62, 70), Color3.fromRGB(95, 80, 70), Color3.fromRGB(40, 42, 48), Color3.fromRGB(120, 45, 45) }
local function addToBin()
	if binCap() == math.huge then return end -- the trash chute takes it away
	binCount += 1
	-- a bin with its own scrap pieces shows how full it is with those
	local scraps = {}
	for _, p in bench:GetChildren() do
		if p.Name:match("^Scrap%d") then table.insert(scraps, p) end
	end
	if #scraps > 0 then
		table.sort(scraps, function(a, b) return a.Name < b.Name end)
		local full = binCount / binCap()
		for i, s in scraps do
			if full > (i - 1) / #scraps then s.Transparency = 0 end
		end
		return
	end
	if binCount > 14 then return end -- the pile tops out
	local bin = bench.Bin
	local top = bin.Position.Y + bin.Size.Y / 2
	-- the pile rises inside the rim as it fills and pokes out over it when full
	local fullness = math.min(1, binCount / binCap())
	local j = Instance.new("Part")
	j.Name = "Junk"
	j.Anchored = true
	j.CanCollide = false
	j.CanQuery = false
	j.CastShadow = false
	j.Size = Vector3.new(0.4 + math.random() * 0.3, 0.3 + math.random() * 0.2, 0.4 + math.random() * 0.3)
	j.Color = JUNK[math.random(#JUNK)]
	j.CFrame = CFrame.new(
		bin.Position.X + (math.random() - 0.5) * (bin.Size.X - 0.7),
		top + 0.1 + fullness * 0.45 + math.random() * 0.08,
		bin.Position.Z + (math.random() - 0.5) * (bin.Size.Z - 0.7)
	) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	j.Parent = binJunk
end

-- Something lands in the bin: clunk, dust, and the open lid rattles.
local function binLand()
	sfx(SFX.Tap, 0.8, 0.5)
	puff(BIN, Color3.fromRGB(200, 200, 200), 6)
	local lid = bench:FindFirstChild("BinLid")
	local hinge = lid and lid:GetAttribute("Hinge")
	if hinge then
		local home = lid.CFrame
		task.spawn(animate, 0.35, function(a)
			local wob = math.sin(a * math.pi * 3) * (1 - a) * math.rad(14)
			lid.CFrame = CFrame.new(hinge) * CFrame.Angles(wob, 0, 0) * CFrame.new(-hinge) * home
		end)
	end
end
local function clearBin()
	binCount = 0
	binJunk:ClearAllChildren()
	for _, p in bench:GetChildren() do
		if p.Name:match("^Scrap%d") then p.Transparency = 1 end
	end
end
clearBin() -- the bin starts the day empty

---------------------------------------------------------------- minigames
local FIX = {}
local onBackgroundFix -- set by the sessions section: a fix left running in the background (charging) is done

-- Flat tyre: walk over to the floor pump by the bench. The hose clips onto the
-- valve and your character pumps it up: hold = push the handle down (air goes in
-- on the way down), let go = it springs back up. A full press is a full stroke,
-- a quick tap a small top-up.
local PUMP_STAND = 1.25 -- how far from the pump you stand (hands reach the handle all the way down)
local PUMP_CAM_SIDE, PUMP_CAM_AHEAD, PUMP_CAM_UP = 7, 6.5, 3 -- camera: to your left, out in front, above
FIX.Tyre = function(m, step)
	local pump = myStations:WaitForChild("Pump")
	local level = player:GetAttribute("Pump") or 1
	local tyre, hub = m.TyreFront, m.TyreFrontHub
	local nozzle, tip = pump.Nozzle, pump.NozzleTip
	local nozzleHome = nozzle.CFrame
	local tipOff = nozzle.CFrame:ToObjectSpace(tip.CFrame)
	local function setNozzle(cf)
		nozzle.CFrame = cf
		tip.CFrame = cf * tipOff
	end
	local valve = orig[hub].CFrame.Position + Config.P.vec(Vector3.new(0, orig[tyre].Size.Y * 0.3, 0.3))

	-- off the bench: your own view, walk over to the pump
	local char, hum, hrp = getRig()
	awayFromBench = true
	hideSelf(false)
	if hrp then
		-- glide back behind your character instead of snapping
		local behind = hrp.CFrame * CFrame.new(0, 4, 11)
		local camStart = camera.CFrame
		local want = CFrame.lookAt(behind.Position, hrp.Position + Vector3.new(0, 1.5, 0))
		animate(0.4, function(a)
			camera.CFrame = camStart:Lerp(want, a)
			camera.FieldOfView = 60 + 10 * a
		end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	freeze(false)
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	setInstruction("Walk to the pump", step)
	glow({ pump.Barrel, pump.Handle, pump.BaseCap })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pump tyre"
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = pump.Barrel
	local go = false
	prompt.Triggered:Connect(function() go = true end)
	while not go do task.wait() end
	prompt:Destroy()
	unglow()
	char, hum, hrp = getRig()

	-- step up to the pump, facing it
	freeze(true)
	local cf0, size0 = pump:GetBoundingBox()
	local floorY = cf0.Position.Y - size0.Y / 2
	local base = pump:GetPivot().Position
	local standY = floorY + hum.HipHeight + hrp.Size.Y / 2
	-- you stand on the side the gauge faces, looking at the pump
	local front = pump.Gauge.Position - pump.Barrel.Position
	front = Vector3.new(front.X, 0, front.Z).Unit
	local standPos = Vector3.new(base.X, standY, base.Z) + front * PUMP_STAND
	local standCF = CFrame.lookAt(standPos, Vector3.new(base.X, standY, base.Z))
	hrp.Anchored = true
	local walkFrom = hrp.CFrame
	animate(0.25, function(a) hrp.CFrame = walkFrom:Lerp(standCF, a) end)

	-- your idle animation keeps playing (head, breathing); IK only takes over the
	-- hands (on the handle) and the feet (planted while the knees bend)
	local animator = hum:FindFirstChildOfClass("Animator")
	local rig = {} -- everything to clean up afterwards
	local function point(name, pos)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = workspace.Terrain
		a.WorldPosition = pos
		table.insert(rig, a)
		return a
	end
	local function ik(rootName, endName, target, pole)
		local root, effector = char:FindFirstChild(rootName), char:FindFirstChild(endName)
		if not (root and effector and animator) then return end
		local c = Instance.new("IKControl")
		c.Type = Enum.IKControlType.Position
		c.ChainRoot = root
		c.EndEffector = effector
		c.Target = target
		c.Pole = pole
		c.Parent = hum
		table.insert(rig, c)
	end
	local legDrop = hum.HipHeight + hrp.Size.Y / 2
	for _, g in pump:GetChildren() do
		if g.Name == "HandleGrip" then
			local s = standCF:PointToObjectSpace(g.Position).X < 0 and -1 or 1
			local side = s < 0 and "Left" or "Right"
			local grab = Instance.new("Attachment")
			grab.Name = "Grab"
			grab.Parent = g
			grab.WorldPosition = g.Position + Vector3.new(0, 0.12, 0)
			table.insert(rig, grab)
			-- elbows out to the side and back
			ik(side .. "UpperArm", side .. "Hand", grab, point("ElbowPole", (standCF * CFrame.new(s * 3, 0, 2)).Position))
			local foot = char:FindFirstChild(side .. "Foot")
			if foot then
				local footAt = (standCF * CFrame.new(s * 0.5, -legDrop + foot.Size.Y / 2, 0)).Position
				ik(side .. "UpperLeg", side .. "Foot", point("FootAt", footAt), point("KneePole", (standCF * CFrame.new(s * 0.6, -1, -4)).Position))
			end
		end
	end

	-- three-quarter front view from the open room: you, the pump in front of you,
	-- the hose going up to the tyre on the bench
	local focus = (base + valve) / 2 + Vector3.new(0, 0.2, 0)
	local view = CFrame.lookAt((standCF * CFrame.new(-PUMP_CAM_SIDE, 0, -PUMP_CAM_AHEAD)).Position + Vector3.new(0, PUMP_CAM_UP, 0), focus)
	camera.CameraType = Enum.CameraType.Scriptable
	local camFrom = camera.CFrame
	animate(0.45, function(a) camera.CFrame = camFrom:Lerp(view, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- the hose goes onto the valve: the tip end of the nozzle points into it,
	-- whichever way the nozzle is built in the model
	local tipDir = nozzleHome:VectorToObjectSpace(tip.Position - nozzle.Position)
	local clipped = CFrame.lookAt(valve + Vector3.new(0.35, 0.7, 1).Unit * (tipDir.Magnitude + 0.06), valve)
		* CFrame.fromRotationBetweenVectors(tipDir.Unit, Vector3.new(0, 0, -1))
	animate(0.5, function(a)
		setNozzle(nozzleHome:Lerp(clipped, a) + Vector3.new(0, math.sin(a * math.pi) * 2, 0))
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	setNozzle(clipped)
	sfx(SFX.Tap, 0.9, 0.8)
	puff(valve, nil, 4)

	setInstruction("Hold to pump, let go, repeat", step)
	local moving = { pump.Rod, pump.Handle }
	local grips = {}
	for _, p in pump:GetChildren() do
		if p.Name == "HandleGrip" then table.insert(moving, p) table.insert(grips, p) end
	end
	local top = {}
	for _, p in moving do top[p] = p.CFrame end
	local needle, needleTop = pump.Needle, pump.Needle.CFrame
	-- how far the handle can go down before it hits the barrel
	local barrelTop = -math.huge
	do
		local cf, half = pump.Barrel.CFrame, pump.Barrel.Size / 2
		for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
			barrelTop = math.max(barrelTop, cf:PointToWorldSpace(half * Vector3.new(x, y, z)).Y)
		end end end
	end
	local travel = math.max(0.2, pump.Handle.Position.Y - pump.Handle.Size.Y / 2 - barrelTop - 0.05)
	-- each push: the handle goes down, you tip forward over it and dip at the
	-- knees (the whole body tilts at the hips; leg IK keeps the feet down)
	local function setDepth(d)
		for _, p in moving do p.CFrame = top[p] - Vector3.new(0, d * travel, 0) end
		hrp.CFrame = standCF * CFrame.new(0, -0.4 * d, 0) * CFrame.Angles(-(0.12 + 0.2 * d), 0, 0)
	end
	setDepth(0)
	local flat = { [tyre] = { tyre.Size, tyre.CFrame }, [hub] = { hub.Size, hub.CFrame } }
	local squash = tyre:FindFirstChild("Flat")
	local squashFrom = squash and squash.Scale
	local flatMesh = m:FindFirstChild("TyreFlat") -- the owner's flat-tyre mesh, if this scooter has one
	-- every tyre wants a different pressure: pump into the green band and keep it there
	local gauge = ui.gauge
	local track = gauge.Track
	local zoneLo = math.random(52, 74)
	local zoneHi = zoneLo + 18
	track.Zone.Position = UDim2.fromScale(zoneLo / 100, 0)
	track.Zone.Size = UDim2.fromScale((zoneHi - zoneLo) / 100, 1)
	track.Fill.Size = UDim2.fromScale(0, 1)
	gauge.Visible = true
	popScale(gauge, 0.7)
	-- Hold = push the handle down (air goes in on the way down), let go = it
	-- springs back up. A full press is a full stroke, a quick tap a small top-up.
	local air = (Config.PumpAir[level] or Config.PumpAir[1]) * (player:GetAttribute("ChromePump") == 1 and Config.Caro.Boost.ChromePump or 1)
	local strokeTime = Config.PumpStroke[level] or Config.PumpStroke[1]
	local HOLD = Config.PumpHold
	local pressure, shown, kick, held, depth = 0, 0, 0, 0, 0
	local pushing = false
	local ready = not holding -- the press that clipped the hose on doesn't count
	local told = false
	local blew = 0 -- overfills: a clean fill is PERFECT, each blow-out a MISS (ScooterClient.Skill)
	pendingPress = nil
	while held < HOLD do
		local dt = task.wait()
		local push = state == "repair" and (holding or UIS:IsKeyDown(Enum.KeyCode.Space))
		if not push then ready = true end
		if push and ready then
			if not pushing and depth < 0.9 then
				sfx(SFX.Tap, 0.4, 0.5 + math.min(pressure, 100) / 100 * 0.4)
			end
			pushing = true
			local before = depth
			depth = math.min(1, depth + dt / strokeTime)
			pressure += air * (depth - before)
			if before < 1 and depth >= 1 then
				-- bottom of the stroke: the air rushes in
				kick = 1
				puff(valve, nil, 4)
				sfx(SFX.Pump, 0.6, 0.85 + math.min(pressure, 100) / 100 * 0.4)
			end
		else
			if pushing and depth < 1 then
				-- let go early: a little top-up
				kick = math.max(kick, depth * 0.6)
				puff(valve, nil, 2)
			end
			pushing = false
			depth = math.max(0, depth - dt / Config.PumpReturn)
		end
		if pressure > zoneHi + 4 then
			-- too much: the safety valve blows and you lose air
			pressure = math.max(0, zoneLo - 14)
			held = 0
			blew += 1
			shake(0.5, 0.3)
			ui.skill.hit("miss", tyre.Position, "TOO MUCH!")
			puff(valve, nil, 16)
			sfx(SFX.Tap, 0.9, 0.4)
		end
		pressure = math.clamp(pressure - Config.PumpLeak * dt, 0, 100)
		local inZone = pressure >= zoneLo and pressure <= zoneHi + 4
		if inZone then
			held += dt
			if not told then
				told = true
				setInstruction("Keep it in the green!", step)
			end
		else
			held = math.max(0, held - dt * 2)
		end
		setBar(held / HOLD)
		shown += (pressure - shown) * math.min(1, dt * 14)
		kick = math.max(0, kick - dt * 6)
		setDepth(TweenService:GetValue(depth, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
		local p = math.clamp(shown / zoneLo, 0, 1)
		for part, f in flat do
			part.Size = f[1]:Lerp(orig[part].Size, p)
			part.CFrame = f[2]:Lerp(orig[part].CFrame, p)
		end
		-- the tyre rounds out as it fills, with a little wobble on each pump
		if squash then squash.Scale = squashFrom:Lerp(Vector3.one, p) * (1 + kick * 0.04) end
		-- the flat mesh pops round once it's half full
		if flatMesh then
			local round = p >= 0.5
			if round ~= (flatMesh.Transparency == 1) then
				flatMesh.Transparency = round and 1 or 0
				tyre.Transparency = round and 0 or 1
				if round then puff(tyre.Position, nil, 6) end
			end
		end
		track.Fill.Size = UDim2.fromScale(math.clamp(shown / 100, 0, 1), 1)
		track.Fill.BackgroundColor3 = inZone and GREEN or (pressure > zoneHi and RED or BLUE)
		needle.CFrame = needleTop * CFrame.Angles(0, 0, -math.clamp(shown / 100, 0, 1) * math.rad(150))
	end
	setBar(nil)
	for part in flat do
		part.Size = orig[part].Size
		part.CFrame = orig[part].CFrame
	end
	if squash then squash:Destroy() end
	if flatMesh then
		flatMesh:Destroy()
		tyre.Transparency = 0
	end
	gauge.Visible = false
	tyre.Color = orig[tyre].Color
	ui.skill.hit(blew == 0 and "perfect" or "good", tyre.Position)
	sparkle(tyre.Position)
	setDepth(0)
	-- hose goes back on its clip
	local from = nozzle.CFrame
	animate(0.45, function(a)
		setNozzle(from:Lerp(nozzleHome, a) + Vector3.new(0, math.sin(a * math.pi) * 2, 0))
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	setNozzle(nozzleHome)
	needle.CFrame = needleTop

	-- step off the pump and back to the bench for the next fix
	for _, x in rig do x:Destroy() end
	local spot = bench.WorkSpot.Position
	local at = Vector3.new(spot.X, standY + 0.2, spot.Z)
	hrp.CFrame = CFrame.lookAt(at, at - Config.P.vec(Vector3.zAxis))
	hrp.Anchored = false
	hideSelf(true)
	local camBack = camera.CFrame
	animate(0.45, function(a) camera.CFrame = camBack:Lerp(REPAIR_CAM, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	camera.FieldOfView = 60
	awayFromBench = false
end

-- Dead battery, a quick swap at the bench: tap it and it pops out into the parts
-- bin, tap the battery holder and a fresh one jumps into place. Each swap uses a
-- battery from your stock; run out and the holder offers a pack right there.
FIX.Battery = function(m, step)
	local dock = myStations:WaitForChild("BatteryDock")
	local battery = m.Battery
	local center = battery.Position
	-- the old battery (cap and warning light too) moves as one piece
	local old = { battery }
	local cap = m:FindFirstChild("BatteryCap")
	if cap then table.insert(old, cap) end
	for _, p in m:GetChildren() do
		if (p.Name == "WarnLight" or p.Name == "BatteryJunk") and (p.Position - center).Magnitude < 1.2 then table.insert(old, p) end
	end
	local oldOff, fresh = {}, {}
	for _, p in old do
		oldOff[p] = CFrame.new(center):ToObjectSpace(p.CFrame)
		if orig[p] then
			-- a brand-new copy for later
			local c = p:Clone()
			c.Size, c.Color, c.Material = orig[p].Size, orig[p].Color, orig[p].Material
			c.Transparency = 0
			fresh[c] = CFrame.new(center):ToObjectSpace(orig[p].CFrame)
		end
	end

	-- 1. tap it: out it pops, into the parts bin
	setInstruction("Tap the dead battery", step)
	tapOn({ battery, cap })
	sfx(SFX.Tap, 0.8, 0.7)
	-- a slow, high arc you can follow, ending inside the bin
	local inside = BIN - Vector3.new(0, 0.6, 0)
	animate(0.8, function(a)
		local p = center:Lerp(inside, a) + Vector3.new(0, math.sin(a * math.pi) * 2.8, 0)
		for part, o in oldOff do part.CFrame = CFrame.new(p) * CFrame.Angles(a * 3.5, a * 1.5, 0) * o end
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	binLand()
	for _, p in old do p:Destroy() end
	addToBin()

	-- 2. tap the holder: a fresh battery (if you have any left)
	setInstruction("Tap the battery holder", step)
	local spot -- the battery comes off the top of the rack
	while true do
		tapOn(RACKS.targets(dock, { "^RackBase", "^RackGrid", "^Upright$" }, { "^Battery%d" }))
		spot = topCell(dock)
		if Remotes.UseBattery:InvokeServer() then break end
		if (player:GetAttribute("Batteries") or 0) <= 0 then
			setInstruction("Out of batteries!", step)
			if not needStock("Batteries", true) then error("OUT_OF_STOCK") end
			setInstruction("Tap the battery holder", step)
		end
	end
	-- it pops up off the rack and drops into the scooter
	spot = spot or dock.RackBase.Position + Vector3.new(0, 0.5, 0)
	for c, o in fresh do
		c.CFrame = CFrame.new(spot) * o
		c.Parent = m
	end
	sparkle(spot)
	sfx(SFX.Tap, 0.8, 1.2)
	animate(0.45, function(a)
		local p = spot:Lerp(center, a) + Vector3.new(0, math.sin(a * math.pi) * 2.2, 0)
		for c, o in fresh do c.CFrame = CFrame.new(p) * CFrame.Angles(0, (1 - a) * 6, 0) * o end
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for c, o in fresh do c.CFrame = CFrame.new(center) * o end
	sfx(SFX.Done, 0.9, 1.3)
	sparkle(center)
	-- the screen lights up: it has power again
	local screen = m:FindFirstChild("Screen")
	if screen then
		local mat, col = screen.Material, screen.Color
		screen.Material = Enum.Material.Neon
		screen.Color = Color3.fromRGB(120, 255, 160)
		task.delay(0.7, function()
			screen.Material, screen.Color = mat, col
		end)
	end
end

-- Worn-out tyre: tap it and it pops off into the bin, tap the tyre rack and a new
-- one flies over, then circle your finger round the wheel to spin it on.
-- Uses one tyre from your stock (the tyres standing on the rack).
FIX.Worn = function(m, step)
	local rack = myStations:WaitForChild("TyreRack")
	local tyre, hub = m.TyreRear, m.TyreRearHub
	local home = orig[tyre].CFrame
	local axle = home.Position
	local rot = home - axle
	-- the axle runs across the scooter; `axis` points at the camera
	local axis = m:GetPivot().ZVector
	if axis:Dot(camera.CFrame.Position - axle) < 0 then axis = -axis end

	-- 1. tap the worn tyre: it pulls off the wheel and flies into the bin
	local worn = m:FindFirstChild("TyreWorn")
	local old = {}
	if worn then
		table.insert(old, worn)
	else
		local c = tyre:Clone()
		c.Name = "OldTyre"
		c.Parent = m
		table.insert(old, c)
		tyre.Transparency = 1
	end
	for _, c in m:GetChildren() do
		if c.Name == "WornCrack" then table.insert(old, c) end
	end
	setInstruction("Tap the worn tyre", step)
	tapOn({ old[1], hub })
	local offs = {}
	for _, p in old do offs[p] = CFrame.new(axle):ToObjectSpace(p.CFrame) end
	sfx(SFX.Tap, 0.8, 0.6)
	puff(axle, Color3.fromRGB(150, 140, 130), 6)
	local pulled = axle + axis * 0.8
	animate(0.2, function(a)
		local p = axle:Lerp(pulled, a)
		for part, o in offs do part.CFrame = CFrame.new(p) * CFrame.fromAxisAngle(axis, math.sin(a * math.pi * 2) * 0.15) * o end
	end)
	local inside = BIN - Vector3.new(0, 0.6, 0)
	animate(0.75, function(a)
		local p = pulled:Lerp(inside, a) + Vector3.new(0, math.sin(a * math.pi) * 2.8, 0)
		for part, o in offs do part.CFrame = CFrame.new(p) * CFrame.Angles(a * 4, a * 1.2, 0) * o end
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	binLand()
	for _, p in old do p:Destroy() end
	addToBin()

	-- 2. tap the rack: the top tyre comes off it (if you have any left)
	setInstruction("Tap the tyre rack", step)
	local taken
	while true do
		tapOn(RACKS.targets(rack, { "^Frame[LR]", "^TopBar" }, { "^Tyre%d" }))
		taken = RACKS.topTyre(rack)
		taken = taken and taken[1].CFrame
		if Remotes.UseTyre:InvokeServer() then break end
		if (player:GetAttribute("Tyres") or 0) <= 0 then
			setInstruction("Out of tyres!", step)
			if not needStock("Tyres", true) then error("OUT_OF_STOCK") end
			setInstruction("Tap the tyre rack", step)
		end
	end
	-- the scooter's own tyre (fresh rubber) flies over from where the rack tyre stood
	local start = axle + axis * 1.5
	local from = taken or rack.TopBar.CFrame
	-- the rack tyres stand side-on: turn the scooter tyre to match, then back
	local fromRot = (from - from.Position) * CFrame.Angles(0, math.pi / 2, 0)
	tyre.Size, tyre.Material = orig[tyre].Size, orig[tyre].Material
	tyre.Color = Config.Rubber or orig[tyre].Color
	tyre.Transparency = 0
	sparkle(from.Position)
	sfx(SFX.Tap, 0.8, 1.2)
	animate(0.55, function(a)
		local p = from.Position:Lerp(start, a) + Vector3.new(0, math.sin(a * math.pi) * 2, 0)
		tyre.CFrame = CFrame.new(p) * fromRot:Lerp(rot, a)
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- 3. hold and circle round the wheel: a ring of dots round it shows the move (a bright
	-- dot runs round it until you get going) and fills up as the tyre screws on
	setInstruction("Hold and circle round the wheel", step)
	local guide = Config.Mini.ring(axle + axis * 0.75, math.max(orig[tyre].Size.X, orig[tyre].Size.Y, orig[tyre].Size.Z) / 2 + 0.35)
	local need, total, spin, cw, lastAng = 2 * math.pi, 0, 0, 0, nil
	pendingPress = nil
	while total < need do
		RunService.RenderStepped:Wait()
		local sp = camera:WorldToScreenPoint(axle)
		local v = pointer - Vector2.new(sp.X, sp.Y)
		if state == "repair" and holding and v.Magnitude > 10 then
			local ang = math.atan2(v.Y, v.X)
			if lastAng then
				local dA = ang - lastAng
				if dA > math.pi then dA -= 2 * math.pi elseif dA < -math.pi then dA += 2 * math.pi end
				local before = total
				total += math.abs(dA)
				cw += dA
				spin -= dA -- screen y points down, so this turns the tyre with your finger
				if math.floor(before / (math.pi / 4)) < math.floor(total / (math.pi / 4)) then
					sfx(SFX.Tap, 0.4, 1.1 + total / need * 0.7)
				end
			end
			lastAng = ang
		else
			lastAng = nil
		end
		local p = math.min(1, total / need)
		guide.hint(total < 0.8)
		guide.progress(p, cw >= 0 and 1 or -1)
		tyre.CFrame = CFrame.new(axle + axis * 1.5 * (1 - p)) * CFrame.fromAxisAngle(axis, spin) * rot
	end
	guide.destroy()

	-- seated: the wheel spins freely for a moment and the rim shines again
	hub.Color = orig[hub].Color
	sparkle(axle)
	sfx(SFX.Done, 0.6, 1.3)
	local hubHome = orig[hub].CFrame
	-- both end on whole turns, so nothing jumps when they settle
	local TAU = 2 * math.pi
	local dir = spin < 0 and -1 or 1 -- keep turning the way your finger went
	local stop = dir < 0 and (math.floor(spin / TAU) - 1) * TAU or (math.ceil(spin / TAU) + 1) * TAU
	local hubTurns = dir * math.max(1, math.floor(math.abs(stop - spin) / TAU + 0.5))
	animate(0.6, function(a)
		tyre.CFrame = CFrame.new(axle) * CFrame.fromAxisAngle(axis, spin + (stop - spin) * a) * rot
		hub.CFrame = CFrame.new(axle) * CFrame.fromAxisAngle(axis, hubTurns * TAU * a) * (hubHome - axle)
	end, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tyre.CFrame = home
	hub.CFrame = hubHome
end

-- Loose bolts: the wrench jumps onto each bolt by itself. A ring of lights round the
-- bolt has a green arc and a bright dot sweeping round it: tap when the dot is in the
-- green. Three bolts, each with a smaller arc and a faster dot. No hands, no UI bar.
FIX.Bolts = function(m, step)
	local rack = myStations:WaitForChild("WrenchRack")
	local wrench = rack.Wrench
	local home = wrench:GetPivot()
	local jaw = (wrench.JawL.Position + wrench.JawR.Position) / 2
	local jawOff = home:ToObjectSpace(CFrame.new(jaw))
	local function wrenchOn(bolt, swing)
		local at = bolt.Position + Config.P.vec(Vector3.new(0, 0, 0.15))
		return CFrame.new(at) * Config.P.rot(CFrame.Angles(0, 0, math.rad(-35 + swing))) * jawOff:Inverse()
	end
	local bolts = { m.Bolt1, m.Bolt2, m.Bolt3 }

	-- push the camera in on the handlebar clamp: the bolts are tiny from the bench view
	local clamp = (bolts[1].Position + bolts[2].Position + bolts[3].Position) / 3
	local camFrom = camera.CFrame
	local toCam = (REPAIR_CAM.Position - clamp).Unit
	local closeCam = CFrame.lookAt(clamp + toCam * 2.6 + Vector3.new(0, -0.25, 0), clamp)
	local from = wrench:GetPivot()
	sfx(SFX.Tap, 0.6, 0.9)
	animate(0.4, function(a)
		camera.CFrame = camFrom:Lerp(closeCam, a)
		wrench:PivotTo(from:Lerp(wrenchOn(bolts[1], 0), a) * CFrame.Angles(0, 0, math.sin(a * math.pi) * 0.6))
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	setInstruction("Tap in the green! Gold = PERFECT", step)
	-- a better wrench (ratchet, impact gun) has a bigger arc and a calmer dot; rarer scooters are fiddlier
	local wrenchLevel = player:GetAttribute("Wrench") or 1
	local zoneMul = (SHOP.Wrench and SHOP.Wrench.Zone[wrenchLevel] or 1) * (player:GetAttribute("GoldenWrench") == 1 and Config.Caro.Boost.GoldenWrench or 1)
	local rar = active and RARITY[active.job.Rarity]
	local speedMul = (SHOP.Wrench and SHOP.Wrench.Speed[wrenchLevel] or 1) * (1 + 0.08 * ((rar and rar.Index or 1) - 1))
	local GOLD = Color3.fromRGB(255, 200, 40)

	-- the ring: neon segments in a circle facing the camera, plus the sweeping dot
	local SEGS, RADIUS = 40, 0.32
	local DIM = Color3.fromRGB(60, 64, 76)
	local ring = Instance.new("Model")
	ring.Name = "TorqueRing"
	local function bit(shape, size)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.Material = Enum.Material.Neon
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Parent = ring
		return p
	end
	local segs = {}
	local segLen = 2 * math.pi * RADIUS / SEGS * 0.7
	for i = 1, SEGS do segs[i] = bit(Enum.PartType.Block, Vector3.new(segLen, 0.075, 0.03)) end
	local dot = bit(Enum.PartType.Ball, Vector3.new(0.13, 0.13, 0.13))
	dot.Color = Color3.new(1, 1, 1)
	ring.Parent = m

	for i, bolt in bolts do
		if i > 1 then
			local f = wrench:GetPivot()
			animate(0.18, function(a) wrench:PivotTo(f:Lerp(wrenchOn(bolt, 0), a)) end)
		end
		local face = CFrame.lookAt(bolt.Position + toCam * 0.2, camera.CFrame.Position)
		local function onRing(turn, r)
			return face * CFrame.Angles(0, 0, -turn * 2 * math.pi) * CFrame.new(0, r or RADIUS, 0)
		end
		-- the green arc (fractions of a turn), never right where the dot starts; its middle 40% is gold (PERFECT).
		-- Owner, 24 Oct: "the bolts minigame must be a lot more challenging like more speed": a smaller arc and
		-- a faster dot than before, quicker on every bolt, every other bolt the other way round.
		local zoneW = math.clamp((0.18 - 0.015 * (i - 1)) * zoneMul, 0.07, 0.42)
		local zoneAt = 0.3 + math.random() * (0.6 - zoneW)
		local function inZone(t)
			t %= 1
			return t >= zoneAt and t <= zoneAt + zoneW
		end
		local function inSweet(t)
			t %= 1
			return math.abs(t - (zoneAt + zoneW / 2)) <= zoneW * 0.2
		end
		local function paintRing()
			for k, sgm in segs do
				local t = (k - 0.5) / SEGS
				sgm.CFrame = onRing(t)
				sgm.Color = inSweet(t) and GOLD or inZone(t) and GREEN or DIM
				sgm.Transparency = inZone(t) and 0 or 0.25
			end
		end
		paintRing()
		-- turns per second
		local baseSpeed = (0.85 + 0.2 * (i - 1)) * speedMul
		local speed = baseSpeed
		local spin = i % 2 == 0 and -1 or 1
		local misses = 0
		local t = 0
		pendingPress = nil
		while true do
			local dt = RunService.RenderStepped:Wait()
			t += speed * dt * spin
			dot.CFrame = onRing(t, RADIUS + 0.01)
			local press = pendingPress
			pendingPress = nil
			if press and state == "repair" then
				if inZone(t) then
					dot.Color = inSweet(t) and GOLD or GREEN
					sfx(SFX.Ratchet, 0.7, 1 + i * 0.05)
					ui.skill.hit(inSweet(t) and "perfect" or "good", bolt.Position)
					local bf = bolt.CFrame
					animate(0.25, function(a)
						wrench:PivotTo(wrenchOn(bolt, -70 * a))
						bolt.CFrame = bf:Lerp(orig[bolt].CFrame, a) * CFrame.Angles(a * math.pi * 2, 0, 0)
					end)
					bolt.CFrame = orig[bolt].CFrame
					bolt.Color = orig[bolt].Color
					sparkle(bolt.Position)
					task.wait(0.1)
					dot.Color = Color3.new(1, 1, 1)
					break
				else
					-- a miss: the ring flashes red, the wrench slips, it costs time (Skill) and the dot speeds up.
					-- After Config.MissHelp misses on one bolt the green grows back and the dot calms down.
					shake(0.3, 0.16)
					ui.skill.hit("miss", bolt.Position)
					misses += 1
					dot.Color = RED
					for _, sgm in segs do if sgm.Color == DIM then sgm.Color = RED end end
					local f = wrench:GetPivot()
					animate(0.15, function(a)
						wrench:PivotTo(f * CFrame.Angles(0, 0, math.sin(a * math.pi * 3) * 0.12))
					end)
					dot.Color = Color3.new(1, 1, 1)
					if misses >= Config.MissHelp then
						misses = 0
						zoneW = math.min(0.42, zoneW * 1.5)
						zoneAt = math.clamp(zoneAt - zoneW * 0.17, 0.05, 0.95 - zoneW)
						speed = baseSpeed * 0.85
					else
						speed *= 1.1
					end
					paintRing()
				end
			end
		end
	end
	ring:Destroy()

	-- tight clamp: the handlebar swings back straight
	local bar = { m.Handlebar, m.Screen }
	for _, p in m:GetChildren() do
		if p.Name == "Grip" or p.Name:match("^Phone") then table.insert(bar, p) end
	end
	local barFrom = {}
	for _, p in bar do
		if orig[p] then barFrom[p] = p.CFrame end
	end
	local f = wrench:GetPivot()
	animate(0.35, function(a)
		wrench:PivotTo(f:Lerp(home, a))
		camera.CFrame = closeCam:Lerp(camFrom, a)
		for p, c in barFrom do p.CFrame = c:Lerp(orig[p].CFrame, a) end
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	camera.CFrame = camFrom
end

-- Broken light: it's small, so the camera moves in on it. Tap it and a junction box
-- pops out (Minigames.wires: drag each wire to its colour); the light swings back up,
-- tap the dead bulb out, tap the bulb box and a new bulb flies over and screws in.
FIX.Light = function(m, step)
	local light, rim = m.Light, m.LightRim
	local camFrom = REPAIR_CAM
	local function closeUp(at)
		return CFrame.lookAt(at + Config.P.vec(Vector3.new(2.9, 0.7, 2.1)), at + Config.P.vec(Vector3.new(0.1, -0.55, 0)))
	end
	local close = closeUp(rim.Position)
	local camAt = camera.CFrame
	animate(0.45, function(a) camera.CFrame = camAt:Lerp(close, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	setInstruction("Tap the broken light", step)
	tapOn({ light, rim })
	Config.Mini.wires(light, rim, step)

	-- wired up: the light swings back up into place (the dead bulb still in it)
	local dead = m:FindFirstChild("DeadBulb")
	local deadOff = dead and light.CFrame:ToObjectSpace(dead.CFrame)
	local lightFrom, rimFrom = light.CFrame, rim.CFrame
	local twins = {}
	for _, n in { "Light2", "LightRim2", "LightBar" } do
		local p = m:FindFirstChild(n)
		if p and orig[p] then twins[p] = p.CFrame end
	end
	animate(0.35, function(a)
		light.CFrame = lightFrom:Lerp(orig[light].CFrame, a)
		rim.CFrame = rimFrom:Lerp(orig[rim].CFrame, a)
		for p, from in twins do p.CFrame = from:Lerp(orig[p].CFrame, a) end
		if dead then dead.CFrame = light.CFrame * deadOff end
	end, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	sfx(SFX.Tap, 0.8, 0.9)
	local front = (orig[light].CFrame.Position - orig[rim].CFrame.Position).Unit
	local socket = orig[light].CFrame.Position + front * 0.1

	-- 1. tap the dead bulb: it pops out and lobs into the bin as the camera pulls back
	camAt = camera.CFrame
	if dead then
		setInstruction("Tap the dead bulb", step)
		tapOn({ dead })
		local from = dead.Position
		local out = from + front * 0.5
		animate(0.15, function(a) dead.CFrame = CFrame.new(from:Lerp(out, a)) end)
		local inside = BIN - Vector3.new(0, 0.6, 0)
		animate(0.65, function(a)
			dead.CFrame = CFrame.new(out:Lerp(inside, a) + Vector3.new(0, math.sin(a * math.pi) * 2.4, 0)) * CFrame.Angles(a * 6, 0, a * 3)
			camera.CFrame = camAt:Lerp(camFrom, a)
		end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		binLand()
		dead:Destroy()
		addToBin()
	else
		animate(0.45, function(a) camera.CFrame = camAt:Lerp(camFrom, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	camera.CFrame = camFrom

	-- 2. tap the bulb box (its bulbs glow too): a fresh bulb flies over and screws itself in
	local box = myStations:WaitForChild("BulbBox")
	setInstruction("Tap the bulb box", step)
	local from
	while true do
		tapOn(RACKS.targets(box, { "^Box$", "^Lid$" }, { "^Bulb%d" }))
		local top = RACKS.topBulb(box)
		from = top and { top[1]:Clone(), top[2]:Clone() }
		if Remotes.UseBulb:InvokeServer() then break end
		if (player:GetAttribute("Bulbs") or 0) <= 0 then
			setInstruction("Out of bulbs!", step)
			if not needStock("Bulbs", true) then error("OUT_OF_STOCK") end
			setInstruction("Tap the bulb box", step)
		end
	end
	-- the bulb (glass + screw base) flies over and twists in, glass first out of the lamp
	if not from then
		local spare = box.Bulb1
		from = { box.Bulb1:Clone(), box.Bulb1Base:Clone() }
		from[1].CFrame, from[2].CFrame = spare.CFrame, box.Bulb1Base.CFrame
	end
	local glass, screw = from[1], from[2]
	glass.Transparency, screw.Transparency = 0.15, 0
	glass.Parent, screw.Parent = m, m
	local start = glass.CFrame
	local screwOff = start:ToObjectSpace(screw.CFrame)
	-- the bulb stands up (screw at the bottom); in the lamp the screw points back in
	local upright = start - start.Position
	local tilt = Vector3.yAxis:Cross(front)
	local fitted = CFrame.fromAxisAngle(tilt.Magnitude > 1e-3 and tilt.Unit or Vector3.xAxis, math.acos(math.clamp(Vector3.yAxis:Dot(front), -1, 1))) * upright
	local function place(cf)
		glass.CFrame = cf
		screw.CFrame = cf * screwOff
	end
	sparkle(start.Position)
	sfx(SFX.Tap, 0.8, 1.3)
	-- the camera moves back in to watch it go in
	local hover = socket + front * 0.45
	close = closeUp(orig[rim].CFrame.Position)
	animate(0.55, function(a)
		local p = start.Position:Lerp(hover, a) + Vector3.new(0, math.sin(a * math.pi) * 2, 0)
		place(CFrame.new(p) * upright:Lerp(fitted, a))
		camera.CFrame = camFrom:Lerp(close, a)
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	-- it twists in (the way a real bulb screws in), with a click at the end
	animate(0.4, function(a)
		place(CFrame.new(hover:Lerp(socket, a)) * CFrame.fromAxisAngle(front, a * math.pi * 4) * fitted)
	end, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	sfx(SFX.Tap, 0.7, 1.6)
	glass:Destroy()
	screw:Destroy()

	-- 3. it flickers, then comes on
	for i = 1, 3 do
		light.Material = Enum.Material.Neon
		light.Color = orig[light].Color
		task.wait(0.07)
		light.Material = Enum.Material.SmoothPlastic
		light.Color = Color3.fromRGB(60, 60, 66)
		task.wait(0.07 + i * 0.03)
	end
	light.Material = orig[light].Material
	light.Color = orig[light].Color
	local light2 = m:FindFirstChild("Light2")
	if light2 and orig[light2] then
		light2.Material = orig[light2].Material
		light2.Color = orig[light2].Color
	end
	sparkle(light.Position)
	task.wait(0.3)
	animate(0.45, function(a) camera.CFrame = close:Lerp(camFrom, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	camera.CFrame = camFrom
end

-- Low battery: tap the charger and the plug flies over and clicks into the battery
-- by itself (a hanging cable follows it). Then sparks zip round the battery: tap them
-- to charge it faster. The charge shows on the charger's screen, not on yours.
-- Low battery. plugCharger does step 1 (tap the charger, the plug hops into the battery) and puts up the
-- meter; it returns a handle the fix drives: fill it in the background while other fixes are done
-- (Config.ChargeInBackground), or tap sparks to top it up, then unplug.
local function plugCharger(m, step, startAt)
	local dock = myStations:WaitForChild("BatteryDock")
	local plug, tip = dock.Plug, dock.PlugTip
	local plugHome = plug.CFrame
	local tipOff = plugHome:ToObjectSpace(tip.CFrame)
	local battery = m.Battery
	local port = battery.Position + Config.P.vec(Vector3.new(battery.Size.X / 2 + 0.3, 0.05, 0))
	local function setPlug(cf)
		plug.CFrame = cf
		tip.CFrame = cf * tipOff
	end
	local level = player:GetAttribute("BatteryDock") or 1 -- the charger is part of the battery station (v5)
	local item = SHOP.BatteryDock
	local rate = item and item.Rate and item.Rate[level] or 0.05
	local boost = (item and item.Spark[level] or 0.2) * (player:GetAttribute("NeonCharger") == 1 and Config.Caro.Boost.NeonCharger or 1)

	-- 1. tap the charger: the plug hops over to the battery, the cable follows
	setInstruction("Tap the charger", step)
	tapOn({ plug, tip, dock.ChargerBase, dock.Screen })
	-- the moulded cable can't stretch: swap it for a hanging one while the plug is out
	local coiled = dock:FindFirstChild("Cable")
	local cable, a0, a1
	do
		local dockPart = dock:FindFirstChild("PlugDock") or dock.ChargerBase
		local DOWN = CFrame.Angles(0, 0, -math.pi / 2) -- an attachment's X axis points down
		a0 = Instance.new("Attachment")
		a0.CFrame = dockPart.CFrame:ToObjectSpace(CFrame.new(dockPart.Position) * DOWN)
		a0.Parent = dockPart
		-- on the plug: at its back end, pointing the way the tip points
		local tipDir = plug.CFrame:VectorToObjectSpace((tip.Position - plug.Position).Unit)
		local perp = math.abs(tipDir.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
		local back = -tipDir * (plug.Size.Y / 2)
		a1 = Instance.new("Attachment")
		a1.CFrame = CFrame.fromMatrix(back, tipDir, tipDir:Cross(perp).Unit)
		a1.Parent = plug
		cable = Instance.new("Beam")
		cable.Attachment0, cable.Attachment1 = a0, a1
		cable.Width0, cable.Width1 = 0.09, 0.09
		cable.Segments = 24
		cable.FaceCamera = true
		cable.Color = ColorSequence.new(Config.Rubber or Color3.fromRGB(32, 33, 38))
		cable.Transparency = NumberSequence.new(0)
		cable.LightInfluence = 1
		cable.CurveSize0, cable.CurveSize1 = 0.6, 0.5
		cable.Parent = plug
		if coiled then coiled.Transparency = 1 end
	end
	-- plugged in: the plug turns so its tip goes into the side of the battery
	local tipWorld = (tip.Position - plug.Position).Unit
	local into = -Config.P.vec(Vector3.xAxis)
	local turn = CFrame.identity
	local axisOfTurn = tipWorld:Cross(into)
	if axisOfTurn.Magnitude > 1e-3 then
		turn = CFrame.fromAxisAngle(axisOfTurn.Unit, math.acos(math.clamp(tipWorld:Dot(into), -1, 1)))
	end
	local reach = (tip.Position - plug.Position).Magnitude + 0.06
	local plugged = CFrame.new(battery.Position + Config.P.vec(Vector3.new(battery.Size.X / 2 + reach, 0.05, 0))) * turn * (plugHome - plugHome.Position)
	animate(0.45, function(a)
		setPlug(plugHome:Lerp(plugged, a) + Vector3.new(0, math.sin(a * math.pi) * 1.2, 0))
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	setPlug(plugged)
	sfx(SFX.Tap, 0.9, 0.7)
	puff(port, Color3.fromRGB(255, 240, 150), 5)

	-- the charger's screen becomes the charge meter: dark, then it fills from the left
	local sign = dock:FindFirstChild("Screen")
	local signColor, signMat, fill = sign and sign.Color, sign and sign.Material, nil
	local EMPTY, HALF, FULL = Color3.fromRGB(235, 80, 60), Color3.fromRGB(255, 205, 60), Color3.fromRGB(90, 230, 120)
	if sign then
		sign.Color, sign.Material = Color3.fromRGB(28, 30, 36), Enum.Material.SmoothPlastic
		fill = Instance.new("Part")
		fill.Name = "ChargeFill"
		fill.Anchored, fill.CanCollide, fill.CanQuery, fill.CanTouch, fill.CastShadow = true, false, false, false, false
		fill.Material = Enum.Material.Neon
		fill.Parent = dock
	end
	-- a battery gauge over the scooter's battery: fills up with the percentage on it,
	-- and every spark you catch pops its "+%" above it
	local meter = Instance.new("BillboardGui")
	meter.Name = "ChargeMeter"
	meter.Adornee = battery
	meter.Size = UDim2.fromOffset(150, 96)
	meter.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0) -- clear of the sparks' loop
	meter.AlwaysOnTop = true
	meter.LightInfluence = 0
	meter.ResetOnSpawn = false
	local shell = Instance.new("Frame")
	shell.AnchorPoint = Vector2.new(0.5, 1)
	shell.Position = UDim2.new(0.5, -6, 1, -4)
	shell.Size = UDim2.fromOffset(120, 52)
	shell.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	Instance.new("UICorner", shell).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", shell)
	stroke.Color = Color3.fromRGB(245, 245, 250)
	stroke.Thickness = 3
	shell.Parent = meter
	local nub = Instance.new("Frame")
	nub.AnchorPoint = Vector2.new(0, 0.5)
	nub.Position = UDim2.new(1, 3, 0.5, 0)
	nub.Size = UDim2.fromOffset(9, 22)
	nub.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
	Instance.new("UICorner", nub).CornerRadius = UDim.new(0, 4)
	nub.Parent = shell
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(6, 6)
	bar.Size = UDim2.new(0, 0, 1, -12)
	bar.BorderSizePixel = 0
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)
	bar.Parent = shell
	local pct = Instance.new("TextLabel")
	pct.BackgroundTransparency = 1
	pct.Size = UDim2.fromScale(1, 1)
	pct.FontFace = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	pct.TextSize = 26
	pct.TextColor3 = Color3.new(1, 1, 1)
	pct.ZIndex = 2
	local pctStroke = Instance.new("UIStroke", pct)
	pctStroke.Color = Color3.fromRGB(18, 19, 25)
	pctStroke.Thickness = 2.5
	pct.Parent = shell
	meter.Parent = player.PlayerGui
	popScale(shell, 0.6)
	local function boostPop(amount)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.new(0.5, 0, 1, -58)
		t.Size = UDim2.fromOffset(110, 30)
		t.FontFace = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
		t.TextSize = 24
		t.Text = ("+%d%%"):format(math.floor(amount * 100 + 0.5))
		t.TextColor3 = Color3.fromRGB(255, 225, 90)
		local s = Instance.new("UIStroke", t)
		s.Color = Color3.fromRGB(18, 19, 25)
		s.Thickness = 2.5
		t.Parent = meter
		TweenService:Create(t, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, -84), TextTransparency = 1 }):Play()
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		task.delay(0.65, function() t:Destroy() end)
		popScale(shell, 0.9, 0.15)
	end

	-- its own colour, kept now: the fix on the bench may load another look table while this one charges
	local batteryColor = orig[battery] and orig[battery].Color or battery.Color
	local function showCharge(c)
		c = math.clamp(c, 0, 1)
		local col = c < 0.5 and EMPTY:Lerp(HALF, c * 2) or HALF:Lerp(FULL, (c - 0.5) * 2)
		battery.Color = Color3.fromRGB(225, 95, 50):Lerp(batteryColor, c)
		bar.Size = UDim2.new(c, c > 0 and -12 * c or 0, 1, -12)
		bar.BackgroundColor3 = col
		pct.Text = ("%d%%"):format(math.floor(c * 100))
		if fill then
			local w = math.max(0.02, (sign.Size.X - 0.1) * c)
			fill.Size = Vector3.new(w, sign.Size.Y - 0.1, 0.02)
			-- on whichever face of the screen looks at the camera
			local side = sign.CFrame:PointToObjectSpace(camera.CFrame.Position).Z < 0 and -1 or 1
			-- and it fills from the left as you see it
			local fromLeft = sign.CFrame.RightVector:Dot(camera.CFrame.RightVector) < 0 and -1 or 1
			fill.CFrame = sign.CFrame * CFrame.new(fromLeft * (-(sign.Size.X - 0.1) / 2 + w / 2), 0, side * (sign.Size.Z / 2 + 0.011))
			fill.Color = col
		end
	end

	-- electric sparks: a hot white-yellow core with a trail, crackling bits and a glow
	local HOT, AMBER = Color3.fromRGB(255, 250, 215), Color3.fromRGB(255, 190, 60)
	local function newSpark()
		local s = Instance.new("Part")
		s.Name = "Spark"
		s.Shape = Enum.PartType.Ball
		s.Size = Vector3.new(0.04, 0.04, 0.04)
		s.Anchored, s.CanCollide, s.CanQuery, s.CanTouch, s.CastShadow = true, false, false, false, false
		s.Material = Enum.Material.Neon
		s.Color = HOT
		local t0 = Instance.new("Attachment", s)
		t0.Position = Vector3.new(0, 0.05, 0)
		local t1 = Instance.new("Attachment", s)
		t1.Position = Vector3.new(0, -0.05, 0)
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = t0, t1
		trail.Lifetime = 0.22
		trail.MinLength = 0
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(HOT, AMBER)
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = s
		local crackle = Instance.new("ParticleEmitter")
		crackle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		crackle.Color = ColorSequence.new(HOT, AMBER)
		crackle.LightEmission = 1
		crackle.Size = NumberSequence.new(0.22, 0)
		crackle.Lifetime = NumberRange.new(0.12, 0.28)
		crackle.Speed = NumberRange.new(1.5, 3.5)
		crackle.SpreadAngle = Vector2.new(180, 180)
		crackle.Rate = 28
		crackle.Parent = s
		local glow = Instance.new("PointLight")
		glow.Color = AMBER
		glow.Brightness = 2.5
		glow.Range = 3.5
		glow.Parent = s
		s.Parent = workspace
		TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = Vector3.new(0.17, 0.17, 0.17) }):Play()
		return s
	end
	local function fizzle(p)
		-- out of time: stops crackling, fades, the trail runs out
		local e = p:FindFirstChildOfClass("ParticleEmitter")
		if e then e.Enabled = false end
		local l = p:FindFirstChildOfClass("PointLight")
		if l then l.Enabled = false end
		TweenService:Create(p, TweenInfo.new(0.2), { Size = Vector3.new(0.01, 0.01, 0.01), Transparency = 1 }):Play()
		task.delay(0.3, function() p:Destroy() end)
	end
	-- caught: a little lightning bolt jumps from the spark into the battery
	local function zap(from, to)
		local pts = { from }
		local dir = to - from
		local side = dir:Cross(camera.CFrame.LookVector)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.yAxis
		for k = 1, 4 do
			table.insert(pts, from + dir * (k / 5) + side * (math.random() - 0.5) * 0.3 + Vector3.new(0, (math.random() - 0.5) * 0.15, 0))
		end
		table.insert(pts, to)
		for k = 1, #pts - 1 do
			local p0, p1 = pts[k], pts[k + 1]
			local seg = Instance.new("Part")
			seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
			seg.Material = Enum.Material.Neon
			seg.Color = HOT
			seg.Size = Vector3.new(0.045, 0.045, (p1 - p0).Magnitude + 0.02)
			seg.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
			seg.Parent = workspace
			TweenService:Create(seg, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Transparency = 1, Color = AMBER }):Play()
			task.delay(0.25, function() seg:Destroy() end)
		end
		emit(to, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(HOT, AMBER),
			Size = NumberSequence.new(0.35, 0),
			Lifetime = NumberRange.new(0.15, 0.35),
			Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		}, 14)
	end

	local ch = { charge = startAt or 0 }
	showCharge(ch.charge)

	-- in the background: it fills at the dock's rate while you do the other fixes; onFull (no yielding)
	-- runs once when it's full
	function ch.background(onFull)
		ch.conn = RunService.RenderStepped:Connect(function(dt)
			ch.charge += dt * rate
			showCharge(ch.charge)
			if ch.charge >= 1 then
				ch.conn:Disconnect()
				ch.conn = nil
				onFull()
			end
		end)
	end
	function ch.stopBackground()
		if ch.conn then
			ch.conn:Disconnect()
			ch.conn = nil
		end
	end

	-- 2. in the foreground: it charges slowly by itself; sparks circle the battery, each one you tap is a boost
	function ch.topUp()
		setInstruction("Tap the sparks!", step)
		local center = battery.Position
		local toCam = (camera.CFrame.Position - center).Unit
		local face = CFrame.lookAt(center + toCam * 0.4, camera.CFrame.Position)
		local charge, sparks, nextSpark = ch.charge, {}, 0.15
		showCharge(charge)
		pendingPress = nil
		while charge < 1 do
			local dt = RunService.RenderStepped:Wait()
			charge += dt * rate
			nextSpark -= dt
			if nextSpark <= 0 and #sparks < 3 then
				nextSpark = 0.45 + math.random() * 0.35
				-- each spark zips round the battery on its own loop, either way round
				table.insert(sparks, {
					part = newSpark(), born = os.clock(),
					ang = math.random() * math.pi * 2,
					speed = (2.2 + math.random() * 1.6) * (math.random() < 0.5 and -1 or 1),
					r = 0.65 + math.random() * 0.45,
					tilt = 0.6 + math.random() * 0.4,
				})
			end
			for i = #sparks, 1, -1 do
				local s = sparks[i]
				local age = os.clock() - s.born
				if age > 1.8 then
					fizzle(s.part)
					table.remove(sparks, i)
				else
					s.ang += s.speed * dt
					-- a little jitter so it buzzes instead of gliding
					local buzz = (math.random() - 0.5) * 0.06
					s.part.CFrame = face * CFrame.new(math.cos(s.ang) * (s.r + buzz), math.sin(s.ang) * (s.r + buzz) * s.tilt, 0)
				end
			end
			local press = pendingPress
			pendingPress = nil
			if press and state == "repair" and #sparks > 0 then
				local list = {}
				for _, s in sparks do table.insert(list, s.part) end
				local hit = pick(press, list)
				if hit then
					charge += boost
					zap(hit.Position, battery.Position)
					boostPop(boost)
					sfx(SFX.Done, 0.45, 1.1 + charge * 0.6)
					for i, s in sparks do
						if s.part == hit then
							table.remove(sparks, i)
							break
						end
					end
					hit:Destroy()
				end
			end
			showCharge(charge)
		end
		for _, s in sparks do fizzle(s.part) end
		ch.charge = charge
	end

	-- full: the battery's own colour again, a ding, the warning light goes out
	function ch.full()
		ch.charge = 1
		showCharge(1)
		battery.Color = batteryColor
		sparkle(battery.Position)
		sfx(SFX.Done, 0.7, 1.4)
		for _, p in m:GetChildren() do
			if p.Name == "WarnLight" and (p.Position - battery.Position).Magnitude < 1.2 then p:Destroy() end
		end
		task.wait(0.25)
	end

	-- unplug: the plug hops home, the sign is a sign again (a half-charged battery keeps its charge)
	function ch.unplug()
		ch.stopBackground()
		local from = plug.CFrame
		animate(0.35, function(a) setPlug(from:Lerp(plugHome, a) + Vector3.new(0, math.sin(a * math.pi) * 1.2, 0)) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		setPlug(plugHome)
		cable:Destroy()
		a0:Destroy()
		a1:Destroy()
		if coiled then coiled.Transparency = 0 end
		if fill then fill:Destroy() end
		meter:Destroy()
		if sign then sign.Color, sign.Material = signColor, signMat end
	end
	return ch
end

-- Is there anything else to do on this scooter at the bench while its battery charges? (The booth takes
-- the scooter away, so a repaint doesn't count: the battery finishes first.)
local function benchWorkLeft(sess)
	for _, name in sess.job.Problems do
		if name ~= "Charge" and name ~= "Paint" and not sess.done[name] then return true end
	end
	return false
end

-- Low battery (Fever, plan/13): plug it in; if the scooter has other bench fixes, it charges in the
-- background while you do them and pays the moment it's full (onBackgroundFix). Otherwise, or when it's
-- the last thing left, you tap sparks to top it up as before. Returns "background" when left charging.
FIX.Charge = function(m, step)
	local sess = active and active.model == m and active or nil
	if sess and sess.done.Charge then return end -- it finished in the background a moment ago
	local ch = sess and sess.charging
	if ch and ch.finishing then
		-- it's full and unplugging itself right now: let that finish (it ticks and pays the fix)
		while sess.charging do task.wait() end
		return
	end
	if not ch then
		ch = plugCharger(m, step, sess and sess.chargeLevel or 0)
		if sess then sess.charging = ch end
		if sess and Config.ChargeInBackground and benchWorkLeft(sess) then
			popText("Charging... carry on!", 0.55, 1.1, TAN)
			ch.background(function()
				-- full while you worked on something else: no yielding in here, so the rest runs on its own
				-- sess.charging stays set until it's paid, so parking waits for this (stopCharging) and the
				-- pay can't land on the next job
				ch.finishing = true
				task.spawn(function()
					ch.full()
					ch.unplug()
					if sess.bg then sess.bg.Charge = nil end
					if onBackgroundFix then
						local ok, err = pcall(onBackgroundFix, sess, "Charge")
						if not ok then warn("Background charge failed: " .. tostring(err)) end
					end
					sess.done.Charge = true
					sess.charging, sess.chargeLevel = nil, nil
				end)
			end)
			return "background"
		end
	end
	ch.stopBackground()
	ch.topUp()
	ch.full()
	ch.unplug()
	if sess then sess.charging, sess.chargeLevel = nil, nil end
end

-- Repaint, in the paint booth (front-left of the garage). The scooter rolls off the
-- bench into the booth, the colour card on the wall shows the paint the customer
-- wants: tap that can, then spray every panel (the can follows your finger, the
-- panels show how covered they are). It then dries in the booth (heat lamps, fans)
-- while you go back to the bench; when it's dry its owner takes it home.
-- One scooter in the booth at a time.
local BODY_PARTS = { Deck = true, DeckNose = true, DeckTail = true, Stem = true, RearFender = true, FrontFender = true, BatteryBay = true, HandGuardL = true, HandGuardR = true }
local BOOTH = { busy = nil } -- busy = the scooter model in the booth
do
	-- drying: lamps glow, fans spin, the wet shine fades; then it lifts off home
	function BOOTH.dry(done, onGone)
		local p = done.painted
		local booth, m = p.booth, done.model
		local lamps, blades, centres = {}, {}, {}
		for _, c in booth:GetDescendants() do -- the Turbo Dryer's lamps are in its Tier3 folder
			if c.Name == "HeatLamp" then table.insert(lamps, { part = c, color = c.Color, mat = c.Material }) end
			if c.Name == "FanBlade" then table.insert(blades, { part = c, home = c.CFrame }) end
			if c.Name == "FanHub" then centres[c:GetAttribute("Fan")] = c.CFrame end
		end
		for _, l in lamps do
			l.part.Material = Enum.Material.Neon
			l.part.Color = Color3.fromRGB(255, 140, 50)
		end
		local spin = 0
		local conn = RunService.RenderStepped:Connect(function(dt)
			spin += dt * 14
			for _, bl in blades do
				local c = centres[bl.part:GetAttribute("Fan")]
				if c then
					local turn = CFrame.fromAxisAngle(c.RightVector, spin) -- a cylinder's axis is its X
					bl.part.CFrame = CFrame.new(c.Position) * turn * CFrame.new(c.Position):Inverse() * bl.home
				end
			end
		end)
		local t0, nextSteam = os.clock(), 0
		while m.Parent and os.clock() - t0 < p.dry do
			local k = (os.clock() - t0) / p.dry
			for _, part in p.wet do part.Reflectance = 0.3 * (1 - k) end
			if os.clock() > nextSteam then
				nextSteam = os.clock() + 0.5
				puff(m:GetPivot().Position + Vector3.new(math.random() * 2 - 1, 1.6, 0), Color3.fromRGB(245, 245, 250), 2)
			end
			task.wait(0.1)
		end
		conn:Disconnect()
		for _, bl in blades do bl.part.CFrame = bl.home end
		for _, l in lamps do l.part.Material, l.part.Color = l.mat, l.color end
		for _, part in p.wet do part.Reflectance = 0 end
		if m.Parent then
			-- dry: a ding, and off it goes to its owner
			local from = m:GetPivot()
			sparkle(from.Position + Vector3.new(0, 1.5, 0))
			sfx(SFX.Done, 0.6, 1.4)
			task.wait(0.4)
			animate(0.45, function(a)
				m:PivotTo(from + Vector3.new(0, a * 2.5, 0))
				m:ScaleTo(math.max(0.05, 1 - a * a))
			end, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			puff(from.Position + Vector3.new(0, 2.5, 0), nil, 12)
			if not onGone then -- (with onGone the scooter goes on to its owner: handOver)
				m:Destroy()
				origs[m] = nil
			end
		end
		if BOOTH.busy == m then BOOTH.busy = nil end
		if onGone then onGone() end
	end
end

-- A pop-up choice over something in the world (buy a colour, paint anyway?).
-- options = { { Text, Color }, ... }; returns the number picked.
function BOOTH.choice(adornee, options)
	local bb = Instance.new("BillboardGui")
	bb.Name = "BoothChoice"
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(250, 62 * #options)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Active = true
	bb.ResetOnSpawn = false
	local list = Instance.new("UIListLayout", bb)
	list.Padding = UDim.new(0, 8)
	local picked
	for i, o in options do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 54)
		btn.FontFace = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
		btn.TextScaled = true
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Text = o.Text
		btn.BackgroundColor3 = o.Color or BLUE
		btn.AutoButtonColor = true
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 14)
		local st = Instance.new("UIStroke", btn)
		st.Color = Color3.fromRGB(18, 19, 25)
		st.Thickness = 3
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local pad = Instance.new("UIPadding", btn)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		btn.Activated:Connect(function() picked = picked or i end)
		btn.Parent = bb
	end
	bb.Parent = player.PlayerGui
	popScale(bb:FindFirstChildOfClass("TextButton"), 0.6)
	while not picked do task.wait() end
	bb:Destroy()
	sfx(SFX.Tap, 0.8, 1)
	return picked
end

FIX.Paint = function(m, step)
	local booth = myStations:WaitForChild("PaintBooth")
	local item = SHOP.PaintBooth
	local level = player:GetAttribute("PaintBooth") or 1
	local sprayMul = item and item.Spray and item.Spray[level] or 1
	local dryTime = item and item.Dry and item.Dry[level] or 12
	local job = active and active.job

	-- the booth holds one scooter: wait for the last one to dry
	if BOOTH.busy and BOOTH.busy.Parent then
		setInstruction("The paint booth is busy drying...", step)
		while BOOTH.busy and BOOTH.busy.Parent do task.wait(0.2) end
	end
	BOOTH.busy = m

	-- the panels that take the new colour; the spots a painter can reach on each are
	-- worked out while the crane carries it over
	local body = {}
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and BODY_PARTS[p.Name] then table.insert(body, p) end
	end
	local samples
	task.spawn(function() samples = Config.Mini.paintSamples(m, body) end)

	-- 1. the crane lifts it off the bench and lowers it into the booth
	setInstruction("Off to the paint booth...", step)
	Config.Mini.crane(booth, m, { home = true })

	-- 2. the colour card shows the colour the customer asked for
	local wanted
	for _, p in Config.SprayPaints do
		if job and p.Name == job.PaintTo then wanted = p end
	end
	wanted = wanted or Config.SprayPaints[1]
	local card = booth.ColorCard:FindFirstChild("Card")
	if card then
		card.Swatch.BackgroundColor3 = wanted.Color
		card.ColorName.Text = wanted.Name
		popScale(card.Swatch, 0.4, 0.3)
	end
	-- the cans on the rack: an empty one looks empty
	local cans, rackCans = {}, {}
	local function loads(p)
		if p.Special then return player:GetAttribute("Can" .. (p.Name:gsub("%s", ""))) or 0 end
		return p.Stock and (player:GetAttribute(p.Stock) or 0) or 0
	end
	local function showCan(c)
		local empty = not c.bought and loads(c.def) <= 0
		for _, part in c.model:GetDescendants() do
			if part:IsA("BasePart") then part.Transparency = empty and 0.65 or 0 end
		end
	end
	for _, p in Config.SprayPaints do
		if p.Can and booth:FindFirstChild(p.Can) then
			local c = { model = booth[p.Can], def = p }
			table.insert(cans, c)
			table.insert(rackCans, c.model)
			showCan(c)
		end
	end
	-- Caro's rare cans (and a colour bought just now) stand upright on the floor under the rack
	local slots = {}
	do
		local c1, c3 = booth:FindFirstChild("Can1"), booth:FindFirstChild("Can3")
		if c1 and c3 then
			local a, b = c1.Body, c3.Body
			local out = c1.Nozzle.Position - a.Position
			local front = Vector3.new(out.X, 0, out.Z).Unit
			local along = (b.Position - a.Position).Unit
			local upright = CFrame.fromRotationBetweenVectors(out.Unit, Vector3.yAxis) * (a.CFrame - a.Position)
			local floorTop = booth.Floor.Position.Y + booth.Floor.Size.Y / 2
			local mid = (a.Position + b.Position) / 2
			for i = 1, 5 do
				local at = Vector3.new(mid.X, floorTop + a.Size.Z / 2 + 0.02, mid.Z) + front * 0.45 + along * ((i - 3) * 0.62)
				slots[i] = CFrame.new(at) * upright
			end
		end
	end
	local used = 0
	local function nextSlot()
		used += 1
		return slots[used] or (booth.Can1:GetPivot() + Vector3.new(0, 0.75 * used, 0))
	end
	for _, p in Config.SprayPaints do
		if p.Special and player:GetAttribute("Can" .. (p.Name:gsub("%s", ""))) ~= nil and used < #slots then
			local can = booth.Can1:Clone()
			can.Name = "RareCan"
			for _, part in can:GetDescendants() do
				if part:IsA("BasePart") and part.Name == "Body" then part.Color = p.Color end
			end
			can:PivotTo(nextSlot())
			can.Parent = booth
			local c = { model = can, def = p }
			table.insert(cans, c)
			showCan(c)
		end
	end

	-- 3. you step up to the spray rack (first person, like the bench)
	awayFromBench = true
	local painter = Config.Mini.painter(booth, m, rackCans)

	-- a rack colour that's run out: the restock card (no cash refills in the day); ran out, they go home
	if not wanted.Special and wanted.Stock and loads(wanted) <= 0 then
		setInstruction(("No %s paint!"):format(wanted.Name), step)
		if not needStock(wanted.Stock, true) then error("OUT_OF_STOCK") end
		for _, c in cans do showCan(c) end
	end
	-- a special colour: buy it for this job, or make do with another colour
	local ownedCan = wanted.Special and player:GetAttribute("Can" .. (wanted.Name:gsub("%s", ""))) ~= nil
	if (wanted.Special and not (ownedCan and loads(wanted) > 0)) or (not wanted.Special and loads(wanted) <= 0) then
		setInstruction(("No %s paint!"):format(wanted.Name), step)
		local options = {}
		local special = wanted.Special and not ownedCan
		local pack = wanted.Stock and SHOP[wanted.Stock]
		if special then
			table.insert(options, { Text = ("Get %s  10 R$"):format(wanted.Name), Color = GREEN })
		elseif ownedCan then
			table.insert(options, { Text = ("Refill %s  $%d"):format(wanted.Name, Config.Caro.RefillCan), Color = GREEN })
		elseif pack then
			table.insert(options, { Text = ("Refill %s  $%d"):format(wanted.Name, pack.Price), Color = GREEN })
		end
		table.insert(options, { Text = "Use another colour", Color = BLUE })
		local pick = BOOTH.choice(booth.ColorCard, options)
		if pick == 1 and #options == 2 then
			if special then
				local got = false
				local r = Remotes.BuyPaint:InvokeServer()
				if r == "granted" then
					got = true
				elseif r == "prompt" then
					local before = player:GetAttribute("PaintCredits") or 0
					game:GetService("MarketplaceService"):PromptProductPurchase(player, Config.PaintProductId)
					local t0 = os.clock()
					while os.clock() - t0 < 30 and (player:GetAttribute("PaintCredits") or 0) <= before do task.wait(0.2) end
					got = (player:GetAttribute("PaintCredits") or 0) > before
				else
					popText("Not on sale yet", 0.55, 1, RED)
				end
				if got then
					-- a new can in that colour pops up under the rack
					local can = booth.Can1:Clone()
					can.Name = "SpecialCan"
					for _, part in can:GetDescendants() do
						if part:IsA("BasePart") then
							part.Transparency = 0
							if part.Name == "Body" then part.Color = wanted.Color end
						end
					end
					can:PivotTo(nextSlot())
					can.Parent = booth
					sparkle(can:GetPivot().Position)
					sfx(SFX.Done, 0.8, 1.3)
					table.insert(cans, { model = can, def = wanted, bought = true })
				end
			elseif ownedCan and Remotes.RefillCan:InvokeServer(wanted.Name) then
				sfx(SFX.Done, 0.8, 1.2)
				for _, c in cans do showCan(c) end
			elseif pack and Remotes.BuyShop:InvokeServer(pack.Id) then
				sfx(SFX.Done, 0.8, 1.2)
				for _, c in cans do showCan(c) end
			else
				popText("Not enough cash!", 0.55, 1, RED)
			end
		end
	end

	-- 4. tap the paint can you want (the wrong colour gets a warning first)
	local chosen
	while not chosen do
		local usable, parts = {}, {}
		for _, c in cans do
			if c.bought or loads(c.def) > 0 then
				table.insert(usable, c)
				table.insert(parts, c.model:FindFirstChild("Body") or c.model:FindFirstChildWhichIsA("BasePart"))
			end
		end
		if #usable == 0 then
			-- every can's empty: the restock card for the colour they want (or the first one)
			setInstruction("All the cans are empty!", step)
			if not needStock(wanted.Stock or "PaintRed", true) then error("OUT_OF_STOCK") end
			for _, c in cans do showCan(c) end
			continue
		end
		setInstruction(("Take the %s can"):format(wanted.Name), step)
		local hit = tapOn(parts)
		local c
		for _, x in usable do
			if hit and hit:IsDescendantOf(x.model) then c = x end
		end
		if c and c.def.Name ~= wanted.Name then
			-- the wrong colour: warn first
			sfx(SFX.Tap, 0.8, 0.5)
			local pick = BOOTH.choice(c.model:FindFirstChild("Body") or c.model.PrimaryPart, {
				{ Text = ("They want %s!"):format(wanted.Name), Color = GREEN },
				{ Text = ("Paint %s anyway"):format(c.def.Name), Color = RED },
			})
			if pick == 2 then chosen = c end
		elseif c then
			chosen = c
		end
		if chosen and not Remotes.UsePaint:InvokeServer(chosen.def.Name) then
			chosen = nil -- the server said no (out of paint): pick again
			for _, x in cans do showCan(x) end
		end
	end
	local wrong = chosen.def.Name ~= wanted.Name
	if active and active.model == m then active.wrongPaint = wrong end

	-- 5. the can goes into your hand and you paint it a panel at a time; other colours
	-- you have paint over it the same way
	painter.grab(chosen.model)
	local colors = { { Name = chosen.def.Name, Color = chosen.def.Color } }
	for _, c in cans do
		if c ~= chosen and (c.bought or loads(c.def) > 0) then
			local dup = false
			for _, x in colors do if x.Name == c.def.Name then dup = true end end
			if not dup then table.insert(colors, { Name = c.def.Name, Color = c.def.Color }) end
		end
	end
	while not samples do task.wait() end
	local quality = painter.paint({ panels = body, samples = samples, color = chosen.def.Color, name = chosen.def.Name, colors = colors, sprayMul = sprayMul, step = step })
	painter.finish()
	if chosen.bought then
		puff(chosen.model:GetPivot().Position, nil, 6)
		chosen.model:Destroy() -- a bought special can is used up
	end
	for _, c in cans do
		if c.model.Parent then showCan(c) end
	end
	for _, p in body do p.Reflectance = 0.3 end
	if active and active.model == m then
		active.painted = { booth = booth, dry = dryTime, wet = body }
		active.paintQuality = not wrong and quality or nil
	end

	-- 6. the grade, then back to the bench; the camera watches it dry from the booth view
	setInstruction(wrong and "Not the colour they wanted..." or "Drying... it'll be ready soon", step)
	if not wrong then Config.Mini.paintGrade(m, quality) end
	task.wait(wrong and 0.3 or 1.2)
	local _, _, hrp = getRig()
	if hrp then
		local spot = bench.WorkSpot.Position
		local at = Vector3.new(spot.X, hrp.Position.Y + 0.2, spot.Z)
		hrp.CFrame = CFrame.lookAt(at, at - Config.P.vec(Vector3.zAxis))
		hrp.Anchored = false
	end
	hideSelf(true)
	local camAt = camera.CFrame
	animate(0.6, function(a) camera.CFrame = camAt:Lerp(booth.BoothCam.CFrame, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	camera.FieldOfView = 60
	awayFromBench = false
end

-- Nitro: filled at the kit, then fitted. The camera turns to the nitro kit; tap its
-- bottle and the hose clips onto the valve by itself. Hold to fill: the needle on the
-- kit's gauge climbs; let go while it's in the green. Too little or too much and it
-- vents and drops back. Then the full bottle hops onto the scooter's deck.
FIX.Nitro = function(m, step)
	local kit = myStations:WaitForChild("NitroKit")
	local source = kit.Bottle
	local crate = kit.Crate
	local level = player:GetAttribute("NitroKit") or 1
	local item = SHOP.NitroKit
	local zoneW = item and item.Zone and item.Zone[level] or 0.14
	local rate = item and item.Fill and item.Fill[level] or 0.5

	-- 1. look at the kit
	local camFrom = camera.CFrame
	local center = crate.Position + Vector3.new(0, 0.3, 0)
	local kitCam = CFrame.lookAt(center + Config.P.vec(Vector3.new(-1.4, 1.5, 2.7)), center + Config.P.vec(Vector3.new(-0.3, -0.15, 0)))
	animate(0.45, function(a) camera.CFrame = camFrom:Lerp(kitCam, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	setInstruction("Tap the nitro bottle", step)
	tapOn(partsOf(source))

	-- 2. the hose clips onto the valve: the moulded hose hides, a hanging one follows
	local hoseMesh, hoseEnd, fitting = kit:FindFirstChild("Hose"), kit.HoseEnd, kit.HoseFitting
	local endHome = hoseEnd.CFrame
	local DOWN = CFrame.Angles(0, 0, -math.pi / 2)
	local a0 = Instance.new("Attachment")
	a0.CFrame = fitting.CFrame:ToObjectSpace(CFrame.new(fitting.Position) * DOWN)
	a0.Parent = fitting
	local a1 = Instance.new("Attachment")
	a1.CFrame = hoseEnd.CFrame:ToObjectSpace(CFrame.new(hoseEnd.Position) * DOWN)
	a1.Parent = hoseEnd
	local hose = Instance.new("Beam")
	hose.Attachment0, hose.Attachment1 = a0, a1
	hose.Width0, hose.Width1 = 0.11, 0.11
	hose.Segments = 20
	hose.FaceCamera = true
	hose.Color = ColorSequence.new(Config.Rubber or Color3.fromRGB(32, 33, 38))
	hose.Transparency = NumberSequence.new(0)
	hose.CurveSize0, hose.CurveSize1 = 0.25, -0.25
	hose.Parent = hoseEnd
	if hoseMesh then hoseMesh.Transparency = 1 end
	local valve = source.Valve.Position
	local clipped = CFrame.new(valve + Vector3.new(0, 0.12, 0)) * (endHome - endHome.Position)
	animate(0.3, function(a)
		hoseEnd.CFrame = endHome:Lerp(clipped, a) + Vector3.new(0, math.sin(a * math.pi) * 0.5, 0)
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	hoseEnd.CFrame = clipped
	sfx(SFX.Tap, 0.9, 0.8)

	-- 3. the gauge on the front of the kit: dial, green band, needle
	local outward = Config.P.vec(Vector3.zAxis)
	if (camFrom.Position - crate.Position):Dot(outward) < 0 then outward = -outward end
	local half = crate.Size / 2
	local frontDepth = math.abs(crate.CFrame:VectorToObjectSpace(outward).Z) > 0.5 and half.Z or half.X
	local dialAt = crate.Position + outward * (frontDepth + 0.04) + Vector3.new(0, 0.02, 0) - Config.P.vec(Vector3.xAxis) * 0.5
	local face = CFrame.lookAt(dialAt, dialAt - outward) -- looking into the crate: X = right as you see it, +Z = toward you
	local gauge = Instance.new("Model")
	gauge.Name = "NitroGauge"
	local function bit(shape, size, cf, color, mat)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Parent = gauge
		return p
	end
	bit(Enum.PartType.Cylinder, Vector3.new(0.04, 0.56, 0.56), face * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(245, 245, 250))
	local SWEEP, R = math.rad(270), 0.2
	local function angleOf(f) return -SWEEP / 2 + SWEEP * f end -- from straight up, clockwise
	local function onDial(f, r, z)
		local t = angleOf(f)
		return face * CFrame.new(math.sin(t) * r, math.cos(t) * r, z) * CFrame.Angles(0, 0, -t)
	end
	local zoneLo = 0.6 + math.random() * (0.3 - zoneW)
	local zoneHi = zoneLo + zoneW
	-- the middle 40% of the green is gold: let go there for PERFECT (ScooterClient.Skill)
	local function inSweet(f) return math.abs(f - (zoneLo + zoneHi) / 2) <= zoneW * 0.2 end
	local SEGS = 30
	local segs = {}
	for k = 1, SEGS do
		local f = (k - 0.5) / SEGS
		local inZone = f >= zoneLo and f <= zoneHi
		segs[k] = bit(Enum.PartType.Block, Vector3.new(0.05, 0.06, 0.02), onDial(f, R, 0.03),
			inSweet(f) and ui.style.Color.Gold or inZone and GREEN or Color3.fromRGB(70, 74, 88), inZone and Enum.Material.Neon or Enum.Material.SmoothPlastic)
	end
	local needleLen = 0.17
	local needle = bit(Enum.PartType.Block, Vector3.new(0.025, needleLen, 0.02), onDial(0, needleLen / 2, 0.05), RED, Enum.Material.Neon)
	bit(Enum.PartType.Cylinder, Vector3.new(0.03, 0.06, 0.06), face * CFrame.new(0, 0, 0.06) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(40, 42, 50))
	gauge.Parent = kit
	local function setNeedle(f)
		needle.CFrame = onDial(math.clamp(f, 0, 1), needleLen / 2, 0.05)
	end
	local function flash(color)
		for _, p in segs do
			if p.Material ~= Enum.Material.Neon then p.Color = color end
		end
	end

	-- 4. hold to fill, let go in the green
	setInstruction("Hold to fill, let go in the green!", step)
	local tank = source.Tank
	local cold, coldMat = tank.Color, tank.Material
	local ICE = Color3.fromRGB(150, 230, 255)
	local fill, wasHolding, hiss = 0, false, 0
	pendingPress = nil
	while true do
		local dt = RunService.RenderStepped:Wait()
		local h = holding and state == "repair"
		if h then
			fill += dt * rate
			hiss -= dt
			if hiss <= 0 then
				hiss = 0.09
				puff(valve, Color3.fromRGB(200, 235, 255), 1)
				sfx(SFX.Tap, 0.12, 1.6 + fill)
			end
			if fill >= 1 then
				-- overfilled: it vents and the needle drops back
				shake(0.45, 0.28)
				ui.skill.hit("miss", dialAt, "TOO MUCH!")
				puff(valve, Color3.fromRGB(200, 235, 255), 16)
				sfx(SFX.Tap, 0.9, 0.4)
				flash(RED)
				local f0 = fill
				animate(0.35, function(a) setNeedle(f0 * (1 - a)); tank.Color = cold:Lerp(ICE, f0 * (1 - a)) end)
				flash(Color3.fromRGB(70, 74, 88))
				fill = 0
				h = false
			end
		elseif wasHolding then
			if fill >= zoneLo and fill <= zoneHi then
				ui.skill.hit(inSweet(fill) and "perfect" or "good", dialAt)
				break
			end
			if fill > 0.03 then
				-- let go too early or too late: a short vent, back to empty
				shake(0.3, 0.18)
				ui.skill.hit("miss", dialAt, fill < zoneLo and "TOO EARLY!" or "TOO LATE!")
				sfx(SFX.Tap, 0.7, 0.5)
				flash(RED)
				puff(valve, Color3.fromRGB(200, 235, 255), 6)
				local f0 = fill
				animate(0.3, function(a) setNeedle(f0 * (1 - a)); tank.Color = cold:Lerp(ICE, f0 * (1 - a)) end)
				flash(Color3.fromRGB(70, 74, 88))
				fill = 0
			end
		end
		wasHolding = h
		setNeedle(fill)
		needle.Color = (fill >= zoneLo and fill <= zoneHi) and GREEN or RED
		tank.Color = cold:Lerp(ICE, math.clamp(fill, 0, 1))
	end
	sfx(SFX.Done, 0.8, 1.5)
	sparkle(dialAt)

	-- 5. hose back home; the full bottle hops over onto the scooter's deck
	local endFrom = hoseEnd.CFrame
	animate(0.25, function(a)
		hoseEnd.CFrame = endFrom:Lerp(endHome, a) + Vector3.new(0, math.sin(a * math.pi) * 0.4, 0)
	end)
	hoseEnd.CFrame = endHome
	hose:Destroy()
	a0:Destroy()
	a1:Destroy()
	if hoseMesh then hoseMesh.Transparency = 0 end

	local full = source:Clone()
	full.Tank.Color = ICE
	full.Tank.Material = Enum.Material.Neon
	full.Parent = m
	tank.Color, tank.Material = cold, coldMat
	for _, p in partsOf(source) do p.Transparency = 1 end
	gauge:Destroy()
	local parts = partsOf(full)
	local fromCF = full.Tank.CFrame
	local offs = {}
	for _, p in parts do offs[p] = fromCF:ToObjectSpace(p.CFrame) end
	local deckTop = m.Deck.Position.Y + m.Deck.Size.Y / 2
	local radius = math.min(full.Tank.Size.X, full.Tank.Size.Y, full.Tank.Size.Z) / 2
	local pivot = m:GetPivot()
	local side = pivot.ZVector
	if side:Dot(camFrom.Position - pivot.Position) < 0 then side = -side end
	local mountPos = (pivot * CFrame.new(0.1, 0, 0)).Position
	mountPos = Vector3.new(mountPos.X, deckTop + radius, mountPos.Z) + side * 0.25
	local mountCF = CFrame.new(mountPos) * (fromCF - fromCF.Position)
	animate(0.55, function(a)
		camera.CFrame = kitCam:Lerp(camFrom, a)
		local p = fromCF.Position:Lerp(mountPos, a) + Vector3.new(0, math.sin(a * math.pi) * 2.2, 0)
		local cf = CFrame.new(p) * (fromCF - fromCF.Position)
		for part, o in offs do part.CFrame = cf * o end
	end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for part, o in offs do part.CFrame = mountCF * o end
	camera.CFrame = camFrom
	sfx(SFX.Tap, 0.9, 0.7)
	sparkle(mountPos)
	for _ = 1, 3 do
		puff((m:GetPivot() * CFrame.new(-2.6, 0.6, 0)).Position, Color3.fromRGB(80, 200, 255), 8)
		task.wait(0.1)
	end
	-- a fresh empty bottle is back in the kit's cradles
	for _, p in source:GetDescendants() do
		if p:IsA("BasePart") then p.Transparency = 0 end
	end
end

-- Rusty handlebar, in the wash bay (the bucket stands there): Minigames.rust. Tap the
-- bucket, scrub the rust with the sponge (thick foam where you rub), then rinse the
-- foam off with the lance. A muddy job is washed first and stays in the bay for this.
FIX.Rust = function(m, step)
	local bay = myStations:WaitForChild("WashBay")
	local parts, clean = {}, {}
	for p, o in orig do
		if p.Parent == m and p.Material == Enum.Material.CorrodedMetal then
			table.insert(parts, p)
			clean[p] = o
		end
	end
	local off = m:GetPivot().Position - bay.ScooterSpot.Position
	local inBay = Vector3.new(off.X, 0, off.Z).Magnitude < 1.5
	if #parts > 0 then
		local level = player:GetAttribute("Bucket") or 1
		local bayLevel = player:GetAttribute("WashBay") or 1
		local scrubMul = SHOP.Bucket and SHOP.Bucket.Scrub and SHOP.Bucket.Scrub[level] or 1
		local jetMul = (SHOP.WashBay and SHOP.WashBay.Jet and SHOP.WashBay.Jet[bayLevel] or 1) * (player:GetAttribute("TurboLance") == 1 and Config.Caro.Boost.TurboLance or 1)
		if not inBay then
			setInstruction("Off to the wash bay...", step)
			Config.Mini.crane(bay, m)
			inBay = true
		end
		Config.Mini.rust(bay, m, { step = step, parts = parts, clean = clean, scrubMul = scrubMul, jetMul = jetMul, bucket = myStations:WaitForChild("Bucket"), tap = tapOn })
	end
	if inBay then
		setInstruction("Back to the bench...", step)
		Config.Mini.crane(bay, m, { to = SPOT })
		local back = camera.CFrame
		animate(0.6, function(a) camera.CFrame = back:Lerp(REPAIR_CAM, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		camera.CFrame = REPAIR_CAM
	end
end

-- Muddy scooter, in the wash bay (front-right). The crane takes it in, you wash it
-- (Minigames.wash: the jet takes the mud off exactly where you point, and it's only
-- done when it's clean all over), and the crane brings it back to the bench.
FIX.Mud = function(m, step)
	local bay = myStations:WaitForChild("WashBay")
	local item = SHOP.WashBay
	local level = player:GetAttribute("WashBay") or 1
	local jetMul = (item and item.Jet and item.Jet[level] or 1) * (player:GetAttribute("TurboLance") == 1 and Config.Caro.Boost.TurboLance or 1)
	setInstruction("Off to the wash bay...", step)
	Config.Mini.crane(bay, m)
	local camAt = camera.CFrame
	animate(0.6, function(a) camera.CFrame = camAt:Lerp(bay.BoothCam.CFrame, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Config.Mini.wash(bay, m, step, jetMul)
	if active and active.job.Problems[step + 1] == "Rust" then return end -- rust is done in the bay too
	setInstruction("Back to the bench...", step)
	Config.Mini.crane(bay, m, { to = SPOT })
	local back = camera.CFrame
	animate(0.6, function(a) camera.CFrame = back:Lerp(REPAIR_CAM, a) end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	camera.CFrame = REPAIR_CAM
end

---------------------------------------------------------------- job card + timer
local rows = {}
-- Scooter looks and moves that aren't a fix:
--   wear(m, amount): weathered on arrival (grimy, faded panels), 0-1; only the wash takes it off
--   polish(m): a shine sweeps over it once every fix is done (changes nothing)
--   escort(c, m): the customer pushes the scooter beside them; returns a stop function
local SCOOTER_FX = {}
do
	local worn = setmetatable({}, { __mode = "k" }) -- [model] = { [part] = { Color, Material } }
	local GRIME = Color3.fromRGB(105, 92, 78)
	function SCOOTER_FX.wear(m, amount)
		amount = math.clamp(amount or 0.4, 0, 1)
		local saved = {}
		for _, p in m:GetChildren() do
			if not p:IsA("BasePart") or p.Transparency >= 1 then continue end
			-- grime only: rust is its own job (Rust), so it never shows up where no fix will clean it
			if BODY_PARTS[p.Name] or p.Name == "Seat" then
				-- faded and grimy, more so the worse it's been treated
				saved[p] = { p.Color, p.Material }
				p.Color = p.Color:Lerp(GRIME, 0.12 + amount * 0.3 + math.random() * 0.08)
			end
		end
		worn[m] = saved
	end
	function SCOOTER_FX.polish(m)
		-- a shine sweeps from the back of the scooter to the front. It changes nothing:
		-- a job only fixes what it fixes (the grime stays unless it went through the wash)
		worn[m] = nil
		local list = {}
		local pivot = m:GetPivot()
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				table.insert(list, { part = p, x = pivot:PointToObjectSpace(p.Position).X })
			end
		end
		table.sort(list, function(a, b) return a.x < b.x end)
		sfx(SFX.Done, 0.5, 1.6)
		for i, e in list do
			if i % 4 == 1 then sparkle(e.part.Position) end
			if i % 6 == 0 then task.wait(0.03) end
		end
	end
	-- the wash takes the grime off a panel: its clean colour (polish then leaves it be)
	function SCOOTER_FX.unwear(m, p)
		local saved = worn[m] and worn[m][p]
		if not saved or p.Material ~= saved[2] then return nil end
		worn[m][p] = nil
		return saved[1]
	end
	-- every customer gets their own look: skin, shirt, trousers, shoes, something on
	-- their head (helmet, cap, beanie, hair) and sometimes a backpack
	local rgb = Color3.fromRGB
	local SKIN = { rgb(255, 224, 189), rgb(241, 194, 125), rgb(224, 172, 105), rgb(198, 134, 66), rgb(141, 85, 36), rgb(92, 58, 32) }
	local SHIRT = { rgb(225, 60, 72), rgb(90, 170, 250), rgb(255, 212, 70), rgb(120, 220, 190), rgb(185, 150, 240), rgb(255, 145, 55), rgb(245, 245, 245), rgb(40, 44, 56), rgb(60, 135, 85), rgb(255, 140, 190) }
	local PANTS = { rgb(52, 78, 140), rgb(35, 38, 46), rgb(190, 165, 120), rgb(110, 115, 125), rgb(70, 95, 60), rgb(150, 40, 45) }
	local SHOES = { rgb(30, 30, 34), rgb(240, 240, 240), rgb(120, 70, 40), rgb(225, 60, 72) }
	local HAIR = { rgb(30, 22, 18), rgb(90, 55, 30), rgb(200, 150, 70), rgb(240, 210, 130), rgb(160, 60, 40), rgb(120, 120, 128) }
	local function pick(t) return t[math.random(#t)] end
	local function blob(parent, name, size, cf, color, sphere, mat)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = sphere and Vector3.new(1, 1, 1) or size
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if sphere then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = size
			mesh.Parent = p
		end
		p.CFrame = cf
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = parent, p
		w.Parent = p
		p.Parent = parent.Parent
		return p
	end
	function SCOOTER_FX.dress(model)
		local bc = model:FindFirstChildOfClass("BodyColors")
		if bc then bc:Destroy() end
		local skin, shirt, pants, shoes = pick(SKIN), pick(SHIRT), pick(PANTS), pick(SHOES)
		local longSleeves = math.random() < 0.5
		local paint = {
			Head = skin, LeftHand = skin, RightHand = skin,
			UpperTorso = shirt, LeftUpperArm = shirt, RightUpperArm = shirt,
			LeftLowerArm = longSleeves and shirt or skin, RightLowerArm = longSleeves and shirt or skin,
			LowerTorso = pants, LeftUpperLeg = pants, RightUpperLeg = pants, LeftLowerLeg = pants, RightLowerLeg = pants,
			LeftFoot = shoes, RightFoot = shoes,
		}
		for name, col in paint do
			local p = model:FindFirstChild(name)
			if p then p.Color = col end
		end
		local head = model:FindFirstChild("Head")
		if not head then return end
		if not head:FindFirstChildOfClass("Decal") then
			local face = Instance.new("Decal")
			face.Name = "face"
			face.Texture = "rbxasset://textures/face.png"
			face.Face = Enum.NormalId.Front
			face.Parent = head
		end
		local top = head.CFrame * CFrame.new(0, head.Size.Y * 0.18, 0)
		local style = math.random(5)
		if style == 1 then
			-- scooter helmet with a visor
			local col = pick(SHIRT)
			blob(head, "Helmet", Vector3.new(1.45, 1.25, 1.45), top, col, true)
			blob(head, "Visor", Vector3.new(1.05, 0.12, 0.3), head.CFrame * CFrame.new(0, head.Size.Y * 0.32, -head.Size.Z * 0.62), rgb(40, 44, 56))
		elseif style == 2 then
			-- cap with a brim
			local col = pick(SHIRT)
			blob(head, "Cap", Vector3.new(1.3, 0.75, 1.3), top * CFrame.new(0, 0.12, 0), col, true)
			blob(head, "Brim", Vector3.new(0.95, 0.08, 0.6), head.CFrame * CFrame.new(0, head.Size.Y * 0.36, -head.Size.Z * 0.62), col)
		elseif style == 3 then
			-- beanie with a folded band
			local col = pick(SHIRT)
			blob(head, "Beanie", Vector3.new(1.32, 1.0, 1.32), top * CFrame.new(0, 0.08, 0), col, true)
			blob(head, "Band", Vector3.new(1.4, 0.32, 1.4), head.CFrame * CFrame.new(0, head.Size.Y * 0.22, 0), col:Lerp(rgb(255, 255, 255), 0.25), true)
		elseif style == 4 then
			-- hair: a mop on top and down the back
			local col = pick(HAIR)
			blob(head, "Hair", Vector3.new(1.32, 0.8, 1.32), top * CFrame.new(0, 0.12, 0.05), col, true)
			blob(head, "HairBack", Vector3.new(1.25, 0.85, 0.5), head.CFrame * CFrame.new(0, 0.05, head.Size.Z * 0.42), col, true)
		end -- style 5: nothing on their head
		local torso = model:FindFirstChild("UpperTorso")
		if torso and math.random() < 0.3 then
			blob(torso, "Backpack", Vector3.new(1.3, 1.3, 0.55), torso.CFrame * CFrame.new(0, 0, torso.Size.Z / 2 + 0.28), pick(SHIRT))
		end
	end

	function SCOOTER_FX.escort(c, m)
		local root = c.model:FindFirstChild("HumanoidRootPart")
		local hum = c.model:FindFirstChildOfClass("Humanoid")
		if not root then return function() end end
		-- wheels turn with the distance travelled
		local wheels = {}
		local pivot0 = m:GetPivot()
		for _, n in { "Front", "Rear" } do
			local tyre = m:FindFirstChild("Tyre" .. n)
			if tyre then
				local centre = pivot0:PointToObjectSpace(tyre.Position)
				local r = math.max(tyre.Size.X, tyre.Size.Y, tyre.Size.Z) / 2
				for _, part in m:GetChildren() do
					if part:IsA("BasePart") and (part.Name == "Tyre" .. n or part.Name == "Tyre" .. n .. "Hub" or part.Name == "TyreWorn" and n == "Rear" or part.Name == "TyreFlat" and n == "Front") then
						table.insert(wheels, { part = part, centre = centre, r = r, off = pivot0:ToObjectSpace(part.CFrame) })
					end
				end
			end
		end
		local travelled, last = 0, nil
		-- how far their feet are below the root (measured: rigs differ)
		local footDrop = (hum and hum.HipHeight or 2) + root.Size.Y / 2
		do
			local lowest = math.huge
			for _, p in c.model:GetDescendants() do
				if p:IsA("BasePart") and p ~= root then lowest = math.min(lowest, p.Position.Y - p.Size.Y / 2) end
			end
			if lowest < math.huge then footDrop = root.Position.Y - lowest end
		end
		local conn = RunService.RenderStepped:Connect(function()
			if not (root.Parent and m.Parent) then return end
			local look = root.CFrame.LookVector
			look = Vector3.new(look.X, 0, look.Z)
			if look.Magnitude < 1e-3 then return end
			look = look.Unit
			local right = look:Cross(Vector3.yAxis)
			-- beside them on their right, a little ahead, wheels on the ground
			local at = root.Position + right * 1.5 + look * 0.5
			at = Vector3.new(at.X, root.Position.Y - footDrop, at.Z)
			local cf = CFrame.fromMatrix(at, look, Vector3.yAxis)
			if last then travelled += (Vector3.new(at.X, 0, at.Z) - Vector3.new(last.X, 0, last.Z)).Magnitude end
			last = at
			m:PivotTo(cf)
			for _, w in wheels do
				w.part.CFrame = cf * CFrame.new(w.centre) * CFrame.Angles(0, 0, -travelled / w.r) * CFrame.new(w.centre):Inverse() * w.off
			end
		end)
		return function()
			conn:Disconnect()
			-- wheels back to their resting angle
			local cf = m:GetPivot()
			for _, w in wheels do w.part.CFrame = cf * w.off end
		end
	end
end

Config.Mini.init({
	P = Config.P, sfx = sfx, SFX = SFX, puff = puff, sparkle = sparkle, setInstruction = setInstruction,
	input = function() return pointer, holding and state == "repair" end,
	press = function()
		local p = pendingPress
		pendingPress = nil
		return state == "repair" and p or nil
	end,
	cleanColor = function(m, p) return SCOOTER_FX.unwear(m, p) or (orig[p] and orig[p].Color) or p.Color end,
	Config = Config, getRig = getRig, hideSelf = hideSelf, glow = glow, unglow = unglow, setBar = setBar,
})

ui.jobCount = function()
	local done, all = 0, 0
	for _, r in rows do
		all += 1
		if r:GetAttribute("Done") then done += 1 end
	end
	ui.job.Head.Count.Text = done .. "/" .. all
end
local function buildJobCard(job)
	for _, r in rows do r:Destroy() end
	table.clear(rows)
	local r = RARITY[job.Rarity] or Config.Rarities[1]
	-- the work-order ticket (ShopTicketKit.reskinJob): name, done count, rarity / pay / mood chips
	local head = ui.job.Head
	head.Tab.Title.Text = job.First and "Your scooter" or job.Story or (job.Paint and (job.Paint .. " " .. job.Scooter) or job.Scooter)
	head.Info.Rarity.Visible = not job.First
	head.Info.Rarity.Label.Text = r.Name:upper()
	head.Info.Rarity.Gloss.Color = ui.style.glossColors(r.Color)
	head.Tab.Gloss.Color = ui.style.glossColors(job.First and ui.style.Color.Sky or r.Color)
	head.Info.Pay.Amount.Text = "$" .. ui.style.money(job.Pay)
	head.Info.Mood.Visible = job.Mood ~= nil
	head.Info.Mood.Label.Text = job.Mood and job.Mood:upper() or ""
	for i, name in job.Problems do
		local r = ui.job.RowTemplate:Clone()
		r.Name = name
		r.LayoutOrder = 10 + i
		r.Text.Text = Config.Problems[name].Label .. (name == "Paint" and job.PaintTo and (": " .. job.PaintTo) or "")
		r.Visible = true
		r.Parent = ui.job
		rows[name] = r
	end
	-- the speed tip chip (Fever loop): a bonus that melts away while the job runs long
	local tipChip = head.Info:FindFirstChild("TipChip")
	if not tipChip then
		tipChip = Instance.new("TextLabel")
		tipChip.Name = "TipChip"
		tipChip.BackgroundTransparency = 1
		tipChip.Size = UDim2.new(0, 0, 0, 18)
		tipChip.AutomaticSize = Enum.AutomaticSize.X
		tipChip.FontFace = ui.style.Font.Chunky
		tipChip.TextSize = 14
		tipChip.TextColor3 = GREEN
		tipChip.LayoutOrder = 5
		tipChip.Parent = head.Info
	end
	tipChip.Visible = not job.First
	ui.tipChip = tipChip
	ui.jobCount()
end
-- a row ticked off on the job card (pop = the little bounce when it's just been done)
local function markRow(name, pop)
	local r = rows[name]
	if not r then return end
	r:SetAttribute("Done", true)
	r.BackgroundColor3 = ui.style.tone(GREEN, -0.3)
	r.Box.Tick.Visible = true
	r.Text.TextColor3 = Color3.new(1, 1, 1)
	if pop then popScale(r.Box, 0.4, 0.3) end
	ui.jobCount()
end
-- a fix finished: the session remembers it (so the next fix comes up) and the card ticks it off
local function tick(sess, name)
	if sess then sess.done[name] = true end
	markRow(name, true)
	ui.moments.cheer(sess and sess.customer)
end

local function starsFor(par, elapsed)
	local stars = 5
	for _, s in Config.StarSteps do
		if elapsed > par * s then stars -= 1 end
	end
	return math.max(1, stars)
end

local function setStars(row, n)
	for i = 1, 5 do
		local s = row["S" .. i]
		-- the owner's star image (pay screen and job timer), tinted dark until earned
		if s:IsA("ImageLabel") then s.ImageColor3 = i <= n and Color3.new(1, 1, 1) or ui.style.Color.StarOff else s.TextColor3 = i <= n and TAN or DIM end
	end
end

local shownStars = 5
-- The par bar (Fever loop): a thin race strip under the stars — elapsed against the job's
-- worst star step, coloured by the speed tip so you can see the bonus melting in real time.
local parBarFill
parBarFill = (function()
	local timer = gui:FindFirstChild("Timer")
	if not timer then return nil end
	-- a centred track under the clock with the fill inside: tidy, never edge-to-edge
	local track = Instance.new("Frame")
	track.Name = "ParBar"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -4)
	track.Size = UDim2.new(0.72, 0, 0, 5)
	track.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
	track.BorderSizePixel = 0
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 3)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)
	fill.Parent = track
	track.Parent = timer
	return fill
end)()

RunService.RenderStepped:Connect(function()
	if not active or active.stopped then return end
	local elapsed = os.clock() - active.started
	ui.timer.Clock.Text = ("%d:%02d"):format(elapsed // 60, elapsed % 60)
	-- the speed tip readout (Fever loop): full at par, gone by Gone x par
	if parBarFill and active.job.Par then
		local steps = Config.StarSteps or { 2.4 }
		local frac = math.clamp(elapsed / (active.job.Par * steps[#steps]), 0, 1)
		parBarFill.Size = UDim2.fromScale(frac, 1)
		local ST = Config.SpeedTip or { TillPar = 1.0, Gone = 2.5 }
		local tipF = math.clamp(1 - (elapsed / math.max(active.job.Par, 1) - ST.TillPar) / (ST.Gone - ST.TillPar), 0, 1)
		parBarFill.BackgroundColor3 = tipF > 0.5 and GREEN or tipF > 0 and TAN or RED
	end
	local chip = ui.tipChip
	if chip and chip.Parent then
		local ST = Config.SpeedTip or { Max = 0.2, TillPar = 1.0, Gone = 2.5 }
		local f = math.clamp(1 - (elapsed / math.max(active.job.Par, 1) - ST.TillPar) / (ST.Gone - ST.TillPar), 0, 1)
		-- the same sum FinishJob makes: the tip is on what's still owed (the per-fix advances are paid already)
		local owed = math.max(0, math.floor(active.job.Pay * benchPay()) - (active.advanced or 0))
		chip.Text = f > 0 and ("TIP +$" .. ui.style.money(math.floor(owed * ST.Max * f))) or "NO TIP"
		chip.TextColor3 = f > 0.5 and GREEN or f > 0 and TAN or RED
	end
	local n = starsFor(active.job.Par, elapsed)
	if n ~= shownStars then
		shownStars = n
		setStars(ui.timer.Stars, n)
		sfx(SFX.Tap, 0.6, 0.45)
		local lost = ui.timer.Stars["S" .. (n + 1)]
		if lost then
			lost.Rotation = 25
			TweenService:Create(lost, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
		end
	end
end)

-- Keep the bench view if the default camera script grabs it back (e.g. on spawn).
RunService.RenderStepped:Connect(function()
	if (state == "repair" or state == "results") and not awayFromBench and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = REPAIR_CAM
		camera.FieldOfView = 60
	end
end)

---------------------------------------------------------------- repair flow
local function showLobbyUI(on)
	ui.shopBtn.Visible = on
	ui.hud.lobby(on)
	if not on then ui.shop.Visible = false end
end

local function enterBench()
	freeze(true)
	hideSelf(true)
	showLobbyUI(false)
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = REPAIR_CAM, FieldOfView = 60 }):Play()
end

local function leaveBench()
	state = "leaving"
	ui.ins.Visible = false
	ui.job.Visible = false
	ui.timer.Visible = false
	ui.pay.Visible = false
	hideSelf(false)
	-- glide back to the usual follow camera instead of snapping
	local _, _, hrp = getRig()
	if hrp then
		local behind = hrp.CFrame * CFrame.new(0, 4, 11)
		local tw = TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			CFrame = CFrame.lookAt(behind.Position, hrp.Position + Vector3.new(0, 1.5, 0)),
			FieldOfView = 70,
		})
		tw:Play()
		tw.Completed:Wait()
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	freeze(false)
	state = "idle"
	refreshStations() -- machines bought at night appear now that the bench is free
	showLobbyUI(true)
end

local RESULT_TITLES = { "DONE", "OKAY", "GOOD!", "GREAT!", "PERFECT!" }
local onRepairDone -- set by the customers section
local finishJob -- hand the scooter back (the customers section)

-- Paper bills fly from a screen point to the cash counter (owner, 24 Oct: green paper cash, not coins).
local function coinsTo(fromAbs, count)
	-- screen px -> FixUI's own space (it has safe-area insets and a Fit UIScale)
	local fit = gui:FindFirstChild("Fit")
	local k = fit and fit.Scale or 1
	local function local2(abs) return (abs - gui.AbsolutePosition) / k end
	fromAbs = local2(fromAbs)
	local target = local2(gui.Cash.AbsolutePosition + gui.Cash.AbsoluteSize * Vector2.new(0.2, 0.5))
	for i = 1, count do
		local coin = Instance.new("Frame")
		coin.Size = UDim2.fromOffset(40, 22)
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.BackgroundColor3 = Color3.fromRGB(96, 176, 92)
		coin.Position = UDim2.fromOffset(fromAbs.X + math.random(-30, 30), fromAbs.Y + math.random(-15, 15))
		coin.Rotation = math.random(-25, 25)
		coin.ZIndex = 20
		Instance.new("UICorner", coin).CornerRadius = UDim.new(0, 3)
		local s = Instance.new("UIStroke", coin)
		s.Color = Color3.fromRGB(18, 19, 25)
		s.Thickness = 2
		-- the printed face: a pale band inside the edge and a round seal with the $
		local face = Instance.new("Frame")
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		face.Position = UDim2.fromScale(0.5, 0.5)
		face.Size = UDim2.new(1, -6, 1, -6)
		face.BackgroundColor3 = Color3.fromRGB(150, 214, 136)
		face.ZIndex = 21
		Instance.new("UICorner", face).CornerRadius = UDim.new(0, 2)
		face.Parent = coin
		local ink = Instance.new("Frame")
		ink.AnchorPoint = Vector2.new(0.5, 0.5)
		ink.Position = UDim2.fromScale(0.5, 0.5)
		ink.Size = UDim2.new(1, -6, 1, -6)
		ink.BackgroundColor3 = Color3.fromRGB(96, 176, 92)
		ink.ZIndex = 22
		ink.Parent = face
		local seal = Instance.new("TextLabel")
		seal.AnchorPoint = Vector2.new(0.5, 0.5)
		seal.Position = UDim2.fromScale(0.5, 0.5)
		seal.Size = UDim2.new(0, 14, 1, 2)
		seal.BackgroundColor3 = Color3.fromRGB(150, 214, 136)
		seal.Text = "$"
		seal.TextColor3 = Color3.fromRGB(30, 86, 40)
		seal.FontFace = ui.style.Font.Chunky
		seal.TextScaled = true
		seal.ZIndex = 23
		Instance.new("UICorner", seal).CornerRadius = UDim.new(1, 0)
		seal.Parent = ink
		coin.Parent = gui
		task.delay(i * 0.06, function()
			local tw = TweenService:Create(coin, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(22, 12), Rotation = coin.Rotation + math.random(-200, 200) })
			tw:Play()
			tw.Completed:Wait()
			coin:Destroy()
			sfx(SFX.Tap, 0.25, 1.6 + i * 0.03)
		end)
	end
end

-- A fix's pay is quick now (owner, 24 Oct: "every fix = a star screen that takes time"): one line and the
-- coins fly from the scooter to your cash. The stars come all together on the day card at night.
-- (plan/13: the pay itself is left at the window by the owner, see handOver: this is just the verdict)
local function quickPay(r)
	if not r then return end
	local title = r.WrongPaint and "WRONG COLOUR" or RESULT_TITLES[r.Stars]
	popText(title .. "  " .. string.rep("★", r.Stars), 0.75, 1.4, r.Stars >= 4 and GREEN or nil)
	sfx(SFX.Done, 0.8, r.Stars >= 4 and 1.3 or 1)
	if r.Stars >= 4 then shake(0.25, 0.2) elseif r.Stars <= 2 then shake(0.15, 0.12) end
end

-- Fever parallel bench (plan/12): sessions round-robin at fix boundaries. Park a half-done
-- job back on the belt (its clock keeps running!), work another, switch back. How many can be
-- in flight at once comes from the bench tier (Config.ParallelBench).
-- The next fix on this session. A low battery goes on charge first (once the wash bay is done with it) so
-- it fills while the other fixes are done; fixes left running in the background (sess.bg) are skipped
-- until nothing else is left, and a battery still charging finishes before the booth takes the scooter.
local function nextProblem(sess)
	local bg = sess.bg or {}
	local problems = sess.job.Problems
	local charge = table.find(problems, "Charge")
	if Config.ChargeInBackground and charge and not sess.done.Charge and not bg.Charge then
		local washing = (table.find(problems, "Mud") and not sess.done.Mud) or (table.find(problems, "Rust") and not sess.done.Rust)
		if not washing then return "Charge", charge end
	end
	for i, name in problems do
		if not sess.done[name] and not bg[name] then
			if name == "Paint" and bg.Charge then return "Charge", charge end
			return name, i
		end
	end
	for i, name in problems do
		if not sess.done[name] then return name, i end
	end
end

-- A battery charging in the background stops when its scooter leaves the bench: the plug goes home and
-- the charge so far is kept (sess.chargeLevel); back on the bench it's plugged in again from there.
local function stopCharging(sess)
	while sess.charging and sess.charging.finishing do task.wait() end -- full right now: let it finish and pay
	local ch = sess.charging
	if not ch then return end
	ch.stopBackground()
	sess.chargeLevel = ch.charge
	sess.charging = nil
	if sess.bg then sess.bg.Charge = nil end
	ch.unplug()
end

-- A finished fix pays on the spot (StepDone): coins fly to the counter, and the same fix as the last one
-- (on any job) is a chain that pays a growing bonus (Config.Chain).
local function payStep(sess, name)
	local advance, bonus, chain = 0, 0, 1
	do
		local ok, a, b, c = pcall(function() return Remotes.StepDone:InvokeServer(name) end)
		if ok and type(a) == "number" then advance, bonus, chain = a, tonumber(b) or 0, tonumber(c) or 1 end
	end
	sess.advanced = (sess.advanced or 0) + advance -- the TIP chip's sum (the chain bonus is extra)
	if advance > 0 and sess.model and sess.model.Parent then
		local sp = camera:WorldToViewportPoint(sess.model:GetPivot().Position)
		coinsTo(Vector2.new(sp.X, sp.Y), 4 + math.min(chain - 1, 4) * 2)
	end
	if chain >= 2 and bonus > 0 then
		popText(("CHAIN x%d!  +$%d"):format(chain, advance + bonus), 0.6 + math.min(chain, 5) * 0.04, 0.9, ui.style.Color.Gold)
		sfx(SFX.Done, 0.6, 1 + math.min(chain, 6) * 0.1)
		shake(0.1 + math.min(chain, 5) * 0.03, 0.15)
	else
		popText(("+$%d"):format(advance > 0 and advance or Config.Problems[name].Pay), 0.55, 0.6, GREEN)
		sfx(SFX.Done, 0.5)
	end
end

-- a battery that filled in the background while another fix was going on: tick it off and pay it
onBackgroundFix = function(sess, name)
	if sess.done[name] then return end
	if active == sess then tick(sess, name) else sess.done[name] = true end
	Config.Fun.fixed(sess.customer)
	payStep(sess, name)
end

local function beltSlotCF(i)
	local s0 = Config.P.toLocal(SPOT.Position)
	return Config.P.PF * CFrame.new(QUEUE_X[i] or QUEUE_X[#QUEUE_X], s0.Y, s0.Z)
end

local function park(sess)
	stopCharging(sess) -- before it slides away (the plug can't follow it down the belt)
	parked[sess.job.Id] = sess
	sess.skill = ui.skill.save() -- its perfects, misses and combo wait with it
	if sess.slotIndex then
		sess.slotCF = beltSlotCF(sess.slotIndex)
		if sess.model and sess.model.Parent then slideModel(sess.model, sess.slotCF, 1.2, nil, true) end
	end
	-- a prompt on the parked scooter: tap it to work on this one after the current fix
	local old = sess.model and sess.model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if old then old:Destroy() end
	if sess.model and sess.model.Parent then
		local p = Instance.new("ProximityPrompt")
		p.Name = "PickPrompt"
		p.ActionText = "Work on this one"
		p.ObjectText = sess.job.Story or sess.job.Scooter
		p.HoldDuration = 0
		p.MaxActivationDistance = 8
		p.RequiresLineOfSight = false
		p.Parent = sess.model:FindFirstChild("Deck") or sess.model:FindFirstChildWhichIsA("BasePart")
		p.Triggered:Connect(function()
			if state == "repair" and switchTo == nil and active ~= sess then
				switchTo = sess
				popText("Switching after this fix...", 0.55, 1.2, TAN)
			end
		end)
	end
end

local function unpark(sess)
	parked[sess.job.Id] = nil
	local old = sess.model and sess.model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if old then old:Destroy() end
	if sess.model and sess.model.Parent then
		slideModel(sess.model, SPOT, 1.3, nil, true)
		settle(sess.model)
	end
end

local function switchCard(sess)
	active = sess
	pcall(function() Remotes.SwitchCurrent:InvokeServer(sess.job.Id) end)
	buildJobCard(sess.job)
	for name in sess.done do markRow(name, false) end -- the fixes it already had stay ticked
	ui.skill.load(sess.skill) -- a fresh job starts from zero, a parked one picks up where it was
	sess.skill = nil
	shownStars = 5
	setStars(ui.timer.Stars, 5)
	state = "repair"
end

local function runSessions(cur)
	while cur do
		active = cur
		local name, idx = nextProblem(cur)
		if name and not cur.stopped then
			-- a step boundary: honour a parked switch or a fresh belt pick before the next fix
			if switchTo and switchTo ~= cur then
				local nxt = switchTo
				switchTo = nil
				park(cur)
				switchCard(nxt)
				unpark(nxt)
				cur = nxt
			elseif pendingPickId then
				local id = pendingPickId
				pendingPickId = nil
				local picked, newQueue = startSession(id)
				if picked then
					park(cur)
					switchCard(picked)
					cur = picked
				end
			else
				local m = cur.model
				loadOrig(m)
				-- a broken minigame must never freeze the job: log it and carry on
				local ok, err = pcall(FIX[name], m, idx)
				local outOfStock = not ok and tostring(err):find("OUT_OF_STOCK") ~= nil
				if not ok then
					if not outOfStock then warn(("Fix %s failed: %s"):format(name, tostring(err))) end
					unglow()
					setBar(nil)
					ui.gauge.Visible = false
					ui.wires.Visible = false
					for _, n in { "WireBox", "SpinGuide", "PaintMist", "PaintHover", "GradeAnchor" } do
						local left = workspace:FindFirstChild(n)
						if left then left:Destroy() end
					end
					for _, n in { "PaintKit", "PaintGrade" } do
						local left = player.PlayerGui:FindFirstChild(n)
						if left then left:Destroy() end
					end
					for _, n in { "PaintSplat" } do
						local left = workspace.Terrain:FindFirstChild(n)
						if left then left:Destroy() end
					end
					if m:FindFirstChild("RustFoam") then m.RustFoam:Destroy() end
					-- a fix that took it off the bench (the wash bay) puts it back
					if name ~= "Paint" and m.Parent and (m:GetPivot().Position - SPOT.Position).Magnitude > 0.5 then m:PivotTo(SPOT) end
					if not awayFromBench then camera.CFrame = REPAIR_CAM end
					if awayFromBench then
						awayFromBench = false
						local _, hum, hrp = getRig()
						if hum then
							for _, c in hum:GetChildren() do
								if c:IsA("IKControl") then c:Destroy() end
							end
						end
						if hrp then hrp.Anchored = false end
						hideSelf(true)
						freeze(true)
						camera.CameraType = Enum.CameraType.Scriptable
						camera.CFrame = REPAIR_CAM
						camera.FieldOfView = 60
					end
				end
				if outOfStock then
					-- the restock card ran out: the customer takes it home unfixed (no pay, no review)
					stopCharging(cur)
					cur.stopped = true
					cur.dropped = true
					ui.ins.Visible = false
					state = "results"
					finishJob()
				elseif ok and err == "background" then
					-- left running (a battery on charge): the next fix comes up straight away
					cur.bg = cur.bg or {}
					cur.bg[name] = true
				elseif not cur.done[name] then -- (a background fix may have ticked itself off already)
					tick(cur, name)
					Config.Fun.fixed(cur.customer)
					payStep(cur, name) -- every fix pays the moment it's done (Fever loop)
					task.wait(0.3)
				end
			end
		else
			-- every fix on this one is done: pay, hand it back, then the next parked job
			if not cur.stopped then
				cur.stopped = true
				if onRepairDone then onRepairDone() end
				ui.ins.Visible = false
				-- good as new (a fresh paint job keeps its new colour)
				SCOOTER_FX.polish(cur.model, table.find(cur.job.Problems, "Paint") ~= nil)
				sparkle(cur.model:GetPivot().Position + Vector3.new(0, 1.5, 0))
				local result = Remotes.FinishJob:InvokeServer(cur.job.Id, cur.paintQuality, ui.skill.report())
				state = "results"
				cur.result = result
				quickPay(result)
				-- a moment to take it for a test ride (not on wet paint); otherwise straight on
				local chip = gui:FindFirstChild("RideChip")
				if chip and result and not cur.painted then
					chip.Visible = true
					popScale(chip, 0.7, 0.2)
					local t0 = os.clock()
					while state == "results" and os.clock() - t0 < 2.6 do task.wait() end
					chip.Visible = false
				else
					task.wait(0.6)
				end
				if state == "results" then finishJob() end
			end
			-- a test ride hands it back itself; a dropped job (out of stock) was handed back already, and
			-- the top of this loop pointed `active` at it again, so waiting on it would never end
			while active == cur and not cur.dropped do task.wait(0.1) end
			-- next parked job, or back to the street
			local nxtId, nxt = next(parked)
			if nxt then
				switchCard(nxt)
				unpark(nxt)
				cur = nxt
			else
				cur = nil
			end
		end
	end
	active = nil
	leaveBench()
end

---------------------------------------------------------------- customers
-- Each job has a customer outside the back window. They drop the scooter on the
-- conveyor and wait, getting angrier the longer it takes.
-- They only ever walk on the sidewalks: along the street lane, round the corner
-- to the belt on the left side, then back to the window.
local ARRIVE = garage:WaitForChild("CustomerArrive").CFrame
local CORNER = garage:WaitForChild("StreetCorner").CFrame
local HANDOVER = garage:WaitForChild("HandoverSpot").CFrame
local WAIT_SPOTS = {}
for i = 1, 4 do WAIT_SPOTS[i] = garage:WaitForChild("WaitSpot" .. i).CFrame end
local LANE_Z = Config.P.toLocal(CORNER.Position).Z
local SIDE_X = -31 -- left of this is the side sidewalk by the belt
local SIDEWALK_Y = 0.6
local function lane(x) return Config.P.PF * CFrame.new(x, 0, LANE_Z) end
local ANIM = {
	Walk = "rbxassetid://507777826",
	Idle = "rbxassetid://507766388",
	Wave = "rbxassetid://507770239",
	Cheer = "rbxassetid://507770677",
	Point = "rbxassetid://507770453",
}
local MOODS = { [0] = {}, {}, {}, {}, {} } -- 0 calm .. 4 furious; the bubble shows a face from 2 up
local customers = {} -- list of live customers

-- Fever rule (plan/12): the clock never stops. Customers keep arriving and their
-- patience keeps running while you fix, so the belt is always alive (Cooking Fever).
-- SetBusy stays for compatibility but pauses nothing (the server ignores it too).
local function pclock()
	return os.clock()
end
local function setBusy(_) end

local function playAnim(c, id, looped)
	local hum = c.model:FindFirstChildOfClass("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	if c.track then c.track:Stop(0.2) end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok then return end
	track.Looped = looped ~= false
	track:Play(0.2)
	c.track = track
end

local function say(c, text, color) ui.bubbles.say(c, text, color) end

-- Feet on the sidewalk at `cf` (customers are anchored and moved by hand).
local function standCF(c, cf)
	local hum = c.model.Humanoid
	local hrp = c.model.HumanoidRootPart
	local y = SIDEWALK_Y + hum.HipHeight + hrp.Size.Y / 2
	return CFrame.new(cf.Position.X, y, cf.Position.Z) * (cf - cf.Position)
end

-- Walk through `points` in order; only the last one sets which way they face.
local function walkPath(c, points)
	c.walking = true
	playAnim(c, ANIM.Walk)
	for i, cf in points do
		local from = c.model:GetPivot()
		local to = standCF(c, cf)
		local flat = Vector3.new(to.Position.X - from.Position.X, 0, to.Position.Z - from.Position.Z)
		local face = flat.Magnitude > 0.1 and CFrame.lookAt(Vector3.zero, flat) or (from - from.Position)
		local time = flat.Magnitude / Config.WalkSpeed
		if time > 0.05 then
			animate(time, function(a)
				c.model:PivotTo(CFrame.new(from.Position:Lerp(to.Position, a)) * face)
			end, Enum.EasingStyle.Linear)
		end
		if i == #points then
			c.model:PivotTo(to)
		else
			c.model:PivotTo(CFrame.new(to.Position) * face)
		end
	end
	c.base = c.model:GetPivot()
	c.walking = false
	playAnim(c, ANIM.Idle)
end

-- From wherever they stand, a route that stays on the sidewalks.
local function routeTo(c, cf)
	local here = Config.P.toLocal(c.model:GetPivot().Position)
	local there = Config.P.toLocal(cf.Position)
	local points = {}
	if here.X < SIDE_X and there.X >= SIDE_X then
		table.insert(points, CORNER)
		table.insert(points, lane(there.X))
	elseif here.X >= SIDE_X and there.X < SIDE_X then
		table.insert(points, lane(here.X))
		table.insert(points, CORNER)
	elseif here.X >= SIDE_X and math.abs(here.Z - there.Z) > 1 then
		-- along the street: step into the lane so nobody walks through the queue
		table.insert(points, lane(here.X))
		table.insert(points, lane(there.X))
	end
	table.insert(points, cf)
	walkPath(c, points)
end

local function newCustomer(startCF, seed)
	local pool = RS.Customers:GetChildren()
	if seed then math.randomseed(seed) end -- the same look as on everybody else's screen
	local c = { model = pool[math.random(#pool)]:Clone(), since = os.clock(), mood = 0 }
	SCOOTER_FX.dress(c.model)
	if seed then math.randomseed(os.time() + math.floor(os.clock() * 1000)) end
	outline(c.model)
	c.model.HumanoidRootPart.Anchored = true
	c.model:PivotTo(standCF(c, startCF or ARRIVE))
	c.base = c.model:GetPivot()
	c.model.Parent = workspace
	table.insert(customers, c)
	return c
end

local function removeCustomer(c)
	local i = table.find(customers, c)
	if i then table.remove(customers, i) end
	if c.model then c.model:Destroy() end
end

-- Customer walks off down the street: happy (cheer) or fed up (storms off).
local function customerLeaves(c, line, angry, scooter)
	c.done = true
	local t0 = os.clock()
	while c.walking and os.clock() - t0 < 12 do task.wait() end
	if angry then
		say(c, line or "😡", Color3.fromRGB(255, 90, 80))
		Config.Fun.stormed(c)
		playAnim(c, ANIM.Point, false)
		for _ = 1, 3 do
			puff(c.model.Head.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 120, 100), 5)
			task.wait(0.25)
		end
	else
		say(c, line or "😄")
		playAnim(c, ANIM.Cheer, false)
		task.wait(1.4)
	end
	say(c, nil)
	local stop = scooter and scooter.Parent and SCOOTER_FX.escort(c, scooter)
	routeTo(c, ARRIVE)
	if stop then stop() end
	if scooter then
		scooter:Destroy()
		origs[scooter] = nil
	end
	removeCustomer(c)
end

onRepairDone = function()
	local c = active and active.customer
	if not c then return end
	c.done = true
	if c.base then c.model:PivotTo(c.base) end
	say(c, "🎉")
	playAnim(c, ANIM.Cheer, false)
end

Config.Fun.init({
	customers = customers, say = say, playAnim = playAnim, ANIM = ANIM, MOODS = MOODS, Config = Config, P = Config.P,
	active = function() return active end,
})

-- Mood: the one whose scooter is on the bench follows your stars; the rest
-- get grumpy the longer they wait.
local moodClock = 0
RunService.RenderStepped:Connect(function(dt)
	moodClock += dt
	for _, c in customers do
		if not c.done and not c.walking then
			local mood
			if active and active.customer == c and not active.stopped then
				local elapsed = os.clock() - active.started
				local stars = 5
				for _, s in Config.StarSteps do
					if elapsed > active.job.Par * s then stars -= 1 end
				end
				mood = 5 - math.max(1, stars)
			elseif active and active.customer == c then
				mood = 0
			elseif c.expires then
				-- waiting in line: patience runs out, then they walk
				local left = (c.expires - pclock()) / c.patience
				mood = left > 0.65 and 0 or left > 0.4 and 1 or left > 0.2 and 2 or left > 0.08 and 3 or 4
			else
				mood = 0
			end
			if mood ~= c.mood then
				c.mood = mood
				if mood >= 3 then playAnim(c, ANIM.Point) elseif mood == 0 then playAnim(c, ANIM.Idle) end
			end
			-- angry: shake and hop, steam when furious
			if c.base then
				local t = os.clock()
				local shake = mood >= 2 and math.sin(t * (mood * 9)) * 0.08 * mood or 0
				local hop = mood >= 3 and math.max(0, math.sin(t * 7)) * 0.5 or 0
				c.model:PivotTo(c.base * CFrame.new(shake, hop, 0))
			end
			if mood >= 4 and moodClock > 0.6 then
				puff(c.model.Head.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 120, 100), 4)
			end
		end
	end
	if moodClock > 0.6 then moodClock = 0 end
end)

---------------------------------------------------------------- queue
local queued = {} -- [job id] = { job, model, customer }

-- The hatch flaps swing out of the way while a scooter rides through them,
-- in the direction it's going (in when it arrives, out when it's taken back).
do
	local hatch = garage:FindFirstChild("Hatch")
	local flaps = {}
	for _, f in hatch and hatch:GetChildren() or {} do
		if f:IsA("BasePart") and f.Name:match("^Flap") then
			table.insert(flaps, { part = f, home = f.CFrame, hinge = f.CFrame * CFrame.new(0, f.Size.Y / 2, 0), swing = 0, dir = 1 })
		end
	end
	local lastX = setmetatable({}, { __mode = "k" })
	RunService.RenderStepped:Connect(function(dt)
		if #flaps == 0 then return end
		local wallX = Config.P.toLocal(hatch.Frame.Position).X
		local near = {}
		for _, c in workspace:GetChildren() do
			if c:IsA("Model") and Templates:FindFirstChild(c.Name) then
				local p = Config.P.toLocal(c:GetPivot().Position)
				local moved = p.X - (lastX[c] or p.X)
				lastX[c] = p.X
				if math.abs(p.X - wallX) < 3.4 then table.insert(near, { pos = p, moved = moved }) end
			end
		end
		for _, f in flaps do
			local want = 0
			for _, s in near do
				if math.abs(s.pos.Z - Config.P.toLocal(f.home.Position).Z) < 1.4 then
					-- fully open while the scooter is under it, closing as it clears
					want = math.max(want, math.clamp((3.4 - math.abs(s.pos.X - wallX)) / 0.8, 0, 1))
					if s.moved ~= 0 then f.dir = s.moved > 0 and 1 or -1 end
				end
			end
			f.swing += (want - f.swing) * math.min(1, dt * 12)
			f.part.CFrame = f.hinge * CFrame.Angles(0, 0, f.swing * f.dir * math.rad(70)) * f.hinge:Inverse() * f.home
		end
	end)
end

-- Every scooter that comes in is painted in its colourway (Config.Paints, picked
-- by the server). Parts are coloured by name, so new model versions just work.
local prepScooter, paint
do
	local BODY = {
		Deck = true, DeckNose = true, DeckTail = true, Stem = true, RearFender = true, FrontFender = true, BatteryBay = true,
		HandGuardL = true, HandGuardR = true, BatteryBlock = true, -- Bolt X
	}
	local TRIM = {
		Handlebar = true, StemClamp = true, StemCollar = true, ForkL = true, ForkR = true, ForkCollarL = true, ForkCollarR = true,
		SwingArm = true, RearRack = true, FrontAxle = true, RearAxle = true, FenderBolt = true, LightRim = true, TailLightRim = true,
		Bolt1 = true, Bolt2 = true, Bolt3 = true,
		-- Bolt X
		ForkCrown = true, ForkLowerL = true, ForkLowerR = true, HeadCollar = true, SteerTube = true, RearShock = true, RearShockL = true,
		SwingArmL = true, LightRim2 = true, LightBar = true,
		-- kick scooters (Courier)
		Basket = true, BasketMount = true, PhoneMount = true,
	}
	-- rims, and Bolt X's springs in the same accent colour
	local RIMS = { TyreFrontHub = true, TyreRearHub = true, SpringL = true, SpringR = true, RearSpring = true, RearSpringL = true }
	local RUBBER = { TyreFront = true, TyreRear = true, Grip = true, DeckGrip = true }
	local FIXED = {
		Screen = Color3.fromRGB(30, 33, 42), Light = Color3.fromRGB(255, 245, 200), Light2 = Color3.fromRGB(255, 245, 200), TailLight = Color3.fromRGB(230, 50, 50),
		Battery = Color3.fromRGB(60, 63, 72), BatteryCap = Color3.fromRGB(240, 190, 60),
		DeckLight = Color3.fromRGB(255, 245, 200), Phone = Color3.fromRGB(40, 42, 50), PhoneScreen = Color3.fromRGB(70, 140, 245),
	}
	local PAINT = {}
	for _, p in Config.Paints do PAINT[p.Name] = p end
	-- Scooter models come straight from Blender: parts may sit in sub-models, be
	-- unanchored, face either way or carry export names ("Grip.001"). Tidy all of
	-- that when a scooter spawns, so a new version of a model can be dropped into
	-- ReplicatedStorage.Scooters without touching the code.
	prepScooter = function(m)
		if m:GetAttribute("BaseScale") == nil then m:SetAttribute("BaseScale", m:GetScale()) end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.Name = (d.Name:gsub("%.%d+$", ""))
				if d.Parent ~= m then d.Parent = m end
			elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
		for _, d in m:GetChildren() do
			if d:IsA("Model") and #d:GetChildren() == 0 then d:Destroy() end
		end
		-- the game expects the front wheel on +X (bench views, test ride)
		local front, rear = m:FindFirstChild("TyreFront"), m:FindFirstChild("TyreRear")
		if front and rear then
			local pivot = m:GetPivot()
			if pivot:PointToObjectSpace(front.Position).X < pivot:PointToObjectSpace(rear.Position).X then
				m.PrimaryPart = nil
				m.WorldPivot = pivot * CFrame.Angles(0, math.pi, 0)
			end
			if not m:GetAttribute("WheelD") then
				m:SetAttribute("WheelD", math.max(front.Size.X, front.Size.Y, front.Size.Z))
			end
		end
	end

	paint = function(m, job)
		local look = PAINT[job.Paint] or Config.Paints[1]
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				local n = p.Name
				if BODY[n] then
					p.Color = look.Body
					p.Material = look.Material or Enum.Material.SmoothPlastic
				elseif n == "Seat" then
					p.Color = look.Seat
				elseif TRIM[n] or RIMS[n] then
					p.Color = RIMS[n] and look.Rims or look.Trim
					p.Material = look.Glow and Enum.Material.Neon or (look.Material or Enum.Material.SmoothPlastic)
				elseif RUBBER[n] then
					p.Color = Config.Rubber
				elseif FIXED[n] then
					p.Color = FIXED[n]
				end
			end
		end
		-- rarer jobs sparkle so you spot them on the belt
		local r = RARITY[job.Rarity]
		if r and r.Index >= 3 then
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(r.Color)
			e.Size = NumberSequence.new(0.3, 0)
			e.Lifetime = NumberRange.new(0.5, 1)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Rate = r.Index * 2
			e.LightEmission = 1
			e.Parent = m.Deck
		end
	end
end

---------------------------------------------------------------- customer list (side)
-- One small tile per waiting customer: rarity stripe, scooter, fix count, patience bar (Hud shapes it).
local listRows = {}
local function updateList()
	local panel = gui:FindFirstChild("Customers")
	panel = panel and panel:FindFirstChild("Rows") -- Customers also holds the tuck tab (Hud)
	if not panel then return end
	local ids = {}
	for id, q in queued do
		if q.customer and not q.customer.done then ids[id] = q end
	end
	-- parked sessions (parallel bench): their customers still wait at the window
	for id, s in parked do
		if s.customer and not s.customer.done then ids["p" .. id] = { job = s.job, customer = s.customer, slotCF = s.slotCF } end
	end
	for id, row in listRows do
		if not ids[id] then
			listRows[id] = nil
			popScale(row, 1, 0.01)
			TweenService:Create(row.UIScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
			task.delay(0.2, function() row:Destroy() end)
		end
	end
	for id, q in ids do
		local row = listRows[id]
		if not row then
			row = panel.RowTemplate:Clone()
			row.Name = "Row"
			row:SetAttribute("JobId", id) -- the X on the card (Hud) sends this one away
			row.Visible = true
			local r = RARITY[q.job.Rarity] or Config.Rarities[1]
			row.Stripe.BackgroundColor3 = r.Color
			row.Title.Text = q.job.Paint and (q.job.Paint .. " " .. q.job.Scooter) or q.job.Scooter
			row.Pic.Image = ui.style.Icon[(q.job.Scooter:gsub(" ", ""))] or ""
			row.Info.Text = ("%d fix%s  $%d"):format(#q.job.Problems, #q.job.Problems == 1 and "" or "es", q.job.Pay)
			row:SetAttribute("Fixes", #q.job.Problems) -- the tile's badge (Hud)
			row.Parent = panel
			listRows[id] = row
			popScale(row, 0.6)
		end
		row.LayoutOrder = math.floor(-Config.P.toLocal(q.slotCF.Position).X * 10)
	end
end
RunService.RenderStepped:Connect(function()
	for id, row in listRows do
		local q = queued[id]
		local c = q and q.customer
		if c and c.expires then
			local left = math.clamp((c.expires - pclock()) / c.patience, 0, 1)
			row.Bar.Fill.Size = UDim2.fromScale(left, 1)
			row.Bar.Fill.BackgroundColor3 = left > 0.4 and GREEN or left > 0.2 and Color3.fromRGB(245, 190, 60) or RED
			-- running out: the card's outline flashes red
			row.UIStroke.Color = left < 0.2 and math.sin(os.clock() * 8) > 0 and RED or ui.style.Color.Ink
		end
	end
end)

local pickJob
local trashRun -- bag the bin and take it to the dumpster (with the closing chores below)

-- Fever agency (plan/12): every scooter on the belt is pickable, Cooking-Fever style —
-- walk up to the one you want (the biggest pay, or the one about to storm off) instead of
-- taking whatever the bench hands you. The bench prompt still fixes the nearest one.
local function beltPrompt(q)
	local m = q.model
	if not (m and m.Parent) then return end
	local old = m:FindFirstChild("PickPrompt")
	if old then old:Destroy() end
	local p = Instance.new("ProximityPrompt")
	p.Name = "PickPrompt"
	p.ActionText = ("Fix  $%d"):format(q.job.Pay)
	p.ObjectText = q.job.Paint and (q.job.Paint .. " " .. q.job.Scooter) or q.job.Scooter
	p.HoldDuration = 0
	p.MaxActivationDistance = 7
	p.RequiresLineOfSight = false
	p.Parent = m:FindFirstChild("Deck") or m:FindFirstChildWhichIsA("BasePart") -- prompts only show on a Part, never a Model
	p.Triggered:Connect(function()
		if state == "idle" then
			pickJob(q.job.Id)
		elseif state == "repair" and inFlight() < parallelCap() then
			-- parallel bench: line it up, it's grabbed at the next fix boundary
			pendingPickId = q.job.Id
			popText("On it after this fix...", 0.5, 1.1, TAN)
		end
	end)
end

-- Match the conveyor to the server's queue: new scooters roll out of the hatch.
local function syncQueue(list)
	local keep = {}
	for _, job in list do keep[job.Id] = true end
	for id, q in queued do
		if not keep[id] then
			-- waited too long: the customer storms off and their scooter rolls back out
			queued[id] = nil
			-- waited too long: their scooter rolls back out and they push it home
			task.spawn(function()
				while not q.arrived and q.model.Parent do task.wait() end
				local c = q.customer
				if q.model.Parent then slideModel(q.model, HATCH, 2.4, nil, true) end
				if c and c.model.Parent and q.model.Parent then
					c.done = true
					routeTo(c, HANDOVER)
					-- lifted down off the belt beside them
					local from = q.model:GetPivot()
					local root = c.model:FindFirstChild("HumanoidRootPart")
					local to = root and (root.CFrame * CFrame.new(1.5, 0, -0.5)).Position or HANDOVER.Position
					local land = Vector3.new(to.X, from.Y - 1.6, to.Z)
					animate(0.4, function(a)
						q.model:PivotTo(CFrame.new(from.Position:Lerp(land, a) + Vector3.new(0, math.sin(a * math.pi) * 0.8, 0)) * (from - from.Position))
					end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					customerLeaves(c, "😡", true, q.model)
				else
					if c then task.spawn(customerLeaves, c, "😡", true) end
					q.model:Destroy()
					origs[q.model] = nil
				end
			end)
			if state == "idle" or state == "repair" then popText("+1 customer lost today", 0.55, 1.1, RED) end
		end
	end
	-- parked sessions hold their belt slot; queued jobs fill the rest
	local held = {}
	for _, s in parked do
		if s.slotIndex then held[s.slotIndex] = true end
	end
	local free = {}
	for i = 1, #QUEUE_X do
		if not held[i] then table.insert(free, i) end
	end
	local s0 = Config.P.toLocal(SPOT.Position)
	local n = 0
	for _, job in list do
		n += 1
		local q = queued[job.Id]
		local slotI = free[n] or #QUEUE_X
		local slotCF = Config.P.PF * CFrame.new(QUEUE_X[slotI] or QUEUE_X[#QUEUE_X], s0.Y, s0.Z)
		local waitCF = WAIT_SPOTS[slotI + 1] or WAIT_SPOTS[#WAIT_SPOTS]
		if q then
			q.slotCF = slotCF
			q.slotIndex = slotI -- it moved up the belt: if it's picked and parked later, it comes back here
			-- the server's clock is the truth (it stops while you're busy)
			if q.customer and job.Age then q.customer.expires = pclock() + q.customer.patience - job.Age end
		end
		if not q then
			local m = Templates[job.Scooter]:Clone()
			prepScooter(m)
			outline(m)
			m:PivotTo(slotCF)
			paint(m, job)
			SCOOTER_FX.wear(m, job.First and 0.3 or job.Wear)
			breakScooter(m, job.Problems)
			q = { job = job, model = m, slotCF = slotCF, slotIndex = slotI }
			queued[job.Id] = q
			if job.First then
				-- your own scooter is already inside
				m.Parent = workspace
				q.arrived = true
				beltPrompt(q)
			else
				-- customer walks up, drops it on the conveyor, then waits at the window
				local path = job.Walk and Config.Crowd.route(ARRIVE.Position, true)
				local c = newCustomer(path and CFrame.new(path[1]) or nil, job.Seed)
				c.patience = job.Patience or 90
				c.expires = pclock() + c.patience - (job.Age or 0)
				c.job = job
				ui.bubbles.attach(c)
				q.customer = c
				local rar = RARITY[job.Rarity]
				if rar and rar.Index >= 3 then
					popText(("%s %s!"):format(rar.Name:upper(), job.Scooter), 0.6, 1.4, rar.Color)
					sfx(SFX.Done, 0.8, 1.4)
				elseif job.Mood == "VIP" then
					popText("VIP!", 0.6, 1.4, ui.style.Color.Gold)
					sfx(SFX.Done, 0.8, 1.4)
				end
				task.spawn(function()
					-- they push their scooter up the sidewalk to the hatch
					m.Parent = workspace
					local stop = SCOOTER_FX.escort(c, m)
					if path then
						-- the last stretch of the way from the bus: round the ring to this garage's side path
						ui.bubbles.fadeIn({ c.model, m }, 0.5)
						local pts = {}
						for i, p in path do
							if i > 1 then table.insert(pts, CFrame.new(p)) end
						end
						walkPath(c, pts)
					end
					routeTo(c, HANDOVER)
					stop()
					playAnim(c, ANIM.Point, false)
					Config.Fun.dropOff(c, job) -- what happened to it
					-- and lift it onto the belt
					local from = m:GetPivot()
					animate(0.45, function(a)
						local p = from.Position:Lerp(HATCH.Position, a) + Vector3.new(0, math.sin(a * math.pi) * 1.2, 0)
						m:PivotTo(CFrame.new(p) * (from - from.Position):Lerp(HATCH - HATCH.Position, a))
					end, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					m:PivotTo(HATCH)
					sfx(SFX.Tap, 0.4, 0.8)
					task.spawn(function()
						-- the queue may move up while it rolls in
						local target
						repeat
							target = q.slotCF
							slideModel(m, target, 2.2, nil, true)
						until target == q.slotCF or not m.Parent
						if m.Parent then settle(m) end
						q.arrived = true
						beltPrompt(q)
					end)
					task.wait(0.5)
					if not c.done then routeTo(c, q.waitCF or waitCF) end
				end)
			end
		else
			if q.arrived then task.spawn(slideModel, q.model, slotCF, 1.2, nil, true) end
			if q.customer and q.waitCF ~= waitCF and not q.customer.walking then
				task.spawn(routeTo, q.customer, waitCF)
			end
		end
		q.waitCF = waitCF
	end
	updateList()
end

-- The restock card for any part a waiting customer needs and you have none of.
local checkStock
do
	local checking = false
	checkStock = function()
		if checking then return end
		checking = true
		local out = {}
		for _, q in queued do
			for _, s in Config.stockNeeds(q.job) do
				if (player:GetAttribute(s) or 0) <= 0 and not table.find(out, s) then table.insert(out, s) end
			end
		end
		state = #out > 0 and "chores" or state
		for _, s in out do
			if (player:GetAttribute(s) or 0) <= 0 then needStock(s) end
		end
		if #out > 0 then state = "idle" end
		checking = false
	end
end

-- Build a session from a belt job (shared by the idle pick and mid-repair picks).
startSession = function(id)
	local q = queued[id]
	if not q or not q.arrived then return nil end
	if binCount >= binCap() then return nil end
	local job, newQueue = Remotes.PickJob:InvokeServer(id)
	if not job then return nil end
	queued[id] = nil
	local pp = q.model and q.model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if pp then pp:Destroy() end
	updateList()
	-- (no skill reset here: a mid-repair pick still has the current job's counts; switchCard swaps them)
	local sess = {
		job = job, model = q.model, started = os.clock(), customer = q.customer,
		slotIndex = q.slotIndex, done = {},
	}
	if sess.customer then
		Config.Fun.picked(sess.customer)
		local c = sess.customer
		task.spawn(function()
			while c.walking do task.wait() end
			if not c.done then routeTo(c, WAIT_SPOTS[1]) end
		end)
	end
	return sess, newQueue
end

function pickJob(id)
	if state == "repair" then
		-- parallel bench: park the current job at the next fix boundary and grab this one
		if inFlight() < parallelCap() then
			pendingPickId = id
			popText("On it after this fix...", 0.5, 1.1, TAN)
		end
		return
	end
	if state ~= "idle" then return end
	local q = queued[id]
	if not q or not q.arrived then return end
	-- bin full: bag it before the next job. Nothing starts by itself afterwards: you walk back and pick the
	-- job (owner, 24 Oct: the camera jumped to the bench while they were still at the dumpster)
	if binCount >= binCap() then
		popText("Bin's full! Bag the trash first", 0.55, 1.4, RED)
		sfx(SFX.Tap, 0.9, 0.4)
		return
	end
	-- out of a part this job needs: the restock card first (no, and they go home)
	for _, s in Config.stockNeeds(q.job) do
		if (player:GetAttribute(s) or 0) <= 0 then
			state = "chores"
			local ok = needStock(s)
			state = "idle"
			if not ok then return end
		end
	end
	state = "picking"
	local sess, newQueue = startSession(id)
	if not sess then
		state = "idle"
		return
	end
	ui.skill.reset() -- nothing else is in flight: this job's perfects and misses start from zero
	shownStars = 5
	setStars(ui.timer.Stars, 5)
	ui.timer.Visible = true
	buildJobCard(sess.job)
	ui.job.Visible = true
	setInstruction("Here it comes...", 1)
	state = "repair"
	enterBench()
	task.spawn(syncQueue, newQueue)
	-- the belt carries it onto the bench
	slideModel(sess.model, SPOT, 1.3, nil, true)
	settle(sess.model)
	sfx(SFX.Tap, 0.6, 0.7)
	runSessions(sess)
end

-- The serve moment (plan/13, Cooking Fever's counter): the fixed scooter pops off the bench and out beside
-- its owner at the window, they cheer with hearts, leave the pay on the window counter in front of them
-- and ride off. Tap the cash to collect it (the tag is a GUI button, so it never counts as a minigame
-- tap); taps in quick succession jingle higher. Cash nobody taps is collected by itself after
-- Config.CashPile.AutoCollect (the server banks it after BankAfter, and when you leave), so none is lost.
-- A modelled ReplicatedStorage.CashPile is used if there is one; otherwise a simple stack is built.
local handOver
do
	local COUNTER_Y, COUNTER_Z = 3.45, -20.6 -- the outside half of the window counter (plot space)
	local piles = {} -- the cash waiting on the counter: { model, tag, x, jobId, taken }
	local lastCollect, streak, hints = 0, 0, 0

	-- little hearts float up from a happy customer (more for more stars)
	local function hearts(c, n)
		local head = c.model:FindFirstChild("Head")
		if not head then return end
		for i = 1, math.clamp(n, 1, 5) do
			task.delay(i * 0.12, function()
				if not head.Parent then return end
				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromOffset(36, 36)
				bb.StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 1.6, 1.3, 0)
				bb.AlwaysOnTop = true
				bb.LightInfluence = 0
				local t = Instance.new("TextLabel")
				t.BackgroundTransparency = 1
				t.Size = UDim2.fromScale(1, 1)
				t.Text = "♥"
				t.TextScaled = true
				t.TextColor3 = Color3.fromRGB(255, 90, 130)
				t.FontFace = ui.style.Font.Chunky
				local st = Instance.new("UIStroke", t)
				st.Color = Color3.new(1, 1, 1)
				st.Thickness = 2
				t.Parent = bb
				bb.Parent = head
				local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad)
				TweenService:Create(bb, info, { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 2.2, 0) }):Play()
				TweenService:Create(t, info, { TextTransparency = 1 }):Play()
				TweenService:Create(st, info, { Transparency = 1 }):Play()
				task.delay(1.2, function() bb:Destroy() end)
			end)
		end
	end

	local function collect(pile, auto)
		if pile.taken then return end
		pile.taken = true
		local i = table.find(piles, pile)
		if i then table.remove(piles, i) end
		local at = pile.model:GetPivot().Position
		local sp = camera:WorldToViewportPoint(at)
		pile.tag:Destroy()
		pile.model:Destroy()
		sparkle(at)
		local ok, got = pcall(function() return Remotes.CollectCash:InvokeServer(pile.jobId, auto) end)
		got = ok and tonumber(got) or 0
		if got <= 0 then return end -- (banked already)
		local now = os.clock()
		streak = now - lastCollect < 2.5 and streak + 1 or 1
		lastCollect = now
		coinsTo(Vector2.new(sp.X, sp.Y), math.clamp(math.floor(got / 15), 5, 16))
		sfx(SFX.Done, 0.7, 1.1 + math.min(streak, 6) * 0.08)
		popText("+$" .. ui.style.money(got), 0.6 + math.min(streak, 4) * 0.04, 0.9, GREEN)
	end

	local function buildPile()
		local template = RS:FindFirstChild("CashPile")
		if template then return template:Clone() end
		local pile = Instance.new("Model")
		pile.Name = "CashPile"
		local function piece(size, color, material, cf)
			local p = Instance.new("Part")
			p.Size = size
			p.Color = color
			p.Material = material
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.CFrame = cf
			p.Parent = pile
			return p
		end
		for i = 1, 3 do
			local bill = piece(Vector3.new(1.1, 0.09, 0.55), i % 2 == 1 and Color3.fromRGB(96, 196, 104) or Color3.fromRGB(70, 160, 84),
				Enum.Material.SmoothPlastic, CFrame.new(0, 0.05 + (i - 1) * 0.09, 0) * CFrame.Angles(0, math.rad(math.random(-14, 14)), 0))
			if i == 1 then pile.PrimaryPart = bill end
		end
		-- a coin on top (a cylinder's axis is its X: turned upright it lies flat)
		piece(Vector3.new(0.08, 0.42, 0.42), Color3.fromRGB(255, 200, 60), Enum.Material.Metal, CFrame.new(0.22, 0.36, 0) * CFrame.Angles(0, 0, math.rad(90)))
		return pile
	end

	-- the pay on the counter in front of x (plot space), with a tag you tap
	local function dropCash(x, amount, jobId)
		x = math.clamp(x, -12, 12)
		-- next to any cash already lying there
		local taken = true
		while taken do
			taken = false
			for _, p in piles do
				if math.abs(p.x - x) < 1.2 then
					x = x + 1.3 > 12 and x - 1.3 or x + 1.3
					taken = true
				end
			end
		end
		local model = buildPile()
		model:PivotTo(Config.P.PF * CFrame.new(x, COUNTER_Y, COUNTER_Z))
		model.Parent = workspace
		puff(model:GetPivot().Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(150, 230, 150), 6)
		local tag = Instance.new("BillboardGui")
		tag.Name = "CashTag"
		tag.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		tag.Size = UDim2.fromOffset(112, 46)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)
		tag.AlwaysOnTop = true
		tag.LightInfluence = 0
		tag.Active = true
		tag.ResetOnSpawn = false
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromScale(1, 1)
		btn.BackgroundColor3 = ui.style.Color.Cash
		btn.Text = "$" .. ui.style.money(amount)
		btn.FontFace = ui.style.Font.Chunky
		btn.TextScaled = true
		btn.TextColor3 = Color3.new(1, 1, 1)
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
		local st = Instance.new("UIStroke", btn)
		st.Color = ui.style.Color.Ink
		st.Thickness = 3
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local pad = Instance.new("UIPadding", btn)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
		btn.Parent = tag
		tag.Parent = player.PlayerGui
		popScale(btn, 0.4, 0.3)
		-- a gentle bob so it catches the eye
		TweenService:Create(tag, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0) }):Play()
		local pile = { model = model, tag = tag, x = x, jobId = jobId }
		table.insert(piles, pile)
		btn.Activated:Connect(function() task.spawn(collect, pile) end)
		task.delay(Config.CashPile and Config.CashPile.AutoCollect or 25, function() collect(pile, true) end)
		if hints < 2 then
			hints += 1
			task.delay(0.8, function()
				if not pile.taken then popText("Tap the cash to collect it!", 0.55, 1.8, ui.style.Color.Gold) end
			end)
		end
	end

	-- done = the finished session; lifted = it already left its spot (the paint booth lifts it itself)
	handOver = function(done, m, c, lifted)
		local r = done.result
		local base = m and m:GetAttribute("BaseScale") or 1
		if m and m.Parent and not lifted then
			-- off the bench: up, small, gone in a puff
			local from = m:GetPivot()
			sfx(SFX.Done, 0.5, 1.3)
			animate(0.45, function(a)
				m:PivotTo(from + Vector3.new(0, a * 2.5, 0))
				m:ScaleTo(base * math.max(0.05, 1 - a * a))
			end, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			puff(from.Position + Vector3.new(0, 2.5, 0), nil, 12)
		end
		local owner = c and c.model and c.model.Parent and c or nil
		if owner then
			-- they may still be walking up to the window
			local t0 = os.clock()
			while owner.walking and os.clock() - t0 < 8 do task.wait() end
		end
		if owner and m and m.Parent then
			-- and out beside its owner, wheels on the ground
			m:ScaleTo(base)
			local stop = SCOOTER_FX.escort(owner, m)
			RunService.RenderStepped:Wait()
			stop()
			puff(m:GetPivot().Position + Vector3.new(0, 1, 0), nil, 10)
			sfx(SFX.Done, 0.6, 1.5)
		elseif m and m.Parent then
			m:Destroy()
			origs[m] = nil
			m = nil
		end
		local happy = not done.dropped and not done.wrongPaint
		if owner and happy then hearts(owner, r and r.Stars or 3) end
		if r and (r.Total or 0) > 0 then
			-- your own first scooter has no owner at the window: its pay lands where the next one will stand
			local x = owner and Config.P.toLocal(owner.model:GetPivot().Position).X or Config.P.toLocal(WAIT_SPOTS[1].Position).X
			dropCash(x, r.Total, done.job.Id)
		end
		if owner then
			customerLeaves(owner, done.dropped and "😕" or done.wrongPaint and "😤" or Config.Fun.thanks(done), done.wrongPaint, m)
		end
	end
end

-- Hand the fixed scooter back to its owner (handOver).
finishJob = function()
	local done = active
	active = nil
	if not done then return end
	local m, c = done.model, done.customer
	if done.painted and m and m.Parent then
		-- it dries in the booth first, then goes out to its owner
		task.spawn(BOOTH.dry, done, function() handOver(done, m, c, true) end)
		return
	end
	task.spawn(handOver, done, m, c, false)
	-- a part a waiting customer needs has run out: the restock card now, between jobs
	task.delay(0.6, function()
		if state == "idle" then checkStock() end
	end)
end

-- Fix scooter at the bench pulls the next scooter in line.
local benchPrompt = bench:WaitForChild("WorkSpot"):WaitForChild("WorkPrompt")
benchPrompt.ActionText = "Fix scooter"
benchPrompt.ObjectText = ""
benchPrompt.HoldDuration = 0
local function nextJobId()
	local best, bestX
	for id, q in queued do
		local x = Config.P.toLocal(q.slotCF.Position).X
		if q.arrived and (not bestX or x > bestX) then best, bestX = id, x end
	end
	return best
end
benchPrompt.Triggered:Connect(function()
	local id = nextJobId()
	if id then pickJob(id) end
end)
RunService.Heartbeat:Connect(function()
	local idle = state == "idle" and binCount < binCap()
	benchPrompt.Enabled = idle and nextJobId() ~= nil
	-- belt prompts: between jobs, or mid-repair while the bench tier has a free slot
	local more = state == "repair" and inFlight() < parallelCap() and binCount < binCap()
	for _, q in queued do
		local p = q.model and q.model:FindFirstChildWhichIsA("ProximityPrompt", true)
		if p then p.Enabled = (idle or more) and q.arrived end
	end
end)

Remotes.QueueChanged.OnClientEvent:Connect(syncQueue)

---------------------------------------------------------------- test ride
local ANIM_WAVE = "rbxassetid://507770239"
local cones = {}
for _, c in road:WaitForChild("Obstacles"):GetChildren() do
	table.insert(cones, { model = c, home = c:GetPivot() })
end

local function startRide()
	state = "ride"
	setBusy(true)
	ui.pay.Visible = false
	ui.job.Visible = false
	ui.timer.Visible = false
	hideSelf(false)
	local scooter = active.model
	local def
	for _, s in Config.Scooters do
		if s.Name == active.job.Scooter then def = s end
	end
	-- the customer waits for you at the end of the road
	local c = active.customer or newCustomer()
	active.customer = nil
	c.done = true
	say(c, nil)
	c.model:PivotTo(CFrame.lookAt(Vector3.new(1204, 3.2, FINISH_Z + 8), Vector3.new(1200, 3.2, FINISH_Z - 10)))
	playAnim(c, ANIM_WAVE)
	local customer = c.model

	local char, hum, hrp = getRig()
	if not hrp then return end
	hrp.Anchored = true
	hum.PlatformStand = true

	local maxSpeed = def and def.MaxSpeed or 55
	local wheelD = scooter:GetAttribute("WheelD") or 1.6
	local hrpUp = wheelD / 2 + 0.4 + hum.HipHeight + hrp.Size.Y / 2
	local pos = START
	local y, vy = START.Y, 0
	local yaw = math.pi
	local speed = 0
	local lastGround = START.Y
	local airTime, airs = 0, 0
	local clean = true
	local wallCooldown = 0
	local shake = 0

	-- riding pose: hands on the grips, feet on the deck (IK targets ride along
	-- with the scooter); knees bend more with speed and you tuck in the air
	local rideRig, crouch = {}, 0
	do
		local base0 = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		scooter:PivotTo(base0 * CFrame.Angles(0, math.pi / 2, 0))
		hrp.CFrame = base0 * CFrame.new(0, hrpUp, 0.3)
		local animator = hum:FindFirstChildOfClass("Animator")
		local function attach(name, parent, worldPos, localPos)
			local a = Instance.new("Attachment")
			a.Name = name
			a.Parent = parent
			if worldPos then a.WorldPosition = worldPos else a.Position = localPos end
			table.insert(rideRig, a)
			return a
		end
		local function ik(rootName, endName, target, pole)
			local root, effector = char:FindFirstChild(rootName), char:FindFirstChild(endName)
			if not (root and effector and animator) then return end
			local c = Instance.new("IKControl")
			c.Type = Enum.IKControlType.Position
			c.ChainRoot = root
			c.EndEffector = effector
			c.Target = target
			c.Pole = pole
			c.Parent = hum
			table.insert(rideRig, c)
		end
		local fwd0, right0 = base0.LookVector, base0.RightVector
		local deck = scooter:FindFirstChild("Deck")
		if deck then
			local up = Vector3.yAxis
			local half = 0.5 * (math.abs(deck.CFrame.RightVector:Dot(up)) * deck.Size.X
				+ math.abs(deck.CFrame.UpVector:Dot(up)) * deck.Size.Y
				+ math.abs(deck.CFrame.LookVector:Dot(up)) * deck.Size.Z)
			local top = deck.Position + Vector3.new(0, half, 0)
			-- stand on the deck, legs straight; the crouch bends them from there
			hrpUp = top.Y - pos.Y + hum.HipHeight + hrp.Size.Y / 2
			hrp.CFrame = base0 * CFrame.new(0, hrpUp, 0.3)
			for _, s in { -1, 1 } do
				local side = s < 0 and "Left" or "Right"
				local foot = char:FindFirstChild(side .. "Foot")
				if foot then
					-- right foot forward, left foot back
					local at = top + fwd0 * (0.4 * s) + right0 * (0.15 * s) + Vector3.new(0, foot.Size.Y / 2, 0)
					ik(side .. "UpperLeg", side .. "Foot", attach("FootAt", deck, at), attach("KneePole", hrp, nil, Vector3.new(s * 0.6, -1, -4)))
				end
			end
		end
		for _, g in scooter:GetChildren() do
			if g.Name == "Grip" and g:IsA("BasePart") then
				local s = right0:Dot(g.Position - hrp.Position) < 0 and -1 or 1
				local side = s < 0 and "Left" or "Right"
				ik(side .. "UpperArm", side .. "Hand", attach("Grab", g, g.Position), attach("ElbowPole", hrp, nil, Vector3.new(s * 3, 0, 1.5)))
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { scooter, char, road.Obstacles, customer }

	ui.ride.Visible = true
	ui.ride.Text.Text = "Clean ride = tip!"
	ui.ride.Text.TextColor3 = Color3.fromRGB(120, 220, 130)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70

	local done = Instance.new("BindableEvent")
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 1 / 20)
		local throttle, steer = getMove(hum)
		local finished = pos.Z >= FINISH_Z
		if finished then throttle, steer = 0, 0 end

		if y <= lastGround + 0.05 then
			if throttle > 0.1 then
				speed += 32 * throttle * dt
			elseif throttle < -0.1 then
				speed -= 60 * dt
			else
				speed -= (finished and 90 or 12) * dt
			end
		end
		speed = math.clamp(speed, 0, maxSpeed)
		yaw -= steer * 1.9 * dt * math.clamp(speed / 20, 0.25, 1)
		local fwd = CFrame.Angles(0, yaw, 0).LookVector
		pos += fwd * speed * dt

		-- kerbs: bounce off and lose speed
		wallCooldown -= dt
		local t1 = math.clamp((pos.Z - 30) / 60, 0, 1)
		local t2 = math.clamp((pos.Z - 450) / 60, 0, 1)
		local cx = 1200 + 22 * math.sin((pos.Z - 30) / 80) * t1 * t1 * (3 - 2 * t1) * (1 - t2 * t2 * (3 - 2 * t2))
		if math.abs(pos.X - cx) > 11.6 then
			pos = Vector3.new(cx + math.sign(pos.X - cx) * 11.6, pos.Y, pos.Z)
			if wallCooldown <= 0 then
				speed *= 0.7
				shake = 0.4
				wallCooldown = 0.5
				sfx(SFX.Tap, 0.8, 0.5)
			end
			yaw += (math.pi - yaw) * 0.3
		end
		if pos.Z < 34 then pos = Vector3.new(pos.X, pos.Y, 34) end

		-- ground follow, ramps launch you
		local hit = workspace:Raycast(Vector3.new(pos.X, y + 6, pos.Z), Vector3.new(0, -30, 0), params)
		local ground = hit and hit.Position.Y or 0.9
		if y <= ground + 0.05 then
			if airTime > 0.35 then
				airs += 1
				popText(("AIR! +$%d"):format(Config.AirBonus), 0.5, 0.8)
				sfx(SFX.Done, 0.5, 1.2)
			end
			airTime = 0
			vy = (ground - lastGround) / dt
			y = ground
		else
			airTime += dt
			vy -= 60 * dt
			y = math.max(ground, y + vy * dt)
		end
		lastGround = ground
		pos = Vector3.new(pos.X, y, pos.Z)

		-- cones
		for _, c in cones do
			if not c.hit then
				local cp = c.home.Position
				if (Vector2.new(cp.X, cp.Z) - Vector2.new(pos.X, pos.Z)).Magnitude < 1.9 and y < 3 then
					c.hit = true
					speed *= 0.55
					shake = 0.5
					sfx(SFX.Tap, 0.8, 0.7)
					if clean then
						clean = false
						ui.ride.Text.Text = "Tip lost!"
						ui.ride.Text.TextColor3 = Color3.fromRGB(255, 120, 100)
					end
					local fly = Instance.new("CFrameValue")
					fly.Value = c.home
					fly.Changed:Connect(function(v) c.model:PivotTo(v) end)
					local target = c.home + fwd * 14 + Vector3.new(math.random(-4, 4), 5, 0)
					TweenService:Create(fly, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Value = target * CFrame.Angles(math.rad(120), 0, math.rad(60)) }):Play()
					c.fly = fly
				end
			end
		end

		-- place scooter + rider
		local pitch = math.atan2(math.clamp(vy, -40, 40), math.max(speed, 8)) * 0.8
		local lean = -steer * 0.22 * math.clamp(speed / maxSpeed, 0, 1)
		local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, lean)
		scooter:PivotTo(base * CFrame.Angles(0, math.pi / 2, 0))
		local k = math.clamp(speed / maxSpeed, 0, 1)
		local want = airTime > 0.1 and 0.45 or 0.12 + 0.22 * k
		crouch += (want - crouch) * math.min(1, dt * 10)
		hrp.CFrame = base * CFrame.new(0, hrpUp - crouch, 0.3) * CFrame.Angles(-(0.06 + 0.14 * k + crouch * 0.3), 0, 0)

		-- chase camera
		shake = math.max(0, shake - dt)
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake * 1.2
		local flat = CFrame.Angles(0, yaw, 0)
		local want = CFrame.lookAt(pos - flat.LookVector * 13 + Vector3.new(0, 6, 0) + jitter, pos + flat.LookVector * 8 + Vector3.new(0, 2.5, 0))
		camera.CFrame = camera.CFrame:Lerp(want, 1 - math.exp(-8 * dt))
		camera.FieldOfView = 70 + 14 * speed / maxSpeed

		local left = math.max(0, math.floor(FINISH_Z - pos.Z))
		ui.ride.Dist.Text = left > 0 and ("%dm to customer"):format(left) or "Delivered!"
		if finished and speed <= 0.5 then
			conn:Disconnect()
			done:Fire(clean, airs)
		end
	end)
	camera.CFrame = CFrame.lookAt(START + Vector3.new(0, 6, -13), START + Vector3.new(0, 2.5, 8))
	local okClean, okAirs = done.Event:Wait()
	done:Destroy()

	ui.ride.Visible = false
	local tip = Remotes.RideTip:InvokeServer(okClean, okAirs)
	if tip and tip.Total > 0 then
		popText(("TIP +$%d"):format(tip.Total), 0.9, 1.6, GREEN)
		sfx(SFX.Done, 0.9, 1.1)
	else
		popText("No tip...", 0.6, 1.4, Color3.fromRGB(255, 120, 100))
	end
	task.wait(1.8)

	-- back to the garage
	removeCustomer(c)
	for _, c in cones do
		if c.fly then c.fly:Destroy() c.fly = nil end
		c.hit = false
		c.model:PivotTo(c.home)
	end
	for _, o in rideRig do o:Destroy() end
	hum.PlatformStand = false
	hrp.CFrame = Config.P.PF * CFrame.lookAt(Vector3.new(0, 4, 4), Vector3.new(0, 4, -8))
	hrp.Anchored = false
	setBusy(false)
	finishJob()
end

ui.pay.Next.Button.Activated:Connect(function()
	if state == "results" then finishJob() end
end)
ui.pay.Ride.Button.Activated:Connect(function()
	if state == "results" and active then startRide() end
end)
-- the quick TEST RIDE chip after a job (runRepair shows it for a moment)
if gui:FindFirstChild("RideChip") then
	gui.RideChip.Button.Activated:Connect(function()
		if state == "results" and active then
			gui.RideChip.Visible = false
			startRide()
		end
	end)
end

---------------------------------------------------------------- shop
local shopRows = {}
local function refreshShop()
	local cash = player:FindFirstChild("leaderstats") and player.leaderstats.Cash.Value or 0
	for i, item in Config.Shop do
		if item.Starter then continue end -- you already own these
		local row = shopRows[item.Id]
		if not row then
			row = ui.shop.List.RowTemplate:Clone()
			row.Name = item.Id
			row.LayoutOrder = i
			row.Visible = true
			row.Icon.Image = ui.style.Icon[item.Icon] or item.Icon or ""
			row.Parent = ui.shop.List
			shopRows[item.Id] = row
			row.Buy.Button.Activated:Connect(function() ui.buyItem(item) end)
		end
		local level = player:GetAttribute(item.Id) or 0
		local price
		-- no tyre packs until you have a tyre rack to put them on
		local holder = item.Holder and SHOP[item.Holder]
		row.Visible = not (holder and holder.Locked and (player:GetAttribute(item.Holder) or 0) == 0)
			and not (item.Needs and (player:GetAttribute(item.Needs) or 0) == 0)
			-- a machine waiting for a bench or garage tier stays hidden until it can be bought
			and not (level == 0 and not Config.gateOpen(item, function(g) return player:GetAttribute(g) end))
		if item.Kind == "Level" then
			-- upgrade system v5: the tier's name, n/10 upgrades; the next one says what it does
			local ups = Config.upgradesOf(level)
			row.Title.Text = level == 0 and (item.Names[1] or item.Id) or item.Ups and ("%s  %d/%d"):format(item.Names[level], ups, item.Ups) or (item.Names[level] or item.Names[1])
			price = item.Prices[level + 1]
			local main = item.Main and item[item.Main[1]]
			if level == 0 or not price then
				row.Desc.Text = level == 0 and item.Desc or "Maxed out!"
			elseif Config.TierUps[ups + 1] then
				row.Desc.Text = ("NEW LOOK: %s"):format(item.Names[level + 1])
			elseif main and main[level + 1] then
				row.Desc.Text = ("%s %s  >  %s"):format(item.Main[2], item.Main[3]:format(main[level]), item.Main[3]:format(main[level + 1]))
			else
				row.Desc.Text = item.Desc
			end
		elseif item.Kind == "Stock" then
			-- consumable: fills the holder up; a part-filled pack costs its share
			local cap = holderCap(item)
			local add = math.min(item.Amount, cap - level)
			row.Title.Text = item.Title
			row.Desc.Text = ("%s (%d/%d)"):format(item.Desc, level, cap)
			price = add > 0 and math.ceil(item.Price * add / item.Amount) or nil
		else
			row.Title.Text = item.Title
			row.Desc.Text = item.Desc
			price = level == 0 and item.Price or nil
		end
		local btn = row.Buy.Button
		-- everything is bought at night, once the trash is out (in the day you can look and plan). Kit buttons
		-- take their colour from the Gloss.
		local waitForNight = not player:GetAttribute("Night")
		local C = ui.style.Color
		if price and waitForNight then
			btn.Label.Text = "NIGHT"
			btn.Gloss.Color = ui.style.glossColors(C.EnamelLine)
		elseif price then
			btn.Label.Text = ("$%d"):format(price)
			btn.Gloss.Color = ui.style.glossColors(cash >= price and C.Cash or C.EnamelLine)
		else
			btn.Label.Text = item.Kind == "Level" and "MAX" or item.Kind == "Stock" and "FULL" or "OWNED"
			btn.Gloss.Color = ui.style.glossColors(C.EnamelLine)
		end
	end
end

-- Buying an upgrade or a pack: the stand's list and the tycoon boards over the machines both come here.
ui.buyItem = function(item)
	local was = player:GetAttribute(item.Id) or 0
	if Remotes.BuyShop:InvokeServer(item.Id) then
		sfx(SFX.Done, 0.9)
		shake(0.2, 0.15)
		popText((item.Kind == "Unlock" or was == 0 and item.Locked) and "UNLOCKED!" or item.Kind == "Stock" and ("+%d!"):format(item.Amount) or "UPGRADED!", 0.8, 1)
		task.wait(0.1)
		refreshStations()
	else
		sfx(SFX.Tap, 0.8, 0.5)
	end
	refreshShop()
end

-- The menu ball and the + on the cash open the Robux store (owner, 24 Oct: "shop isnt the upgrades ui ...
-- shop should be robux purchases"). Upgrades and stock are at the stand in the garage.
ui.shopBtn.Button.Activated:Connect(function()
	if state ~= "idle" then return end
	ui.shop.Visible = false
	ui.store.toggle()
end)
ui.shop.Close.Button.Activated:Connect(function() ui.shop.Visible = false end)
if gui.Cash:FindFirstChild("Plus") then
	gui.Cash.Plus.Button.Activated:Connect(function()
		if state ~= "idle" then return end
		ui.shop.Visible = false
		ui.store.open("Cash")
	end)
end
ui.shop:GetPropertyChangedSignal("Visible"):Connect(function() setBusy(ui.shop.Visible) end)

-- The upgrade stand (the parts counter) opens the upgrades. It glows at night once they're open (the guide).
local shopPrompt = garage:WaitForChild("PartsShop"):WaitForChild("CounterTop"):WaitForChild("ShopPrompt")
shopPrompt.ActionText = "Upgrades"
shopPrompt.ObjectText = ""
shopPrompt.Triggered:Connect(function()
	if state ~= "idle" then return end
	refreshShop()
	ui.shop.Visible = true
end)
RunService.Heartbeat:Connect(function()
	shopPrompt.Enabled = state == "idle" and not ui.shop.Visible
end)
player.AttributeChanged:Connect(function()
	if ui.shop.Visible then refreshShop() end
end)

---------------------------------------------------------------- closing time
-- When the day ends (the server sets ShopOpen = false) nobody new comes in.
-- Once the last customer is served you bag up the parts bin, carry it out to
-- the dumpster and throw it in; that starts the next day.
do -- (own scope: the script is near Luau's 200-locals limit; nothing outside uses these)
local openSign = garage:WaitForChild("OpenSign")
local dumpster = garage:WaitForChild("Dumpster")
local function updateSign()
	do return end -- the Crowd module draws every garage's sign from the shared clock
	local open = player:GetAttribute("ShopOpen") ~= false
	local day = player:GetAttribute("Day") or 1
	local endsAt = player:GetAttribute("DayEndsAt") or 0
	local sub = ("DAY %d"):format(day)
	if player:GetAttribute("Night") then
		sub = "NIGHT"
	elseif not open then
		sub = ("DAY %d DONE"):format(day)
	elseif endsAt > 0 then
		local left = math.max(0, math.floor(endsAt - workspace:GetServerTimeNow()))
		sub = ("DAY %d  %d:%02d"):format(day, left // 60, left % 60)
	end
	for _, g in openSign.Board:GetChildren() do
		if g:IsA("SurfaceGui") then
			g.Title.Text = open and "OPEN" or "CLOSED"
			g.Title.TextColor3 = open and Color3.fromRGB(120, 230, 130) or RED
			g.Sub.Text = sub
		end
	end
end
task.spawn(function()
	while true do
		updateSign()
		task.wait(0.5)
	end
end)

-- Wait for the player to use a prompt on `part`.
local function promptOn(part, text)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = text
	pp.ObjectText = ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.Parent = part
	local used = false
	pp.Triggered:Connect(function() used = true end)
	while not used do task.wait() end
	pp:Destroy()
end

-- Dumpster lids swing up at the front and drop back.
local function flapLids()
	local lids = {}
	for _, p in dumpster:GetChildren() do
		if p.Name:match("^Lid") then
			local hingeAt = (p.CFrame * CFrame.new(0, 0, -p.Size.Z / 2)).Position
			table.insert(lids, { part = p, home = p.CFrame, hinge = hingeAt, axis = p.CFrame.RightVector })
		end
	end
	local function set(a)
		for _, l in lids do
			l.part.CFrame = CFrame.new(l.hinge) * CFrame.fromAxisAngle(l.axis, -a * math.rad(75)) * CFrame.new(-l.hinge) * l.home
		end
	end
	animate(0.2, set, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return function()
		animate(0.25, function(a) set(1 - a) end, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		sfx(SFX.Tap, 0.9, 0.6)
	end
end

-- Night: the street goes dark and the work lights come up warm.
local Lighting = game:GetService("Lighting")
local DAY_LOOK = { ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient }
local NIGHT_LOOK = { ClockTime = 20.6, Brightness = 0.8, Ambient = Color3.fromRGB(120, 100, 150), OutdoorAmbient = Color3.fromRGB(60, 50, 95) }
local lampLights = {}
for _, p in garage:GetChildren() do
	local l = p.Name == "Lamp" and p:FindFirstChildOfClass("PointLight")
	if l then table.insert(lampLights, { light = l, day = l.Brightness, dayColor = l.Color }) end
end
for _, l in game:GetService("CollectionService"):GetTagged("NightLamp") do
	table.insert(lampLights, { light = l, day = 0, dayColor = l.Color })
end
local function setNight(on)
	local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, on and NIGHT_LOOK or DAY_LOOK):Play()
	for _, l in lampLights do
		TweenService:Create(l.light, info, {
			Brightness = on and 0.9 or l.day,
			Color = on and Color3.fromRGB(255, 210, 160) or l.dayColor,
		}):Play()
	end
end

-- Day and night come from the server's clock: the same moment for every player.
local lastPhase
local function applyPhase()
	local phase = workspace:GetAttribute("Phase") or "Day"
	if phase == lastPhase then return end
	local first = lastPhase == nil
	lastPhase = phase
	setNight(phase == "Night")
	if phase == "Day" and not first then
		popText(("DAY %d"):format(workspace:GetAttribute("DayNumber") or 1), 1, 1.6)
		sfx(SFX.Done, 0.9, 1)
	end
end
workspace:GetAttributeChangedSignal("Phase"):Connect(applyPhase)
applyPhase()

local choring = false
local carrying = false
-- Bag the bin (its own prompt, below) and carry the bag out to the dumpster.
trashRun = function()
	do
		state = "chores"
		carrying = true
		ui.ins.Step.Text = ""
		clearBin()
		sfx(SFX.Tap, 0.8, 0.8)
		-- carry the bag in your hand
		local char = player.Character
		local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
		-- a real bin bag: a lumpy sack, a gathered neck, tied ears and a yellow tie
		local bagModel = Instance.new("Model")
		bagModel.Name = "TrashBag"
		local PLASTIC = Color3.fromRGB(34, 36, 34)
		local function lump(name, scale, offset, color)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(1, 1, 1)
			p.Color = color or PLASTIC
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0.12
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = scale
			mesh.Parent = p
			p.CFrame = CFrame.new(offset)
			p.Parent = bagModel
			return p
		end
		local bag = lump("Body", Vector3.new(1.35, 1.35, 1.25), Vector3.new(0, 0, 0))
		lump("Lump", Vector3.new(0.85, 0.75, 0.8), Vector3.new(0.35, -0.3, 0.2))
		lump("Lump", Vector3.new(0.8, 0.7, 0.85), Vector3.new(-0.3, -0.35, -0.15))
		lump("Lump", Vector3.new(0.7, 0.6, 0.7), Vector3.new(0.05, 0.35, -0.25))
		lump("Neck", Vector3.new(0.32, 0.5, 0.32), Vector3.new(0, 0.78, 0))
		lump("Ear", Vector3.new(0.38, 0.22, 0.16), Vector3.new(0.2, 1.05, 0)).CFrame = CFrame.new(0.18, 1.05, 0) * CFrame.Angles(0, 0, -0.6)
		lump("Ear", Vector3.new(0.38, 0.22, 0.16), Vector3.new(-0.2, 1.05, 0)).CFrame = CFrame.new(-0.18, 1.05, 0) * CFrame.Angles(0, 0, 0.6)
		lump("Tie", Vector3.new(0.4, 0.1, 0.4), Vector3.new(0, 0.93, 0), Color3.fromRGB(255, 205, 60))
		for _, p in bagModel:GetChildren() do
			if p ~= bag then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = bag, p
				w.Parent = p
			end
		end
		bagModel.PrimaryPart = bag
		local weld
		if hand then
			-- held by the knot
			bagModel:PivotTo(hand.CFrame * CFrame.new(0, -1.25, 0))
			weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = hand, bag
			weld.Parent = bag
			bagModel.Parent = char
		else
			bag.Anchored = true
			bagModel:PivotTo(bench.Bin.CFrame + Vector3.new(0, 1.5, 0))
			bagModel.Parent = workspace
		end
		setInstruction("Throw it in the dumpster outside")
		promptOn(dumpster.Body, "Throw away")
		ui.ins.Visible = false
		-- in it goes
		local from = bag.Position
		if weld then weld:Destroy() end
		bag.Anchored = true
		bagModel.Parent = workspace
		local closeLids = flapLids()
		local into = dumpster.Body.Position + Vector3.new(0, dumpster.Body.Size.Y / 2 - 0.4, 0)
		animate(0.5, function(a)
			bagModel:PivotTo(CFrame.new(from:Lerp(into, a) + Vector3.new(0, math.sin(a * math.pi) * 2.5, 0)) * CFrame.Angles(a * 2, 0, a))
		end, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		bagModel:Destroy()
		puff(into + Vector3.new(0, 1, 0), Color3.fromRGB(200, 200, 200), 10)
		closeLids()
		carrying = false
		state = "idle"
	end
end

-- The bin's own prompt: bag the trash whenever there's some in it (owner, 24 Oct: "throwing away trash should
-- be doable at anytime and imperative"). A full bin stops the next job until it's out, and at night the
-- upgrades stay shut until it's out.
local binPrompt = Instance.new("ProximityPrompt")
binPrompt.Name = "BagTrash"
binPrompt.ActionText = "Bag trash"
binPrompt.HoldDuration = 0
binPrompt.MaxActivationDistance = 9
binPrompt.RequiresLineOfSight = false
binPrompt.Parent = bench:WaitForChild("Bin")
binPrompt.Triggered:Connect(function()
	if state == "idle" and binCount > 0 then task.spawn(trashRun) end
end)
RunService.Heartbeat:Connect(function()
	binPrompt.Enabled = state == "idle" and binCount > 0
	binPrompt.ObjectText = binCount >= binCap() and "Full!" or ""
end)

-- Night, once the last customer is served: the day card (the reward), then the trash, then the upgrades.
local summaryDay = 0
local function closingChores()
	local day = workspace:GetAttribute("DayNumber") or 0
	if summaryDay ~= day then
		summaryDay = day
		state = "chores"
		ui.daycard.show({ gui = gui, remotes = Remotes, payfx = ui.payfx, sfx = sfx, SFX = SFX, popScale = popScale })
		state = "idle"
	end
	if binCount > 0 then
		-- the bin glows (the guide); you bag it with its prompt
		setInstruction("Night! Bag up the parts bin")
		while binCount > 0 or state ~= "idle" do
			if workspace:GetAttribute("Phase") ~= "Night" then break end
			task.wait(0.2)
		end
		ui.ins.Visible = false
	end
	if workspace:GetAttribute("Phase") ~= "Night" or not Remotes.EmptyTrash:InvokeServer() then
		task.wait(2) -- the server wasn't ready (a customer still in); try again shortly
		choring = false
		return
	end
	-- the trash is out: the stand glows until dawn (no lasting line: it hid the clock on phones)
	sfx(SFX.Done, 0.6, 0.7)
	popText("Upgrades are open!", 0.6, 1.6, GREEN)
	while workspace:GetAttribute("Phase") == "Night" do task.wait(0.5) end
	choring = false
end

-- What to do next (ui.guide): the one thing that glows gold, with a trail on the floor when it's far.
local stand = garage:FindFirstChild("PartsShop")
local standLight = Instance.new("PointLight")
standLight.Name = "NightGlow"
standLight.Color = Color3.fromRGB(255, 200, 90)
standLight.Range = 18
standLight.Brightness = 2.5
standLight.Enabled = false
standLight.Parent = stand and stand:FindFirstChild("CounterTop")
RunService.Heartbeat:Connect(function()
	local want
	local night = player:GetAttribute("Night") == true
	if carrying then
		want = dumpster
	elseif state == "idle" and not ui.shop.Visible then
		local closing = player:GetAttribute("ShopOpen") == false and next(queued) == nil
		if binCount > 0 and (binCount >= binCap() or (closing and not night)) then
			want = bench.Bin
		elseif nextJobId() then
			want = bench
		elseif night then
			want = stand
		end
	end
	ui.guide.set(want)
	standLight.Enabled = night
end)
RunService.Heartbeat:Connect(function()
	if choring or player:GetAttribute("ShopOpen") ~= false then return end
	if state ~= "idle" or next(queued) ~= nil then return end
	choring = true
	task.spawn(closingChores)
end)
end

-- Cash counts up (or down) smoothly and the pill pops when you earn.
local refreshCash
do
	local cashShown, cashTarget = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		if cashShown == cashTarget then return end
		local diff = cashTarget - cashShown
		local step = math.max(1, math.abs(diff) * math.min(1, dt * 5))
		cashShown = diff > 0 and math.min(cashTarget, cashShown + step) or math.max(cashTarget, cashShown - step)
		ui.cash.Text = ui.style.money(cashShown)
	end)

	refreshCash = function()
		local ls = player:FindFirstChild("leaderstats")
		local value = ls and ls.Cash.Value or 0
		if value > cashTarget then popScale(gui.Cash, 0.85) end
		cashTarget = value
		if ui.shop.Visible then refreshShop() end
	end
end

---------------------------------------------------------------- start
task.spawn(function()
	local ls = player:WaitForChild("leaderstats")
	ls:WaitForChild("Cash").Changed:Connect(refreshCash)
	refreshCash()
end)

local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart")
while player:GetAttribute("Pump") == nil do task.wait() end
refreshStations()
ui.hud.start({ gui = gui, config = Config })
ui.restock.init({ gui = gui, config = Config, remotes = Remotes, sfx = sfx, SFX = SFX, popScale = popScale, popText = popText })
ui.skill.init({ camera = camera, sfx = sfx, SFX = SFX, config = Config })
ui.store.start({ gui = gui, config = Config, remotes = Remotes, sfx = sfx, SFX = SFX, popScale = popScale, popText = popText, setBusy = setBusy })ui.tycoon.init({ player = player, config = Config, style = ui.style, garage = garage, myStations = myStations, stations = STATION_FOR,
	templates = StationTemplates, P = Config.P, buy = ui.buyItem, busy = function() return state ~= "idle" end })
ui.bubbles.init({ customers = customers, pclock = pclock, active = function() return active end })
ui.moments.init({ gui = gui, config = Config, remotes = Remotes, customers = customers, active = function() return active end, pclock = pclock,
	playAnim = playAnim, ANIM = ANIM, puff = puff, sfx = sfx, SFX = SFX, popText = popText, popScale = popScale })
require(script.Market).start({ gui = gui, popText = popText, popScale = popScale, sfx = sfx, SFX = SFX, remotes = Remotes, config = Config })
require(script.Crowd).start({ dress = SCOOTER_FX.dress, crowd = Config.Crowd, config = Config, remotes = Remotes })
local list = Remotes.GetQueue:InvokeServer()
syncQueue(list)
-- the first job is your own scooter: start fixing straight away
for _, job in list do
	if job.First then
		task.wait(1.3)
		pickJob(job.Id)
		break
	end
end
