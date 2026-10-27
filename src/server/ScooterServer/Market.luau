-- Caro's night market: tonight's stock (rolled once per night for the whole server), purchases and
-- what each item does. The van that carries it is in the Van module; this is the shop behind the counter.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.ScooterConfig)
local Caro = Config.Caro

local M = { open = false, stock = {}, night = 0 }
local changed -- RemoteEvent: fired to everyone whenever the stock or the opening state changes

function M.init(remoteChanged)
	changed = remoteChanged
end

local function hashId(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

local function def(id)
	for _, item in Caro.Items do
		if item.Id == id then return item end
	end
end
M.def = def

local function shopItem(id)
	for _, item in Config.Shop do
		if item.Id == id then return item end
	end
end

-- the attribute that holds a rare can's remaining sprays (nil = not owned)
function M.canKey(colour)
	return "Can" .. colour:gsub("%s", "")
end

local function crateLimit(player, stockId)
	local item = shopItem(stockId)
	local holder = item and item.Holder and shopItem(item.Holder)
	local level = holder and (player:GetAttribute(item.Holder) or 1) or 1
	local cap = holder and holder.Capacity and holder.Capacity[level] or math.huge
	return math.floor(cap * Caro.CrateOverCap)
end

-- Roll tonight's stock. Same server + same night = same shelf.
function M.roll(night, jobId)
	M.night = night
	local rng = Random.new(night * 7919 + hashId(jobId or ""))
	local specials = {}
	for _, p in Config.SprayPaints do
		if p.Special then table.insert(specials, p) end
	end
	local stock, have = {}, {}
	for _, item in Caro.Items do
		if rng:NextNumber() < item.Chance then
			local e = { Id = item.Id, Left = item.Qty, Qty = item.Qty }
			if item.Kind == "Can" then e.Colour = specials[rng:NextInteger(1, #specials)].Name end
			table.insert(stock, e)
			have[item.Id] = true
		end
	end
	for _, item in Caro.Items do
		if #stock >= Caro.MinItems then break end
		if item.Kind == "Crate" and not have[item.Id] then
			table.insert(stock, { Id = item.Id, Left = item.Qty, Qty = item.Qty })
			have[item.Id] = true
		end
	end
	-- still short (both crates already on the shelf): something else from the catalogue turns up
	local pool = {}
	for _, item in Caro.Items do
		if not have[item.Id] then table.insert(pool, item) end
	end
	while #stock < Caro.MinItems and #pool > 0 do
		local item = table.remove(pool, rng:NextInteger(1, #pool))
		local e = { Id = item.Id, Left = item.Qty, Qty = item.Qty }
		if item.Kind == "Can" then e.Colour = specials[rng:NextInteger(1, #specials)].Name end
		table.insert(stock, e)
	end
	M.stock = stock
	return stock
end

-- The night's pitch (for the arrival announcement): says WHAT the market is, not just the rarest item.
function M.headline()
	local best, bestChance
	for _, e in M.stock do
		local d = def(e.Id)
		if d.Rare and (not bestChance or d.Chance < bestChance) then
			best, bestChance = e.Colour and ("Rare paint: " .. e.Colour) or d.Title, d.Chance
		end
	end
	if best then return "Caro's Night Market is open — tonight's headliner: " .. best end
	return "Caro's Night Market is open — crates in stock tonight, gone at dawn"
end

-- Why this player can't buy it (a short word for the button), or nil if they can.
function M.blocked(player, e)
	local d = def(e.Id)
	if e.Left <= 0 then return "SOLD OUT" end
	if d.Kind == "Tool" and player:GetAttribute(d.Attr) == 1 then return "OWNED" end
	if d.Kind == "Helper" and player:GetAttribute("Helper") == 1 then return "OWNED" end
	if d.Kind == "Can" and player:GetAttribute(M.canKey(e.Colour)) ~= nil then return "OWNED" end
	if d.Kind == "Marketer" and (player:GetAttribute("MarketerNext") or player:GetAttribute("Marketer")) then return "BOOKED" end
	if d.Kind == "Pack" and (player:GetAttribute("LookTier") or 1) >= Caro.LookTiers then return "MAX" end
	if d.Kind == "Crate" and (player:GetAttribute(d.Stock) or 0) >= crateLimit(player, d.Stock) then return "FULL" end
	return nil
end

-- What the client draws.
function M.view(player)
	local items = {}
	for _, e in M.stock do
		local d = def(e.Id)
		table.insert(items, {
			Id = e.Id, Title = e.Colour and ("Rare paint: " .. e.Colour) or d.Title, Icon = d.Icon, Desc = d.Desc, Kind = d.Kind, Colour = e.Colour,
			Price = d.Price, Product = d.Product or 0, Robux = d.Robux, Left = e.Left, Qty = e.Qty, Rare = d.Rare == true, Blocked = M.blocked(player, e),
		})
	end
	return { Open = M.open, Items = items }
end

local function broadcast()
	if not changed then return end
	local left = {}
	for _, e in M.stock do left[e.Id] = e.Left end
	changed:FireAllClients(M.open, left)
end

function M.setOpen(open)
	M.open = open
	broadcast()
end

local function apply(player, e, d)
	local k = d.Kind
	if k == "Marketer" then
		player:SetAttribute("MarketerNext", true) -- tomorrow's customers pick your garage more
	elseif k == "Helper" then
		player:SetAttribute("Helper", 1)
	elseif k == "Pack" then
		player:SetAttribute("LookTier", math.min(Caro.LookTiers, (player:GetAttribute("LookTier") or 1) + 1))
	elseif k == "Tool" then
		player:SetAttribute(d.Attr, 1)
	elseif k == "Can" then
		player:SetAttribute(M.canKey(e.Colour), Caro.CanLoads)
	elseif k == "Crate" then
		player:SetAttribute(d.Stock, math.min((player:GetAttribute(d.Stock) or 0) + d.Amount, crateLimit(player, d.Stock)))
	elseif k == "Mystery" then
		-- CF's mystery box (its native code has CAutomaticBoxOdds): one random rare the player
		-- doesn't already own. If they own everything, the crate falls back to a battery crate.
		local pool = {}
		for _, item in Caro.Items do
			if item.Rare and item.Kind ~= "Mystery" then
				local probe = { Id = item.Id, Left = 1, Qty = 1, Colour = item.Kind == "Can" and "Hot Pink" or nil }
				if not M.blocked(player, probe) then table.insert(pool, item) end
			end
		end
		local win = pool[math.random(#pool)]
		if win then
			apply(player, { Id = win.Id, Left = 1, Qty = 1, Colour = win.Kind == "Can" and "Hot Pink" or nil }, win)
		else
			local fallback = def("BatteryCrate")
			if fallback then apply(player, { Id = fallback.Id, Left = 1, Qty = 1 }, fallback) end
		end
	end
end

-- Cash purchase. Returns ok, reason.
function M.buy(player, id)
	if not M.open then return false, "closed" end
	local e
	for _, x in M.stock do
		if x.Id == id then e = x end
	end
	if not e then return false, "unknown" end
	local why = M.blocked(player, e)
	if why then return false, why == "SOLD OUT" and "soldout" or "owned" end
	local d = def(id)
	local cash = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
	if not cash or cash.Value < d.Price then return false, "poor" end
	cash.Value -= d.Price
	apply(player, e, d)
	e.Left -= 1
	broadcast()
	return true
end

-- A Robux purchase (ProcessReceipt): hands the item over whether or not the shelf still has one.
function M.grantProduct(player, productId)
	for _, d in Caro.Items do
		if (d.Product or 0) > 0 and d.Product == productId then
			local e
			for _, x in M.stock do
				if x.Id == d.Id then e = x end
			end
			e = e or { Id = d.Id, Left = 0, Qty = d.Qty, Colour = d.Kind == "Can" and "Galaxy Purple" or nil }
			apply(player, e, d)
			if e.Left > 0 then e.Left -= 1 end
			broadcast()
			return true
		end
	end
	return false
end

-- Refill a rare can at the booth.
function M.refillCan(player, colour)
	if type(colour) ~= "string" then return false end
	local key = M.canKey(colour)
	local loads = player:GetAttribute(key)
	if loads == nil or loads >= Caro.CanLoads then return false end
	local cash = player.leaderstats and player.leaderstats:FindFirstChild("Cash")
	if not cash or cash.Value < Caro.RefillCan then return false end
	cash.Value -= Caro.RefillCan
	player:SetAttribute(key, Caro.CanLoads)
	return true
end

-- dawn / dusk: a Marketer booked at night works the next day
function M.onPhase(name, players)
	for _, p in players do
		if name == "Day" then
			p:SetAttribute("Marketer", p:GetAttribute("MarketerNext") == true)
			p:SetAttribute("MarketerNext", false)
		else
			p:SetAttribute("Marketer", false)
		end
	end
end

---------------------------------------------------------------- saving
-- Everything permanent Caro sold: the tools, Helper Mo, the garage look tier and rare cans (with their sprays left).
local PERMANENT = { "GoldenWrench", "ChromePump", "NeonCharger", "TurboLance", "Helper" }
function M.collect(player)
	local rec = { Cans = {}, LookTier = player:GetAttribute("LookTier") or 1, MarketerNext = player:GetAttribute("MarketerNext") == true }
	for _, a in PERMANENT do rec[a] = player:GetAttribute(a) == 1 and 1 or nil end
	for _, p in Config.SprayPaints do
		if p.Special then
			local loads = player:GetAttribute(M.canKey(p.Name))
			if loads ~= nil then rec.Cans[p.Name] = loads end
		end
	end
	return rec
end

function M.restore(player, rec)
	rec = type(rec) == "table" and rec or {}
	for _, a in PERMANENT do player:SetAttribute(a, rec[a] == 1 and 1 or nil) end
	player:SetAttribute("LookTier", math.clamp(math.floor(tonumber(rec.LookTier) or 1), 1, Caro.LookTiers))
	player:SetAttribute("MarketerNext", rec.MarketerNext == true)
	player:SetAttribute("Marketer", false)
	for _, p in Config.SprayPaints do
		if p.Special then
			local loads = type(rec.Cans) == "table" and tonumber(rec.Cans[p.Name]) or nil
			player:SetAttribute(M.canKey(p.Name), loads and math.clamp(math.floor(loads), 0, Caro.CanLoads) or nil)
		end
	end
end

return M
