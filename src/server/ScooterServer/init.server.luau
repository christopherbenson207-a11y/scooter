local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local Config = require(RS.ScooterConfig)
-- The machines live in Workspace.Garage.Machines so they can be seen and moved in
-- Edit mode. When the game runs they go to ReplicatedStorage.Stations, and each
-- player's client copies the ones they own into their garage.
do
	local machines = workspace:FindFirstChild("Garage") and workspace.Garage:FindFirstChild("Machines")
	if machines then
		local stations = RS:FindFirstChild("Stations") or Instance.new("Folder")
		stations.Name = "Stations"
		stations.Parent = RS
		for _, m in machines:GetChildren() do m.Parent = stations end
		machines:Destroy()
	end
end

-- Every player gets their own garage plot (built from Workspace.Garage when they join).
local Plots = require(script.Plots)
Plots.init()
local Clock = require(script.Clock) -- one shared day and night
local Spawner = require(script.Spawner) -- which garage a customer chooses
local Crowd = require(RS:WaitForChild("ScooterCrowd")) -- the walk from the bus stop
local Market = require(script.Market) -- Caro's night market: stock, purchases, what the items do
local Van = require(script.Van) -- her van drives in at night and out at dawn
local Director = require(script.Director) -- plans each player's day of customers from their own data (plan/11)

local remotes = Instance.new("Folder")
remotes.Name = "ScooterRemotes"
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local GetQueue = remote("RemoteFunction", "GetQueue")
local PickJob = remote("RemoteFunction", "PickJob")
local FinishJob = remote("RemoteFunction", "FinishJob")
local RideTip = remote("RemoteFunction", "RideTip")
local BuyShop = remote("RemoteFunction", "BuyShop")
local UseBattery = remote("RemoteFunction", "UseBattery")
local UseTyre = remote("RemoteFunction", "UseTyre")
local UseBulb = remote("RemoteFunction", "UseBulb")
local UsePaint = remote("RemoteFunction", "UsePaint")
local BuyPaint = remote("RemoteFunction", "BuyPaint")
local RejectJob = remote("RemoteFunction", "RejectJob")
local EmptyTrash = remote("RemoteFunction", "EmptyTrash")
local OpenShop = remote("RemoteFunction", "OpenShop")
local QueueChanged = remote("RemoteEvent", "QueueChanged")
local SetBusy = remote("RemoteEvent", "SetBusy")
local CustomerSpawned = remote("RemoteEvent", "CustomerSpawned") -- every client draws the customer walking from the bus stop
local CustomerLeft = remote("RemoteEvent", "CustomerLeft")
local GetCrowd = remote("RemoteFunction", "GetCrowd")
local MarketChanged = remote("RemoteEvent", "MarketChanged") -- the shelf or the opening state changed
local MarketArrived = remote("RemoteEvent", "MarketArrived") -- the van has parked (the one-line announcement)
local GetMarket = remote("RemoteFunction", "GetMarket")
local BuyMarket = remote("RemoteFunction", "BuyMarket")
local RefillCan = remote("RemoteFunction", "RefillCan")
local Restock = remote("RemoteFunction", "Restock") -- out of stock: the 10 R$ restock card
local GiveUpStock = remote("RemoteFunction", "GiveUpStock") -- the card ran out: the customers who needed it leave
local GetDay = remote("RemoteFunction", "GetDay") -- today's numbers for the day summary card
local StoreBuy = remote("RemoteFunction", "StoreBuy") -- the Robux store (Config.Store)
local HangOn = remote("RemoteFunction", "HangOn") -- "Hang on!": waiting customers get some patience back
local StepDone = remote("RemoteFunction", "StepDone") -- Fever loop: each finished fix pays on the spot
local SwitchCurrent = remote("RemoteFunction", "SwitchCurrent") -- parallel bench: which job is on the bench right now
local Offer = remote("RemoteEvent", "Offer") -- context offers (plan/12): short, need-timed popups
local OfferBuy = remote("RemoteFunction", "OfferBuy")
remotes.Parent = RS

local data = {} -- [player] = { queue, actives, current, lastRepair, nextId, lastKey, fresh, freshLeft, night, hungry, tour, today }
local customerLeft, forgetCustomers -- set in the customers section at the end
local newDay -- today's numbers for the day card (below, with the player setup)
local storeGrant -- hands over a Robux store item (the store section at the end)


local function shopItem(id)
	for _, item in Config.Shop do
		if item.Id == id then return item end
	end
end

---------------------------------------------------------------- saving
-- One record per player: cash, every shop item's level/stock, fixed count, day
-- and when they were last online (for the helper's offline earnings later).
-- A save that failed to load is never written over (that would wipe it).
local store
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService,
		RunService:IsStudio() and Config.StudioSaveStore or Config.SaveStore)
	if ok then store = result else warn("[Save] no DataStore:", result) end
