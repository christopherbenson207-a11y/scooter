-- The game's UI style (fix-my-scooter/plan/09-UI-STYLE.md): chunky glossy "simulator" panels to match the 3D icons. One place for every colour, font, size
-- and icon, used by the Edit-time kit (ServerStorage.ShopTicketKit) that stamps the authored UI and by the
-- client for the few things that move. Change a token here, re-run the kit, and the whole game follows.

local TweenService = game:GetService("TweenService")

local S = {}

local rgb = Color3.fromRGB
S.Color = {
	Ink = rgb(18, 19, 25), -- every outline, text on paper
	Paper = rgb(245, 238, 222), -- things you read; text on enamel
	PaperLine = rgb(222, 212, 192), -- rules, perforations, empty bars on paper
	PaperSoft = rgb(104, 98, 88), -- quiet text on paper
	Enamel = rgb(60, 64, 78), -- HUD readouts, spec plates, menu buttons
	EnamelWell = rgb(40, 43, 54), -- tracks, wells, empty pips on enamel
	EnamelLine = rgb(86, 91, 108), -- rivets, dividers, disabled buttons
	EnamelSoft = rgb(178, 182, 196), -- quiet text on enamel
	Cash = rgb(88, 190, 96), -- money, buy, confirm, fix done
	Stop = rgb(224, 86, 74), -- leave, not today, close, angry
	Safety = rgb(255, 196, 61), -- look here: affordable goal, Hang on!, stars
	Teal = rgb(35, 165, 170), -- headers, ticket stubs; as a button it means Robux
	Mint = rgb(110, 215, 195), -- teal on dark: owned pips, the "after" stat, the day bar
	Sky = rgb(58, 150, 245), -- the clock by day
	Night = rgb(98, 82, 205), -- the clock at night
	Gold = rgb(255, 184, 40), -- menu squares, a goal you can afford
	Goal = rgb(170, 95, 235), -- the next-goal tag
	White = rgb(255, 255, 255), -- text on glossy fills (with an Ink text stroke)
	Track = rgb(34, 30, 52), -- empty bars
	-- One palette for every panel (owner, 23 Oct: mixed colours didn't blend). Colour only where it means something.
	Panel = rgb(236, 238, 246), -- every HUD panel, card and menu square (matches the garage's navy trim)
	Band = rgb(58, 150, 245), -- title bands and insets on a Panel
	Orange = rgb(255, 140, 30), -- title tabs on white panels
	OnPanel = rgb(40, 44, 62), -- text straight on a Panel (dark, no outline: panels are light)
	StarOff = rgb(70, 74, 96), -- ImageColor3 on a star not earned yet
}

local FAM = "rbxasset://fonts/families/"
S.Font = {
	Chunky = Font.new(FAM .. "FredokaOne.json", Enum.FontWeight.Regular), -- 24 Oct: owner asked to change DenkOne (23 Oct pick); Fredoka One
	Ext = Font.new(FAM .. "BuilderExtended.json", Enum.FontWeight.Bold), -- short caps words only
	Sans = Font.new(FAM .. "BuilderSans.json", Enum.FontWeight.ExtraBold), -- buttons
	Body = Font.new(FAM .. "FredokaOne.json", Enum.FontWeight.Regular), -- text
	Mono = Font.new(FAM .. "BuilderMono.json", Enum.FontWeight.Bold), -- all money and timers
}

-- role = { font, design px }
S.Type = {
	Stamp = { S.Font.Ext, 26 },
	Title = { S.Font.Chunky, 28 },
	Big = { S.Font.Chunky, 26 },
	Number = { S.Font.Chunky, 22 },
	ButtonL = { S.Font.Chunky, 24 },
	ButtonM = { S.Font.Chunky, 20 },
	Text = { S.Font.Body, 18 },
	Label = { S.Font.Chunky, 18 },
}

S.Gloss = { Top = 0.1, Foot = -0.07, Shine = 0.72, RestShine = 0.55, Hover = 0.12, HoverScale = 1.06 } -- flat at rest, pops on hover (owner, 23 Oct)

-- k > 0 lightens toward white, k < 0 darkens
function S.tone(c, k)
	if k >= 0 then return c:Lerp(Color3.new(1, 1, 1), k) end
	return c:Lerp(Color3.fromRGB(12, 12, 20), -k)
end

-- The glossy fill for a coloured surface: a bright band on the top half, a hard step, then base to a darker foot.
-- Put it on a UIGradient (Rotation 90) over a white BackgroundColor3.
-- lift > 0 brightens the whole fill (hover).
function S.glossColors(base, lift)
	base = lift and S.tone(base, lift) or base
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, S.tone(base, S.Gloss.Top + 0.04)),
		ColorSequenceKeypoint.new(0.46, S.tone(base, S.Gloss.Top * 0.5)),
		ColorSequenceKeypoint.new(0.5, base),
		ColorSequenceKeypoint.new(1, S.tone(base, S.Gloss.Foot)),
	})
