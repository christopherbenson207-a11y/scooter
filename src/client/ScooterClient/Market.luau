-- Caro's night market panel. It is a copy of the garage shop frame (white kit panel, tab title, rows and
-- glossy buttons), so it reads as part of the same game; each row adds a stock count and the teal Robux
-- button when the item has a product (plan/10). Open it from the prompt on Caro's counter.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer

local Style = require(RS:WaitForChild("UIStyle"))
local C = Style.Color

local M = {}
local GREEN, AMBER, RED = C.Cash, Color3.fromRGB(214, 140, 20), C.Stop
local ROW_H = 84

local env, panel, list, template, timerLabel
local rows = {} -- [itemId] = its row frame
local itemOf = {} -- [itemId] = what the server last said about it (instances can't hold fields)
local visible = false

local function commas(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function counter()
	local van = workspace:FindFirstChild("CaroVan")
	return van and van:FindFirstChild("CaroCounter", true)
end

local function cash()
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls.Cash.Value or 0
end

local function spray(colourName)
	for _, p in env.config.SprayPaints do
		if p.Name == colourName then return p.Color end
	end
end

-- one row, built from the shop's own row so spacing, strokes and fonts match
local function makeRow(item)
	local row = template:Clone()
	row.Name = item.Id
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.Visible = true
	row.Icon.Image = item.Icon or ""
	row.Title.Position = UDim2.new(0, 76, 0, 6)
	row.Desc.Position = UDim2.new(0, 76, 0, 33)
	-- how many are left tonight, under the description
	local left = row.Desc:Clone()
	left.Name = "Left"
	left.Position = UDim2.new(0, 76, 0, 56)
	left.Parent = row
	-- cash on top, the teal Robux button under it (only for items with a Developer Product)
	row.Buy.Size = UDim2.fromOffset(128, 76)
	local cashBtn = row.Buy.Button
	cashBtn.Size = UDim2.new(1, 0, 0, 36)
	cashBtn.Position = UDim2.new(0, 0, 0, 0)
	local robux = cashBtn:Clone()
	robux.Name = "Robux"
	robux.Position = UDim2.new(0, 0, 0, 40)
	robux.Gloss.Color = Style.glossColors(C.Teal)
	robux.Parent = row.Buy
	row.Parent = list
	return row
end

local function toast(text, color)
	env.popText(text, 0.7, 1.2, color)
end

local function buy(item, row)
	local ok, why = env.remotes.BuyMarket:InvokeServer(item.Id)
	if ok then
		env.sfx(env.SFX.Done, 0.9, 1.1)
		local k = item.Kind
		toast(k == "Crate" and "STOCKED!" or k == "Marketer" and "BOOKED FOR TOMORROW!" or k == "Helper" and "MO IS HIRED!" or k == "Pack" and "GARAGE UPGRADED!" or k == "Can" and "NEW CAN ON YOUR RACK!" or "IT'S YOURS!", GREEN)
	else
		env.sfx(env.SFX.Tap, 0.8, 0.5)
		toast(why == "poor" and "Not enough cash!" or why == "soldout" and "Sold out!" or why == "owned" and "You already have it" or "Caro's closed", RED)
	end
end

local function render(view)
	local balance = cash()
	local seen = {}
	for i, item in view.Items do
		seen[item.Id] = true
		local row = rows[item.Id]
		if not row then
			row = makeRow(item)
			rows[item.Id] = row
			row.Buy.Button.Activated:Connect(function()
				buy(itemOf[item.Id] or item, row)
				M.refresh()
			end)
			row.Buy.Robux.Activated:Connect(function()
				local current = itemOf[item.Id]
				if current and current.Product > 0 then MarketplaceService:PromptProductPurchase(player, current.Product) end
			end)
		end
		itemOf[item.Id] = item
		row.LayoutOrder = i
		row.Title.Text = item.Title
		row.Desc.Text = item.Desc
		local icon = row.Icon
		icon.Image = item.Icon or ""
		icon.ImageColor3 = item.Colour and spray(item.Colour) or Color3.new(1, 1, 1)
		-- how many are left tonight, shared by everyone in the server
		if item.Left <= 0 then
			row.Left.Text = "Sold out tonight"
			row.Left.TextColor3 = RED
		else
			row.Left.Text = ("%d of %d left"):format(item.Left, item.Qty)
			row.Left.TextColor3 = item.Left == 1 and AMBER or Color3.fromRGB(60, 150, 70)
		end
		local btn = row.Buy.Button
		if item.Blocked then
			btn.Label.Text = item.Blocked
			btn.Gloss.Color = Style.glossColors(C.EnamelLine)
		else
			btn.Label.Text = "$" .. commas(item.Price)
			btn.Gloss.Color = Style.glossColors(balance >= item.Price and GREEN or C.EnamelLine)
		end
		-- Robux buys don't use tonight's stock: the button stays when the cash one says sold out (plan/10)
		local hasRobux = item.Product > 0 and item.Blocked ~= "OWNED" and item.Blocked ~= "MAX" and item.Blocked ~= "BOOKED"
		row.Buy.Robux.Visible = hasRobux
		if hasRobux then row.Buy.Robux.Label.Text = item.Robux and ("R$" .. item.Robux) or "Robux" end
		-- one button: it takes the full height
		btn.Size = UDim2.new(1, 0, 0, hasRobux and 36 or 50)
		row.Buy.Size = UDim2.fromOffset(128, hasRobux and 76 or 50)
	end
	for id, row in rows do
		if not seen[id] then row:Destroy() rows[id] = nil itemOf[id] = nil end
	end
end

function M.refresh()
	if not visible then return end
	local ok, view = pcall(function() return env.remotes.GetMarket:InvokeServer() end)
	if ok and view then
		if not view.Open then M.close() return end
		render(view)
	end
end

function M.open()
	if visible then return end
	local ok, view = pcall(function() return env.remotes.GetMarket:InvokeServer() end)
	if not (ok and view and view.Open) then toast("Caro's closed", RED) return end
	visible = true
	-- phones are short: the same panel, a row less tall (like the garage shop)
	local phone = Style.fitScale(workspace.CurrentCamera.ViewportSize) == 0.85
	panel.Size = UDim2.fromOffset(phone and 560 or 580, phone and 318 or 430)
	panel.Position = UDim2.fromScale(0.5, phone and 0.56 or 0.55)
	panel.Visible = true
	render(view)
	env.popScale(panel, 0.85, 0.25)
	env.sfx(env.SFX.Tap, 0.6, 1.2)
end

function M.close()
	if not visible then return end
	visible = false
	panel.Visible = false
end

-- env = { gui, popText, popScale, sfx, SFX, remotes, config }
function M.start(e)
	env = e
	panel = e.gui.Shop:Clone()
	panel.Name = "CaroMarket"
	panel.Visible = false
	list = panel.List
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") and c.Name ~= "RowTemplate" then c:Destroy() end
	end
	template = list.RowTemplate
	template.Visible = false
	-- Caro's own colour on the tab: teal (her van), a wider tab for her name
	panel.Title.Text = "CARO'S VAN"
	panel.Tab.Gloss.Color = Style.glossColors(C.Teal)
	panel.Tab.Size = UDim2.fromOffset(260, 48)
	panel.Title.Size = UDim2.fromOffset(260, 48)
	panel.Size = UDim2.fromOffset(580, 430)
	-- time left tonight, top left inside the panel (the close button has the right)
	timerLabel = template.Desc:Clone()
	timerLabel.Name = "Timer"
	timerLabel.Text = "until dawn"
	timerLabel.AnchorPoint = Vector2.new(0, 0)
	timerLabel.Position, timerLabel.Size = UDim2.new(0, 16, 0, 10), UDim2.fromOffset(150, 20)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Left
	timerLabel.TextColor3 = C.OnPanel
	timerLabel.ZIndex = 8
	timerLabel.Parent = panel
	panel.Parent = e.gui
	panel.Close.Button.Activated:Connect(function()
		e.sfx(e.SFX.Tap, 0.6, 0.8)
		M.close()
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if prompt.Name == "CaroShop" and who == player then M.open() end
	end)
	e.remotes.MarketChanged.OnClientEvent:Connect(function()
		M.refresh()
	end)
	-- the one-line announcement when the van parks
	e.remotes.MarketArrived.OnClientEvent:Connect(function(headline)
		e.popText(headline and ("Caro's here! " .. headline .. " in stock") or "Caro's here!", 0.75, 2.4, AMBER)
		e.sfx(e.SFX.Done, 0.7, 1.3)
	end)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats")
		ls:WaitForChild("Cash").Changed:Connect(function() M.refresh() end)
	end)
	RunService.Heartbeat:Connect(function()
		if not visible then return end
		local left = math.max(0, math.floor((workspace:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
		timerLabel.Text = ("until dawn  %d:%02d"):format(left // 60, left % 60)
		-- walk away from the counter and the panel closes
		local c, root = counter(), player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not c or not root or (c.Position - root.Position).Magnitude > 26 then M.close() end
	end)
end

return M
