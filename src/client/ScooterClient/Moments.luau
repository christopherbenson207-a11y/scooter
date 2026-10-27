-- Small moments that make the day feel alive (plan/06 and a 24 Oct initiative):
--   cheers       the customer whose scooter you're fixing cheers through the window at every fix you finish.
-- (The "Hang on!" button and the lunch rush were taken out in plan/13: nobody felt them.)
local M = {}
local e

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

-- e = { gui, config, remotes, customers, active = fn, pclock, playAnim, ANIM, puff, sfx, SFX, popText, popScale }
function M.init(env)
	e = env
	-- the old "Hang on!" button may still be in StarterGui (FixUI.HangOn): keep it out of sight
	local btn = e.gui:FindFirstChild("HangOn")
	if btn then btn.Visible = false end
end

return M
