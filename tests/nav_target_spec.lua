-- t_d17939c1 — a world-anchored line on a player-centred minimap can never be
-- followed: the map scrolls under the player and the line slides. What makes
-- RXPGuides/Zygor followable is a NEXT-waypoint arrow with the distance
-- counting down, so the two things that have to be provably right are:
--
--   A. the chooser: on a 17-point loop it advances point by point, in order,
--      and NEVER names a point behind the one it named last;
--   B. the angle: the marker's screen angle is `bearing - facing` for the
--      rotation the client applies, and plain `bearing` on a north-up map.
--
-- Both are pure arithmetic, so both are checked here rather than asserted in a
-- handoff. Not loaded by the addon TOC.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "check") .. "\n")
  end
end

local function near(a, b, msg, tol)
  tol = tol or 1e-6
  check(type(a) == "number" and type(b) == "number" and math.abs(a - b) < tol,
    (msg or "near") .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

local pkg = {}
local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/Nav/Target.lua")
if not chunk then
  io.stderr:write("FAIL: Nav/Target.lua did not load: " .. tostring(err) .. "\n")
  os.exit(1)
end
chunk("MightiePack", pkg)
local T = pkg.NodeTrail and pkg.NodeTrail.Nav and pkg.NodeTrail.Nav.Target
if type(T) ~= "table" then
  io.stderr:write("FAIL: the addon exposes no NodeTrail.Nav.Target\n")
  os.exit(1)
end

-- ═══ A. a synthetic 17-point loop ═══════════════════════════════════════════
-- 16 distinct points around a 200yd circle plus the closing copy of point 1,
-- which is exactly how Route/Build closes a route (path[#path] = path[1] with
-- close = true). Walking the loop clockwise must walk the targets 2..17 in
-- order, never backwards.
local N = 16
local R = 200
local loop = {}
for i = 1, N do
  local a = (i - 1) / N * math.pi * 2
  loop[i] = { x = R * math.sin(a), y = R * math.cos(a) }
end
loop[#loop + 1] = { x = loop[1].x, y = loop[1].y }
check(#loop == 17, "A: the synthetic loop has 17 points (got " .. #loop .. ")")

-- Walk the player a little behind each vertex, then onto it.
local prev
local seen = {}
local backwards = 0
local offBy = 0
for step = 1, 16 do
  local from, to = loop[step], loop[step + 1]
  for k = 0, 4 do
    local t = k / 4
    local px = from.x + (to.x - from.x) * t
    local py = from.y + (to.y - from.y) * t
    local sel = T.Next(loop, px, py, { prev = prev, radius = 12 })
    check(type(sel) == "table", "A: the chooser answers for step " .. step)
    if type(sel) == "table" then
      -- Never backwards: the index may hold still or advance, never retreat.
      if prev and sel.index < prev then
        backwards = backwards + 1
        io.stderr:write(("  step %d t=%.2f: index %d after %d\n"):format(step, t, sel.index, prev))
      end
      prev = sel.index
      seen[sel.index] = true
      -- The named point must be the far end of the leg being walked (or the
      -- next one once this leg's end is inside the arrival radius).
      if sel.index ~= step + 1 and not (t > 0.9 and sel.index == step + 2) then
        offBy = offBy + 1
        io.stderr:write(("  step %d t=%.2f: named point %d, expected %d\n")
          :format(step, t, sel.index, step + 1))
      end
      -- And the arrow must not point backwards along the route: the angle
      -- between the player->target vector and the local travel direction has
      -- to stay acute.
      local travelX, travelY = to.x - from.x, to.y - from.y
      local tl = math.sqrt(travelX * travelX + travelY * travelY)
      local dl = sel.dist or 0
      if dl > 1e-6 then
        local dot = (sel.east * travelX + sel.north * travelY) / (dl * tl)
        if dot < 0.0 then
          backwards = backwards + 1
          io.stderr:write(("  step %d t=%.2f: the target is behind the travel direction (dot %.2f)\n")
            :format(step, t, dot))
        end
      end
    end
  end
end
check(backwards == 0, "A: the chooser never points backwards on the loop (" .. backwards .. " violations)")
check(offBy == 0, "A: every step names the far end of the leg it is walking (" .. offBy .. " wrong)")
for i = 2, 17 do
  check(seen[i] == true, "A: the walk reached point #" .. i)
end

-- Arriving at the last point completes the route, and only then.
local last = loop[17]
local atEnd = T.Next(loop, last.x, last.y, { prev = 16, radius = 12 })
check(type(atEnd) == "table" and atEnd.complete == true,
  "A: standing on the closing point completes the loop")
local almost = T.Next(loop, last.x + 40, last.y, { prev = 16, radius = 12 })
check(type(almost) == "table" and almost.complete == false,
  "A: 40yd short of the closing point is not complete")

-- Monotonicity also holds when the player is dragged BACK along the route: the
-- chooser keeps the forward target instead of turning round.
local back = T.Next(loop, loop[9].x, loop[9].y, { prev = 10, radius = 12 })
check(type(back) == "table" and back.index >= 10,
  "A: walking back over a waypoint keeps the arrow forward (named #" ..
    tostring(back and back.index) .. " after #10)")

-- ═══ B. the angle ═══════════════════════════════════════════════════════════
-- Compass bearing: north = 0, east = pi/2, clockwise.
near(T.Bearing(0, 10), 0, "B: due north is bearing 0")
near(T.Bearing(10, 0), math.pi / 2, "B: due east is bearing pi/2")
near(T.Bearing(0, -10), math.pi, "B: due south is bearing pi")
near(T.Bearing(-10, 0), math.pi * 1.5, "B: due west is bearing 3pi/2")

-- The card's formula: the arrow's angle is atan2(dy, dx) - facing. For a known
-- input — target 30yd east, 40yd north (a 3-4-5 triangle), facing 0.5rad —
-- both the atan2 form and the chooser's bearing must give the same rotation.
local east, north = 30, 40
local bearing = T.Bearing(east, north)
near(bearing, math.atan2(east, north), "B: bearing is atan2(east, north)")
near(T.ScreenAngle(bearing, 0.5), bearing - 0.5,
  "B: on a turned minimap the marker's angle is bearing - facing")
near(T.ScreenAngle(bearing, nil), bearing,
  "B: on a north-up minimap the marker's angle is the bearing itself")
near(T.ScreenAngle(0.1, 0.3), math.pi * 2 + 0.1 - 0.3,
  "B: the angle is normalised into [0, 2pi)")
-- A bearing that would go negative wraps instead of pointing off the texture.
local wrapped = T.ScreenAngle(0.2, 1.0)
check(wrapped > math.pi, "B: a negative rotation wraps into [0,2pi) (got " .. tostring(wrapped) .. ")")

-- The marker itself: 3-4-5 to the north-east must project up and to the right.
near(T.Dist(0, 0, 30, 40), 50, "B: the 3-4-5 target is 50yd away")

local px, py, clamped = T.RingClamp(30, 40, 100)
check(clamped == false, "B: a target inside the ring is not clamped")
near(px, 30, "B: an unclamped x is kept")
near(py, 40, "B: an unclamped y is kept")

local cx, cy, wasClamped = T.RingClamp(300, 400, 100)
check(wasClamped == true, "B: a target outside the ring is clamped to it")
near(math.sqrt(cx * cx + cy * cy), 100, "B: the clamped point sits exactly on the ring", 1e-6)
near(cx / cy, 300 / 400, "B: clamping keeps the bearing", 1e-6)

-- The distance Zygor prints, and never a "0 yd" while a waypoint is pending.
check(T.YardText(123.4) == "123 yd", "B: the label is the whole-yard countdown")
check(T.YardText(0.4) == "0 yd", "B: a sub-yard number rounds to 0 yd")
check(T.YardText(nil) == "? yd", "B: an unusable distance reads as ? yd, not as a number")
check(T.CompassWord(0) == "N", "B: the compass word for north")
check(T.CompassWord(math.pi / 2) == "E", "B: the compass word for east")
check(T.CompassWord(math.pi) == "S", "B: the compass word for south")
check(T.CompassWord(math.pi * 1.5) == "W", "B: the compass word for west")

-- ═══ degenerate inputs do not raise ══════════════════════════════════════════
local nilSel, why = T.Next(nil, 0, 0, {})
check(nilSel == nil and type(why) == "string", "edge: no points is nil, with a reason")
local one = { { x = 10, y = 0 } }
local oneSel = T.Next(one, 0, 0, {})
check(type(oneSel) == "table" and oneSel.index == 1 and oneSel.dist == 10,
  "edge: a single-point route names that point")
local dup = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 100, y = 0 } }
local dupSel = T.Next(dup, 0, 0, { prev = 1, radius = 12 })
check(type(dupSel) == "table" and dupSel.index == 3,
  "edge: a zero-length leg is stepped over, not divided by (named #" ..
    tostring(dupSel and dupSel.index) .. ")")
local nanSel = T.Next(loop, 0 / 0, 0, {})
check(nanSel == nil, "edge: a NaN player position names nothing")

if failed > 0 then
  io.stderr:write(failed .. " check(s) failed\n")
  os.exit(1)
end
print("nav_target_spec: ok")
