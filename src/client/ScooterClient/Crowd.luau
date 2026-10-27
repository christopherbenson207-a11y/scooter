-- Everyone's customers, the plaza clock and every garage's OPEN sign.
-- A customer who steps off the bus is drawn walking past the other garages to the one they
-- chose, on every screen. Your own customers carry your real jobs, so the main script draws
-- those; here we draw everybody else's, from the server's CustomerSpawned / CustomerLeft.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local M = {}
local ANIM = { Walk = "rbxassetid://507777826", Idle = "rbxassetid://507766388" }
local GREEN, RED = Color3.fromRGB(120, 230, 130), Color3.fromRGB(225, 70, 70)
local SLATE, CREAM, AMBER = Color3.fromRGB(60, 64, 78), Color3.fromRGB(245, 238, 222), Color3.fromRGB(255, 196, 61)

local env, speed
local rigs = {} -- [customerId] = rig (waiting or walking to their garage)
local left = {} -- customers who already went home (a leave can arrive before their rig is built)
local active = {} -- every rig that is still drawn, including ones walking home

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function play(rig, which)
	if rig.playing == which then return end
	rig.playing = which
	if rig.track then rig.track:Stop(0.2) end
	local track = rig.tracks[which]
	if not track then
		local hum = rig.model:FindFirstChildOfClass("Humanoid")
		local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = ANIM[which]
			local ok, t = pcall(function() return animator:LoadAnimation(a) end)
			if ok then track = t; rig.tracks[which] = t end
		end
	end
	if track then
		track.Looped = true
		track:Play(0.2)
	end
	rig.track = track
end

local function stand(rig, pos, facing)
	rig.model:PivotTo(CFrame.new(pos.X, rig.standY, pos.Z) * (facing or CFrame.identity))
end

