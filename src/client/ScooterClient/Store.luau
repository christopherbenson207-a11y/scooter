-- The Robux store (owner, 24 Oct: "shop should be robux purchases"; plan/10-ROBUX-AND-OFFERS.md section 2).
-- FixUI.Store { Tabs { Featured, Passes, Cash, Extras }, List { RowTemplate } }, filled from Config.Store.
-- Buying asks the server (StoreBuy): an id of 0 is handed over free in Studio and says SOON live; products
-- and passes open Roblox's prompt. The menu ball and the + on the cash open it.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Style = require(game:GetService("ReplicatedStorage"):WaitForChild("UIStyle"))
local C = Style.Color

local player = Players.LocalPlayer
local Store = {}

local env, panel, config
local tab = "Featured"

local function inTab(item, name)
	if name == "Featured" then return item.Tab == "Featured" or item.Featured end
	return item.Tab == name
end

-- What the buy button says, and whether it can be pressed.
local function buyState(item)
	if item.Kind == "Pass" and player:GetAttribute("Pass_" .. item.Id) then return "OWNED", false end
	if item.Once and player:GetAttribute("StarterPack") then return "OWNED", false end
	local id = item.Kind == "Pass" and item.PassId or item.ProductId
	if (id or 0) == 0 and not RunService:IsStudio() then return "SOON", false end
	if (item.Id == "CallCustomer" or item.Id == "CallRare") and workspace:GetAttribute("Phase") ~= "Day" then return "DAYTIME", false end
	return "R$" .. item.Robux, true
end

local function describe(item)
	if item.Nights then
		local cash = item.Nights * config.nightCash(player:GetAttribute("Day") or 1)
		return ("$%s. About %d night%s of upgrades"):format(Style.money(cash), item.Nights, item.Nights == 1 and "" or "s")
	end
	return item.Desc or ""
end

-- a kit button's colour (Base is what its hover brightens)
local function paint(face, base)
	face:SetAttribute("Base", base)
	face.Gloss.Color = Style.glossColors(base)
end

local function render()
	if not panel then return end
	for _, b in panel.Tabs:GetChildren() do
		if b:IsA("Frame") and b:FindFirstChild("Button") then paint(b.Button, b.Name == tab and C.Teal or C.EnamelLine) end
	end
	for _, r in panel.List:GetChildren() do
		if r:IsA("Frame") and r.Name ~= "RowTemplate" then r:Destroy() end
	end
	local template = panel.List.RowTemplate
	for i, item in config.Store do
		if inTab(item, tab) then
			local r = template:Clone()
			r.Name = item.Id
			r.LayoutOrder = i
			r.Visible = true
			r.Icon.Image = Style.Icon[item.Icon] or ""
			r.Title.Text = item.Title
			r.Desc.Text = describe(item)
			if item.Tab == "Featured" then r.BackgroundColor3 = Style.tone(C.Gold, 0.45) end -- the starter pack stands out
			local text, can = buyState(item)
			r.Buy.Button.Label.Text = text
			paint(r.Buy.Button, can and C.Teal or C.EnamelLine)
			r.Buy:SetAttribute("Wired", nil) -- the template was wired at start; the copy gets its own press feel
			r.Buy.Button.Activated:Connect(function()
				if not select(2, buyState(item)) then return end
				local result = env.remotes.StoreBuy:InvokeServer(item.Id)
				if result == "granted" then
					env.sfx(env.SFX.Done, 0.8, 1.2)
					env.popText("Thanks! " .. item.Title)
				elseif result == "prompt" then
					MarketplaceService:PromptProductPurchase(player, item.ProductId)
				elseif result == "pass" then
					MarketplaceService:PromptGamePassPurchase(player, item.PassId)
				elseif result == "notnow" then
					env.popText("Not right now")
				elseif result ~= "owned" then
					env.popText("Coming soon")
				end
				render()
			end)
			r.Parent = panel.List
		end
	end
	panel.List.CanvasPosition = Vector2.zero
end

function Store.open(name)
	tab = name or tab
	render()
	panel.Visible = true
	env.popScale(panel, 0.85, 0.18)
end

function Store.close()
	panel.Visible = false
end

function Store.toggle()
	if panel.Visible then Store.close() else Store.open() end
end

function Store.start(e)
	env, config = e, e.config
	panel = e.gui:WaitForChild("Store")
	panel.Visible = false
	panel.Close.Button.Activated:Connect(Store.close)
	for _, b in panel.Tabs:GetChildren() do
		if b:IsA("Frame") and b:FindFirstChild("Button") then
			b.Button.Activated:Connect(function()
				tab = b.Name
				render()
			end)
		end
	end
	-- a pass or pack bought through Roblox's prompt shows as owned straight away
	player.AttributeChanged:Connect(function(name)
		if panel.Visible and (name == "StarterPack" or name:sub(1, 5) == "Pass_") then render() end
	end)
	workspace:GetAttributeChangedSignal("Phase"):Connect(function()
		if panel.Visible then render() end
	end)
	panel:GetPropertyChangedSignal("Visible"):Connect(function() e.setBusy(panel.Visible) end)
end

return Store
