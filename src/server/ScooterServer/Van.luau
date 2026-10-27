-- Caro's van: at night it drives in along the town road, crosses the ring, parks in the plaza bay and
-- opens its hatch (the flap swings up into an awning, the shelf folds out into a counter) with Caro behind
-- it. At dawn everything folds away, the van backs out, turns and drives off. The model is
-- ServerStorage.CaroVan (the Blender van, coloured by part name); without it a plain stall stands in.
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local M = { state = "gone" }

local CENTER = Vector3.new(-4, 0, -133)
local PHI = math.rad(330) -- the town road (the van lane runs on through the plaza)
local DIR = Vector3.new(-math.sin(PHI), 0, -math.cos(PHI)) -- outward
local LAT = Vector3.new(DIR.Z, 0, -DIR.X) -- right-hand side while driving inward
local SCALE = 1.15 -- plan/12: a bigger van — the night market should read as an EVENT from across the plaza
local WHEEL_R = 1.5 * SCALE
local PARK_R, START_R = 42, 209 -- START_R is inside the town tunnel's dark mouth, so the van appears out of it
local WARM = Color3.fromRGB(255, 210, 160)

-- ground height under the van along the lane: road 0.05, raised tables 0.62 (and their ramps)
local function groundY(r)
	local pts = { { 240, 0.05 }, { 86.8, 0.05 }, { 84.7, 0.62 }, { 74.2, 0.62 }, { 71.4, 0.05 }, { 69.3, 0.05 }, { 66.5, 0.62 }, { 0, 0.62 } }
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if r <= a[1] and r >= b[1] then
			local t = (a[1] - r) / (a[1] - b[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return r > 240 and 0.05 or 0.62
end

local function rOf(p) return (p - CENTER):Dot(DIR) end

-- pose of the van's design frame (+X = nose, +Z = right-hand side) at lane radius r, lateral offset, heading psi
-- (psi in degrees in the (outward, right) plane: 180 = nose toward the plaza centre, 0 = nose outward)
local function frameAt(r, lat, psi)
	local pos = CENTER + DIR * r + LAT * lat
	local a = math.rad(psi)
	local h = DIR * math.cos(a) + LAT * math.sin(a)
	local front, back = pos + h * (4 * SCALE), pos - h * (4 * SCALE)
	local y = groundY(r)
	local slope = (groundY(rOf(front)) - groundY(rOf(back))) / (8 * SCALE)
	local p = Vector3.new(pos.X, y, pos.Z)
	return CFrame.lookAt(p, p + Vector3.new(h.X, slope, h.Z).Unit) * CFrame.Angles(0, math.rad(90), 0)
end

M.frameAt = frameAt
local van, caro, prompt, wheels, spin
local relWheels = {}
local flapHome, shelfHome, flapHinge, shelfHinge
local FLAP_OPEN, SHELF_OPEN = math.rad(100), math.rad(90) -- about the part's own X axis (it is the design X axis, flipped)

local function parkedFrame() return frameAt(PARK_R, 0, 180) end

local function place(frame)
	van:PivotTo(frame * CFrame.Angles(0, math.pi, 0))
	for w, rel in relWheels do
		w.CFrame = frame * CFrame.Angles(0, math.pi, 0) * rel * CFrame.Angles(0, 0, spin)
	end
end

local function follow(nodes)
	for i = 2, #nodes do
		local a, b = nodes[i - 1], nodes[i]
		local len = math.max(math.sqrt((b.r - a.r) ^ 2 + (b.lat - a.lat) ^ 2), 0.5)
		local t = 0
		while t < 1 do
			local dt = RunService.Heartbeat:Wait()
			local step = dt * b.speed
			t = math.min(1, t + step / len)
			spin += (step * (b.sign or 1)) / WHEEL_R
			place(frameAt(a.r + (b.r - a.r) * t, a.lat + (b.lat - a.lat) * t, a.psi + (b.psi - a.psi) * t))
		end
	end
end

local function swing(part, home, hinge, angle)
	if part then part.CFrame = hinge * CFrame.Angles(angle, 0, 0) * hinge:Inverse() * home end
end

local function tween(duration, fn)
	local t0 = os.clock()
	while true do
		local a = math.min(1, (os.clock() - t0) / duration)
		fn(a * a * (3 - 2 * a))
		if a >= 1 then break end
		RunService.Heartbeat:Wait()
	end
end

---------------------------------------------------------------- Caro
local function buildCaro(frame)
	local rigs = RS:FindFirstChild("Customers") and RS.Customers:GetChildren()
	if not rigs or #rigs == 0 then return nil end
	local rig = rigs[1]:Clone()
	rig.Name = "Caro"
	local skin, shirt, pants, shoes = Color3.fromRGB(240, 190, 150), Color3.fromRGB(245, 238, 222), Color3.fromRGB(60, 64, 78), Color3.fromRGB(40, 42, 52)
	local paint = {
		Head = skin, LeftHand = skin, RightHand = skin, UpperTorso = shirt, LeftUpperArm = shirt, RightUpperArm = shirt,
		LeftLowerArm = shirt, RightLowerArm = shirt, LowerTorso = pants, LeftUpperLeg = pants, RightUpperLeg = pants,
		LeftLowerLeg = pants, RightLowerLeg = pants, LeftFoot = shoes, RightFoot = shoes,
	}
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then bc:Destroy() end
	for name, col in paint do
		local p = rig:FindFirstChild(name)
		if p then p.Color = col end
	end
	local function accessory(parent, name, shape, size, offset, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CFrame = parent.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = parent, p
		w.Parent = p
		p.Parent = rig
		return p
	end
	local AMBER, TEAL = Color3.fromRGB(255, 196, 61), Color3.fromRGB(35, 165, 170)
	local head, torso = rig:FindFirstChild("Head"), rig:FindFirstChild("UpperTorso")
	if head then
		accessory(head, "CapTop", Enum.PartType.Ball, Vector3.new(1.34, 0.9, 1.34), CFrame.new(0, 0.38, 0), AMBER)
		accessory(head, "CapBrim", Enum.PartType.Cylinder, Vector3.new(0.12, 1.5, 1.5), CFrame.new(0, 0.28, -0.12) * CFrame.Angles(0, 0, math.rad(90)), AMBER)
	end
	if torso then
		accessory(torso, "Apron", Enum.PartType.Block, Vector3.new(1.62, 1.55, 0.14), CFrame.new(0, -0.12, -0.52), TEAL)
		accessory(torso, "ApronPocket", Enum.PartType.Block, Vector3.new(0.8, 0.45, 0.16), CFrame.new(0, -0.48, -0.55), Color3.fromRGB(28, 130, 135))
	end
	local hum, hrp = rig:FindFirstChildOfClass("Humanoid"), rig:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then rig:Destroy() return nil end
	hrp.Anchored = true
	local standY = hum.HipHeight + hrp.Size.Y / 2
	-- at the rear end of the counter, a step out from the van's side, facing the customers
	local at = frame * CFrame.new(-2.6 * SCALE, 0, 4.7 * SCALE) * CFrame.Angles(0, math.pi, 0)
	rig:PivotTo(CFrame.new(at.Position + Vector3.new(0, standY, 0)) * (at - at.Position))
	rig.Parent = workspace
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local function play(id)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(a) end)
		if ok then track.Looped = true track:Play(0.2) return track end
	end
	task.spawn(function()
		local wave = play("rbxassetid://507770239")
		task.wait(2.5)
		if wave then wave:Stop(0.3) end
		play("rbxassetid://507766388")
	end)
	return rig
end

---------------------------------------------------------------- Caro's personality
-- While the van is open Caro chats (a bubble over her head every so often), turns and waves
-- at anyone who walks up, cheers when you buy something and waves goodbye at dawn.
local Players = game:GetService("Players")
local LINES = {
	"Night market's open! Deals the shop can't sell.", "Crates restock your rack. Rare paint never runs out.",
	"Mystery Crate tonight — one random rare inside.", "Stock's shared, sugar. First come, first served.",
	"Everything's gone at dawn. EVERYTHING.", "Late night fixing? Same.",
	"A Helper fixes while you sleep. Think about it.", "Rare stuff goes fast. Just saying.",
	"Cash only. Well, cash or Robux.", "Batteries! Tyres! Questionable paint!",
}
local THANKS = { "Pleasure doing business!", "Good pick!", "Ooh, that's a good one.", "Spend it wisely!", "You won't regret it. Probably." }
local function caroAnim(id, looped)
	local hum = caro and caro:FindFirstChildOfClass("Humanoid")
	local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
	if not animator then return end
	for _, t in animator:GetPlayingAnimationTracks() do t:Stop(0.25) end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok then return end
	track.Looped = looped or false
	track:Play(0.2)
	if not looped then
		track.Stopped:Once(function()
			if caro and caro.Parent then caroAnim("rbxassetid://507766388", true) end
		end)
	end
end
local saying = 0
local function caroSay(text, hold)
	local head = caro and caro:FindFirstChild("Head")
	if not head then return end
	local bb = head:FindFirstChild("Bubble")
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "Bubble"
		bb.Size = UDim2.fromOffset(230, 52)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 70
		local f = Instance.new("TextLabel")
		f.Name = "Label"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(35, 165, 170)
		f.TextColor3 = Color3.new(1, 1, 1)
		f.FontFace = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
		f.TextScaled = true
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 14)
		local s = Instance.new("UIStroke", f)
		s.Color = Color3.fromRGB(18, 19, 25)
		s.Thickness = 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local pad = Instance.new("UIPadding", f)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
		f.Parent = bb
		bb.Parent = head
	end
	saying += 1
	local mine = saying
	bb.Label.Text = text
	bb.Enabled = true
	task.delay(hold or 3, function()
		if saying == mine and bb.Parent then bb.Enabled = false end
	end)
end
-- turn to face a point (keeps her upright), then back to her counter pose
local caroHome
local function caroFace(pos)
	local hrp = caro and caro:FindFirstChild("HumanoidRootPart")
	if not (hrp and caroHome) then return end
	local p = caroHome.Position
	local flat = Vector3.new(pos.X, p.Y, pos.Z)
	if (flat - p).Magnitude < 0.5 then return end
	caro:PivotTo(CFrame.lookAt(p, flat))
end
local function caroLoop()
	caroHome = caro and caro:GetPivot()
	local greeted = {} -- [player] = when
	local nextLine = os.clock() + 6
	caroSay("Caro's Night Market! Deals the shop can't sell — gone at dawn.", 4)
	while caro and caro.Parent and M.state == "parked" do
		task.wait(0.4)
		if not (caro and caro.Parent) then break end
		local here = caroHome.Position
		local near
		for _, plr in Players:GetPlayers() do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - here).Magnitude < 16 then
				near = near or root
				if not greeted[plr] or os.clock() - greeted[plr] > 90 then
					greeted[plr] = os.clock()
					caroFace(root.Position)
					caroAnim("rbxassetid://507770239")
					caroSay(("Hey %s! Take a look."):format(plr.DisplayName), 3)
					nextLine = os.clock() + 9
				end
			end
		end
		if near then caroFace(near.Position) elseif caroHome then caro:PivotTo(caroHome) end
		if os.clock() > nextLine then
			nextLine = os.clock() + 16 + math.random() * 10
			caroSay(LINES[math.random(#LINES)], 2.8)
		end
	end
end
-- a purchase at her counter (ok = it went through; reason = why not)
function M.react(player, ok, reason)
	if not (caro and caro.Parent and M.state == "parked") then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then caroFace(root.Position) end
	if ok then
		caroAnim("rbxassetid://507770677")
		caroSay(THANKS[math.random(#THANKS)], 2.6)
	elseif reason and tostring(reason):lower():find("sold") then
		caroSay("Ah, that one's gone! Tomorrow maybe.", 2.6)
	else
		caroSay("Come back with a bit more cash!", 2.6)
	end
end

---------------------------------------------------------------- the van (or the stall)
local function buildStall(frame)
	-- no van model yet: a plain counter with an awning at the same spot
	local m = Instance.new("Model")
	m.Name = "CaroVan"
	local function part(name, size, offset, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = frame * offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = m
		return p
	end
	part("Counter", Vector3.new(9, 3.4, 2.6), CFrame.new(0, 1.7 + groundY(PARK_R) - frameAt(PARK_R, 0, 180).Position.Y, 0), Color3.fromRGB(35, 165, 170))
	part("CounterTop", Vector3.new(9.4, 0.3, 3.1), CFrame.new(0, 3.55, 0.25), Color3.fromRGB(245, 238, 222))
	part("Awning", Vector3.new(9.4, 0.3, 4.2), CFrame.new(0, 6.8, 0.8), Color3.fromRGB(255, 196, 61))
	for _, x in ipairs({ -4.4, 4.4 }) do part("Post", Vector3.new(0.3, 6.6, 0.3), CFrame.new(x, 3.3, 2.6), Color3.fromRGB(60, 64, 78)) end
	m.Parent = workspace
	return m
end

local function collectParts()
	local function find(name) return van:FindFirstChild(name, true) end
	local flap, shelf = find("Flap"), find("Shelf")
	wheels = {}
	for _, n in ipairs({ "WheelFL", "WheelFR", "WheelRL", "WheelRR" }) do
		local w = find(n)
		if w then table.insert(wheels, w) end
	end
	flapHome, shelfHome = flap and flap.CFrame, shelf and shelf.CFrame
	flapHinge = flap and flap.CFrame * CFrame.new(0, flap.Size.Y / 2, 0)
	shelfHinge = shelf and shelf.CFrame * CFrame.new(0, shelf.Size.Y / 2, 0)
	return flap, shelf
end

local function setLights(on)
	if not van then return end
	for _, d in van:GetDescendants() do
		if d:IsA("PointLight") then d.Enabled = on end
	end
end

-- Drive in, park, open up. Returns once the shop is open.
function M.arrive()
	if M.state ~= "gone" then return end
	M.state = "driving"
	local template = SS:FindFirstChild("CaroVan")
	if template then
		van = template:Clone()
		van.Name = "CaroVan"
		van:ScaleTo(van:GetScale() * SCALE)
		van.Parent = workspace
		spin = 0
		local frame0 = frameAt(START_R, 0, 180)
		van:PivotTo(frame0 * CFrame.Angles(0, math.pi, 0))
		local flap, shelf = collectParts()
		local pivot0 = frame0 * CFrame.Angles(0, math.pi, 0)
		relWheels = {}
		for _, w in wheels do relWheels[w] = pivot0:ToObjectSpace(w.CFrame) end
		-- (the hinges are measured at the start pose; they are re-based on the parked pose below)
		follow({ { r = START_R, lat = 0, psi = 180, speed = 0 }, { r = 62, lat = 0, psi = 180, speed = 22, sign = 1 }, { r = PARK_R, lat = 0, psi = 180, speed = 9, sign = 1 } })
		-- measure the hatch parts on the parked van
		local parked = parkedFrame() * CFrame.Angles(0, math.pi, 0)
		place(frameAt(PARK_R, 0, 180))
		flap, shelf = collectParts()
		task.wait(0.4)
		tween(0.9, function(a)
			swing(flap, flapHome, flapHinge, FLAP_OPEN * a)
			swing(shelf, shelfHome, shelfHinge, SHELF_OPEN * a)
		end)
	else
		van = buildStall(parkedFrame())
	end
	local frame = parkedFrame()
	caro = buildCaro(frame)
	if caro then task.delay(2.6, caroLoop) end
	-- the prompt over the counter
	local pp = Instance.new("Part")
	pp.Name = "CaroCounter"
	pp.Anchored, pp.CanCollide, pp.CanQuery, pp.CanTouch = true, false, false, false
	pp.Transparency = 1
	pp.Size = Vector3.new(4, 1, 1)
	pp.CFrame = frame * CFrame.new(0.4 * SCALE, 3.9 * SCALE, 4.2 * SCALE)
	pp.Parent = van
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = WARM, 22, 1.4, false
	light.Parent = pp
	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CaroShop"
	prompt.ActionText = "Browse deals"
	prompt.ObjectText = "Caro's Night Market — gone at dawn"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pp
	-- one clean sign over the van (plan/12): says what this is and why it matters, readable
	-- from anywhere in the plaza, and it replaces the wall of floating item text.
	local sign = Instance.new("BillboardGui")
	sign.Name = "MarketSign"
	sign.Adornee = pp
	sign.Size = UDim2.fromOffset(430, 130)
	sign.StudsOffset = Vector3.new(0, 5.2 * SCALE, 0)
	sign.MaxDistance = 260
	sign.LightInfluence = 0
	sign.ResetOnSpawn = false
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
	plate.BackgroundTransparency = 0.08
	Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 14)
	local plateStroke = Instance.new("UIStroke", plate)
	plateStroke.Color, plateStroke.Thickness = Color3.fromRGB(255, 196, 61), 3
	plate.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.52)
	title.BackgroundTransparency = 1
	title.Text = "CARO'S NIGHT MARKET"
	title.TextColor3 = Color3.fromRGB(255, 196, 61)
	title.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	title.TextScaled = true
	local ts = Instance.new("UIStroke", title)
	ts.Color, ts.Thickness = Color3.fromRGB(18, 19, 25), 2.5
	title.Parent = plate
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.36)
	sub.Position = UDim2.fromScale(0, 0.56)
	sub.BackgroundTransparency = 1
	sub.Text = "Deals every night — gone at dawn"
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
	sub.TextScaled = true
	sub.Parent = plate
	sign.Parent = pp
	M.state = "parked"
end

-- Close up, back out, turn round and drive away.
function M.leave()
	if M.state ~= "parked" then return end
	M.state = "driving"
	if prompt then prompt.Enabled = false end
	if caro then
		-- a wave goodbye before she shuts up shop
		if caroHome then caro:PivotTo(caroHome) end
		caroAnim("rbxassetid://507770239")
		caroSay("Sun's up! See you tomorrow night!", 2.2)
		task.wait(2.2)
		for _, d in caro:GetDescendants() do
			if d:IsA("BasePart") then d.Transparency = 1 end
		end
		caro:Destroy()
		caro = nil
	end
	local flap, shelf = van:FindFirstChild("Flap", true), van:FindFirstChild("Shelf", true)
	if flap and shelf and flapHome then
		tween(0.8, function(a)
			swing(flap, flapHome, flapHinge, FLAP_OPEN * (1 - a))
			swing(shelf, shelfHome, shelfHinge, SHELF_OPEN * (1 - a))
		end)
		task.wait(0.3)
		-- a short K-turn out of the bay, then off along the lane
		follow({
			{ r = PARK_R, lat = 0, psi = 180, speed = 0 },
			{ r = 44.5, lat = 0.3, psi = 190, speed = 6, sign = -1 }, { r = 47.5, lat = 1.6, psi = 205, speed = 6, sign = -1 },
			{ r = 50.5, lat = 3.8, psi = 222, speed = 6, sign = -1 }, { r = 52.5, lat = 6.2, psi = 238, speed = 6, sign = -1 },
			{ r = 51.5, lat = 4.2, psi = 262, speed = 8, sign = 1 }, { r = 51.7, lat = 1.2, psi = 295, speed = 8, sign = 1 },
			{ r = 53.4, lat = -0.7, psi = 330, speed = 8, sign = 1 }, { r = 57, lat = -0.9, psi = 352, speed = 10, sign = 1 },
			{ r = 64, lat = -0.2, psi = 360, speed = 16, sign = 1 }, { r = START_R + 6, lat = 0, psi = 360, speed = 22, sign = 1 },
		})
	end
	if van then van:Destroy() end
	van, prompt, relWheels = nil, nil, {}
	M.state = "gone"
end

return M
