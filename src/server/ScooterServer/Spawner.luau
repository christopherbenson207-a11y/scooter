-- Which garage does the next customer choose? By its stars: the better the rating, the more
-- customers, but a low-rated garage still gets some.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.ScooterConfig)

local M = {}

-- weight = (0.35 + rating / 5) ^ 2; no reviews yet counts as Config.UnratedAs stars.
-- A Marketer and a player's first day make customers more likely to pick the garage.
function M.weight(rating, reviews, firstDay, marketer)
	local r = (reviews or 0) > 0 and (rating or 0) or Config.UnratedAs
	local w = (0.35 + r / 5) ^ 2
	if marketer then w *= Config.MarketerBoost end
	if firstDay then w *= Config.NewGarageBoost end
	return w
end

-- candidates: { { weight = n, ... } }. Returns one of them (nil when there are none).
function M.pick(candidates, roll)
	local total = 0
	for _, c in candidates do total += c.weight end
	if total <= 0 then return nil end
	local x = (roll or math.random()) * total
	for _, c in candidates do
		x -= c.weight
		if x <= 0 then return c end
	end
	return candidates[#candidates]
end

return M
