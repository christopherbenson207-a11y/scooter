-- Skill (owner, 24 Oct: "it should be fun but also punishing and rewarding, lenient too"). Timing minigames
-- report every tap as "perfect" (the gold middle of the green), "good" (the rest of the green) or "miss".
-- Perfects in a row build a combo that pops up where you tapped; a miss shakes the camera, breaks the combo
-- and costs Config.MissSeconds (FinishJob adds them to the job's time). Each perfect pays Config.SkillPerfect
-- of the repair on top.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Style = require(RS:WaitForChild("UIStyle"))
local C = Style.Color
local Skill = {}
local env -- { camera, sfx, SFX, config }
local perfect, miss, combo = 0, 0, 0

function Skill.init(e)
	env = e
end

function Skill.reset()
	perfect, miss, combo = 0, 0, 0
end

-- what FinishJob gets
function Skill.report()
	return { Perfect = perfect, Miss = miss }
end

function Skill.counts()
	return perfect, miss, combo
end

-- Parallel bench: each job in flight keeps its own counts. save() when a job is parked, load() when it
-- comes back to the bench (load(nil) = a fresh job, from zero).
function Skill.save()
	return { perfect = perfect, miss = miss, combo = combo }
end
function Skill.load(t)
	if t then
		perfect, miss, combo = t.perfect, t.miss, t.combo
	else
		perfect, miss, combo = 0, 0, 0
	end
end

-- A word that pops up at a world point and floats off.
local function float(at, text, color, big)
	local anchor = Instance.new("Part")
	anchor.Name = "SkillPop"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(at)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 60)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0.6, 0)
	bb.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Style.Font.Chunky
	label.Text = text
	label.TextSize = big and 40 or 30
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Ink
	stroke.Thickness = 3
	stroke.Parent = label
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = label
	label.Parent = bb
	anchor.Parent = workspace
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0) }):Play()
	task.delay(0.55, function()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end)
	task.delay(1, function() anchor:Destroy() end)
end

-- A short jolt that works on top of whatever else moves the camera.
local function shake(power)
	local cam = env.camera
	local prev = CFrame.identity
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local k = math.max(0, 1 - t / 0.3) * power
		local off = t < 0.3 and CFrame.Angles(math.rad((math.random() - 0.5) * 3 * k), math.rad((math.random() - 0.5) * 3 * k), 0) or CFrame.identity
		cam.CFrame = cam.CFrame * prev:Inverse() * off
		prev = off
		if t >= 0.3 then conn:Disconnect() end
	end)
end

-- kind = "perfect" | "good" | "miss"; at = where it happened (a Vector3); word = what a miss says ("TOO MUCH!")
function Skill.hit(kind, at, word)
	if kind == "perfect" then
		perfect += 1
		combo += 1
		float(at, combo >= 2 and ("PERFECT x%d"):format(combo) or "PERFECT!", C.Gold, combo >= 3)
		env.sfx(env.SFX.Done, 0.7, 1.15 + math.min(combo, 8) * 0.08)
	elseif kind == "good" then
		combo = 0
		float(at, "GOOD", C.Cash)
		env.sfx(env.SFX.Done, 0.5, 1.05)
	else
		miss += 1
		combo = 0
		float(at, ("%s  -%ds"):format(word or "MISS", env.config.MissSeconds), C.Stop, true)
		env.sfx(env.SFX.Miss, 0.8)
		shake(1)
	end
end

return Skill
