-- All numbers for Fix My Scooter. Edit here, not in the scripts.
local C = {}

-- Scooter models customers bring in. Garage = the garage building's tier (1-4) that brings them.
-- Class = which group the director mixes (defaults to Garage); a model not yet in ReplicatedStorage.Scooters is skipped.
C.Scooters = {
	{ Name = "Pebble", Pay = 30, Garage = 1, MaxSpeed = 52 },
	{ Name = "City Folder", Pay = 30, Garage = 1, Class = 1, MaxSpeed = 54 }, -- kick class (blender/build_kick.py)
	{ Name = "Kiddo", Pay = 30, Garage = 1, Class = 1, MaxSpeed = 46 },
	{ Name = "Courier", Pay = 30, Garage = 1, Class = 1, MaxSpeed = 50 },
	{ Name = "Zippy", Pay = 60, Garage = 2, MaxSpeed = 62 },
	{ Name = "Bolt X", Pay = 120, Garage = 3, MaxSpeed = 74 },
}

-- Colourways a customer's scooter can come in. The server picks one per job;
-- chance = Weight / total of all weights (119 now, so Mint is ~8.4%, Neon Night ~0.4%).
-- Body = panels, Seat, Trim = metal bits, Rims = wheel rims (defaults to Trim).
-- Optional: Material for the body, Glow = neon trim and rims.
local rgb = Color3.fromRGB
C.Paints = {
	{ Name = "Mint", Weight = 10, Body = rgb(120, 220, 190), Seat = rgb(55, 50, 48), Trim = rgb(205, 210, 220) },
	{ Name = "Cherry", Weight = 10, Body = rgb(225, 60, 72), Seat = rgb(35, 35, 40), Trim = rgb(210, 212, 220) },
	{ Name = "Sky", Weight = 10, Body = rgb(90, 170, 250), Seat = rgb(245, 238, 225), Trim = rgb(220, 224, 232) },
	{ Name = "Lemon", Weight = 9, Body = rgb(255, 212, 70), Seat = rgb(45, 45, 50), Trim = rgb(60, 62, 70) },
	{ Name = "Snow", Weight = 9, Body = rgb(242, 242, 246), Seat = rgb(150, 95, 60), Trim = rgb(60, 62, 70) },
	{ Name = "Midnight", Weight = 9, Body = rgb(42, 46, 62), Seat = rgb(175, 115, 75), Trim = rgb(205, 210, 220) },
	{ Name = "Tangerine", Weight = 8, Body = rgb(255, 145, 55), Seat = rgb(40, 40, 45), Trim = rgb(210, 212, 220) },
	{ Name = "Lilac", Weight = 8, Body = rgb(185, 150, 240), Seat = rgb(245, 238, 225), Trim = rgb(220, 224, 232) },
	{ Name = "Bubblegum", Weight = 7, Body = rgb(255, 140, 190), Seat = rgb(255, 255, 255), Trim = rgb(220, 224, 232) },
	{ Name = "Forest", Weight = 7, Body = rgb(60, 135, 85), Seat = rgb(200, 165, 115), Trim = rgb(60, 62, 70) },
	{ Name = "Coral", Weight = 6, Body = rgb(255, 120, 100), Seat = rgb(55, 50, 48), Trim = rgb(220, 224, 232) },
	{ Name = "Teal", Weight = 6, Body = rgb(35, 165, 170), Seat = rgb(240, 235, 225), Trim = rgb(60, 62, 70) },
	{ Name = "Slate", Weight = 5, Body = rgb(110, 118, 135), Seat = rgb(200, 55, 55), Trim = rgb(40, 42, 48) },
	{ Name = "Cream", Weight = 5, Body = rgb(245, 230, 195), Seat = rgb(120, 78, 48), Trim = rgb(175, 140, 90) },
	{ Name = "Racing Red", Weight = 3, Body = rgb(205, 25, 35), Seat = rgb(25, 25, 28), Trim = rgb(245, 245, 245) },
	{ Name = "Police", Weight = 2.5, Body = rgb(28, 40, 75), Seat = rgb(240, 240, 245), Trim = rgb(240, 240, 245) },
	{ Name = "Camo", Weight = 2, Body = rgb(95, 110, 70), Seat = rgb(70, 58, 42), Trim = rgb(50, 52, 45) },
	{ Name = "Chrome", Weight = 1.2, Body = rgb(205, 212, 222), Material = Enum.Material.Metal, Seat = rgb(25, 25, 28), Trim = rgb(235, 238, 245) },
	{ Name = "Gold", Weight = 0.8, Body = rgb(240, 190, 60), Material = Enum.Material.Metal, Seat = rgb(40, 28, 22), Trim = rgb(255, 225, 130) },
	{ Name = "Neon Night", Weight = 0.5, Body = rgb(22, 22, 32), Seat = rgb(22, 22, 32), Trim = rgb(0, 255, 200), Glow = true },
}
C.Rubber = rgb(32, 33, 38) -- tyres, grips and the deck mat

-- What can be wrong with a scooter. Needs = shop item that unlocks the job type.
-- Par = seconds for a perfect (5 star) fix of this problem.
C.Problems = {
	Mud = { Label = "Muddy scooter", Pay = 40, Par = 36, Needs = "WashBay" }, -- includes the crane there and back (~5 s each way) and washing both sides
	Tyre = { Label = "Flat tyre", Pay = 15, Par = 13 }, -- includes walking to the floor pump
	Worn = { Label = "Worn-out tyre", Pay = 28, Par = 11, Needs = "TyreRack" },
	Charge = { Label = "Low battery", Pay = 18, Par = 8, Needs = "BatteryDock" },
	Paint = { Label = "Repaint", Pay = 60, Par = 24, Needs = "PaintBooth" }, -- includes the crane to the booth (~5 s) and looking round both sides
	Nitro = { Label = "Nitro boost", Pay = 85, Par = 11, Needs = "NitroKit" },
	Battery = { Label = "Dead battery", Pay = 25, Par = 6, Needs = "BatteryDock" }, -- tap it out, tap the holder: uses 1 battery
	Bolts = { Label = "Loose bolts", Pay = 30, Par = 8, Needs = "Wrench" },
	Light = { Label = "Broken light", Pay = 35, Par = 12, Needs = "WireKit" }, -- close-up, wiring box, dead bulb out, new bulb in
	Rust = { Label = "Rusty handlebar", Pay = 45, Par = 12, Trip = 10, Needs = "Bucket" }, -- in the wash bay; Trip = the crane there and back when no mud job takes it
}
C.ProblemOrder = { "Mud", "Rust", "Tyre", "Worn", "Charge", "Battery", "Bolts", "Light", "Nitro", "Paint" } -- order you fix them in (paint last: it goes to the booth)