end

S.Radius = { Small = 4, Button = 8, Card = 8, Panel = 10, Square = 10 } -- squared off, slight rounding (owner, 23 Oct)
S.Stroke = { World = 2.5, Inside = 2, Text = 2.5 } -- dark Ink outlines on everything, like the owner's reference games (23 Oct)
S.Space = { 4, 8, 12, 16, 24, 32 }
S.Edge = 16 -- from the screen edges and inside panels
S.Button = { L = 52, M = 44, Shadow = 4, Press = 3, ShadowAlpha = 0.6 }
S.Canvas = Vector2.new(1280, 720) -- every screen is authored at this size

-- HUD icons. Owner's direction (23 Oct): chunky, glossy 3D / 2.5D "simulator" icons with a thick dark outline,
-- like Coin, Cash and Cart. Sun..Wrench are Microsoft Fluent 3D (MIT, fix-my-scooter/ui/fluent) until swapped.
S.Icon = {
	Coin = "rbxassetid://15589362394", -- Toolbox decal 15589362420 (owner's pick)
	Cash = "rbxassetid://140328458522143", -- Toolbox decal 71562500655686, the cash pill (owner's pick)
	Shop = "rbxassetid://79659521983541", -- Toolbox decal 15455565647 (3D basket), re-uploaded, the shop button (owner's pick)
	Sun = "rbxassetid://125462125891529", -- owner's pick, Toolbox decal 14172517052, re-uploaded (fix-my-scooter/ui/toolbox/DaySun.png)
	Moon = "rbxassetid://108533117681150", -- owner's pick, Toolbox decal 80243917018062, re-uploaded (DayMoon.png)
	Star = "rbxassetid://132192590966199", -- owner's pick, Toolbox decal 131259989203883, re-uploaded (ui/toolbox/Star0.png)
	StarOff = "rbxassetid://132192590966199", -- the same star, tinted dark where it's used (S.Color.StarOff)
	Tick = "rbxassetid://121359906429109",
	Cross = "rbxassetid://118032298655764", -- owner's pick (close button), Toolbox decal 134075841517020, re-uploaded (ui/toolbox/Close.png)
	Padlock = "rbxassetid://121947701258566", -- owner's pick, Toolbox decal 78846836707882, re-uploaded (Padlock.png)
	Gear = "rbxassetid://140202599362118",
	-- 23 Oct icon batch (ui/toolbox/icon-batch-23oct.json); Timer is the owner's Toolbox pick, the rest are renders (see below)
	Wrench = "rbxassetid://109234783379462", -- render: WrenchWall (owner chose renders over the Toolbox pick, 23 Oct)
	Battery = "rbxassetid://108336359066090", -- render: Battery
	PaintCan = "rbxassetid://127983633947100", -- render: PaintCan
	Wires = "rbxassetid://118225052286927", -- render: WireKit
	Bulb = "rbxassetid://94845625993905", -- render: Bulb
	Timer = "rbxassetid://75647735250742", -- decal 138822569463511
	-- rendered in Blender from the game's own models with ink lines + outline (owner: "the needed ones u can render",
	-- "outline them make them look like icons"): fix-my-scooter/ui/make_previews.py -> ui/toolbox/Render<Name>.png
	Pump = "rbxassetid://107742539267474", -- AirPump
	Tyre = "rbxassetid://131282895298715",
	TyreRack = "rbxassetid://117156889065899",
	Bench = "rbxassetid://117590544700840", -- Workbench
	Belt = "rbxassetid://71910993225380", -- Conveyor
	Bin = "rbxassetid://71989038826512", -- TrashBin
	Bucket = "rbxassetid://113914199706800", -- RustBucket
	PaintBooth = "rbxassetid://140150861857876",
	Nitro = "rbxassetid://104966687686369", -- NitroKit
	Charger = "rbxassetid://78744578241257",
	BatteryDock = "rbxassetid://73236308665413", -- BatteryStation render
	PaintBlue = "rbxassetid://79079625606984", -- the paint can render, recoloured
	PaintYellow = "rbxassetid://117433664806980",
	-- the scooters, keyed by Config.Scooters name without spaces
	Pebble = "rbxassetid://121293237653429",
	Zippy = "rbxassetid://86473524173272",
	BoltX = "rbxassetid://100692200098518",
}

-- Shapes UICorner can't make, drawn by fix-my-scooter/ui/make_ui_shapes.py at 2x
S.Shape = {
	TagBody = "rbxassetid://76939422594227", -- 218 x 72 incl. a 6 px margin
	TagReady = "rbxassetid://119801134315213", -- same, with the Safety Yellow ring
}

---------------------------------------------------------------- runtime helpers

-- The design-px to screen factor for this viewport (phones get a 993 x 459 canvas).
function S.fitScale(viewport)
	if math.min(viewport.X, viewport.Y) < 600 then return 0.85 end
	return math.clamp(viewport.Y / S.Canvas.Y, 0.9, 1.5)
end

-- One UIScale on the ScreenGui, kept in step with the window.
function S.fit(screenGui)
	local scale = screenGui:FindFirstChild("Fit")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Fit"
		scale.Parent = screenGui
	end
	local camera = workspace.CurrentCamera
	local function update() scale.Scale = S.fitScale(camera.ViewportSize) end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	return scale
end

-- Kit buttons are a Frame holding a Shadow and a Button that sits on it; pressing pushes the face down onto
-- the shadow. Wire every kit button in a ScreenGui once.
local QUICK = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
function S.wirePress(holder)
	local face = holder:FindFirstChild("Button")
	if not face or holder:GetAttribute("Wired") then return end
	holder:SetAttribute("Wired", true)
	local up = face.Position
	local down = up + UDim2.fromOffset(0, S.Button.Press)
	local scale = face:FindFirstChild("Press") or Instance.new("UIScale")
	scale.Name = "Press"
	scale.Parent = face
	local gloss, shine = face:FindFirstChild("Gloss"), face:FindFirstChild("Shine")
	local hovering = false
	-- flat at rest; on hover it grows a touch, brightens and gets its full shine back
	local function setHover(on)
		hovering = on
		TweenService:Create(scale, SPRING, { Scale = on and S.Gloss.HoverScale or 1 }):Play()
		local base = face:GetAttribute("Base")
		if gloss and base then gloss.Color = S.glossColors(base, on and S.Gloss.Hover or nil) end
		if shine then TweenService:Create(shine, QUICK, { BackgroundTransparency = on and 0 or S.Gloss.RestShine }):Play() end
	end
	face.MouseEnter:Connect(function() setHover(true) end)
	face.MouseLeave:Connect(function()
		TweenService:Create(face, SPRING, { Position = up }):Play()
		setHover(false)
	end)
	face.MouseButton1Down:Connect(function()
		if not face.Active then return end
		TweenService:Create(face, QUICK, { Position = down }):Play()
		TweenService:Create(scale, QUICK, { Scale = 0.95 }):Play()
	end)
	face.MouseButton1Up:Connect(function()
		TweenService:Create(face, SPRING, { Position = up }):Play()
		TweenService:Create(scale, SPRING, { Scale = hovering and S.Gloss.HoverScale or 1 }):Play()
	end)
end

function S.wireAll(screenGui)
	for _, d in screenGui:GetDescendants() do
		if d:GetAttribute("KitButton") then S.wirePress(d) end
	end
	screenGui.DescendantAdded:Connect(function(d)
		if d:GetAttribute("KitButton") then task.defer(S.wirePress, d) end
	end)
end

-- Money as the HUD shows it: 12,480
function S.money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return S
