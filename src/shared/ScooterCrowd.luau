-- The customers' walk, shared by the server (how long it takes) and every client (drawing it):
-- bus stop on the town road -> town-road pavement -> round the ring's outer pavement -> the
-- top of the chosen plot's side path. Everything is in world space; the plaza is the origin
-- of the angle phi (phi 0 points along -Z; plot 0 sits at phi 180 since the 24 Oct flip, plot k is plot 0
-- turned 60 * k degrees).
local M = {}

local CENTER = Vector3.new(-4, 0, -133)
local RING_R = 82.9 -- customers keep to the outer edge of the pavement, clear of the lamps
local TOWN_PHI = 330
local TOWN_LATERAL = 11 -- the right-hand pavement of the town road
local STEP = 7 -- degrees between waypoints round the ring

local function dir(phi)
	local a = math.rad(phi)
	return Vector3.new(-math.sin(a), 0, -math.cos(a))
end
local function phiOf(p)
	local v = p - CENTER
	return math.deg(math.atan2(-v.X, -v.Z)) % 360
end
M.dir, M.phiOf, M.CENTER = dir, phiOf, CENTER

function M.busSpawn()
	local stop = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("BusStop")
	local marker = stop and stop:FindFirstChild("CustomerSpawn")
	if marker then return Vector3.new(marker.Position.X, 0.6, marker.Position.Z) end
	local d = dir(TOWN_PHI)
	local lat = Vector3.new(d.Z, 0, -d.X)
	local p = CENTER + d * 156 + lat * TOWN_LATERAL
	return Vector3.new(p.X, 0.6, p.Z)
end

-- How far a customer walks to a garage: they step off the bus out of sight and only walk this last stretch,
-- so a new customer is at the hatch within a few seconds instead of half a minute.
M.WalkIn = 55

-- Waypoints from the bus stop to `arrive` (a world position at the top of a side path).
-- short = only the last M.WalkIn studs of it.
function M.route(arrive, short)
	local d = dir(TOWN_PHI)
	local lat = Vector3.new(d.Z, 0, -d.X)
	local pts = { M.busSpawn() }
	local gate = CENTER + d * 88 + lat * TOWN_LATERAL -- where the town pavement meets the ring pavement
	table.insert(pts, Vector3.new(gate.X, 0.6, gate.Z))
	local from = phiOf(gate)
	local to = phiOf(arrive)
	local diff = (to - from + 540) % 360 - 180 -- the shorter way round
	local steps = math.max(1, math.ceil(math.abs(diff) / STEP))
	for i = 0, steps do
		local p = CENTER + dir(from + diff * i / steps) * RING_R
		table.insert(pts, Vector3.new(p.X, 0.6, p.Z))
	end
	table.insert(pts, Vector3.new(arrive.X, 0.6, arrive.Z))
	if not short then return pts end
	local skip = M.length(pts) - M.WalkIn
	if skip <= 0 then return pts end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local seg = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
		if skip <= seg then
			local tail = { a:Lerp(b, skip / math.max(seg, 0.001)) }
			for j = i, #pts do table.insert(tail, pts[j]) end
			return tail
		end
		skip -= seg
	end
	return pts
end

function M.length(pts)
	local n = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		n += Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
	end
	return n
end

return M