-- Garage shop, in display order. Level items start at level 1 (first price is 0). Their Prices, Names and
-- per-level stats are made from C.Upgrades at the end of this file (upgrade system v5): level 1 = T1 with no
-- upgrades, level 11 = all 10 upgrades.
-- Starter = you own it from the start (not listed in the shop).
-- Look = how a machine shows its level until real models exist: Parts (part
-- names; Lua patterns, so "Leg%d*" matches Leg1, Leg2...) take Colors[level] (level 1 keeps the model's own colours when Colors[1] is
-- false), and the machine grows by Grow per level. Model = a machine that stands
-- in Workspace.Garage instead of being cloned from Stations (colour only).
local LV2, LV3, LV4 = rgb(70, 150, 240), rgb(170, 95, 250), rgb(255, 195, 60) -- blue, purple, gold
C.Shop = {
	{ Id = "Pump", Icon = "Pump", Kind = "Level", Desc = "More air every pump",
		Look = { Parts = { "Barrel" }, Colors = { false, LV2, LV3, LV4 }, Grow = 0.03 } }, -- each tier is the owner's own model (TierMin/TierMax in the template)
	-- Bigger green zone on the bolt; the needle also slows a little.
	{ Id = "Wrench", Icon = "Wrench", Kind = "Level", Desc = "Bigger green zone on bolts",
		Look = { Parts = { "Grip", "Head", "JawL", "JawR" }, Colors = { false, LV2, LV3, LV4 } } },
	-- The battery station: the rack (every tray of 6 you can see) and its charger (low-battery jobs: charges by
	-- itself at Rate per second, every spark you tap adds Spark). Plan/02 merged the old Charger into it.
	{ Id = "BatteryDock", Icon = "BatteryDock", Kind = "Level", Desc = "Holds more batteries, charges faster",
		Look = { Parts = { "RackBase", "Upright", "ChargerBase" }, Colors = { false, LV2, LV3, LV4 } } },
	-- Stock items are consumables: buy as often as you like, each adds Amount (up to
	-- what the rack holds; a part-filled pack costs its share).
	{ Id = "Batteries", Icon = "Battery", Kind = "Stock", Start = 6, Price = 40, Amount = 6, Holder = "BatteryDock", Title = "Battery Pack", Desc = "Fill up your battery rack" },
	-- More pay for every job, and a bigger parts bin (plan/02 merged the old Bin into it; T4 = the trash chute,
	-- no more trash runs). Its tier decides which machines you can buy (Gate on them).
	{ Id = "Bench", Icon = "Bench", Kind = "Level", Desc = "More pay for every fix, bigger bin; T2 and T4 add a bench slot",
		Look = { Model = "Bench", Parts = { "Mat", "BackLip", "Bin", "BinLip" }, Colors = { false, LV2, LV3, LV4 } } },
	-- More scooters can wait on the belt, and customers turn up more often.
	{ Id = "Belt", Icon = "Belt", Kind = "Level", Desc = "More customers waiting",
		Look = { Model = "Conveyor", Parts = { "Frame", "Rail%u?", "Leg%d*" }, Colors = { false, LV2, LV3, LV4 } } },
	-- Locked = you start without it (level 0); Prices[1] buys it. It comes with a full
	-- shelf of tyres, and every level adds a shelf you can see.
	{ Id = "TyreRack", Icon = "TyreRack", Kind = "Level", Locked = true, Gate = { Id = "Bench", Tier = 2 },
		Desc = "Worn-out tyre jobs; holds more tyres",
		Look = { Parts = { "Frame[LR]", "Rail%u%l+", "TopBar" }, Colors = { false, LV2, LV3, LV4 } } },
	{ Id = "Tyres", Icon = "Tyre", Kind = "Stock", Start = 4, Price = 48, Amount = 4, Holder = "TyreRack", Title = "Tyre Pack", Desc = "Fill up your tyre rack" },
	-- Paint cans on the booth's rack: each repaint uses one can-load (the booth's
	-- level decides how many loads a can holds). Bought one colour at a time.
	{ Id = "PaintRed", Icon = "PaintCan", Kind = "Stock", Start = 4, Price = 25, Amount = 4, Holder = "PaintBooth", Title = "Cherry Red paint", Desc = "Refill the red can" },
	{ Id = "PaintBlue", Icon = "PaintBlue", Kind = "Stock", Start = 4, Price = 25, Amount = 4, Holder = "PaintBooth", Title = "Sky Blue paint", Desc = "Refill the blue can" },
	{ Id = "PaintYellow", Icon = "PaintYellow", Kind = "Stock", Start = 4, Price = 25, Amount = 4, Holder = "PaintBooth", Title = "Sunny Yellow paint", Desc = "Refill the yellow can" },
	{ Id = "Garage", Kind = "Level", Desc = "Fancier scooters, more customers" },
	-- The wire kit box comes with a tray of 4 bulbs; the Pro kit adds a second tray.
	{ Id = "WireKit", Icon = "Wires", Kind = "Level", Locked = true, Gate = { Id = "Bench", Tier = 2 },
		Desc = "Broken light jobs; holds more bulbs",
		Look = { Parts = { "Box", "Lid" }, Colors = { false, LV2, LV3, LV4 } } },
	{ Id = "Bulbs", Icon = "Bulb", Kind = "Stock", Start = 4, Price = 20, Amount = 4, Holder = "WireKit", Title = "Bulb Pack", Desc = "Fill up your bulb box" },
	-- Scrub = how much each stroke cleans (and how big the sponge is). It stands in the
	-- wash bay, so Needs = you have to own the wash bay first.
	{ Id = "Bucket", Icon = "Bucket", Kind = "Level", Locked = true, Needs = "WashBay", Gate = { Id = "Bench", Tier = 3 },
		Desc = "Rust jobs in the wash bay; bigger sponge",
		Look = { Parts = { "Pail", "Rim" }, Colors = { false, LV2, LV3, LV4 } } },
	-- The paint booth room (front-left of the garage): repaint jobs happen in there and
	-- the scooter dries while you work on the next one. Dry = seconds to dry, Spray =
	-- how fast the spray covers a panel. One scooter in the booth at a time.
	-- The wash bay (front-right of the garage): muddy scooters get washed in there first.
	-- Jet = how wide and strong the pressure washer is.
	-- The wash room opens with the Big Garage (Garage T2), the paint room at garage upgrade 3 (plan/02).
	{ Id = "WashBay", Kind = "Level", Locked = true, Gate = { Id = "Garage", Tier = 2 },
		Desc = "Muddy scooter jobs; stronger jet",
		Look = { Parts = { "Post", "Header" }, Colors = { false, LV2, LV3, LV4 } } },
	{ Id = "PaintBooth", Icon = "PaintBooth", Kind = "Level", Locked = true, Gate = { Id = "Garage", Level = 4 },
		Desc = "Repaint jobs; dries faster",
		Look = { Parts = { "Post", "Header" }, Colors = { false, LV2, LV3, LV4 } } },
	-- Zone = width of the green band on the kit's gauge; Fill = gauge per second while you hold.
	{ Id = "NitroKit", Icon = "Nitro", Kind = "Level", Locked = true, Gate = { Id = "Bench", Tier = 3 },
		Desc = "Nitro boost jobs; easier to fill",
		Look = { Parts = { "Crate" }, Colors = { false, LV2, LV3, LV4 } } },
}

