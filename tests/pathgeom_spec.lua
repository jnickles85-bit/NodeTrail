local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local ns = {}
local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/UI/PathGeom.lua")
assert(chunk, err)
chunk("MightiePack", { NodeTrail = ns })
local G = ns.PathGeom

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local function near(a, b, msg)
  check(type(a) == "number" and math.abs(a - b) < 1e-4, msg .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

do
  local x1, y1, x2, y2 = G.ClipCircle(-1, 0, 1, 0, 5)
  near(x1, -1, "inside x1")
  near(y1, 0, "inside y1")
  near(x2, 1, "inside x2")
  near(y2, 0, "inside y2")
end

do
  local x1, y1, x2, y2 = G.ClipCircle(-10, 0, 10, 0, 5)
  near(x1, -5, "span x1")
  near(y1, 0, "span y1")
  near(x2, 5, "span x2")
  near(y2, 0, "span y2")
end

do
  local x1 = G.ClipCircle(10, 0, 12, 0, 5)
  check(x1 == nil, "segment outside circle")
end

do
  local x1 = G.ClipCircle(10, 10, 12, 12, 5)
  check(x1 == nil, "miss circle")
end

do
  local x1, y1, x2, y2 = G.ClipCircle(0, 0, 10, 0, 5)
  near(x1, 0, "one-in x1")
  near(y1, 0, "one-in y1")
  near(x2, 5, "one-in x2")
  near(y2, 0, "one-in y2")
end

do
  local s = 5 / math.sqrt(2)
  local x1, y1, x2, y2 = G.ClipCircle(-10, -10, 10, 10, 5)
  near(x1, -s, "diag x1")
  near(y1, -s, "diag y1")
  near(x2, s, "diag x2")
  near(y2, s, "diag y2")
end

do
  check(G.ClipCircle(0, 0, 1, 0, 0) == nil, "zero radius")
  check(G.ClipCircle(0, 0, 1, 0, nil) == nil, "nil radius")
end

do
  local x1, y1, x2, y2 = G.ClipRect(-10, 0, 10, 0, -5, -5, 5, 5)
  near(x1, -5, "rect x1")
  near(y1, 0, "rect y1")
  near(x2, 5, "rect x2")
  near(y2, 0, "rect y2")
end

do
  local x1, y1, x2, y2 = G.ClipRect(0, 0, 10, 0, -5, -5, 5, 5)
  near(x1, 0, "rect partial x1")
  near(x2, 5, "rect partial x2")
  near(y1, 0, "rect partial y1")
  near(y2, 0, "rect partial y2")
end

do
  local x1, y1, x2, y2 = G.ClipRect(-10, -10, 10, 10, -5, -5, 5, 5)
  near(x1, -5, "rect diag x1")
  near(y1, -5, "rect diag y1")
  near(x2, 5, "rect diag x2")
  near(y2, 5, "rect diag y2")
end

do
  check(G.ClipRect(-10, -10, -8, -8, -5, -5, 5, 5) == nil, "rect outside")
end

do
  check(G.IsMapPoint({ x = 0.2, y = 0.3 }), "valid point")
  check(not G.IsMapPoint({ x = 0.2 }), "missing y")
  check(not G.IsMapPoint({ x = 0 / 0, y = 0.2 }), "nan x")
  check(not G.IsMapPoint(nil), "nil point")
end

-- Decor containment: every kept item sits inside the clip region.
do
  check(G.InCircle(0, 0, 0, 0, 5), "origin is inside a radius-5 circle")
  check(G.InCircle(3, 4, 0, 0, 5), "a point on the circle is inside")
  check(not G.InCircle(3, 4.1, 0, 0, 5), "a point just outside is rejected")
  check(not G.InCircle(nil, 0, 0, 0, 5), "a missing coordinate is outside")
  check(G.InRect(1, 1, 0, 0, 10, 10), "a point inside a y-down rect")
  check(G.InRect(0, 5, -10, 10, 10, -10), "min/max swap still contains the point")
  check(not G.InRect(11, 1, 0, 0, 10, 10), "a point past the right edge is outside")
  check(G.InsideClip(0, 0, nil), "a missing clip admits a usable point")
  check(not G.InsideClip(nil, 0, nil), "a missing clip still rejects a bad point")
  check(G.InsideClip(0, 0, { shape = "circle", x = 0, y = 0, r = 5 }), "circle clip admits the origin")
  check(not G.InsideClip(20, 0, { shape = "circle", x = 0, y = 0, r = 5 }), "circle clip rejects a far point")

  local items = {
    { kind = "start", x = 0, y = 0 },
    { kind = "chevron", x = 2, y = 0 },
    { kind = "chevron", x = 20, y = 0 },
    { kind = "end", x = 40, y = 0 },
  }
  local clip = { shape = "circle", x = 0, y = 0, r = 5 }
  local kept, kn = G.ClipItems(items, #items, clip)
  check(kn == 2, "7: only the items inside the circle are kept (got " .. tostring(kn) .. ")")
  for i = 1, kn do
    check(G.InsideClip(kept[i].x, kept[i].y, clip),
      "7: kept decor item " .. i .. " is inside the circle")
  end
  check(kept[1].kind == "start" and kept[2].kind == "chevron" and kept[2].x == 2,
    "7: the in-circle start and chevron stay, in order")

  -- A chevron whose centre is just outside the circle is kept when the
  -- arm pad intersects the clip, and dropped when the clip must contain
  -- the whole extent (the world-map window).
  local edge = { { kind = "chevron", x = 6, y = 0, dx = 1, dy = 0 } }
  local intersect = { shape = "circle", x = 0, y = 0, r = 5, pad = 2 }
  local _, en = G.ClipItems(edge, 1, intersect)
  check(en == 1, "7: an intersecting chevron arm is kept when pad reaches the circle (got " .. tostring(en) .. ")")
  local contain = { shape = "circle", x = 0, y = 0, r = 5, pad = 2, contain = true }
  _, en = G.ClipItems(edge, 1, contain)
  check(en == 0, "7: the same chevron is dropped when the clip must contain the arm (got " .. tostring(en) .. ")")
  check(G.InsideClip(4, 0, { shape = "rect", left = 0, top = 10, right = 10, bottom = -10, pad = 2, contain = true }),
    "7: a contained point still sits inside an inverted yup rect after the pad shrinks it")
  check(not G.InsideClip(1, 0, { shape = "rect", left = 0, top = 10, right = 10, bottom = -10, pad = 2, contain = true }),
    "7: a centre near the edge is outside once the contain pad shrinks an inverted rect")
  -- A pad larger than half the rect must not invert the edges (InRect's
  -- min/max would expand the rect). The mid-point of a 10-wide box with
  -- pad 20 is not "inside".
  check(not G.InsideClip(5, 5, { shape = "rect", left = 0, top = 0, right = 10, bottom = 10, pad = 20, contain = true }),
    "7: a contain pad larger than half the rect is empty, not inverted")
  -- ROUND minimap inset (r = half * 0.96). A chevron centre inside the
  -- disk whose arm pad crosses the circle must be dropped.
  local roundR = 100 * 0.96
  local armPad = 6
  local roundClip = { shape = "circle", x = 0, y = 0, r = roundR, pad = armPad, contain = true }
  check(G.InsideClip(0, 0, roundClip), "7: a centre well inside the ROUND inset is kept")
  check(G.InsideClip(roundR - armPad - 1, 0, roundClip),
    "7: a centre whose pad still sits inside the ROUND inset is kept")
  local edge = { { kind = "chevron", x = roundR - 2, y = 0, dx = 1, dy = 0 } }
  check(G.InsideClip(edge[1].x, edge[1].y, { shape = "circle", x = 0, y = 0, r = roundR }),
    "7: sanity: the chevron centre itself is inside the ROUND inset")
  local _, dropped = G.ClipItems(edge, 1, roundClip)
  check(dropped == 0,
    "7: a chevron whose centre is inside the ROUND inset but whose pad crosses the circle is dropped (got "
      .. tostring(dropped) .. ")")

  local rect = { shape = "rect", left = -1, top = -1, right = 3, bottom = 1 }
  kept, kn = G.ClipItems(items, #items, rect)
  check(kn == 2, "7: a rect clip also drops the far chevron and the end (got " .. tostring(kn) .. ")")
  for i = 1, kn do
    check(G.InsideClip(kept[i].x, kept[i].y, rect),
      "7: kept decor item " .. i .. " is inside the rect")
  end

  -- Per-kind pads: a start marker may sit closer to the contain edge than
  -- a chevron, because its painted square is smaller than a chevron arm.
  local r = 100
  local chevPad, markPad = 8, 3
  local clipKinds = {
    shape = "circle", x = 0, y = 0, r = r, contain = true,
    padFor = function(it)
      if it.kind == "start" or it.kind == "end" or it.kind == "loop" then
        return markPad
      end
      return chevPad
    end,
  }
  local nearEdge = r - 5 -- inside for pad 3, outside for pad 8
  local mixed = {
    { kind = "start", x = nearEdge, y = 0 },
    { kind = "chevron", x = nearEdge, y = 0, dx = 1, dy = 0 },
  }
  kept, kn = G.ClipItems(mixed, 2, clipKinds)
  check(kn == 1 and kept[1].kind == "start",
    "7: a start marker inside its own pad is kept when a chevron at the same point is dropped (got kn="
      .. tostring(kn) .. ", kind=" .. tostring(kept[1] and kept[1].kind) .. ")")
  check(G.InsideClip(nearEdge, 0, { shape = "circle", x = 0, y = 0, r = r, pad = markPad, contain = true }),
    "7: sanity: the marker pad still sits inside the circle")
  check(not G.InsideClip(nearEdge, 0, { shape = "circle", x = 0, y = 0, r = r, pad = chevPad, contain = true }),
    "7: sanity: the chevron pad crosses the circle")
end

if failed > 0 then
  io.stderr:write(failed .. " geometry check(s) failed\n")
  os.exit(1)
end
print("pathgeom_spec: ok")
