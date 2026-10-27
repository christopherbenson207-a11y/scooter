-- Garages belong to players: one is built for each player who joins (in the next free
-- slot round the plaza) and removed again when they leave, so a server with three
-- players has three garages. The editable garage stays in Workspace.Garage in Edit
-- mode; when the game runs it becomes the template these are cloned from.
-- Owner, 24 Oct: every plot's pavement is always there (Workspace.Map.PlotPads.Pad0-5: yard, paths, hedge,
-- benches, a slab and a FREE PLOT sign); the garage itself only comes with its player. Parts tagged FreeOnly
-- (the slab and the sign) hide while a garage stands on the pad.
local ServerStorage = game:GetService("ServerStorage")

local M = {}
M.MAX = 6
M.CENTER = Vector3.new(-4, 0, -133) -- the plaza; plot k is plot 0 turned 60 * k degrees about it

local template
local folder = Instance.new("Folder")
folder.Name = "Plots"
local slots = {} -- [index] = { player = ..., model = ... }

function M.frame(k)
	return CFrame.new(M.CENTER) * CFrame.Angles(0, math.rad(60 * k), 0) * CFrame.new(-M.CENTER)
end

-- free = the slab and FREE PLOT sign show; taken = they hide under the garage
local function setFree(k, free)
	local pads = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("PlotPads")
	local pad = pads and pads:FindFirstChild("Pad" .. k)
	if not pad then return end
	for _, d in pad:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("FreeOnly") then
			d.Transparency = free and 0 or 1
			d.CanCollide = free
			d.CanQuery = free
		elseif d:IsA("SurfaceGui") then
			d.Enabled = free
		end
	end
end

function M.init()
	local previews = workspace:FindFirstChild("Plots")
	if previews then previews:Destroy() end
	folder.Parent = workspace
	local g = workspace:FindFirstChild("Garage")
	if g then
		g.Name = "GarageTemplate"
		g.Parent = ServerStorage
		template = g
	else
		template = ServerStorage:FindFirstChild("GarageTemplate")
	end
	assert(template, "no Workspace.Garage to use as the garage template")
	for k = 0, M.MAX - 1 do setFree(k, true) end
end

function M.indexOf(player)
	for k, s in slots do
		if s.player == player then return k end
	end
end

-- Gives the player the lowest free plot and builds their garage there (nil = server full).
function M.assign(player)
	local have = M.indexOf(player)
	if have then return have end
	local k
	for i = 0, M.MAX - 1 do
		if not slots[i] then k = i break end
	end
	if not k then return nil end
	local model = Instance.new("Model")
	model.Name = "Plot" .. k
	for _, c in template:GetChildren() do c:Clone().Parent = model end
	model:PivotTo(M.frame(k) * model:GetPivot())
	model:SetAttribute("Plot", k)
	model:SetAttribute("Owner", player.UserId)
	slots[k] = { player = player, model = model }
	local spawn = model:FindFirstChild("PlotSpawn")
	if spawn then player.RespawnLocation = spawn end
	model.Parent = folder
	setFree(k, false)
	player:SetAttribute("Plot", k)
	return k
end

function M.release(player)
	local k = M.indexOf(player)
	if not k then return end
	local s = slots[k]
	slots[k] = nil
	if s.model then s.model:Destroy() end
	setFree(k, true)
end

-- World position of this player's CustomerArrive marker (customers walk there from the bus stop).
function M.arrivePosition(player)
	local k = M.indexOf(player)
	local model = k and slots[k].model
	local marker = model and model:FindFirstChild("CustomerArrive")
	return marker and marker.Position
end

-- The plot's garage model, for anything that needs to look at it.
function M.modelOf(player)
	local k = M.indexOf(player)
	return k and slots[k].model
end