-- Colours customers can ask for in a repaint. Can = the rack can that holds it
-- (Stock = its shop refill). Special colours aren't on the rack: when a customer
-- wants one you buy it for that job (PaintProductId, 10 Robux) or paint another
-- colour and make them unhappy (fewer stars, half the repair pay).
C.SprayPaints = {
	{ Name = "Cherry Red", Color = rgb(225, 60, 72), Can = "Can1", Stock = "PaintRed" },
	{ Name = "Sky Blue", Color = rgb(90, 170, 250), Can = "Can2", Stock = "PaintBlue" },
	{ Name = "Sunny Yellow", Color = rgb(255, 212, 70), Can = "Can3", Stock = "PaintYellow" },
	{ Name = "Galaxy Purple", Color = rgb(120, 60, 200), Special = true },
	{ Name = "Lime Zest", Color = rgb(150, 230, 70), Special = true },
	{ Name = "Hot Pink", Color = rgb(255, 90, 180), Special = true },
	{ Name = "Midnight Black", Color = rgb(30, 32, 40), Special = true },
}
C.SpecialPaintChance = 0.25 -- how often a repaint asks for a special colour
C.PaintProductId = 0 -- Developer Product (10 Robux) for one special colour. 0 = not set up yet (Studio gives it free)
C.RejectProductId = 0 -- Developer Product for sending a waiting customer away (the X on their card). 0 = not set up yet (Studio does it free)
C.WrongPaint = { Stars = 2, Pay = 0.5 } -- painting the wrong colour: this many stars off, repair pay x this

