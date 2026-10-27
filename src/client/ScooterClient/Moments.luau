-- Small moments that make the day feel alive (plan/06 and a 24 Oct initiative):
--   "Hang on!"   when a waiting customer is nearly out of patience, a yellow button under the customer cards.
--                Tap it: you wave, everyone waiting cheers and gets Config.HangOn.Back of their patience back
--                (server HangOn), once each; then it rests Config.HangOn.Cooldown seconds.
--   cheers       the customer whose scooter you're fixing cheers through the window at every fix you finish.
--   lunch rush   workspace.LunchRushEndsAt: one short line when it starts (server sends more customers).
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local M = {}
local e
local restUntil = 0

local function waiting(c)
	local a = e.active()
	return not c.done and not c.walking and c.expires and c.patience and not (a and a.customer == c)
end

local function idleAgain(c)
	task.delay(1.4, function()
		if c.model.Parent and not c.done and not c.walking then
			e.playAnim(c, (c.mood or 0) >= 3 and e.ANIM.Point or e.ANIM.Idle)
		end
	end)
end

-- the customer watching their own scooter: a cheer and a green puff
function M.cheer(c)
	if not (e and c and c.model and c.model.Parent) or c.walking or c.done then return end
	e.playAnim(c, e.ANIM.Cheer, false)
	local head = c.model:FindFirstChild("Head")
	if head then e.puff(head.Position + Vector3.new(0, 1.2, 0), Color3.fromRGB(120, 230, 130), 4) end
	idleAgain(c)
end

local function wave()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local animator = hum and (hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum))
	if not animator then return end
	local a = Instance.new("Animation")
	a.AnimationId = e.ANIM.Wave
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if ok then track.Looped = false track:Play(0.1) end
end

local function covered()
	for _, n in { "PayPanel", "Shop", "Store", "Restock" } do
		local f = e.gui:FindFirstChild(n)
		if f and f.Visible then return true end
	end
	return false
end

local function place(btn)
	local list = e.gui:FindFirstChild("Customers")
	local rows = list and list:FindFirstChild("Rows")
	local ref = rows and rows.Visible and rows.AbsoluteSize.Y > 0 and rows or list
	if not ref then return end
	local origin = e.gui.AbsolutePosition
	btn.Position = UDim2.fromOffset(ref.AbsolutePosition.X + ref.AbsoluteSize.X - origin.X, ref.AbsolutePosition.Y + ref.AbsoluteSize.Y + 8 - origin.Y)
end

local function update(btn)
	local show = false
	if os.clock() >= restUntil and not covered() then
		local now = e.pclock()
		for _, c in e.customers do
			if waiting(c) and not c.hungOn and (c.expires - now) / c.patience <= e.config.HangOn.Below then show = true break end
		end
	end
	if show then place(btn) end
	if show ~= btn.Visible then
		btn.Visible = show
		if show then e.popScale(btn, 0.25, 0.25) end
	end
end

local function hangOn(btn)
	btn.Visible = false
	restUntil = os.clock() + 1
	local ok, done = pcall(function() return e.remotes.HangOn:InvokeServer() end)
	if not (ok and done) then return end
	restUntil = os.clock() + e.config.HangOn.Cooldown
	e.sfx(e.SFX.Done, 0.6, 1.2)
	wave()
	for _, c in e.customers do
		if waiting(c) and not c.hungOn then
			c.hungOn = true
			task.delay(0.2 + math.random() * 0.4, function() M.cheer(c) end)
		end
	end
end

local function lunchRush()
	local ends = workspace:GetAttribute("LunchRushEndsAt")
	if ends and ends > workspace:GetServerTimeNow() then
		e.popText("LUNCH RUSH!", 0.8, 1.6, Color3.fromRGB(255, 196, 61))
		e.sfx(e.SFX.Done, 0.8, 0.9)
	end
end

-- e = { gui, config, remotes, customers, active = fn, pclock, playAnim, ANIM, puff, sfx, SFX, popText, popScale }
function M.init(env)
	e = env
	local btn = e.gui:FindFirstChild("HangOn")
	if btn then
		btn.Button.Activated:Connect(function() hangOn(btn) end)
		task.spawn(function()
			while true do
				update(btn)
				task.wait(0.25)
			end
		end)
	end
	workspace:GetAttributeChangedSignal("LunchRushEndsAt"):Connect(lunchRush)
end

return M