-- The rating readout: a compact world-locked BillboardGui over the sign (plan/12) — constant
-- size, never grows or clutters, reads across the plaza. Same fields as the old panel, so
-- nothing above this module changes.
function M.sign(player)
	local k = M.indexOf(player)
	local model = k and slots[k].model
	local sign = model and model:FindFirstChild("Sign")
	if not sign then return nil end
	local anchor = sign:FindFirstChild("Rating") or sign:FindFirstChildWhichIsA("BasePart")
	for _, d in anchor:GetDescendants() do
		if d:IsA("SurfaceGui") then d.Enabled = false end -- the old built-on panel stands down
	end
	local bb = anchor:FindFirstChild("RatingBillboard")
	if not bb then
		local Style
		pcall(function() Style = require(game:GetService("ReplicatedStorage"):WaitForChild("UIStyle")) end)
		bb = Instance.new("BillboardGui")
		bb.Name = "RatingBillboard"
		bb.Adornee = anchor
		bb.Size = UDim2.fromOffset(240, 78)
		bb.MaxDistance = 300
		bb.LightInfluence = 0
		bb.ResetOnSpawn = false
		-- sit ON TOP of the garage: measured from the plot's bounding box, so the plate hangs
		-- over the roofline whatever the sign part's height (owner: "on top of my garage like before")
		do
			local cf, size = model:GetBoundingBox()
			local top = (cf.Position + Vector3.new(0, size.Y / 2, 0)).Y
			bb.StudsOffsetWorldSpace = Vector3.new(0, math.max(8, top - anchor.Position.Y + 2.5), 0)
		end
		-- drop shadow
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.Position = UDim2.fromScale(0.5, 0.5)
		shadow.Size = UDim2.fromScale(1, 1)
		shadow.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
		shadow.BackgroundTransparency = 0.55
		shadow.ZIndex = 0
		Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 12)
		shadow.Parent = bb
		-- paper plate in the game's ticket language
		local plate = Instance.new("Frame")
		plate.Name = "Plate"
		plate.Size = UDim2.fromScale(1, 1)
		plate.BackgroundColor3 = (Style and Style.Color.Panel) or Color3.fromRGB(236, 238, 246)
		Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 10)
		local st = Instance.new("UIStroke", plate)
		st.Color = (Style and Style.Color.Ink) or Color3.fromRGB(18, 19, 25)
		st.Thickness = 3
		plate.Parent = bb
		-- orange title band with the garage owner's name
		local band = Instance.new("Frame")
		band.Name = "Band"
		band.Size = UDim2.fromScale(1, 0.38)
		band.BackgroundColor3 = (Style and Style.Color.Orange) or Color3.fromRGB(255, 140, 30)
		Instance.new("UICorner", band).CornerRadius = UDim.new(0, 10)
		local bandFlat = Instance.new("Frame")
		bandFlat.AnchorPoint = Vector2.new(0.5, 1)
		bandFlat.Position = UDim2.fromScale(0.5, 1)
		bandFlat.Size = UDim2.new(1, 0, 0.5, 0)
		bandFlat.BackgroundColor3 = band.BackgroundColor3
		bandFlat.BorderSizePixel = 0
		bandFlat.ZIndex = band.ZIndex
		bandFlat.Parent = band
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.fromScale(1, 1)
		title.BackgroundTransparency = 1
		title.TextColor3 = Color3.new(1, 1, 1)
		title.FontFace = (Style and Style.Font.Chunky) or Font.new("rbxasset://fonts/families/FredokaOne.json")
		title.TextScaled = true
		local pad = Instance.new("UIPadding", title)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0.07, 0), UDim.new(0.07, 0)
		title.Parent = band
		-- star row (real star icons) + a score chip, like the job card's pay chip
		local row = Instance.new("Frame")
		row.Name = "Row"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0.06, 0.46)
		row.Size = UDim2.fromScale(0.88, 0.44)
		row.Parent = plate
		local rl = Instance.new("UIListLayout", row)
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.VerticalAlignment = Enum.VerticalAlignment.Center
		rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rl.Padding = UDim.new(0.012, 0)
		for i = 1, 5 do
			local s = Instance.new("ImageLabel")
			s.Name = "Star" .. i
			s.BackgroundTransparency = 1
			s.Size = UDim2.fromScale(0.15, 1)
			s.Image = (Style and Style.Icon.Star) or "rbxassetid://132192590966199"
			s.ImageColor3 = (Style and Style.Color.StarOff) or Color3.fromRGB(70, 74, 96)
			s.ScaleType = Enum.ScaleType.Fit
			s.Parent = row
		end
		local chip = Instance.new("Frame")
		chip.Name = "ScoreChip"
		chip.Size = UDim2.fromScale(0.24, 0.92)
		chip.BackgroundColor3 = (Style and Style.Color.Enamel) or Color3.fromRGB(60, 64, 78)
		Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
		chip.Parent = row
		local score = Instance.new("TextLabel")
		score.Name = "Score"
		score.Size = UDim2.fromScale(1, 1)
		score.BackgroundTransparency = 1
		score.TextColor3 = (Style and Style.Color.Mint) or Color3.fromRGB(110, 215, 195)
		score.FontFace = (Style and Style.Font.Mono) or Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Bold)
		score.TextScaled = true
		local sp = Instance.new("UIPadding", score)
		sp.PaddingTop, sp.PaddingBottom = UDim.new(0.14, 0), UDim.new(0.14, 0)
		score.Parent = chip
		bb.Parent = anchor
		-- the offset was measured before the bb existed; apply it now that bb is built
		do
			local cf2, size2 = model:GetBoundingBox()
			local top = (cf2.Position + Vector3.new(0, size2.Y / 2, 0)).Y
			bb.StudsOffsetWorldSpace = Vector3.new(0, math.max(8, top - anchor.Position.Y + 2.5), 0)
		end
	end
	local plate = bb:FindFirstChild("Plate")
	local row = plate and plate:FindFirstChild("Row")
	local stars = {}
	if row then
		for i = 1, 5 do stars[i] = row:FindFirstChild("Star" .. i) end
	end
	local score = row and row:FindFirstChild("ScoreChip") and row.ScoreChip:FindFirstChild("Score")
	local band = plate and plate:FindFirstChild("Band")
	return { title = band and band:FindFirstChild("Title"), stars = stars, score = score }
end

return M