-- Out of stock (owner, 24 Oct): batteries, tyres, bulbs and paint are bought with cash at the upgrade stand
-- at night. Run out in the day and a card offers a full restock for RestockRobux; after RestockSeconds it
-- goes, and every customer whose job needs that part leaves (no bad review). Until you restock, nobody
-- brings a job that needs it.
C.RestockProductId = 0 -- Developer Product (10 Robux) "Restock". 0 = not set up yet (Studio restocks free)
C.RescueProductId = 0 -- Developer Product (24 Robux) "Keep them waiting" (the walk-out rescue). 0 = Studio grants free
C.Offers = { RescuePrice = 24, RescueSeconds = 10, RescueCooldown = 180, TopUpCooldown = 300 } -- context offers (plan/12)
C.RestockRobux = 10
C.RestockSeconds = 5
C.StockFor = { Battery = "Batteries", Worn = "Tyres", Light = "Bulbs" } -- fix -> the stock it uses up
-- The stock ids a job needs (a repaint needs its rack colour's can; special colours are bought per job).
function C.stockNeeds(job)
	local list = {}
	for _, name in job.Problems or {} do
		if C.StockFor[name] then table.insert(list, C.StockFor[name]) end
		if name == "Paint" and job.PaintTo then
			for _, p in C.SprayPaints do
				if p.Name == job.PaintTo and p.Stock then table.insert(list, p.Stock) end
			end
		end
	end
	return list
end

-- The Robux store (plan/10; owner, 24 Oct: "shop should be robux purchases"). The menu ball and the + on the
-- cash open it; upgrades are at the stand in the garage. Ids are the owner's to create: 0 = not set up yet
-- (live: the button says SOON; Studio hands it over free so it can be tested). Robux = the price shown
-- (set the same price on the product). Tab: Featured / Passes / Cash / Extras.
C.Store = {
	{ Id = "Starter", Tab = "Featured", Kind = "Product", ProductId = 0, Robux = 49, Icon = "Shop", Title = "Starter Pack", Desc = "$1,500, a Golden Wrench and a rare paint can", Once = true },
	{ Id = "Cash2x", Tab = "Passes", Kind = "Pass", PassId = 0, Robux = 199, Icon = "Cash", Title = "2x Cash", Desc = "Every job pays double, for good", Featured = true },
	{ Id = "VIP", Tab = "Passes", Kind = "Pass", PassId = 0, Robux = 299, Icon = "Star", Title = "VIP", Desc = "+20% tips and a gold name on your garage" },
	{ Id = "CashS", Tab = "Cash", Kind = "Product", ProductId = 0, Robux = 25, Icon = "Coin", Title = "Pile of cash", Nights = 1 },
	{ Id = "CashM", Tab = "Cash", Kind = "Product", ProductId = 0, Robux = 99, Icon = "Coin", Title = "Bag of cash", Nights = 5, Featured = true },
	{ Id = "CashL", Tab = "Cash", Kind = "Product", ProductId = 0, Robux = 249, Icon = "Cash", Title = "Case of cash", Nights = 14 },
	{ Id = "CashXL", Tab = "Cash", Kind = "Product", ProductId = 0, Robux = 499, Icon = "Cash", Title = "Vault of cash", Nights = 30 },
	{ Id = "CallCustomer", Tab = "Extras", Kind = "Product", ProductId = 0, Robux = 9, Icon = "Timer", Title = "Call a customer", Desc = "Someone comes right now (daytime)" },
	{ Id = "CallRare", Tab = "Extras", Kind = "Product", ProductId = 0, Robux = 29, Icon = "Star", Title = "Call a rare customer", Desc = "A Rare or better scooter, right now (daytime)" },
}
C.StoreTabs = { "Featured", "Passes", "Cash", "Extras" }
C.StarterCash = 1500
C.VipTips = 1.2 -- VIP: paint and ride tips x this
-- Cash packs scale with how far you are: one "night" is about what a night of upgrades costs on your day.
function C.nightCash(day)
	return 300 + 200 * (math.clamp(day or 1, 1, 30) - 1)
end

-- Skill (owner, 24 Oct: "fun but also punishing and rewarding, lenient too"). Timing minigames call every
-- tap PERFECT (the gold middle of the green), GOOD (the rest of the green) or MISS. Every perfect adds
-- SkillPerfect x the repair pay (up to SkillMax) and builds a combo; a miss breaks the combo and adds
-- MissSeconds to the job's time, so the stars drop sooner. After MissHelp misses on one bolt the green
-- grows back, so nobody gets stuck.
C.SkillPerfect = 0.06
C.SkillMax = 0.4
C.MissSeconds = 2
C.MissHelp = 3
-- How well it was painted (coverage minus runs): the badge over the scooter, its paint
-- drops, and a tip on top of the repair pay (x repair pay). Best first.
C.PaintGrades = {
	{ Min = 0.95, Name = "EXCELLENT WORK!", Drops = 3, Tip = 0.3, Color = rgb(255, 205, 60) },
	{ Min = 0.85, Name = "GREAT WORK!", Drops = 2, Tip = 0.15, Color = rgb(110, 215, 110) },
	{ Min = 0.7, Name = "GOOD WORK", Drops = 1, Tip = 0.05, Color = rgb(110, 185, 250) },
	{ Min = 0, Name = "POOR WORK", Drops = 0, Tip = 0, Color = rgb(225, 95, 85) },
}

-- Pumping: hold to push the handle down, let go and it springs back up.
-- Air only goes in on the way down, so a full press is a full stroke and a
-- quick tap is a small top-up.
-- C.PumpAir (% pressure per full stroke) and C.PumpStroke (seconds for a full push down) by Pump level are
-- made from C.Upgrades.Pump at the end of this file.
C.PumpReturn = 0.28 -- seconds for the handle to spring back up
C.PumpLeak = 3 -- % pressure lost per second
C.PumpHold = 0.8 -- seconds in the green band to finish

-- Timer: you keep 5 stars up to Par, then lose one at each of these multiples of Par.
C.StarSteps = { 1.15, 1.5, 1.9, 2.4 } -- Fever tuning: a little slack past par before each star drops (plan/12)
C.StarPay = { 1.0, 1.1, 1.25, 1.4, 1.6 } -- pay multiplier for 1..5 stars
C.StreakStep = 0.1 -- each perfect in a row adds +10% (from the 2nd perfect)
C.StreakMax = 0.5

-- Fever loop (plan/12): CF-style pacing
C.StepPay = 0.55 -- each finished fix pays this fraction of its pay on the spot (FinishJob pays the rest)
C.SpeedTip = { Max = 0.2, TillPar = 1.0, Gone = 2.5 } -- a tip on the repair pay: full at par, gone by 2.5x par
C.DayGoals = { Low = 0.8, Med = 1.1, High = 1.45 } -- today's cash goal in nightCash units: 1/2/3 stars + a dawn chest
C.ParallelBench = { Tier2 = 2, Tier4 = 3 } -- how many jobs can be in flight at once, by bench tier (plan/12)
-- Chains (plan/13, Diner Dash's chain bonus): the same fix twice or more in a row, on any jobs, pays each
-- link's step pay x (1 + Step per link after the first), up to +Max. A different fix starts a new chain.
-- The belt shows every scooter's fixes, so lining up four flat tyres is a plan, not luck.
C.Chain = { Step = 0.25, Max = 0.75 }
-- Background charging (plan/13, CF's grill): plug a low battery in and carry on with the scooter's other
-- fixes; it fills at the dock's Rate by itself and pays the moment it's full. With nothing else to do on
-- that scooter you tap sparks as before.
C.ChargeInBackground = true

-- The shop runs in days. When a day ends no new customers come; finish the ones
-- waiting, take the trash out to the dumpster and the next day starts.
-- One clock for the whole server: everyone shares day and night (workspace attributes Phase and PhaseEndsAt).
C.DaySeconds = 360 -- garages are open and customers arrive
C.NightSeconds = 150 -- no new customers; finish who's waiting, bag the trash, upgrade
-- Caro's night market: her van parks in the plaza every night and leaves at dawn. What she sells is
-- rolled once per night for the whole server (Chance = how likely the item is tonight), and the stock is
-- shared by everyone: first come, first served. Product = a Robux Developer Product id (0 = not set up yet,
-- the Robux button stays hidden). Prices are cash; the permanents are saved with the player.
C.Caro = {
	MinItems = 3, -- if the rolls give fewer, crates fill the shelf
	CanLoads = 8, -- a rare paint can holds this many sprays
	RefillCan = 40, -- cash to refill an empty rare can at the booth
	CrateOverCap = 1.5, -- crates may fill a rack up to this multiple of its normal capacity
	PackPay = 0.1, -- each Garage Upgrade Pack adds this much to every job's pay
	LookTiers = 3, -- Small / Big / Mega garage look (the look itself comes in phase F)
	Boost = { GoldenWrench = 1.25, ChromePump = 1.2, NeonCharger = 1.25, TurboLance = 1.25 }, -- on top of the shop levels
	Items = {
		-- plan/12 (see the design note): crates first — everyone understands "restock"; the Mystery Crate
		-- is CF's mystery box (its native code has CAutomaticBoxOdds and its daily calendar hands out
		-- SmallBoxes) — a cheap, exciting pull that teaches the market's job; exclusives come last.
		{ Id = "BatteryCrate", Kind = "Crate", Icon = "rbxassetid://138570434434474", Stock = "Batteries", Amount = 12, Title = "Battery crate", Desc = "12 batteries for your rack", Chance = 0.90, Qty = 10, Price = 150, Product = 0, Robux = 9 },
		{ Id = "TyreCrate", Kind = "Crate", Icon = "rbxassetid://132545507695166", Stock = "Tyres", Amount = 8, Title = "Tyre crate", Desc = "8 tyres for your rack", Chance = 0.70, Qty = 10, Price = 200, Product = 0, Robux = 9 },
		{ Id = "MysteryBox", Kind = "Mystery", Icon = "rbxassetid://132192590966199", Title = "Mystery Crate", Desc = "One random rare inside. No refunds, no regrets.", Chance = 0.45, Qty = 2, Price = 2500, Rare = true, Product = 0, Robux = 0 },
		{ Id = "RareCan", Kind = "Can", Icon = "rbxassetid://77877862136147", Title = "Rare paint can", Desc = "A can for your booth rack that never runs out of the colour", Chance = 0.40, Qty = 3, Price = 6000, Rare = true, Product = 0, Robux = 29 },
		{ Id = "Pack", Kind = "Pack", Icon = "rbxassetid://100853534545540", Title = "Garage Upgrade Pack", Desc = "A fancier garage and 10% more pay", Chance = 0.25, Qty = 2, Price = 40000, Product = 0, Rare = true, Robux = 99 },
		-- plan/13, CF's pre-level boosters: a Boost is booked at night and works all of tomorrow (Attr is set
		-- at dawn; the effect is read where it applies, e.g. Coffee in makeJob). Cheap, so it's a real choice
		-- every night rather than a rare.
		{ Id = "Coffee", Kind = "Boost", Attr = "Coffee", Icon = "rbxassetid://75647735250742", Title = "Free coffee", Desc = "Tomorrow, customers wait 35% longer", Chance = 0.55, Qty = 4, Price = 350, Product = 0, Robux = 0 },
		{ Id = "Marketer", Kind = "Marketer", Icon = "rbxassetid://127703785941799", Title = "Marketer", Desc = "Tomorrow, customers pick your garage 60% more", Chance = 0.20, Qty = 1, Price = 25000, Product = 0, Rare = true, Robux = 19 },
		{ Id = "Helper", Kind = "Helper", Icon = "rbxassetid://119114328487433", Title = "Helper Mo", Desc = "Fixes scooters while you're away", Chance = 0.12, Qty = 1, Price = 50000, Product = 0, Rare = true, Robux = 299 },
		{ Id = "GoldenWrench", Kind = "Tool", Icon = "rbxassetid://71441819598102", Attr = "GoldenWrench", Title = "Golden Wrench", Desc = "Bolt zone 25% bigger, on top of your wrench", Chance = 0.10, Qty = 1, Price = 12000, Rare = true, Product = 0, Robux = 49 },
		{ Id = "ChromePump", Kind = "Tool", Icon = "rbxassetid://97099931712591", Attr = "ChromePump", Title = "Chrome Pump", Desc = "20% more air with every stroke", Chance = 0.10, Qty = 1, Price = 12000, Rare = true, Product = 0, Robux = 49 },
		{ Id = "NeonCharger", Kind = "Tool", Icon = "rbxassetid://74089628511043", Attr = "NeonCharger", Title = "Neon Charger", Desc = "25% more charge from every spark", Chance = 0.10, Qty = 1, Price = 12000, Rare = true, Product = 0, Robux = 49 },
		{ Id = "TurboLance", Kind = "Tool", Icon = "rbxassetid://126190682804664", Attr = "TurboLance", Title = "Turbo Lance", Desc = "Washes mud 25% harder", Chance = 0.10, Qty = 1, Price = 12000, Rare = true, Product = 0, Robux = 49 },
	},
}
-- Customers choose a garage by its stars: weight = (0.35 + rating / 5) ^ 2 (no reviews yet counts as 3.5 stars).
C.UnratedAs = 3.5
C.MarketerBoost = 1.6 -- a garage with an active Marketer (Caro's market, later)
C.CoffeePatience = 1.35 -- Caro's Free coffee booster: customers' patience x this for a day
C.NewGarageBoost = 1.5 -- a player's first day: a few extra customers while they learn
C.WalkSpeed = 14 -- studs per second customers walk (with ScooterCrowd.WalkIn, how long they take to reach you)
C.DayLength = 300 -- seconds the shop is open each day (shop/ride time doesn't count)

-- Scooters waiting on the belt (plus the one on the bench): see Belt in C.Shop.
C.ArrivalGap = { 12, 20 } -- seconds between customers arriving (random in this range; Belt level shortens it)
C.FirstArrival = 2 -- first customer comes this long after your own scooter is fixed
C.EmptyArrival = 3 -- if nobody is waiting when you finish, the next one comes this soon
-- How long a waiting customer stays before walking off: depends on who they are,
-- plus extra time for every fix their scooter needs. Their clocks never stop (Fever rule,
-- plan/12): not in the shop, not on a test ride.
-- Fever pacing (plan/13): at 120-240 s nobody ever walked out, so waiting had no stakes. These are about
-- Cooking Fever's feel for a garage (a one-fix job's owner waits ~1.5-2 min, a big job's ~3), and the
-- first days are softer while you learn (PatienceByDay, the last entry holds from then on).
C.Personalities = {
	{ Name = "Chill", Patience = 110 },
	{ Name = "Normal", Patience = 85 },
	{ Name = "Rushed", Patience = 60 },
}
C.PatiencePerFix = 20 -- (old rule, kept for reference; patience now grows with the job's par)
C.PatiencePerPar = 1.8 -- + 1.8 s of patience for every second of par, so a big job doesn't make them cross
C.PatienceByDay = { 1.6, 1.3, 1.1, 1.0 }
-- "Hang on!" (plan/06): shows when a waiting customer is down to Below of their patience; every waiting customer
-- gets Back of their patience back, once each, then the button rests Cooldown seconds.
C.HangOn = { Below = 0.3, Back = 0.25, Cooldown = 45 }
-- Lunch rush (24 Oct): once a day, somewhere between From and To of the day, for Seconds, customers come Rate
-- times as often and pay Pay times more. Every garage gets busy at once.
C.LunchRush = { From = 0.35, To = 0.65, Seconds = 60, Rate = 2.5, Pay = 1.25 }
-- They walk out after this many times their patience (1.0 = the moment it's gone) and leave a bad review.
-- Stars still only count from when you pick the job; a picked job's clock keeps running even while parked.
C.LeaveAfter = 1.0 -- Fever rule: when their patience is gone, they take their scooter and go (plan/12)
C.WalkOutReview = 1 -- a customer who walks out leaves this many stars on your rating
C.FixCountWeights = { 50, 35, 15 } -- (fallback only) chance of a job needing 1, 2 or 3 fixes

-- Job stories: what happened to the scooter decides which fixes go together.
-- Fixes = always needed, Extra = each one 50% (if you have the machine and it fits).
-- A story only comes up once you own every machine its Fixes need. Wear = how
-- weathered it looks when it arrives (0-1, default grows with the fix count);
-- Pay = pay multiplier. The job card shows the story's name.
C.Stories = {
	-- Line = what the customer says when they drop it off; Thanks = when they get it back.
	{ Name = "Flat Out", Fixes = { "Tyre" }, Weight = 6, Line = "It just went pssssh!", Thanks = "Bouncy again!" },
	{ Name = "Battery Swap", Fixes = { "Battery" }, Weight = 5, Line = "It smells like burnt toast.", Thanks = "No more smoke!" },
	{ Name = "Low on Juice", Fixes = { "Charge" }, Weight = 5, Line = "Forgot to charge it. Again.", Thanks = "Full power!" },
	{ Name = "Rattly Ride", Fixes = { "Bolts" }, Weight = 4, Line = "It sounds like a drawer of spoons.", Thanks = "So quiet!" },
	{ Name = "Commuter Special", Fixes = { "Charge", "Tyre" }, Weight = 5, Line = "Gotta be at work in ten!", Thanks = "Made it! Maybe." },
	{ Name = "Pothole Crash", Fixes = { "Tyre", "Bolts" }, Extra = { "Light" }, Weight = 6, Line = "Hit a pothole the size of a pool!", Thanks = "Never riding that street again." },
	{ Name = "Dead in a Ditch", Fixes = { "Battery", "Bolts" }, Extra = { "Tyre" }, Weight = 4, Line = "Don't ask how it got in the ditch.", Thanks = "Our secret, yeah?" },
	{ Name = "Night Rider", Fixes = { "Light", "Charge" }, Weight = 4, Line = "I ride at night. In the dark. Help.", Thanks = "I can SEE!" },
	{ Name = "Left in the Rain", Fixes = { "Rust", "Battery" }, Extra = { "Light" }, Weight = 5, Wear = 0.9, Line = "Left it outside. For a month.", Thanks = "Never again. Probably." },
	{ Name = "Bald Tyres", Fixes = { "Worn" }, Extra = { "Bolts" }, Weight = 4, Line = "Is it meant to be this smooth?", Thanks = "Grippy!" },
	{ Name = "Wobbly Wheels", Fixes = { "Worn", "Bolts" }, Extra = { "Tyre" }, Weight = 3, Line = "It wobbles like jelly.", Thanks = "Steady as a rock!" },
	{ Name = "Fresh Look", Fixes = { "Paint" }, Extra = { "Rust" }, Weight = 3, Line = "Make it pop!", Thanks = "It POPS!" },
	{ Name = "Muddy Puddles", Fixes = { "Mud" }, Weight = 4, Line = "I may have jumped in every puddle.", Thanks = "Shiny!" },
	{ Name = "Off-Road Fun", Fixes = { "Mud", "Tyre" }, Extra = { "Bolts" }, Weight = 4, Wear = 0.7, Line = "Scooters can go off-road, right?", Thanks = "Doing it again tomorrow!" },
	{ Name = "Festival Weekend", Fixes = { "Mud", "Light" }, Extra = { "Charge" }, Weight = 3, Line = "Best. Weekend. Ever. Sorry about the mud.", Thanks = "Ready for next year!" },
	{ Name = "Old Banger", Fixes = { "Rust", "Worn", "Paint" }, Extra = { "Light", "Mud" }, Weight = 3, Wear = 1, Pay = 1.15, Line = "It was my dad's. And his dad's.", Thanks = "Grandad would cry!" },
	{ Name = "Speed Freak", Fixes = { "Nitro", "Bolts" }, Extra = { "Worn" }, Weight = 3, Pay = 1.2, Line = "Faster. FASTER.", Thanks = "ZOOOM!" },
	{ Name = "Race Day", Fixes = { "Nitro", "Worn", "Charge" }, Weight = 2, Pay = 1.25, Line = "Race starts in an hour!", Thanks = "Trophy's mine!" },
	{ Name = "Barn Find", Fixes = { "Rust", "Worn", "Battery", "Light", "Paint" }, Extra = { "Mud" }, Weight = 1, Wear = 1, Pay = 1.5, Line = "Found it in grandad's barn!", Thanks = "It's a CLASSIC now!" },
	-- more pairs, so most two-fix mixes come with a reason
	{ Name = "Kerb Kisser", Fixes = { "Light", "Bolts" }, Weight = 4, Line = "Clipped a kerb. Twice.", Thanks = "I'll steer this time." },
	{ Name = "Puddle Splash", Fixes = { "Mud", "Battery" }, Weight = 3, Line = "Rode through a puddle. It went dark.", Thanks = "It lives!" },
	{ Name = "Spring Clean", Fixes = { "Rust", "Mud" }, Weight = 3, Wear = 0.8, Line = "It's been in the shed all winter.", Thanks = "Spring is here!" },
	{ Name = "Glow Up", Fixes = { "Paint", "Light" }, Weight = 3, Line = "Make it pretty AND bright.", Thanks = "Main character energy!" },
	{ Name = "Birthday Present", Fixes = { "Paint", "Tyre" }, Weight = 3, Pay = 1.1, Line = "It's for my kid's birthday. Shhh!", Thanks = "They're gonna love it!" },
	{ Name = "Pizza Shift", Fixes = { "Battery", "Light" }, Weight = 4, Line = "No light, no battery, no pizza.", Thanks = "Pizza for everyone!" },
	{ Name = "Showroom Ready", Fixes = { "Mud", "Paint" }, Weight = 2, Pay = 1.15, Line = "Selling it tomorrow. Make it shine!", Thanks = "I might keep it now..." },
	{ Name = "Rusty Rattler", Fixes = { "Rust", "Bolts" }, Weight = 3, Wear = 0.8, Line = "It squeaks AND rattles.", Thanks = "Silence. Beautiful." },
	{ Name = "Coast Trip", Fixes = { "Charge", "Worn" }, Weight = 3, Line = "Riding to the seaside!", Thanks = "Sandcastles, here I come!" },
	{ Name = "Street Legal", Fixes = { "Nitro", "Light" }, Weight = 2, Pay = 1.2, Line = "If it's this fast it needs lights.", Thanks = "Fast AND legal!" },
	{ Name = "Flame Job", Fixes = { "Nitro", "Paint" }, Weight = 2, Pay = 1.25, Line = "Make it look as fast as it goes.", Thanks = "It looks illegal. Love it." },
	{ Name = "Swamp Monster", Fixes = { "Mud", "Worn", "Rust" }, Weight = 2, Wear = 0.9, Pay = 1.15, Line = "Took a shortcut. Through a swamp.", Thanks = "It's not a monster anymore!" },
	{ Name = "Tyre Trouble", Fixes = { "Tyre", "Worn" }, Weight = 4, Line = "One's flat, one's bald. Classic.", Thanks = "Two new shoes!" },
	{ Name = "Seaside Special", Fixes = { "Light", "Rust" }, Weight = 3, Wear = 0.7, Line = "Parked it by the sea. Bad idea.", Thanks = "Salt-free!" },
	{ Name = "Nan's Scooter", Fixes = { "Rust", "Charge", "Paint" }, Weight = 2, Wear = 0.8, Pay = 1.2, Line = "My nan rides this every day. Be gentle.", Thanks = "Nan's gonna be so fast now." },
	{ Name = "Grand Tour", Fixes = { "Charge", "Bolts", "Worn" }, Extra = { "Light" }, Weight = 2, Pay = 1.1, Line = "Riding across the whole country!", Thanks = "Postcards incoming!" },
	{ Name = "Stunt Show", Fixes = { "Bolts", "Tyre", "Nitro" }, Weight = 1, Pay = 1.3, Line = "I do flips. Mostly on purpose.", Thanks = "Watch THIS!" },
}
-- How many fixes a job can need, by day (day 1 is gentle, then it builds up).
C.MaxFixesByDay = { 2, 3, 3, 4, 5 }
-- Some customers add a twist. Rush: less patience, more pay. Picky: stars drop
-- faster (Par x0.75), more pay. VIP (about one a day): a gold outline and a crown,
-- big pay, less patience. Shown on the job card and in the customer's bubble.
C.Moods = {
	{ Name = "Rush", Chance = 0.12, Patience = 0.6, Pay = 1.5 },
	{ Name = "Picky", Chance = 0.08, Par = 0.75, Pay = 1.4 },
	{ Name = "VIP", Chance = 0.05, Patience = 0.75, Pay = 2.5 },
}
C.FreshJobs = 3 -- after you unlock a job type, the next this-many jobs include it

-- The job director (plan/11 section 3, ScooterServer.Director): each player's day is planned from what the
-- server knows about them. A day deals Warm-up -> Show-off -> Core (with one Practice) -> Big at the lunch rush
-- -> Cool-down at the end of the day. Inside a slot it's still a little random.
C.Director = {
	Deck = { Base = 8, PerBelt = 2, GoodRating = 4, PerGoodRating = 2, Max = 14 }, -- slots planned per day
	Fresh = 1, FreshCap = 12, Overdue = 15, -- score per job since a fix last came up (capped); + Overdue after 2 days unseen
	Top = 4, -- a slot picks from the best this-many stories
	LowStock = 2, LowStockScore = 0.4, -- 1-2 parts left: stories that use them score this much
	PracticeMin = 2, PracticeRatio = 1.25, PracticePatience = 1.3, -- your weakest fix (time / par) after 2 tries, once a day
	ShowOffJobs = 2, -- jobs that use what you just bought
	ShowOff = { -- the machine you bought -> the fixes that show it off
		Pump = { "Tyre" }, Wrench = { "Bolts" }, BatteryDock = { "Battery", "Charge" },
		TyreRack = { "Worn" }, WireKit = { "Light" }, Bucket = { "Rust" }, WashBay = { "Mud" },
		PaintBooth = { "Paint" }, NitroKit = { "Nitro" },
	},
	BigPerDay = 2, -- Big jobs (the most fixes today allows) during the lunch rush
	CoolAt = 45, -- seconds of daylight left: from here on jobs are short and easy
	ClassMix = { 0.5, 0.35, 0.15 }, -- your newest scooter class, the one below, all older ones
	Pity = { 12, 40, 120 }, -- jobs without a Rare / Epic / Legendary before one is guaranteed
	StruggleStars = 2, StruggleRed = 0.2, SlowArrivals = 0.7, -- struggling: a quick job next, fewer arrivals
	FlyingPay = 1.15, -- flying: the next core job gets one more fix and pays this much more
	Behind = 0.6, GuardRarity = 1.6, GuardPay = 1.1, -- well under today's target: more Uncommon/Rare, more pay
	MoodsFromDay = 3, RaresFromDay = 3, -- days 1-2: no moods, nothing rarer than Uncommon
	-- The first 3 days are scripted (after your own flat tyre). Fixes = exactly these; Count = a job with this
	-- many fixes; Rarity = at least this rarity (index); Mood = this mood. A step you can't do yet is skipped.
	FirstDays = {
		{ { Fixes = { "Tyre" } }, { Fixes = { "Battery" } }, { Fixes = { "Bolts" } }, { Count = 2 } },
		{ { Fixes = { "Charge" } }, { Rarity = 2 } },
		{ { Mood = "Rush" }, { Count = 3 } },
	},
}

-- Rarity: rolled per job. Rarer scooters pay more and look special.
-- Glow = the shiny highlight on the parts you need to work on.
C.Rarities = {
	{ Name = "Common", Weight = 60, Pay = 1.0, Color = Color3.fromRGB(200, 202, 215), Glow = Color3.fromRGB(255, 220, 80) },
	{ Name = "Uncommon", Weight = 25, Pay = 1.3, Color = Color3.fromRGB(110, 215, 120), Glow = Color3.fromRGB(90, 255, 120) },
	{ Name = "Rare", Weight = 10, Pay = 1.8, Color = Color3.fromRGB(80, 165, 255), Glow = Color3.fromRGB(70, 170, 255) },
	{ Name = "Epic", Weight = 4, Pay = 2.6, Color = Color3.fromRGB(185, 105, 255), Glow = Color3.fromRGB(200, 110, 255) },
	{ Name = "Legendary", Weight = 1, Pay = 4.0, Color = Color3.fromRGB(255, 200, 60), Glow = Color3.fromRGB(255, 160, 40) },
}
C.RatingReviews = 20 -- the garage's star rating = average stars of your last this-many jobs
C.RideTip = 0.5 -- clean test ride tips 50% of the repair pay
C.AirBonus = 5 -- $ per jump on the test ride

-- Saving. Studio playtests use their own store so they never touch live saves.
-- Changing SaveStore wipes everyone (they start fresh on the new store).
C.SaveStore = "ScooterSave_v1"
C.StudioSaveStore = "ScooterSave_Studio_v1"
C.AutosaveEvery = 60 -- seconds

-- Studio test mode (Studio playtests only; live servers ignore it): you own every
-- machine from the start with full stock, and after your own scooter the customers
-- bring one fix each, in this order, so every minigame comes up in one playtest.
-- Set StudioTestAll = false to test the real progression in Studio.
C.StudioTestAll = true
C.StudioTour = { "Mud", "Worn", "Light", "Rust", "Nitro", "Charge", "Bolts", "Battery", "Paint" }

---------------------------------------------------------------- upgrade system v5 (plan/02 + 04)
-- Every machine: 4 tiers, 10 upgrades (the owner's 1 / 3 / 4 / 2 pattern). Upgrades 1, 4 and 8 are tier-ups
-- (new look, big jump); the rest are boosts. A boost counts 1 unit of progress and a tier-up 2, 13 in all, so a
-- stat after upgrade n = start + (max - start) x Units[n] / 13. Price of upgrade n = Base x 1.5^(n-1), tier-ups
-- x1.8, rounded (to 10 under 1,000, to 100 above). Buy = what a machine you start without costs.
-- Stats = { start, max } (Int = whole numbers). Main = { stat, label, format } for the shop's "now > next" line. Everything maxed costs about $594,000 (plan/04).
C.TierUps = { [1] = true, [4] = true, [8] = true }
C.Units = { 2, 3, 4, 6, 7, 8, 9, 11, 12, 13 }
C.Upgrades = {
	Bench = { Base = 350, Tiers = { "Workbench", "Steel Bench", "Lift Bench", "Pro Station" },
		Stats = { Pay = { 1, 1.6 }, BinCap = { 4, 24, Int = true } }, Main = { "Pay", "Pay", "x%.2f" } },
	Pump = { Base = 78, Tiers = { "Hand Pump", "Big Pump", "Turbo Pump", "Air Cannon" },
		Stats = { Air = { 10, 34 }, Stroke = { 0.24, 0.16 } }, Main = { "Air", "Air per pump", "%.0f%%" } },
	Wrench = { Base = 122, Tiers = { "Wrench", "Ratchet", "Impact Gun", "Torque Station" },
		Stats = { Zone = { 1, 2 }, Speed = { 1, 0.7 } }, Main = { "Zone", "Green zone", "x%.1f" } },
	BatteryDock = { Base = 150, Tiers = { "Battery Rack", "Charge Station", "Glass Cabinet", "Power Wall" },
		Stats = { Capacity = { 6, 36, Int = true }, Rate = { 0.05, 0.14 }, Spark = { 0.2, 0.45 } }, Main = { "Capacity", "Holds", "%d" } },
	Belt = { Base = 300, Tiers = { "Conveyor", "Lit Conveyor", "Tunnel Conveyor", "Twin Conveyor" },
		-- the belt has 4 slots; Queue goes to 6 once the T4 second lane is modelled
		Stats = { Queue = { 2, 4, Int = true }, Gap = { 1, 0.55 } }, Main = { "Queue", "Waiting", "%d" } },
	Garage = { Base = 900, Tiers = { "Small Garage", "Big Garage", "Mega Garage", "Grand Garage" },
		Stats = { Appeal = { 1, 1.8 } }, Main = { "Appeal", "Customers", "x%.2f" } },
	TyreRack = { Base = 150, Buy = 120, Tiers = { "Tyre Rack", "Big Tyre Rack", "Tall Tyre Rack", "Tyre Carousel" },
		Stats = { Capacity = { 4, 20, Int = true }, Spin = { 1, 0.6 } }, Main = { "Capacity", "Holds", "%d" } },
	WireKit = { Base = 220, Buy = 300, Tiers = { "Wire Kit", "Pro Wire Kit", "Diagnostic Screen", "Diagnostic Cart" },
		Stats = { Capacity = { 4, 16, Int = true }, Reach = { 1, 1.8 } }, Main = { "Capacity", "Holds", "%d" } },
	Bucket = { Base = 300, Buy = 550, Tiers = { "Sponge Bucket", "Bucket Trolley", "Foam Station", "Dip Tank" },
		Stats = { Scrub = { 1, 2.2 } }, Main = { "Scrub", "Scrub", "x%.1f" } },
	NitroKit = { Base = 780, Buy = 1500, Tiers = { "Nitro Kit", "Bottle Rack", "Cryo Cabinet", "Tank Cart" },
		Stats = { Zone = { 0.14, 0.28 }, Fill = { 0.5, 0.35 } }, Main = { "Zone", "Green zone", "%.2f" } },
	WashBay = { Base = 500, Buy = 700, Tiers = { "Wash Bay", "Power Washer", "Turbo Washer", "Brush Arch" },
		Stats = { Jet = { 1, 2.2 } }, Main = { "Jet", "Jet", "x%.1f" } },
	PaintBooth = { Base = 650, Buy = 900, Tiers = { "Paint Booth", "Fan Booth", "Turbo Dryer", "Infrared Tunnel" },
		Stats = { Spray = { 1, 2 }, Dry = { 12, 3 }, Capacity = { 4, 12, Int = true } }, Main = { "Dry", "Dries in", "%.0fs" } },
}

-- level = the saved attribute (0 = not owned, 1 = T1 with no upgrades, 11 = all 10)
function C.upgradesOf(level)
	return math.clamp((level or 0) - 1, 0, 10)
end
function C.tierOf(level)
	local n = C.upgradesOf(level)
	return n >= 8 and 4 or n >= 4 and 3 or n >= 1 and 2 or 1
end
function C.stat(id, level, name)
	local u = C.Upgrades[id]
	local s = u and u.Stats[name]
	if not s then return nil end
	local n = C.upgradesOf(level)
	local v = s[1] + (s[2] - s[1]) * (n == 0 and 0 or C.Units[n]) / 13
	return s.Int and math.floor(v + 0.5) or v
end
-- A Gate = { Id, Tier } or { Id, Level }: what you need before you can buy it. get(id) -> that item's level.
function C.gateOpen(item, get)
	local g = item and item.Gate
	if not g then return true end
	local level = get(g.Id) or 0
	if g.Level then return level >= g.Level end
	return level > 0 and C.tierOf(level) >= (g.Tier or 1)
end

local function roundPrice(x)
	return x >= 1000 and math.floor(x / 100 + 0.5) * 100 or math.floor(x / 10 + 0.5) * 10
end
for _, item in C.Shop do
	local u = C.Upgrades[item.Id]
	if not u then continue end
	item.Ups = 10
	item.Prices = { u.Buy or 0 }
	for n = 1, 10 do
		table.insert(item.Prices, roundPrice(u.Base * 1.5 ^ (n - 1) * (C.TierUps[n] and 1.8 or 1)))
	end
	item.Names, item.Tiers = {}, u.Tiers
	for level = 1, 11 do item.Names[level] = u.Tiers[C.tierOf(level)] end
	for name in u.Stats do
		item[name] = {}
		for level = 1, 11 do item[name][level] = C.stat(item.Id, level, name) end
	end
	item.Main = u.Main
	-- the look's colour follows the tier
	if item.Look and item.Look.Colors then
		local byTier = item.Look.Colors
		item.Look.TierColors = byTier
		item.Look.Colors = {}
		for level = 1, 11 do item.Look.Colors[level] = byTier[C.tierOf(level)] or false end
	end
end
-- the bench's T4 is the trash chute: the bin never fills
for _, item in C.Shop do
	if item.Id == "Bench" then
		for level = 1, 11 do
			if C.tierOf(level) == 4 then item.BinCap[level] = math.huge end
		end
	elseif item.Id == "Pump" then
		C.PumpAir, C.PumpStroke = item.Air, item.Stroke
	end
end

-- Old saves (V1) had levels 1-4 = tiers. Upgrade number for each old level: 1 -> 0, 2 -> 1, 3 -> 4, 4 -> 8
-- (as levels: 1, 2, 5, 9). The old Charger and Bin are refunded once (what they cost then).
C.SaveVersion = 2
C.OldLevel = { 1, 2, 5, 9 }
C.OldRefund = { Charger = { 0, 200, 650 }, Bin = { 0, 120, 400, 1500 } }

return C