end
local loaded = {} -- [player] = true once their save loaded cleanly (or they're new)
local reviews = {} -- [player] = stars of their last jobs, newest last (the garage rating)
local pending = 0 -- saves in flight (shutdown waits for them)

local function saveKey(player)
	return "u" .. player.UserId
end

-- Returns ok, record (record is nil for a brand new player).
local function loadSave(player)
	if not store then return false end
	for attempt = 1, 3 do
		local ok, result = pcall(store.GetAsync, store, saveKey(player))
		if ok then return true, result end
		if tostring(result):find("Studio access to APIs") then
			-- Game Settings > Security > Enable Studio Access to API Services is off
			warn("[Save] Studio API access is off: this playtest won't load or save")
			store = nil
			return false
		end
		warn(("[Save] load failed for %s (try %d): %s"):format(player.Name, attempt, tostring(result)))
		if attempt < 3 then task.wait(attempt * 2) end
	end
	return false
end

local function collectSave(player)
	local ls = player:FindFirstChild("leaderstats")
	local record = {
		V = Config.SaveVersion, -- 2 = upgrade system v5 levels (0-11)
		Cash = ls and ls.Cash.Value or 0,
		Fixed = player:GetAttribute("Fixed") or 0,
		Day = player:GetAttribute("Day") or 1,
		WalkedOut = player:GetAttribute("WalkedOut") or 0,
		LastOnline = os.time(),
		Reviews = reviews[player] or {},
		Caro = Market.collect(player),
		Director = Director.collect(player),
		Starter = player:GetAttribute("StarterPack") == true or nil,
		Items = {},
	}
	for _, item in Config.Shop do
		record.Items[item.Id] = player:GetAttribute(item.Id)
	end
	return record
end

-- `final` = they're leaving (or the server is closing): last save, no more after it.
local function writeSave(player, final)
	if not store or not loaded[player] then return end
	if final then loaded[player] = nil end
	local record = collectSave(player)
	pending += 1
	for attempt = 1, 3 do
		local ok, err = pcall(store.SetAsync, store, saveKey(player), record, { player.UserId })
		if ok then break end
		warn(("[Save] save failed for %s (try %d): %s"):format(player.Name, attempt, tostring(err)))
		if attempt < 3 then task.wait(attempt) end
	end
	pending -= 1
end

-- A saved item value, kept inside what the current shop allows (prices and
-- capacities change while the game is being built).
local function savedItem(item, value, items)
	if item.Starter then return 1 end
	if type(value) ~= "number" then return nil end
	value = math.floor(value)
	if item.Kind == "Level" then
		return math.clamp(value, item.Locked and 0 or 1, #item.Prices)
	elseif item.Kind == "Stock" then
		local holder = item.Holder and shopItem(item.Holder)
		local level = holder and math.clamp(tonumber(items[item.Holder]) or 1, 1, #holder.Prices) or 1
		local cap = holder and holder.Capacity and holder.Capacity[level] or math.huge
		return math.clamp(value, 0, cap)
	end
	return math.clamp(value, 0, 1)
end

-- A Level item's per-level value (`field` table indexed by the player's level).
local function levelValue(player, id, field)
	local item = shopItem(id)
	local list = item and item[field]
	if not list then return nil end
	return list[player:GetAttribute(id) or 1] or list[1]
end

-- you own a machine, and whatever it needs (the bucket stands in the wash bay)
local function owns(player, id)
	if (player:GetAttribute(id) or 0) <= 0 then return false end
	local item = shopItem(id)
	return not (item and item.Needs) or owns(player, item.Needs)
end

-- Out of a part: nobody brings a job that needs it until you restock (a repaint needs at least one rack can).
local function hasStockFor(player, name)
	local stock = Config.StockFor[name]
	if stock then return (player:GetAttribute(stock) or 0) > 0 end
	if name == "Paint" then
		for _, p in Config.SprayPaints do
			if p.Stock and (player:GetAttribute(p.Stock) or 0) > 0 then return true end
		end
		return false
	end
	return true
end

local function unlockedProblems(player)
	local list = {}
	for _, name in Config.ProblemOrder do
		local needs = Config.Problems[name].Needs
		if (not needs or owns(player, needs)) and hasStockFor(player, name) then table.insert(list, name) end
	end
	return list
end

-- minIndex: only this rarity or rarer (the "Call a rare customer" product)
local function rollRarity(minIndex)
	minIndex = minIndex or 1
	local total = 0
	for i, r in Config.Rarities do
		if i >= minIndex then total += r.Weight end
	end
	local roll = math.random() * total
	for i, r in Config.Rarities do
		if i >= minIndex then
			roll -= r.Weight
			if roll <= 0 then return r end
		end
	end
	return Config.Rarities[minIndex] or Config.Rarities[1]
end

local function weighted(weights)
	local total = 0
	for _, w in weights do total += w end
	local roll = math.random() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then return i end
	end
	return 1
end

-- Pick which fixes a scooter needs: 1-3 of the unlocked types, a just-unlocked
-- type shows up in the next few jobs, and never the exact same set twice in a row.
local function rollProblems(player)
	local d = data[player]
	-- Studio test mode: the next fix on the tour, on its own
	if d.tour and #d.tour > 0 then
		local name = table.remove(d.tour, 1)
		d.lastKey = name
		return { [name] = true }
	end
	local open = unlockedProblems(player)
	local chosen, key
	for _ = 1, 8 do
		local count = math.min(weighted(Config.FixCountWeights), #open)
		chosen = {}
		if d.fresh and d.freshLeft > 0 then
			chosen[d.fresh[math.random(#d.fresh)]] = true
		end
		while true do
			local n = 0
			for _ in chosen do n += 1 end
			if n >= count then break end
			chosen[open[math.random(#open)]] = true
		end
		-- a dead battery gets swapped, so it can't also need charging
		if chosen.Battery and chosen.Charge then chosen.Charge = nil end
		local names = {}
		for _, name in Config.ProblemOrder do
			if chosen[name] then table.insert(names, name) end
		end
		key = table.concat(names, "+")
		if key ~= d.lastKey then break end
	end
	d.lastKey = key
	if d.fresh and d.freshLeft > 0 then d.freshLeft -= 1 end
	return chosen
end

-- Pick a job story (Config.Stories): its fixes belong together. Only stories whose
-- machines you own, no bigger than today allows; a just-unlocked fix gets a story
-- that uses it; never the same story twice in a row.
local function rollStory(player)
	local d = data[player]
	local open = {}
	for _, name in unlockedProblems(player) do open[name] = true end
	local day = player:GetAttribute("Day") or 1
	local maxFixes = Config.MaxFixesByDay[math.min(day, #Config.MaxFixesByDay)]
	local function usable(story)
		if #story.Fixes > maxFixes then return false end
		for _, f in story.Fixes do
			if not open[f] then return false end
		end
		return true
	end
	local want = d.fresh and d.freshLeft > 0 and d.fresh or nil
	local pool, weights = {}, {}
	for _, story in Config.Stories do
		local ok = usable(story) and story.Name ~= d.lastStory
		if ok and want then
			ok = false
			for _, f in story.Fixes do
				if table.find(want, f) then ok = true end
			end
		end
		if ok then
			table.insert(pool, story)
			table.insert(weights, story.Weight or 1)
		end
	end
	if #pool == 0 then
		-- nothing fits (early game, odd unlocks): the old random roll
		local chosen = rollProblems(player)
		local names = {}
		for name in chosen do table.insert(names, Config.Problems[name].Label) end
		return chosen, { Name = names[1] or "Quick Fix" }
	end
	local story = pool[weighted(weights)]
	if want and d.freshLeft > 0 then d.freshLeft -= 1 end
	local chosen, count = {}, 0
	for _, f in story.Fixes do
		chosen[f] = true
		count += 1
	end
	for _, f in story.Extra or {} do
		if open[f] and not chosen[f] and count < maxFixes and math.random() < 0.5 then
			chosen[f] = true
			count += 1
		end
	end
	if chosen.Battery and chosen.Charge then chosen.Charge = nil end
	d.lastStory = story.Name
	return chosen, story
end

Director.init({
	unlocked = unlockedProblems,
	maxFixes = function(player)
		local day = player:GetAttribute("Day") or 1
		return Config.MaxFixesByDay[math.min(day, #Config.MaxFixesByDay)]
	end,
})

-- The colour a repaint customer wants: usually one on the rack (one you have paint for), sometimes special.
local function pickPaintColour(player)
	local rack, special = {}, {}
	for _, p in Config.SprayPaints do
		if p.Special then
			table.insert(special, p.Name)
		elseif not p.Stock or (player:GetAttribute(p.Stock) or 0) > 0 then
			table.insert(rack, p.Name)
		end
	end
	if #rack == 0 then
		for _, p in Config.SprayPaints do
			if not p.Special then table.insert(rack, p.Name) end
		end
	end
	if #special > 0 and math.random() < (Config.SpecialPaintChance or 0) then
		return special[math.random(#special)]
	end
	return rack[math.random(#rack)]
end

-- opts (from the spawner): rush, queue, cap; the director plans the job from them (nil plan = the old roll)
local function makeJob(player, first, minRarity, opts)
	local d = data[player]
	d.nextId += 1
	local garage = Config.tierOf(player:GetAttribute("Garage") or 1) -- scooters come with the garage's tier

	-- the very first job is your own scooter with a flat tyre
	if first then
		local s = Config.Scooters[1]
		local p = Config.Problems.Tyre
		d.lastKey = "Tyre"
		return { Id = d.nextId, Scooter = s.Name, Problems = { "Tyre" }, Pay = s.Pay + p.Pay, Par = p.Par + 2, Rarity = "Common", First = true, Paint = Config.Paints[1].Name }
	end

	local plan
	if not (d.tour and #d.tour > 0) then
		opts = opts or {}
		opts.minRarity = minRarity
		plan = Director.next(player, opts)
	end

	-- newest scooter most of the time
	local scooter = plan and plan.Scooter
	if not scooter then
		local pool = {}
		for _, s in Config.Scooters do
			if s.Garage <= garage and game.ReplicatedStorage.Scooters:FindFirstChild(s.Name) then
				for _ = 1, (s.Garage == garage) and 3 or 1 do table.insert(pool, s) end
			end
		end
		scooter = pool[math.random(#pool)]
	end

	local chosen, story
	if plan then
		chosen, story = plan.Chosen, plan.Story
	elseif d.tour and #d.tour > 0 then
		-- Studio test mode: the next fix on the tour, on its own
		chosen = rollProblems(player)
		local name = next(chosen)
		story = { Name = name and Config.Problems[name].Label or "Test" }
	else
		chosen, story = rollStory(player)
	end
	local problems, pay, par = {}, scooter.Pay, 2
	for _, name in Config.ProblemOrder do
		if chosen[name] then
			table.insert(problems, name)
			pay += Config.Problems[name].Pay
			par += Config.Problems[name].Par
		end
	end
	-- rust on its own goes to the wash bay and back (with mud, the wash's time covers that)
	if chosen.Rust and not chosen.Mud then par += Config.Problems.Rust.Trip or 0 end
	local rarity = plan and plan.Rarity or rollRarity(minRarity)
	local paintWeights = {}
	for i, p in Config.Paints do paintWeights[i] = p.Weight end
	local paint = Config.Paints[weighted(paintWeights)]
	-- some customers are relaxed, some are in a hurry; bigger jobs buy you more time
	local persona = Config.Personalities[math.random(#Config.Personalities)]
	local patience = (persona.Patience + par * Config.PatiencePerPar + math.random(-5, 5)) * (plan and plan.Patience or 1)
	-- a twist on some jobs (rush, picky): not on the very first days' single fixes (the director says when)
	local mood
	if plan and plan.Mood then
		for _, m in Config.Moods do
			if m.Name == plan.Mood then mood = m end
		end
	elseif plan and plan.NoMood then
		mood = nil
	elseif #problems > 1 or (player:GetAttribute("Day") or 1) > 1 then
		for _, m in Config.Moods do
			if math.random() < m.Chance then mood = m break end
		end
	end
	pay *= (story.Pay or 1) * (mood and mood.Pay or 1) * (plan and plan.Pay or 1)
	patience *= mood and mood.Patience or 1
	par *= mood and mood.Par or 1
	return {
		Id = d.nextId,
		Scooter = scooter.Name,
		Problems = problems,
		Pay = math.floor(pay * rarity.Pay),
		Par = par,
		Rarity = rarity.Name,
		Paint = paint.Name,
		queuedAt = os.clock(),
		Personality = persona.Name,
		Patience = math.floor(patience),
		Story = story.Name,
		Mood = mood and mood.Name or nil,
		PaintTo = table.find(problems, "Paint") and pickPaintColour(player) or nil,
		Wear = story.Wear or math.clamp(0.2 + 0.15 * #problems, 0, 1),
		Slot = plan and plan.Slot or nil, -- the director's slot (Warm, Show, Core, Practice, Big, Cool, Quick, Script)
		NewScooter = plan and plan.NewScooter or nil, -- the first time you've had this model
	}
end

local function gap(player)
	local base = Config.ArrivalGap[1] + math.random() * (Config.ArrivalGap[2] - Config.ArrivalGap[1])
	return base * (levelValue(player, "Belt", "Gap") or 1)
end

---------------------------------------------------------------- garage rating
-- Every finished job is a review (its stars). The garage's rating is the
-- average of the last Config.RatingReviews, on a sign over the garage that
-- everyone in the server sees. (One garage for now: it shows the first player's.)
local GOLD, DIM_STAR = Color3.fromRGB(255, 200, 60), Color3.fromRGB(112, 118, 138)
-- Each garage has its own sign (Garage.Sign.Rating, built in Studio) showing its owner's
-- name, stars and score; everyone in the server sees every garage's sign.
local function updateRatingSign(leaving)
	for _, p in Players:GetPlayers() do
		local sg = p ~= leaving and Plots.sign(p)
		if sg then
			local rating = p:GetAttribute("Rating") or 0
			local count = p:GetAttribute("Reviews") or 0
			sg.title.Text = p.DisplayName .. "'s Garage"
			sg.title.TextColor3 = p:GetAttribute("Pass_VIP") and GOLD or Color3.new(1, 1, 1) -- VIP: a gold name
			for i, s in sg.stars do
				s.TextColor3 = count > 0 and rating >= i - 0.5 and GOLD or DIM_STAR
			end
			sg.score.Text = count > 0 and ("%.1f"):format(rating) or "NEW"
		end
	end
end

local function publishRating(player)
	local list = reviews[player] or {}
	local sum = 0
	for _, s in list do sum += s end
	player:SetAttribute("Rating", #list > 0 and math.floor(sum / #list * 10 + 0.5) / 10 or 0)
	player:SetAttribute("Reviews", #list)
	updateRatingSign()
end

local function addReview(player, stars)
	local list = reviews[player]
	if not list then return end
	table.insert(list, stars)
	while #list > Config.RatingReviews do table.remove(list, 1) end
	publishRating(player)
end

-- Today's numbers, for the day summary card at night (reset at dawn).
function newDay()
	return { Jobs = 0, Stars = 0, Cash = 0, Perfect = 0, Lost = 0, Best = nil }
end

local function onPlayerAdded(player)
	if not Plots.assign(player) then
		player:Kick("This server is full: every garage is taken.")
		return
	end
	updateRatingSign()
	local ok, saved = loadSave(player)
	if not player.Parent then return end
	loaded[player] = ok or nil
	if type(saved) ~= "table" then saved = nil end
	local items = saved and type(saved.Items) == "table" and saved.Items or {}
	-- a V1 save: old levels 1-4 move onto the 10-upgrade scale, the old Charger and Bin are refunded once
	local refund = 0
	if saved and (tonumber(saved.V) or 1) < Config.SaveVersion then
		for _, item in Config.Shop do
			local old = tonumber(items[item.Id])
			if item.Ups and old and old >= 1 then
				items[item.Id] = Config.OldLevel[math.clamp(math.floor(old), 1, #Config.OldLevel)]
			end
		end
		for id, prices in Config.OldRefund do
			local old = math.floor(tonumber(items[id]) or 0)
			for l = 1, math.min(old, #prices) do refund += prices[l] end
			items[id] = nil
		end
	end

	-- everything is set in one go (no yields) so the client never sees half a save
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = (saved and math.max(0, math.floor(tonumber(saved.Cash) or 0)) or 0) + refund
	if refund > 0 then player:SetAttribute("Refunded", refund) end -- the client shows "Refund +$X" once
	cash.Parent = ls
	for _, item in Config.Shop do
		local value = savedItem(item, items[item.Id], items)
		if value == nil then
			if item.Kind == "Stock" then
				value = item.Start or 0
			else
				value = ((item.Kind == "Level" and not item.Locked) or item.Starter) and 1 or 0
			end
		end
		player:SetAttribute(item.Id, value)
	end
	-- Studio test mode: every machine owned, every rack full (see Config.StudioTestAll)
	local testAll = RunService:IsStudio() and Config.StudioTestAll
	if testAll then
		for _, item in Config.Shop do
			if (item.Kind == "Unlock" or item.Kind == "Level") and (player:GetAttribute(item.Id) or 0) < 1 then
				player:SetAttribute(item.Id, 1)
			end
		end
		for _, item in Config.Shop do
			if item.Kind == "Stock" then
				local holder = item.Holder and shopItem(item.Holder)
				local cap = holder and holder.Capacity and holder.Capacity[player:GetAttribute(item.Holder) or 1] or item.Amount
				player:SetAttribute(item.Id, math.max(player:GetAttribute(item.Id) or 0, cap))
			end
		end
	end
	player:SetAttribute("Fixed", saved and tonumber(saved.Fixed) or 0)
	player:SetAttribute("WalkedOut", saved and tonumber(saved.WalkedOut) or 0)
	player:SetAttribute("Streak", 0)
	player:SetAttribute("Day", saved and math.max(1, tonumber(saved.Day) or 1) or 1)
	player:SetAttribute("LastOnline", saved and tonumber(saved.LastOnline) or 0)
	Market.restore(player, saved and saved.Caro)
	Director.restore(player, saved and saved.Director)
	player:SetAttribute("StarterPack", saved and saved.Starter == true or nil)
	local list = {}
	if saved and type(saved.Reviews) == "table" then
		for _, s in saved.Reviews do
			if type(s) == "number" then table.insert(list, math.clamp(math.floor(s), 1, 5)) end
		end
	end
	while #list > Config.RatingReviews do table.remove(list, 1) end
	reviews[player] = list
	publishRating(player)
	ls.Parent = player

	-- nobody turns up until your own scooter is fixed; after that customers choose garages (see the
	-- customers section at the end). Day and night come from the shared clock.
	local d = { queue = {}, actives = {}, nextId = 0, freshLeft = 0, today = newDay() }
	if testAll and Config.StudioTour then d.tour = table.clone(Config.StudioTour) end
	data[player] = d
	player:SetAttribute("ShopOpen", Clock.phase == "Day")
	player:SetAttribute("Night", false)
	if (player:GetAttribute("Fixed") or 0) == 0 then
		table.insert(d.queue, makeJob(player, true))
	end
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do task.spawn(onPlayerAdded, player) end

Players.PlayerRemoving:Connect(function(player)
	forgetCustomers(player)
	data[player] = nil
	updateRatingSign(player)
	Plots.release(player)
	writeSave(player, true)
	Director.forget(player)
	reviews[player] = nil
end)

-- Autosave, and a last save for everyone when the server shuts down.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveEvery)
		for _, player in Players:GetPlayers() do
			task.spawn(writeSave, player)
		end
	end
end)
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(writeSave, player, true)
	end
	task.wait() -- let the saves start
	local deadline = os.clock() + 20
	while pending > 0 and os.clock() < deadline do task.wait(0.1) end
end)

-- What the client sees: jobs plus how long each customer has been waiting.
local function snapshot(d)
	local now = os.clock()
	for _, job in d.queue do
		job.Age = job.queuedAt and (now - job.queuedAt) or 0
	end
	return d.queue
end

-- Fever loop (plan/12): the clock never stops — customers keep arriving and their
-- patience keeps running while you work, like Cooking Fever. The remote stays so
-- older clients can still fire it; it just doesn't pause anything any more.
SetBusy.OnServerEvent:Connect(function() end)

-- Customers turn up one at a time. Out of patience they get angry, and soon after
-- (Config.LeaveAfter) they take their scooter and walk off.
task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for player, d in data do
			local changed = false
			-- a rescued customer who wasn't rescued in time goes home angry after all
			if d.rescuing then
				if now >= (d.rescueUntil or 0) then
					local job = d.rescuing
					d.rescuing = nil
					player:SetAttribute("WalkedOut", (player:GetAttribute("WalkedOut") or 0) + 1)
					d.today.Lost += 1
					player:SetAttribute("LostToday", d.today.Lost)
					customerLeft(job, true)
					addReview(player, Config.WalkOutReview or 1)
				end
			end
			for i = #d.queue, 1, -1 do
				local job = d.queue[i]
				if job.Patience and now - job.queuedAt > job.Patience * Config.LeaveAfter then
					-- a big job about to walk: one short, quiet offer to keep them (plan/12)
					local cool = Config.Offers and Config.Offers.RescueCooldown or 180
					if not d.rescuing and job.Pay >= 120 and now - (d.rescueAt or 0) > cool then
						d.rescueAt = now
						d.rescuing = job
						d.rescueUntil = now + (Config.Offers and Config.Offers.RescueSeconds or 10)
						table.remove(d.queue, i)
						Offer:FireClient(player, {
							Kind = "Rescue", Scooter = job.Scooter, Pay = job.Pay,
							Seconds = Config.Offers and Config.Offers.RescueSeconds or 10,
							ProductId = Config.RescueProductId or 0,
							Price = Config.Offers and Config.Offers.RescuePrice or 24,
						})
						changed = true
						continue
					end
					table.remove(d.queue, i)
					player:SetAttribute("WalkedOut", (player:GetAttribute("WalkedOut") or 0) + 1)
					d.today.Lost += 1
					player:SetAttribute("LostToday", d.today.Lost) -- the HUD's lost-today chip
					customerLeft(job, true)
					-- a walk-out is a bad review: slow garages see their rating drop
					addReview(player, Config.WalkOutReview or 1)
					changed = true
				end
			end
			if changed then QueueChanged:FireClient(player, snapshot(d)) end
		end
	end
end)

-- "Hang on!" (Config.HangOn): everyone waiting gets a quarter of their patience back, once each.
HangOn.OnServerInvoke = function(player)
	local d = data[player]
	if not d then return false end
	local now = os.clock()
	if d.hangOnAt and now - d.hangOnAt < Config.HangOn.Cooldown then return false end
	local anyLow, n = false, 0
	for _, job in d.queue do
		if job.Patience and job.queuedAt and now - job.queuedAt > job.Patience * (1 - Config.HangOn.Below) then anyLow = true end
	end
	if not anyLow then return false end
	for _, job in d.queue do
		if job.Patience and job.queuedAt and not job.HungOn then
			job.HungOn = true
			job.queuedAt = math.min(now, job.queuedAt + job.Patience * Config.HangOn.Back)
			n += 1
		end
	end
	if n == 0 then return false end
	d.hangOnAt = now
	QueueChanged:FireClient(player, snapshot(d))
	return true
end

GetQueue.OnServerInvoke = function(player)
	local d = data[player]
	return d and snapshot(d) or {}
end

-- Picking a job starts its timer.
-- Fever parallel bench (plan/12): up to a couple of jobs in flight at once. A picked job
-- keeps its clock running even while parked, so switching costs stars — juggle carefully.
local function activeCap(player)
	local tier = Config.tierOf(player:GetAttribute("Bench") or 1)
	local P = Config.ParallelBench or { Tier2 = 2, Tier4 = 3 }
	return tier >= 4 and (P.Tier4 or 3) or tier >= 2 and (P.Tier2 or 2) or 1
end
local function activeCount(d)
	local n = 0
	for _ in d.actives do n += 1 end
	return n
end
local function currentJob(d)
	return d and d.actives and d.actives[d.current] or nil
end

PickJob.OnServerInvoke = function(player, id)
	local d = data[player]
	if not d or d.actives[id] or activeCount(d) >= activeCap(player) then return nil end
	for i, job in d.queue do
		if job.Id == id then
			table.remove(d.queue, i)
			d.actives[id] = job
			d.current = id
			job.started = os.clock()
			return job, snapshot(d)
		end
	end
	return nil
end

SwitchCurrent.OnServerInvoke = function(player, id)
	local d = data[player]
	if not d or type(id) ~= "number" or not d.actives[id] then return false end
	d.current = id
	return true
end

-- A finished fix pays on the spot (Fever loop, plan/12): an advance on the job's
-- repair pay; FinishJob subtracts what was already handed over and adds the rest.
StepDone.OnServerInvoke = function(player, name)
	local d = data[player]
	local job = currentJob(d)
	if not job or job.First or type(name) ~= "string" then return 0 end
	if not table.find(job.Problems, name) or (job.paidSteps and job.paidSteps[name]) then return 0 end
	-- a fix can't be over sooner than a fraction of its par after the last one on this job: a claim that
	-- quick is someone skipping the minigame. Nothing is lost by it, FinishJob still pays the whole job.
	local now = os.clock()
	if now - (job.lastStepAt or job.started or now) < Config.Problems[name].Par * 0.2 then return 0 end
	job.lastStepAt = now
	job.paidSteps = job.paidSteps or {}
	job.paidSteps[name] = true
	local benchPay = (levelValue(player, "Bench", "Pay") or 1) * (1 + Config.Caro.PackPay * ((player:GetAttribute("LookTier") or 1) - 1))
	local advance = math.max(1, math.floor(Config.Problems[name].Pay * benchPay * (Config.StepPay or 0.55)))
	job.advanced = (job.advanced or 0) + advance
	player.leaderstats.Cash.Value += advance
	d.today.Cash += advance
	return advance
end

local function starsFor(job, elapsed)
	local stars = 5
	for _, step in Config.StarSteps do
		if elapsed > job.Par * step then stars -= 1 end
	end
	return math.max(1, stars)
end

FinishJob.OnServerInvoke = function(player, jobId, paintQuality, skill)
	local d = data[player]
	local job
	if type(jobId) == "number" and d and d.actives[jobId] then
		job = d.actives[jobId]
		d.actives[jobId] = nil
	else
		-- an older client (or a job the restock card dropped): the only active job
		if d then
			local only
			for _, j in d.actives do
				if only then only = nil break end
				only = j
			end
			job = only
			if job then
				for id, j in d.actives do
					if j == job then d.actives[id] = nil end
				end
				paintQuality, skill = jobId, paintQuality
			end
		end
	end
	if not job or not d then return nil end
	if d.current and not d.actives[d.current] then d.current = nil end
	local elapsed = os.clock() - job.started
	if elapsed < #job.Problems * 1.5 then return nil end
	-- skill (Config.SkillPerfect): misses cost time, perfects pay a bonus. The counts come from the
	-- client, so they're capped: a miss can't cost more than 60% of par, perfects can't pass SkillMax.
	skill = type(skill) == "table" and skill or {}
	local perfects = math.clamp(math.floor(tonumber(skill.Perfect) or 0), 0, 30)
	local misses = math.clamp(math.floor(tonumber(skill.Miss) or 0), 0, 30)
	local penalty = math.min(misses * Config.MissSeconds, job.Par * 0.6)
	elapsed += penalty
	-- a battery swap has to have used a battery from your stock
	if table.find(job.Problems, "Battery") and not job.batteryUsed then return nil end
	if table.find(job.Problems, "Worn") and not (job.used and job.used.Tyres) then return nil end
	if table.find(job.Problems, "Light") and not (job.used and job.used.Bulbs) then return nil end
	if table.find(job.Problems, "Paint") and not job.paintedWith then return nil end
	local stars = starsFor(job, elapsed)
	-- the wrong colour: the customer isn't happy
	if job.wrongPaint then stars = math.max(1, stars - (Config.WrongPaint and Config.WrongPaint.Stars or 2)) end
	local recordTime = elapsed -- for the director, below (once the pay is known)
	-- customers review the garage (your own scooter doesn't count)
	if not job.First then addReview(player, stars) end
	-- a better workbench pays more for every job
	local benchPay = (levelValue(player, "Bench", "Pay") or 1) * (1 + Config.Caro.PackPay * ((player:GetAttribute("LookTier") or 1) - 1))
	-- the per-fix advances (StepDone) come off the repair pay here
	local repair = math.max(0, math.floor(job.Pay * benchPay) - (job.batteryDebt or 0) - (job.stockDebt or 0) - (job.advanced or 0))
	if job.wrongPaint then repair = math.floor(repair * (Config.WrongPaint and Config.WrongPaint.Pay or 0.5)) end
	local speed = math.floor(repair * (Config.StarPay[stars] - 1))
	local streak = 0
	if stars == 5 then
		streak = (player:GetAttribute("Streak") or 0) + 1
	end
	player:SetAttribute("Streak", streak)
	local streakBonus = 0
	if streak >= 2 then
		streakBonus = math.floor((repair + speed) * math.min((streak - 1) * Config.StreakStep, Config.StreakMax))
	end
	-- a tip for a nicely painted scooter (the client reports how well it was painted)
	local tip, grade = 0, nil
	if job.paintedWith and not job.wrongPaint and type(paintQuality) == "number" and Config.PaintGrades then
		local q = math.clamp(paintQuality, 0, 1)
		for _, g in Config.PaintGrades do
			if q >= g.Min then grade = g break end
		end
		if grade then tip = math.floor(repair * grade.Tip * (player:GetAttribute("Pass_VIP") and Config.VipTips or 1)) end
	end
	local skillBonus = math.floor(repair * math.min(perfects * Config.SkillPerfect, Config.SkillMax))
	-- the speed tip (Fever loop): finish at par for the full tip; it melts to nothing by Gone x par
	local ST = Config.SpeedTip or { Max = 0.2, TillPar = 1.0, Gone = 2.5 }
	local tipFrac = math.clamp(1 - (elapsed / math.max(job.Par, 1) - ST.TillPar) / (ST.Gone - ST.TillPar), 0, 1)
	local speedTip = math.floor(repair * ST.Max * tipFrac)
	local total = repair + speed + streakBonus + tip + skillBonus + speedTip
	-- the 2x Cash pass doubles the job's pay (not tips: plan/10 keeps a cash player within 2x)
	if player:GetAttribute("Pass_Cash2x") then total += repair + speed + streakBonus + skillBonus end
	player.leaderstats.Cash.Value += total
	player:SetAttribute("Fixed", (player:GetAttribute("Fixed") or 0) + 1)
	Director.record(player, job, stars, recordTime, total)
	-- the day card's numbers (your own first scooter doesn't count)
	if not job.First then
		local t = d.today
		t.Jobs += 1
		t.Stars += stars
		t.Cash += total
		if stars == 5 then t.Perfect += 1 end
		if not t.Best or total > t.Best.Total then t.Best = { Total = total, Stars = stars, Scooter = job.Scooter, Rarity = job.Rarity } end
	end
	d.lastRepair = { pay = repair, at = os.clock() }
	-- don't leave the belt empty for long: this garage's next customer comes soon
	if #d.queue == 0 and activeCount(d) == 0 then
		d.hungry = os.clock() + (job.First and Config.FirstArrival or Config.EmptyArrival)
	end
	customerLeft(job, false)
	return {
		Stars = stars, Repair = repair, Speed = speed, Streak = streak, StreakBonus = streakBonus, WrongPaint = job.wrongPaint or nil,
		SpeedTip = speedTip > 0 and speedTip or nil,
		Total = total, Time = elapsed, Rarity = job.Rarity, Scooter = job.Scooter,
		PaintTip = tip > 0 and tip or nil, PaintGrade = grade and grade.Name or nil,
		Skill = skillBonus > 0 and skillBonus or nil, Penalty = penalty > 0 and penalty or nil,
	}
end

-- Taking a fresh battery out of the holder for the job on the bench. Out of stock: the client shows the
-- restock card (Restock / GiveUpStock below); there's no borrowing any more (owner, 24 Oct).
UseBattery.OnServerInvoke = function(player)
	local d = data[player]
	local job = currentJob(d)
	if not job or job.batteryUsed or not table.find(job.Problems, "Battery") then return false end
	local stock = player:GetAttribute("Batteries") or 0
	if stock > 0 then
		player:SetAttribute("Batteries", stock - 1)
		job.batteryUsed = true
		return true
	end
	return false
end

-- One part out of stock for the job on the bench (a tyre for a worn tyre, a bulb for a broken light; same
-- rules as batteries): once per job.
local function useStock(player, _, problem, stockId)
	local d = data[player]
	local job = currentJob(d)
	if not job or not table.find(job.Problems, problem) then return false end
	job.used = job.used or {}
	if job.used[stockId] then return false end
	local stock = player:GetAttribute(stockId) or 0
	if stock > 0 then
		player:SetAttribute(stockId, stock - 1)
		job.used[stockId] = true
		return true
	end
	return false
end

-- A full holder of `stockId` (as much as its rack holds; a paint can holds what the booth's level allows).
local function fillStock(player, stockId)
	local item = shopItem(stockId)
	if not item or item.Kind ~= "Stock" then return false end
	local holder = item.Holder and shopItem(item.Holder)
	local cap = holder and holder.Capacity and holder.Capacity[math.max(1, player:GetAttribute(item.Holder) or 1)] or item.Amount
	player:SetAttribute(stockId, math.max(player:GetAttribute(stockId) or 0, cap))
	return true
end

-- Does this job still need `stockId` (it hasn't taken one yet)?
local function stillNeeds(job, stockId)
	if not table.find(Config.stockNeeds(job), stockId) then return false end
	if stockId == "Batteries" then return not job.batteryUsed end
	if job.used and job.used[stockId] then return false end
	for _, p in Config.SprayPaints do
		if p.Stock == stockId then return not job.paintedWith end
	end
	return true
end

-- The restock card's button. "prompt" = the client shows the purchase (ProcessReceipt fills the rack);
-- in Studio without a product it's free.
Restock.OnServerInvoke = function(player, stockId)
	local d = data[player]
	local item = type(stockId) == "string" and shopItem(stockId)
	if not d or not item or item.Kind ~= "Stock" then return "unavailable" end
	if (Config.RestockProductId or 0) > 0 then
		d.restockPending = stockId
		return "prompt"
	end
	if RunService:IsStudio() then
		fillStock(player, stockId)
		return "granted"
	end
	return "unavailable"
end

-- The card ran out (or "No thanks"): everyone whose job needs that part goes home. Not angry, no review:
-- it's the garage that's out, they'll be back another day. Returns how many left and whether the job on
-- the bench was one of them.
GiveUpStock.OnServerInvoke = function(player, stockId, onBench)
	local d = data[player]
	if not d or type(stockId) ~= "string" or (player:GetAttribute(stockId) or 0) > 0 then return 0, false end
	local lost = 0
	for i = #d.queue, 1, -1 do
		local job = d.queue[i]
		if stillNeeds(job, stockId) then
			table.remove(d.queue, i)
			customerLeft(job, false)
			lost += 1
		end
	end
	local dropped = false
	-- every in-flight job that still needs this part goes home too (the bench job counts as "dropped")
	for id, job in d.actives do
		if (onBench == true and id == d.current) or stillNeeds(job, stockId) then
			customerLeft(job, false)
			d.actives[id] = nil
			if id == d.current then dropped = true end
			lost += 1
		end
	end
	if d.current and not d.actives[d.current] then d.current = nil end
	d.today.Lost += lost
	player:SetAttribute("LostToday", d.today.Lost)
	if #d.queue == 0 then d.hungry = os.clock() + Config.EmptyArrival end
	QueueChanged:FireClient(player, snapshot(d))
	return lost, dropped
end

GetDay.OnServerInvoke = function(player)
	local d = data[player]
	if not d then return nil end
	local t = table.clone(d.today)
	t.Day = player:GetAttribute("Day") or 1
	-- today's cash goal (Fever loop / CF's TargetLow-Med-High): 1-3 stars, a chest at dawn
	local base = Config.nightCash(t.Day)
	local G = Config.DayGoals or { Low = 0.8, Med = 1.1, High = 1.45 }
	t.GoalLow = math.floor(base * G.Low)
	t.GoalMed = math.floor(base * G.Med)
	t.GoalHigh = math.floor(base * G.High)
	return t
end
UseTyre.OnServerInvoke = function(player, borrow) return useStock(player, borrow, "Worn", "Tyres") end

-- Spraying starts: which colour you picked. A rack colour uses one load from its
-- can; a special colour needs one you bought (BuyPaint / the Robux product).
-- Any colour other than the one the customer asked for is the wrong colour.
UsePaint.OnServerInvoke = function(player, name)
	local d = data[player]
	local job = currentJob(d) -- the job on the bench (parallel bench: d.actives[d.current])
	if not job or job.paintedWith or not table.find(job.Problems, "Paint") then return false end
	local def
	for _, p in Config.SprayPaints do
		if p.Name == name then def = p end
	end
	if not def then return false end
	if def.Stock then
		local left = player:GetAttribute(def.Stock) or 0
		if left <= 0 then return false end
		player:SetAttribute(def.Stock, left - 1)
	elseif def.Special then
		local key = Market.canKey(def.Name)
		local loads = player:GetAttribute(key)
		if loads and loads > 0 then
			player:SetAttribute(key, loads - 1) -- a rare can from Caro
		elseif name == job.PaintTo and (d.paintCredits or 0) > 0 then
			d.paintCredits -= 1
		else
			return false
		end
	end
	job.paintedWith = name
	job.wrongPaint = name ~= job.PaintTo
	return true
end

-- A special colour for this job. "prompt" = the client shows the Robux purchase
-- (ProcessReceipt below hands out the colour); in Studio without a product it's free.
BuyPaint.OnServerInvoke = function(player)
	local d = data[player]
	if not d then return "unavailable" end
	if (Config.PaintProductId or 0) > 0 then return "prompt" end
	if RunService:IsStudio() then
		d.paintCredits = (d.paintCredits or 0) + 1
		return "granted"
	end
	return "unavailable"
end
-- Sending a waiting customer away (the X on their card) is a Robux buy: no walk-out review, their spot frees up.
-- RejectJob remembers which card was tapped; "prompt" = the client shows the purchase, ProcessReceipt does the rest.
local function rejectJob(player, d, id)
	for i, job in d.queue do
		if job.Id == id or id == nil then
			table.remove(d.queue, i)
			customerLeft(job, false)
			QueueChanged:FireClient(player, snapshot(d))
			return true
		end
	end
	return false
end
RejectJob.OnServerInvoke = function(player, id)
	local d = data[player]
	if not d or typeof(id) ~= "number" then return "unavailable" end
	d.rejectPending = id
	if (Config.RejectProductId or 0) > 0 then return "prompt" end
	if RunService:IsStudio() then return rejectJob(player, d, id) and "done" or "unavailable" end
	return "unavailable"
end

game:GetService("MarketplaceService").ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local d = player and data[player]
	if not d then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if receipt.ProductId == Config.RejectProductId and Config.RejectProductId > 0 then
		-- the card they tapped; if that customer already left, the one who's waited longest
		if not rejectJob(player, d, d.rejectPending) then rejectJob(player, d, nil) end
		d.rejectPending = nil
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if receipt.ProductId == Config.RestockProductId and Config.RestockProductId > 0 then
		-- the part on the card; if that's gone, every empty rack
		if not (d.restockPending and fillStock(player, d.restockPending)) then
			for _, item in Config.Shop do
				if item.Kind == "Stock" and (player:GetAttribute(item.Id) or 0) <= 0 then fillStock(player, item.Id) end
			end
		end
		d.restockPending = nil
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if receipt.ProductId == Config.RescueProductId and Config.RescueProductId > 0 then
		-- the walk-out rescue: the pulled-aside customer comes back to the belt, patient again
		local job = d.rescuing
		d.rescuing = nil
		if job then
			job.queuedAt = os.clock()
			table.insert(d.queue, job)
			QueueChanged:FireClient(player, snapshot(d))
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if receipt.ProductId == Config.PaintProductId then
		d.paintCredits = (d.paintCredits or 0) + 1
		player:SetAttribute("PaintCredits", d.paintCredits)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	for _, item in Config.Store do
		if item.Kind == "Product" and (item.ProductId or 0) > 0 and item.ProductId == receipt.ProductId then
			return storeGrant(player, item) and Enum.ProductPurchaseDecision.PurchaseGranted or Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	if Market.grantProduct(player, receipt.ProductId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
UseBulb.OnServerInvoke = function(player, borrow) return useStock(player, borrow, "Light", "Bulbs") end

-- Trash taken out at night: now you can upgrade (the shared clock decides when dawn comes).
EmptyTrash.OnServerInvoke = function(player)
	local d = data[player]
	if not d or Clock.phase ~= "Night" or activeCount(d) > 0 then return false end
	d.night = true
	player:SetAttribute("Night", true)
	return true
end

-- The old "flip the sign to open" shortcut: the day now starts at dawn for everyone, so this does nothing.
OpenShop.OnServerInvoke = function(player)
	return nil
end

-- Optional test ride after a fix: tip for a clean ride plus jumps.
RideTip.OnServerInvoke = function(player, clean, airs)
	local d = data[player]
	local last = d and d.lastRepair
	if not last then return nil end
	d.lastRepair = nil
	if os.clock() - last.at < 5 then return nil end
	local tip = clean == true and math.floor(last.pay * Config.RideTip * (player:GetAttribute("Pass_VIP") and Config.VipTips or 1)) or 0
	local air = math.clamp(tonumber(airs) or 0, 0, 4) * Config.AirBonus
	player.leaderstats.Cash.Value += tip + air
	d.today.Cash += tip + air
	return { Tip = tip, Air = air, Total = tip + air }
end

BuyShop.OnServerInvoke = function(player, id)
	local item = shopItem(id)
	if not item or item.Starter then return false end
	if item.Needs and (player:GetAttribute(item.Needs) or 0) == 0 then return false end
	-- a machine you don't have yet may wait for a bench or garage tier (Gate)
	if (player:GetAttribute(id) or 0) == 0 and not Config.gateOpen(item, function(g) return player:GetAttribute(g) end) then return false end
	-- everything is bought at the upgrade stand at night (plan/12: dusk opens upgrades for
	-- everyone — no chore in the way; the trash run stays as flavour, not a key)
	local d = data[player]
	if not d or Clock.phase ~= "Night" then return false end
	local level = player:GetAttribute(id) or 0
	local price, add
	if item.Kind == "Level" then
		price = item.Prices[level + 1]
	elseif item.Kind == "Stock" then
		-- only as much as the holder has room for; a part-filled pack costs its share
		local holder = item.Holder and shopItem(item.Holder)
		if holder and holder.Locked and (player:GetAttribute(item.Holder) or 0) == 0 then return false end
		local cap = holder and holder.Capacity and holder.Capacity[player:GetAttribute(item.Holder) or 1] or math.huge
		add = math.min(item.Amount, cap - level)
		if add <= 0 then return false end
		price = math.ceil(item.Price * add / item.Amount)
	elseif level == 0 then
		price = item.Price
	end
	if not price then return false end
	local cash = player.leaderstats.Cash
	if cash.Value < price then
		-- a need-timed top-up (plan/12): the exact upgrade you're short on, offered briefly
		if d and (d.topUpAt == nil or os.clock() - d.topUpAt > (Config.Offers and Config.Offers.TopUpCooldown or 300)) then
			d.topUpAt = os.clock()
			d.topShort = price - cash.Value
			Offer:FireClient(player, {
				Kind = "TopUp",
				Item = item.Names and (item.Names[math.min(#item.Names, level + 1)] or item.Id) or item.Title or item.Id,
				Short = d.topShort,
			})
		end
		return false
	end
	cash.Value -= price
	if item.Kind == "Stock" then
		player:SetAttribute(id, level + add)
		return true
	end
	player:SetAttribute(id, level + 1)
	-- a machine bought for the first time comes stocked (the tyre rack with its tyres)
	if level == 0 and item.Locked and item.Capacity then
		for _, stock in Config.Shop do
			if stock.Kind == "Stock" and stock.Holder == id then
				player:SetAttribute(stock.Id, math.max(player:GetAttribute(stock.Id) or 0, item.Capacity[1]))
			end
		end
	end
	-- show off what you just unlocked in the next few jobs
	local fresh = {}
	for name, p in Config.Problems do
		if p.Needs == id then table.insert(fresh, name) end
	end
	if d and #fresh > 0 then
		d.fresh = fresh
		d.freshLeft = Config.FreshJobs
	end
	Director.bought(player, id, fresh)
	return true
end

---------------------------------------------------------------- shared day and night
-- Dusk closes every garage at once; dawn opens them all. Upgrades open once you've bagged the
-- trash at night (the Night attribute); waiting customers are served first.
local function applyPhase(name)
	local day = name == "Day"
	for player, d in data do
		player:SetAttribute("ShopOpen", day)
		if day then
			-- yesterday's day-goal (Fever loop): stars and a chest bonus at dawn
			local base = Config.nightCash(player:GetAttribute("Day") or 1)
			local G = Config.DayGoals or { Low = 0.8, Med = 1.1, High = 1.45 }
			local stars, bonus = 0, 0
			if d.today.Cash >= base * G.High then
				stars, bonus = 3, math.floor(base * 0.3)
			elseif d.today.Cash >= base * G.Med then
				stars, bonus = 2, math.floor(base * 0.12)
			elseif d.today.Cash >= base * G.Low then
				stars = 1
			end
			player:SetAttribute("DayStars", stars)
			if bonus > 0 then
				player.leaderstats.Cash.Value += bonus
				player:SetAttribute("DayBonus", bonus)
			end
			Director.newDay(player, d.today.Cash)
			d.today = newDay()
			player:SetAttribute("LostToday", 0)
			d.night = false
			player:SetAttribute("Night", false)
			if Clock.number > 1 then
				player:SetAttribute("Day", (player:GetAttribute("Day") or 1) + 1)
			end
		else
			-- plan/12: dusk opens upgrades for everyone — no trash chore gate, and waiting
			-- customers can no longer hold anyone's upgrades hostage
			d.night = true
			player:SetAttribute("Night", true)
		end
	end
end
Clock.onPhase(applyPhase)

---------------------------------------------------------------- customers choose garages
-- One spawner for the whole server. Every so often a customer steps off the bus and picks an
-- open garage (owner done with their own scooter, queue not full) by its stars; every client
-- sees them walk past the other garages to the one they chose.
local crowd = {} -- [customerId] = { player, plot, jobId, seed, at }
local nextCustomerId = 0

customerLeft = function(job, angry)
	local id = job and job.CustomerId
	if not id or not crowd[id] then return end
	crowd[id] = nil
	CustomerLeft:FireAllClients(id, angry == true, false)
end

forgetCustomers = function(player)
	for id, c in crowd do
		if c.player == player then
			crowd[id] = nil
			CustomerLeft:FireAllClients(id, false, true) -- their garage is gone: they wander off
		end
	end
end

GetCrowd.OnServerInvoke = function()
	local now = os.clock()
	local list = {}
	for id, c in crowd do
		table.insert(list, { Id = id, Plot = c.plot, Owner = c.player.UserId, JobId = c.jobId, Seed = c.seed, Age = now - c.at })
	end
	return list
end

local function candidates()
	local list = {}
	for player, d in data do
		if player.Parent and Plots.indexOf(player) and (player:GetAttribute("Fixed") or 0) > 0 then
			local cap = levelValue(player, "Belt", "Queue") or 2
			-- parked jobs sit on the belt too: the belt owns the Queue slots plus the bench (plan/12)
			if #d.queue + activeCount(d) < cap + 1 then
				local weight = Spawner.weight(player:GetAttribute("Rating") or 0, player:GetAttribute("Reviews") or 0,
					(player:GetAttribute("Day") or 1) <= 1, player:GetAttribute("Marketer") == true)
				-- swamped (two going red, or the last two jobs went badly): customers come a bit less often
				if Director.struggling(player, d.queue, nil) then weight *= Config.Director.SlowArrivals end
				weight *= levelValue(player, "Garage", "Appeal") or 1 -- a fancier garage pulls more customers
				table.insert(list, { player = player, weight = weight })
			end
		end
	end
	return list
end

local rushAt, rushUntil = nil, 0 -- lunch rush (below)

local function spawnCustomer(player, minRarity)
	local d = data[player]
	local arrive = Plots.arrivePosition(player)
	if not (d and arrive) then return end
	local job = makeJob(player, false, minRarity, {
		rush = os.clock() < rushUntil, queue = d.queue, cap = levelValue(player, "Belt", "Queue") or 2,
	})
	if os.clock() < rushUntil then
		job.Pay = math.floor(job.Pay * Config.LunchRush.Pay)
		job.Rush = true
	end
	local walk = Crowd.length(Crowd.route(arrive, true)) / Config.WalkSpeed
	job.queuedAt = os.clock() + walk -- patience starts when they get there
	job.Walk = walk
	nextCustomerId += 1
	job.CustomerId = nextCustomerId
	local seed = math.random(1, 1000000) -- the same look for this customer on every screen
	job.Seed = seed
	table.insert(d.queue, job)
	d.hungry = nil
	local plot = Plots.indexOf(player)
	crowd[nextCustomerId] = { player = player, plot = plot, jobId = job.Id, seed = seed, at = os.clock() }
	QueueChanged:FireClient(player, snapshot(d))
	CustomerSpawned:FireAllClients({ Id = nextCustomerId, Plot = plot, Owner = player.UserId, JobId = job.Id, Seed = seed, Walk = walk })
end

-- Lunch rush (Config.LunchRush): once a day everyone's garage gets busy at once. workspace.LunchRushEndsAt
-- (server time) tells the clients; jobs that arrive during it pay more.
Clock.onPhase(function(name)
	rushUntil = 0
	workspace:SetAttribute("LunchRushEndsAt", nil)
	local R = Config.LunchRush
	rushAt = name == "Day" and os.clock() + Config.DaySeconds * (R.From + math.random() * (R.To - R.From)) or nil
end)
local function rushing() return os.clock() < rushUntil end

task.spawn(function()
	local nextSpawn = 0
	local avgGap = (Config.ArrivalGap[1] + Config.ArrivalGap[2]) / 2
	while true do
		task.wait(0.5)
		if Clock.phase ~= "Day" then continue end -- night: nobody new comes
		local now = os.clock()
		if rushAt and now >= rushAt then
			rushAt = nil
			rushUntil = now + Config.LunchRush.Seconds
			workspace:SetAttribute("LunchRushEndsAt", workspace:GetServerTimeNow() + Config.LunchRush.Seconds)
			nextSpawn = now -- the first rush customer steps off the bus right away
		end
		local list = candidates()
		if #list == 0 then continue end
		-- a garage that just ran out of customers gets someone soon
		local chosen
		for _, c in list do
			local d = data[c.player]
			if d.hungry and now >= d.hungry and #d.queue == 0 then chosen = c break end
		end
		if chosen or now >= nextSpawn then
			chosen = chosen or Spawner.pick(list)
			spawnCustomer(chosen.player)
			-- the more open garages (and the faster their belts), the more often someone arrives
			local rate = 0
			for _, c in list do rate += 1 / (avgGap * (levelValue(c.player, "Belt", "Gap") or 1)) end
			local gapNow = Config.ArrivalGap[1] + math.random() * (Config.ArrivalGap[2] - Config.ArrivalGap[1])
			nextSpawn = now + gapNow / (avgGap * rate) / (rushing() and Config.LunchRush.Rate or 1)
		end
	end
end)

---------------------------------------------------------------- the Robux store
-- Config.Store. Products come through ProcessReceipt (above), passes through PromptGamePassPurchaseFinished
-- and an ownership check when you join. With an id of 0, Studio hands it over free (for testing).
local MarketplaceService = game:GetService("MarketplaceService")
local function storeItem(id)
	for _, item in Config.Store do
		if item.Id == id then return item end
	end
end

-- Why it can't be bought right now (nil = it can).
local function storeBlocked(player, item)
	local d = data[player]
	if not d then return "unavailable" end
	if item.Kind == "Pass" and player:GetAttribute("Pass_" .. item.Id) then return "owned" end
	if item.Once and player:GetAttribute("StarterPack") then return "owned" end
	if item.Id == "CallCustomer" or item.Id == "CallRare" then
		if Clock.phase ~= "Day" or (player:GetAttribute("Fixed") or 0) == 0 or #d.queue >= (levelValue(player, "Belt", "Queue") or 2) then return "notnow" end
	end
	return nil
end

storeGrant = function(player, item)
	local cash = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
	if not cash then return false end
	if item.Id == "Starter" then
		cash.Value += Config.StarterCash
		player:SetAttribute("GoldenWrench", 1)
		local key = Market.canKey("Galaxy Purple")
		player:SetAttribute(key, math.max(player:GetAttribute(key) or 0, Config.Caro.CanLoads))
		player:SetAttribute("StarterPack", true)
	elseif item.Nights then
		cash.Value += item.Nights * Config.nightCash(player:GetAttribute("Day") or 1)
	elseif item.Kind == "Pass" then
		player:SetAttribute("Pass_" .. item.Id, true)
		updateRatingSign()
	elseif item.Id == "CallCustomer" then
		spawnCustomer(player)
	elseif item.Id == "CallRare" then
		spawnCustomer(player, 3)
	end
	return true
end

-- Context offers (plan/12): the buy button on a need-timed popup. In Studio (no product ids yet)
-- it grants free so the loop can be tested; live servers prompt the product.
OfferBuy.OnServerInvoke = function(player, kind)
	local d = data[player]
	if not d then return false end
	if kind == "Rescue" then
		local job = d.rescuing
		if not job then return false end
		if (Config.RescueProductId or 0) > 0 then return "prompt" end
		if RunService:IsStudio() then
			d.rescuing = nil
			job.queuedAt = os.clock()
			table.insert(d.queue, job)
			QueueChanged:FireClient(player, snapshot(d))
			return true
		end
		return false
	elseif kind == "TopUp" then
		local short = d.topShort or 0
		local day = player:GetAttribute("Day") or 1
		local item = short <= 2 * Config.nightCash(day) and storeItem("CashS")
			or short <= 7 * Config.nightCash(day) and storeItem("CashM") or storeItem("CashL")
		if not item then return false end
		if (item.ProductId or 0) > 0 then return "prompt" end
		if RunService:IsStudio() then
			storeGrant(player, item)
			d.topShort = nil
			return true
		end
	end
	return false
end

-- "granted" (Studio, free) / "prompt" (product) / "pass" / "owned" / "notnow" / "unavailable"
StoreBuy.OnServerInvoke = function(player, id)
	local item = type(id) == "string" and storeItem(id)
	if not item then return "unavailable" end
	local why = storeBlocked(player, item)
	if why then return why end
	local assetId = item.Kind == "Pass" and item.PassId or item.ProductId
	if (assetId or 0) > 0 then return item.Kind == "Pass" and "pass" or "prompt" end
	if RunService:IsStudio() then return storeGrant(player, item) and "granted" or "unavailable" end
	return "unavailable"
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if not bought then return end
	for _, item in Config.Store do
		if item.Kind == "Pass" and item.PassId == passId then storeGrant(player, item) end
	end
end)
local function checkPasses(player)
	for _, item in Config.Store do
		if item.Kind == "Pass" and (item.PassId or 0) > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.PassId)
			if ok and owns then player:SetAttribute("Pass_" .. item.Id, true) end
		end
	end
	updateRatingSign()
end
Players.PlayerAdded:Connect(checkPasses)
for _, p in Players:GetPlayers() do task.spawn(checkPasses, p) end

---------------------------------------------------------------- Caro's night market
Market.init(MarketChanged)
GetMarket.OnServerInvoke = function(player) return Market.view(player) end
BuyMarket.OnServerInvoke = function(player, id)
	local ok, reason = Market.buy(player, id)
	Van.react(player, ok, reason) -- Caro cheers (or shrugs) at her counter
	return ok, reason
end
RefillCan.OnServerInvoke = function(player, colour) return Market.refillCan(player, colour) end
Clock.onPhase(function(name)
	Market.onPhase(name, Players:GetPlayers())
	task.spawn(function()
		if name == "Night" then
			Market.roll(Clock.number, game.JobId)
			Van.arrive() -- drives in, parks, opens the hatch
			if Clock.phase == "Night" then
				Market.setOpen(true)
				MarketArrived:FireAllClients(Market.headline())
			end
		elseif name == "Day" then
			Market.setOpen(false)
			Van.leave()
		end
	end)
end)

Clock.start()
