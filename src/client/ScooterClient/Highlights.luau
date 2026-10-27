-- Highlight budget (plan/11). Roblox draws only about 31 Highlights at once and silently skips the rest, so a
-- full yard of outlined customers could hide the glow on the part you need to fix. This keeps the total under
-- BUDGET: every Highlight that isn't a cartoon outline (part glows, the guide glow, minigame hints, VIPs) is
-- "important" and never touched here. The cartoon outlines (workspace.CelOutlines) share what's left, nearest
-- to the camera first, and only within RANGE studs.
-- In Studio, workspace attribute HighlightsLive shows how many are switched on.
local RunService = game:GetService("RunService")

local M = {}
M.BUDGET = 28
M.RANGE = 60

local important = {} -- [Highlight] = true
local outlines = {} -- [Highlight] = true
local inkFolder

local function track(h)
	if not h:IsA("Highlight") then return end
	if inkFolder and h:IsDescendantOf(inkFolder) then outlines[h] = true else important[h] = true end
	h.Destroying:Connect(function()
		important[h] = nil
		outlines[h] = nil
	end)
end

local function where(h)
	local a = h.Adornee or h.Parent
	if not a then return nil end
	if a:IsA("Model") then return a:GetPivot().Position end
	if a:IsA("BasePart") then return a.Position end
	return nil
end

local function step()
	local used = 0
	for h in important do
		if h.Enabled and h.Parent then used += 1 end
	end
	local room = math.max(0, M.BUDGET - used)
	local cam = workspace.CurrentCamera.CFrame.Position
	local list = {}
	for h in outlines do
		if h.Parent then
			local p = where(h)
			local d = p and (p - cam).Magnitude or math.huge
			table.insert(list, { h = h, d = d })
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local on = 0
	for _, e in list do
		local want = on < room and e.d <= M.RANGE
		if want then on += 1 end
		if e.h.Enabled ~= want then e.h.Enabled = want end
	end
	if RunService:IsStudio() then
		workspace:SetAttribute("HighlightsLive", used + on)
		if used > M.BUDGET then warn(("Highlights: %d important ones alone are over the budget of %d"):format(used, M.BUDGET)) end
	end
end

function M.init()
	inkFolder = workspace:WaitForChild("CelOutlines", 10)
	for _, d in workspace:GetDescendants() do track(d) end
	workspace.DescendantAdded:Connect(track)
	task.spawn(function()
		while true do
			local ok, err = pcall(step)
			if not ok then warn("Highlights: " .. tostring(err)) end
			task.wait(0.25)
		end
	end)
end

return M
