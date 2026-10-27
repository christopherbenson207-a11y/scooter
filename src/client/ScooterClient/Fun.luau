-- Customers with a bit of life. While they wait in the yard they wave at you through
-- the window, peek in, dance and "talk" to each other; they react when their scooter
-- goes on the bench, to every fix, to how it turned out, and when someone storms off.
-- No words: every line is one emoji in their bubble (ScooterClient.Bubbles), so a
-- busy yard reads at a glance. ScooterClient requires this as
-- Config.Fun and calls init() once its customer helpers exist.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M = {}
local ctx -- customers (the client's live list), say, playAnim, ANIM, MOODS, active(), Config, P

local IDLE = { "👋", "📱", "☕", "😮", "⭐", "😎", "🎵", "🤔", "👀", "🛴" }
local CHATS = { -- two people waiting next to each other
	{ "🛴", "👍" }, { "❓", "🛞" }, { "⭐", "😮" }, { "⏰", "😩" },
	{ "🏗️", "😍" }, { "😎", "😂" }, { "✨", "🤩" }, { "🚀", "😏" },
}
local PICKED = { "🙏", "😬", "🤞", "😃", "🚀" }
local FIXED = { "👍", "😃", "🙌", "✨", "💪" }
local BY_STARS = {
	[5] = { "😍", "🤩", "💯" },
	[4] = { "😄", "👍" },
	[3] = { "🙂", "👌" },
	[2] = { "😕", "🐌" },
	[1] = { "😒", "🙄" },
}
local STORMED = { "😬", "🙄", "😂", "🤷" }
local WAVE = "👋"

local function pick(t) return t[math.random(#t)] end

local function alive(c)
	return c and c.model and c.model.Parent and c.model:FindFirstChild("HumanoidRootPart") ~= nil
end
-- free for a bit of fun: standing still in the yard, not cross, not leaving
local function free(c)
	return alive(c) and not c.done and not c.walking and c.base and (c.mood or 0) <= 1 and not c.fun
end

-- A bubble for `hold` seconds, then back to whatever their mood says.
local talkingUntil = 0
local function line(c, text, hold, color)
	if not alive(c) then return end
	hold = math.min(hold or 1.6, 2) -- short: their order bubble comes back quickly
	local token = {}
	c.funSay = token
	ctx.say(c, text, color or Color3.new(1, 1, 1))
	task.delay(hold, function()
		if c.funSay ~= token or not alive(c) then return end
		c.funSay = nil
		local m = ctx.MOODS[c.mood or 0]
		if c.done then return end
		ctx.say(c, m and m.text, m and m.color)
	end)
end

-- Move them about by easing their resting spot (the mood code keeps them pinned to it).
local function ease(c, to, time)
	local from = c.base
	local t = 0
	while t < time do
		t += RunService.Heartbeat:Wait()
		if c.walking or c.done or not alive(c) then return false end
		local a = math.min(1, t / time)
		a = a * a * (3 - 2 * a)
		c.base = from:Lerp(to, a)
	end
	c.base = to
	return true
end
local function backToIdle(c)
	if alive(c) and not c.walking and not c.done and (c.mood or 0) <= 1 then ctx.playAnim(c, ctx.ANIM.Idle) end
end

local function wave(c)
	ctx.playAnim(c, ctx.ANIM.Wave, false)
	if os.clock() > talkingUntil then
		talkingUntil = os.clock() + 2
		line(c, WAVE, 2)
	end
	task.wait(2.2)
	backToIdle(c)
end

-- step up to the back window, have a good look, step back
local function peek(c)
	local home = c.base
	local toward = ctx.P.vec(Vector3.zAxis) -- the yard is behind the garage: +Z (plot space) is the window
	local at = home.Position + toward * 1.1
	local look = CFrame.lookAt(at, at + toward)
	if not ease(c, look, 0.45) then return end
	if os.clock() > talkingUntil and math.random() < 0.6 then
		talkingUntil = os.clock() + 1.6
		line(c, pick({ "👀", "😮", "🤩" }), 1.6)
	end
	task.wait(1.3)
	ease(c, home, 0.45)
end

-- a happy little spin and a bounce
local function dance(c)
	local home = c.base
	ctx.playAnim(c, ctx.ANIM.Cheer, false)
	if os.clock() > talkingUntil and math.random() < 0.4 then
		talkingUntil = os.clock() + 1.5
		line(c, "🎵", 1.5)
	end
	local t = 0
	while t < 1 do
		t += RunService.Heartbeat:Wait()
		if c.walking or c.done or not alive(c) then return end
		local a = math.min(1, t)
		c.base = home * CFrame.new(0, math.abs(math.sin(a * math.pi * 2)) * 0.6, 0) * CFrame.Angles(0, a * math.pi * 2, 0)
	end
	c.base = home
	task.wait(0.6)
	backToIdle(c)
end

-- two neighbours turn to each other and swap a line each
local function chat(a, b)
	talkingUntil = os.clock() + 5
	b.fun = true
	local ha, hb = a.base, b.base
	local pa, pb = ha.Position, hb.Position
	local okA = ease(a, CFrame.lookAt(pa, Vector3.new(pb.X, pa.Y, pb.Z)), 0.3)
	local okB = ease(b, CFrame.lookAt(pb, Vector3.new(pa.X, pb.Y, pa.Z)), 0.3)
	if okA and okB then
		local pair = pick(CHATS)
		line(a, pair[1], 2)
		ctx.playAnim(a, ctx.ANIM.Point, false)
		task.wait(2)
		line(b, pair[2], 2.2)
		ctx.playAnim(b, ctx.ANIM.Wave, false)
		task.wait(2.3)
	end
	if not a.walking and not a.done then ease(a, ha, 0.3) end
	if not b.walking and not b.done then ease(b, hb, 0.3) end
	backToIdle(a)
	backToIdle(b)
	b.fun = nil
end

function M.idle(c)
	c.fun = true
	local ok, err = pcall(function()
		local roll = math.random()
		local canTalk = os.clock() > talkingUntil
		if roll < 0.3 and canTalk then
			local other, best = nil, 7
			for _, o in ctx.customers do
				if o ~= c and free(o) then
					local d = (o.base.Position - c.base.Position).Magnitude
					if d < best then other, best = o, d end
				end
			end
			if other then
				chat(c, other)
			else
				talkingUntil = os.clock() + 2.6
				line(c, pick(IDLE))
			end
		elseif roll < 0.5 then
			wave(c)
		elseif roll < 0.7 then
			peek(c)
		elseif roll < 0.85 then
			dance(c)
		elseif canTalk then
			talkingUntil = os.clock() + 2.6
			line(c, pick(IDLE))
		end
	end)
	if not ok then warn("Customer fun: " .. tostring(err)) end
	c.fun = nil
end

function M.loop()
	local nextAct = setmetatable({}, { __mode = "k" })
	while true do
		task.wait(0.5)
		local now = os.clock()
		local act = ctx.active()
		for _, c in ctx.customers do
			if free(c) and not (act and act.customer == c) then
				nextAct[c] = nextAct[c] or now + 3 + math.random() * 5
				if now >= nextAct[c] then
					nextAct[c] = now + 6 + math.random() * 8
					task.spawn(M.idle, c)
				end
			end
		end
	end
end


-- They've put their scooter on the belt. A rare one turns the whole yard's heads; a rush or a picky
-- customer says so with a face. Everyone else lets their order bubble do the talking.
function M.dropOff(c, job)
	if not alive(c) or not job then return end
	local text
	if job.Rarity == "Legendary" or job.Rarity == "Epic" then
		text = job.Rarity == "Legendary" and "💎" or "✨"
		for _, o in ctx.customers do
			if o ~= c and free(o) then
				task.delay(0.6 + math.random() * 0.6, function() line(o, pick({ "😮", "🤩", "😱" }), 1.8) end)
			end
		end
	elseif job.Mood == "VIP" then
		text = "👑"
		for _, o in ctx.customers do
			if o ~= c and free(o) then
				task.delay(0.5 + math.random() * 0.6, function() line(o, pick({ "😮", "🤩" }), 1.8) end)
			end
		end
	elseif job.Mood == "Rush" then
		text = "⏰"
	elseif job.Mood == "Picky" then
		text = "🧐"
	end
	if text then
		talkingUntil = os.clock() + 3
		line(c, text, 2.4)
	end
end

-- Their scooter just went on the bench.
function M.picked(c)
	if not alive(c) then return end
	line(c, pick(PICKED), 2)
end

-- A fix on their scooter is done: they cheer you on.
function M.fixed(c)
	if not alive(c) or c.done or c.walking then return end
	ctx.playAnim(c, ctx.ANIM.Cheer, false)
	line(c, pick(FIXED), 1.4, Color3.fromRGB(120, 220, 130))
	task.delay(1.6, function() backToIdle(c) end)
end

-- What they say as they take it home; a perfect job gets the whole yard clapping.
function M.thanks(done)
	local r = done and done.result
	local stars = r and r.Stars or 3
	if stars >= 5 then
		for _, o in ctx.customers do
			if free(o) then
				task.delay(math.random() * 0.5, function()
					ctx.playAnim(o, ctx.ANIM.Cheer, false)
					task.delay(1.8, function() backToIdle(o) end)
				end)
			end
		end
	end
	if r and r.WrongPaint then return "😤" end
	return pick(BY_STARS[math.clamp(stars, 1, 5)])
end

-- Someone just stormed off: somebody in the yard has an opinion.
function M.stormed(c)
	for _, o in ctx.customers do
		if o ~= c and free(o) then
			task.delay(0.8, function() line(o, pick(STORMED), 1.8) end)
			return
		end
	end
end

function M.init(c)
	ctx = c
	task.spawn(M.loop)
end

return M
