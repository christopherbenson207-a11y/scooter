-- The day summary (owner, 24 Oct: "star screen should appear after day is over to show how well i did through
-- the day"). Once the last customer of the day is served, the pay panel shows the day's average stars (the
-- PayFX slam), what you earned and how many you fixed. Fixes themselves only get a quick "+$" now.
-- Yields until NIGHT is tapped (or a while passes).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local Style = require(RS:WaitForChild("UIStyle"))
local C = Style.Color
local D = {}

-- env = { gui, remotes, payfx, sfx, SFX, popScale }
function D.show(env)
	local ok, s = pcall(function() return env.remotes.GetDay:InvokeServer() end)
	if not ok or not s or (s.Jobs or 0) <= 0 then return end
	local pay = env.gui.PayPanel
	local lines = pay.Lines
	for i = 1, 5 do pay.Stars["S" .. i].ImageColor3 = C.StarOff end
	local avg = math.clamp(math.floor(s.Stars / s.Jobs + 0.5), 1, 5)
	pay.Title.Text = ("DAY %d DONE!"):format(s.Day)
	pay.Tab.Gloss.Color = Style.glossColors(C.Night)
	lines.L1.Text = ("Fixed %d scooter%s"):format(s.Jobs, s.Jobs == 1 and "" or "s")
	lines.L2.Text = s.Perfect > 0 and ("Perfect fixes  %d"):format(s.Perfect)
		or (s.Best and ("Best  %s %s  +$%s"):format(s.Best.Rarity, s.Best.Scooter, Style.money(s.Best.Total)) or "")
	lines.L3.Text = s.Lost > 0 and ("Customers lost  %d"):format(s.Lost) or "Nobody went home unhappy!"
	local rating = player:GetAttribute("Rating") or 0
	lines.L4.Text = (player:GetAttribute("Reviews") or 0) > 0 and ("Garage rating  %.1f stars"):format(rating) or ""
	pay.Total.Text = "+$0"
	pay.Ride.Visible = false
	pay.Next.AnchorPoint = Vector2.new(0.5, 1)
	pay.Next.Position = UDim2.new(0.5, 0, 1, -16)
	pay.Next.Button.Label.Text = "NIGHT"
	pay.Visible = true
	env.popScale(pay, 0.6, 0.35)
	env.sfx(env.SFX.Done, 0.8, 0.9)
	local closed = false
	local conn = pay.Next.Button.Activated:Connect(function() closed = true end)
	task.spawn(function()
		env.payfx.stars(pay.Stars, avg, pay)
		local t0 = os.clock()
		while os.clock() - t0 < 0.8 do
			local a = TweenService:GetValue((os.clock() - t0) / 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			pay.Total.Text = "+$" .. Style.money(s.Cash * a)
			task.wait()
		end
		pay.Total.Text = "+$" .. Style.money(s.Cash)
	end)
	local t0 = os.clock()
	while not closed and os.clock() - t0 < 20 do task.wait(0.1) end
	conn:Disconnect()
	pay.Visible = false
	pay.Next.Button.Label.Text = "NEXT JOB"
end

return D
