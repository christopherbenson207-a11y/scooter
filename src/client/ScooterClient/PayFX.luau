-- The pay screen's star moment (owner, 23 Oct): each earned star flies in big and slams into its slot one by
-- one, with a gold ring, sparks, a little panel kick and a ding that climbs with every star. 4-5 stars end on
-- a happy sting and confetti; 1-2 stars end on a slide whistle and the empty slots thud. Yields until done.
local TweenService = game:GetService("TweenService")

local PayFX = {}

local SND = {
	Land = "rbxassetid://3416831713", -- token ding
	Good = "rbxassetid://1848281810", -- APM "Everything Works Out - Tag2"
	Bad = "rbxassetid://9104111128", -- slide whistle down
}
local GOLD = Color3.fromRGB(255, 184, 40)
local CONFETTI = { Color3.fromRGB(255, 184, 40), Color3.fromRGB(58, 150, 245), Color3.fromRGB(88, 190, 96), Color3.fromRGB(240, 80, 90), Color3.fromRGB(98, 82, 205) }

local function play(parent, id, volume, pitch, cut)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch or 1
	s.Parent = parent
	s:Play()
	task.delay(cut or 6, function() s:Destroy() end)
end

local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- a ring and sparks from the slot's centre (children of the slot, so they follow the panel's scale)
local function burst(slot)
	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.9, 0.9)
	ring.ZIndex = slot.ZIndex + 2
	Instance.new("UICorner", ring).CornerRadius = UDim.new(0.5, 0)
	local st = Instance.new("UIStroke", ring)
	st.Color = GOLD
	st.Thickness = 5
	ring.Parent = slot
	tween(ring, 0.35, { Size = UDim2.fromScale(2.4, 2.4) })
	tween(st, 0.35, { Transparency = 1, Thickness = 1 })
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + math.random() * 0.4
		local sp = Instance.new("ImageLabel")
		sp.BackgroundTransparency = 1
		sp.Image = slot.Image
		sp.AnchorPoint = Vector2.new(0.5, 0.5)
		sp.Position = UDim2.fromScale(0.5, 0.5)
		sp.Size = UDim2.fromOffset(14, 14)
		sp.Rotation = math.random(0, 72)
		sp.ZIndex = slot.ZIndex + 2
		sp.Parent = slot
		local d = math.random(38, 56)
		tween(sp, 0.45, { Position = UDim2.new(0.5, math.cos(a) * d, 0.5, math.sin(a) * d), Size = UDim2.fromOffset(6, 6),
			ImageTransparency = 1, Rotation = sp.Rotation + 120 })
	end
	task.delay(0.5, function()
		ring:Destroy()
		for _, c in slot:GetChildren() do if c:IsA("ImageLabel") then c:Destroy() end end
	end)
end

local function kick(panel, amount)
	tween(panel, 0.05, { Rotation = amount }).Completed:Wait()
	tween(panel, 0.18, { Rotation = 0 }, Enum.EasingStyle.Back)
end

local function confetti(panel)
	for _ = 1, 22 do
		local c = Instance.new("Frame")
		c.BorderSizePixel = 0
		c.BackgroundColor3 = CONFETTI[math.random(#CONFETTI)]
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0)
		c.Size = UDim2.fromOffset(math.random(6, 10), math.random(10, 16))
		c.Rotation = math.random(0, 180)
		c.ZIndex = 20
		c.Parent = panel
		local x, up = math.random(-230, 230), math.random(-50, -10) -- a low, wide pop, then it rains over the card
		tween(c, 0.3, { Position = UDim2.new(0.5, x * 0.6, 0, up) }).Completed:Once(function()
			tween(c, 0.9, { Position = UDim2.new(0.5, x, 0, up + math.random(260, 380)), Rotation = c.Rotation + math.random(-240, 240),
				BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		task.delay(1.4, function() c:Destroy() end)
	end
end

-- row: the Stars frame (S1..S5 image slots, already dimmed). n: stars earned. panel: the pay panel.
function PayFX.stars(row, n, panel)
	task.wait(0.3)
	for i = 1, n do
		local slot = row["S" .. i]
		local fly = Instance.new("ImageLabel")
		fly.BackgroundTransparency = 1
		fly.Image = slot.Image
		fly.AnchorPoint = Vector2.new(0.5, 0.5)
		fly.Position = UDim2.new(0.5, 0, 0.5, -70)
		fly.Size = UDim2.fromScale(2.6, 2.6)
		fly.ImageTransparency = 0.5
		fly.Rotation = -40
		fly.ZIndex = slot.ZIndex + 3
		fly.Parent = slot
		tween(fly, 0.18, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ImageTransparency = 0, Rotation = 0 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		fly:Destroy()
		slot.ImageColor3 = Color3.new(1, 1, 1)
		local pop = slot:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", slot) -- not Size: the row is a list layout
		pop.Scale = 1.3
		tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		burst(slot)
		play(panel, SND.Land, 0.55, 0.9 + i * 0.1, 1)
		task.spawn(kick, panel, i % 2 == 0 and 1.5 or -1.5)
		task.wait(0.24)
	end
	if n >= 4 then
		play(panel, SND.Good, 0.5)
		confetti(panel)
	elseif n <= 2 then
		play(panel, SND.Bad, 0.6, 1, 1)
		for i = n + 1, 5 do
			local slot = row["S" .. i]
			task.delay((i - n - 1) * 0.06, function()
				tween(slot, 0.08, { Rotation = 12 }).Completed:Wait()
				tween(slot, 0.3, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			end)
		end
		task.wait(0.3)
	end
end

return PayFX
