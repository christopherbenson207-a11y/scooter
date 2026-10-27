-- The bigger pieces of the fix minigames, kept out of ScooterClient (that script is
-- close to Studio's 200,000-character limit). ScooterClient requires this as
-- Config.Mini and calls init() once with its helpers.
--   crane(bay, m, opts)        the overhead crane carries a scooter between the bench and a bay
--   dirty(m, remember)         a scooter caked in mud (done when it arrives)
--   wash(bay, m, step, jetMul) the pressure-wash minigame in the wash bay
--   holder(tool, body, nozzle) a hand tool held low on the right of the view, aimed at a point
--   wires(light, rim, step)    the junction box on a broken light: drag each wire to its colour
--   ring(center, radius)       the "circle round the wheel" guide, its dots fill as you go
--   paintSamples(m, panels)    the spots on each panel a painter can reach (for coverage)
--   painter(booth, m, cans)    first person in the paint booth: grab(can), paint(o), finish()
--   paintGrade(m, q)           the "EXCELLENT WORK" badge over a freshly painted scooter
--   rust(bay, m, o)            the rusty-parts job in the wash bay: sponge and foam, then the lance
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local M = {}
local ctx -- Config, P, input(), press(), sfx, SFX, puff, sparkle, setInstruction, orig(), cleanColor(m, p)

function M.init(c)
	ctx = c
end

local GREEN = Color3.fromRGB(88, 190, 96)
local RED = Color3.fromRGB(225, 70, 70)
local DOWN = CFrame.Angles(0, 0, -math.pi / 2) -- an attachment whose X axis points down: beams sag

local function smoothstep(a) return a * a * (3 - 2 * a) end
local function smootherstep(a) return a * a * a * (a * (a * 6 - 15) + 10) end
local function smootherAccel(a) return 60 * a * (1 - a) * (1 - 2 * a) end -- smootherstep's second derivative
local function damp(rate, dt) return 1 - math.exp(-rate * dt) end -- the same feel at any frame rate

-- Run fn(alpha 0..1, dt) every frame for `duration` seconds.
local function tween(duration, fn)
	local t = 0
	while true do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		local a = math.min(1, t / duration)
		fn(a, dt)
		if a >= 1 then return end
	end
end

local function part(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return p
end
local function ball(name, d, color, material)
	local p = part(name, Vector3.one, color, material)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(d, d, d)
	return p
end

local function shuffled(n)
	local t = {}
	for i = 1, n do t[i] = i end
	for i = n, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

---------------------------------------------------------------- crane
-- The trolley runs along the bay's rail; the hook hangs from it on its cable and the
-- load swings like a real one (it lags when the trolley sets off, swings on when it
-- stops, and settles before it's put down). The camera pulls back to a wide view of
-- the bench and the bay and turns to follow the scooter.
local CRANE = {
	Speed = 11, -- average studs a second along the rail
	HookSpeed = 6.5, -- studs a second, up and down
	Gravity = 140, -- how hard a swinging load pulls back under the trolley
	Damping = 2.4, -- how fast a swing dies away
	MaxSwing = math.rad(12),
	Clear = 0.8, -- gap over the bay walls while carrying
	Park = 2.2, -- the idle hook hangs this far under the rail
}
local trips = setmetatable({}, { __mode = "k" }) -- [bay] = trip number; a new trip stops the last one's tidy-up

-- A wide view that sees the bench and the bay, from the open middle of the garage.
local function overview(a, b)
	local mid = (a + b) / 2
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local n = Vector3.new(-d.Z, 0, d.X).Unit
	if n:Dot(ctx.P.vec(Vector3.zAxis)) < 0 then n = -n end
	return Vector3.new(mid.X, mid.Y + 8, mid.Z) + n * (d.Magnitude * 0.45 + 3.5)
end

-- opts.to: where to put it down (default the bay's ScooterSpot); opts.home: send the
-- empty trolley back over the bench afterwards; opts.camera = false: leave the camera alone.
function M.crane(bay, m, opts)
	opts = opts or {}
	local camera = workspace.CurrentCamera
	local trolley, hook, tip, rail = bay.CraneTrolley, bay.CraneHook, bay.CraneHookTip, bay.CraneRail
	local tipOff = hook.CFrame:ToObjectSpace(tip.CFrame)
	local hookRot = hook.CFrame - hook.Position
	local trolleyRot = trolley.CFrame - trolley.Position
	local railY = trolley.Position.Y
	local look = rail.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z).Unit
	local axis = dir:Cross(Vector3.yAxis) -- a positive swing moves the load along dir
	local from = m:GetPivot()
	local rot = from - from.Position
	local to = opts.to or bay.ScooterSpot.CFrame
	local pickup = Vector3.new(from.X, railY, from.Z)
	local drop = Vector3.new(to.X, railY, to.Z)
	local bb, size = m:GetBoundingBox()
	local topOff = bb.Position.Y + size.Y / 2 - from.Y
	local bottomOff = bb.Position.Y - size.Y / 2 - from.Y
	local hang = topOff + 0.5 -- the hook sits this far over the scooter's pivot while it carries it
	local wallTop = bay.WallBack.Position.Y + bay.WallBack.Size.Y / 2
	local carryY = math.max(from.Y + hang, to.Y + hang, wallTop + CRANE.Clear + hang - bottomOff)
	carryY = math.min(carryY, railY - 0.8)
	local trip = (trips[bay] or 0) + 1
	trips[bay] = trip

	-- the moving parts: trolley on the rail, hook height, swing angle and its speed
	local s = { pos = Vector3.new(trolley.Position.X, railY, trolley.Position.Z), hookY = hook.Position.Y, acc = 0, phi = 0, w = 0, load = false }
	local function apply()
		trolley.CFrame = CFrame.new(s.pos) * trolleyRot
		local swing = CFrame.fromAxisAngle(axis, s.phi)
		local hookPos = s.pos + swing:VectorToWorldSpace(Vector3.new(0, s.hookY - railY, 0))
		hook.CFrame = CFrame.new(hookPos) * swing * hookRot
		tip.CFrame = hook.CFrame * tipOff
		if s.load then m:PivotTo(CFrame.new(hookPos) * swing * CFrame.new(0, -hang, 0) * rot) end
	end
	local function physics(dt)
		local len = math.max(0.6, railY - s.hookY + (s.load and hang or 0))
		s.w += (-(CRANE.Gravity / len) * math.sin(s.phi) - (s.acc / len) * math.cos(s.phi) - CRANE.Damping * s.w) * dt
		s.phi = math.clamp(s.phi + s.w * dt, -CRANE.MaxSwing, CRANE.MaxSwing)
		apply()
	end

	-- camera: eases out to the wide view, keeps the scooter in the middle
	local cam0 = camera.CFrame
	local view = opts.camera ~= false and overview(from.Position, to.Position)
	local focus = cam0.Position + cam0.LookVector * (cam0.Position - from.Position).Magnitude
	local camT = 0
	local function follow(dt)
		if not view then return end
		camT = math.min(1, camT + dt / 1.1)
		focus = focus:Lerp(m:GetPivot().Position + Vector3.new(0, 1, 0), damp(2.5 + 2.5 * camT, dt))
		camera.CFrame = CFrame.lookAt(cam0.Position:Lerp(view, smootherstep(camT)), focus)
	end

	-- every frame: fn(alpha, dt), then the swing and the camera. A tidy-up run (quiet)
	-- stops as soon as another trip starts on this bay.
	local function run(duration, fn, quiet)
		local t = 0
		while true do
			local dt = math.min(RunService.RenderStepped:Wait(), 1 / 20)
			if quiet and trips[bay] ~= trip then return false end
			t += dt
			local a = math.min(1, t / duration)
			if fn then fn(a, dt) end
			physics(dt)
			if not quiet then follow(dt) end
			if a >= 1 then return true end
		end
	end
	local function moveTrolley(target, quiet, hookTo)
		local p0, y0 = s.pos, s.hookY
		local d = target - p0
		if d.Magnitude < 0.05 and math.abs((hookTo or y0) - y0) < 0.05 then return true end
		local T = math.clamp(d.Magnitude / CRANE.Speed * 1.3, 0.35, 3)
		local along = d:Dot(dir)
		local ok = run(T, function(a)
			s.pos = p0:Lerp(target, smootherstep(a))
			s.acc = smootherAccel(a) * along / (T * T)
			if hookTo then s.hookY = y0 + (hookTo - y0) * smoothstep(a) end
		end, quiet)
		s.acc = 0
		return ok
	end

	-- 1. the trolley rolls over the scooter and the hook comes straight down onto it
	ctx.sfx(ctx.SFX.Tap, 0.5, 0.6)
	moveTrolley(pickup, false, railY - CRANE.Park)
	local grabY = from.Y + hang
	local y0 = s.hookY
	run(math.clamp((y0 - grabY) / CRANE.HookSpeed, 0.3, 1.1), function(a, dt)
		s.hookY = y0 + (grabY - y0) * smoothstep(a)
		local k = 1 - damp(4, dt)
		s.phi *= k
		s.w *= k
	end)

	-- 2. two straps clip on, front then back
	local straps = {}
	local anchor = m:FindFirstChild("Deck") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	for i, sx in { 0.32, -0.32 } do
		local at = from * Vector3.new(size.X * sx, 0, 0)
		local a0 = Instance.new("Attachment")
		a0.Name = "CraneStrap"
		a0.Parent = anchor
		a0.WorldPosition = Vector3.new(at.X, from.Y + topOff - 0.9, at.Z)
		local a1 = Instance.new("Attachment")
		a1.Name = "CraneStrap"
		a1.Position = Vector3.new(0, -0.17, 0)
		a1.Parent = hook
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = 0.12, 0.12
		beam.FaceCamera = true
		beam.Segments = 2
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40))
		beam.Transparency = NumberSequence.new(0)
		beam.Parent = hook
		table.insert(straps, { a0, a1, beam })
		ctx.sfx(ctx.SFX.Tap, 0.7, 0.9 + i * 0.2)
		run(0.16)
	end

	-- 3. up, along the rail, and down: it sets off before it's all the way up and starts
	-- coming down as it arrives, like a crane driver would
	s.load = true
	local liftT = math.clamp((carryY - grabY) / CRANE.HookSpeed, 0.45, 1.2)
	local D = drop - pickup
	local travelT = math.clamp(D.Magnitude / CRANE.Speed * 1.3, 0.6, 3)
	local landY = to.Y + hang
	local lowerT = math.clamp((carryY - landY) / CRANE.HookSpeed, 0.5, 1.4)
	local goAt = liftT * 0.6
	local downAt = math.max(liftT, goAt + travelT * 0.8)
	local along = D:Dot(dir)
	ctx.sfx(ctx.SFX.Tap, 0.6, 0.55)
	run(downAt + lowerT, function(a, dt)
		local t = a * (downAt + lowerT)
		if t < liftT then
			s.hookY = grabY + (carryY - grabY) * smoothstep(t / liftT)
		elseif t < downAt then
			s.hookY = carryY
		else
			s.hookY = carryY + (landY - carryY) * smoothstep(math.min(1, (t - downAt) / lowerT))
		end
		local u = math.clamp((t - goAt) / travelT, 0, 1)
		s.pos = pickup:Lerp(drop, smootherstep(u))
		s.acc = (u > 0 and u < 1) and smootherAccel(u) * along / (travelT * travelT) or 0
		-- the swing dies away as it comes down to land
		local landing = math.clamp((t - downAt) / lowerT, 0, 1)
		if landing > 0.3 then
			local k = 1 - damp(14 * landing, dt)
			s.phi *= k
			s.w *= k
		end
	end)
	s.acc, s.phi, s.w = 0, 0, 0
	apply()
	s.load = false
	m:PivotTo(CFrame.new(to.Position) * rot)
	ctx.sfx(ctx.SFX.Tap, 0.7, 0.6)
	ctx.puff(to.Position + Vector3.new(0, 0.2, 0), nil, 5)
	run(0.2, function(a)
		m:PivotTo(CFrame.new(to.Position - Vector3.new(0, math.sin(a * math.pi) * 0.06, 0)) * rot)
	end)
	m:PivotTo(CFrame.new(to.Position) * rot)
	for _, st in straps do
		for _, x in st do x:Destroy() end
	end
	ctx.sfx(ctx.SFX.Tap, 0.6, 1.1)

	-- 4. the empty hook goes back up (and the trolley home) while you get on with it
	task.spawn(function()
		local y1 = s.hookY
		local park = railY - CRANE.Park
		if not run(0.6, function(a) s.hookY = y1 + (park - y1) * smoothstep(a) end, true) then return end
		if opts.home then moveTrolley(pickup, true) end
	end)
end

---------------------------------------------------------------- mud
-- Mud is shot onto the scooter with rays from both sides (a little from above), so
-- every splatter sits on a real surface. Each one is a wet blob with a drier crust in
-- the middle and flecks thrown out round it (each laid onto the surface); on the side
-- panels some have a drip running down. The wheels throw it up, so there's lots low
-- down and less higher up. Panels get a light muddy film as well.
local WET = { Color3.fromRGB(74, 52, 34), Color3.fromRGB(88, 62, 40), Color3.fromRGB(64, 46, 31) }
local DRY = { Color3.fromRGB(140, 110, 76), Color3.fromRGB(152, 122, 86), Color3.fromRGB(126, 98, 66) }
local CRUST = Color3.fromRGB(168, 138, 102)
local FILM = Color3.fromRGB(96, 72, 48)
local NO_MUD = { Light = true, LightRim = true, Light2 = true, LightRim2 = true, Screen = true, Grip = true, Handlebar = true, Bolt1 = true, Bolt2 = true, Bolt3 = true }
local mudOn = setmetatable({}, { __mode = "k" }) -- [splatter] = the part it's stuck to
local function filmed(p) -- panels that get a muddy film (and lose their grime in the wash)
	local n = p.Name
	return n:match("^Deck") or n:match("Fender") or n == "Stem" or n == "BatteryBay" or n:match("^Tyre") or n:match("^HandGuard") or n == "Seat"
end

local function blob(model, name, cf, w, h, color, wet)
	local p = part(name, Vector3.one, color, wet and Enum.Material.SmoothPlastic or Enum.Material.Sand)
	p.Reflectance = wet and 0.07 or 0
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(w, h, 0.06)
	mesh.Parent = p
	p.CFrame = cf
	p.Parent = model
	return p
end

-- One splatter where `hit` landed. onto(pos, normal) finds the surface near a point.
local function splatter(m, hit, onto)
	local n = hit.Normal
	local wet = math.random() < 0.6
	local color = wet and WET[math.random(#WET)] or DRY[math.random(#DRY)]
	local model = Instance.new("Model")
	model.Name = "Mud"
	local d = 0.22 + math.random() * 0.26
	local face = CFrame.lookAt(hit.Position + n * 0.015, hit.Position + n) * CFrame.Angles(0, 0, math.random() * math.pi * 2)
	local core = blob(model, "Core", face, d * (1 + math.random() * 0.45), d, color, wet)
	blob(model, "Crust", face * CFrame.new((math.random() - 0.5) * d * 0.2, (math.random() - 0.5) * d * 0.2, -0.01), d * 0.55, d * 0.42, color:Lerp(CRUST, wet and 0.35 or 0.5), false)
	for _ = 1, math.random(2, 5) do
		local a = math.random() * math.pi * 2
		local r = d * (0.55 + math.random() * 0.75)
		local at, nn = onto((face * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0)).Position, n)
		if at then
			local s = 0.035 + math.random() * 0.07
			blob(model, "Fleck", CFrame.lookAt(at + nn * 0.012, at + nn), s, s * (0.6 + math.random() * 0.5), color, wet)
		end
	end
	-- a drip running down a side panel
	if math.abs(n.Y) < 0.55 and math.random() < 0.45 then
		local down = (Vector3.new(0, -1, 0) + n * n.Y).Unit
		local len = 0.22 + math.random() * 0.3
		local at, nn = onto(hit.Position + down * (d * 0.35 + len / 2), n)
		if at then
			blob(model, "Drip", CFrame.fromMatrix(at + nn * 0.012, down:Cross(nn).Unit, down), 0.07 + math.random() * 0.05, len, color, true)
		end
	end
	model.WorldPivot = core.CFrame
	model.Parent = m
	mudOn[model] = hit.Instance
end

function M.dirty(m, remember)
	local parent = m.Parent
	m.Parent = workspace -- rays only hit things in the world
	local pivot = m:GetPivot()
	local parts, film = {}, {}
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			table.insert(parts, p)
			local c, h = pivot:PointToObjectSpace(p.Position), p.Size / 2
			lo, hi = lo:Min(c - h), hi:Max(c + h)
			if filmed(p) then
				remember(p)
				p.Color = p.Color:Lerp(FILM, 0.28)
				film[p] = 0
			end
		end
	end
	local box, size = pivot * CFrame.new((lo + hi) / 2), hi - lo
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local function onto(pos, n)
		local hit = workspace:Raycast(pos + n * 0.35, -n * 0.7, params)
		if hit and not NO_MUD[hit.Instance.Name] and hit.Normal:Dot(n) > 0.4 then return hit.Position, hit.Normal end
		return nil
	end
	local reach = size.Magnitude + 2
	local function shoot(u, v, side, only)
		local view = Vector3.new((math.random() - 0.5) * 0.6, 0.15 + math.random() * 0.4, side).Unit
		local target = box * Vector3.new(u, v, 0)
		local origin = target + box:VectorToWorldSpace(view) * reach
		local hit = workspace:Raycast(origin, (target - origin).Unit * reach * 2, params)
		if not hit or NO_MUD[hit.Instance.Name] or (only and hit.Instance ~= only) then return end
		splatter(m, hit, onto)
		if film[hit.Instance] then film[hit.Instance] += 1 end
	end
	local COLS, ROWS = 16, 9
	for _, side in { 1, -1 } do
		for i = 1, COLS do
			for j = 1, ROWS do
				local up = (j - 0.5 + (math.random() - 0.5)) / ROWS
				if math.random() < 0.15 + up * 0.75 then continue end -- less mud higher up
				shoot(((i - 0.5 + (math.random() - 0.5)) / COLS - 0.5) * size.X, (up - 0.5) * size.Y, side)
			end
		end
	end
	-- every muddy panel gets a couple of splatters, so none is brown on its own
	for p in film do
		for _ = 1, 8 do
			if film[p] >= 2 then break end
			local c = box:PointToObjectSpace(p.Position + (Vector3.new(math.random(), math.random(), math.random()) - Vector3.one * 0.5) * p.Size * 0.6)
			shoot(c.X, c.Y, math.random() < 0.5 and 1 or -1, p)
		end
	end
	m.Parent = parent
end

---------------------------------------------------------------- held tools
-- A hand tool held low on the right of your view with its nozzle on `at`, like holding
-- it yourself: it never covers what you're aiming at. update(dt, at) every frame;
-- put(time) hangs it back where it came from.
local GRIP = Vector3.new(1.35, -1.1, -2.7) -- right, down and ahead of the camera
function M.holder(tool, body, nozzle)
	local camera = workspace.CurrentCamera
	local home = tool:GetPivot()
	local bodyOff = home:ToObjectSpace(body.CFrame)
	local nozzleDir = body.CFrame:VectorToObjectSpace((nozzle.Position - body.Position).Unit)
	local fix = CFrame.fromRotationBetweenVectors(nozzleDir, Vector3.new(0, 0, -1))
	local cur = home
	local function update(dt, at)
		local grip = camera.CFrame * GRIP
		cur = cur:Lerp(CFrame.lookAt(grip, at) * fix * bodyOff:Inverse(), damp(16, dt))
		tool:PivotTo(cur)
	end
	local function put(time)
		local from = tool:GetPivot()
		tween(time or 0.35, function(a)
			local p = from.Position:Lerp(home.Position, smoothstep(a)) + Vector3.new(0, math.sin(a * math.pi) * 0.6, 0)
			tool:PivotTo(CFrame.new(p) * (from - from.Position):Lerp(home - home.Position, smoothstep(a)))
		end)
		tool:PivotTo(home)
	end
	return update, put
end

---------------------------------------------------------------- washing
-- Hold to spray. The jet lands exactly where you point and blasts off the mud under
-- it; each panel's film goes as its splatters go, with a ding and a glint when it's
-- spotless. When the side facing you is clean the turntable spins the scooter round
-- for the other side; the last few splatters glow so they're easy to find. Then a
-- final rinse takes off the last film and the old grime, and the turntable brings it
-- back round the right way.
local JET = { Radius = 0.5, Rate = 5 } -- studs (x the washer's jet level); splatter strength a second
function M.wash(bay, m, step, jetMul)
	local camera = workspace.CurrentCamera
	jetMul = jetMul or 1
	local lance = bay.Lance
	local hold, put = M.holder(lance, lance.GunBody, lance.Nozzle)
	local center = bay.ScooterSpot.Position
	local turning = {} -- the turntable top and its markings
	for _, d in bay:GetChildren() do
		if d:IsA("BasePart") and d.Name:match("^Turntable") and d.Name ~= "TurntableRim" then table.insert(turning, d) end
	end

	-- the scooter's solid parts, the panels with a film, and the splatters
	local solid, panels, splats = {}, {}, {}
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			table.insert(solid, p)
			-- a rusty part keeps its rust colour: that's the rust job's to clean
			if filmed(p) and p.Material ~= Enum.Material.CorrodedMetal then panels[p] = { from = p.Color, to = ctx.cleanColor(m, p), n = 0, of = 0, rinse = 0 } end
		end
	end
	for _, s in m:GetChildren() do
		local core = s.Name == "Mud" and s:IsA("Model") and s:FindFirstChild("Core")
		if core then
			local list = {}
			for _, d in s:GetChildren() do
				if d:IsA("BasePart") then table.insert(list, d) end
			end
			local mesh = core:FindFirstChildOfClass("SpecialMesh")
			local on = mudOn[s]
			table.insert(splats, { model = s, core = core, parts = list, size = mesh and mesh.Scale.X or 0.3, hp = 1, on = on })
			if on and panels[on] then
				panels[on].n += 1
				panels[on].of += 1
			end
		end
	end
	local total = math.max(1, #splats)
	local left = #splats
	local seeParams = RaycastParams.new()
	seeParams.FilterType = Enum.RaycastFilterType.Include
	seeParams.FilterDescendantsInstances = solid
	-- the splatters you can see from here (the rest are round the other side)
	local function inView()
		local eye = camera.CFrame.Position
		local list = {}
		for _, e in splats do
			if not e.gone then
				local to = e.core.Position - eye
				local hit = workspace:Raycast(eye, to, seeParams)
				if not hit or (hit.Position - eye).Magnitude >= to.Magnitude - 0.2 then table.insert(list, e) end
			end
		end
		return list
	end

	-- the jet hits the scooter or the bay; the lance never gets in the way
	local world = table.clone(solid)
	for _, d in bay:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not d:IsDescendantOf(lance) then table.insert(world, d) end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = world

	local fromAt = Instance.new("Attachment")
	fromAt.Parent = lance.Nozzle
	local hitAt = Instance.new("Attachment")
	hitAt.Parent = workspace.Terrain
	local jet = Instance.new("Beam")
	jet.Attachment0, jet.Attachment1 = fromAt, hitAt
	jet.Width0, jet.Width1 = 0.05, 0.26 * jetMul
	jet.Segments = 6
	jet.FaceCamera = true
	jet.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(170, 215, 255))
	jet.Transparency = NumberSequence.new(0.1, 0.45)
	jet.LightEmission = 0.5
	jet.Enabled = false
	jet.Parent = lance.Nozzle
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(225, 242, 255))
	mist.Size = NumberSequence.new(0.15, 0.55)
	mist.Transparency = NumberSequence.new(0.35, 1)
	mist.Lifetime = NumberRange.new(0.2, 0.4)
	mist.Speed = NumberRange.new(2, 4)
	mist.SpreadAngle = Vector2.new(70, 70)
	mist.Rate = 45
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Enabled = false
	mist.Parent = hitAt
	local drops = Instance.new("ParticleEmitter")
	drops.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
	drops.LightEmission = 0.3
	drops.Size = NumberSequence.new(0.07, 0.03)
	drops.Lifetime = NumberRange.new(0.35, 0.55)
	drops.Speed = NumberRange.new(4, 7)
	drops.SpreadAngle = Vector2.new(55, 55)
	drops.Acceleration = Vector3.new(0, -45, 0)
	drops.Rate = 70
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Enabled = false
	drops.Parent = hitAt
	local hiss = Instance.new("Sound")
	hiss.SoundId = "rbxasset://sounds/action_swim.mp3"
	hiss.Looped = true
	hiss.Volume = 0
	hiss.PlaybackSpeed = 1.35
	hiss.Parent = camera
	hiss:Play()

	-- mud running off a splatter as it goes
	local function runoff(at, color)
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new(0.12, 0.04)
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(1, 2.5)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = Vector3.new(0, -40, 0)
		e.Enabled = false
		e.Parent = a
		e:Emit(7)
		task.delay(0.8, function() a:Destroy() end)
	end
	local function gone(e)
		e.gone = true
		left -= 1
		local pan = e.on and panels[e.on]
		if pan then pan.n -= 1 end
		e.model:Destroy()
		return pan
	end

	-- the turntable spins the scooter round on the spot
	local turned = 0
	local function spin(angle, time)
		local from = m:GetPivot()
		local start = {}
		for _, p in turning do start[p] = p.CFrame end
		ctx.sfx(ctx.SFX.Tap, 0.6, 0.6)
		tween(time, function(a)
			local r = CFrame.new(center) * CFrame.Angles(0, angle * smootherstep(a), 0) * CFrame.new(-center)
			m:PivotTo(r * from)
			for p, cf in start do p.CFrame = r * cf end
		end)
		turned += angle
		ctx.sfx(ctx.SFX.Tap, 0.6, 0.9)
	end

	local aim, normal = nil, Vector3.yAxis
	local wet = {} -- [part] = wet shine left
	local function blast(active, dt)
		local pointer, spraying = ctx.input()
		local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
		local dirn = ray.Direction.Unit
		local hit = workspace:Raycast(ray.Origin, dirn * 80, rayParams)
		local target = hit and hit.Position or (ray.Origin + dirn * 10)
		aim = aim and aim:Lerp(target, damp(30, dt)) or target
		if hit then
			local n = normal:Lerp(hit.Normal, damp(20, dt))
			if n.Magnitude > 1e-3 then normal = n.Unit end
		end
		hold(dt, aim)
		hitAt.WorldCFrame = CFrame.lookAt(aim, aim + normal) * CFrame.Angles(-math.pi / 2, 0, 0)
		jet.Enabled, mist.Enabled, drops.Enabled = spraying, spraying, spraying
		hiss.Volume += ((spraying and 0.45 or 0) - hiss.Volume) * damp(14, dt)
		if not spraying then return false end
		local cleaned = false
		-- everything under the jet: near the line you point along, not hidden behind what it hits
		local depth = hit and (hit.Position - ray.Origin):Dot(dirn) or math.huge
		for k = #active, 1, -1 do
			local e = active[k]
			local rel = e.core.Position - ray.Origin
			local along = rel:Dot(dirn)
			local off = (rel - dirn * along).Magnitude
			local reach = (JET.Radius * jetMul + e.size * 0.4) * (active.hint and 1.6 or 1) -- the last few are easier to hit
			if along < depth + 0.6 and off < reach then
				e.hp -= dt * JET.Rate * jetMul * (1 - 0.6 * off / reach)
				if e.hp > 0 then
					e.model:ScaleTo(0.25 + 0.75 * e.hp)
					for _, p in e.parts do p.Transparency = (1 - e.hp) * 0.4 end
				else
					runoff(e.core.Position, e.core.Color)
					table.remove(active, k)
					local pan = gone(e)
					cleaned = true
					local done = 1 - left / total
					ctx.sfx(ctx.SFX.Tap, 0.22, 1.1 + done * 0.9)
					if pan and pan.n == 0 and pan.of > 0 then
						-- that panel's spotless: a ding and a glint
						ctx.sparkle(e.on.Position)
						ctx.sfx(ctx.SFX.Done, 0.4, 1.2 + done * 0.5)
					end
				end
			end
		end
		if hit then
			local pan = panels[hit.Instance]
			if pan then pan.rinse = math.min(1, pan.rinse + dt * 0.8 * jetMul) end
			if hit.Instance.Parent == m then wet[hit.Instance] = 1 end
		end
		return cleaned
	end
	local function shine(dt)
		-- each panel is as clean as its own mud is gone (or as long as you've rinsed it)
		for p, pan in panels do
			local f = pan.of > 0 and (1 - pan.n / pan.of) * 0.9 + pan.rinse * 0.1 or pan.rinse
			p.Color = pan.from:Lerp(pan.to, math.clamp(f, 0, 1))
		end
		for p, w in wet do
			w = math.max(0, w - dt * 0.5)
			wet[p] = w > 0 and w or nil
			p.Reflectance = 0.18 * w
		end
	end
	local function stopJet()
		jet.Enabled, mist.Enabled, drops.Enabled = false, false, false
		hiss.Volume = 0
	end

	-- this side, then (if there's mud round the back) the other side
	for side = 1, 2 do
		local active = inView()
		local sideTotal = math.max(1, #active)
		ctx.setInstruction(side == 1 and "Hold to spray off all the mud!" or "Now the other side!", step)
		local idle, hint, light = 0, nil, nil
		while #active > 0 do
			local dt = RunService.RenderStepped:Wait()
			idle = blast(active, dt) and 0 or idle + dt
			shine(dt)
			-- what's left glows (through the scooter too) once most of this side is clean, or
			-- as soon as you stop finding any, so no splatter gets missed
			if not hint and (#active <= math.max(5, math.ceil(sideTotal * 0.35)) or idle > 1.5) then
				hint = Instance.new("Model")
				hint.Name = "MudLeft"
				for _, e in active do e.model.Parent = hint end
				hint.Parent = m
				light = Instance.new("Highlight")
				light.Adornee = hint
				light.FillColor = Color3.fromRGB(255, 220, 90)
				light.OutlineColor = Color3.fromRGB(255, 240, 170)
				light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				light.Parent = hint
				active.hint = true
			end
			if light then
				local pulse = 0.45 + math.sin(os.clock() * 7) * 0.2
				light.FillTransparency = pulse
				light.OutlineTransparency = math.max(0, pulse - 0.3)
			end
		end
		if hint then hint:Destroy() end
		stopJet()
		if left <= 0 or side == 2 then break end
		task.wait(0.25)
		spin(math.pi, 1.3)
	end
	-- anything still on (tucked out of sight both ways) washes off in the final rinse
	for _, e in splats do
		if not e.gone then
			runoff(e.core.Position, e.core.Color)
			gone(e)
		end
	end
	jet:Destroy()
	hitAt:Destroy()
	fromAt:Destroy()
	hiss:Destroy()

	-- the final rinse: every panel comes up spotless and the wet shine fades, the lance
	-- goes back on its hook and the turntable brings the scooter back round
	ctx.sfx(ctx.SFX.Done, 0.7, 1.3)
	ctx.sparkle(m:GetBoundingBox().Position)
	local start = {}
	for p in panels do start[p] = { p.Color, p.Reflectance } end
	task.spawn(tween, 0.8, function(a)
		for p, pan in panels do
			p.Color = start[p][1]:Lerp(pan.to, a)
			p.Reflectance = math.max(start[p][2], 0.15) * (1 - a)
		end
	end)
	for p in wet do
		if not panels[p] then p.Reflectance = 0 end
	end
	put(0.4)
	if turned % (2 * math.pi) ~= 0 then spin(2 * math.pi - turned % (2 * math.pi), 1.2) end
end

---------------------------------------------------------------- broken light wiring
-- A junction box pops out in front of the light. Three wires come out of the ports on
-- its left; drag each loose end onto the terminal of the same colour on the right (or
-- tap an end, then tap its terminal). A wrong terminal buzzes and the end springs back.
local WIRES = { Color3.fromRGB(240, 70, 70), Color3.fromRGB(255, 205, 60), Color3.fromRGB(70, 150, 240) }
function M.wires(light, rim, step)
	local camera = workspace.CurrentCamera
	local eye = camera.CFrame.Position
	local toCam = (eye - rim.Position).Unit
	local center = rim.Position + toCam * 0.55 - Vector3.new(0, 0.95, 0) -- just under the light, toward you
	local face = CFrame.lookAt(center, center - (eye - center).Unit) -- +X = right as you see it, +Z = toward you
	local W, H = 1.7, 1.25
	local box = Instance.new("Model")
	box.Name = "WireBox"
	local frame = part("Frame", Vector3.new(W + 0.14, H + 0.14, 0.08), Color3.fromRGB(60, 64, 78))
	frame.CFrame = face * CFrame.new(0, 0, -0.05)
	frame.Parent = box
	local plate = part("Plate", Vector3.new(W, H, 0.04), Color3.fromRGB(30, 32, 40))
	plate.CFrame = face * CFrame.new(0, 0, 0)
	plate.Parent = box
	-- a bundle of cable from the light down into the box
	local bundleA, bundleB = Instance.new("Attachment"), Instance.new("Attachment")
	bundleA.Parent, bundleB.Parent = rim, frame
	bundleA.WorldCFrame = CFrame.new(rim.Position) * DOWN
	bundleB.WorldCFrame = CFrame.new((face * CFrame.new(-W / 2 + 0.2, H / 2, 0)).Position) * DOWN
	local bundle = Instance.new("Beam")
	bundle.Attachment0, bundle.Attachment1 = bundleA, bundleB
	bundle.Width0, bundle.Width1 = 0.1, 0.1
	bundle.Segments = 10
	bundle.FaceCamera = true
	bundle.CurveSize0, bundle.CurveSize1 = 0.25, -0.25
	bundle.Color = ColorSequence.new(Color3.fromRGB(32, 33, 38))
	bundle.Transparency = NumberSequence.new(0)
	bundle.Parent = frame

	local left, right = shuffled(3), shuffled(3)
	while left[1] == right[1] and left[2] == right[2] do right = shuffled(3) end
	local ROWS = { 0.38, 0, -0.38 }
	local plugs, terms = {}, {}
	for i = 1, 3 do
		local c = WIRES[left[i]]
		local port = part("Port", Vector3.new(0.18, 0.18, 0.06), c, Enum.Material.Neon)
		port.CFrame = face * CFrame.new(-0.72, ROWS[i], 0.04)
		port.Parent = box
		local plug = ball("Plug", 0.19, c, Enum.Material.Neon)
		local home = face * CFrame.new(-0.46, ROWS[i] - 0.05, 0.12)
		plug.CFrame = home
		plug.Parent = box
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent, a1.Parent = port, plug
		a0.WorldCFrame = CFrame.new(port.Position) * DOWN
		a1.WorldCFrame = CFrame.new(plug.Position) * DOWN
		local wire = Instance.new("Beam")
		wire.Attachment0, wire.Attachment1 = a0, a1
		wire.Width0, wire.Width1 = 0.07, 0.07
		wire.Segments = 12
		wire.FaceCamera = true
		wire.CurveSize0, wire.CurveSize1 = 0.12, -0.12
		wire.Color = ColorSequence.new(c)
		wire.Transparency = NumberSequence.new(0)
		wire.Parent = plug
		plugs[i] = { part = plug, color = left[i], home = home }
		local tc = WIRES[right[i]]
		local at = face * CFrame.new(0.62, ROWS[i], 0.06)
		local ring = part("Terminal", Vector3.new(0.05, 0.3, 0.3), tc)
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.05, 0.3, 0.3)
		ring.CFrame = at * CFrame.Angles(0, math.pi / 2, 0)
		ring.Parent = box
		local hole = part("Hole", Vector3.new(0.06, 0.15, 0.15), Color3.fromRGB(20, 20, 24))
		hole.Shape = Enum.PartType.Cylinder
		hole.Size = Vector3.new(0.06, 0.15, 0.15)
		hole.CFrame = at * CFrame.new(0, 0, 0.01) * CFrame.Angles(0, math.pi / 2, 0)
		hole.Parent = box
		terms[i] = { part = ring, color = right[i], at = face * CFrame.new(0.62, ROWS[i], 0.12) }
	end
	-- the box pops out of the light
	local parts = {}
	for _, d in box:GetDescendants() do
		if d:IsA("BasePart") then parts[d] = { d.CFrame, d.Size } end
	end
	box.Parent = workspace
	ctx.sfx(ctx.SFX.Tap, 0.8, 0.8)
	tween(0.25, function(a)
		local k = 0.2 + 0.8 * TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		for d, o in parts do
			d.Size = o[2] * k
			d.CFrame = face * CFrame.new(face:PointToObjectSpace(o[1].Position) * k) * (o[1] - o[1].Position)
		end
	end)
	for d, o in parts do d.Size, d.CFrame = o[2], o[1] end

	local function onBoard(pointer)
		local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
		local o, d = face:PointToObjectSpace(ray.Origin), face:VectorToObjectSpace(ray.Direction)
		if math.abs(d.Z) < 1e-4 then return nil end
		local t = (0.12 - o.Z) / d.Z
		if t <= 0 then return nil end
		local p = o + d * t
		return Vector3.new(math.clamp(p.X, -W / 2 + 0.1, W / 2 - 0.08), math.clamp(p.Y, -H / 2 + 0.1, H / 2 - 0.1), 0.12)
	end
	local function screenDist(pos, at)
		local sp = camera:WorldToScreenPoint(pos)
		return (Vector2.new(sp.X, sp.Y) - at).Magnitude
	end
	local function spring(pl)
		local from = pl.part.CFrame
		task.spawn(tween, 0.22, function(a)
			pl.part.CFrame = from:Lerp(pl.home, TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		end)
	end
	-- let go of `pl` at `term` (or nowhere): the right colour clicks in, anything else springs back
	local done = 0
	local function drop(pl, term)
		if term and term.color == pl.color then
			pl.part.CFrame = term.at
			pl.done, term.done = true, true
			term.part.Material = Enum.Material.Neon
			done += 1
			ctx.sparkle(term.at.Position)
			ctx.sfx(ctx.SFX.Done, 0.6, 1 + done * 0.15)
			return
		end
		if term then
			ctx.sfx(ctx.SFX.Tap, 0.9, 0.45)
			local c = term.part.Color
			term.part.Color = RED
			task.delay(0.25, function() term.part.Color = c end)
		end
		spring(pl)
	end
	-- the free terminal nearest a point on the board (or on screen), if it's close enough
	local function termAt(localPos, screenPos)
		local best, bestD = nil, math.huge
		for _, t in terms do
			if not t.done then
				local tp = face:PointToObjectSpace(t.at.Position)
				local d = localPos and (Vector2.new(localPos.X, localPos.Y) - Vector2.new(tp.X, tp.Y)).Magnitude / 0.27
					or screenDist(t.at.Position, screenPos) / 55
				if d < 1 and d < bestD then best, bestD = t, d end
			end
		end
		return best
	end

	ctx.setInstruction("Drag each wire to its colour", step)
	local drag, armed, moved = nil, nil, 0
	while done < 3 do
		local dt = RunService.RenderStepped:Wait()
		local pointer, holding = ctx.input()
		local press = ctx.press()
		if press and not drag then
			-- tapped a terminal with an end picked up: plug it in there
			local term = armed and termAt(nil, press)
			if term then
				local pl = armed
				armed = nil
				local from = pl.part.CFrame
				tween(0.15, function(a) pl.part.CFrame = from:Lerp(term.at, a) end)
				drop(pl, term)
			else
				-- grab the loose end nearest your finger
				local best, bestD = nil, 60
				for _, pl in plugs do
					if not pl.done then
						local d = screenDist(pl.part.Position, press)
						if d < bestD then best, bestD = pl, d end
					end
				end
				if best then
					drag, armed, moved = best, nil, 0
					ctx.sfx(ctx.SFX.Tap, 0.6, 1.2)
				end
			end
		end
		if drag then
			local p = onBoard(pointer)
			if p then
				local want = face * CFrame.new(p)
				moved += (want.Position - drag.part.Position).Magnitude
				drag.part.CFrame = drag.part.CFrame:Lerp(want, damp(30, dt))
			end
			if not holding then
				local pl = drag
				drag = nil
				local term = termAt(face:PointToObjectSpace(pl.part.Position))
				if not term and moved < 0.25 then
					-- just a tap: keep it picked up, tap its terminal next
					armed = pl
					pl.part.CFrame = pl.home * CFrame.new(0, 0.06, 0.05)
				else
					drop(pl, term)
				end
			end
		end
		-- the end you're holding (or have picked up) pulses
		for _, pl in plugs do
			if not pl.done then
				local on = pl == drag or pl == armed
				local k = on and 1.25 + math.sin(os.clock() * 10) * 0.1 or 1
				pl.part.Size = Vector3.one * 0.19 * k
			end
		end
	end
	tween(0.35, function() end)
	-- wired: the box tucks back into the light
	tween(0.25, function(a)
		local k = 1 - 0.85 * smoothstep(a)
		for d, o in parts do
			if d.Parent then
				d.Transparency = a
			end
		end
		bundle.Transparency = NumberSequence.new(a)
		for _, d in box:GetDescendants() do
			if d:IsA("Beam") then d.Transparency = NumberSequence.new(a) end
		end
		box:ScaleTo(math.max(0.05, k))
	end)
	box:Destroy()
end

---------------------------------------------------------------- painting
-- First person, like the bench: you're hidden and the camera is your eyes. At the spray
-- rack you tap a can and it comes into your hand, held low on the right of the view.
-- Then you look round the scooter (A / D, the arrow keys or the arrow buttons; when
-- nothing you can see is left to paint it turns you round by itself) and spray. The
-- panel under the spray is what gets painted: hold the spray on it and it fills with
-- the colour, a panel at a time, and a near miss on a tyre or a grip still lands on
-- the panel next to it. Pick another colour (the swatches, or 1-9) and spray a panel
-- again to paint over it the same way. Lights and the screen are masked with tape;
-- spray that misses the scooter lands on the booth walls and floor (it stays there
-- until the booth is cleaned). DONE is there all along: you say when it's finished.
local PAINT = {
	Eye = 4.4, -- your eyes, this high over the booth floor
	Gap = 2.6, -- you stand this far out from the scooter's sides
	Fov = 70,
	Walk = 1.4, -- radians a second round the scooter
	Fill = 0.2, PerSpot = 0.006, MinFill = 0.25, MaxFill = 0.8, -- seconds of spray a panel takes; bigger panels take longer
	Snap = 0.45, -- a near miss this close to a panel still paints it
	TurnAfter = 0.5, -- seconds without spraying before it turns you round to what's left
	Specks = 30, MaxMess = 350, -- overspray: new specks a second at most, and how many stay on the booth
}
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
}
local TURN_ORDER = { 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8 } -- eighths of a turn, nearest first
-- masked with tape before painting (peeled off after); paint never sticks to the rest
local TAPED = { Light = true, LightRim = true, Light2 = true, LightRim2 = true, LightBar = true, TailLight = true, TailLightRim = true, Screen = true }
local TAPE = Color3.fromRGB(70, 150, 235)
local SPRAY_DOT = "rbxassetid://82148777515225" -- soft round dot with a fine grain (ui/paint/spray_dot.png)
local SPRAY_MIST = "rbxassetid://114596771060391" -- soft core with loose droplets (ui/paint/spray_mist.png)
local DARK = Color3.fromRGB(18, 19, 25)
local paintCam = { zoom = 1 }

local function flat(v)
	v = Vector3.new(v.X, 0, v.Z)
	return v.Magnitude > 1e-4 and v.Unit or Vector3.zAxis
end
-- keep a camera point inside the booth (in the floor's own space, so any plot works)
local function insideFloor(floor, p)
	local l = floor.CFrame:PointToObjectSpace(p)
	local h = floor.Size / 2 - Vector3.new(0.4, 0, 0.4)
	return floor.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), l.Y, math.clamp(l.Z, -h.Z, h.Z)))
end

local SAMPLE_DIRS = {}
for _, d in { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 1, 1, 0 }, { -1, 1, 0 }, { 0, 1, 1 }, { 0, 1, -1 }, { 1, 0.4, 1 }, { -1, 0.4, 1 }, { 1, 0.4, -1 }, { -1, 0.4, -1 }, { 0, -0.35, 1 }, { 0, -0.35, -1 } } do
	table.insert(SAMPLE_DIRS, Vector3.new(d[1], d[2], d[3]).Unit)
end
-- Spots on each panel the painter can reach: seen from somewhere round it, not hidden
-- under another part, not facing the floor. Kept in the scooter's own space, so the
-- crane can carry it while this runs (one panel a frame).
function M.paintSamples(m, panels)
	local all = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then table.insert(all, d) end
	end
	local anyParams = RaycastParams.new()
	anyParams.FilterType = Enum.RaycastFilterType.Include
	anyParams.FilterDescendantsInstances = all
	local out = {}
	for _, p in panels do
		local pivot = m:GetPivot()
		local only = RaycastParams.new()
		only.FilterType = Enum.RaycastFilterType.Include
		only.FilterDescendantsInstances = { p }
		local list, seen = {}, {}
		local ext = p.Size.Magnitude / 2
		local n = math.clamp(math.ceil(ext * 2 / 0.3), 2, 9)
		for _, d in SAMPLE_DIRS do
			local u = d:Cross(math.abs(d.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis).Unit
			local v = d:Cross(u)
			for i = 0, n do
				for j = 0, n do
					local o = p.Position + u * ((i / n - 0.5) * 2 * ext) + v * ((j / n - 0.5) * 2 * ext) + d * (ext + 1)
					local ray = -d * (ext * 2 + 2)
					local h = workspace:Raycast(o, ray, only)
					if h and h.Normal.Y > -0.45 then
						local first = workspace:Raycast(o, ray, anyParams)
						if first and first.Instance == p then
							local lp = pivot:PointToObjectSpace(h.Position)
							local key = math.floor(lp.X / 0.28) .. "," .. math.floor(lp.Y / 0.28) .. "," .. math.floor(lp.Z / 0.28)
							if not seen[key] then
								seen[key] = true
								table.insert(list, { at = lp, n = pivot:VectorToObjectSpace(h.Normal), paint = 0 })
							end
						end
					end
				end
			end
		end
		out[p] = list
		task.wait()
	end
	return out
end

-- A round button in the booth's paint kit (arrows, colour swatches, DONE).
local function kitButton(parent, name, text, color, size)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.BackgroundColor3 = color
	b.FontFace = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeColor3 = DARK
	b.TextStrokeTransparency = 0.4
	b.AutoButtonColor = true
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
	local s = Instance.new("UIStroke", b)
	s.Color = DARK
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pad = Instance.new("UIPadding", b)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	b.Parent = parent
	return b
end

-- A spray can held up in your right hand, low on the right of the view: it stays upright
-- (leaning a little toward where you aim) with its nozzle facing that way. Same calls as
-- holder(): update(dt, at) every frame, put(time) hangs it back on the rack.
local CAN_GRIP = Vector3.new(1.75, -1.2, -3) -- right, down and ahead of the camera
local function canHolder(can)
	local camera = workspace.CurrentCamera
	local body = can.Body
	local home = can:GetPivot()
	local bodyOff = home:ToObjectSpace(body.CFrame)
	local top = body.CFrame:VectorToObjectSpace((can.Nozzle.Position - body.Position).Unit)
	local fix = CFrame.fromRotationBetweenVectors(top, Vector3.new(0, 0, -1)) -- its top along -Z
	local cur = home
	local function update(dt, at)
		local cf = camera.CFrame
		local pos = cf * CAN_GRIP
		local d = (at - pos).Unit
		local axis = (Vector3.yAxis + d * 0.3).Unit
		local f = d - axis * d:Dot(axis)
		f = f.Magnitude > 1e-3 and f.Unit or cf.LookVector
		local back = -axis
		cur = cur:Lerp(CFrame.fromMatrix(pos, f:Cross(back), f, back) * fix * bodyOff:Inverse(), damp(16, dt))
		can:PivotTo(cur)
	end
	local function put(time)
		local from = can:GetPivot()
		tween(time or 0.35, function(a)
			local p = from.Position:Lerp(home.Position, smoothstep(a)) + Vector3.new(0, math.sin(a * math.pi) * 0.6, 0)
			can:PivotTo(CFrame.new(p) * (from - from.Position):Lerp(home - home.Position, smoothstep(a)))
		end)
		can:PivotTo(home)
	end
	return update, put
end

-- cans = the rack's cans (Can1..3). You step up to the rack and look at it.
function M.painter(booth, m, cans)
	local camera = workspace.CurrentCamera
	local _, hum, hrp = ctx.getRig()
	local api = {}
	local floor = booth.Floor
	local floorY = floor.Position.Y + floor.Size.Y / 2
	local standY = hrp and hum and floorY + hum.HipHeight + hrp.Size.Y / 2 or floorY + 3
	-- the rack: which way it faces and where its cans are
	local mid = Vector3.zero
	for _, c in cans do mid += c.Body.Position end
	mid /= #cans
	local front = flat(cans[1].Nozzle.Position - cans[1].Body.Position)
	-- where the others in the server see you stand; you don't see yourself
	local function stand(at, toward)
		if not hrp then return end
		local p = Vector3.new(at.X, standY, at.Z)
		hrp.CFrame = CFrame.lookAt(p, Vector3.new(toward.X, standY, toward.Z))
	end
	if hrp then hrp.Anchored = true end
	stand(mid + front * 2.4, mid)
	ctx.hideSelf(true)
	camera.CameraType = Enum.CameraType.Scriptable
	local camFrom, fov0 = camera.CFrame, camera.FieldOfView
	local rackView = CFrame.lookAt(Vector3.new(mid.X, floorY + 4.2, mid.Z) + front * 3.6, mid + Vector3.new(0, 0.6, 0))
	tween(0.6, function(a)
		camera.CFrame = camFrom:Lerp(rackView, smootherstep(a))
		camera.FieldOfView = fov0 + (PAINT.Fov - fov0) * a
	end)

	-- the can comes off the rack into your hand
	function api.grab(can)
		api.can = can
		api.canColor = can.Body.Color
		ctx.sfx(ctx.SFX.Tap, 0.7, 1.1)
		api.hold, api.put = canHolder(can)
		tween(0.35, function(_, dt)
			api.hold(dt, camera.CFrame.Position + camera.CFrame.LookVector * 6)
		end)
		ctx.sfx(ctx.SFX.Tap, 0.6, 1.4)
	end

	-- o = { panels, samples, color, name, colors = { {Name, Color}, ... } (yours first), sprayMul, step }
	-- returns quality 0..1: how much of it you painted (and mostly in the colour you picked)
	function api.paint(o)
		local can = api.can
		local sprayMul = o.sprayMul or 1
		local bb, size = m:GetBoundingBox()
		local pivot = m:GetPivot()
		local centre = bb.Position
		local look = centre + Vector3.new(0, 0.2, 0)
		local function eyeAt(t)
			local gap = PAINT.Gap * paintCam.zoom
			local p = bb * Vector3.new(math.cos(t) * (size.X / 2 + gap), 0, math.sin(t) * (size.Z / 2 + gap))
			return insideFloor(floor, Vector3.new(p.X, floorY + PAINT.Eye, p.Z))
		end
		-- start on the long side nearer the open booth
		local theta = math.pi / 2
		local eye0 = booth:FindFirstChild("BoothCam") and booth.BoothCam.Position or camera.CFrame.Position
		if (eyeAt(-math.pi / 2) - eye0).Magnitude < (eyeAt(math.pi / 2) - eye0).Magnitude then theta = -math.pi / 2 end
		local colors = o.colors or { { Name = o.name, Color = o.color } }
		local cur = 1

		-- what the spray can land on: the scooter and the booth (not the can)
		local world, solid, onScooter = {}, {}, {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 and d.CanQuery then
				table.insert(world, d)
				table.insert(solid, d)
				onScooter[d] = true
			end
		end
		for _, d in booth:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 and d.CanQuery and not d:IsDescendantOf(can) then table.insert(world, d) end
		end
		local mess = booth:FindFirstChild("Overspray") or Instance.new("Folder")
		mess.Name = "Overspray"
		mess.Parent = booth

		-- masking tape over the lights and the screen: it slaps on, and peels off at the end
		local tape = Instance.new("Model")
		tape.Name = "MaskingTape"
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and TAPED[d.Name] and d.Transparency < 1 then
				local t = d:Clone()
				t:ClearAllChildren()
				t.Name = "Tape"
				t.Color = TAPE
				t.Material = Enum.Material.Fabric
				t.Transparency = 0
				t.Reflectance = 0
				t.Anchored, t.CanCollide, t.CanTouch, t.CastShadow = true, false, false, false
				t.CanQuery = true
				t.Size = d.Size * 1.06 + Vector3.one * 0.02
				t.Parent = tape
			end
		end
		tape.Parent = m
		local tapeParts = tape:GetChildren()
		for _, t in tapeParts do
			table.insert(world, t)
			table.insert(solid, t)
			onScooter[t] = true
		end
		if #tapeParts > 0 then
			ctx.sfx(ctx.SFX.Tap, 0.7, 0.7)
			local sizes = {}
			for _, t in tapeParts do sizes[t] = t.Size end
			tween(0.25, function(a)
				local k = 0.4 + 0.6 * TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				for t, s in sizes do t.Size = s * k end
			end)
		end
		local worldParams = RaycastParams.new()
		worldParams.FilterType = Enum.RaycastFilterType.Include
		worldParams.FilterDescendantsInstances = world
		local seeParams = RaycastParams.new()
		seeParams.FilterType = Enum.RaycastFilterType.Include
		seeParams.FilterDescendantsInstances = solid

		-- the panels: how much of each there is (its reachable spots), a few spots to tell
		-- whether you can see it, and its paint so far
		local st = {}
		for _, p in o.panels do
			local list = o.samples and o.samples[p] or {}
			local spots = {}
			for i = 1, #list, math.max(1, math.floor(#list / 6)) do
				table.insert(spots, { at = pivot * list[i].at, n = pivot:VectorToWorldSpace(list[i].n) })
			end
			st[p] = {
				weight = #list, spots = spots, from = p.Color, fill = 0,
				time = math.clamp(PAINT.Fill + #list * PAINT.PerSpot, PAINT.MinFill, PAINT.MaxFill),
			}
		end
		-- can you see some of panel p from eye?
		local function sees(eye, p)
			for _, s in st[p].spots do
				local to = s.at - eye
				if to:Dot(s.n) < 0 then
					local h = workspace:Raycast(eye, to + to.Unit * 0.05, seeParams)
					if h and h.Instance == p then return true end
				end
			end
			return false
		end
		-- a panel you can't see from anywhere round it doesn't count (it takes your colour at the end)
		local count, hidden = 0, {}
		for p, s in st do
			local seen = false
			if s.weight > 0 then
				for i = 0, 15 do
					if sees(eyeAt(i * math.pi / 8), p) then
						seen = true
						break
					end
				end
			end
			if seen then
				count += 1
			else
				s.weight = 0
				table.insert(hidden, p)
			end
		end
		-- the panel a spray lands on; a near miss (a tyre, a grip, the tape) finds the one next to it
		local function panelAt(h)
			local p = h.Instance
			if st[p] then return st[p].weight > 0 and p or nil end
			if not onScooter[p] then return nil end
			local best, bestD = nil, PAINT.Snap
			for q, s in st do
				if s.weight > 0 then
					local l = q.CFrame:PointToObjectSpace(h.Position)
					local half = q.Size / 2
					local c = Vector3.new(math.clamp(l.X, -half.X, half.X), math.clamp(l.Y, -half.Y, half.Y), math.clamp(l.Z, -half.Z, half.Z))
					local d = (l - c).Magnitude
					if d < bestD then best, bestD = q, d end
				end
			end
			return best
		end

		-- the paint kit: walk arrows, colour swatches, DONE
		local gui = Instance.new("ScreenGui")
		gui.Name = "PaintKit"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 5
		local btnDir = 0
		for i, d in { { "WalkLeft", "<", -1 }, { "WalkRight", ">", 1 } } do
			local b = kitButton(gui, d[1], d[2], Color3.fromRGB(70, 74, 92), UDim2.fromOffset(64, 64))
			b.AnchorPoint = Vector2.new(i == 1 and 0 or 1, 0.5)
			b.Position = UDim2.new(i == 1 and 0 or 1, i == 1 and 20 or -20, 0.55, 0)
			b.MouseButton1Down:Connect(function() btnDir = d[3] end)
			b.MouseButton1Up:Connect(function() btnDir = 0 end)
			b.MouseLeave:Connect(function() if btnDir == d[3] then btnDir = 0 end end)
		end
		local bar = Instance.new("Frame")
		bar.Name = "Swatches"
		bar.BackgroundTransparency = 1
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -22)
		bar.Size = UDim2.fromOffset(0, 54)
		bar.AutomaticSize = Enum.AutomaticSize.X
		bar.Parent = gui
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 10)
		list.Parent = bar
		local swatches = {}
		local function pickColor(i)
			cur = i
			if can.Body then can.Body.Color = colors[i].Color end
			for k, s in swatches do
				local on = k == i
				s.Size = UDim2.fromOffset(on and 52 or 42, on and 52 or 42)
				s.UIStroke.Color = on and Color3.new(1, 1, 1) or DARK
			end
		end
		if #colors > 1 then
			for i, c in colors do
				local s = kitButton(bar, "Swatch" .. i, "", c.Color, UDim2.fromOffset(42, 42))
				s.LayoutOrder = i
				s.Activated:Connect(function()
					pickColor(i)
					ctx.sfx(ctx.SFX.Tap, 0.6, 1.3)
				end)
				swatches[i] = s
			end
		end
		pickColor(1)
		local done = kitButton(gui, "Done", "DONE", Color3.fromRGB(88, 190, 96), UDim2.fromOffset(150, 58))
		done.AnchorPoint = Vector2.new(1, 1)
		done.Position = UDim2.new(1, -20, 1, -22)
		done.UICorner.CornerRadius = UDim.new(0, 16)
		local pressedDone = false
		done.Activated:Connect(function() pressedDone = true end)
		gui.Parent = Players.LocalPlayer.PlayerGui

		-- zoom (mouse wheel or pinch) and the number keys for colours
		local conns = {}
		table.insert(conns, UIS.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				paintCam.zoom = math.clamp(paintCam.zoom - input.Position.Z * 0.1, 0.6, 1.5)
			end
		end))
		local pinch0
		table.insert(conns, UIS.TouchPinch:Connect(function(_, scale, _, s)
			if s == Enum.UserInputState.Begin then pinch0 = paintCam.zoom end
			if pinch0 and scale > 0 then paintCam.zoom = math.clamp(pinch0 / scale, 0.6, 1.5) end
		end))
		table.insert(conns, UIS.InputBegan:Connect(function(input, processed)
			local i = not processed and NUMBER_KEYS[input.KeyCode]
			if i and swatches[i] then
				pickColor(i)
				ctx.sfx(ctx.SFX.Tap, 0.6, 1.3)
			end
		end))

		-- the mist from the nozzle, the puff where it lands, and the hiss
		local mistSource = part("PaintMist", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1))
		mistSource.Transparency = 1
		mistSource.Parent = workspace
		local mist = Instance.new("ParticleEmitter")
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Size = NumberSequence.new(0.12, 0.7)
		mist.Transparency = NumberSequence.new(0.3, 1)
		mist.Lifetime = NumberRange.new(0.18, 0.32)
		mist.Speed = NumberRange.new(6, 8)
		mist.SpreadAngle = Vector2.new(12, 12)
		mist.Rate = 80
		mist.EmissionDirection = Enum.NormalId.Front
		mist.Enabled = false
		mist.Parent = mistSource
		local splatAt = Instance.new("Attachment")
		splatAt.Name = "PaintSplat"
		splatAt.Parent = workspace.Terrain
		local splat = Instance.new("ParticleEmitter")
		splat.Texture = "rbxasset://textures/particles/smoke_main.dds"
		splat.Size = NumberSequence.new(0.2, 0.55)
		splat.Transparency = NumberSequence.new(0.35, 1)
		splat.Lifetime = NumberRange.new(0.15, 0.3)
		splat.Speed = NumberRange.new(0.5, 1.2)
		splat.SpreadAngle = Vector2.new(80, 80)
		splat.Rate = 40
		splat.EmissionDirection = Enum.NormalId.Front
		splat.Enabled = false
		splat.Parent = splatAt
		local hiss = Instance.new("Sound")
		hiss.SoundId = "rbxassetid://9119525650" -- PSE aerosol spray paint hiss, 14 s
		hiss.Looped = true
		hiss.Volume = 0
		hiss.PlaybackSpeed = 1
		hiss.Parent = camera
		hiss:Play()
		-- the outline on the panel you're aiming at, tinted with the colour it'll get
		local hover = Instance.new("Highlight")
		hover.Name = "PaintHover"
		hover.DepthMode = Enum.HighlightDepthMode.Occluded
		hover.FillTransparency = 0.6
		hover.OutlineColor = Color3.new(1, 1, 1)
		hover.OutlineTransparency = 0.1
		hover.Enabled = false
		hover.Parent = workspace

		-- overspray on the booth: soft dots (decals) that stay until the booth is cleaned
		local layer = 0
		local function speck(pos, n, d, color, alpha)
			layer += 1
			local p = part("Speck", Vector3.new(d, d, 0.02), color)
			p.Transparency = 1
			p.CFrame = CFrame.lookAt(pos + n * (0.004 + (layer % 6) * 0.0012), pos + n * 2) * CFrame.Angles(0, 0, math.random() * math.pi * 2)
			local dc = Instance.new("Decal")
			dc.Face = Enum.NormalId.Front
			dc.Texture = math.random() < 0.75 and SPRAY_DOT or SPRAY_MIST
			dc.Color3 = color
			dc.Transparency = alpha
			dc.Parent = p
			p.Parent = mess
			return p
		end
		local messList = mess:GetChildren()
		local budget = 0
		local function overspray(h, c, dt)
			budget = math.min(budget + PAINT.Specks * dt, 2)
			if budget < 1 then return end
			budget -= 1
			table.insert(messList, speck(h.Position, h.Normal, 0.45 + math.random() * 0.4, c.Color, 0.55))
			if #messList > PAINT.MaxMess then
				local old = table.remove(messList, 1)
				if old then old:Destroy() end
			end
			booth:SetAttribute("Mess", #messList)
		end

		-- one frame of spray on a panel: it fills with the colour; a new colour goes on over
		-- whatever is there now, the same way
		local painted = 0
		local function coat(p, s, c, dt)
			if s.to ~= c.Name then
				s.to, s.toColor, s.from, s.fill = c.Name, c.Color, p.Color, 0
			end
			s.fill = math.min(1, s.fill + dt * sprayMul / s.time)
			local k = smoothstep(s.fill)
			p.Color = s.from:Lerp(c.Color, k)
			p.Reflectance = 0.3 * k -- wet
			if s.fill >= 1 then
				if not s.name then painted += 1 end
				s.name = c.Name
				ctx.sfx(ctx.SFX.Done, 0.35, 1.05 + painted * 0.06)
				ctx.sparkle(p.Position)
			end
		end
		local function needs(s, c) return s.weight > 0 and not (s.to == c.Name and s.fill >= 1) end

		-- nothing left to paint that you can see from here: turn round to the side that has
		-- the most left (the nearest way round)
		local auto
		local function turnToWhatsLeft(eye)
			local todo = {}
			for p, s in st do
				if s.weight > 0 and not s.name then table.insert(todo, p) end
			end
			if #todo == 0 then return end
			for _, p in todo do
				if sees(eye, p) then return end
			end
			local best, bestN = nil, 0
			for _, k in TURN_ORDER do
				local t = theta + k * math.pi / 8
				local n = 0
				for _, p in todo do
					if sees(eyeAt(t), p) then n += 1 end
				end
				if n > bestN then best, bestN = t, n end
			end
			auto = best
		end

		-- from the rack round to the scooter
		ctx.setInstruction("Paint it " .. (o.name or ""), o.step)
		local camPos = eyeAt(theta)
		do
			local c0, f0 = camera.CFrame, camera.FieldOfView
			local c1 = CFrame.lookAt(camPos, look)
			tween(0.7, function(a, dt)
				local k = smootherstep(a)
				camera.CFrame = c0:Lerp(c1, k)
				camera.FieldOfView = f0 + (PAINT.Fov - f0) * k
				stand(camera.CFrame.Position, centre)
				api.hold(dt, camera.CFrame.Position + camera.CFrame.LookVector * 5)
			end)
		end
		local aim = centre
		local idle, nextLook, allDone = 0, 0, false
		while true do
			local dt = math.min(RunService.RenderStepped:Wait(), 1 / 20)
			local pointer, spraying = ctx.input()
			spraying = spraying and btnDir == 0 -- holding an arrow button isn't spraying
			-- look round it (the way you press is the way you go on screen)
			local dir = btnDir
			if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) or UIS:IsKeyDown(Enum.KeyCode.Q) then dir -= 1 end
			if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) or UIS:IsKeyDown(Enum.KeyCode.E) then dir += 1 end
			if dir ~= 0 then
				auto = nil
				local sign = (eyeAt(theta + 0.05) - eyeAt(theta)):Dot(camera.CFrame.RightVector) >= 0 and 1 or -1
				theta += math.clamp(dir, -1, 1) * sign * PAINT.Walk * dt
			elseif auto then
				local d = auto - theta
				theta += d * damp(4, dt)
				if math.abs(d) < 0.03 then auto = nil end
			end
			camPos = camPos:Lerp(eyeAt(theta), damp(8, dt))
			camera.CFrame = CFrame.lookAt(camPos, look)
			stand(camPos, centre)
			-- what you're aiming at; the can in your hand points at it
			local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 40, worldParams)
			local want = hit and hit.Position or ray.Origin + ray.Direction * ((centre - ray.Origin).Magnitude)
			aim = aim:Lerp(want, damp(30, dt))
			api.hold(dt, aim)
			local c = colors[cur]
			local target = hit and panelAt(hit)
			local s = target and st[target]
			local todo = s and needs(s, c)
			hover.Adornee = todo and target or nil
			hover.Enabled = todo and true or false
			hover.FillColor = c.Color
			-- spray
			mistSource.CFrame = CFrame.lookAt(can.Nozzle.Position, aim)
			mist.Color = ColorSequence.new(c.Color)
			mist.Enabled = spraying
			splat.Enabled = spraying and hit ~= nil
			if hit then
				splatAt.WorldCFrame = CFrame.lookAt(hit.Position, hit.Position + hit.Normal)
				splat.Color = ColorSequence.new(c.Color)
			end
			hiss.Volume += ((spraying and 0.3 or 0) - hiss.Volume) * damp(14, dt)
			if spraying then
				idle = 0
				auto = nil
				if todo then
					coat(target, s, c, dt)
				elseif hit and not onScooter[hit.Instance] then
					overspray(hit, c, dt)
				end
			else
				idle += dt
			end
			if idle > PAINT.TurnAfter and dir == 0 and not auto and os.clock() >= nextLook then
				nextLook = os.clock() + 0.4
				turnToWhatsLeft(camPos)
			end
			-- all of it painted: DONE bobs (you still say when)
			if not allDone and painted >= count then
				allDone = true
				ctx.setInstruction("All painted! Tap DONE", o.step)
				ctx.sfx(ctx.SFX.Tap, 0.6, 1.5)
				task.spawn(function()
					while done.Parent do
						done:TweenSize(UDim2.fromOffset(166, 64), Enum.EasingDirection.Out, Enum.EasingStyle.Sine, 0.35, true)
						task.wait(0.4)
						if not done.Parent then break end
						done:TweenSize(UDim2.fromOffset(150, 58), Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.35, true)
						task.wait(0.45)
					end
				end)
			end
			if pressedDone then break end
		end
		for _, x in conns do x:Disconnect() end
		gui:Destroy()
		hover:Destroy()
		splatAt:Destroy()
		mistSource:Destroy()
		hiss:Destroy()
		ctx.sfx(ctx.SFX.Done, 0.6, 1.25)

		-- a panel left half done: past half it gets finished, under half it goes back; the
		-- panels nobody can see take your colour (if you painted anything)
		local settle = {}
		for p, s in st do
			if s.to and s.fill < 1 then
				if s.fill >= 0.5 then
					s.name = s.to
					table.insert(settle, { p, p.Color, s.toColor })
				else
					table.insert(settle, { p, p.Color, s.from })
				end
			end
		end
		if painted > 0 then
			for _, p in hidden do table.insert(settle, { p, p.Color, colors[1].Color }) end
		end
		if #settle > 0 then
			tween(0.25, function(a)
				for _, x in settle do x[1].Color = x[2]:Lerp(x[3], a) end
			end)
		end

		-- the tape peels off, clean lights underneath
		if #tapeParts > 0 then
			ctx.sfx(ctx.SFX.Tap, 0.7, 1.6)
			local starts = {}
			for _, t in tapeParts do starts[t] = { t.CFrame, t.Transparency } end
			local fling = flat(camera.CFrame.Position - centre)
			tween(0.4, function(a)
				for t, s0 in starts do
					t.CFrame = s0[1] + fling * (a * 0.8) + Vector3.new(0, math.sin(a * math.pi) * 0.5, 0)
					t.Transparency = s0[2] + (1 - s0[2]) * a
				end
			end)
		end
		tape:Destroy()

		-- how much of it you painted, and whether most of it is the colour you picked
		local total, got, main = 0, 0, 0
		for _, s in st do
			if s.weight > 0 then
				total += s.weight
				if s.name then got += s.weight end
				if s.name == colors[1].Name then main += s.weight end
			end
		end
		if total == 0 then return 1 end
		local q = got / total
		if main / total < 0.5 then q *= 0.8 end
		return q
	end

	-- the can goes back on the rack; you're left in the booth (the caller takes you back
	-- to the bench)
	function api.finish()
		local can = api.can
		if not can then return end
		if can.Body and api.canColor then can.Body.Color = api.canColor end
		if api.put then api.put(0.35) end
	end
	return api
