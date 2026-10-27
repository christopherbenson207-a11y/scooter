-- Every sound in one place (owner, 24 Oct: "get all needed sounds", "simple ui press sounds").
-- Roblox's own UI pack, Pro Sound Effects and APM music. Requiring this module also wires the
-- sounds nobody has to call: a click on every button, a page swipe when a big panel opens, a till
-- when cash goes up, the shop bell when day turns to night, and the background music.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local S = {}

S.Id = {
	Click = "rbxassetid://15675032796", -- Roblox_UI_Small_Click
	Bright = "rbxassetid://15675059323", -- Roblox_UI_Bright_Click
	Pop = "rbxassetid://15675055424", -- Roblox_UI_Cute_Pop
	Swipe = "rbxassetid://15675037413", -- Roblox_UI_Paper_Swipe
	Miss = "rbxassetid://15675075163", -- Roblox_UI_Delete
	Till = "rbxassetid://121518193382221", -- cash register ka-ching
	Bell = "rbxassetid://9125935023", -- PSE shop door bell
	Ratchet = "rbxassetid://9118046636", -- PSE ratchet wrench, slow, 0.8 s
	Pump = "rbxassetid://9125791580", -- PSE pump clunk + air burst, 1 s
	Water = "rbxassetid://9126200774", -- PSE hose spray, 8 s (looped)
	Rattle = "rbxassetid://9119524652", -- PSE spray can rattle
	DayMusic = "rbxassetid://1839578771", -- APM "Charming View Ukulele"
	NightMusic = "rbxassetid://1839453894", -- APM "So Kind"
}

local function group(name, volume)
	local g = SoundService:FindFirstChild(name) or Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	return g
end
S.Sfx = group("Sfx", 1)
S.Music = group("Music", 0.35)

local lastClick = 0

-- one-shot; returns the Sound so loops can be stopped
function S.play(name, volume, pitch, parent)
	local s = Instance.new("Sound")
	s.SoundId = S.Id[name] or name
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.SoundGroup = S.Sfx
	s.Parent = parent or SoundService
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(10, function() if s.Parent and not s.Looped then s:Destroy() end end)
	return s
end

-- true just after a button click, so the game's own tap on the same press doesn't double up
function S.justClicked()
	return os.clock() - lastClick < 0.08
end

local player = Players.LocalPlayer
local pgui = player:WaitForChild("PlayerGui")

-- a click on every button press, anywhere in the player's UI (screens, boards, billboards)
local hooked = setmetatable({}, { __mode = "k" })
local function hook(b)
	if hooked[b] or not b:IsA("GuiButton") then return end
	hooked[b] = true
	b.Activated:Connect(function()
		if os.clock() - lastClick < 0.05 then return end
		lastClick = os.clock()
		S.play("Click", 0.7, 0.95 + math.random() * 0.1)
	end)
end
for _, d in pgui:GetDescendants() do hook(d) end
pgui.DescendantAdded:Connect(hook)

-- a page swipe when one of the big panels opens
local PANELS = { Shop = true, Store = true, PayPanel = true, JobCard = true, Restock = true }
local function watchPanels(screen)
	for name in PANELS do
		local f = screen:FindFirstChild(name)
		if f and f:IsA("GuiObject") then
			f:GetPropertyChangedSignal("Visible"):Connect(function()
				if f.Visible then S.play("Swipe", 0.45) end
			end)
		end
	end
end
task.spawn(function()
	watchPanels(pgui:WaitForChild("FixUI"))
end)

-- till when cash goes up (job pay, tips, cash packs)
task.spawn(function()
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	local last, lastTill = cash.Value, 0
	cash.Changed:Connect(function(v)
		if v > last and os.clock() - lastTill > 0.6 then
			lastTill = os.clock()
			S.play("Till", 0.55)
		end
		last = v
	end)
end)

-- music: day tune and night tune, crossfaded; the shop bell rings when the phase flips
local tracks = {}
for _, key in { "DayMusic", "NightMusic" } do
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = S.Id[key]
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = S.Music
	s.Parent = SoundService
	tracks[key] = s
end
local TweenService = game:GetService("TweenService")
local function music()
	local want = workspace:GetAttribute("Phase") == "Night" and "NightMusic" or "DayMusic"
	for key, s in tracks do
		local on = key == want
		if on and not s.IsPlaying then s:Play() end
		local tw = TweenService:Create(s, TweenInfo.new(2), { Volume = on and 0.5 or 0 })
		tw:Play()
		if not on then tw.Completed:Once(function() if s.Volume == 0 then s:Pause() end end) end
	end
end
music()
local phase = workspace:GetAttribute("Phase")
workspace:GetAttributeChangedSignal("Phase"):Connect(function()
	local now = workspace:GetAttribute("Phase")
	if now ~= phase then
		phase = now
		S.play("Bell", 0.6)
		music()
	end
end)

return S
