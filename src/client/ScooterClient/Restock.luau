-- The out-of-stock card (owner, 24 Oct): run out of a part and a card offers a full restock for
-- Config.RestockRobux. It waits Config.RestockSeconds (the bar drains; the clock stops while Roblox's purchase
-- box is open), then goes, and everyone whose job needed the part goes home (ScooterServer GiveUpStock).
-- The card is authored in StarterGui.FixUI.Restock (ShopTicketKit).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local Style = require(RS:WaitForChild("UIStyle"))
local R = {}
local env -- { gui, config, remotes, sfx, SFX, popScale, popText }
local busy = false

local WORD = { Batteries = "BATTERIES", Tyres = "TYRES", Bulbs = "BULBS", PaintRed = "RED PAINT", PaintBlue = "BLUE PAINT", PaintYellow = "YELLOW PAINT" }

function R.init(e)
	env = e
end

local function stock(id)
	return player:GetAttribute(id) or 0
end

-- Shows the card for `stockId`. Returns true once the rack is full again, false if the time ran out
-- (or "No thanks").
function R.offer(stockId)
	while busy do task.wait(0.1) end -- one card at a time
	if stock(stockId) > 0 then return true end
	busy = true
	local cfg = env.config
	local card = env.gui.Restock
	local item
	for _, i in cfg.Shop do
		if i.Id == stockId then item = i end
	end
	card.Title.Text = ("OUT OF %s!"):format(WORD[stockId] or stockId:upper())
	card.Icon.Image = Style.Icon[item and item.Icon or ""] or ""
	card.Buy.Button.Label.Text = ("RESTOCK  R$%d"):format(cfg.RestockRobux)
	card.Time.Fill.Size = UDim2.fromScale(1, 1)
	card.Visible = true
	env.popScale(card, 0.7, 0.25)
	env.sfx(env.SFX.Tap, 0.9, 0.4)
	local result -- "bought" / "skip"
	local paused = false
	local conns = {}
	table.insert(conns, card.Buy.Button.Activated:Connect(function()
		if result or paused then return end
		paused = true
		local r = env.remotes.Restock:InvokeServer(stockId)
		if r == "granted" then
			result = "bought"
		elseif r == "prompt" then
			-- the clock waits while Roblox's box is open; the receipt can land a moment after it closes
			local closed = false
			local c = MarketplaceService.PromptProductPurchaseFinished:Connect(function(uid, pid)
				if uid == player.UserId and pid == cfg.RestockProductId then closed = true end
			end)
			MarketplaceService:PromptProductPurchase(player, cfg.RestockProductId)
			local t0 = os.clock()
			while not closed and os.clock() - t0 < 60 and stock(stockId) <= 0 do task.wait(0.1) end
			c:Disconnect()
			local t1 = os.clock()
			while os.clock() - t1 < 3 and stock(stockId) <= 0 do task.wait(0.1) end
			if stock(stockId) > 0 then result = "bought" end
		else
			env.popText("Not on sale yet", 0.55, 1, Style.Color.Stop)
		end
		paused = false
	end))
	table.insert(conns, card.Skip.Button.Activated:Connect(function()
		if not paused then result = result or "skip" end
	end))
	local left = cfg.RestockSeconds
	while not result do
		local dt = RunService.Heartbeat:Wait()
		if stock(stockId) > 0 then
			result = "bought"
		elseif not paused then
			left -= dt
			card.Time.Fill.Size = UDim2.fromScale(math.max(0, left / cfg.RestockSeconds), 1)
			if left <= 0 then result = "skip" end
		end
	end
	for _, c in conns do c:Disconnect() end
	card.Visible = false
	busy = false
	if result == "bought" then
		env.sfx(env.SFX.Done, 0.9, 1.1)
		env.popText("RESTOCKED!", 0.8, 1, Style.Color.Cash)
		return true
	end
	return false
end

-- The card ran out: whoever needed the part goes home (onBench: the job on the bench goes too, it can't be
-- finished). Returns how many left, and whether the job on the bench was one of them.
function R.giveUp(stockId, onBench)
	local lost, dropped = env.remotes.GiveUpStock:InvokeServer(stockId, onBench == true)
	if (lost or 0) > 0 then
		env.popText(lost == 1 and "+1 customer lost today" or ("+%d customers lost today"):format(lost), 0.55, 1.4, Style.Color.Stop)
	end
	return lost or 0, dropped == true
end

return R