-- walk `pts` (world positions) at walking pace; `faceEnd` is the pose on arrival; `done` runs then
local function walk(rig, pts, faceEnd, done)
	rig.path, rig.faceEnd, rig.done = pts, faceEnd, done
	rig.cum = { 0 }
	for i = 2, #pts do rig.cum[i] = rig.cum[i - 1] + flat(pts[i] - pts[i - 1]).Magnitude end
	rig.total = rig.cum[#pts]
	rig.travel = rig.skip or 0
	rig.skip = nil
	rig.walking = true
	play(rig, "Walk")
end

local function finish(rig)
	rig.walking = false
	local last = rig.path[#rig.path]
	stand(rig, last, rig.faceEnd)
	play(rig, "Idle")
	local done = rig.done
	rig.done = nil
	if done then done(rig) end
end

local function destroy(rig)
	rig.dead = true
	if rig.model then rig.model:Destroy() end
end

RunService.Heartbeat:Connect(function(dt)
	for i = #active, 1, -1 do
		local rig = active[i]
		if rig.dead then
			table.remove(active, i)
		elseif rig.walking then
			rig.travel += dt * speed
			if rig.travel >= rig.total then
				finish(rig)
			else
				local k = 2
				while rig.cum[k] < rig.travel do k += 1 end
				local a, b = rig.path[k - 1], rig.path[k]
				local seg = rig.cum[k] - rig.cum[k - 1]
				local t = seg > 0 and (rig.travel - rig.cum[k - 1]) / seg or 1
				local pos = a:Lerp(b, t)
				local dirv = flat(b - a)
				stand(rig, pos, dirv.Magnitude > 0.01 and CFrame.lookAt(Vector3.zero, dirv) or nil)
			end
		end
	end
end)

local function makeRig(info)
	local pool = RS.Customers:GetChildren()
	math.randomseed(info.Seed) -- the same look the owner's own screen gives this customer
	local model = pool[math.random(#pool)]:Clone()
	env.dress(model)
	math.randomseed(os.time() + math.floor(os.clock() * 1000))
	local hum, hrp = model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then model:Destroy() return nil end
	hrp.Anchored = true
	local rig = { id = info.Id, plot = info.Plot, model = model, tracks = {}, standY = 0.6 + hum.HipHeight + hrp.Size.Y / 2 }
	model.Parent = workspace
	table.insert(active, rig)
	return rig
end

local function waitingAt(plot)
	local n = 0
	for _, r in rigs do
		if r.plot == plot then n += 1 end
	end
	return n
end

-- A customer chose somebody else's garage: walk from the bus stop to its hatch, then round to the yard.
function M.spawn(info, age)
	if info.Owner == player.UserId or rigs[info.Id] or left[info.Id] then return end
	local plots = workspace:FindFirstChild("Plots")
	local plotModel = plots and plots:WaitForChild("Plot" .. info.Plot, 8)
	if not plotModel or rigs[info.Id] or left[info.Id] then return end
	local arrive, hatch = plotModel:WaitForChild("CustomerArrive"), plotModel:WaitForChild("HandoverSpot")
	local corner = plotModel:WaitForChild("StreetCorner")
	local rig = makeRig(info)
	if not rig then return end
	local slot = math.min(waitingAt(info.Plot) + 1, 4)
	rigs[info.Id] = rig
	local spot = plotModel:WaitForChild("WaitSpot" .. slot)
	rig.route = env.crowd.route(arrive.Position, true)
	rig.corner = corner.Position
	local toHatch = table.clone(rig.route)
	table.insert(toHatch, hatch.Position)
	local toYard = { hatch.Position, corner.Position, spot.Position }
	local faceSpot = spot.CFrame - spot.CFrame.Position
	stand(rig, toHatch[1])
	-- late joiners: skip the part of the walk that has already happened
	local skip = (age or 0) * speed
	local total1 = env.crowd.length(toHatch)
	local function yard()
		walk(rig, toYard, faceSpot)
	end
	if skip >= total1 + speed then
		rig.skip = skip - total1 - speed
		yard()
	else
		rig.skip = skip
		walk(rig, toHatch, nil, function()
			task.delay(1, function()
				if rigs[info.Id] == rig and not rig.dead then yard() end
			end)
		end)
	end
end

-- Their scooter is fixed (or they gave up): walk home along the way they came. `gone` = the garage vanished.
function M.leave(id, angry, gone)
	left[id] = true
	local rig = rigs[id]
	if not rig then return end
	rigs[id] = nil
	if gone or not rig.route then destroy(rig) return end
	local pts = { rig.corner }
	for i = #rig.route, 1, -1 do table.insert(pts, rig.route[i]) end
	rig.skip = nil
	walk(rig, pts, nil, destroy)
end

---------------------------------------------------------------- clocks and signs
local function updateClocks()
	local night = workspace:GetAttribute("Phase") == "Night"
	local left = math.max(0, math.floor((workspace:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
	local day = workspace:GetAttribute("DayNumber") or 1
	local time = ("%d:%02d"):format(left // 60, left % 60)

	local plaza = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plaza")
	local clock = plaza and plaza:FindFirstChild("Clock")
	local face = clock and clock:FindFirstChild("Face")
	if face then
		face.Color = night and SLATE or CREAM
		for _, sg in face:GetChildren() do
			if sg:IsA("SurfaceGui") then
				sg.Top.Text = ("DAY %d"):format(day)
				sg.Time.Text = time
				sg.Sub.Text = night and "until dawn" or "until dusk"
				sg.Top.TextColor3 = night and CREAM or SLATE
				sg.Time.TextColor3 = night and AMBER or SLATE
				sg.Sub.TextColor3 = night and Color3.fromRGB(190, 195, 210) or Color3.fromRGB(100, 106, 124)
			end
		end
	end

	-- every garage's OPEN / CLOSED sign (the shared clock, so they all agree)
	local plots = workspace:FindFirstChild("Plots")
	for _, plot in (plots and plots:GetChildren() or {}) do
		local sign = plot:FindFirstChild("OpenSign")
		local board = sign and sign:FindFirstChild("Board")
		if board then
			for _, g in board:GetChildren() do
				if g:IsA("SurfaceGui") and g:FindFirstChild("Title") and g:FindFirstChild("Sub") then
					g.Title.Text = night and "CLOSED" or "OPEN"
					g.Title.TextColor3 = night and RED or GREEN
					g.Sub.Text = night and ("NIGHT  " .. time) or ("DAY %d  %s"):format(day, time)
				end
			end
		end
	end
end

-- env = { dress = SCOOTER_FX.dress, crowd = ScooterCrowd, config = Config, remotes = Remotes }
function M.start(e)
	env = e
	speed = e.config.WalkSpeed or 14
	task.spawn(function()
		while true do
			updateClocks()
			task.wait(0.5)
		end
	end)
	e.remotes.CustomerSpawned.OnClientEvent:Connect(function(info) M.spawn(info, 0) end)
	e.remotes.CustomerLeft.OnClientEvent:Connect(M.leave)
	-- customers who were already walking or waiting when we arrived
	task.spawn(function()
		local ok, list = pcall(function() return e.remotes.GetCrowd:InvokeServer() end)
		if ok and type(list) == "table" then
			for _, info in list do task.spawn(M.spawn, info, info.Age) end
		end
	end)
end

return M
