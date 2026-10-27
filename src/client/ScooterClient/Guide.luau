-- What to do next, outside a fix (owner, 24 Oct: "some props don't get highlighted so i have no clue what to
-- do"). The one thing to go to glows gold, and while it's far away a trail of chevrons on the floor points the
-- way. ScooterClient decides the target (customer waiting -> bench, bin full -> bin, carrying trash ->
-- dumpster, night -> the upgrade stand).
-- Owner, 24 Oct (clutter): the gold glow is always on, but the floor chevrons only come out once you haven't got
-- any closer to the target for STUCK seconds.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local G = {}
local GOLD = Color3.fromRGB(255, 196, 61)
local COUNT, SPACING, NEAR = 7, 3.2, 11
local STUCK = 8 -- seconds without getting closer before the chevrons show
local bestDist, lastProgress = math.huge, 0

local target
local folder = Instance.new("Folder")
folder.Name = "GuideTrail"
folder.Parent = workspace
local hl = Instance.new("Highlight")
hl.Name = "GuideGlow"
hl.FillColor = GOLD
hl.OutlineColor = GOLD
hl.DepthMode = Enum.HighlightDepthMode.Occluded
hl.Enabled = false
hl.Parent = folder

-- one chevron: two thin bars in a > shape, lying on the floor
local chevrons = {}
for i = 1, COUNT do
	local m = Instance.new("Model")
	m.Name = "Chevron"
	local arms = {}
	for _, s in { -1, 1 } do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = GOLD
		p.Size = Vector3.new(0.28, 0.06, 1.25)
		p.Transparency = 1
		p.Parent = m
		table.insert(arms, { part = p, side = s })
	end
	m.Parent = folder
	chevrons[i] = arms
end

local function place(arms, cf, alpha)
	for _, a in arms do
		-- cf looks along the way to go: each arm runs from the tip back (+Z) and out to one side, a > shape
		a.part.CFrame = cf * CFrame.Angles(0, a.side * math.rad(38), 0) * CFrame.new(0, 0, 0.5)
		a.part.Transparency = alpha
	end
end

local function hideTrail()
	for _, arms in chevrons do
		for _, a in arms do a.part.Transparency = 1 end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function targetPos()
	if not target or not target.Parent then return nil end
	if target:IsA("Model") then return target:GetPivot().Position end
	return target.Position
end

-- inst: a Model or BasePart to go to, or nil
function G.set(inst)
	if inst == target then return end
	target = inst
	bestDist, lastProgress = math.huge, os.clock()
	hl.Adornee = inst
	hl.Enabled = inst ~= nil
	if not inst then hideTrail() end
end

function G.get()
	return target
end

RunService.RenderStepped:Connect(function()
	if not target then return end
	local t = os.clock()
	hl.FillTransparency = 0.55 + math.sin(t * 5) * 0.2
	hl.OutlineTransparency = 0.1
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local goal = targetPos()
	if not root or not goal then hideTrail() return end
	local flat = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	local dist = flat.Magnitude
	if dist < bestDist - 1 then bestDist, lastProgress = dist, t end
	if dist < NEAR or t - lastProgress < STUCK then hideTrail() return end
	local dir = flat.Unit
	rayParams.FilterDescendantsInstances = { char, folder }
	local scroll = (t * 4) % SPACING
	for i, arms in chevrons do
		local along = 2.5 + (i - 1) * SPACING + scroll
		if along > dist - 3 then
			place(arms, CFrame.new(), 1)
		else
			local p = root.Position + dir * along
			local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), rayParams)
			local y = hit and hit.Position.Y + 0.08 or root.Position.Y - 2.9
			-- fade in at the near end, out at the far end
			local fade = math.min(1, (along - 2.5) / 2, (dist - 3 - along) / 3)
			place(arms, CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z) + dir), 1 - 0.85 * math.clamp(fade, 0, 1))
		end
	end
end)

return G
