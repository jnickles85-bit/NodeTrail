local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

-- Next-waypoint chooser and the pure geometry the arrow needs.
--
-- Everything here is plain arithmetic on a flat plane in YARDS (x = east,
-- y = north). No WoW calls, so the same functions run under lua5.1 in the
-- specs — which is the only way "the chooser advances along a loop and never
-- points backwards" can be a fact instead of a claim.
--
-- Why a waypoint chooser at all: a world-anchored line on a player-centred
-- minimap slides under the player and cannot be followed. What RXP/Zygor give
-- the player is the NEXT point plus the distance to it, so the countdown is
-- the feedback loop and the direction is a single bearing.

ns.Nav = ns.Nav or {}
local N = ns.Nav
N.Target = N.Target or N.Target or {}
local T = N.Target

--- How close (yards) the player must be to a waypoint before the arrow moves
--- on to the following one. Zygor flips around 10-15yd; a node is lootable
--- from about 5yd, so 12yd flips early enough to be useful and late enough
--- that walking past a point does not skip the leg after it.
T.ARRIVE_YARDS = 12

local function finite(v)
  return type(v) == "number" and v == v and v > -1e300 and v < 1e300
end

function T.Dist2(ax, ay, bx, by)
  if not (finite(ax) and finite(ay) and finite(bx) and finite(by)) then
    return nil
  end
  local dx, dy = bx - ax, by - ay
  return dx * dx + dy * dy
end

function T.Dist(ax, ay, bx, by)
  local d2 = T.Dist2(ax, ay, bx, by)
  if not d2 then
    return nil
  end
  return math.sqrt(d2)
end

--- Project P onto the segment A->B.
--- @return t (0..1), qx, qy, d2 — the clamped parameter, the projected point
---         and the squared distance from P to it.
function T.Project(px, py, ax, ay, bx, by)
  if not (finite(px) and finite(py) and finite(ax) and finite(ay) and finite(bx) and finite(by)) then
    return nil
  end
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  if len2 <= 1e-12 then
    local qx, qy = ax, ay
    local d2 = (px - qx) * (px - qx) + (py - qy) * (py - qy)
    return 0, qx, qy, d2
  end
  local t = ((px - ax) * dx + (py - ay) * dy) / len2
  if t < 0 then
    t = 0
  elseif t > 1 then
    t = 1
  end
  local qx, qy = ax + dx * t, ay + dy * t
  local d2 = (px - qx) * (px - qx) + (py - qy) * (py - qy)
  return t, qx, qy, d2
end

--- The next waypoint for a player at (px, py) on a route given as points in
--- yards ({ {x=, y=}, ... }).
---
--- Rules, in the order they matter:
---   1. FORWARD ONLY. The search starts at the point the caller was last
---      heading for, so the result can never name an earlier point than a
---      previous call did: the arrow cannot turn around and point back along
---      the route, which is worse than pointing at nothing.
---   2. Every point already inside `radius` is stepped over first, so standing
---      on a node does not leave the arrow aimed at your own feet.
---   3. The target is the FAR endpoint of the nearest forward segment — the
---      segment the player is actually standing on, not whichever point
---      happens to be nearest on the other side of a hairpin.
---   4. `complete` is true only when the player is inside `radius` of the last
---      point, so "arrived at the end of the route" is never inferred from an
---      index.
---
--- @param points array of { x, y } in yards
--- @param px, py player position in the same space
--- @param opts { prev = last target index, radius = arrival yards }
--- @return table { index, dist, dx, dy, east, north, segment, along, advanced,
---                 complete, radius } or nil, reason
function T.Next(points, px, py, opts)
  opts = opts or {}
  local n = type(points) == "table" and #points or 0
  if n < 1 then
    return nil, "the route has no points"
  end
  if not (finite(px) and finite(py)) then
    return nil, "the player has no position"
  end
  local radius = tonumber(opts.radius) or T.ARRIVE_YARDS
  if not finite(radius) or radius <= 0 then
    radius = T.ARRIVE_YARDS
  end
  local radius2 = radius * radius

  local prev = math.floor((tonumber(opts.prev) or 1) + 0.5)
  if prev < 1 then
    prev = 1
  end
  if prev > n then
    prev = n
  end

  local function reached(index)
    local p = points[index]
    if type(p) ~= "table" then
      return false
    end
    local d2 = T.Dist2(px, py, p.x, p.y)
    return d2 ~= nil and d2 <= radius2
  end

  -- (1)+(2) step over the points already reached, from `prev` on.
  local advanced = 0
  local k = prev
  while k < n and reached(k) do
    k = k + 1
    advanced = advanced + 1
  end

  -- (3) the nearest FORWARD segment, never one behind `prev`.
  local segFrom = k - 1
  if segFrom < 1 then
    segFrom = 1
  end
  local bestI, bestD2
  for i = segFrom, n - 1 do
    local a, b = points[i], points[i + 1]
    if type(a) == "table" and type(b) == "table" then
      local _, _, _, d2 = T.Project(px, py, a.x, a.y, b.x, b.y)
      if d2 and (bestD2 == nil or d2 < bestD2 - 1e-9) then
        bestI, bestD2 = i, d2
      end
    end
  end
  if bestI then
    local a, b = points[bestI], points[bestI + 1]
    local t = T.Project(px, py, a.x, a.y, b.x, b.y)
    local want = bestI + 1
    -- Standing SHORT of the leg the player is heading for (or off the start of
    -- the route entirely): the next point to walk to is that leg's near end, not
    -- its far end — otherwise the first target of a route is already the second
    -- waypoint. Guarded by `bestI >= k`, so this can never step back past the
    -- point the arrow was already aiming at.
    if bestI >= k and type(t) == "number" and t <= 1e-6 then
      want = bestI
    end
    if want > k then
      advanced = advanced + (want - k)
      k = want
    end
  end

  -- The segment search can land on a point the player already stands on (a
  -- route that doubles back on itself); step over those too, but never past
  -- the last point.
  while k < n and reached(k) do
    k = k + 1
    advanced = advanced + 1
  end

  local target = points[k]
  local dx = (type(target) == "table" and finite(target.x)) and (target.x - px) or nil
  local dy = (type(target) == "table" and finite(target.y)) and (target.y - py) or nil
  local dist = (dx and dy) and math.sqrt(dx * dx + dy * dy) or nil
  local last = points[n]
  local complete = false
  if k >= n and type(last) == "table" then
    local d2 = T.Dist2(px, py, last.x, last.y)
    complete = d2 ~= nil and d2 <= radius2
  end
  return {
    index = k,
    dist = dist,
    dx = dx,
    dy = dy,          -- x = east, y = north (the plane this function expects)
    east = dx,
    north = dy,
    segment = bestI,
    along = bestI and T.Project(px, py, points[bestI].x, points[bestI].y,
      points[bestI + 1].x, points[bestI + 1].y) or nil,
    advanced = advanced,
    complete = complete,
    radius = radius,
    count = n,
  }
