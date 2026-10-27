-- One clock for the whole server: day and night are shared by every garage.
-- workspace attributes: Phase ("Day" / "Night"), PhaseEndsAt (server time), DayNumber.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.ScooterConfig)

local M = { phase = "Day", number = 1, endsAt = 0 }
local handlers = {}

-- fn(phaseName) runs at every change (and once when the clock starts)
function M.onPhase(fn)
	table.insert(handlers, fn)
end

local function set(name, length)
	M.phase = name
	M.endsAt = os.clock() + length
	workspace:SetAttribute("Phase", name)
	workspace:SetAttribute("DayNumber", M.number)
	workspace:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + length)
	for _, fn in handlers do
		local ok, err = pcall(fn, name)
		if not ok then warn("[Clock] handler failed:", err) end
	end
end

function M.start()
	set("Day", Config.DaySeconds)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if os.clock() >= M.endsAt then
				if M.phase == "Day" then
					set("Night", Config.NightSeconds)
				else
					M.number += 1
					set("Day", Config.DaySeconds)
				end
			end
		end
	end)
end

return M