end

-- The grade for a paint job: a badge pops up over the scooter with paint-drop stars,
-- a chime per drop and a burst of sparkles. Returns the grade's entry from Config.PaintGrades.
function M.paintGrade(m, q)
	local grades = ctx.Config.PaintGrades
	local g = grades[#grades]
	for _, x in grades do
		if q >= x.Min then g = x break end
	end
	local bb, size = m:GetBoundingBox()
	local anchor = part("GradeAnchor", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1))
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(bb.Position + Vector3.new(0, size.Y / 2 + 1.2, 0))
	anchor.Parent = workspace
	local bbg = Instance.new("BillboardGui")
	bbg.Name = "PaintGrade"
	bbg.Adornee = anchor
	bbg.Size = UDim2.fromOffset(330, 120)
	bbg.AlwaysOnTop = true
	bbg.LightInfluence = 0
	bbg.ResetOnSpawn = false
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = bbg
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = holder
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 52)
	title.FontFace = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	title.TextScaled = true
	title.Text = g.Name
	title.TextColor3 = g.Color
	title.Parent = holder
	local st = Instance.new("UIStroke")
	st.Color = DARK
	st.Thickness = 3
	st.Parent = title
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 60)
	row.Size = UDim2.new(1, 0, 0, 48)
	row.Parent = holder
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = row
	local drops = {}
	for i = 1, 3 do
		local d = Instance.new("Frame")
		d.LayoutOrder = i
		d.Size = UDim2.fromOffset(40, 40)
		d.Rotation = 45 -- a paint drop: a square with three round corners
		d.BackgroundColor3 = Color3.fromRGB(60, 62, 74)
		Instance.new("UICorner", d).CornerRadius = UDim.new(0.5, 0)
		local s = Instance.new("UIStroke")
		s.Color = DARK
		s.Thickness = 3
		s.Parent = d
		local tip = Instance.new("Frame")
		tip.Size = UDim2.fromScale(0.5, 0.5)
		tip.BackgroundColor3 = d.BackgroundColor3
		tip.BorderSizePixel = 0
		tip.Parent = d
		d.Parent = row
		drops[i] = { d, tip }
	end
	bbg.Parent = Players.LocalPlayer.PlayerGui
	ctx.sfx(ctx.SFX.Done, 0.7, 1)
	tween(0.3, function(a) scale.Scale = 0.2 + 0.8 * TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
	for i = 1, g.Drops do
		task.wait(0.18)
		drops[i][1].BackgroundColor3 = g.Color
		drops[i][2].BackgroundColor3 = g.Color
		drops[i][1].Size = UDim2.fromOffset(52, 52)
		drops[i][1]:TweenSize(UDim2.fromOffset(40, 40), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.25, true)
		ctx.sfx(ctx.SFX.Done, 0.6, 1.1 + i * 0.15)
		ctx.sparkle(bb.Position + Vector3.new((i - 2) * 0.8, size.Y / 2, 0))
	end
	if g.Drops >= 3 then
		for _ = 1, 3 do
			ctx.sparkle(bb.Position + Vector3.new((math.random() - 0.5) * size.X, math.random() * size.Y * 0.6, (math.random() - 0.5) * size.Z))
		end
	end
	task.delay(2.4, function()
		tween(0.25, function(a) scale.Scale = 1 - a end)
		bbg:Destroy()
		anchor:Destroy()
	end)
	return g
end

---------------------------------------------------------------- rust (in the wash bay)
-- First person, like the wash. You turn to the bucket on the bay floor and tap it: the
-- sponge comes into your hand. Rub it over the glowing rusty parts: thick foam builds
-- up where you scrub and the rust fades under it; a part stops glowing once it's done.
-- Then the sponge goes back in the bucket, the lance comes off its hook and you spray
-- the foam off: each part comes up clean metal when its foam is gone. The turntable
-- turns the scooter round when what's left is on the other side.
local RUST = {
	Eye = 4.4, Gap = 2.4, Fov = 70, -- where you stand: eyes over the bay floor, out from the scooter's side
	Scrub = 420, -- pixels of rubbing a part needs (x its size, / the bucket's Scrub)
	-- owner, 24 Oct: it took too long and you got stuck not knowing what was left. Enough foam is enough:
	Accept = 0.75, -- share of all the rubbing that finishes the scrub (the rest foams up by itself)
	RinseAccept = 0.85, -- share of the foam rinsed off that finishes the rinse
	PointAfter = 1.5, -- seconds without progress before a marker bobs on the nearest part that's left
	Foam = 24, -- foam blobs on one part at most
	Rinse = 2.5, -- how fast the jet melts foam (x the washer's jet)
	TurnAfter = 0.6, -- seconds without progress before it turns the scooter to what's left
	HintAfter = 2, -- seconds without progress before the foam that's left glows through the scooter
}
local FOAM = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(242, 248, 255), Color3.fromRGB(226, 240, 255) }
local SPONGE_GRIP = CFrame.new(1.75, -1.2, -2.9) * CFrame.Angles(math.rad(-55), math.rad(-20), 0) -- in your hand, low right

-- o = { step, parts (the rusty ones), clean = { [part] = { Color, Material } }, scrubMul,
-- jetMul, bucket, tap = function(parts) that waits for a tap on one of them }
function M.rust(bay, m, o)
	local camera = workspace.CurrentCamera
	local bucket, lance = o.bucket, bay.Lance
	local sponge = bucket.Sponge
	local scrubMul, jetMul = o.scrubMul or 1, o.jetMul or 1
	local floorY = bay.Floor.Position.Y + bay.Floor.Size.Y / 2
	local center = bay.ScooterSpot.Position
	ctx.hideSelf(true)
	camera.CameraType = Enum.CameraType.Scriptable

	-- you stand on the open side of the scooter (toward the bay window), level with it
	local bb, size = m:GetBoundingBox()
	local across = flat(m:GetPivot().ZVector)
	if across:Dot(flat(bay.BoothCam.Position - center)) < 0 then across = -across end
	local eye = Vector3.new(bb.X, floorY + RUST.Eye, bb.Z) + across * (size.Z / 2 + RUST.Gap)
	local view = CFrame.lookAt(eye, bb.Position + Vector3.new(0, 0.35, 0))
	local solid = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d.CanQuery then table.insert(solid, d) end
	end
	local scooterParams = RaycastParams.new()
	scooterParams.FilterType = Enum.RaycastFilterType.Include
	scooterParams.FilterDescendantsInstances = solid

	-- the turntable turns the scooter (and the foam on it) round on the spot, as in the wash
	local turning = {}
	for _, d in bay:GetChildren() do
		if d:IsA("BasePart") and d.Name:match("^Turntable") and d.Name ~= "TurntableRim" then table.insert(turning, d) end
	end
	local turned = 0
	local function spin(angle, time)
		local from = m:GetPivot()
		local start = {}
		for _, p in turning do start[p] = p.CFrame end
		ctx.sfx(ctx.SFX.Tap, 0.6, 0.6)
		tween(time, function(a)
			local r = CFrame.new(center) * CFrame.Angles(0, angle * smootherstep(a), 0) * CFrame.new(-center)
			m:PivotTo(r * from)
			for p, cf in start do p.CFrame = r * cf end
		end)
		turned += angle
		ctx.sfx(ctx.SFX.Tap, 0.6, 0.9)
	end

	-- the rusty parts: how much rubbing each needs, and the foam on it
	local foamModel = Instance.new("Model")
	foamModel.Name = "RustFoam"
	foamModel.Parent = m
	local st, left = {}, 0
	for _, p in o.parts do
		local big = math.clamp(math.max(p.Size.X, p.Size.Y, p.Size.Z) / 1.6, 0.45, 1.2)
		st[p] = { need = RUST.Scrub * big / scrubMul, done = 0, rust = p.Color, blobs = {} }
		left += 1
	end
	local needAll = 0
	for _, s in st do needAll += s.need end
	local function coverage()
		local got = 0
		for _, s in st do got += math.min(s.done, s.need) end
		return got / math.max(needAll, 1)
	end
	-- the "here" marker: a soft bubble that bobs on the nearest part still to do
	local marker = ball("RustHere", 0.5, Color3.fromRGB(255, 225, 90), Enum.Material.Neon)
	marker.Transparency = 1
	marker.CanQuery = false
	marker.Parent = workspace
	local fullSize, hp = {}, {}
	local function addFoam(s, at, n)
		if #s.blobs >= RUST.Foam then return end
		local d = 0.22 + math.random() * 0.26
		local f = ball("Foam", d, FOAM[math.random(#FOAM)])
		local j = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.3
		f.CFrame = CFrame.new(at + n * (d * 0.2) + (j - n * j:Dot(n)))
		f.Parent = foamModel
		table.insert(s.blobs, f)
		fullSize[f], hp[f] = f.Size, 1
		f.Size = fullSize[f] * 0.3
		TweenService:Create(f, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = fullSize[f] }):Play()
	end
	-- the rusty part under your finger (a near miss on the part next to it still counts)
	local function rustyAt(h)
		if st[h.Instance] then return h.Instance end
		local best, bestD = nil, 0.4
		for q in st do
			local l = q.CFrame:PointToObjectSpace(h.Position)
			local half = q.Size / 2
			local c = Vector3.new(math.clamp(l.X, -half.X, half.X), math.clamp(l.Y, -half.Y, half.Y), math.clamp(l.Z, -half.Z, half.Z))
			local d = (l - c).Magnitude
			if d < bestD then best, bestD = q, d end
		end
		return best
	end
	-- can you see some of part p, or foam blob f, from where you stand?
	local CHECK = { Vector3.zero, Vector3.new(0.35, 0, 0), Vector3.new(-0.35, 0, 0), Vector3.new(0, 0.35, 0), Vector3.new(0, 0, 0.35), Vector3.new(0, 0, -0.35) }
	local function seen(p)
		for _, k in CHECK do
			local at = p.CFrame * (k * p.Size)
			local h = workspace:Raycast(eye, (at - eye) * 1.05, scooterParams)
			if h and h.Instance == p then return true end
		end
		return false
	end
	local function blobSeen(f)
		local to = f.Position - eye
		local h = workspace:Raycast(eye, to, scooterParams)
		return not h or (h.Position - eye).Magnitude > to.Magnitude - f.Size.X
	end
	local function todo()
		local t = {}
		for p, s in st do
			if s.done < s.need then table.insert(t, p) end
		end
		return t
	end

	-- 1. turn to the bucket and tap it
	local camFrom, fov0 = camera.CFrame, camera.FieldOfView
	local pail = bucket.Pail.Position
	local bucketView = CFrame.lookAt(eye + flat(pail - eye) * 0.4 - Vector3.new(0, 1, 0), pail + Vector3.new(0, 0.5, 0))
	tween(0.6, function(a)
		camera.CFrame = camFrom:Lerp(bucketView, smootherstep(a))
		camera.FieldOfView = fov0 + (RUST.Fov - fov0) * a
	end)
	ctx.setInstruction("Tap the bucket", o.step)
	o.tap({ bucket.Pail, bucket.Rim, bucket.Water, sponge.Soft, sponge.Scrub })
	ctx.sfx(ctx.SFX.Tap, 0.7, 1.1)
	ctx.puff(sponge.Soft.Position, Color3.fromRGB(230, 245, 255), 6)

	-- the sponge comes into your hand (a better bucket = a bigger sponge) as you turn back
	local spongeHome = sponge:GetPivot()
	local baseScale = sponge:GetScale()
	sponge:ScaleTo(baseScale * (0.62 + 0.12 * scrubMul) / sponge.Soft.Size.X)
	local handScale = sponge:GetScale()
	local lift = sponge.Scrub.Size.Y / 2 - sponge.Root.CFrame:PointToObjectSpace(sponge.Scrub.Position).Y
	local suds = Instance.new("ParticleEmitter")
	suds.Texture = "rbxasset://textures/particles/smoke_main.dds"
	suds.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
	suds.Size = NumberSequence.new(0.12, 0.32)
	suds.Transparency = NumberSequence.new(0.2, 1)
	suds.Lifetime = NumberRange.new(0.3, 0.6)
	suds.Speed = NumberRange.new(0.6, 1.4)
	suds.SpreadAngle = Vector2.new(60, 60)
	suds.Acceleration = Vector3.new(0, 1.5, 0)
	suds.Rate = 30
	suds.Enabled = false
	suds.Parent = sponge.Scrub
	local cur = sponge:GetPivot()
	local function holdSponge(dt, onto)
		cur = cur:Lerp(onto or camera.CFrame * SPONGE_GRIP, damp(onto and 30 or 14, dt))
		sponge:PivotTo(cur)
	end
	-- the sponge flat on a surface, its scrubbing side down
	local function against(pos, n, twist)
		local r = camera.CFrame.RightVector
		r = r - n * r:Dot(n)
		r = r.Magnitude > 1e-3 and r.Unit or n:Cross(Vector3.xAxis).Unit
		return CFrame.fromMatrix(pos + n * lift, r, n, r:Cross(n)) * CFrame.Angles(0, twist, 0)
	end
	do
		local c0 = camera.CFrame
		tween(0.5, function(a, dt)
			camera.CFrame = c0:Lerp(view, smootherstep(a))
			holdSponge(dt)
		end)
	end

	-- 2. scrub: foam builds up where you rub, the rust fades under it
	ctx.setInstruction("Scrub off the rust!", o.step)
	ctx.glow(o.parts)
	if ctx.setBar then ctx.setBar(0) end
	local last, wiggle, lastFoam, idle, nextLook, stuck = nil, 0, 0, 0, 0, 0
	while left > 0 do
		local dt = RunService.RenderStepped:Wait()
		local pointer, holding = ctx.input()
		local moved = last and (pointer - last).Magnitude or 0
		last = pointer
		local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 40, scooterParams)
		local p = hit and rustyAt(hit)
		local s = p and st[p]
		local scrubbing = holding and hit ~= nil
		suds.Enabled = scrubbing and s ~= nil
		if scrubbing then
			wiggle += moved * 0.02
			holdSponge(dt, against(hit.Position, hit.Normal, math.sin(wiggle) * 0.35))
		else
			holdSponge(dt)
		end
		if scrubbing and s and s.done < s.need and moved > 0.5 then
			idle, stuck = 0, 0
			s.done = math.min(s.need, s.done + moved)
			local k = s.done / s.need
			p.Color = s.rust:Lerp(o.clean[p].Color, k * 0.6) -- the rinse finishes it
			if os.clock() - lastFoam > 0.04 then
				lastFoam = os.clock()
				addFoam(s, hit.Position, hit.Normal)
			end
			if k - (s.tick or 0) >= 0.2 then
				s.tick = k
				ctx.sfx(ctx.SFX.Tap, 0.22, 1.2 + k * 0.6)
			end
			if s.done >= s.need then
				-- covered: a last dollop, a squelch, and it stops glowing
				left -= 1
				for _ = 1, 3 do addFoam(s, hit.Position, hit.Normal) end
				ctx.sfx(ctx.SFX.Done, 0.4, 1.1 + (#o.parts - left) * 0.08)
				ctx.unglow()
				local rest = todo()
				if #rest > 0 then ctx.glow(rest) end
			end
		else
			idle += dt
		end
		local cov = coverage()
		if ctx.setBar then ctx.setBar(cov / RUST.Accept) end
		if left > 0 and cov >= RUST.Accept then
			-- enough of it is covered: the foam spreads over what's left by itself
			for _, q in todo() do
				local s2 = st[q]
				s2.done = s2.need
				q.Color = s2.rust:Lerp(o.clean[q].Color, 0.6)
				for _ = 1, 6 do addFoam(s2, q.Position, flat(eye - q.Position).Unit) end
			end
			left = 0
			ctx.sfx(ctx.SFX.Done, 0.5, 1.3)
		end
		-- stalled: a bubble bobs on the nearest part you can see that still needs scrubbing
		local point
		if left > 0 and idle > RUST.PointAfter then
			local bestD
			for _, q in todo() do
				if seen(q) then
					local d = (q.Position - eye).Magnitude
					if not bestD or d < bestD then point, bestD = q, d end
				end
			end
		end
		if point then
			local bob = math.sin(os.clock() * 6)
			marker.Position = point.Position + (eye - point.Position).Unit * 0.5 + Vector3.new(0, 0.15 * bob, 0)
			marker.Size = Vector3.one * (0.4 + 0.08 * bob)
			marker.Transparency = 0.25
		else
			marker.Transparency = 1
		end
		-- nothing left that you can see from here: the turntable turns it round (if it's
		-- still hidden after turning both ways, it counts as done)
		if left > 0 and idle > RUST.TurnAfter and os.clock() >= nextLook then
			nextLook = os.clock() + 0.5
			local rest = todo()
			local any = false
			for _, q in rest do
				if seen(q) then any = true break end
			end
			if not any and stuck >= 2 then
				for _, q in rest do
					local s2 = st[q]
					s2.done = s2.need
					left -= 1
					for _ = 1, 3 do addFoam(s2, q.Position, flat(eye - q.Position)) end
				end
				ctx.unglow()
			elseif not any then
				stuck += 1
				spin(math.pi, 1.2)
			end
		end
	end
	ctx.unglow()
	suds:Destroy()
	marker:Destroy()

	-- 3. the sponge goes back in the bucket and the lance comes off its hook
	do
		local from = sponge:GetPivot()
		tween(0.35, function(a)
			local k = smoothstep(a)
			sponge:ScaleTo(handScale + (baseScale - handScale) * k)
			local q = from.Position:Lerp(spongeHome.Position, k) + Vector3.new(0, math.sin(a * math.pi) * 0.8, 0)
			sponge:PivotTo(CFrame.new(q) * (from - from.Position):Lerp(spongeHome - spongeHome.Position, k))
		end)
		sponge:ScaleTo(baseScale)
		sponge:PivotTo(spongeHome)
		ctx.puff(pail + Vector3.new(0, 0.8, 0), Color3.fromRGB(230, 245, 255), 5)
	end
	ctx.setInstruction("Rinse off the foam!", o.step)
	local hold, put = M.holder(lance, lance.GunBody, lance.Nozzle)
	local world = table.clone(solid)
	for _, d in bay:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not d:IsDescendantOf(lance) then table.insert(world, d) end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = world
	local fromAt = Instance.new("Attachment")
	fromAt.Parent = lance.Nozzle
	local hitAt = Instance.new("Attachment")
	hitAt.Parent = workspace.Terrain
	local jet = Instance.new("Beam")
	jet.Attachment0, jet.Attachment1 = fromAt, hitAt
	jet.Width0, jet.Width1 = 0.05, 0.26 * jetMul
	jet.Segments = 6
	jet.FaceCamera = true
	jet.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(170, 215, 255))
	jet.Transparency = NumberSequence.new(0.1, 0.45)
	jet.LightEmission = 0.5
	jet.Enabled = false
	jet.Parent = lance.Nozzle
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(225, 242, 255))
	mist.Size = NumberSequence.new(0.15, 0.55)
	mist.Transparency = NumberSequence.new(0.35, 1)
	mist.Lifetime = NumberRange.new(0.2, 0.4)
	mist.Speed = NumberRange.new(2, 4)
	mist.SpreadAngle = Vector2.new(70, 70)
	mist.Rate = 45
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Enabled = false
	mist.Parent = hitAt
	local hiss = Instance.new("Sound")
	hiss.SoundId = "rbxasset://sounds/action_swim.mp3"
	hiss.Looped = true
	hiss.Volume = 0
	hiss.PlaybackSpeed = 1.35
	hiss.Parent = camera
	hiss:Play()

	-- 4. rinse: the jet melts the foam where it hits; a part with no foam left is clean
	local cleaned, total = 0, #o.parts
	local function blobCount()
		local n = 0
		for _, s in st do n += #s.blobs end
		return n
	end
	local blobsAll = blobCount()
	if ctx.setBar then ctx.setBar(0) end
	local aim, normal = nil, Vector3.yAxis
	local idle2, nextLook2, stuck2, hint = 0, 0, 0, nil
	while true do
		local dt = RunService.RenderStepped:Wait()
		local pointer, spraying = ctx.input()
		local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
		local dirn = ray.Direction.Unit
		local hit = workspace:Raycast(ray.Origin, dirn * 80, rayParams)
		local target = hit and hit.Position or (ray.Origin + dirn * 10)
		aim = aim and aim:Lerp(target, damp(30, dt)) or target
		if hit then
			local n = normal:Lerp(hit.Normal, damp(20, dt))
			if n.Magnitude > 1e-3 then normal = n.Unit end
		end
		hold(dt, aim)
		hitAt.WorldCFrame = CFrame.lookAt(aim, aim + normal) * CFrame.Angles(-math.pi / 2, 0, 0)
		jet.Enabled, mist.Enabled = spraying, spraying
		hiss.Volume += ((spraying and 0.45 or 0) - hiss.Volume) * damp(14, dt)
		local melted = false
		if spraying then
			local depth = hit and (hit.Position - ray.Origin):Dot(dirn) or math.huge
			for _, s in st do
				for k = #s.blobs, 1, -1 do
					local f = s.blobs[k]
					local rel = f.Position - ray.Origin
					local along = rel:Dot(dirn)
					local off = (rel - dirn * along).Magnitude
					local reach = 0.5 * jetMul + fullSize[f].X * 0.5
					if along < depth + 0.8 and off < reach then
						melted = true
						hp[f] -= dt * RUST.Rinse * jetMul * (1 - 0.5 * off / reach)
						if hp[f] <= 0 then
							table.remove(s.blobs, k)
							ctx.puff(f.Position, Color3.fromRGB(235, 245, 255), 2)
							f:Destroy()
						else
							f.Size = fullSize[f] * (0.25 + 0.75 * hp[f])
							f.Transparency = (1 - hp[f]) * 0.5
						end
					end
				end
			end
		end
		-- a part with its foam all gone comes up clean metal
		for p, s in st do
			if not s.clean and #s.blobs == 0 then
				s.clean = true
				cleaned += 1
				p.Material = o.clean[p].Material
				local c0 = p.Color
				task.spawn(tween, 0.35, function(a) p.Color = c0:Lerp(o.clean[p].Color, a) end)
				ctx.sparkle(p.Position)
				ctx.sfx(ctx.SFX.Done, 0.45, 1.15 + cleaned * 0.08)
			end
		end
		if cleaned >= total then break end
		-- most of the foam is off: the last bits run off by themselves
		local rinsed = 1 - blobCount() / math.max(blobsAll, 1)
		if ctx.setBar then ctx.setBar(rinsed / RUST.RinseAccept) end
		if rinsed >= RUST.RinseAccept then
			for _, s in st do
				for _, f in s.blobs do
					if f:IsA("BasePart") then ctx.puff(f.Position, Color3.fromRGB(235, 245, 255), 1) end
					f:Destroy()
				end
				table.clear(s.blobs)
			end
			continue -- next frame the parts come up clean
		end
		idle2 = melted and 0 or idle2 + dt
		if melted then stuck2 = 0 end
		-- the foam that's left glows through the scooter once you've lost track of it
		local blobs = foamModel:GetChildren()
		if not hint and (idle2 > RUST.HintAfter or #blobs <= 6) then
			hint = Instance.new("Highlight")
			hint.Adornee = foamModel
			hint.FillColor = Color3.fromRGB(150, 215, 255)
			hint.OutlineColor = Color3.fromRGB(220, 245, 255)
			hint.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hint.Parent = foamModel
		end
		if hint then
			local pulse = 0.45 + math.sin(os.clock() * 7) * 0.2
			hint.FillTransparency = pulse
			hint.OutlineTransparency = math.max(0, pulse - 0.3)
		end
		-- none of it in sight: the turntable turns it round (still hidden both ways: it
		-- runs off by itself)
		if idle2 > RUST.TurnAfter and os.clock() >= nextLook2 then
			nextLook2 = os.clock() + 0.5
			local any = false
			for _, f in blobs do
				if f:IsA("BasePart") and blobSeen(f) then any = true break end
			end
			if not any and stuck2 >= 2 then
				for _, s in st do
					for _, f in s.blobs do f:Destroy() end
					table.clear(s.blobs)
				end
			elseif not any then
				stuck2 += 1
				spin(math.pi, 1.2)
			end
		end
	end
	if ctx.setBar then ctx.setBar(nil) end
	jet:Destroy()
	hitAt:Destroy()
	fromAt:Destroy()
	hiss:Destroy()
	foamModel:Destroy()
	ctx.sfx(ctx.SFX.Done, 0.7, 1.3)
	put(0.4)
	if turned % (2 * math.pi) ~= 0 then spin(2 * math.pi - turned % (2 * math.pi), 1.2) end
end

---------------------------------------------------------------- spin guide
-- A ring of dots round the wheel, facing you. A bright dot runs round it to show the
-- move (hint(true)); progress(p, dir) lights the dots from the top, the way you're going.
function M.ring(center, radius)
	local camera = workspace.CurrentCamera
	local toCam = (camera.CFrame.Position - center).Unit
	local at = center + toCam * 0.2
	local face = CFrame.lookAt(at, at - toCam) -- +X = right as you see it
	local N = 24
	local model = Instance.new("Model")
	model.Name = "SpinGuide"
	local dots = {}
	local function onRing(a, r) return face * CFrame.new(math.sin(a) * r, math.cos(a) * r, 0) end
	for k = 1, N do
		local d = ball("Dot", 0.1, Color3.new(1, 1, 1), Enum.Material.Neon)
		d.Transparency = 0.5
		d.CFrame = onRing((k - 1) / N * math.pi * 2, radius)
		d.Parent = model
		dots[k] = d
	end
	local runner = {}
	for i = 1, 4 do
		local r = ball("Runner", 0.24 - i * 0.035, Color3.fromRGB(255, 225, 90), Enum.Material.Neon)
		r.Parent = model
		runner[i] = r
	end
	model.Parent = workspace
	local showing, t0 = true, os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) * math.pi * 2 * 0.8 -- clockwise as you see it
		for i, r in runner do
			r.Transparency = showing and (i - 1) * 0.2 or 1
			r.CFrame = onRing(a - (i - 1) * 0.22, radius) * CFrame.new(0, 0, 0.03)
		end
	end)
	local api = {}
	function api.hint(on)
		if on and not showing then t0 = os.clock() end
		showing = on
	end
	function api.progress(p, dir)
		local lit = math.floor(math.clamp(p, 0, 1) * N + 0.5)
		for k, d in dots do
			local idx = (dir or 1) >= 0 and k or ((N - k + 1) % N) + 1
			local on = idx <= lit
			d.Color = on and GREEN or Color3.new(1, 1, 1)
			d.Transparency = on and 0 or 0.5
			d.Size = Vector3.one * (on and 0.14 or 0.1)
		end
	end
	function api.destroy()
		conn:Disconnect()
		model:Destroy()
	end
	return api
end

return M