end

local function norm(angle)
  local twoPi = math.pi * 2
  angle = angle % twoPi
  if angle < 0 then
    angle = angle + twoPi
  end
  return angle
end
T.NormAngle = norm

--- Compass bearing of a vector: 0 = north, +pi/2 = east, increasing clockwise.
--- This is the same quantity HereBeDragons:GetWorldVector() returns (RXPGuides
--- passes it straight into SetRotation after subtracting the player's facing).
--- @param east yards east of the player
--- @param north yards north of the player
function T.Bearing(east, north)
  if not (finite(east) and finite(north)) then
    return nil
  end
  return norm(math.atan2(east, north))
end

--- Screen angle of the marker, measured the way a texture rotation is measured:
--- 0 = straight up (north), +pi/2 = right (east), increasing clockwise.
--- With `rotateMinimap` on, the client turns the minimap by the player's facing,
--- so the same bearing that is up on a north-up map is `-facing` further round.
--- This is exactly the transform HereBeDragons-Pins and this addon's minimap
--- line already apply on this client (xDist*cos - yDist*sin / xDist*sin +
--- yDist*cos); the specs pin it.
--- @param bearing compass bearing (T.Bearing)
--- @param facing GetPlayerFacing() value, or nil when the minimap is north-up
function T.ScreenAngle(bearing, facing)
  if not finite(bearing) then
    return nil
  end
  if not finite(facing) then
    return norm(bearing)
  end
  return norm(bearing - facing)
end

--- Bearing -> the words a player can read at a glance. Used by the label when
--- the distance alone is ambiguous (a waypoint behind you reads as "behind").
local COMPASS = {
  [0] = "N", [1] = "NE", [2] = "E", [3] = "SE",
  [4] = "S", [5] = "SW", [6] = "W", [7] = "NW",
}

function T.CompassWord(bearing)
  if not finite(bearing) then
    return nil
  end
  local sector = math.floor(norm(bearing) / (math.pi / 4) + 0.5) % 8
  return COMPASS[sector]
end

--- "123 yd" — the number Zygor counts down. Below 10 yards the count still
--- reads as whole yards (`%d`), never "0 yd": the chooser advances before
--- that, so a zero here would mean the chooser is broken.
function T.YardText(yards)
  local n = tonumber(yards)
  if not finite(n) then
    return "? yd"
  end
  if n < 0 then
    n = 0
  end
  return string.format("%d yd", math.floor(n + 0.5))
end

--- Keep a screen offset inside the minimap ring. Returns the clamped point and
--- whether it had to be clamped, in the same "pixels from centre, +y up" space
--- the minimap painters use.
function T.RingClamp(px, py, ringRadius)
  if not (finite(px) and finite(py) and finite(ringRadius)) or ringRadius <= 0 then
    return nil
  end
  local d = math.sqrt(px * px + py * py)
  if d <= ringRadius then
    return px, py, false
  end
  if d <= 1e-9 then
    return 0, ringRadius, true
  end
  local k = ringRadius / d
  return px * k, py * k, true
end
