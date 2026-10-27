-- The job director (plan/11 section 3). Instead of rolling every customer from scratch, each player's day is
-- planned from what the server knows about them: what they're good and bad at, what they haven't seen lately,
-- what they just bought, how the day is going. A day deals Warm-up -> Show-off -> Core (one Practice in it)
-- -> Big in the middle of the day -> Cool-down at the end; the first 3 days are scripted. Inside a slot it's still a
-- little random. All the numbers are in ScooterConfig.Director.
--
-- Director.init(env)            env.unlocked(player) -> fix names you can do now, env.maxFixes(player) -> n
-- Director.restore / collect    the saved part (about 1 KB)
-- Director.next(player, opts)   the plan for the next customer (makeJob turns it into a job)
-- Director.record(...)          a finished job: fix stats, recent stars, today's cash
-- Director.bought(player, id, unlocks)   show off what you just paid for
-- Director.struggling(player, queue, cap)  the spawner sends fewer customers while you're swamped

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("ScooterConfig"))
local D = Config.Director

local Director = {}
local env
local st = {} -- [player] = { saved..., today's plan }

local function blank()
	return { Fix = {}, Dealt = 0, Pity = { 0, 0, 0 }, Seen = {}, Tut = 0, TutDay = 0, Earned = {} }
end

local function num(v, lo, hi, default)
	v = tonumber(v)
	if not v or v ~= v then return default end
	return math.clamp(v, lo, hi)
end

function Director.init(e)
	env = e
end

function Director.restore(player, saved)
	local s = blank()
	if type(saved) == "table" then
		s.Dealt = math.floor(num(saved.Dealt, 0, 1e7, 0))
		s.Tut = math.floor(num(saved.Tut, 0, 50, 0))
		s.TutDay = math.floor(num(saved.TutDay, 0, 1e5, 0))
		if type(saved.Pity) == "table" then
			for k = 1, 3 do s.Pity[k] = math.floor(num(saved.Pity[k], 0, 1e5, 0)) end
		end
		if type(saved.Seen) == "table" then
			for name, v in saved.Seen do
				if type(name) == "string" and v == true then s.Seen[name] = true end
			end
		end
		if type(saved.Earned) == "table" then
			for i = 1, math.min(#saved.Earned, 5) do table.insert(s.Earned, num(saved.Earned[i], 0, 1e12, 0)) end
		end
		if type(saved.Fix) == "table" then
			for name, f in saved.Fix do
				if Config.Problems[name] and type(f) == "table" then
					s.Fix[name] = {
						N = math.floor(num(f.N, 0, 1e7, 0)),
						Ratio = num(f.Ratio, 0.1, 10, 1),
						Perfect = num(f.Perfect, 0, 1, 0),
						At = math.floor(num(f.At, 0, 1e7, 0)),
						Day = math.floor(num(f.Day, 0, 1e5, 0)),
					}
				end
			end
		end
		if type(saved.LastBuy) == "table" and type(saved.LastBuy.Id) == "string" then
			s.LastBuy = { Id = saved.LastBuy.Id, Left = math.floor(num(saved.LastBuy.Left, 0, 10, 0)) }
		end
	end
	s.recent = {} -- stars of the last few jobs (this session)
	s.lastModels = {}
	st[player] = s
end

function Director.collect(player)
	local s = st[player]
	if not s then return nil end
	return {
		Fix = s.Fix, Dealt = s.Dealt, Pity = s.Pity, Seen = s.Seen, Tut = s.Tut, TutDay = s.TutDay,
		Earned = s.Earned, LastBuy = s.LastBuy,
	}
end

function Director.forget(player)
	st[player] = nil
end

-- yesterday's earnings go on the list (the economy step uses the last 5 days)
function Director.newDay(player, earned)
	local s = st[player]
	if not s then return end
	table.insert(s.Earned, math.max(0, earned or 0))
	while #s.Earned > 5 do table.remove(s.Earned, 1) end
	s.planDay = nil
end

local function dayOf(player)
	return player:GetAttribute("Day") or 1
end

-- How many slots today, and in what order (the rush and the evening override this as they come).
local function planDay(player, s)
	local belt = Config.tierOf(player:GetAttribute("Belt") or 1)
	local size = D.Deck.Base + (belt - 1) * D.Deck.PerBelt
	if (player:GetAttribute("Rating") or 0) >= D.Deck.GoodRating then size += D.Deck.PerGoodRating end
	size = math.min(size, D.Deck.Max)
	local deck = { "Warm" }
	if size >= 11 then table.insert(deck, "Warm") end
	if s.LastBuy and s.LastBuy.Left > 0 then
		for _ = 1, math.min(s.LastBuy.Left, size >= 10 and 2 or 1) do table.insert(deck, "Show") end
	end
	while #deck < size - 1 do table.insert(deck, "Core") end
	table.insert(deck, math.min(#deck + 1, 4), "Practice")
	s.deck, s.dealtToday, s.big, s.practiced, s.planDay = deck, 0, 0, false, dayOf(player)
	s.cashToday = 0
end

---------------------------------------------------------------- picking a story
local function stockLow(player, story)
	for _, f in story.Fixes do
		local id = Config.StockFor[f]
		local n = id and player:GetAttribute(id)
		if n and n > 0 and n <= D.LowStock then return true end
	end
	return false
end

local function freshness(s, story, day)
	local score = 0
	for _, f in story.Fixes do
		local fx = s.Fix[f]
		local since = fx and (s.Dealt - fx.At) or D.FreshCap
		score += math.min(since, D.FreshCap) * D.Fresh
		if not fx or day - fx.Day >= 2 then score += D.Overdue end
	end
	return score
end

local function ratioOf(s, story)
	local worst = 0
	for _, f in story.Fixes do
		local fx = s.Fix[f]
		worst = math.max(worst, fx and fx.N > 0 and fx.Ratio or 1)
	end
	return worst
end

-- The stories you could get now: every fix unlocked and in stock, no more fixes than `max`.
local function pool(player, s, open, max, filter)
	local list = {}
	for _, story in Config.Stories do
		if #story.Fixes > max or story.Name == s.lastStory then continue end
		local ok = true
		for _, f in story.Fixes do
			if not open[f] then ok = false break end
		end
		if ok and (not filter or filter(story)) then table.insert(list, story) end
	end
	return list
end

-- the best few by score, then a weighted pick among them
local function pickBest(list, score)
	if #list == 0 then return nil end
	local scored = {}
	for _, story in list do table.insert(scored, { story = story, score = math.max(0.01, score(story)) }) end
	table.sort(scored, function(a, b) return a.score > b.score end)
	local total = 0
	for i = 1, math.min(D.Top, #scored) do total += scored[i].score end
	local roll = math.random() * total
	for i = 1, math.min(D.Top, #scored) do
		roll -= scored[i].score
		if roll <= 0 then return scored[i].story end
	end
	return scored[1].story
end

local function has(story, f) return table.find(story.Fixes, f) ~= nil end

---------------------------------------------------------------- scooter, rarity
local function pickScooter(player, s, day)
	local garage = Config.tierOf(player:GetAttribute("Garage") or 1) -- scooter classes come with the garage's tier
	local byClass, classes = {}, {}
	local models = game:GetService("ReplicatedStorage"):FindFirstChild("Scooters")
	for _, sc in Config.Scooters do
		local class = sc.Class or sc.Garage
		-- a listed model that isn't imported yet is skipped
		if sc.Garage <= garage and (day > 1 or class == 1) and (not models or models:FindFirstChild(sc.Name)) then
			if not byClass[class] then
				byClass[class] = {}
				table.insert(classes, class)
			end
			table.insert(byClass[class], sc)
		end
	end
	if #classes == 0 then return Config.Scooters[1] end
	table.sort(classes, function(a, b) return a > b end) -- newest first
	local weights = {}
	for i = 1, #classes do
		weights[i] = i == 1 and D.ClassMix[1] or i == 2 and D.ClassMix[2] or D.ClassMix[3] / (#classes - 2)
	end
	local total = 0
	for _, w in weights do total += w end
	local roll, class = math.random() * total, classes[1]
	for i, w in weights do
		roll -= w
		if roll <= 0 then class = classes[i] break end
	end
	local models = byClass[class]
	local m = models[math.random(#models)]
	-- never the same model three times in a row (when there's another one to show)
	local a, b = s.lastModels[1], s.lastModels[2]
	if a == m.Name and b == m.Name and #models > 1 then
		local others = {}
		for _, x in models do
			if x.Name ~= m.Name then table.insert(others, x) end
		end
		m = others[math.random(#others)]
	end
	s.lastModels = { m.Name, a }
	return m
end

local function pickRarity(s, day, minIndex, guard)
	-- day 1 is all Common, day 2 brings the first Uncommon, rarer ones from RaresFromDay
	local maxIndex = day <= 1 and 1 or day < D.RaresFromDay and 2 or #Config.Rarities
	local pity = 1
	if day >= D.RaresFromDay then
		if s.Pity[3] >= D.Pity[3] then pity = 5 elseif s.Pity[2] >= D.Pity[2] then pity = 4 elseif s.Pity[1] >= D.Pity[1] then pity = 3 end
	end
	local lo = math.clamp(math.max(minIndex or 1, pity), 1, #Config.Rarities)
	local hi = math.max(lo, maxIndex)
	local total = 0
	local w = {}
	for i = lo, hi do
		w[i] = Config.Rarities[i].Weight * ((guard and (i == 2 or i == 3)) and D.GuardRarity or 1)
		total += w[i]
	end
	local roll, idx = math.random() * total, lo
	for i = lo, hi do
		roll -= w[i]
		if roll <= 0 then idx = i break end
	end
	-- the pity counters only run once rares can come at all
	if day >= D.RaresFromDay then
		for k = 1, 3 do
			if idx >= k + 2 then s.Pity[k] = 0 else s.Pity[k] += 1 end
		end
	end
	return Config.Rarities[idx], idx
end

---------------------------------------------------------------- live state
local function lastStars(s, n)
	local t = {}
	for i = #s.recent, math.max(1, #s.recent - n + 1), -1 do table.insert(t, s.recent[i]) end
	return t
end

function Director.struggling(player, queue, cap)
	local s = st[player]
	if not s or not queue then return false end
	if cap and #queue >= cap then return true end
	local now, red = os.clock(), 0
	for _, job in queue do
		if job.Patience and job.queuedAt and now - job.queuedAt > job.Patience * (1 - D.StruggleRed) then red += 1 end
	end
	if red >= 2 then return true end
	local last = lastStars(s, 2)
	return #last == 2 and last[1] <= D.StruggleStars and last[2] <= D.StruggleStars
end

local function flying(s, queue)
	if queue and #queue > 0 then return false end
	local last = lastStars(s, 3)
	return #last == 3 and last[1] == 5 and last[2] == 5 and last[3] == 5
end

-- today's earnings well under where they should be by now (a day should pay about a night of upgrades)
local function behind(player, s)
	local ends = workspace:GetAttribute("PhaseEndsAt")
	if not ends then return false end
	local through = math.clamp(1 - (ends - workspace:GetServerTimeNow()) / Config.DaySeconds, 0, 1)
	if through < 0.25 then return false end
	return (s.cashToday or 0) < Config.nightCash(dayOf(player)) * through * D.Behind
end

-- the middle stretch of the day (35-65% through): where the Big jobs go (it used to be the lunch rush)
local function midday(ends)
	if workspace:GetAttribute("Phase") ~= "Day" then return false end
	local through = 1 - (ends - workspace:GetServerTimeNow()) / Config.DaySeconds
	return through >= 0.35 and through <= 0.65
end

---------------------------------------------------------------- the next customer
-- opts: queue + cap (the yard), minRarity (the "call a rare customer" product).
-- Returns { Chosen = { [fix] = true }, Story, Scooter, Rarity, Slot, Patience, Pay, NoMood, Mood, NewScooter }
-- or nil (makeJob then rolls the old way).
function Director.next(player, opts)
	local s = st[player]
	if not s or not env then return nil end
	opts = opts or {}
	local day = dayOf(player)
	if s.planDay ~= day then planDay(player, s) end
	local open = {}
	local openList = env.unlocked(player)
	for _, f in openList do open[f] = true end
	if #openList == 0 then return nil end
	local max = env.maxFixes(player)

	local plan = { Patience = 1, Pay = 1 }
	local story

	-- the first 3 days: the next scripted step you can do
	local script = D.FirstDays[day]
	if script then
		if s.TutDay ~= day then s.TutDay, s.Tut = day, 0 end
		while s.Tut < #script and not story do
			s.Tut += 1
			local step = script[s.Tut]
			if step.Fixes then
				local ok = true
				for _, f in step.Fixes do
					if not open[f] then ok = false end
				end
				if ok then
					local key = table.concat(step.Fixes, "+")
					for _, sty in Config.Stories do
						if table.concat(sty.Fixes, "+") == key then story = sty break end
					end
					story = story or { Name = Config.Problems[step.Fixes[1]].Label, Fixes = step.Fixes }
				end
			elseif step.Count then
				if step.Count <= max then
					story = pickBest(pool(player, s, open, step.Count, function(x) return #x.Fixes == step.Count end), function(x)
						return freshness(s, x, day) + (x.Weight or 1)
					end)
				end
			else
				story = pickBest(pool(player, s, open, max, function(x) return #x.Fixes <= 2 end), function(x)
					return freshness(s, x, day) + (x.Weight or 1)
				end)
			end
			if story then
				plan.Slot = "Script"
				plan.Rarity = step.Rarity
				plan.Mood = step.Mood
				plan.NoExtras = step.Fixes ~= nil
			end
		end
	end

	-- otherwise the slot this point in the day calls for
	if not story then
		s.dealtToday += 1
		local slot = s.deck[s.dealtToday] or "Core"
		local ends = workspace:GetAttribute("PhaseEndsAt")
		local late = ends and ends - workspace:GetServerTimeNow() < D.CoolAt
		if late then
			slot = "Cool"
		elseif s.big < D.BigPerDay and max >= 2 and ends and midday(ends) then
			slot = "Big"
		end
		if slot == "Practice" and (s.practiced or s.dealtToday <= 1) then slot = "Core" end
		if slot == "Show" and not (s.LastBuy and s.LastBuy.Left > 0) then slot = "Core" end
		if slot == "Core" then
			if Director.struggling(player, opts.queue, opts.cap) then
				slot = "Quick"
			elseif flying(s, opts.queue) then
				plan.Flying = true
			end
		end
		-- a fix you just unlocked: the next few jobs use it (any slot but practice)
		local want = s.fresh and s.freshLeft > 0 and s.fresh or nil
		local function wants(x)
			if not want then return true end
			for _, f in want do
				if has(x, f) then return true end
			end
			return false
		end
		local function base(x)
			return freshness(s, x, day) * (stockLow(player, x) and D.LowStockScore or 1)
		end

		if slot == "Practice" then
			local worst, worstR
			for f in open do
				local fx = s.Fix[f]
				if fx and fx.N >= D.PracticeMin and fx.Ratio >= D.PracticeRatio and (not worstR or fx.Ratio > worstR) then
					worst, worstR = f, fx.Ratio
				end
			end
			if worst then
				s.practiced = true
				story = pickBest(pool(player, s, open, 1, function(x) return has(x, worst) end), base)
					or { Name = Config.Problems[worst].Label, Fixes = { worst } }
				plan.Patience = D.PracticePatience
				plan.NoExtras = true
			else
				slot = "Core"
			end
		end
		if slot == "Show" and not story then
			local fixes = D.ShowOff[s.LastBuy.Id] or {}
			story = pickBest(pool(player, s, open, max, function(x)
				for _, f in fixes do
					if has(x, f) then return true end
				end
				return false
			end), function(x) return base(x) + 10 / #x.Fixes end)
			s.LastBuy.Left -= 1
			if not story then slot = "Core" end
		end
		if (slot == "Warm" or slot == "Cool" or slot == "Quick") and not story then
			-- one fix you're quick at
			story = pickBest(pool(player, s, open, 1, wants), function(x) return 2 / ratioOf(s, x) + base(x) * 0.05 end)
				or pickBest(pool(player, s, open, 1), function(x) return 2 / ratioOf(s, x) end)
			plan.NoExtras = true
			if not story then slot = "Core" end
		end
		if slot == "Big" and not story then
			local most = 0
			for _, x in pool(player, s, open, max, wants) do most = math.max(most, #x.Fixes) end
			story = pickBest(pool(player, s, open, max, function(x) return #x.Fixes == most and wants(x) end), base)
			if story then s.big += 1 else slot = "Core" end
		end
		if not story then
			slot = "Core"
			local lo = math.min(2, max)
			story = pickBest(pool(player, s, open, max, function(x) return #x.Fixes >= lo and wants(x) end), function(x) return base(x) + (x.Weight or 1) end)
				or pickBest(pool(player, s, open, max, wants), function(x) return base(x) + (x.Weight or 1) end)
				or pickBest(pool(player, s, open, max), function(x) return base(x) + (x.Weight or 1) end)
		end
		if want then s.freshLeft -= 1 end -- counts down even if its stock ran out, so it can't get stuck
		plan.Slot = slot
	end
	if not story then return nil end

	-- the fixes: the story's own, plus its extras (Big takes every one that fits; Flying adds one)
	local chosen, count = {}, 0
	for _, f in story.Fixes do
		chosen[f] = true
		count += 1
	end
	if not plan.NoExtras then
		for _, f in story.Extra or {} do
			if open[f] and not chosen[f] and count < max and (plan.Slot == "Big" or math.random() < 0.5) then
				chosen[f] = true
				count += 1
			end
		end
		if plan.Flying and count < max then
			local extra = {}
			for f in open do
				if not chosen[f] then table.insert(extra, f) end
			end
			if #extra > 0 then
				chosen[extra[math.random(#extra)]] = true
				plan.Pay *= D.FlyingPay
			end
		end
	end
	if chosen.Battery and chosen.Charge then chosen.Charge = nil end
	s.lastStory = story.Name

	-- every fix in it counts as seen now (freshness)
	s.Dealt += 1
	for f in chosen do
		local fx = s.Fix[f] or { N = 0, Ratio = 1, Perfect = 0, At = 0, Day = 0 }
		fx.At, fx.Day = s.Dealt, day
		s.Fix[f] = fx
	end

	local guard = behind(player, s)
	if guard then plan.Pay *= D.GuardPay end
	plan.Rarity = pickRarity(s, day, math.max(opts.minRarity or 1, plan.Rarity or 1), guard)
	plan.Scooter = pickScooter(player, s, day)
	if not s.Seen[plan.Scooter.Name] then
		s.Seen[plan.Scooter.Name] = true
		plan.NewScooter = true
	end
	plan.NoMood = day < D.MoodsFromDay or plan.Slot == "Practice" or plan.Slot == "Warm" or plan.Slot == "Cool" or plan.Slot == "Quick"
	plan.Chosen, plan.Story = chosen, story
	return plan
end

-- A finished job: how long each of its fixes took against par, perfects, recent stars, today's cash.
function Director.record(player, job, stars, elapsed, total)
	local s = st[player]
	if not s or job.First then return end
	local ratio = math.clamp(elapsed / math.max(job.Par or 1, 1), 0.1, 10)
	for _, f in job.Problems do
		local fx = s.Fix[f] or { N = 0, Ratio = 1, Perfect = 0, At = s.Dealt, Day = dayOf(player) }
		local a = fx.N == 0 and 1 or 0.3
		fx.Ratio += (ratio - fx.Ratio) * a
		fx.Perfect += ((stars == 5 and 1 or 0) - fx.Perfect) * a
		fx.N += 1
		s.Fix[f] = fx
	end
	table.insert(s.recent, stars)
	while #s.recent > 5 do table.remove(s.recent, 1) end
	s.cashToday = (s.cashToday or 0) + (total or 0)
end

-- You bought or upgraded `id`: the next jobs show it off; `unlocks` = fixes it just opened up.
function Director.bought(player, id, unlocks)
	local s = st[player]
	if not s then return end
	if D.ShowOff[id] then s.LastBuy = { Id = id, Left = D.ShowOffJobs } end
	if unlocks and #unlocks > 0 then
		s.fresh, s.freshLeft = unlocks, Config.FreshJobs
	end
	-- a new day plan picks up the show-off slots
	if s.deck then
		for i = (s.dealtToday or 0) + 1, math.min(#s.deck, (s.dealtToday or 0) + 2) do
			if s.deck[i] == "Core" then s.deck[i] = "Show" end
		end
	end
end

return Director
