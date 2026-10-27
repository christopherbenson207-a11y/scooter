-- This player's garage: which plot they were given, the model the server built for it
-- (same layout as the Workspace.Garage template) and helpers for plot-relative maths.
-- The gameplay code is written in "plot 0 space" (the template's own coordinates);
-- PF maps that space onto this player's plot, RF is just its rotation.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CENTER = Vector3.new(-4, 0, -133)
local M = {}

local k = player:GetAttribute("Plot")
while k == nil do
	player:GetAttributeChangedSignal("Plot"):Wait()
	k = player:GetAttribute("Plot")
end
M.index = k
M.PF = CFrame.new(CENTER) * CFrame.Angles(0, math.rad(60 * k), 0) * CFrame.new(-CENTER)
M.RF = M.PF - M.PF.Position
M.garage = workspace:WaitForChild("Plots"):WaitForChild("Plot" .. k)

function M.toLocal(p) return M.PF:PointToObjectSpace(p) end -- world point -> plot 0 space
function M.toWorld(p) return M.PF:PointToWorldSpace(p) end -- plot 0 point -> world
function M.vec(v) return M.RF * v end -- a plot 0 direction or offset -> world
function M.ivec(v) return M.RF:Inverse() * v end -- a world direction -> plot 0
function M.rot(cf) return M.RF * cf * M.RF:Inverse() end -- a rotation about plot 0 axes -> about this plot's axes

-- Other players' garages are for looking at: their counters and prompts belong to them.
local function quiet(model)
	if model == M.garage then return end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then d.Enabled = false end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then d.Enabled = false end
	end)
end
local plots = workspace.Plots
for _, m in plots:GetChildren() do quiet(m) end
plots.ChildAdded:Connect(function(m)
	task.wait()
	quiet(m)
end)

return M
